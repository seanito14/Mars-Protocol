#!/usr/bin/env python3
"""Local ElevenLabs + wake-word companion for Mars Protocol.

Endpoints:
- GET /health
- GET /signed-url
- POST /wake/start
- POST /wake/stop
- POST /command   (legacy demo fallback path)

Wake-word behavior:
- Uses local/offline keyword spotting when optional dependencies are installed.
- Emits UDP events to Godot on localhost.
- Keeps ElevenLabs API keys on the Python side only.
"""

from __future__ import annotations

import base64
import json
import os
import queue
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


HOST = os.environ.get("HERO_VOICE_HOST", "127.0.0.1")
PORT = int(os.environ.get("HERO_VOICE_PORT", "8765"))
API_KEY = os.environ.get("ELEVENLABS_API_KEY", "")
AGENT_ID = os.environ.get("ELEVENLABS_AGENT_ID", "")
VOICE_ID = os.environ.get("ELEVENLABS_VOICE_ID", "EXAVITQu4vr4xnSDxMaL")
MODEL_ID = os.environ.get("ELEVENLABS_MODEL_ID", "eleven_multilingual_v2")
SECRET_IMPORT_READY = os.environ.get("MARS_PROTOCOL_SECRET_IMPORT_READY", "0") == "1"
RUNTIME_ENV_READY = os.environ.get("MARS_PROTOCOL_RUNTIME_ENV_READY", "0") == "1"
DEPENDENCY_INSTALL_READY = os.environ.get("MARS_PROTOCOL_DEPENDENCY_INSTALL_READY", "0") == "1"
SETUP_ERROR = os.environ.get("MARS_PROTOCOL_SETUP_ERROR", "")

WAKE_ENABLED = os.environ.get("SUDO_AI_WAKE_ENABLED", "1") != "0"
WAKE_UDP_HOST = os.environ.get("SUDO_AI_WAKE_HOST", "127.0.0.1")
WAKE_UDP_PORT = int(os.environ.get("SUDO_AI_WAKE_PORT", "4245"))
WAKE_MODEL_PATH = os.environ.get("SUDO_AI_WAKE_MODEL_PATH", "")
WAKE_SAMPLE_RATE = int(os.environ.get("SUDO_AI_WAKE_SAMPLE_RATE", "16000"))
WAKE_BLOCK_SIZE = int(os.environ.get("SUDO_AI_WAKE_BLOCK_SIZE", "4000"))
WAKE_COOLDOWN_SECONDS = float(os.environ.get("SUDO_AI_WAKE_COOLDOWN", "2.2"))

try:
    import sounddevice as sd
except Exception:
    sd = None

try:
    from vosk import KaldiRecognizer, Model
except Exception:
    KaldiRecognizer = None
    Model = None


def elevenlabs_signed_url() -> str:
    if not API_KEY or not AGENT_ID:
        return ""
    query = urllib.parse.urlencode({"agent_id": AGENT_ID})
    request = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/convai/conversation/get-signed-url?{query}",
        headers={"xi-api-key": API_KEY},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return payload.get("signed_url", "")


def elevenlabs_tts(text: str) -> bytes:
    if not API_KEY or not text.strip():
        return b""
    body = json.dumps(
        {
            "text": text,
            "model_id": MODEL_ID,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}",
        data=body,
        headers={
            "xi-api-key": API_KEY,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


class WakeDetector:
    def __init__(self) -> None:
        self.enabled = WAKE_ENABLED
        self.running = False
        self.last_error = ""
        self.thread: threading.Thread | None = None
        self.stop_event = threading.Event()
        self.queue: queue.Queue[bytes] = queue.Queue()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.last_detection_at = 0.0

    @property
    def supported(self) -> bool:
        return self.enabled and sd is not None and Model is not None and self._resolved_model_path() is not None

    def _resolved_model_path(self) -> Path | None:
        if not WAKE_MODEL_PATH:
            return None
        path = Path(WAKE_MODEL_PATH).expanduser()
        return path if path.exists() and path.is_dir() else None

    def status_payload(self) -> dict:
        reason = self.last_error
        if not self.enabled:
            reason = "wake_disabled"
        elif sd is None or Model is None:
            reason = "missing_python_dependencies"
        elif self._resolved_model_path() is None:
            reason = "missing_vosk_model"
        return {
            "wake_supported": self.supported,
            "wake_listening": self.running,
            "wake_reason": reason,
            "wake_udp_host": WAKE_UDP_HOST,
            "wake_udp_port": WAKE_UDP_PORT,
        }

    def start(self) -> dict:
        if not self.supported:
            payload = self.status_payload()
            self._emit_udp({"type": "mic_blocked", "reason": payload["wake_reason"]})
            return payload
        if self.running:
            return self.status_payload()
        self.stop_event.clear()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()
        self.running = True
        self.last_error = ""
        self._emit_udp({"type": "wake_ready"})
        return self.status_payload()

    def stop(self) -> dict:
        if self.running:
            self.stop_event.set()
            self.running = False
        return self.status_payload()

    def _emit_udp(self, payload: dict) -> None:
        data = json.dumps(payload).encode("utf-8")
        try:
            self.sock.sendto(data, (WAKE_UDP_HOST, WAKE_UDP_PORT))
        except OSError as exc:
            self.last_error = f"udp_send_failed:{exc}"

    def _audio_callback(self, indata, frames, time_info, status) -> None:  # noqa: ANN001
        _ = frames, time_info
        if status:
            self.last_error = str(status)
        if self.stop_event.is_set():
            return
        self.queue.put(bytes(indata))

    def _run(self) -> None:
        assert sd is not None
        assert Model is not None
        model_path = self._resolved_model_path()
        if model_path is None:
            self.last_error = "missing_vosk_model"
            self.running = False
            self._emit_udp({"type": "wake_error", "message": self.last_error})
            return

        try:
            recognizer = KaldiRecognizer(Model(str(model_path)), WAKE_SAMPLE_RATE, '["sudo"]')
            with sd.RawInputStream(
                samplerate=WAKE_SAMPLE_RATE,
                blocksize=WAKE_BLOCK_SIZE,
                dtype="int16",
                channels=1,
                callback=self._audio_callback,
            ):
                while not self.stop_event.is_set():
                    try:
                        audio_bytes = self.queue.get(timeout=0.2)
                    except queue.Empty:
                        continue
                    if recognizer.AcceptWaveform(audio_bytes):
                        result = json.loads(recognizer.Result())
                        text = str(result.get("text", "")).strip().lower()
                        if text == "sudo":
                            now = time.monotonic()
                            if now - self.last_detection_at >= WAKE_COOLDOWN_SECONDS:
                                self.last_detection_at = now
                                self._emit_udp({"type": "wake_detected", "word": "sudo"})
                    else:
                        partial = json.loads(recognizer.PartialResult()).get("partial", "")
                        if str(partial).strip().lower() == "sudo":
                            now = time.monotonic()
                            if now - self.last_detection_at >= WAKE_COOLDOWN_SECONDS:
                                self.last_detection_at = now
                                self._emit_udp({"type": "wake_detected", "word": "sudo"})
        except Exception as exc:  # noqa: BLE001
            self.last_error = str(exc)
            self._emit_udp({"type": "wake_error", "message": self.last_error})
        finally:
            self.running = False


WAKE_DETECTOR = WakeDetector()


class Handler(BaseHTTPRequestHandler):
    server_version = "MarsProtocolVoiceBridge/0.2"

    def do_GET(self) -> None:
        if self.path == "/health":
            wake_payload = WAKE_DETECTOR.status_payload()
            self._send_json(
                {
                    "ok": True,
                    "tts_enabled": bool(API_KEY),
                    "agent_enabled": bool(API_KEY and AGENT_ID),
                    "voice_id": VOICE_ID,
                    "secret_import_ready": SECRET_IMPORT_READY,
                    "runtime_env_ready": RUNTIME_ENV_READY,
                    "dependency_install_ready": DEPENDENCY_INSTALL_READY,
                    "setup_error": SETUP_ERROR,
                    **wake_payload,
                }
            )
            return

        if self.path == "/signed-url":
            try:
                signed_url = elevenlabs_signed_url()
            except urllib.error.URLError as exc:
                self._send_json({"signed_url": "", "error": str(exc)}, status=502)
                return
            self._send_json({"signed_url": signed_url, "enabled": bool(signed_url)})
            return

        self._send_json({"error": "Not found"}, status=404)

    def do_POST(self) -> None:
        if self.path == "/wake/start":
            self._send_json(WAKE_DETECTOR.start())
            return

        if self.path == "/wake/stop":
            self._send_json(WAKE_DETECTOR.stop())
            return

        if self.path != "/command":
            self._send_json({"error": "Not found"}, status=404)
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send_json({"error": "Invalid JSON payload"}, status=400)
            return

        response_text = str(payload.get("assistant_text", "")).strip()
        audio_bytes = b""
        used_tts = False
        error = ""
        if response_text and API_KEY:
            try:
                audio_bytes = elevenlabs_tts(response_text)
                used_tts = bool(audio_bytes)
            except urllib.error.URLError as exc:
                error = str(exc)

        self._send_json(
            {
                "command_id": str(payload.get("command_id", "")),
                "response_text": response_text,
                "used_tts": used_tts,
                "audio_base64": base64.b64encode(audio_bytes).decode("ascii") if audio_bytes else "",
                "error": error,
            }
        )

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        sys.stdout.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), format % args))

    def _send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Voice companion listening on http://{HOST}:{PORT}")
    print(f"Wake UDP target: {WAKE_UDP_HOST}:{WAKE_UDP_PORT}")
    print(
        "Setup status: "
        f"secret_import_ready={SECRET_IMPORT_READY} "
        f"runtime_env_ready={RUNTIME_ENV_READY} "
        f"dependency_install_ready={DEPENDENCY_INSTALL_READY} "
        f"setup_error={SETUP_ERROR or 'none'}"
    )
    if not API_KEY or not AGENT_ID:
        print("ElevenLabs credentials not configured; signed URLs will be unavailable.")
    if not WAKE_DETECTOR.supported:
        print(f"Wake detector inactive: {WAKE_DETECTOR.status_payload()['wake_reason']}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()

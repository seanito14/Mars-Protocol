#!/usr/bin/env python3
"""Small local bridge for the Mars Protocol hero demo.

Endpoints:
- GET /health
- GET /signed-url
- POST /command

The game uses /command to synthesize Marvin's spoken response when
ELEVENLABS_API_KEY is configured. Without credentials, the endpoint still
returns the assistant text so the demo remains playable offline.
"""

from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HOST = os.environ.get("HERO_VOICE_HOST", "127.0.0.1")
PORT = int(os.environ.get("HERO_VOICE_PORT", "8765"))
API_KEY = os.environ.get("ELEVENLABS_API_KEY", "")
AGENT_ID = os.environ.get("ELEVENLABS_AGENT_ID", "")
VOICE_ID = os.environ.get("ELEVENLABS_VOICE_ID", "EXAVITQu4vr4xnSDxMaL")
MODEL_ID = os.environ.get("ELEVENLABS_MODEL_ID", "eleven_multilingual_v2")


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


class Handler(BaseHTTPRequestHandler):
    server_version = "MarsProtocolBridge/0.1"

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send_json(
                {
                    "ok": True,
                    "tts_enabled": bool(API_KEY),
                    "agent_enabled": bool(API_KEY and AGENT_ID),
                    "voice_id": VOICE_ID,
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

    def log_message(self, format: str, *args) -> None:
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
    print(f"Hero voice bridge listening on http://{HOST}:{PORT}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Secure launcher for the local SudoAI voice companion.

This wrapper performs three setup tasks before it hands off to the actual
bridge server:
1. Import and normalize ElevenLabs secrets from a one-time Desktop RTF source.
2. Create and maintain a private Python runtime for optional voice deps.
3. Exec the real bridge with secrets and redacted setup status in the env.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


APP_NAME = "Mars Protocol"
ALLOWED_SECRET_KEYS = (
    "ELEVENLABS_API_KEY",
    "ELEVENLABS_AGENT_ID",
    "ELEVENLABS_VOICE_ID",
    "ELEVENLABS_MODEL_ID",
    "SUDO_AI_WAKE_MODEL_PATH",
)
REQUIRED_SECRET_KEYS = ("ELEVENLABS_API_KEY", "ELEVENLABS_AGENT_ID")
STATUS_ENV_KEYS = {
    "secret_import_ready": "MARS_PROTOCOL_SECRET_IMPORT_READY",
    "runtime_env_ready": "MARS_PROTOCOL_RUNTIME_ENV_READY",
    "dependency_install_ready": "MARS_PROTOCOL_DEPENDENCY_INSTALL_READY",
    "setup_error": "MARS_PROTOCOL_SETUP_ERROR",
}
SECRET_IMPORT_SOURCE_ENV = "MARS_PROTOCOL_SECRET_IMPORT_SOURCE"
APP_SUPPORT_DIR_ENV = "MARS_PROTOCOL_APP_SUPPORT_DIR"
RUNTIME_PYTHON_ENV = "MARS_PROTOCOL_RUNTIME_PYTHON"


class SetupStatus:
    def __init__(self) -> None:
        self.secret_import_ready = False
        self.runtime_env_ready = False
        self.dependency_install_ready = False
        self.setup_error = ""

    def set_error(self, code: str) -> None:
        if not self.setup_error:
            self.setup_error = code

    def as_env(self) -> dict[str, str]:
        return {
            STATUS_ENV_KEYS["secret_import_ready"]: "1" if self.secret_import_ready else "0",
            STATUS_ENV_KEYS["runtime_env_ready"]: "1" if self.runtime_env_ready else "0",
            STATUS_ENV_KEYS["dependency_install_ready"]: "1" if self.dependency_install_ready else "0",
            STATUS_ENV_KEYS["setup_error"]: self.setup_error,
        }


def default_app_support_dir() -> Path:
    override = os.environ.get(APP_SUPPORT_DIR_ENV, "").strip()
    if override:
        return Path(override).expanduser()
    home = Path.home()
    if sys.platform == "darwin":
        return home / "Library" / "Application Support" / APP_NAME
    xdg_data_home = os.environ.get("XDG_DATA_HOME", "").strip()
    if xdg_data_home:
        return Path(xdg_data_home).expanduser() / APP_NAME
    return home / ".local" / "share" / APP_NAME


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def secure_mkdir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass
    return path


def select_runtime_python() -> Path | None:
    override = os.environ.get(RUNTIME_PYTHON_ENV, "").strip()
    candidates: list[str] = []
    if override:
        candidates.append(override)
    candidates.extend(["python3.12", "python3.11", "python3.10", "python3.9", sys.executable, "python3"])

    seen: set[str] = set()
    for candidate in candidates:
        resolved = shutil.which(candidate) if candidate and not os.path.isabs(candidate) else candidate
        if not resolved:
            continue
        resolved = str(Path(resolved).expanduser())
        if resolved in seen:
            continue
        seen.add(resolved)
        return Path(resolved)
    return None


def parse_env_text(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key not in ALLOWED_SECRET_KEYS:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        values[key] = value
    return values


def strip_rtf_to_text(raw_text: str) -> str:
    text_parts: list[str] = []
    stack: list[bool] = []
    skip_destination = False
    uc_skip = 1
    pending_unicode_skip = 0
    i = 0
    length = len(raw_text)

    while i < length:
        char = raw_text[i]
        if pending_unicode_skip > 0:
            pending_unicode_skip -= 1
            i += 1
            continue
        if char == "{":
            stack.append(skip_destination)
            i += 1
            continue
        if char == "}":
            if stack:
                skip_destination = stack.pop()
            else:
                skip_destination = False
            i += 1
            continue
        if char != "\\":
            if not skip_destination:
                text_parts.append(char)
            i += 1
            continue

        i += 1
        if i >= length:
            break
        token = raw_text[i]
        if token in "{}\\":
            if not skip_destination:
                text_parts.append(token)
            i += 1
            continue
        if token == "'":
            hex_value = raw_text[i + 1 : i + 3]
            if len(hex_value) == 2 and not skip_destination:
                try:
                    text_parts.append(bytes.fromhex(hex_value).decode("cp1252"))
                except ValueError:
                    pass
            i += 3
            continue
        if token == "*":
            skip_destination = True
            i += 1
            continue

        start = i
        while i < length and raw_text[i].isalpha():
            i += 1
        word = raw_text[start:i]
        sign = 1
        if i < length and raw_text[i] == "-":
            sign = -1
            i += 1
        param_start = i
        while i < length and raw_text[i].isdigit():
            i += 1
        param = raw_text[param_start:i]
        if i < length and raw_text[i] == " ":
            i += 1

        if word == "par" and not skip_destination:
            text_parts.append("\n")
        elif word == "tab" and not skip_destination:
            text_parts.append("\t")
        elif word == "line" and not skip_destination:
            text_parts.append("\n")
        elif word == "uc" and param:
            uc_skip = max(int(param) * sign, 0)
        elif word == "u" and param and not skip_destination:
            codepoint = int(param) * sign
            if codepoint < 0:
                codepoint += 65536
            text_parts.append(chr(codepoint))
            pending_unicode_skip = uc_skip

    return "".join(text_parts)


def extract_secret_text(source_path: Path) -> str:
    if not source_path.exists():
        return ""
    if source_path.suffix.lower() == ".rtf":
        textutil = shutil.which("textutil")
        if textutil:
            try:
                result = subprocess.run(
                    [textutil, "-convert", "txt", "-stdout", str(source_path)],
                    check=False,
                    capture_output=True,
                    text=True,
                )
            except OSError:
                result = None
            if result and result.returncode == 0 and result.stdout.strip():
                return result.stdout
        raw_bytes = source_path.read_bytes()
        decoded = raw_bytes.decode("cp1252", errors="ignore")
        return strip_rtf_to_text(decoded)

    raw_bytes = source_path.read_bytes()
    decoded = raw_bytes.decode("utf-8", errors="ignore")
    if decoded.strip():
        return decoded
    return raw_bytes.decode("cp1252", errors="ignore")


def validate_secret_values(values: dict[str, str]) -> bool:
    for key in REQUIRED_SECRET_KEYS:
        if not values.get(key, "").strip():
            return False
    return True


def load_secret_file(secret_file: Path) -> dict[str, str]:
    if not secret_file.exists():
        return {}
    return parse_env_text(secret_file.read_text(encoding="utf-8"))


def write_secret_file(secret_file: Path, values: dict[str, str]) -> None:
    secure_mkdir(secret_file.parent)
    payload_lines = [f"{key}={values[key]}" for key in ALLOWED_SECRET_KEYS if values.get(key, "")]
    payload = "\n".join(payload_lines) + "\n"
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=str(secret_file.parent),
        prefix=".sudo_ai",
        delete=False,
    ) as handle:
        handle.write(payload)
        temp_path = Path(handle.name)
    try:
        os.chmod(temp_path, 0o600)
    except OSError:
        pass
    os.replace(temp_path, secret_file)
    try:
        os.chmod(secret_file, 0o600)
    except OSError:
        pass


def resolve_secret_values(status: SetupStatus, app_support_dir: Path) -> dict[str, str]:
    secret_file = app_support_dir / "secrets" / "sudo_ai.env"
    secret_values = load_secret_file(secret_file)
    if validate_secret_values(secret_values):
        status.secret_import_ready = True
        return secret_values

    source_override = os.environ.get(SECRET_IMPORT_SOURCE_ENV, "").strip()
    source_path = Path(source_override).expanduser() if source_override else Path("/Users/z/Desktop/sudoaiapi.rtf")
    if not source_path.exists():
        status.set_error("secret_source_missing")
        return {}

    extracted_text = extract_secret_text(source_path)
    imported_values = parse_env_text(extracted_text)
    if not validate_secret_values(imported_values):
        status.set_error("secret_import_invalid")
        return {}

    try:
        write_secret_file(secret_file, imported_values)
        source_path.unlink()
    except OSError:
        status.set_error("secret_persist_failed")
        return {}

    status.secret_import_ready = True
    return imported_values


def venv_python_path(venv_dir: Path) -> Path:
    if os.name == "nt":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def ensure_runtime_env(status: SetupStatus, app_support_dir: Path) -> Path:
    runtime_dir = secure_mkdir(app_support_dir / "runtime")
    venv_dir = runtime_dir / "voice-companion-venv"
    interpreter = venv_python_path(venv_dir)
    if interpreter.exists():
        status.runtime_env_ready = True
        return interpreter

    bootstrap_python = select_runtime_python()
    if bootstrap_python is None:
        status.set_error("runtime_env_missing_python")
        return Path(sys.executable)

    try:
        result = subprocess.run(
            [str(bootstrap_python), "-m", "venv", str(venv_dir)],
            check=False,
            capture_output=True,
            text=True,
        )
    except Exception:
        status.set_error("runtime_env_create_failed")
        return Path(sys.executable)
    if result.returncode != 0:
        status.set_error("runtime_env_create_failed")
        return Path(sys.executable)

    if interpreter.exists():
        status.runtime_env_ready = True
        return interpreter

    status.set_error("runtime_env_missing_python")
    return Path(sys.executable)


def install_dependencies(status: SetupStatus, python_executable: Path, app_support_dir: Path) -> None:
    requirements_path = repo_root() / "tools" / "voice_requirements.txt"
    if not requirements_path.exists():
        status.set_error("dependency_manifest_missing")
        return

    runtime_dir = secure_mkdir(app_support_dir / "runtime")
    stamp_path = runtime_dir / "voice_requirements.sha256"
    digest = hashlib.sha256(requirements_path.read_bytes()).hexdigest()
    if stamp_path.exists() and stamp_path.read_text(encoding="utf-8").strip() == digest:
        status.dependency_install_ready = True
        return

    try:
        result = subprocess.run(
            [
                str(python_executable),
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--no-input",
                "-r",
                str(requirements_path),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        status.set_error("dependency_install_failed")
        return

    if result.returncode != 0:
        status.set_error("dependency_install_failed")
        return

    stamp_path.write_text(digest + "\n", encoding="utf-8")
    status.dependency_install_ready = True


def bridge_env(secret_values: dict[str, str], status: SetupStatus) -> dict[str, str]:
    env = dict(os.environ)
    for key in ALLOWED_SECRET_KEYS:
        env.pop(key, None)
    for key, value in secret_values.items():
        if key in ALLOWED_SECRET_KEYS and value:
            env[key] = value
    env.update(status.as_env())
    return env


def launch_bridge(secret_values: dict[str, str], status: SetupStatus, python_executable: Path) -> int:
    bridge_script = repo_root() / "tools" / "elevenlabs_demo_bridge.py"
    if not bridge_script.exists():
        print("SudoAI launcher error: bridge script missing.", file=sys.stderr)
        return 1
    env = bridge_env(secret_values, status)
    os.execve(str(python_executable), [str(python_executable), str(bridge_script)], env)
    return 1


def main() -> int:
    status = SetupStatus()
    app_support_dir = secure_mkdir(default_app_support_dir())
    secret_values = resolve_secret_values(status, app_support_dir)
    python_executable = ensure_runtime_env(status, app_support_dir)
    if status.runtime_env_ready:
        install_dependencies(status, python_executable, app_support_dir)
    return launch_bridge(secret_values, status, python_executable)


if __name__ == "__main__":
    raise SystemExit(main())

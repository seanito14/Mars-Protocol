#!/usr/bin/env python3
"""Prepare a bundled RevenueCat config for iOS builds.

This tool treats `/Users/z/Desktop/revenuecatapi.txt` as a one-time import
source for the RevenueCat Apple public SDK key. It normalizes the key into an
external App Support env file, keeps it out of the repo, and writes a compact
plist into the built app bundle for runtime consumption.

It never prints raw key values.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import stat
from pathlib import Path


DEFAULT_SOURCE = Path("/Users/z/Desktop/revenuecatapi.txt")
DEFAULT_ENV_PATH = Path("~/Library/Application Support/Mars Protocol/secrets/revenuecat.env").expanduser()
PUBLIC_KEY_PREFIX = "appl_"
SECRET_KEY_PREFIX = "sk_"


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def write_private_text(path: Path, content: str) -> None:
    ensure_parent(path)
    path.write_text(content, encoding="utf-8")
    try:
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
    except OSError:
        pass


def read_existing_public_key(path: Path) -> str:
    if not path.exists():
        return ""
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() == "REVENUECAT_IOS_PUBLIC_API_KEY":
            return value.strip()
    return ""


def read_source_token(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace").strip()


def classify_token(token: str) -> str:
    if not token:
        return "missing_public_api_key"
    if token.startswith(PUBLIC_KEY_PREFIX):
        return "public_key"
    if token.startswith(SECRET_KEY_PREFIX):
        return "secret_api_key_provided"
    return "invalid_public_api_key"


def import_public_key(source_path: Path, env_path: Path) -> tuple[str, str]:
    existing_key = read_existing_public_key(env_path)
    if existing_key.startswith(PUBLIC_KEY_PREFIX):
        return existing_key, ""

    source_token = read_source_token(source_path)
    classification = classify_token(source_token)
    if classification != "public_key":
        return "", classification

    write_private_text(env_path, "REVENUECAT_IOS_PUBLIC_API_KEY=%s\n" % source_token)
    try:
        source_path.unlink()
    except OSError:
        # Keep moving; the secure env file is already the canonical source.
        pass
    return source_token, ""


def build_payload(source_path: Path, env_path: Path) -> dict:
    public_key, setup_error = import_public_key(source_path, env_path)
    if not public_key:
        existing_key = read_existing_public_key(env_path)
        if existing_key.startswith(PUBLIC_KEY_PREFIX):
            public_key = existing_key
            setup_error = ""

    return {
        "public_api_key": public_key,
        "setup_error": setup_error,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=str(DEFAULT_SOURCE))
    parser.add_argument("--env-path", default=str(DEFAULT_ENV_PATH))
    parser.add_argument("--output-plist", required=True)
    args = parser.parse_args()

    source_path = Path(args.source).expanduser()
    env_path = Path(args.env_path).expanduser()
    output_path = Path(args.output_plist)

    payload = build_payload(source_path, env_path)
    ensure_parent(output_path)
    with output_path.open("wb") as handle:
        plistlib.dump(payload, handle)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

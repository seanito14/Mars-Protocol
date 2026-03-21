#!/usr/bin/env python3
"""Convert the reference opening clip into Godot's runtime video format.

The source-of-truth opening reference is the MP4 file captured from the target
visual reference. Godot 4.6 core playback supports Ogg Theora video, so this
helper performs a deterministic transcode into the shipped .ogv asset.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


DEFAULT_SOURCE = Path("/Users/z/Downloads/open.mp4")
DEFAULT_OUTPUT = Path("/Users/z/Desktop/ProjectMarsHighFidelity/assets/video/opening_scene.ogv")
FFMPEG4_PATH = Path("/opt/homebrew/opt/ffmpeg@4/bin/ffmpeg")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert the Project Mars opening reference clip into a Godot-playable .ogv asset."
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="Path to the reference .mp4 clip.")
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Destination path for the generated .ogv runtime asset.",
    )
    return parser


def ensure_transcoder_available() -> str:
    if FFMPEG4_PATH.exists():
        return str(FFMPEG4_PATH)
    if shutil.which("ffmpeg2theora") is not None:
        return "ffmpeg2theora"
    if shutil.which("ffmpeg") is not None:
        return "ffmpeg"
    raise SystemExit("Neither ffmpeg2theora nor ffmpeg was found in PATH.")

def ffmpeg_supports_theora(binary: str) -> bool:
    probe = subprocess.run(
        [binary, "-encoders"],
        check=False,
        capture_output=True,
        text=True,
    )
    return "theora" in probe.stdout


def convert_with_ffmpeg2theora(source: Path, output: Path) -> None:
    command = [
        "ffmpeg2theora",
        "--no-skeleton",
        "--videoquality",
        "7",
        "--audioquality",
        "5",
        "--width",
        "1920",
        "--height",
        "1080",
        "--aspect",
        "16:9",
        "--framerate",
        "30",
        "--output",
        str(output),
        str(source),
    ]
    subprocess.run(command, check=True)


def convert_with_ffmpeg(source: Path, output: Path, binary: str) -> None:
    if not ffmpeg_supports_theora(binary):
        raise SystemExit(
            "ffmpeg was found, but this build does not include Theora encoding support. "
            "Install ffmpeg2theora or an ffmpeg build with theora enabled."
        )
    command = [
        binary,
        "-y",
        "-i",
        str(source),
        "-vf",
        "fps=30,scale=1920:1080:flags=lanczos",
        "-c:v",
        "libtheora",
        "-q:v",
        "7",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "libvorbis",
        "-q:a",
        "5",
        str(output),
    ]
    subprocess.run(command, check=True)


def convert_video(source: Path, output: Path) -> None:
    if not source.exists():
        raise SystemExit(f"Source clip not found: {source}")

    output.parent.mkdir(parents=True, exist_ok=True)
    transcoder = ensure_transcoder_available()
    if transcoder == "ffmpeg2theora":
        convert_with_ffmpeg2theora(source, output)
        return
    convert_with_ffmpeg(source, output, transcoder)


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    convert_video(args.source.expanduser(), args.output.expanduser())
    print(f"Generated runtime intro asset: {args.output.expanduser()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

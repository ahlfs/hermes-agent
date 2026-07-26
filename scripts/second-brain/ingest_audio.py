#!/usr/bin/env python3
"""AI Second Brain — Pass 1: audio transcription.

Scans <vault>/01-Audio/ for .mp3/.wav/.m4a files, transcribes each with
faster-whisper, and writes a timestamped Markdown transcript to
<vault>/03-Notes/Transcripts/. Skips files that already have an up-to-date
transcript.

Run via the isolated venv:
    ~/.hermes/venv-second-brain/bin/python scripts/second-brain/ingest_audio.py

Env vars:
    OBSIDIAN_VAULT_DIR  path to the Obsidian vault (preferred)
    SECOND_BRAIN_VAULT  fallback vault path (default: ~/obsidian/memo)
    WHISPER_MODEL       faster-whisper model size (default: base)
    WHISPER_DEVICE      "cpu" | "cuda" | "auto" (default: auto)
"""
import datetime
import os
import sys
from pathlib import Path

# Allow running from any CWD — resolve _vault relative to this script.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _vault import resolve_vault

AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a"}

VAULT_ROOT = resolve_vault()
AUDIO_DIR = VAULT_ROOT / "01-Audio"
TRANSCRIPTS_DIR = VAULT_ROOT / "03-Notes" / "Transcripts"

WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "base")
WHISPER_DEVICE = os.environ.get("WHISPER_DEVICE", "auto")


def format_timestamp(seconds: float) -> str:
    total_seconds = int(seconds)
    hours, remainder = divmod(total_seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def transcript_path_for(audio_path: Path) -> Path:
    return TRANSCRIPTS_DIR / f"{audio_path.stem}.md"


def needs_processing(audio_path: Path) -> bool:
    out_path = transcript_path_for(audio_path)
    if not out_path.exists():
        return True
    # Re-transcribe if the source audio was modified after the transcript
    # was generated (e.g. the file was replaced under the same name).
    return audio_path.stat().st_mtime > out_path.stat().st_mtime


def find_audio_files() -> list[Path]:
    if not AUDIO_DIR.exists():
        return []
    return sorted(
        p
        for p in AUDIO_DIR.iterdir()
        if p.is_file() and p.suffix.lower() in AUDIO_EXTENSIONS
    )


def write_transcript(audio_path: Path, segments, model_name: str) -> None:
    lines = [
        f"# Transcript: {audio_path.name}",
        "",
        f"- Source: `01-Audio/{audio_path.name}`",
        f"- Generated: {datetime.datetime.now().isoformat(timespec='seconds')}",
        f"- Model: faster-whisper ({model_name})",
        "",
        "---",
        "",
    ]
    segment_count = 0
    for segment in segments:
        segment_count += 1
        ts = format_timestamp(segment.start)
        text = segment.text.strip()
        lines.append(f"**[{ts}]** {text}")
        lines.append("")

    if segment_count == 0:
        lines.append("_(no speech detected)_")
        lines.append("")

    TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = transcript_path_for(audio_path)
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"  -> wrote {out_path.relative_to(VAULT_ROOT)} ({segment_count} segments)")


def main() -> int:
    audio_files = find_audio_files()
    if not audio_files:
        print(f"No audio files found in {AUDIO_DIR.relative_to(VAULT_ROOT)}/ — nothing to do.")
        return 0

    pending = [p for p in audio_files if needs_processing(p)]
    if not pending:
        print(f"All {len(audio_files)} audio file(s) already have up-to-date transcripts.")
        return 0

    print(f"Found {len(pending)} audio file(s) to transcribe (of {len(audio_files)} total).")

    try:
        from faster_whisper import WhisperModel
    except ImportError:
        print(
            "faster-whisper is not installed. Install dependencies first:\n"
            "  pip install -r requirements-second-brain.txt\n"
            "or run setup-venv.sh to create an isolated venv.",
            file=sys.stderr,
        )
        return 1

    def load_model(device: str):
        compute_type = "int8" if device == "cpu" else "auto"
        print(f"Loading faster-whisper model '{WHISPER_MODEL}' (device={device})...")
        return WhisperModel(WHISPER_MODEL, device=device, compute_type=compute_type)

    try:
        model = load_model(WHISPER_DEVICE)
    except Exception as exc:  # noqa: BLE001 — surface any load failure (e.g. no network for model download)
        print(f"Failed to load Whisper model: {exc}", file=sys.stderr)
        return 1

    failures = 0
    fell_back_to_cpu = False
    for audio_path in pending:
        print(f"Transcribing {audio_path.name}...")
        try:
            segments, info = model.transcribe(str(audio_path))
            write_transcript(audio_path, segments, WHISPER_MODEL)
        except Exception as exc:  # noqa: BLE001 — one bad file shouldn't stop the batch
            # GPU selected ("auto"/"cuda") but the CUDA runtime libs (e.g.
            # libcublas) aren't installed on this machine — retry once on
            # CPU instead of failing every file for an environment reason.
            if not fell_back_to_cpu and WHISPER_DEVICE != "cpu" and "libcublas" in str(exc):
                print("  GPU inference unavailable (missing CUDA runtime libs) — falling back to CPU.")
                fell_back_to_cpu = True
                try:
                    model = load_model("cpu")
                    segments, info = model.transcribe(str(audio_path))
                    write_transcript(audio_path, segments, WHISPER_MODEL)
                    continue
                except Exception as retry_exc:  # noqa: BLE001
                    exc = retry_exc
            failures += 1
            print(f"  !! failed to transcribe {audio_path.name}: {exc}", file=sys.stderr)

    processed = len(pending) - failures
    print(f"Done: {processed} transcribed, {failures} failed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

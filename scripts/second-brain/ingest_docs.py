#!/usr/bin/env python3
"""AI Second Brain — Pass 2: document parsing.

Scans <vault>/02-Documents/ for PDFs and images, extracts text, and writes
Markdown notes to <vault>/03-Notes/Extracted-Docs/. Skips files that already
have an up-to-date extraction.

PDFs: text extraction via pypdf (works for text-based PDFs; scanned/
image-only PDFs will come out empty — that's a pypdf limitation, not a bug
here).

Images: OCR via pytesseract, only if the `tesseract` binary is installed on
this machine. Without it, image files are skipped with a clear message rather
than silently producing nothing.

Run via the isolated venv:
    ~/.hermes/venv-second-brain/bin/python scripts/second-brain/ingest_docs.py

Env vars:
    OBSIDIAN_VAULT_DIR  path to the Obsidian vault (preferred)
    SECOND_BRAIN_VAULT  fallback vault path (default: ~/obsidian/memo)
"""
import datetime
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _vault import resolve_vault

PDF_EXTENSIONS = {".pdf"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tiff", ".webp"}

VAULT_ROOT = resolve_vault()
DOCUMENTS_DIR = VAULT_ROOT / "02-Documents"
EXTRACTED_DIR = VAULT_ROOT / "03-Notes" / "Extracted-Docs"

TESSERACT_AVAILABLE = shutil.which("tesseract") is not None


def output_path_for(doc_path: Path) -> Path:
    return EXTRACTED_DIR / f"{doc_path.stem}.md"


def needs_processing(doc_path: Path) -> bool:
    out_path = output_path_for(doc_path)
    if not out_path.exists():
        return True
    return doc_path.stat().st_mtime > out_path.stat().st_mtime


def find_documents() -> list[Path]:
    if not DOCUMENTS_DIR.exists():
        return []
    exts = PDF_EXTENSIONS | IMAGE_EXTENSIONS
    return sorted(
        p for p in DOCUMENTS_DIR.iterdir() if p.is_file() and p.suffix.lower() in exts
    )


def write_note(doc_path: Path, body: str, extraction_method: str) -> None:
    lines = [
        f"# {doc_path.name}",
        "",
        f"- Source: `02-Documents/{doc_path.name}`",
        f"- Generated: {datetime.datetime.now().isoformat(timespec='seconds')}",
        f"- Extraction: {extraction_method}",
        "",
        "---",
        "",
        body.strip() or "_(no text extracted)_",
        "",
    ]
    EXTRACTED_DIR.mkdir(parents=True, exist_ok=True)
    out_path = output_path_for(doc_path)
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"  -> wrote {out_path.relative_to(VAULT_ROOT)}")


def extract_pdf(doc_path: Path) -> str:
    from pypdf import PdfReader

    reader = PdfReader(str(doc_path))
    pages = []
    for i, page in enumerate(reader.pages, start=1):
        text = (page.extract_text() or "").strip()
        if text:
            pages.append(f"## Page {i}\n\n{text}")
    return "\n\n".join(pages)


def extract_image(doc_path: Path) -> str:
    import pytesseract
    from PIL import Image

    with Image.open(doc_path) as img:
        return pytesseract.image_to_string(img)


def main() -> int:
    documents = find_documents()
    if not documents:
        print(f"No documents found in {DOCUMENTS_DIR.relative_to(VAULT_ROOT)}/ — nothing to do.")
        return 0

    pending = [p for p in documents if needs_processing(p)]
    if not pending:
        print(f"All {len(documents)} document(s) already have up-to-date extractions.")
        return 0

    print(f"Found {len(pending)} document(s) to process (of {len(documents)} total).")

    failures = 0
    skipped_images = 0
    for doc_path in pending:
        ext = doc_path.suffix.lower()
        print(f"Processing {doc_path.name}...")
        try:
            if ext in PDF_EXTENSIONS:
                text = extract_pdf(doc_path)
                write_note(doc_path, text, "pypdf text extraction")
            elif ext in IMAGE_EXTENSIONS:
                if not TESSERACT_AVAILABLE:
                    skipped_images += 1
                    print(
                        "  !! skipped: tesseract OCR is not installed on this machine.\n"
                        "     Install it with `sudo apt install tesseract-ocr` to enable "
                        "image ingestion, then re-run this script.",
                        file=sys.stderr,
                    )
                    continue
                text = extract_image(doc_path)
                write_note(doc_path, text, "pytesseract OCR")
        except Exception as exc:  # noqa: BLE001 — one bad file shouldn't stop the batch
            failures += 1
            print(f"  !! failed to process {doc_path.name}: {exc}", file=sys.stderr)

    processed = len(pending) - failures - skipped_images
    print(
        f"Done: {processed} processed, {failures} failed, "
        f"{skipped_images} image(s) skipped (no tesseract)."
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

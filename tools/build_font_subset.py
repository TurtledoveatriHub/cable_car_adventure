"""Build the runtime Chinese font subset.

The original Source Han Sans CN is ~10.6MB and dominated the WeChat PCK / first
load. The UI only needs GB2312 + characters used by runtime JSON / scenes, so a
subset keeps arbitrary Chinese nicknames working while cutting the PCK by ~8MB.

Usage:
    python tools/build_font_subset.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools" / "fonts" / "SourceHanSansCN-Regular.otf"
OUTPUT = ROOT / "assets" / "fonts" / "CableCarSans-Subset.otf"
CHAR_FILE = ROOT / "build" / "font_subset_chars.txt"
BASE_CHARS = ROOT / "build" / "font_chars.txt"

EXTRA = (
    "←→↑↓★☆×·♪♫⚙…—–“”‘’【】《》「」『』〈〉"
    "▸◂▶◀●○◆◇■□▲△▼▽✦✧✓✕"
)


def collect_chars() -> str:
    chars: set[str] = set(" " + "".join(chr(i) for i in range(32, 127)) + EXTRA)
    # GB2312 coverage for player names and older level text.
    if BASE_CHARS.exists():
        chars.update(BASE_CHARS.read_text(encoding="utf-8", errors="replace"))
    for pattern in ("*.gd", "*.tscn", "*.tres", "*.json"):
        for path in list((ROOT / "scripts").rglob(pattern)) + list((ROOT / "scenes").rglob(pattern)) + list((ROOT / "data").rglob(pattern)):
            try:
                chars.update(path.read_text(encoding="utf-8", errors="ignore"))
            except OSError:
                pass
    # Drop control chars except whitespace used by layout.
    chars = {ch for ch in chars if ch in "\n\t" or ord(ch) >= 32}
    return "".join(sorted(chars))


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"missing font: {SOURCE}")
    text = collect_chars()
    CHAR_FILE.parent.mkdir(parents=True, exist_ok=True)
    CHAR_FILE.write_text(text, encoding="utf-8")
    print(f"characters: {len(text)} -> {CHAR_FILE}")
    subprocess.check_call([
        sys.executable, "-m", "fontTools.subset", str(SOURCE),
        f"--text-file={CHAR_FILE}",
        f"--output-file={OUTPUT}",
        "--layout-features=*",
        "--no-hinting",
        "--desubroutinize",
    ])
    print(f"font: {SOURCE.stat().st_size:,} -> {OUTPUT.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()

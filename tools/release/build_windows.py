"""Builds the Windows release (M14c): exports the "Windows Desktop" preset and zips the exe with
the read-me into build/KingdomTiles_v<version>_Windows.zip.

Usage: python tools/release/build_windows.py [path to the Godot console exe]
"""
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\MyPC\Desktop\Godot_v4.5.1-stable_win64_console.exe"
EXE = ROOT / "build" / "windows" / "KingdomTiles.exe"
README = Path(__file__).with_name("Doc truoc.txt")


def version() -> str:
    match = re.search(r'^config/version="([^"]+)"', (ROOT / "project.godot").read_text(encoding="utf-8"), re.M)
    return match.group(1) if match else "0.0"


def main() -> None:
    EXE.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([GODOT, "--headless", "--path", str(ROOT), "--export-release", "Windows Desktop", str(EXE)],
                   check=True, timeout=900)
    folder = f"KingdomTiles_v{version()}"
    out = ROOT / "build" / f"{folder}_Windows.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(EXE, f"{folder}/KingdomTiles.exe")
        archive.write(README, f"{folder}/{README.name}")
    print(f"{out} ({out.stat().st_size // (1024 * 1024)} MB)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Static checks. internal/ lists forbidden hosts, so it is skipped. Fixtures are skipped too."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".build", "build", "Fixtures", ".git", "DerivedData", "internal"}
SOURCE_SUFFIXES = {".swift", ".plist", ".entitlements", ".yml", ".sh", ".xcconfig", ".pbxproj"}
FORBIDDEN = [
    "oauth/token",
    "oauth/usage",
    "api.anthropic.com",
    "api2.cursor.sh",
    "auth.openai.com",
    "platform.claude.com",
    "console.anthropic.com",
    "SQLITE_OPEN_READWRITE",
    "SQLITE_OPEN_CREATE",
    "sqlite3_exec",
    "SecItemAdd",
    "SecItemUpdate",
    "SecItemDelete",
]
# Collapse "a" + "b" (Swift) and adjacent "a""b" / 'a''b' (shell) so a split forbidden word still matches.
LITERAL_JOIN = re.compile(r'"\s*\+\s*"|""|\'\'')


def source_files():
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.name == "Makefile" or path.suffix in SOURCE_SUFFIXES:
            if path.name == "check.py":
                continue
            yield path


def normalized(path: Path) -> str:
    return LITERAL_JOIN.sub("", path.read_text(encoding="utf-8", errors="replace"))


def main() -> int:
    failed = False
    files = list(source_files())
    texts = {path: normalized(path) for path in files}
    for pattern in FORBIDDEN:
        for path, text in texts.items():
            if pattern in text:
                print(f"forbidden {pattern} in {path.relative_to(ROOT)}")
                failed = True

    entitlements = ROOT / "CoamingWidget" / "CoamingWidget.entitlements"
    if "com.apple.security.network.client" in entitlements.read_text(encoding="utf-8"):
        print("extension entitlements allow network")
        failed = True

    for path in files:
        if path.suffix != ".swift":
            continue
        for lineno, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if "refresh_token" not in line and "refreshToken" not in line:
                continue
            stripped = line.strip()
            if stripped.startswith("//") and "do not read" in line.lower():
                continue
            print(f"refresh token string in {path.relative_to(ROOT)}:{lineno}")
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

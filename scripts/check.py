#!/usr/bin/env python3
"""Static checks. internal/ lists forbidden hosts, so it is skipped. Fixtures are skipped too."""
import re
import subprocess
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
    "chatgpt.com/backend-api",
    "wham/usage",
]
# Strings that must be absent from the flag-less package build. See ProviderID.included.
DEFAULT_BUILD_MARKERS = (
    "cursor.com",
    "usage-summary",
    "state.vscdb",
    "WorkosCursorSessionToken",
    "cursor-access-token",
)
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
    if len(sys.argv) == 3 and sys.argv[1] == "--app":
        return 1 if scan_app(Path(sys.argv[2])) else 0
    if len(sys.argv) != 1:
        print("usage: check.py [--app PATH]")
        return 1
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

    if check_sparkle_boundaries(files):
        failed = True

    if check_default_build():
        failed = True

    return 1 if failed else 0


def check_sparkle_boundaries(files) -> bool:
    """Sparkle is linked by the host only, checks only on the button, and the feed is HTTPS."""
    failed = False
    host_plist = (ROOT / "CoamingHost" / "Info.plist").read_text(encoding="utf-8")
    if not re.search(r"<key>SUEnableAutomaticChecks</key>\s*<false/>", host_plist):
        print("host Info.plist must set SUEnableAutomaticChecks to false")
        failed = True
    feed = re.search(r"<key>SUFeedURL</key>\s*<string>([^<]*)</string>", host_plist)
    if not feed or not feed.group(1).startswith("https://github.com/"):
        print("host Info.plist SUFeedURL must be an https://github.com/ URL")
        failed = True
    for path in files:
        if "CoamingWidget" in path.parts and path.suffix == ".swift":
            if re.search(r"^\s*import Sparkle\b", path.read_text(encoding="utf-8", errors="replace"), re.M):
                print(f"widget imports Sparkle in {path.relative_to(ROOT)}")
                failed = True
    widget_plist = (ROOT / "CoamingWidget" / "Info.plist").read_text(encoding="utf-8")
    if "SUFeedURL" in widget_plist or "SUPublicEDKey" in widget_plist:
        print("widget Info.plist must not configure Sparkle")
        failed = True
    return failed


def check_default_build() -> bool:
    root = ROOT / "build" / "spm-off"
    if not root.is_dir():
        print("default build missing: build/spm-off")
        return True
    targets = [
        path
        for path in root.rglob("*")
        if path.is_file() and (path.name == "coaming" or path.suffix == ".o" or path.name.startswith("libCoamingCore"))
    ]
    if not any(path.name == "coaming" for path in targets):
        print("default build has no coaming executable under build/spm-off")
        return True
    failed = False
    for path in targets:
        try:
            output = subprocess.run(
                ["strings", "-a", str(path)],
                check=False,
                capture_output=True,
                text=True,
                errors="replace",
            )
        except OSError as error:
            print(f"strings failed: {error}")
            return True
        for marker in DEFAULT_BUILD_MARKERS:
            if marker in output.stdout:
                print(f"default build contains {marker} in {path.relative_to(ROOT)}")
                failed = True
    return failed


def scan_app(app: Path) -> bool:
    """Fail if a product contains the optional Cursor path, or if an extension carries Sparkle.
    Markers stay in this file."""
    if not app.is_dir():
        print(f"app missing: {app}")
        return True
    failed = False
    saw_file = False
    plugins = app / "Contents" / "PlugIns"
    for path in app.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        saw_file = True
        if plugins in path.parents and ("Sparkle" in path.name or "Sparkle.framework" in path.parts):
            print(f"extension contains Sparkle: {path}")
            failed = True
        try:
            output = subprocess.run(
                ["strings", "-a", str(path)],
                check=False,
                capture_output=True,
                text=True,
                errors="replace",
            )
        except OSError as error:
            print(f"strings failed: {error}")
            return True
        for marker in DEFAULT_BUILD_MARKERS:
            if marker in output.stdout:
                print(f"app contains {marker} in {path}")
                failed = True
    if not saw_file:
        print(f"app has no files: {app}")
        return True
    return failed


if __name__ == "__main__":
    sys.exit(main())

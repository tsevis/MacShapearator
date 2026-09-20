#!/usr/bin/env python3
"""Check that the app can actually run on the macOS it claims to support.

Every Mach-O records the oldest macOS it will load on, and dyld enforces it.
The bundled interpreter, OpenSSL and potrace are not built here: they are
copied from whatever pyenv and Homebrew installed, carrying the deployment
target of the machine that built *them*. So the app's Info.plist can promise
macOS 13 while its own interpreter refuses to start below 15.4 -- and it
does, which is how this check came to exist. The app would open and its
engine would never start, on exactly the machines the README invites.

    check_minimum_os.py <path to .app>

Exits non-zero, naming the offenders, when any bundled binary needs a newer
macOS than LSMinimumSystemVersion advertises.
"""
from __future__ import annotations

import plistlib
import re
import subprocess
import sys
from pathlib import Path

MINOS = re.compile(r"^\s*minos\s+([0-9.]+)\s*$", re.MULTILINE)
MACHO_MAGIC = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe")


def version(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in text.split("."))


def is_macho(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        return False
    try:
        return path.open("rb").read(4) in MACHO_MAGIC
    except OSError:
        return False


def minimum_os(path: Path) -> str | None:
    """The oldest macOS this binary loads on, or None if it does not say."""
    out = subprocess.run(["otool", "-l", str(path)], capture_output=True, text=True).stdout
    found = MINOS.findall(out)
    # A fat binary carries one load command per architecture; the app can only
    # run where every slice it might use can run, so take the highest.
    return max(found, key=version) if found else None


def declared_minimum(app: Path) -> str:
    plist = plistlib.loads((app / "Contents" / "Info.plist").read_bytes())
    declared = plist.get("LSMinimumSystemVersion")
    if not declared:
        raise SystemExit("error: the app declares no LSMinimumSystemVersion.")
    return declared


def main(argv: list[str]) -> int:
    app = Path(argv[1])
    declared = declared_minimum(app)
    limit = version(declared)

    offenders: list[tuple[str, str]] = []
    highest = limit
    for path in app.rglob("*"):
        if not is_macho(path):
            continue
        needed = minimum_os(path)
        if needed is None:
            continue
        if version(needed) > highest:
            highest = version(needed)
        if version(needed) > limit:
            offenders.append((needed, str(path.relative_to(app))))

    if offenders:
        print(f"error: the app declares macOS {declared}, but {len(offenders)} bundled "
              f"binaries need a newer one. The highest is "
              f"{'.'.join(str(n) for n in highest)}.", file=sys.stderr)
        for needed, name in sorted(offenders, key=lambda pair: version(pair[0]), reverse=True)[:10]:
            print(f"  needs {needed}: {name}", file=sys.stderr)
        if len(offenders) > 10:
            print(f"  ... and {len(offenders) - 10} more", file=sys.stderr)
        print("Raise MACOSX_DEPLOYMENT_TARGET in project.yml to match, or rebuild the "
              "bundled dependencies against an older target.", file=sys.stderr)
        return 1

    print(f"every bundled binary runs on macOS {declared}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

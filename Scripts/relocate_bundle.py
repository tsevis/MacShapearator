#!/usr/bin/env python3
"""Make the bundled interpreter and tools self-contained.

Copying an interpreter into an app does not move it: its Mach-O load commands
still name the absolute paths it was linked against on the build machine.
MacShapearator shipped for months with its python3.10 pointing at
/Users/<author>/.pyenv/..., its _ssl at Homebrew's OpenSSL and its potrace at
a Homebrew Cellar path. On the build machine those paths exist, so nothing
ever failed there; on any other Mac the interpreter cannot start, and the app
that advertises "nothing to install" cannot run its engine.

Signing makes it fail on the build machine too, which is how it was finally
noticed: a Developer ID binary refuses to load a dylib signed by a different
team, so dyld reports "different Team IDs" rather than a missing file.

This copies every non-system library a bundled Mach-O still points at into the
bundle and rewrites the reference to a @loader_path one, repeating until the
closure is empty because a vendored library has dependencies of its own.

Run it before signing. install_name_tool invalidates whatever signature a
binary already carried -- pyenv's interpreter and Homebrew's dylibs are all
signed -- and a binary with a broken signature is killed on launch with no
message at all, only exit 137. So every Mach-O is re-signed ad hoc here;
release.sh replaces that with the Developer ID signature.

    relocate_bundle.py <Resources dir>            relocate, then report
    relocate_bundle.py <Resources dir> --verify   report only, non-zero if any
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

SYSTEM_PREFIXES = ("@", "/usr/lib/", "/System/")


def is_macho(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        return False
    try:
        return path.open("rb").read(4) in (
            b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe")
    except OSError:
        return False


def install_id(path: Path) -> str | None:
    """A dylib's own name. Anything linking it by an absolute id resolves to
    the build machine, so it is rewritten like any other reference."""
    out = subprocess.run(["otool", "-D", str(path)], capture_output=True, text=True).stdout
    lines = [line.strip() for line in out.splitlines()[1:] if line.strip()]
    return lines[0] if lines else None


def references(path: Path) -> list[str]:
    out = subprocess.run(["otool", "-L", str(path)], capture_output=True, text=True).stdout
    return [line.strip().split(" (")[0] for line in out.splitlines()[1:] if line.strip()]


def external(ref: str) -> bool:
    """An absolute path outside the bundle. A relative install name is a
    build artefact of whoever compiled the extension; the loader ignores it
    and copying it in creates junk, as one run of this script proved."""
    return ref.startswith("/") and not ref.startswith(SYSTEM_PREFIXES)


def run(*argv: str) -> None:
    subprocess.run(argv, check=True, capture_output=True)


def relocate(roots: list[Path], vendor: Path) -> tuple[int, int]:
    vendor.mkdir(parents=True, exist_ok=True)
    pending = [p for root in roots for p in root.rglob("*") if is_macho(p)]
    seen: set[Path] = set()
    copied = rewritten = 0

    while pending:
        binary = pending.pop()
        if binary in seen:
            continue
        seen.add(binary)
        os.chmod(binary, os.stat(binary).st_mode | 0o200)

        own = install_id(binary)
        if own and external(own):
            run("install_name_tool", "-id", f"@loader_path/{os.path.basename(own)}", str(binary))
            rewritten += 1

        for ref in references(binary):
            if own and ref == own:
                continue
            if not external(ref):
                continue
            name = os.path.basename(ref)
            target = vendor / name
            if not target.exists():
                source = Path(ref)
                if not source.exists():
                    # A dylib id that names a path nobody ships (Inkscape does
                    # this); the loader never resolves it, so leave it alone.
                    continue
                shutil.copy2(source.resolve(), target)
                os.chmod(target, os.stat(target).st_mode | 0o200)
                run("install_name_tool", "-id", f"@loader_path/{name}", str(target))
                copied += 1
                pending.append(target)
            relative = os.path.relpath(vendor, binary.parent)
            new = f"@loader_path/{name}" if relative == "." else f"@loader_path/{relative}/{name}"
            run("install_name_tool", "-change", ref, new, str(binary))
            rewritten += 1

    for binary in sorted(seen):
        # Ad hoc, because the point is a valid signature rather than an
        # identity; release.sh signs the shipped bundle for real.
        subprocess.run(["codesign", "--force", "--sign", "-", str(binary)],
                       check=False, capture_output=True)

    return copied, rewritten, len(seen)


def survey(roots: list[Path]) -> list[tuple[str, str]]:
    return [
        (str(p), ref)
        for root in roots for p in root.rglob("*")
        if is_macho(p) for ref in references(p)
        if external(ref)
    ]


def main(argv: list[str]) -> int:
    bundle = Path(argv[1])
    verify_only = "--verify" in argv
    python_root = bundle / "BundledPython/python"
    # Inkscape.app is deliberately not in here: it arrives already relocated
    # and re-signed as a unit, and rewriting its internals would break that.
    roots = [python_root, bundle / "BundledBin"]

    if not verify_only:
        copied, rewritten, signed = relocate(roots, python_root / "lib")
        print(f"vendored {copied} libraries, rewrote {rewritten} references, "
              f"re-signed {signed} binaries")

    left = survey(roots)
    if left:
        print(f"error: {len(left)} references still point outside the bundle:")
        for path, ref in left[:20]:
            print(f"  {path}\n    -> {ref}")
        return 1
    print("every bundled binary resolves inside the bundle")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

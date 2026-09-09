#!/usr/bin/env python3
"""Ad-hoc sign unsigned runtime Mach-O code in a staged XCFramework.

Existing signatures (including invalid or partially signed universal binaries)
and signed enclosing bundles are preserved. Never sign the XCFramework itself.
"""

import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


MACH_MAGICS = {
    bytes.fromhex(value)
    for value in (
        "feedface", "cefaedfe", "feedfacf", "cffaedfe",
        "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
    )
}
BUNDLE_SUFFIXES = {".framework", ".xcframework", ".bundle", ".app", ".xpc"}


def run(*arguments):
    return subprocess.run(
        arguments, capture_output=True, text=True,
        env={**os.environ, "LC_ALL": "C"},
    )


def checked(*arguments):
    result = run(*arguments)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def runtime_binary(path):
    """Return (is runtime code, has any embedded signature), across all slices."""
    with path.open("rb") as source:
        if source.read(4) not in MACH_MAGICS:
            return False, False
    headers = checked("/usr/bin/otool", "-arch", "all", "-hv", str(path))
    types = [
        line.split()[4] for line in headers.splitlines()
        if line.startswith(("MH_MAGIC", "MH_CIGAM"))
    ]
    if not types:
        raise RuntimeError(f"Cannot read Mach-O headers: {path}")
    if not all(kind in {"EXECUTE", "DYLIB", "BUNDLE"} for kind in types):
        return False, False
    commands = checked("/usr/bin/otool", "-arch", "all", "-l", str(path))
    return True, re.search(r"^\s*cmd LC_CODE_SIGNATURE$", commands, re.M) is not None


def unsigned(path, *options):
    # Verification failure does not mean unsigned. Display is a separate query;
    # only its explicit unsigned diagnostic authorizes adding a signature.
    result = run("/usr/bin/codesign", "--display", *options, str(path))
    if result.returncode == 0:
        return False
    if result.stderr.strip() == f"{path}: code object is not signed at all":
        return True
    raise RuntimeError(f"Cannot determine signature state: {result.stderr.strip()}")


def framework_versions(path):
    versions = path / "Versions"
    if versions.is_dir():
        roots = [p for p in sorted(versions.iterdir()) if p.is_dir() and not p.is_symlink()]
    else:
        roots = [path]
    result = []
    for root in roots:
        plist = root / "Resources/Info.plist" if root != path else root / "Info.plist"
        with plist.open("rb") as source:
            executable = plistlib.load(source)["CFBundleExecutable"]
        binary = root / executable
        if binary.parent != root or binary.is_symlink() or not binary.is_file():
            raise RuntimeError(f"Unexpected framework executable: {binary}")
        options = ("--bundle-version", root.name) if root != path else ()
        result.append((root, binary, options))
    if not result:
        raise RuntimeError(f"No framework versions: {path}")
    return result


def snapshot(root):
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            result[path] = ("symlink", os.readlink(path))
        elif path.is_file():
            result[path] = ("file", hashlib.sha256(path.read_bytes()).hexdigest())
        elif path.is_dir():
            result[path] = ("directory",)
    return result


def sign_tree(root):
    before = snapshot(root)
    changed_binaries = set()
    new_seals = set()

    def sign(target, binary, options=(), seal_root=None):
        checked("/usr/bin/codesign", "--sign", "-", "--timestamp=none", *options, str(target))
        checked("/usr/bin/codesign", "--verify", "--all-architectures", *options, str(target))
        changed_binaries.add(binary)
        if seal_root:
            new_seals.update({seal_root / "_CodeSignature", seal_root / "_CodeSignature/CodeResources"})
        print(f"Ad-hoc signed: {target}" + (f" ({options[-1]})" if options else ""))

    def visit(path, excluded=frozenset()):
        if path.is_symlink() or path in excluded:
            return
        if path.is_file():
            runtime, signed = runtime_binary(path)
            if runtime and not signed and unsigned(path):
                sign(path, path)
            return
        if not path.is_dir():
            return

        versions = framework_versions(path) if path.suffix == ".framework" else []
        if versions:
            states = [(runtime_binary(binary), root, binary, options) for root, binary, options in versions]
            # A signature on any architecture/version protects the entire bundle,
            # including its unsigned nested code and resources.
            if (path / "_CodeSignature").exists() or any(
                (root / "_CodeSignature").exists() or state[1]
                for state, root, _, _ in states
            ):
                return
            if not all(state[0] for state, _, _, _ in states):
                return  # Static framework: no runtime code to sign.
            if any(not unsigned(path, *options) for _, _, _, options in states):
                return
        elif path.suffix in BUNDLE_SUFFIXES:
            if (path / "_CodeSignature").exists() or not unsigned(path):
                return

        mains = excluded | {binary for _, binary, _ in versions}
        for child in sorted(path.iterdir()):
            visit(child, mains)
        for version_root, binary, options in versions:
            sign(path, binary, options, version_root)

    visit(root)
    after = snapshot(root)
    # Signing may only change the selected unsigned executables and add resource
    # seals. Preserve every other byte, entry and symlink, including old seals.
    for path in before.keys() | after.keys():
        if before.get(path) == after.get(path):
            continue
        if path in changed_binaries and before.get(path, (None,))[0] == "file" and after.get(path, (None,))[0] == "file":
            continue
        if path in new_seals and path not in before and path in after:
            continue
        raise RuntimeError(f"Signing changed unrelated contents: {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: sign-unsigned.py <staged.xcframework>")
    try:
        sign_tree(Path(sys.argv[1]).absolute())
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        sys.exit(f"Error: {error}")

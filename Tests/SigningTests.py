"""Regression checks using real Mach-O fixtures and macOS codesign."""

import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "sign_unsigned", Path(__file__).resolve().parents[1] / "Scripts/sign-unsigned.py"
)
signer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signer)


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "fixture.c"
        self.source.write_text("int answer(void) { return 42; }\nint main(void) { return 0; }\n")
        self.staged = self.root / "staged"
        self.staged.mkdir()

    def build(self, path, kind="dylib", arch="arm64"):
        options = {
            "dylib": ["-dynamiclib"], "bundle": ["-bundle"],
            "executable": [], "object": ["-c"],
        }[kind]
        if kind != "object":
            options += ["-Wl,-no_adhoc_codesign"]
        signer.checked(
            "/usr/bin/xcrun", "clang", "-arch", arch, *options,
            str(self.source), "-o", str(path),
        )
        return path

    def framework(self, parent, name="Fixture", versioned=False):
        framework = parent / f"{name}.framework"
        content = framework / "Versions/A" if versioned else framework
        content.mkdir(parents=True)
        resources = content / "Resources" if versioned else content
        resources.mkdir(exist_ok=True)
        with (resources / "Info.plist").open("wb") as output:
            plistlib.dump({
                "CFBundleExecutable": name,
                "CFBundleIdentifier": f"test.{name}",
                "CFBundlePackageType": "FMWK",
                "CFBundleVersion": "1.0",
            }, output)
        self.build(content / name)
        (resources / "data.txt").write_text("preserved resource\n")
        if versioned:
            (framework / "Versions/Current").symlink_to("A")
            (framework / name).symlink_to(f"Versions/Current/{name}")
            (framework / "Resources").symlink_to("Versions/Current/Resources")
        return framework, content

    def assertSigned(self, path):
        signer.checked("/usr/bin/codesign", "--verify", "--all-architectures", str(path))

    def test_runtime_types_and_non_code(self):
        binaries = [self.build(self.staged / kind, kind) for kind in ("dylib", "bundle", "executable")]
        obj = self.build(self.staged / "fixture.o", "object")
        archive = self.staged / "libfixture.a"
        signer.checked("/usr/bin/ar", "rcs", str(archive), str(obj))
        data = self.staged / "data.dylib"
        data.write_text("not a Mach-O library\n")
        (self.staged / "alias").symlink_to("dylib")
        preserved = {p: p.read_bytes() for p in (obj, archive, data)}
        signer.sign_tree(self.staged)
        for binary in binaries:
            self.assertSigned(binary)
        for path, original in preserved.items():
            self.assertEqual(path.read_bytes(), original)
        self.assertEqual(os.readlink(self.staged / "alias"), "dylib")

    def test_existing_valid_invalid_and_partial_signatures(self):
        valid = self.build(self.staged / "valid.dylib")
        signer.checked("/usr/bin/codesign", "--sign", "-", "--timestamp=none", str(valid))
        invalid = self.staged / "invalid.dylib"
        shutil.copyfile(valid, invalid)
        # Header bytes are sealed, but changing the UUID does not break parsing.
        commands = signer.checked("/usr/bin/otool", "-l", str(invalid))
        uuid = commands.split("uuid ", 1)[1].splitlines()[0].strip()
        payload = invalid.read_bytes()
        marker = bytes.fromhex(uuid.replace("-", ""))
        offset = payload.index(marker)
        invalid.write_bytes(payload[:offset] + bytes([payload[offset] ^ 1]) + payload[offset + 1:])
        self.assertNotEqual(signer.run("/usr/bin/codesign", "--verify", str(invalid)).returncode, 0)
        x86 = self.build(self.root / "x86.dylib", arch="x86_64")
        signer.checked("/usr/bin/codesign", "--sign", "-", "--timestamp=none", str(x86))
        arm = self.build(self.root / "arm.dylib")
        partial = self.staged / "partial.dylib"
        signer.checked("/usr/bin/lipo", "-create", str(x86), str(arm), "-output", str(partial))
        before = signer.snapshot(self.staged)
        signer.sign_tree(self.staged)
        self.assertEqual(signer.snapshot(self.staged), before)

    def test_framework_nesting_versions_and_reproducibility(self):
        outer, content = self.framework(self.staged, "Outer", versioned=True)
        nested = content / "Frameworks"
        nested.mkdir()
        inner, _ = self.framework(nested, "Inner")
        resource = self.build(content / "Resources/layer.dylib", "bundle")
        duplicate = self.root / "duplicate"
        shutil.copytree(self.staged, duplicate, symlinks=True)
        signer.sign_tree(self.staged)
        for path in (resource, inner, outer):
            self.assertSigned(path)
        first = {p.relative_to(self.staged): value for p, value in signer.snapshot(self.staged).items()}
        signer.sign_tree(self.staged)
        signer.sign_tree(duplicate)
        self.assertEqual(first, {p.relative_to(self.staged): value for p, value in signer.snapshot(self.staged).items()})
        self.assertEqual(first, {p.relative_to(duplicate): value for p, value in signer.snapshot(duplicate).items()})

    def test_signed_framework_protects_unsigned_resource(self):
        outer, content = self.framework(self.staged, versioned=True)
        resource = self.build(content / "Resources/unsigned.dylib")
        signer.checked("/usr/bin/codesign", "--sign", "-", "--timestamp=none", str(outer))
        self.assertSigned(outer)
        self.assertTrue(signer.unsigned(resource))
        before = signer.snapshot(self.staged)
        signer.sign_tree(self.staged)
        self.assertEqual(signer.snapshot(self.staged), before)
        self.assertSigned(outer)
        (content / "Resources/data.txt").write_text("invalidated seal\n")
        before = signer.snapshot(self.staged)
        signer.sign_tree(self.staged)
        self.assertEqual(signer.snapshot(self.staged), before)

    def test_signed_xcframework_is_preserved(self):
        container = self.staged / "Fixture.xcframework"
        container.mkdir()
        with (container / "Info.plist").open("wb") as output:
            plistlib.dump({"CFBundlePackageType": "XFWK", "XCFrameworkFormatVersion": "1.0", "AvailableLibraries": []}, output)
        self.build(container / "unsigned.dylib")
        signer.checked("/usr/bin/codesign", "--sign", "-", "--timestamp=none", str(container))
        before = signer.snapshot(self.staged)
        signer.sign_tree(self.staged)
        self.assertEqual(signer.snapshot(self.staged), before)

    def test_static_framework_is_unchanged(self):
        framework, content = self.framework(self.staged)
        (content / "Fixture").unlink()
        obj = self.build(self.root / "fixture.o", "object")
        signer.checked("/usr/bin/ar", "rcs", str(content / "Fixture"), str(obj))
        before = signer.snapshot(self.staged)
        signer.sign_tree(self.staged)
        self.assertEqual(signer.snapshot(self.staged), before)

    def test_unknown_signature_state_fails_closed(self):
        broken = self.staged / "broken.dylib"
        broken.write_bytes(bytes.fromhex("cffaedfe"))
        before = signer.snapshot(self.staged)
        with self.assertRaises(RuntimeError):
            signer.sign_tree(self.staged)
        self.assertEqual(signer.snapshot(self.staged), before)
        with self.assertRaises(RuntimeError):
            signer.unsigned(self.staged / "missing.dylib")


if __name__ == "__main__":
    unittest.main()

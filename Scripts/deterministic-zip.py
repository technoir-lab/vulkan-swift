#!/usr/bin/env python3
"""Create a deterministic zip archive.

Usage: deterministic-zip.py <output.zip> <path> <arcname> [<path> <arcname> ...]

All entries use a fixed timestamp and DEFLATE compression level. Symlinks are
stored as symlinks.
"""

import os
import stat
import sys
import zipfile


FIXED_DATE = (1980, 1, 1, 0, 0, 0)


def add_entry(zf, path, arcname):
    if os.path.islink(path):
        info = zipfile.ZipInfo(arcname, FIXED_DATE)
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, os.readlink(path))
        return
    if os.path.isdir(path):
        info = zipfile.ZipInfo(arcname.rstrip("/") + "/", FIXED_DATE)
        info.create_system = 3
        info.external_attr = (stat.S_IFDIR | 0o755) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, b"")
        for name in sorted(os.listdir(path)):
            child_path = os.path.join(path, name)
            child_arc = arcname.rstrip("/") + "/" + name
            add_entry(zf, child_path, child_arc)
        return
    info = zipfile.ZipInfo(arcname, FIXED_DATE)
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    with open(path, "rb") as source:
        zf.writestr(info, source.read())


def main():
    if len(sys.argv) < 4 or (len(sys.argv) - 2) % 2 != 0:
        sys.exit(
            "usage: deterministic-zip.py <output.zip> "
            "<path> <arcname> [<path> <arcname> ...]"
        )
    output = sys.argv[1]
    pairs = sys.argv[2:]
    with zipfile.ZipFile(
        output,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as zf:
        for index in range(0, len(pairs), 2):
            path = os.path.realpath(pairs[index])
            arcname = pairs[index + 1]
            add_entry(zf, path, arcname)


if __name__ == "__main__":
    main()

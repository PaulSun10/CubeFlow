#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Paul Sun
"""Verify the recorded delivery inventory, not GPL compliance or build equivalence."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import struct
import sys
import tarfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "ThirdPartySources/TNoodle/source-manifest.json"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe_relative(name):
    path = PurePosixPath(name)
    require(not path.is_absolute() and ".." not in path.parts, f"Unsafe path: {name}")
    return path


def local(name):
    path = ROOT / safe_relative(name)
    require(path.resolve().is_relative_to(ROOT), f"Path escapes repository: {name}")
    return path


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_archive(item):
    path = local(item["path"])
    require(sha256(path) == item["sha256"], f"Archive hash mismatch: {path.name}")
    with zipfile.ZipFile(path) if path.suffix == ".zip" else tarfile.open(path, "r:gz") as archive:
        if isinstance(archive, zipfile.ZipFile):
            require(archive.testzip() is None, f"ZIP CRC failure: {path.name}")
            members = archive.namelist()
            read = archive.read
        else:
            entries = archive.getmembers()
            members = [entry.name for entry in entries]
            for entry in entries:
                if entry.issym():
                    safe_relative(str(PurePosixPath(entry.name).parent / entry.linkname))
                elif entry.islnk():
                    safe_relative(entry.linkname)
                else:
                    require(entry.isdir() or entry.isfile(), f"Special archive entry: {entry.name}")

            def read(name):
                with archive.extractfile(name) as stream:
                    return stream.read()

        require(len(members) == len(set(members)), f"Duplicate archive paths: {path.name}")
        for name in members:
            safe_relative(name)
        for member in item["required_members"]:
            name = item["root"] + "/" + member["path"]
            require(name in members, f"Missing archive member: {name}")
            require(hashlib.sha256(read(name)).hexdigest() == member["sha256"],
                    f"Archive member mismatch: {name}")
    print(f"PASS archive: {path.name}")


def macho_observations(path, expected):
    """Read load-command and SVM string facts without loading or executing the image."""
    data = path.read_bytes()
    require(struct.unpack_from("<I", data)[0] == 0xFEEDFACF, "Expected little-endian Mach-O 64")
    count = struct.unpack_from("<I", data, 16)[0]
    offset = 32
    segments = []
    dependencies = []
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, offset)
        require(size >= 8 and offset + size <= len(data), "Invalid Mach-O load command")
        if command == 0x19:
            address, _, file_offset, file_size = struct.unpack_from("<QQQQ", data, offset + 24)
            segments.append((address, file_offset, file_size))
        elif command in (0xC, 0x18, 0x80000018, 0x8000001F):
            start = offset + struct.unpack_from("<I", data, offset + 8)[0]
            dependencies.append(data[start:offset + size].split(b"\0", 1)[0].decode())
        offset += size
    require(dependencies == expected["dynamic_dependencies"], "Dynamic dependency list changed")
    for record in expected["svm_strings"]:
        address = int(record["address"], 16)
        matches = [file_offset + address - base for base, file_offset, size in segments
                   if base <= address < base + size]
        require(len(matches) == 1, "Unmapped SVM metadata address")
        actual = data[matches[0]:matches[0] + 512].split(b"\0", 1)[0].decode()
        require(actual == record["value"], f"SVM metadata mismatch: {record['symbol']}")
    print("PASS binary: hash, dynamic libraries and mapped SVM metadata")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-complete", action="store_true",
                        help="also fail when the documented source-delivery verdict is incomplete")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    require(manifest["schema_version"] == 1, "Unsupported source manifest schema")
    for item in manifest["archives"]:
        verify_archive(item)
    sums = local("ThirdPartySources/TNoodle/SHA256SUMS").read_text().splitlines()
    recorded = {}
    for line in sums:
        digest, name = line.split(maxsplit=1)
        require(name not in recorded, f"Duplicate checksum path: {name}")
        recorded[name] = digest
    require(recorded == {item["path"]: item["sha256"] for item in manifest["archives"]},
            "Checksum list and manifest disagree")
    for item in manifest["repository_files"]:
        require(sha256(local(item["path"])) == item["sha256"], f"Repository file mismatch: {item['path']}")
    binary = local(manifest["binary"]["path"])
    require(sha256(binary) == manifest["binary"]["sha256"], "Native input hash changed")
    macho_observations(binary, manifest["binary"])
    for name in manifest["documentation"]:
        require(local(name).is_file(), f"Missing documentation: {name}")
    archive_paths = {item["path"] for item in manifest["archives"]}
    component_ids = [item["id"] for item in manifest["components"]]
    require(len(component_ids) == len(set(component_ids)), "Duplicate component IDs")
    for component in manifest["components"]:
        require(component["id"] and component["evidence"] and component["source_status"],
                "Incomplete component inventory entry")
        require(set(component["source_archives"]) <= archive_paths, "Unknown component source archive")
    print("PASS integrity: archives, source/license members, repository hashes and references")
    print("Delivery verdict: " + manifest["delivery_verdict"])
    for gap in manifest["remaining_gaps"]:
        print(f"OPEN {gap['id']}: {gap['missing']}")
    if args.require_complete and (manifest["remaining_gaps"] or manifest["delivery_verdict"] != "COMPLETE"):
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, struct.error, zipfile.BadZipFile, tarfile.TarError) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)

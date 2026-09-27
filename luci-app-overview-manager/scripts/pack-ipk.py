#!/usr/bin/env python3
"""Build a deterministic opkg package without requiring an OpenWrt SDK."""

import gzip
import io
import os
import sys
import tarfile

EPOCH = 0


def normalize(info):
    info.uid = info.gid = 0
    info.uname = info.gname = "root"
    info.mtime = EPOCH
    return info


def archive(members):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for archive_name, path in members:
            info = normalize(tar.gettarinfo(path, archive_name))
            if info.isreg():
                with open(path, "rb") as source:
                    tar.addfile(info, source)
            else:
                tar.addfile(info)
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", mtime=EPOCH) as output:
        output.write(raw.getvalue())
    return compressed.getvalue()


def walk_payload(stage):
    result = []
    for root, directories, files in os.walk(stage):
        directories.sort()
        relative = os.path.relpath(root, stage)
        if relative == "CONTROL" or relative.startswith("CONTROL" + os.sep):
            continue
        if relative != ".":
            result.append(("./" + relative, root))
        for name in sorted(files):
            path = os.path.join(root, name)
            result.append(("./" + os.path.relpath(path, stage), path))
    return sorted(result)


def field(path, name):
    with open(path, encoding="utf-8") as source:
        for line in source:
            if line.startswith(name + ":"):
                return line.split(":", 1)[1].strip()
    raise SystemExit(f"missing {name} in {path}")


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: pack-ipk.py STAGE OUTPUT_DIR")
    stage, output_dir = sys.argv[1:]
    control_dir = os.path.join(stage, "CONTROL")
    control_path = os.path.join(control_dir, "control")
    control_members = [("./", control_dir)]
    control_members.extend(
        ("./" + name, os.path.join(control_dir, name))
        for name in sorted(os.listdir(control_dir))
    )
    parts = {
        "debian-binary": b"2.0\n",
        "control.tar.gz": archive(control_members),
        "data.tar.gz": archive(walk_payload(stage)),
    }
    package = field(control_path, "Package")
    version = field(control_path, "Version")
    architecture = field(control_path, "Architecture")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(
        output_dir, f"{package}_{version}_{architecture}.ipk"
    )
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for name in ("debian-binary", "control.tar.gz", "data.tar.gz"):
            payload = parts[name]
            info = normalize(tarfile.TarInfo("./" + name))
            info.mode = 0o644
            info.size = len(payload)
            tar.addfile(info, io.BytesIO(payload))
    with gzip.GzipFile(output_path, "wb", mtime=EPOCH) as output:
        output.write(raw.getvalue())
    print(output_path)


if __name__ == "__main__":
    main()

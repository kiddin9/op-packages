#!/usr/bin/env python3
"""Build a deterministic opkg package."""
import gzip
import io
import os
import sys
import tarfile


def normalize(info):
    info.uid = info.gid = info.mtime = 0
    info.uname = info.gname = "root"
    return info


def archive(members):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as out:
        for name, path in members:
            info = normalize(out.gettarinfo(path, name))
            if info.isreg():
                with open(path, "rb") as source:
                    out.addfile(info, source)
            else:
                out.addfile(info)
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", mtime=0) as out:
        out.write(raw.getvalue())
    return compressed.getvalue()


def walk(stage, control=False):
    result = []
    base = os.path.join(stage, "CONTROL") if control else stage
    for root, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if control or d != "CONTROL")
        rel = os.path.relpath(root, base)
        if rel != ".":
            result.append(("./" + rel, root))
        for name in sorted(files):
            result.append(("./" + os.path.join(rel, name).replace("./", "", 1),
                           os.path.join(root, name)))
    return sorted(result)


def control_field(path, field):
    with open(path, encoding="utf-8") as source:
        for line in source:
            if line.startswith(field + ":"):
                return line.split(":", 1)[1].strip()
    raise SystemExit("missing control field: " + field)


stage, output = sys.argv[1:]
control = os.path.join(stage, "CONTROL", "control")
parts = {
    "debian-binary": b"2.0\n",
    "control.tar.gz": archive(walk(stage, True)),
    "data.tar.gz": archive(walk(stage, False)),
}
os.makedirs(output, exist_ok=True)
name = "%s_%s_%s.ipk" % tuple(control_field(control, field) for field in
                               ("Package", "Version", "Architecture"))
target = os.path.join(output, name)
raw = io.BytesIO()
with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as out:
    for part in ("debian-binary", "control.tar.gz", "data.tar.gz"):
        data = parts[part]
        info = normalize(tarfile.TarInfo("./" + part))
        info.mode, info.size = 0o644, len(data)
        out.addfile(info, io.BytesIO(data))
with gzip.GzipFile(target, "wb", mtime=0) as out:
    out.write(raw.getvalue())
print(target)

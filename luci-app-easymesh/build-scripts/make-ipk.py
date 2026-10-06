#!/usr/bin/env python3
"""Create a Debian/OpenWrt .ipk (ar archive) from debian-binary + control.tar.gz + data.tar.gz."""

import sys
import os
import struct

def write_ar_header(f, name, size):
    # ar member header is 60 bytes
    # name must end with '/' for GNU/SysV compatibility
    name_field = (name + '/')[:16].ljust(16)
    header = "{}{:<12}{:<6}{:<6}{:<8}{:<10}`\n".format(
        name_field, "0", "0", "0", "100644", size
    )
    f.write(header.encode('ascii'))

def add_file(ar, path, archive_name):
    data = open(path, 'rb').read()
    write_ar_header(ar, archive_name, len(data))
    ar.write(data)
    # Pad to even length
    if len(data) % 2:
        ar.write(b'\n')

def main():
    if len(sys.argv) != 5:
        print("Usage: make-ipk.py <out.ipk> <debian-binary> <control.tar.gz> <data.tar.gz>")
        sys.exit(1)

    out, debian_bin, control_tgz, data_tgz = sys.argv[1:]

    with open(out, 'wb') as ar:
        # Magic
        ar.write(b'!<arch>\n')
        add_file(ar, debian_bin, 'debian-binary')
        add_file(ar, control_tgz, 'control.tar.gz')
        add_file(ar, data_tgz, 'data.tar.gz')

if __name__ == '__main__':
    main()

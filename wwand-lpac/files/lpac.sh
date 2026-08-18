#!/bin/sh
# thin wrapper so `lpac` on PATH resolves to the self-contained static binary
exec /usr/lib/lpac "$@"

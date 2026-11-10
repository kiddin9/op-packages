#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 Amr Fateem <amr.fateem@yahoo.com>

case "$1" in
v2raya)
	/usr/bin/v2raya --version | grep -F "$2"
	;;
*)
	exit 1
	;;
esac

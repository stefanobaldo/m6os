# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The files /etc/rc works on: romfs's, so the generators cannot drift
# apart. Written by tools/mkdisk.tcl before it imports the staging
# directory, and generated again by romfs-turbo.tcl for the comparison.
source [file join [file dirname [info script]] .. romfs files.tcl]

# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# m6os build.
#   make         assemble every test program under tests/ and report sizes
#   make check   fetch the pinned tools, build, run every test in headless openMSX
#                (arrives with the harness)
#   make clean   remove build/;  make distclean   also remove .tools/
# Tools come from .tools/ when tools/fetch-*.sh put them there, else from PATH;
# either way their versions are checked. See CONTRIBUTING.md.

SJASMPLUS_VERSION := 1.24.0
OPENMSX_VERSION   := 21.0-m6.1

SJASMPLUS := $(if $(wildcard .tools/sjasmplus/bin/sjasmplus),.tools/sjasmplus/bin/sjasmplus,sjasmplus)
# On macOS the fetched build is an application bundle (tools/fetch-openmsx.sh).
OPENMSX_APP := .tools/openmsx/openMSX.app/Contents/MacOS/openmsx
OPENMSX   := $(if $(wildcard .tools/openmsx/bin/openmsx),.tools/openmsx/bin/openmsx,$(if $(wildcard $(OPENMSX_APP)),$(OPENMSX_APP),openmsx))

# Every tests/<name>/<name>.asm builds to build/<name>.com. A test may include
# modules from src/ (the build passes -Isrc); every src/ file is a prerequisite
# of every test binary, so a module edit rebuilds the tests that include it.
# The resident kernel image, src/kernel/kernel.asm, builds to build/kernel.bin
# at its own address, the switched part, src/kernel/kseg.asm, to
# build/kseg.bin, and the boot image, src/kernel/kboot.asm, to
# build/kboot.bin; a test that loads them includes the three binaries and
# the resident's exported labels.
# A test directory holding a `product` marker boots the product,
# build/m6.com, instead of a program of its own.
PRODUCT_TESTS := $(notdir $(patsubst %/,%,$(dir $(wildcard tests/*/product))))
# A test with a rom marker and a block of its own runs from the kernel ROM
# too: build/<test>.block is the block assembled for 0100h of page 0
# against the resident without the adapter, build/<test>.rom the Sunrise
# kernel ROM carrying it in bank 2 beside m6's own driver (tests/romblock.asm).
ROM_TESTS := $(notdir $(patsubst %/,%,$(dir $(wildcard tests/*/rom))))
BLOCK_TESTS := $(foreach t,$(ROM_TESTS),$(if $(wildcard tests/$(t)/block.asm),$(t)))
TEST_BLOCKS := $(foreach t,$(BLOCK_TESTS),build/$(t).block)
TEST_ROMS := $(foreach t,$(BLOCK_TESTS),build/$(t).rom)
TESTS     := $(sort $(notdir $(patsubst %/,%,$(dir $(wildcard tests/*/*.asm)))) $(PRODUCT_TESTS))
TEST_BINS := $(foreach t,$(filter-out $(PRODUCT_TESTS),$(TESTS)),build/$(t).com)
# A test may ship programs on its disk: tests/<name>/progs/<prog>.asm builds
# to build/<name>.progs/<prog>, a raw image for P0_PROG with the executable
# header (tests/m6prog.inc); tests/<name>/progs/<prog>.dest names where on
# the volume tools/run-test.sh puts it.
PROG_SRCS := $(wildcard tests/*/progs/*.asm)
PROG_BINS := $(foreach p,$(PROG_SRCS),build/$(word 2,$(subst /, ,$(p))).progs/$(basename $(notdir $(p))))
KERNEL    := build/kernel.bin
# The same resident without the Nextor adapter (M6_NOADAPTER): what a
# kernel ROM carrying a driver block of m6's own is built with; built by
# `all` so that its size is read every day.
KERNEL_NA := build/kernel-noadapter.bin
KSEG      := build/kseg.bin
# The boot image, src/kernel/kboot.asm: what runs once at boot, carried by
# every loader beside the other two and run from the loader's page 0.
KBOOT     := build/kboot.bin
# The legacy layer, src/leg/leg.asm: what a .COM program finds above its
# TPA, and the layer's body, which lives outside it — two images from one
# source, both carried inside build/bin/dos.
LEG       := build/leg.bin
LEGB      := build/legb.bin
# The base utilities: src/bin/<name>.asm builds to build/bin/<name>, a raw
# image for P0_PROG with the executable header (src/lib/prog.inc). Every
# one fits one page: a file above PAGE_MAX bytes — 16K less the 256-byte
# argument block, the kernel's 24-byte frame and the 256 bytes below the
# program — is refused, and the program's own assertion keeps its buffers
# below the same ceiling.
BIN_SRCS  := $(wildcard src/bin/*.asm)
BIN_BINS  := $(patsubst src/bin/%.asm,build/bin/%,$(BIN_SRCS))
PAGE_MAX  := 16102
# The product, with the three kernel images embedded: src/loader/m6.asm,
# run under Nextor as M6.COM, and src/loader/nextor.asm, loaded by the
# Nextor kernel ROM as NEXTOR.SYS in place of Nextor's own.
M6COM     := build/m6.com
NEXTORSYS := build/nextor.sys
# The kernel ROM, src/rom/rom.asm: m6 in the cartridge, with the bank
# switch of the Nextor kernel ROM built for that cartridge, and either a
# driver block of m6's own in the driver bank or that ROM's driver bank
# taken whole — one source, the kernel ROM and the block as its
# parameters. Three are built from the ROMs tools/fetch-nextor.sh puts in
# the ROM pool, each by `all` only when its input is there and by `check`
# always, and each checked by tools/check-rom.sh against its input: the
# Sunrise IDE ROM with m6's own driver (src/drivers/m6ide.asm) and the
# resident without the adapter, the product; the same cartridge's ROM
# with the Nextor driver bank and the adapter, `-legacy`, the way every
# ROM was built before there was a driver of m6's own; and the ASCII16
# one from Nextor's standalone kernel, whose driver has no hardware
# behind it — a test fixture, the bytes m6 writes into an SD Mapper ROM,
# booted in CI as far as a kernel with no volume. A fourth, from the
# FBLabs SD Mapper V2's own kernel ROM (SDXC110.ROM, fetched too): that
# cartridge's driver bank and the adapter, `-legacy` as the Sunrise's is,
# the ROM an SD Mapper V2 owner flashes, and the one CI boots in the
# emulated cartridge. `rom-from
# DRIVER_ROM=<file>` builds from any eight-bank Nextor kernel ROM, which
# is how the MSX-Pico+'s ROM is made from the kernel ROM its firmware
# embeds; with `DRIVER=<block.asm>` besides, bank 7 is that driver block
# instead of the input's driver bank, the resident has no adapter, the
# output's name carries the block's, and the bank's room is printed.
ROM          := build/m6-sunriseide.rom
ROM_LEGACY   := build/m6-sunriseide-legacy.rom
ROM16        := build/m6-ascii16-test.rom
ROM_SDL      := build/m6-sdmapper-legacy.rom
M6IDE        := src/drivers/m6ide.asm
ROM_POOL     := tools/openmsx/systemroms
NEXTOR_ROM   := $(ROM_POOL)/Nextor-2.1.4.SunriseIDE.ROM
NEXTOR_ROM16 := $(ROM_POOL)/Nextor-2.1.4.StandaloneASCII16.ROM
FBLABS_ROM   := $(ROM_POOL)/SDXC110.ROM
ROM_FROM      = build/m6-$(basename $(notdir $(DRIVER_ROM)))$(if $(DRIVER),-$(basename $(notdir $(DRIVER)))).rom
# The driver-contract test's ROM: the kernel ROM built from the Standalone
# ASCII16 kernel, with the pattern block in its driver bank (M6_DRIVER),
# the test itself in bank 2 after the boot image (M6_TEST) and the
# resident without the adapter, booted by tools/run-test.sh as an ASCII16
# cartridge with no disk. The block carries the first sectors of a FAT12
# volume that tests/drvrom/mkvol.py writes around the reader program.
DRVROM     := build/drvrom.rom
DRVROM_VOL := build/drvrom.vol
# The Sunrise IDE driver test's ROMs: the Sunrise kernel ROM with the
# driver and the test block (M6_TEST) in bank 2, booted by
# tools/run-test.sh in the Sunrise cartridge with a master and a slave;
# and the same test block on the ROM with the Nextor driver bank and the
# adapter, the comparison.
M6IDE_ROM  := build/m6ide.rom
M6IDE_LROM := build/m6ide-legacy.rom
SRC_FILES := $(wildcard src/*.inc src/*/*.asm src/*/*.inc)
# sjasmplus rejects an include path that does not exist, so -Isrc is passed
# only once there is a src/ to point at.
INCLUDES  := -Itests $(if $(wildcard src),-Isrc)

# An assembler that fails still writes its output; without this make would
# take that half-built file as up to date on the next run and never say so.
.DELETE_ON_ERROR:

.PHONY: all rom rom-from check check-sjasmplus check-openmsx check-tools fetch sizes clean distclean

all: check-sjasmplus $(KERNEL) $(KERNEL_NA) $(KSEG) $(KBOOT) $(LEG) $(M6COM) $(NEXTORSYS) $(if $(wildcard $(NEXTOR_ROM)),$(ROM) $(ROM_LEGACY) $(M6IDE_ROM) $(M6IDE_LROM) $(TEST_ROMS)) $(if $(wildcard $(NEXTOR_ROM16)),$(ROM16) $(DRVROM)) $(if $(wildcard $(FBLABS_ROM)),$(ROM_SDL)) $(BIN_BINS) $(TEST_BINS) $(PROG_BINS) sizes

rom: $(ROM) $(ROM_LEGACY) $(ROM16) $(ROM_SDL)

build:
	mkdir -p build

# The image also exports the labels a program needs to assemble a block for
# the address above it (build/kernel.exp, included by such a program).
$(KERNEL): src/kernel/kernel.asm tests/m6test.inc $(SRC_FILES) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) --raw=$@ --lst=build/kernel.lst --exp=build/kernel.exp $<
$(KERNEL_NA): src/kernel/kernel.asm tests/m6test.inc $(SRC_FILES) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) -DM6_NOADAPTER --raw=$@ --lst=build/kernel-noadapter.lst --exp=build/kernel-noadapter.exp $<

# The switched part of the kernel, src/kernel/kseg.asm, at its own address:
# a loader carries it and the resident copies it into a segment at boot.
$(KSEG): src/kernel/kseg.asm $(SRC_FILES) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) --raw=$@ --lst=build/kseg.lst $<

# The boot image, src/kernel/kboot.asm, at KB_BASE: a loader carries it and
# the resident copies it into the loader's page 0 at boot. The source's own
# assertion keeps it under its 4K ceiling.
$(KBOOT): src/kernel/kboot.asm $(SRC_FILES) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) --raw=$@ --lst=build/kboot.lst $<

# The layer: two raw images, written by the source's own OUTPUT lines —
# build/leg.bin at LEG_BASE and build/legb.bin, the body, at LEG_BODY. The
# source refuses a page-3 part that reaches the hinge with its variables,
# and a body that outgrows the buffers the block cache lends it; dos
# embeds both.
$(LEG): src/leg/leg.asm $(SRC_FILES) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) --lst=build/leg.lst --exp=build/leg.exp $<
$(LEGB): $(LEG)
	@test -f $@ || { rm -f $(LEG); $(MAKE) --no-print-directory $(LEG); }
build/bin/dos: $(LEG) $(LEGB)

# A pattern rule cannot say tests/%/%.asm (only the first % is the stem), so
# one explicit rule is generated per test.
define test_rule
build/$(1).com: tests/$(1)/$(1).asm $$(wildcard tests/$(1)/block.asm) tests/m6test.inc tests/m6prog.inc tests/m6util.asm $$(SRC_FILES) $$(KERNEL) $$(KSEG) $$(KBOOT) | build
	$$(SJASMPLUS) --nologo --msg=war $$(INCLUDES) --raw=$$@ --lst=build/$(1).lst $$<
endef
$(foreach t,$(TESTS),$(eval $(call test_rule,$(t))))

# One rule per program a test ships, for the same reason.
define prog_rule
build/$(1).progs/$(2): tests/$(1)/progs/$(2).asm tests/m6prog.inc $$(SRC_FILES) | build
	@mkdir -p build/$(1).progs
	$$(SJASMPLUS) --nologo --msg=war $$(INCLUDES) --raw=$$@ --lst=build/$(1).progs/$(2).lst $$<
endef
$(foreach p,$(PROG_SRCS),$(eval $(call prog_rule,$(word 2,$(subst /, ,$(p))),$(basename $(notdir $(p))))))

$(M6COM): src/loader/m6.asm $(SRC_FILES) src/version.inc $(KERNEL) $(KSEG) $(KBOOT) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) --raw=$@ --lst=build/m6.lst $<

$(NEXTORSYS): src/loader/nextor.asm $(SRC_FILES) src/version.inc $(KERNEL) $(KSEG) $(KBOOT) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) --raw=$@ --lst=build/nextor.lst $<

# The ROMs: assembled with the input's directory on the include path, which
# is where incbin finds the Nextor kernel ROM, then checked against it. A
# ROM that fails the check is removed with the build's error. Asked for
# without its input in the pool, the build says what to run instead of
# failing on a missing prerequisite.
$(NEXTOR_ROM) $(NEXTOR_ROM16):
	@echo "$@ is not there: run make fetch (tools/fetch-nextor.sh) first" >&2; exit 1
$(ROM): src/rom/rom.asm $(SRC_FILES) src/version.inc $(KERNEL_NA) $(KSEG) $(KBOOT) $(NEXTOR_ROM) tools/check-rom.sh | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) -I$(ROM_POOL) -D'M6_DRIVER="$(M6IDE)"' -D'KERNEL_BIN="$(KERNEL_NA)"' -D'KERNEL_EXP="$(KERNEL_NA:.bin=.exp)"' --raw=$@ --lst=build/rom.lst --exp=build/rom.exp $<
	@tools/check-rom.sh $@ $(NEXTOR_ROM) block
$(ROM_LEGACY): src/rom/rom.asm $(SRC_FILES) src/version.inc $(KERNEL) $(KSEG) $(KBOOT) $(NEXTOR_ROM) tools/check-rom.sh | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) -I$(ROM_POOL) --raw=$@ --lst=build/rom-legacy.lst --exp=build/rom-legacy.exp $<
	@tools/check-rom.sh $@ $(NEXTOR_ROM)
$(ROM16): src/rom/rom.asm $(SRC_FILES) src/version.inc $(KERNEL) $(KSEG) $(KBOOT) $(NEXTOR_ROM16) tools/check-rom.sh | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) -I$(ROM_POOL) -D'NEXTOR_ROM="$(notdir $(NEXTOR_ROM16))"' --raw=$@ --lst=build/rom16.lst --exp=build/rom16.exp $<
	@tools/check-rom.sh $@ $(NEXTOR_ROM16)
$(ROM_SDL): src/rom/rom.asm $(SRC_FILES) src/version.inc $(KERNEL) $(KSEG) $(KBOOT) $(FBLABS_ROM) tools/check-rom.sh | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) -I$(ROM_POOL) -D'NEXTOR_ROM="$(notdir $(FBLABS_ROM))"' --raw=$@ --lst=build/rom-sd-legacy.lst --exp=build/rom-sd-legacy.exp $<
	@tools/check-rom.sh $@ $(FBLABS_ROM)
# The driver-contract test's ROM and the volume its driver carries
# (DRVROM, above).
$(DRVROM_VOL): tests/drvrom/mkvol.py tests/drvrom/layout.inc build/drvrom.progs/reader | build
	python3 -I tests/drvrom/mkvol.py $@ build/drvrom.progs/reader
$(DRVROM): src/rom/rom.asm $(SRC_FILES) src/version.inc $(KERNEL_NA) $(KSEG) $(KBOOT) $(NEXTOR_ROM16) tools/check-rom.sh tests/drvrom/pattern.asm tests/drvrom/block.asm tests/drvrom/layout.inc tests/m6util.asm $(DRVROM_VOL) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) -I$(ROM_POOL) -D'NEXTOR_ROM="$(notdir $(NEXTOR_ROM16))"' -D'M6_DRIVER="tests/drvrom/pattern.asm"' -D'M6_TEST="tests/drvrom/block.asm"' -D'KERNEL_BIN="$(KERNEL_NA)"' -D'KERNEL_EXP="$(KERNEL_NA:.bin=.exp)"' --raw=$@ --lst=build/drvrom.lst --exp=build/drvrom.exp $<
	@tools/check-rom.sh $@ $(NEXTOR_ROM16) block
# The Sunrise IDE driver test's ROMs (M6IDE_ROM, M6IDE_LROM, above).
$(M6IDE_ROM): src/rom/rom.asm $(SRC_FILES) src/version.inc $(KERNEL_NA) $(KSEG) $(KBOOT) $(NEXTOR_ROM) tools/check-rom.sh tests/m6ide/block.asm tests/m6util.asm | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) -I$(ROM_POOL) -D'M6_DRIVER="$(M6IDE)"' -D'M6_TEST="tests/m6ide/block.asm"' -D'KERNEL_BIN="$(KERNEL_NA)"' -D'KERNEL_EXP="$(KERNEL_NA:.bin=.exp)"' --raw=$@ --lst=build/m6ide.lst --exp=build/m6ide.exp $<
	@tools/check-rom.sh $@ $(NEXTOR_ROM) block
$(M6IDE_LROM): src/rom/rom.asm $(SRC_FILES) src/version.inc $(KERNEL) $(KSEG) $(KBOOT) $(NEXTOR_ROM) tools/check-rom.sh tests/m6ide-legacy/block.asm tests/m6ide/block.asm tests/m6util.asm | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) -I$(ROM_POOL) -D'M6_TEST="tests/m6ide-legacy/block.asm"' --raw=$@ --lst=build/m6ide-legacy.lst --exp=build/m6ide-legacy.exp $<
	@tools/check-rom.sh $@ $(NEXTOR_ROM)
# A test's block for the ROM, and the ROM: one rule per test with a rom
# marker and a block (ROM_TESTS, above).
define block_rule
build/$(1).block: tests/romblock.asm tests/$(1)/block.asm tests/m6test.inc tests/m6prog.inc tests/m6util.asm $$(SRC_FILES) $$(KERNEL_NA) | build
	$$(SJASMPLUS) --nologo --msg=war $$(INCLUDES) -D'M6_BLOCK="tests/$(1)/block.asm"' --raw=$$@ --lst=build/$(1).block.lst $$<
build/$(1).rom: src/rom/rom.asm $$(SRC_FILES) src/version.inc $$(KERNEL_NA) $$(KSEG) $$(KBOOT) $$(NEXTOR_ROM) tools/check-rom.sh build/$(1).block | build
	$$(SJASMPLUS) --nologo --msg=war $$(INCLUDES) -I$$(ROM_POOL) -D'M6_DRIVER="$$(M6IDE)"' -D'M6_TEST_BIN="build/$(1).block"' -D'KERNEL_BIN="$$(KERNEL_NA)"' -D'KERNEL_EXP="$$(KERNEL_NA:.bin=.exp)"' --raw=$$@ --lst=build/$(1).rom.lst --exp=build/$(1).rom.exp $$<
	@tools/check-rom.sh $$@ $$(NEXTOR_ROM) block
endef
$(foreach t,$(BLOCK_TESTS),$(eval $(call block_rule,$(t))))
# Any other cartridge: the kernel ROM given by path, the output named after
# it, in build/ beside the other two, never over one of them; nothing of
# the input is kept. The target is phony, so .DELETE_ON_ERROR does not
# reach the output: a failed step removes it itself.
rom-from: $(KERNEL) $(KERNEL_NA) $(KSEG) $(KBOOT) tools/check-rom.sh | build
	@[ -n "$(DRIVER_ROM)" ] || { echo "usage: make rom-from DRIVER_ROM=<eight-bank Nextor kernel ROM> [DRIVER=<driver block .asm>]" >&2; exit 2; }
	@case "$(DRIVER_ROM)$(DRIVER)" in *" "*) echo "$(DRIVER_ROM) $(DRIVER): a path must not contain a space (the assembler takes the name as a definition)" >&2; exit 2 ;; esac
	@[ -f "$(DRIVER_ROM)" ] || { echo "$(DRIVER_ROM): no such file" >&2; exit 2; }
	@[ -z "$(DRIVER)" ] || [ -f "$(DRIVER)" ] || { echo "$(DRIVER): no such file" >&2; exit 2; }
	@case "$(ROM_FROM)" in $(ROM)|$(ROM_LEGACY)|$(ROM16)|$(ROM_SDL)) echo "$(DRIVER_ROM): would be built as $(ROM_FROM), which make rom owns; rename the input" >&2; exit 2 ;; esac
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) -I$(dir $(DRIVER_ROM)) -D'NEXTOR_ROM="$(notdir $(DRIVER_ROM))"' $(if $(DRIVER),-D'M6_DRIVER="$(DRIVER)"' -D'KERNEL_BIN="$(KERNEL_NA)"' -D'KERNEL_EXP="$(KERNEL_NA:.bin=.exp)"') --raw=$(ROM_FROM) --lst=$(ROM_FROM:.rom=.lst) --exp=$(ROM_FROM:.rom=.exp) src/rom/rom.asm || { rm -f $(ROM_FROM); exit 1; }
	@tools/check-rom.sh $(ROM_FROM) $(DRIVER_ROM) $(if $(DRIVER),block) || { rm -f $(ROM_FROM); exit 1; }
	@echo "rom-from: $(ROM_FROM)"
	@[ -z "$(DRIVER)" ] || { v=$$(sed -n "s/^ROM_B7_FREE: EQU 0x0*\([0-9A-Fa-f]*\)$$/\1/p" $(ROM_FROM:.rom=.exp)); printf 'ROOM rom-bank7 %d\n' $$(( 0x$${v:-0} )); }

# One rule per utility, with the one-page check.
define bin_rule
build/bin/$(1): src/bin/$(1).asm $$(SRC_FILES) | build
	@mkdir -p build/bin
	$$(SJASMPLUS) --nologo --msg=war $$(INCLUDES) --raw=$$@ --lst=build/bin/$(1).lst $$<
	@s=$$$$(wc -c < $$@ | tr -d ' '); [ "$$$$s" -le $(PAGE_MAX) ] || { \
	    echo "$$@ is $$$$s bytes: a base utility fits one page ($(PAGE_MAX) at most)" >&2; rm -f $$@; exit 1; }
endef
$(foreach b,$(patsubst src/bin/%.asm,%,$(BIN_SRCS)),$(eval $(call bin_rule,$(b))))

# One line per binary, "SIZE <name> <bytes>": what the build reports today
# and what size limits are later checked against. kernel.bin is the resident
# image, the number the 16K target is measured against; kseg.bin the
# switched part, against the window's 16K; kboot.bin the boot image,
# against its 4K. Then "ROOM kernel <bytes>": what
# the resident leaves below the address it must end under, read from the
# labels the image exports; and, when the ROM was built, "ROOM rom-bankN
# <bytes>" for its four filled banks, what each leaves before CHGBNK —
# banks 0 to 2 the same for every input, so read from the Sunrise build
# alone, bank 7 the room the Sunrise driver leaves.
sizes: $(KERNEL) $(KERNEL_NA) $(KSEG) $(KBOOT) $(LEG) $(M6COM) $(NEXTORSYS) $(if $(wildcard $(NEXTOR_ROM)),$(ROM) $(ROM_LEGACY)) $(if $(wildcard $(NEXTOR_ROM16)),$(ROM16)) $(if $(wildcard $(FBLABS_ROM)),$(ROM_SDL)) $(BIN_BINS) $(TEST_BINS) $(PROG_BINS)
	@for f in $(KERNEL) $(KERNEL_NA) $(KSEG) $(KBOOT) $(LEG) $(LEGB) $(M6COM) $(NEXTORSYS) $(wildcard $(ROM) $(ROM_LEGACY) $(ROM16) $(ROM_SDL)) $(BIN_BINS) $(TEST_BINS) $(PROG_BINS); do \
	    printf 'SIZE %s %s\n' "$$(basename $$f)" "$$(wc -c < $$f | tr -d ' ')"; \
	done
	@for k in kernel kernel-noadapter; do \
	    roof=$$(sed -n 's/^K_IMAGE_ROOF: EQU 0x0*\([0-9A-Fa-f]*\)$$/\1/p' build/$$k.exp); \
	    end=$$(sed -n 's/^K_IMAGE_END: EQU 0x0*\([0-9A-Fa-f]*\)$$/\1/p' build/$$k.exp); \
	    printf 'ROOM %s %d\n' "$$k" $$(( 0x$$roof - 0x$$end )); \
	done
	@if [ -f build/rom.exp ]; then for b in 0 1 2 7; do \
	    v=$$(sed -n "s/^ROM_B$${b}_FREE: EQU 0x0*\([0-9A-Fa-f]*\)$$/\1/p" build/rom.exp); \
	    printf 'ROOM rom-bank%s %d\n' "$$b" $$(( 0x$${v:-0} )); \
	done; fi
	@if [ -f build/drvrom.exp ]; then \
	    printf 'SIZE drvrom.rom %s\n' "$$(wc -c < $(DRVROM) | tr -d ' ')"; \
	    v=$$(sed -n "s/^ROM_B7_FREE: EQU 0x0*\([0-9A-Fa-f]*\)$$/\1/p" build/drvrom.exp); \
	    printf 'ROOM drvrom-bank7 %d\n' $$(( 0x$${v:-0} )); \
	fi
	@for l in LEG_ROOM LEGB_ROOM; do \
	    v=$$(sed -n "s/^$$l: EQU 0x0*\([0-9A-Fa-f]*\)$$/\1/p" build/leg.exp); \
	    printf 'ROOM %s %d\n' "$$(echo $$l | sed 's/_ROOM//' | tr A-Z a-z)" $$(( 0x$${v:-0} )); \
	done

check-sjasmplus:
	@v=$$($(SJASMPLUS) --nologo --version 2>&1 || true); \
	[ "$$v" = "$(SJASMPLUS_VERSION)" ] || { \
	    echo "sjasmplus $(SJASMPLUS_VERSION) required, found '$$v' via $(SJASMPLUS); run tools/fetch-sjasmplus.sh" >&2; exit 1; }

check-openmsx:
	@v=$$($(OPENMSX) --version 2>/dev/null | sed -n '1s/^openMSX \([0-9][0-9.a-z-]*\).*/\1/p'); \
	[ "$$v" = "$(OPENMSX_VERSION)" ] || { \
	    echo "openMSX $(OPENMSX_VERSION) required, found '$$v' via $(OPENMSX); run tools/fetch-openmsx.sh" >&2; exit 1; }

check-tools: check-sjasmplus check-openmsx

fetch:
	tools/fetch-sjasmplus.sh
	tools/fetch-openmsx.sh
	tools/fetch-cbios.sh
	tools/fetch-nextor.sh

# The one command: tools, build, every test in name order, stop at the first
# failure, summary.
check: fetch
	@$(MAKE) --no-print-directory all $(ROM) $(ROM_LEGACY) $(ROM16) $(ROM_SDL) $(DRVROM) $(M6IDE_ROM) $(M6IDE_LROM) $(TEST_ROMS) check-tools
	@tools/check-version.sh
	@tools/check-headers.sh
	@tools/check-leg.sh
	@set -e; n=0; for t in $(TESTS); do \
	    echo "TEST $$t"; tools/run-test.sh $$t; n=$$((n + 1)); \
	done; echo "OK: $$n test(s) passed"

clean:
	rm -rf build

distclean: clean
	rm -rf .tools tools/openmsx/systemroms/*.rom tools/openmsx/systemroms/*.ROM

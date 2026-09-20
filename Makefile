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
OPENMSX_VERSION   := 21.0

SJASMPLUS := $(if $(wildcard .tools/sjasmplus/bin/sjasmplus),.tools/sjasmplus/bin/sjasmplus,sjasmplus)
OPENMSX   := $(if $(wildcard .tools/openmsx/bin/openmsx),.tools/openmsx/bin/openmsx,openmsx)

# Every tests/<name>/<name>.asm builds to build/<name>.com. A test may include
# modules from src/ (the build passes -Isrc); every src/ file is a prerequisite
# of every test binary, so a module edit rebuilds the tests that include it.
# The resident kernel image, src/kernel/kernel.asm, builds to build/kernel.bin
# at its own address, and the switched part, src/kernel/kseg.asm, to
# build/kseg.bin; a test that loads them includes both binaries and the
# resident's exported labels.
# A test directory holding a `product` marker boots the product,
# build/m6.com, instead of a program of its own.
PRODUCT_TESTS := $(notdir $(patsubst %/,%,$(dir $(wildcard tests/*/product))))
TESTS     := $(sort $(notdir $(patsubst %/,%,$(dir $(wildcard tests/*/*.asm)))) $(PRODUCT_TESTS))
TEST_BINS := $(foreach t,$(filter-out $(PRODUCT_TESTS),$(TESTS)),build/$(t).com)
# A test may ship programs on its disk: tests/<name>/progs/<prog>.asm builds
# to build/<name>.progs/<prog>, a raw image for P0_PROG with the executable
# header (tests/m6prog.inc); tests/<name>/progs/<prog>.dest names where on
# the volume tools/run-test.sh puts it.
PROG_SRCS := $(wildcard tests/*/progs/*.asm)
PROG_BINS := $(foreach p,$(PROG_SRCS),build/$(word 2,$(subst /, ,$(p))).progs/$(basename $(notdir $(p))))
KERNEL    := build/kernel.bin
KSEG      := build/kseg.bin
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
# The product: src/loader/m6.asm with both kernel images embedded.
M6COM     := build/m6.com
SRC_FILES := $(wildcard src/*.inc src/*/*.asm src/*/*.inc)
# sjasmplus rejects an include path that does not exist, so -Isrc is passed
# only once there is a src/ to point at.
INCLUDES  := -Itests $(if $(wildcard src),-Isrc)

# An assembler that fails still writes its output; without this make would
# take that half-built file as up to date on the next run and never say so.
.DELETE_ON_ERROR:

.PHONY: all check check-sjasmplus check-openmsx check-tools fetch sizes clean distclean

all: check-sjasmplus $(KERNEL) $(KSEG) $(LEG) $(M6COM) $(BIN_BINS) $(TEST_BINS) $(PROG_BINS) sizes

build:
	mkdir -p build

# The image also exports the labels a program needs to assemble a block for
# the address above it (build/kernel.exp, included by such a program).
$(KERNEL): src/kernel/kernel.asm tests/m6test.inc $(SRC_FILES) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) --raw=$@ --lst=build/kernel.lst --exp=build/kernel.exp $<

# The switched part of the kernel, src/kernel/kseg.asm, at its own address:
# a loader carries it and the resident copies it into a segment at boot.
$(KSEG): src/kernel/kseg.asm $(SRC_FILES) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) --raw=$@ --lst=build/kseg.lst $<

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
build/$(1).com: tests/$(1)/$(1).asm tests/m6test.inc $$(SRC_FILES) $$(KERNEL) $$(KSEG) | build
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

$(M6COM): src/loader/m6.asm $(SRC_FILES) src/version.inc $(KERNEL) $(KSEG) | build
	$(SJASMPLUS) --nologo --msg=war $(INCLUDES) --raw=$@ --lst=build/m6.lst $<

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
# switched part, against the window's 16K. Then "ROOM kernel <bytes>": what
# the resident leaves below the address it must end under, read from the
# labels the image exports.
sizes: $(KERNEL) $(KSEG) $(LEG) $(M6COM) $(BIN_BINS) $(TEST_BINS) $(PROG_BINS)
	@for f in $(KERNEL) $(KSEG) $(LEG) $(LEGB) $(M6COM) $(BIN_BINS) $(TEST_BINS) $(PROG_BINS); do \
	    printf 'SIZE %s %s\n' "$$(basename $$f)" "$$(wc -c < $$f | tr -d ' ')"; \
	done
	@roof=$$(sed -n 's/^K_IMAGE_ROOF: EQU 0x0*\([0-9A-Fa-f]*\)$$/\1/p' build/kernel.exp); \
	end=$$(sed -n 's/^K_IMAGE_END: EQU 0x0*\([0-9A-Fa-f]*\)$$/\1/p' build/kernel.exp); \
	printf 'ROOM kernel %d\n' $$(( 0x$$roof - 0x$$end ))
	@for l in LEG_ROOM LEGB_ROOM; do \
	    v=$$(sed -n "s/^$$l: EQU 0x0*\([0-9A-Fa-f]*\)$$/\1/p" build/leg.exp); \
	    printf 'ROOM %s %d\n' "$$(echo $$l | sed 's/_ROOM//' | tr A-Z a-z)" $$(( 0x$${v:-0} )); \
	done

check-sjasmplus:
	@v=$$($(SJASMPLUS) --nologo --version 2>&1 || true); \
	[ "$$v" = "$(SJASMPLUS_VERSION)" ] || { \
	    echo "sjasmplus $(SJASMPLUS_VERSION) required, found '$$v' via $(SJASMPLUS); run tools/fetch-sjasmplus.sh" >&2; exit 1; }

check-openmsx:
	@v=$$($(OPENMSX) --version 2>/dev/null | sed -n '1s/^openMSX \([0-9][0-9.]*\).*/\1/p'); \
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
	@$(MAKE) --no-print-directory all check-tools
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

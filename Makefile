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

# Every tests/<name>/<name>.asm builds to build/<name>.com.
TESTS     := $(notdir $(patsubst %/,%,$(dir $(wildcard tests/*/*.asm))))
TEST_BINS := $(foreach t,$(TESTS),build/$(t).com)

.PHONY: all check check-sjasmplus check-openmsx check-tools fetch sizes clean distclean

all: check-sjasmplus $(TEST_BINS) sizes

build:
	mkdir -p build

# A pattern rule cannot say tests/%/%.asm (only the first % is the stem), so
# one explicit rule is generated per test.
define test_rule
build/$(1).com: tests/$(1)/$(1).asm tests/m6test.inc | build
	$$(SJASMPLUS) --nologo --msg=war -Itests --raw=$$@ --lst=build/$(1).lst $$<
endef
$(foreach t,$(TESTS),$(eval $(call test_rule,$(t))))

# One line per binary, "SIZE <name> <bytes>": what the build reports today
# and what size limits are later checked against.
sizes: $(TEST_BINS)
	@for f in $(TEST_BINS); do \
	    printf 'SIZE %s %s\n' "$$(basename $$f)" "$$(wc -c < $$f | tr -d ' ')"; \
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
	@set -e; n=0; for t in $(TESTS); do \
	    echo "TEST $$t"; tools/run-test.sh $$t; n=$$((n + 1)); \
	done; echo "OK: $$n test(s) passed"

clean:
	rm -rf build

distclean: clean
	rm -rf .tools tools/openmsx/systemroms/*.rom tools/openmsx/systemroms/*.ROM

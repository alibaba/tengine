# Stand-alone unit tests for the HTTP/2 connection flow control fix
# (CVE-2026-123007).
#
# The Python driver extracts the complete production functions from
# src/http/v2 into temporary build artifacts and compiles them against
# minimal stubs, so nothing here requires a built tengine or a configure.
# Production sources are never modified.
#
#   make            - run the unit tests and the patch-omission controls
#   make SANITIZE=  - run without the sanitizers
#
# The fix guards a window accounting error that led to memory corruption,
# so the extracted functions run under AddressSanitizer and
# UndefinedBehaviorSanitizer by default.
#
# With an existing make build, H2_INTEGRATION_NEGATIVE=1 additionally
# verifies that tests/nginx-tests/tengine-tests/h2_flow_control.t detects
# a binary rebuilt without the window check.

CC       ?= cc
SANITIZE ?= -fsanitize=address,undefined -fno-sanitize-recover=all \
            -fno-omit-frame-pointer

.PHONY: all check

all: check

check:
	CC="$(CC)" CFLAGS="$(SANITIZE)" \
	python3 -m unittest discover -v -s .

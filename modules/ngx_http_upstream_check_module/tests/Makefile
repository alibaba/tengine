# Stand-alone unit tests for the upstream health-check parsers.
#
# Each test binary stubs the handful of ngx primitives its parser header needs,
# so nothing here requires a built tengine.
#
#   make        - build and run every test
#   make clean  - remove the built binaries
#
# Adding a test: drop test_<name>.c next to the header it exercises and append
# the pair below. The CI job runs a plain `make -C` on this directory, so a test
# that is not reachable from the default target never runs.

CC      ?= cc
CFLAGS  ?= -Wall -Wextra -Werror -g -O0

BINS    := test_check_http_parse test_check_send_parse

.PHONY: all check clean

all: check

test_check_http_parse: test_check_http_parse.c \
                       ../ngx_http_upstream_check_http_parse.h
	$(CC) $(CFLAGS) -o $@ $<

test_check_send_parse: test_check_send_parse.c \
                       ../ngx_upstream_check_send_parse.h
	$(CC) $(CFLAGS) -o $@ $<

# Runs every binary; fails the target if any of them fails, after running all.
check: $(BINS)
	@rc=0; \
	for t in $(BINS); do \
		echo "== ./$$t"; \
		./$$t || rc=1; \
	done; \
	exit $$rc

clean:
	rm -f $(BINS)

# Stand-alone unit tests for the xquic key file and certificate conf helpers.
#
#   make        - build and run the tests
#   make clean  - remove the built binaries

CC      ?= cc
CFLAGS  ?= -Wall -Wextra -Werror -g -O0

BINS    := test_xquic_read_file_data test_xquic_ssl_conf

.PHONY: all check clean

all: check

test_xquic_read_file_data: test_xquic_read_file_data.c ../../ngx_xquic_file.h
	$(CC) $(CFLAGS) -o $@ $<

test_xquic_ssl_conf: test_xquic_ssl_conf.c ../../ngx_xquic_ssl_conf.h
	$(CC) $(CFLAGS) -o $@ $<

check: $(BINS)
	@for b in $(BINS); do echo "==> $$b"; ./$$b || exit 1; done

clean:
	rm -f $(BINS)

# Stand-alone unit tests for the upstream health-check HTTP response parsers.
#
#   make        - build and run the tests
#   make clean  - remove the built binary

CC      ?= cc
CFLAGS  ?= -Wall -Wextra -Werror -g -O0

BIN     := test_check_http_parse
SRC     := test_check_http_parse.c
HDR     := ../ngx_http_upstream_check_http_parse.h

.PHONY: all check clean

all: check

$(BIN): $(SRC) $(HDR)
	$(CC) $(CFLAGS) -o $@ $(SRC)

check: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)

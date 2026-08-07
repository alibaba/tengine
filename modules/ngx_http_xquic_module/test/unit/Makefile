# Stand-alone unit tests for the xquic key file helper.
#
#   make        - build and run the tests
#   make clean  - remove the built binary

CC      ?= cc
CFLAGS  ?= -Wall -Wextra -Werror -g -O0

BIN     := test_xquic_read_file_data
SRC     := test_xquic_read_file_data.c
HDR     := ../../ngx_xquic_file.h

.PHONY: all check clean

all: check

$(BIN): $(SRC) $(HDR)
	$(CC) $(CFLAGS) -o $@ $(SRC)

check: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)

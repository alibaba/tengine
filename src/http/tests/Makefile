# Stand-alone send-chain progress and rate accounting tests.
# Complete production functions are extracted; no configure is needed.
CC       ?= cc
SANITIZE ?= -fsanitize=address,undefined -fno-sanitize-recover=all \
            -fno-omit-frame-pointer

.PHONY: all check
all: check

check:
	CC="$(CC)" CFLAGS="$(CFLAGS) $(SANITIZE)" \
	python3 -B -m unittest discover -v -s .

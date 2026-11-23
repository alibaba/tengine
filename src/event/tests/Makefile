# Stand-alone SSL error log policy tests and patch-omission controls.
# Extracts the complete production function; no configure is needed.

CC       ?= cc
SANITIZE ?= -fsanitize=address,undefined -fno-sanitize-recover=all \
            -fno-omit-frame-pointer

.PHONY: all check
all: check

check:
	CC="$(CC)" CFLAGS="$(CFLAGS) $(SANITIZE)" \
	python3 -m unittest discover -v -s .

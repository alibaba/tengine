# Stand-alone unit tests for the hessian2 codec of mod_dubbo.
#
# The tests link the codec sources the module ships, with a stub ngx_config.h
# (stub/), so nothing here requires a built tengine.
#
#   make                 - build and run every test, under AddressSanitizer
#   make SANITIZE=       - the same without a sanitizer
#   make clean           - remove the built binaries
#
# The sanitizer is on by default because the decoder bugs these tests guard
# against are memory errors -- reads past the payload, and a dereference of
# the NULL read_utf8_string() hands back for a null tag: the tests also detect
# them without it, but ASan points at the exact access.
#
# Adding a test: drop test_<name>.cc here and append it to BINS. The CI job
# runs a plain `make -C` on this directory, so a test that is not reachable
# from the default target never runs.

CXX       ?= c++
CXXFLAGS  ?= -Wall -g -O0
SANITIZE  ?= -fsanitize=address -fno-omit-frame-pointer

MOD       := ..
INCS      := -Istub -I$(MOD)/utils -I$(MOD)/hessian2

# the codec as listed in ../config, minus the nginx glue
CODEC     := $(MOD)/utils/objects.cc \
             $(MOD)/utils/utils.cc \
             $(MOD)/hessian2/hessian2_ext.cc \
             $(MOD)/hessian2/hessian2_input.cc \
             $(MOD)/hessian2/hessian2_output.cc

CODEC_HDRS := $(wildcard $(MOD)/utils/*.h $(MOD)/hessian2/*.h) stub/ngx_config.h

BINS      := test_hessian2_input test_hessian2_read_map test_hessian2_type_confusion \
             test_hessian2_output test_hessian2_depth test_hessian2_bytes \
             test_hessian2_null_ref

.PHONY: all check clean

all: check

# one binary per test_<name>.cc, each linked against the whole codec
$(BINS): %: %.cc $(CODEC) $(CODEC_HDRS)
	$(CXX) $(CXXFLAGS) $(SANITIZE) $(INCS) -o $@ $< $(CODEC)

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
	rm -rf *.dSYM

all: clean kern_xquic.o

.PHONY: config


config:
	echo $(root) > config

kern_xquic.o:
	make -C $(shell cat config) kern srcdir=$(shell pwd)  target=kern_xquic.o

test: kern_xquic.o
	gcc test.c -l xudp -o test


clean:
	-@rm *.o 2>/dev/null || true

rpm:
	rm -rf ~/rpmbuild
	rpmdev-setuptree
	cp * ~/rpmbuild/BUILD
	rpmbuild -ba xquic_xdp.spec

Introduction
===
APKBUILD files to build tengine .apk package for [Alpine Linux](https://www.alpinelinux.org).

Build
===
To build the package in alpine linux, install alpine-sdk and depends listed in the APKBUILD file, cd to APKBUILD directory and run:
```
abuild checksum && abuild -r
```

Reference
===
* Detailed [abuild instuctions](https://wiki.alpinelinux.org/wiki/Abuild_and_Helpers)
* APKBUILD file for [Alpine nginx ports](https://github.com/alpinelinux/aports/tree/master/main/nginx)
* Docker image of abuild tools[docker abuild image](https://hub.docker.com/r/andyshinn/alpine-abuild/)

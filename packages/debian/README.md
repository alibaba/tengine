Installation
===

##  build the deb package   
1. install some basic packages

```
aptitude install build-essential debhelper make autoconf automake patch \
 dpkg-dev fakeroot pbuilder gnupg dh-make libssl-dev libpcre3-dev      
```

2. build package     
change to source directory

```
mv packages/debian .
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -rfakeroot -uc -b
```

## install the deb package 
replace the deb name with the current version

```
sudo dpkg -i tengine_2.0.2-1_amd64.deb
```


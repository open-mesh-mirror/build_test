#! /bin/sh
set -e
rm -f linux-build.img
rm -rf linux-build
mkdir -p linux-build
mv linux-2.6.* linux-build
mv linux-3* linux-build
mv linux-4* linux-build
mksquashfs linux-build linux-build.img
rm -rf linux-build
echo ok

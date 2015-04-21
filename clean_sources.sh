#! /bin/sh

# download and prepare source for 2.6.9 - 3.1:
# make allnoconfig
# grep -v CONFIG_MODULES .config > config; mv config .config
# echo "CONFIG_MODULES=y" >> .config
# make prepare
# make modules

set -e

for i in linux-2.6* linux-3.* linux-4.*; do
(
	test -d "$i" && cd "$i"  && (
	find . -iname "*.S" -print0 | xargs --null rm -f
	find . -iname "*.c" -print0 | xargs --null rm -f
	find . -iname "*.o" -print0 | xargs --null rm -f
	find . -iname "*.cmd" -not -iname "auto.conf.cmd" -print0 | xargs --null rm -f
	find . -iname "modules.order" -print0 | xargs --null rm -f
	find . -iname "vmlinu*" -not -iname "*.h" -print0 | xargs --null rm -f
	find arch -maxdepth 1 -type d -not -iname i386 -not -iname x86_64 -not -iname x86 -not -iname arch -print0 | xargs --null rm -rf
	find include -maxdepth 1 -type d -iname "asm-*" -not -iname asm-i386 -not -iname asm-x86_64 -not -iname asm-x86 -not -iname asm-generic  -not -iname include -print0 | xargs --null rm -rf
	rm -rf Documentation
	rm -f linux
	find |grep -v '/include/'|grep -v '/arch/'|grep "\.h$"|xargs -d '\n' rm -f
	rm -f .config.old
	) || true
)
done

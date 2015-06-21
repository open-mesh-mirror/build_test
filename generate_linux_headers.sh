#! /bin/bash
set -e

LINUX_REPOSITORY=${LINUX_REPOSITORY:="git+ssh://git@git.open-mesh.org/linux-merge.git"}

prepare_source()
{
	make allnoconfig
	grep -v 'CONFIG_MODULES is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_NET is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_DEBUG_STRICT_USER_COPY_CHECKS is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_SPARSE_RCU_POINTER is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_ENABLE_MUST_CHECK is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_ENABLE_WARN_DEPRECATED is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_CRC16 is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_DEBUG_FS is not set' .config > .config.tmp; mv .config.tmp .config
	if [ "$3" != "smp" ]; then
		grep -v 'CONFIG_SMP is not set' .config > .config.tmp; mv .config.tmp .config
		grep -v 'CONFIG_MODULE_UNLOAD is not set' .config > .config.tmp; mv .config.tmp .config
		echo 'CONFIG_SMP=y' >> .config
		echo 'CONFIG_MODULE_UNLOAD=y' >> .config
	fi
	echo 'CONFIG_MODULES=y' >> .config
	echo 'CONFIG_NET=y' >> .config
	echo 'CONFIG_DEBUG_STRICT_USER_COPY_CHECKS=y' >> .config
	echo 'CONFIG_SPARSE_RCU_POINTER=y' >> .config
	echo 'CONFIG_ENABLE_MUST_CHECK=y' >> .config
	echo 'CONFIG_ENABLE_WARN_DEPRECATED=y' >> .config
	echo 'CONFIG_CRC16=y' >> .config
	echo 'CONFIG_DEBUG_FS=y' >> .config
	if [ "$1" = "2.6" -a \( "$2" = "29" -o "$2" = "30" -o "$2" = "31" -o "$2" = "32" -o "$2" = "33" -o "$2" = "34" -o "$2" = "35" \) ]; then
		echo 'xy'|make menuconfig
	else
		make oldnoconfig
	fi
	make prepare
	make modules
}

clean_source()
{
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
}

generate_squashfs()
{
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
}

for i in `seq 29 39`; do
	#wget "http://www.kernel.org/pub/linux/kernel/v2.6/linux-2.6.${i}.tar.gz"
	#tar xfz "linux-2.6.${i}.tar.gz"
	#rm "linux-2.6.${i}.tar.gz"
	git archive --remote="${LINUX_REPOSITORY}" --format tar --prefix=linux-2.6.${i}/ v2.6.${i}|tar x
	(
		cd "linux-2.6.${i}" || exit
		if [ "$i" = 29 -o "$i" = 30 -o "$i" = 31 -o "$i" = 32 -o "$i" = 33 -o "$i" = 34 -o "$i" = 35 -o "$i" = 36 ]; then
			sed -i 's/^\(KBUILD_CFLAGS[[:space:]]*:=\)[[:space:]]*\(-Wall\)/\1 -Wno-unused-but-set-variable \2/' Makefile
		fi
		if [ "$i" != 32 -a "$i" != 33 ]; then
			SMP=smp
		else
			SMP=nosmp
		fi
		prepare_source "2.6" "${i}" "$SMP"
		if [ -d "../patches/v2.6.${i}" ]; then
			for p in "../patches/v2.6.${i}/"*.patch; do
				patch -p1 -i "${p}"
			done
		fi

		clean_source
	)
done

for i in `seq 0 19`; do
	git archive --remote="${LINUX_REPOSITORY}" --format tar --prefix=linux-3.${i}/ v3.${i}|tar x
	(
		cd "linux-3.${i}" || exit
		SMP=smp
		prepare_source "3" "${i}" "$SMP"
		if [ -d "../patches/v3.${i}" ]; then
			for p in "../patches/v3.${i}/"*.patch; do
				patch -p1 -i "${p}"
			done
		fi

		clean_source
	)
done

for i in `seq 0 0`; do
	git archive --remote="${LINUX_REPOSITORY}" --format tar --prefix=linux-4.${i}/ v4.${i}|tar x
	(
		cd "linux-4.${i}" || exit
		SMP=smp
		prepare_source "4" "${i}" "$SMP"
		if [ -d "../patches/v4.${i}" ]; then
			for p in "../patches/v4.${i}/"*.patch; do
				patch -p1 -i "${p}"
			done
		fi

		clean_source
	)
done

generate_squashfs

echo "done"

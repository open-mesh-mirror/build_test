#! /bin/bash
set -e

LINUX_REPOSITORY=${LINUX_REPOSITORY:="git+ssh://git@git.open-mesh.org/linux-merge.git"}
MAKE_AMD64=${MAKE_AMD64:=1}

if [ -e "linux-build.img" ]; then
	echo "Please delete linux-build.img before running this script"
	exit 1
fi

if mountpoint -q -- "linux-build"; then
	echo "Please umount linux-build before running this script"
	exit 1
fi

prepare_source()
{
	if [ -e include/linux/compiler-gcc4.h -a ! -e include/linux/compiler-gcc5.h ]; then
		ln -s compiler-gcc4.h include/linux/compiler-gcc5.h
	fi

	make allnoconfig
	grep -v 'CONFIG_MODULES is not set' .config > .config.tmp; mv .config.tmp .config
	if [ "${MAKE_AMD64}" != "0" ]; then
		grep -v 'CONFIG_64BIT is not set' .config > .config.tmp; mv .config.tmp .config
		grep -v 'CONFIG_X86_32=y' .config > .config.tmp; mv .config.tmp .config
	fi
	grep -v 'CONFIG_NET is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_DEBUG_STRICT_USER_COPY_CHECKS is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_SPARSE_RCU_POINTER is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_ENABLE_MUST_CHECK is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_ENABLE_WARN_DEPRECATED is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_CRC16 is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_DEBUG_FS is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_INET is not set' .config > .config.tmp; mv .config.tmp .config
	grep -v 'CONFIG_CFG80211 is not set' .config > .config.tmp; mv .config.tmp .config
	echo 'CONFIG_MODULES=y' >> .config
	if [ "${MAKE_AMD64}" != "0" ]; then
		echo 'CONFIG_64BIT=y' >> .config
		echo 'CONFIG_X86_64=y' >> .config
	fi
	echo 'CONFIG_NET=y' >> .config
	echo 'CONFIG_DEBUG_STRICT_USER_COPY_CHECKS=y' >> .config
	echo 'CONFIG_SPARSE_RCU_POINTER=y' >> .config
	echo 'CONFIG_ENABLE_MUST_CHECK=y' >> .config
	echo 'CONFIG_ENABLE_WARN_DEPRECATED=y' >> .config
	echo 'CONFIG_CRC16=y' >> .config
	echo 'CONFIG_DEBUG_FS=y' >> .config
	echo 'CONFIG_INET=y' >> .config
	echo 'CONFIG_CFG80211=y' >> .config
	make oldnoconfig
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
	mv linux-3* linux-build
	mv linux-4* linux-build
	mksquashfs linux-build linux-build.img
	rm -rf linux-build
	echo ok
}

for i in `seq 2 19`; do
	git archive --remote="${LINUX_REPOSITORY}" --format tar --prefix=linux-3.${i}/ v3.${i}|tar x
	(
		cd "linux-3.${i}" || exit
		prepare_source "3" "${i}"
		if [ -d "../patches/v3.${i}" ]; then
			for p in "../patches/v3.${i}/"*.patch; do
				patch -p1 -i "${p}"
			done
		fi

		clean_source
	)
done

for i in `seq 0 5`; do
	git archive --remote="${LINUX_REPOSITORY}" --format tar --prefix=linux-4.${i}/ v4.${i}|tar x
	(
		cd "linux-4.${i}" || exit
		prepare_source "4" "${i}"
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
echo "Please mount the image:"
echo "    mkdir -p linux-build"
echo "    mount -o loop linux-build.img linux-build"

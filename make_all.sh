#! /bin/sh
set -e

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

for i in `seq 29 39`; do
	#wget "http://www.kernel.org/pub/linux/kernel/v2.6/linux-2.6.${i}.tar.gz"
	#tar xfz "linux-2.6.${i}.tar.gz"
	#rm "linux-2.6.${i}.tar.gz"
	git archive --remote=git+ssh://git@git.open-mesh.org/linux-merge.git --format tar --prefix=linux-2.6.${i}/ v2.6.${i}|tar x
	(
		cd "linux-2.6.${i}"
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
	)
	./clean_sources.sh
done

for i in `seq 0 15`; do
	git archive --remote=git+ssh://git@git.open-mesh.org/linux-merge.git --format tar --prefix=linux-3.${i}/ v3.${i}|tar x
	(
		cd "linux-3.${i}"
		SMP=smp
		prepare_source "3" "${i}" "$SMP"
		if [ -d "../patches/v3.${i}" ]; then
			for p in "../patches/v3.${i}/"*.patch; do
				patch -p1 -i "${p}"
			done
		fi
	)
	./clean_sources.sh
done


find linux-2.6.* -type f -exec sha1sum '{}' \; > checksums
find linux-3.* -type f -exec sha1sum '{}' \; >> checksums
./create_links.py; rm -f checksums
./generate_squashfs.sh

echo "done"

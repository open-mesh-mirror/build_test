#! /bin/sh
set -e

build_path()
{
	if [ -d "build/net/batman-adv" ]; then
		echo "./build/net/batman-adv"
	elif [ -d "net/batman-adv" ]; then
		echo "./net/batman-adv"
	else
		echo "."
	fi
}

path="$(build_path)"
mv "${path}"/batman-adv.o "${path}"/batman-adv.o.disabled
defined="`nm -g --defined-only "${path}"/*.o|awk '{ print $3}'|sort|uniq`"
mv "${path}"/batman-adv.o.disabled "${path}"/batman-adv.o
ret=0
blacklist="cleanup_module init_module __this_module"

for i in $defined; do
	found=0
	echo $i |grep -v '^batadv_' >/dev/null && found=1

	for j in $blacklist; do
		[ "$i" = "$j" ] && found=0 && break
	done

	if [ "$found" = "1" ]; then
		echo $i
		ret=1
	fi
done

exit ${ret}

#! /bin/sh
set -e

defined="`nm -g --defined-only *.o|awk '{ print $3}'|sort|uniq`"
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

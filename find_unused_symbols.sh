#! /bin/sh
set -e

defined="`nm -g --defined-only *.o|awk '{ print $3}'|sort|uniq`"
used="`nm -g --undefined-only *.o|awk '{ print $2}'|sort|uniq`"
ret=0
blacklist="cleanup_module batadv_prepare_unicast_4addr_packet batadv_hash_set_lock_class "

for i in $defined; do
	found=0
	for j in $used; do
		[ "$i" = "$j" ] && found=1 && break
	done

	for j in $blacklist; do
		[ "$i" = "$j" ] && found=1 && break
	done

	if [ "$found" = "0" ]; then
		echo $i
		ret=1
	fi
done

exit ${ret}

#! /bin/sh
set -e

source_path()
{
	if [ -d "net/batman-adv" ]; then
		echo "./net/batman-adv/"
	else
		echo "./"
	fi
}

path="$(source_path)"
defined="`nm -g --defined-only "${path}"/*.o|awk '{ print $3}'|sort|uniq`"
used="`nm -g --undefined-only "${path}"/*.o|awk '{ print $2}'|sort|uniq`"
ret=0
blacklist="cleanup_module batadv_hash_set_lock_class batadv_send_skb_prepare_unicast_4addr batadv_unicast_4addr_prepare_skb batadv_skb_crc32"

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

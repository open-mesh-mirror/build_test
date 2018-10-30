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
obj=$(ls -1 "${path}"/*.o|grep -v -e 'batman-adv\.o' -e 'batman-adv\.mod\.o')
defined="`nm -g --defined-only  ${obj}|awk '{ print $3}'|grep '^batadv'|sort|uniq`"
used="$@"
ret=0
blacklist="
  batadv_broadcast_addr
  batadv_event_workqueue
  batadv_hardif_list
  batadv_hardif_generation
  batadv_hard_if_notifier
  batadv_link_ops
  batadv_netlink_family
  batadv_routing_algo
"

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

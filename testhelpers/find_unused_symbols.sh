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
defined="`nm -g --defined-only  ${obj}|awk '{ print $3}'|sort|uniq`"
used="`nm -g --undefined-only  ${obj}|awk '{ print $2}'|sort|uniq`"
ret=0
blacklist="
	cleanup_module
	init_module
	batadv_send_skb_prepare_unicast_4addr
	batadv_skb_crc32
	batadv_send_skb_packet
	batadv_parse_throughput
	batadv_gw_node_get
	batadv_get_real_netdev
	batadv_is_cfg80211_hardif
	batadv_tvlv_containers_process2
	batadv_v_elp_nhh_cmp
	batadv_v_elp_rx_egress_bad
	batadv_v_elp_rx_ingress_bad
	batadv_v_elp_tx_egress_bad
	batadv_v_elp_tx_ingress_bad
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

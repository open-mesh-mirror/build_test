#! /bin/sh

TO="linux-merge@lists.open-mesh.org"
REMOTE="/srv/git/repositories/batman-adv.git/"
REMOTE_BATCTL="/srv/git/repositories/batctl.git/"

cd "$(dirname "$0")"

rm -f batctl_stable.packet.h  batctl_main.packet.h  batman-adv_stable.packet.h  batman-adv_main.packet.h
rm -f stable.diff  main.diff

checkout_packet_h()
{
	remote="${1}"
	branch="${2}"

	git --git-dir="${remote}" cat-file -p "${branch}":include/uapi/linux/batadv_packet.h 2> /dev/null
	if [ "$?" = "0" ]; then
		return
	fi

	git --git-dir="${remote}" cat-file -p "${branch}":batadv_packet.h 2> /dev/null
	if [ "$?" = "0" ]; then
		return
	fi

	git --git-dir="${remote}" cat-file -p "${branch}":net/batman-adv/packet.h 2> /dev/null
	if [ "$?" = "0" ]; then
		return
	fi

	git --git-dir="${remote}" cat-file -p "${branch}":packet.h 2> /dev/null
	if [ "$?" = "0" ]; then
		return
	fi
}

checkout_packet_h "${REMOTE}" main > batman-adv_main.packet.h
checkout_packet_h "${REMOTE}" stable > batman-adv_stable.packet.h

checkout_packet_h "${REMOTE_BATCTL}" main > batctl_main.packet.h
checkout_packet_h "${REMOTE_BATCTL}" stable > batctl_stable.packet.h

diff -ruN batman-adv_main.packet.h batctl_main.packet.h > main.diff
diff -ruN batman-adv_stable.packet.h batctl_stable.packet.h > stable.diff

generate_email_header()
{
	cat <<-EOF
	From: postmaster@open-mesh.org
	To: $1
	Subject: Noticed difference in batadv_packet.h in $2
	MIME-Version: 1.0
	Content-Type: text/plain; charset=UTF-8

	EOF
}

for i in main.diff stable.diff; do
	if [ -s "$i" ]; then
		(generate_email_header "$TO" "$i"
		cat "$i") | /usr/sbin/sendmail -t
	fi
done

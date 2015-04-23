#! /bin/sh

TO="linux-merge@lists.open-mesh.org"
REMOTE="/srv/git/repositories/batman-adv.git/"
REMOTE_BATCTL="/srv/git/repositories/batctl.git/"

cd /home/batman/build_test/packet.h_check

rm -f batctl_maint.packet.h batctl_next.packet.h  batctl_master.packet.h  batman-adv_maint.packet.h  batman-adv_next.packet.h batman-adv_master.packet.h
rm -f maint.diff next.diff  master.diff

git --git-dir="${REMOTE}" cat-file -p master:packet.h > batman-adv_master.packet.h
git --git-dir="${REMOTE}" cat-file -p next:packet.h > batman-adv_next.packet.h
git --git-dir="${REMOTE}" cat-file -p maint:packet.h > batman-adv_maint.packet.h

git --git-dir="${REMOTE_BATCTL}" cat-file -p master:packet.h > batctl_master.packet.h
git --git-dir="${REMOTE_BATCTL}" cat-file -p next:packet.h > batctl_next.packet.h
git --git-dir="${REMOTE_BATCTL}" cat-file -p maint:packet.h > batctl_maint.packet.h

diff -ruN batman-adv_master.packet.h batctl_master.packet.h > master.diff
diff -ruN batman-adv_next.packet.h batctl_next.packet.h > next.diff
diff -ruN batman-adv_maint.packet.h batctl_maint.packet.h > maint.diff

generate_email_header()
{
	cat <<-EOF
	From: postmaster@open-mesh.org
	To: $1
	Subject: Noticed difference in packet.h in $2
	MIME-Version: 1.0
	Content-Type: text/plain; charset=UTF-8

	EOF
}

for i in master.diff next.diff maint.diff; do
	if [ -s "$i" ]; then
		(generate_email_header "$TO" "$i"
		cat "$i") | /usr/sbin/sendmail -t
	fi
done

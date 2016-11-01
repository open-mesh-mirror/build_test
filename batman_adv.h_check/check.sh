#! /bin/sh

TO="linux-merge@lists.open-mesh.org"
REMOTE="/srv/git/repositories/batman-adv.git/"
REMOTE_BATCTL="/srv/git/repositories/batctl.git/"

cd "$(dirname "$0")"

rm -f batctl_maint.batman_adv.h batctl_master.batman_adv.h  batman-adv_maint.batman_adv.h  batman-adv_master.batman_adv.h
rm -f maint.diff master.diff

checkout_batman_adv_h()
{
	remote="${1}"
	branch="${2}"

	git --git-dir="${remote}" cat-file -p "${branch}":include/uapi/linux/batman_adv.h 2> /dev/null
	if [ "$?" = "0" ]; then
		return
	fi

	git --git-dir="${remote}" cat-file -p "${branch}":batman_adv.h 2> /dev/null
}

checkout_batman_adv_h "${REMOTE}" master > batman-adv_master.batman_adv.h
checkout_batman_adv_h "${REMOTE}" maint > batman-adv_maint.batman_adv.h

checkout_batman_adv_h "${REMOTE_BATCTL}" master > batctl_master.batman_adv.h
checkout_batman_adv_h "${REMOTE_BATCTL}" maint > batctl_maint.batman_adv.h

diff -ruN batman-adv_master.batman_adv.h batctl_master.batman_adv.h > master.diff
diff -ruN batman-adv_maint.batman_adv.h batctl_maint.batman_adv.h > maint.diff

generate_email_header()
{
	cat <<-EOF
	From: postmaster@open-mesh.org
	To: $1
	Subject: Noticed difference in batman_adv.h in $2
	MIME-Version: 1.0
	Content-Type: text/plain; charset=UTF-8

	EOF
}

for i in master.diff maint.diff; do
	if [ -s "$i" ]; then
		(generate_email_header "$TO" "$i"
		cat "$i") | /usr/sbin/sendmail -t
	fi
done

#! /bin/sh

TO="linux-merge@lists.open-mesh.org"
REMOTE="/srv/git/repositories/batman-adv.git/"
REMOTE_BATCTL="/srv/git/repositories/batctl.git/"
REMOTE_ALFRED="/srv/git/repositories/alfred.git/"

cd "$(dirname "$0")"

rm -f batctl_stable.batman_adv.h batctl_main.batman_adv.h  alfred_stable.batman_adv.h alfred_main.batman_adv.h  batman-adv_stable.batman_adv.h batman-adv_main.batman_adv.h
rm -f stable.diff main.diff

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

checkout_batman_adv_h "${REMOTE}" main > batman-adv_main.batman_adv.h
checkout_batman_adv_h "${REMOTE}" stable > batman-adv_stable.batman_adv.h

checkout_batman_adv_h "${REMOTE_BATCTL}" main > batctl_main.batman_adv.h
checkout_batman_adv_h "${REMOTE_BATCTL}" stable > batctl_stable.batman_adv.h

checkout_batman_adv_h "${REMOTE_ALFRED}" main > alfred_main.batman_adv.h

diff -ruN batman-adv_main.batman_adv.h batctl_main.batman_adv.h > main.diff
diff -ruN batman-adv_stable.batman_adv.h batctl_stable.batman_adv.h > stable.diff

diff -ruN batman-adv_main.batman_adv.h alfred_main.batman_adv.h > alfred.main.diff

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

for i in main.diff stable.diff alfred.main.diff; do
	if [ -s "$i" ]; then
		(generate_email_header "$TO" "$i"
		cat "$i") | /usr/sbin/sendmail -t
	fi
done

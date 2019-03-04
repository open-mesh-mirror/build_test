#! /bin/bash
set -e

LINUX_REPOSITORY=${LINUX_REPOSITORY:="$HOME/tmp/qemu-batman/linux-next/"}
LINUX_VERSIONS="$(echo linux-3.{16..19} linux-4.{0..20} linux-5.0) linux-3.16.62 linux-4.4.169 linux-4.9.148 linux-4.14.91 linux-4.19.13"
PATCHDIR="$(pwd)/../patches/"


for i in ${LINUX_VERSIONS}; do
	version="$(echo "${i}"|sed 's/^linux-/v/')"

	if [ ! -d "${PATCHDIR}/${version}/" ]; then
		continue
	fi

	cd "${LINUX_REPOSITORY}"
	git checkout "${version}"
	git am "${PATCHDIR}/${version}/"*
	rm "${PATCHDIR}/${version}/"*
	git format-patch --output-directory "${PATCHDIR}/${version}/" --no-stat --full-index --no-renames --binary --diff-algorithm=histogram --no-signature --format=format:'From: %an <%ae>%nDate: %aD%nSubject: %B' "${version}"
done

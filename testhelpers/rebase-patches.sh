#! /bin/bash
set -e

LINUX_REPOSITORY=${LINUX_REPOSITORY:="$HOME/tmp/qemu-batman/linux-next/"}
PATCHDIR="$(pwd)/../patches/"

. ../linux-versions

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

#! /bin/bash
set -e

LINUX_REPOSITORY=${LINUX_REPOSITORY:="$HOME/tmp/qemu-batman/linux-next/"}
PATCHDIR="$(pwd)/../patches/"

. ../linux-versions

for version in ${LINUX_VERSIONS}; do
	if [ ! -d "${PATCHDIR}/linux/${version}/" ]; then
		continue
	fi

	cd "${LINUX_REPOSITORY}"
	git checkout "${version}"
	git am "${PATCHDIR}/linux/${version}/"*
	rm "${PATCHDIR}/linux/${version}/"*
	git format-patch --output-directory "${PATCHDIR}/linux/${version}/" --no-stat --full-index --no-renames --binary --diff-algorithm=histogram --no-signature --format=format:'From: %an <%ae>%nDate: %aD%nSubject: %B' "${version}"
done

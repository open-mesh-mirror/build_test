#! /bin/bash
set -e

LINUX_REPOSITORY=${LINUX_REPOSITORY:="$HOME/tmp/linux-next/"}
LINUX_VERSIONS=$(echo linux-3.{2..19} linux-4.{0..11})
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
	git -c core.abbrev=7 format-patch --output-directory "${PATCHDIR}/${version}/" --diff-algorithm=histogram --no-signature --format=format:'From: %an <%ae>%nDate: %aD%nSubject: [PATCH] %B' --abbrev=7  "${version}"
done

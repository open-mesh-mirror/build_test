#! /bin/bash

cd "$(dirname "$0")"

TO=${TO:="$(whoami)"}
FROM=${FROM:="$(whoami)"}
REMOTE=${REMOTE:="git+ssh://git@git.open-mesh.org/batman-adv.git"}
JOBS=${JOBS:=$(nproc || echo 1)}
TESTBRANCHES="${TESTBRANCHES:="master next"}"
SUBMIT_BRANCH=${SUBMIT_BRANCH:="next"}
INCOMING_BRANCH=${INCOMING_BRANCH:="master"}

BUILD_RUNS=${BUILD_RUNS:=1}
CONFIGS_PER_RUN=${CONFIGS_PER_RUN:=4}
LINUX_VERSIONS_PER_RUN=${LINUX_VERSIONS_PER_RUN:=0}
MAX_BUILDTIME_PER_BRANCH=${MAX_BUILDTIME_PER_BRANCH:=725328000}

DEFAULT_LINUX_VERSIONS=$(echo linux-3.{2..19} linux-4.{0..7})
LINUX_VERSIONS=${LINUX_VERSIONS:=${DEFAULT_LINUX_VERSIONS}}
LINUX_DEFAULT_VERSION=${LINUX_DEFAULT_VERSION:="linux-4.7"}
TMPNAME="$(mktemp -d -p. -u)"

CGCC="$(pwd)/sparse/cgcc"
SPARSE="$(pwd)/sparse/sparse"
CPPCHECK="$(pwd)/cppcheck/cppcheck"
SMATCH="$(pwd)/smatch/smatch"
SMATCH_CGCC="$(pwd)/smatch/cgcc"
BRACKET="$(pwd)/testhelpers/bracket_align.py"
LINUXNEXT="$(pwd)/linux-next/"
CHECKPATCH="${LINUXNEXT}/scripts/checkpatch.pl"
KERNELDOC="${LINUXNEXT}/scripts/kernel-doc"
UNUSED_SYMBOLS="$(pwd)/testhelpers/find_unused_symbols.sh"
CHECK_COPYRIGHT="$(pwd)/testhelpers/check_copyright.sh"
WRONG_NAMESPACE="$(pwd)/testhelpers/find_wrong_namespace.sh"
IWYU_KERNEL_MAPPINGS="$(pwd)/testhelpers/kernel_mappings.iwyu"
FIX_INCLUDE_SORT="$(pwd)/testhelpers/fix_includes_sort.py"

MAIL_AGGREGATOR="$(pwd)/testhelpers/mail_aggregator.py"
DB="$(pwd)/error.db"
LINUX_HEADERS="$(pwd)/linux-build/"
GENERATE_CONFIG="$(pwd)/testhelpers/generate_config_params.py"
GENERATE_LINUX_VERSIONS="$(pwd)/testhelpers/generate_linux_versions.py"

MAKE="/usr/bin/make"
extra_flags='-Werror -D__CHECK_ENDIAN__ -DDEBUG'
export LANG=C

check_external()
{
	if [ ! -x "${CGCC}" -o ! -x "${SPARSE}" ]; then
		echo "Required tool sparse missing:"
		echo "    git clone git://git.kernel.org/pub/scm/devel/sparse/sparse.git sparse"
		echo "    make -C sparse"
		exit 1
	fi

	if [ ! -x "${CPPCHECK}" ]; then
		echo "Required tool cppcheck missing:"
		echo "    git clone git://github.com/danmar/cppcheck.git cppcheck"
		echo "    make -C cppcheck"
		exit 1
	fi

	if [ ! -x "${SMATCH_CGCC}" -o ! -x "${SMATCH}" ]; then
		echo "Required tool smatch missing:"
		echo "    git clone http://repo.or.cz/smatch.git smatch"
		echo "    git -C smatch reset --hard dfe27cf918e52fa00c1c6ec10b0f72ee45316236"
		echo "    git -C smatch am ../patches/smatch/9999-smatch-Workaround-to-allow-the-check-of-batadv_iv_og.patch"
		echo "    make -C smatch"
		exit 1
	fi

	if [ ! -x "${CHECKPATCH}" -o ! -x "${KERNELDOC}" ]; then
		echo "Required tool checkpatch and kernel-doc missing:"
		echo "    git clone git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git linux-next"
		echo "    git --git-dir=linux-next/.git/ remote add net-next git://git.kernel.org/pub/scm/linux/kernel/git/davem/net-next.git"
		echo "    git --git-dir=linux-next/.git/ remote add net git://git.kernel.org/pub/scm/linux/kernel/git/davem/net.git"
		exit 1
	fi

	for linux_name in ${LINUX_VERSIONS} ${LINUX_DEFAULT_VERSION}; do
		if [ ! -d "${LINUX_HEADERS}/${linux_name}" ]; then
			echo "Required linux header for ${linux_name} missing:"
			echo "    ./generate_linux_headers.sh"
			echo "    mkdir -p linux-build"
			echo "    mount -o loop linux-build.img linux-build"
			exit 1
		fi
	done
}

test_cppcheck()
{
	branch="$1"

	touch compat-autoconf.h
	rm -f log logfull
	("${CPPCHECK}" --error-exitcode=42 -I../minilinux/ --enable=all --suppress=variableScope . 3>&2 2>&1 1>&3 \
				| grep -v "bridge_loop_avoidance.c.* The function 'batadv_bla_backbone_table_seq_print_text' is never used" \
				| grep -v "bridge_loop_avoidance.c.* The function 'batadv_bla_claim_table_seq_print_text' is never used" \
				| grep -v "distributed-arp-table.c.* The function 'batadv_dat_cache_seq_print_text' is never used" \
				| grep -v "distributed-arp-table.c.* The function 'batadv_dat_status_update' is never used" \
				| grep -v "bridge_loop_avoidance.c.* The function 'batadv_bla_status_update' is never used" \
				| grep -v "log.c.* The function 'batadv_debug_log' is never used" \
				| grep -v "network-coding.c.* The function 'batadv_nc_nodes_seq_print_text' is never used" \
				| grep -v "network-coding.c.* The function 'batadv_nc_status_update' is never used" \
				| grep -v "multicast.c.* The function 'batadv_mcast_flags_seq_print_text' is never used" \
				| grep -v "gateway_client.c.* Either the condition 'next_gw' is redundant or there is possible null pointer dereference: next_gw" \
				| grep -v "main.c.* Either the condition '!tvlv_value' is redundant or there is possible null pointer dereference: tvlv_value" \
				| grep -v "tvlv.c.* Either the condition '!tvlv_value' is redundant or there is possible null pointer dereference: tvlv_value" \
				| grep -v "Cppcheck cannot find all the include files" \
				|tee log) &> logfull
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "cppcheck" log logfull
	fi
	rm -f compat-autoconf.h
}

source_path()
{
	if [ -d "net/batman-adv" ]; then
		echo "./net/batman-adv"
	else
		echo "."
	fi
}

test_coccicheck()
{
	branch="$1"
	path="$(source_path)"

	rm -f log
	make -s -C "${LINUXNEXT}" coccicheck MODE=report KBUILD_EXTMOD="$(pwd)/${path}/" | \
		grep -v -e 'Please check for false positives in the output before submitting a patch.' \
			-e 'When using "patch" mode, carefully review the patch before submitting it.' \
			-e 'ERROR: next_gw is NULL but dereferenced.' \
			-e 'tp_meter.c.*ERROR: reference preceded by free on line' \
			-e '^$' \
		> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "coccicheck" log log
	fi
}

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

simplify_config_string()
{
	config="$@"
	config_simple="$(echo "${config}"|sed 's/CONFIG_BATMAN_ADV_//g')"

	echo "cfg: ${config_simple}"
}

test_comments()
{
	branch="$1"
	path="$(source_path)"

	grep -nE "^\s*\*.+\*/" "${path}"/*.c "${path}"/*.h &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "Multiline comment ending at a non-empty line" log log
	fi

	grep -nE "/\*\*..*$" "${path}"/*.c "${path}"/*.h &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "Comment starting with two asterisk non-empty line" log log
	fi

	grep -nE "[^ ]\*/$" "${path}"/*.c "${path}"/*.h &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "Comment ending without space" log log
	fi

	grep -nE "/\*$" "${path}"/*.c "${path}"/*.h &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "Multiline comment starting with empty line" log log
	fi
}

test_checkpatch()
{
	branch="$1"
	path="$(source_path)"

	rm -f log logfull
	for i in "${path}"/*; do
		if [ ! -f "$i" ]; then
			continue
		fi

		fname=$(basename "$i")
		if [ "$fname" != "compat.c" -a "$fname" != "compat.h" -a "$fname" != "gen-compat-autoconf.sh" ]; then
			rm -f log logfull

			"${CHECKPATCH}" -q \
				--ignore COMPLEX_MACRO \
				--min-conf-desc-length=3 \
				--strict --file "$i" &> logfull

			if [ -s "logfull" ]; then
				"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "checkpatch $i" logfull logfull
			fi
		fi
	done
}

test_kerneldoc()
{
	branch="$1"
	path="$(source_path)"

	rm -f log logfull
	for i in "${path}"/*; do
		if [ ! -f "$i" ]; then
			continue
		fi

		fname=$(basename "$i")
		if [ "$fname" != "compat.c" -a "$fname" != "compat.h" -a "$fname" != "gen-compat-autoconf.sh" ]; then
			rm -f log logfull

			("${KERNELDOC}" -v -list "$i" 2>&1 > /dev/null)| \
				grep -v Scanning|grep -v \
				-e "[0-9]* warnings" \
				-e 'no structured comments found' &> logfull

			if [ -s "logfull" ]; then
				"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "kerneldoc $i" logfull logfull
			fi
		fi
	done
}

test_brackets()
{
	branch="$1"
	path="$(source_path)"

	for i in "${path}"/*.c "${path}"/*.h; do
		fname=$(basename "$i")
		if [ "$fname" != "compat.c" -a "$fname" != "compat.h" ]; then
			rm -f log logfull
			"${BRACKET}" "$i" &> logfull

			if [ -s logfull ]; then
				"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "bracket_align $i" logfull logfull
			fi
		fi
	done
}

test_sparse()
{
	branch="$1"
	linux_name="$2"
	config="$3"

	# hard-interface.c:.* delete is required for a warning caused by the compat.h hack for get_link_net
	(EXTRA_CFLAGS="$extra_flags" "${MAKE}" CHECK="${SPARSE} -Wsparse-all -Wno-ptr-subtraction-blows $extra_flags" $config CC="${CGCC}" KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" 3>&2 2>&1 1>&3 \
			|grep -v "No such file: c" \
			|sed -e '/hard-interface.c:.* warning: incorrect type in return expression (different base types)/,+2d'|sed '/hard-interface.c: In function .batadv_getlink_net./,+3d' \
			|tee log) &> logfull
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "sparse ${linux_name} $(simplify_config_string "${config}")" log logfull
	fi
}

test_unused_symbols()
{
	branch="$1"
	linux_name="$2"
	config="$3"

	"${UNUSED_SYMBOLS}" \
		| grep -v batadv_send_skb_unicast \
		| grep -v batadv_tt_global_hash_count \
	&> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "unused_symbols ${linux_name} $(simplify_config_string "${config}")" log log
	fi
}

test_wrong_namespace()
{
	branch="$1"
	linux_name="$2"
	config="$3"

	"${WRONG_NAMESPACE}" &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "wrong namespace symbols ${linux_name} $(simplify_config_string "${config}")" log log
	fi
}

test_smatch()
{
	branch="$1"
	linux_name="$2"
	config="$3"

	EXTRA_CFLAGS="$extra_flags" "${MAKE}" CHECK="${SMATCH} -p=kernel --two-passes --file-output $extra_flags" $config CC="${SMATCH_CGCC}" KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" -j"${JOBS}" &> /dev/null
	# installed filters:
	#
	path="$(build_path)"
	cat "${path}"/*.smatch \
		> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "smatch ${linux_name} $config" log log
	fi
}

test_copyright()
{
	branch="$1"

	"${CHECK_COPYRIGHT}" \
	&> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "copyright" log log
	fi
}

test_main_include()
{
	branch="$1"

	spath="$(source_path)"
	for i in $(ls -1 "${spath}"|grep -v -e '^main.h$' -e '^packet.h$' -e '^types.h$'|grep -e '\.c$' -e '\.h$'); do
		grep -L '#[[:space:]]*include[[:space:]]*"main.h"' net/batman-adv/"$i"
	done|sed 's/^/missing include for "main.h" in /' > log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "main.h include missing" log log
	fi
}

test_compare_net_next()
{
	branch="$1"

	rm -rf "${TMPNAME}"
	mkdir "${TMPNAME}"

	netnext_rev="$(git -C "linux-next" rev-parse net-next/master)"
	net_rev="$(git -C "linux-next" rev-parse net/master)"
	netmerge_base="$(git -C "linux-next" merge-base "${net_rev}" "${netnext_rev}")"

	# use net instead of net-next in case it net-next is currently frozen and everything is added to net
	if [ "${netmerge_base}" = "${netnext_rev}" ]; then
		upstream_rev="net/master"
		upstream_name="net"
	else
		upstream_rev="net-next/master"
		upstream_name="net-next"
	fi

	git archive --remote="${REMOTE}" --format=tar --prefix="${TMPNAME}/batadv/" "$branch" -- net/batman-adv/ Documentation/networking/batman-adv.txt Documentation/ABI/testing/sysfs-class-net-batman-adv Documentation/ABI/testing/sysfs-class-net-mesh | tar x
	git archive --remote="linux-next/.git/" --format=tar --prefix="${TMPNAME}/netnext/" "${upstream_rev}" -- net/batman-adv/ Documentation/networking/batman-adv.txt Documentation/ABI/testing/sysfs-class-net-batman-adv Documentation/ABI/testing/sysfs-class-net-mesh | tar x

	# compare against stripped down MAINTAINERS when available
	git archive --remote="${REMOTE}" --format=tar --prefix="${TMPNAME}/batadv/" "$branch" -- MAINTAINERS | tar x
	git archive --remote="linux-next/.git/" --format=tar --prefix="${TMPNAME}/netnext/" "${upstream_rev}" -- MAINTAINERS | tar x
	if [ -r "${TMPNAME}/batadv/MAINTAINERS" ]; then
		awk '/^BATMAN ADVANCED$/{f=1};/^$/{f=0};f' "${TMPNAME}/netnext/MAINTAINERS" > "${TMPNAME}/netnext/MAINTAINERS.2"
		mv "${TMPNAME}/netnext/MAINTAINERS.2" "${TMPNAME}/netnext/MAINTAINERS"
	else
		rm -f "${TMPNAME}/netnext/MAINTAINERS"
	fi

	# compare against batman_adv.h
	git archive --remote="${REMOTE}" --format=tar --prefix="${TMPNAME}/batadv/" "$branch" -- include/uapi/linux/batman_adv.h | tar x
	git archive --remote="linux-next/.git/" --format=tar --prefix="${TMPNAME}/netnext/" "${upstream_rev}" -- include/uapi/linux/batman_adv.h | tar x

	diff -ruN "${TMPNAME}"/batadv "${TMPNAME}"/netnext|diffstat -w 71 -q -p2 > "${TMPNAME}"/log
	if [ -s "${TMPNAME}/log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "difference between ${upstream_name} and batadv ${branch}" "${TMPNAME}"/log "${TMPNAME}"/log
	fi
}

test_headers()
{
	branch="$1"

	rm -rf "${TMPNAME}"
	git clone -b "$branch" "${REMOTE}" "${TMPNAME}"
	(
		cd "${TMPNAME}" || exit
		spath="$(source_path)"

		MAKE_CONFIG="CONFIG_BATMAN_ADV_DEBUGFS=y CONFIG_BATMAN_ADV_DEBUG=y CONFIG_BATMAN_ADV_BLA=y CONFIG_BATMAN_ADV_DAT=y CONFIG_BATMAN_ADV_MCAST=y CONFIG_BATMAN_ADV_NC=y CONFIG_BATMAN_ADV_BATMAN_V=y KBUILD_SRC=${LINUX_HEADERS}/${LINUX_DEFAULT_VERSION}"

		# don't touch main.h and files which are required by linux/wait.h, packet.h
		sed -i 's/#include "main.h"/#include "main.h" \/\/ IWYU pragma: keep/' "${spath}"/*c "${spath}"/*.h
		sed -i 's/\/\* for linux\/wait.h \*\//\/\* for linux\/wait.h \*\/ \/\/ IWYU pragma: keep/' "${spath}"/*c "${spath}"/*.h
		sed -i 's/\/\* for packet.h \*\//\/\* for packet.h \*\/ \/\/ IWYU pragma: keep/' "${spath}"/*c "${spath}"/*.h

		make KERNELPATH="${LINUX_HEADERS}/${LINUX_DEFAULT_VERSION}" $MAKE_CONFIG clean
		make KERNELPATH="${LINUX_HEADERS}/${LINUX_DEFAULT_VERSION}" -j1 -k CC="iwyu -Xiwyu --prefix_header_includes=keep -Xiwyu --no_default_mappings -Xiwyu --transitive_includes_only -Xiwyu --verbose=1 -Xiwyu --mapping_file=$IWYU_KERNEL_MAPPINGS" $MAKE_CONFIG 2> test

		bpath="$(build_path)"

		git add -f "${bpath}" "${spath}"
		fix_include --nosafe_headers --separate_project_includes="$(pwd)/${bpath}" < test

		# remove extra noise
		git checkout -f -- compat-sources
		sed -i '/struct batadv_algo_ops;/d' "${bpath}"/main.h
		sed -i '/struct batadv_hard_iface;/d' "${bpath}"/main.h
		sed -i '/struct batadv_orig_node;/d' "${bpath}"/main.h
		sed -i '/struct batadv_priv;/d' "${bpath}"/main.h

		"${FIX_INCLUDE_SORT}" --sort_only "${bpath}"/*.c "${bpath}"/*.h
		git diff > log

	)
	if [ -s "${TMPNAME}/log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "headers" "${TMPNAME}"/log "${TMPNAME}"/log
	fi
	rm -rf "${TMPNAME}"
}

test_builds()
{
	branch="$1"

	linux_test_versions="$("${GENERATE_LINUX_VERSIONS}" "${LINUX_VERSIONS_PER_RUN}" ${LINUX_VERSIONS})"
	for c in `"${GENERATE_CONFIG}" "${CONFIGS_PER_RUN}" BLA DAT DEBUGFS DEBUG NC MCAST BATMAN_V`; do
		config="`echo $c|sed 's/\+/ /g'`"

		for linux_name in ${linux_test_versions}; do
			"${MAIL_AGGREGATOR}" "${DB}" add_buildtests "${branch}" "${linux_name}" "${c}" || continue

			rm -f log logfull

			# B.A.T.M.A.N. V only supports Linux >=3.16
			if [[ "${config}" == *"CONFIG_BATMAN_ADV_BATMAN_V=y"* ]]; then
				if dpkg --compare-versions "${linux_name#linux-}" lt "3.16"; then
					continue
				fi
			fi

			# force DEBUGFS when DEBUG
			if [[ "${config}" == *"CONFIG_BATMAN_ADV_DEBUG=y"* ]]; then
				config="$(echo ${config}|sed 's/CONFIG_BATMAN_ADV_DEBUGFS=n/CONFIG_BATMAN_ADV_DEBUGFS=y/')"
			fi

			test_sparse "${branch}" "${linux_name}" "${config}"
			test_unused_symbols "${branch}" "${linux_name}" "${config}"
			test_wrong_namespace "${branch}" "${linux_name}" "${config}"
			"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" -j"${JOBS}" clean

			test_smatch "${branch}" "${linux_name}" "${config}"
			"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" -j"${JOBS}" clean
		done
	done
}

testbranch()
{
	branch="$1"
	(
		test_headers "$branch"

		if [ "$branch" == "${SUBMIT_BRANCH}" ]; then
			test_compare_net_next "${branch}"
		fi

		rm -rf "${TMPNAME}"
		git archive --remote="${REMOTE}" --format=tar --prefix="${TMPNAME}/" "$branch" | tar x
		cd "${TMPNAME}"

		test_cppcheck "${branch}"
		# TODO enable also for all other branches
		if [ "$branch" == "${INCOMING_BRANCH}" ]; then
			test_coccicheck "${branch}"
		fi
		test_comments "${branch}"

		start_time="$(date +%s)"
		end_time="$((${start_time} + ${MAX_BUILDTIME_PER_BRANCH}))"
		for i in $(seq 1 "${BUILD_RUNS}"); do
			test_builds "${branch}"

			now="$(date +%s)"
			if [ "${now}" -gt "${end_time}" ]; then
				break
			fi
		done

		test_checkpatch "${branch}"
		if [ "$branch" == "${INCOMING_BRANCH}" ]; then
			test_kerneldoc "${branch}"
			test_copyright "${branch}"
			test_main_include "${branch}"
		fi
		test_brackets "${branch}"
	)
	rm -rf "${TMPNAME}"
}

check_external

# update linux next for checkpatch/net-next
git --git-dir=linux-next/.git/ --work-tree=linux-next remote update --prune
git --git-dir=linux-next/.git/ --work-tree=linux-next reset --hard origin/master

"${MAIL_AGGREGATOR}" "${DB}" create
for branch in $TESTBRANCHES; do
	testbranch $branch
done
"${MAIL_AGGREGATOR}" "${DB}" send "${FROM}" "${TO}" "Build check errors found: `date '+%Y-%m-%d'`"

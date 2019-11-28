#! /bin/bash

cd "$(dirname "$0")"

TO=${TO:="$(whoami)"}
FROM=${FROM:="$(whoami)"}
REMOTE=${REMOTE:="git+ssh://git@git.open-mesh.org/batman-adv.git"}
JOBS=${JOBS:=$(nproc || echo 1)}
TESTBRANCHES="${TESTBRANCHES:="master maint"}"
SUBMIT_NET_NEXT_BRANCH=${SUBMIT_NET_NEXT_BRANCH:="master"}
SUBMIT_NET_BRANCH=${SUBMIT_NET_BRANCH:="maint"}

BUILD_RUNS=${BUILD_RUNS:=1}
CONFIGS_PER_RUN=${CONFIGS_PER_RUN:=4}
LINUX_VERSIONS_PER_RUN=${LINUX_VERSIONS_PER_RUN:=0}
MAX_BUILDTIME_PER_BRANCH=${MAX_BUILDTIME_PER_BRANCH:=725328000}

. linux-versions

DEFAULT_TMPNAME="$(mktemp -d -p. -u)"
TMPNAME=${TMPNAME:=${DEFAULT_TMPNAME}}

SPARSE="$(pwd)/sparse/sparse"
SMATCH="$(pwd)/smatch/smatch"
SPATCH="$(pwd)/coccinelle/spatch"
BRACKET="$(pwd)/testhelpers/bracket_align.py"
LINUXNEXT="$(pwd)/linux-next"
CHECKPATCH="${LINUXNEXT}/scripts/checkpatch.pl"
KERNELDOC="${LINUXNEXT}/scripts/kernel-doc"
UNUSED_SYMBOLS="$(pwd)/testhelpers/find_unused_symbols.sh"
CHECK_COPYRIGHT="$(pwd)/testhelpers/check_copyright.sh"
WRONG_NAMESPACE="$(pwd)/testhelpers/find_wrong_namespace.sh"
MISSING_KERNELDOC_SYMBOLS="$(pwd)/testhelpers/find_missing_kerneldoc_symbols.sh"
IWYU_KERNEL_MAPPINGS="$(pwd)/testhelpers/kernel_mappings.iwyu"
FIX_INCLUDE_SORT="$(pwd)/testhelpers/fix_includes_sort.py"

MAIL_AGGREGATOR="$(pwd)/testhelpers/mail_aggregator.py"
DB="$(pwd)/error.db"
LINUX_HEADERS="$(pwd)/linux-build"
GENERATE_CONFIG="$(pwd)/testhelpers/generate_config_params.py"
GENERATE_LINUX_VERSIONS="$(pwd)/testhelpers/generate_linux_versions.py"

MAKE="/usr/bin/make"
extra_flags='-Werror -D__CHECK_ENDIAN__ -DDEBUG'
export LANG=C.UTF-8

check_external()
{
	if [ ! -x "${SPARSE}" ]; then
		echo "Required tool sparse missing:"
		echo "    git clone --depth 1 -b v0.6.1 git://git.kernel.org/pub/scm/devel/sparse/sparse.git sparse"
		echo "    make -C sparse"
		exit 1
	fi

	if [ ! -x "${SMATCH}" ]; then
		echo "Required tool smatch missing:"
		echo "    git clone http://repo.or.cz/smatch.git smatch"
		echo "    git -C smatch reset --hard 45eb228201137f975805eb79437eb363272df88d"
		echo "    git -C smatch am ../patches/smatch/9997-Revert-new-check_uninitialized-warn-about-uninitiali.patch"
		echo "    git -C smatch am ../patches/smatch/9998-Revert-function_hooks-fake-an-assignment-when-functi.patch"
		echo "    git -C smatch am ../patches/smatch/9999-smatch-Workaround-to-allow-the-check-of-batadv_iv_og.patch"
		echo "    make -C smatch"
		exit 1
	fi

	if [ ! -x "${CHECKPATCH}" -o ! -x "${KERNELDOC}" ]; then
		echo "Required tool checkpatch and kernel-doc missing:"
		echo "    git clone --depth=1 git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git linux-next"
		echo "    git --git-dir=linux-next/.git/ remote add -t master --no-tags net-next git://git.kernel.org/pub/scm/linux/kernel/git/davem/net-next.git"
		echo "    git --git-dir=linux-next/.git/ remote add -t master --no-tags net git://git.kernel.org/pub/scm/linux/kernel/git/davem/net.git"
		echo "    git --git-dir=linux-next/.git/ config remote.origin.tagopt --no-tags"
		echo "    git --git-dir=linux-next/.git/ fetch --depth=1 net-next"
		echo "    git --git-dir=linux-next/.git/ fetch --depth=1 net"
		exit 1
	fi

	if [ ! -x "${SPATCH}" ]; then
		echo "Required tool spatch missing:"
		echo "    git clone --depth=1 -b 1.0.7 https://github.com/coccinelle/coccinelle coccinelle"
		echo "    (cd coccinelle && ./autogen && ./configure)"
		echo "    make -C coccinelle"
		echo "    make -C coccinelle spatch"
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
	make -s -C "${LINUXNEXT}" coccicheck SPATCH="${SPATCH}" MODE=report KBUILD_EXTMOD="$(pwd)/${path}" | \
		grep -v -e 'Please check for false positives in the output before submitting a patch.' \
			-e 'When using "patch" mode, carefully review the patch before submitting it.' \
			-e 'ERROR: next_gw is NULL but dereferenced.' \
			-e 'tp_meter.c.*ERROR: reference preceded by free on line' \
			-e '^$' \
			-e "recipe for target 'coccicheck' failed" \
			-e 'coccicheck failed' \
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

	grep -nE "/\*\*..*$" "${path}"/*.c "${path}"/*.h|grep -v -nE '\*/$' &> log
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
	for i in "${path}"/* include/uapi/linux/*; do
		if [ ! -f "$i" ]; then
			continue
		fi

		rm -f log logfull

		fname="$(basename "$i")"
		cp_extra_params=""

		if [ "${fname}" = "trace.h" ]; then
			continue
		fi

		if [ "${fname}" = "sysfs.c" ]; then
			cp_extra_params="${cp_extra_params} --ignore COMPLEX_MACRO"
			cp_extra_params="${cp_extra_params} --ignore MACRO_ARG_PRECEDENCE"
			cp_extra_params="${cp_extra_params} --ignore MACRO_ARG_REUSE"
		fi

		if [ "${fname}" = "log.h" ]; then
			cp_extra_params="${cp_extra_params} --ignore MACRO_ARG_REUSE"
		fi

		"${CHECKPATCH}" -q \
			${cp_extra_params} \
			--min-conf-desc-length=3 \
			--strict --file "$i" &> logfull

		if [ -s "logfull" ]; then
			"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "checkpatch $i" logfull logfull
		fi
	done
}

test_kerneldoc()
{
	branch="$1"
	path="$(source_path)"

	rm -f log logfull
	for i in "${path}"/* include/uapi/linux/*; do
		if [ ! -f "$i" ]; then
			continue
		fi

		fname=$(basename "$i")
		if [ "$fname" != "compat.c" -a "$fname" != "compat.h" -a "$fname" != "gen-compat-autoconf.sh" ]; then
			rm -f log logfull

			("${KERNELDOC}" -v -none "$i" 2>&1 > /dev/null)| \
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

	for i in "${path}"/*.c "${path}"/*.h include/uapi/linux/*; do
		fname=$(basename "$i")
		if [ "$fname" != "compat.c" -a "$fname" != "compat.h" -a "$fname" != "trace.h" ]; then
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
	(EXTRA_CFLAGS="$extra_flags" "${MAKE}" CHECK="${SPARSE} -Wsparse-all -Wnopointer-arith -Wno-ptr-subtraction-blows $extra_flags" $config C=1 KERNELPATH="${LINUX_HEADERS}/${linux_name}" 3>&2 2>&1 1>&3 \
			|grep -v "No such file: c" \
			|grep -v 'trace.h:' \
			|grep -v 'include/uapi/linux/perf_event.h:.*: warning: cast truncates bits from constant value (8000000000000000 becomes 0)' \
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

test_missing_kerneldoc_symbols()
{
	branch="$1"
	linux_name="$2"
	config="$3"

	path="$(source_path)"


	"${MISSING_KERNELDOC_SYMBOLS}" $("${KERNELDOC}" -rst "${path}"/*{c,h} include/uapi/linux/* 2>/dev/null|grep '^\.\. c:function::'|sed -e 's/[^(]* \([A-Za-z_][A-Za-z0-9_]*\) (.*/\1/') &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "missing kerneldoc for non-static symbols ${linux_name} $(simplify_config_string "${config}")" log log
	fi
}

test_smatch()
{
	branch="$1"
	linux_name="$2"
	config="$3"

	EXTRA_CFLAGS="$extra_flags" "${MAKE}" CHECK="${SMATCH} -p=kernel --two-passes --file-output $extra_flags" $config C=1 KERNELPATH="${LINUX_HEADERS}/${linux_name}" -j"${JOBS}" &> /dev/null
	# installed filters:
	#
	path="$(build_path)"
	cat "${path}"/*.smatch \
		|grep -v 'arch/x86/include/asm/refcount.h' \
		|grep -v 'warn: was || intended here instead of &&?' \
		|grep -v 'trace_event_define_fields_' \
		|grep -v 'ftrace_define_fields_batadv_dbg() warn: unused return: ret = trace_define_field' \
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
	for i in $(ls -1 "${spath}"|grep -v -e '^main.h$' -e '^types.h$' -e '^trace.c$'|grep -e '\.c$' -e '\.h$'); do
		grep -L '#[[:space:]]*include[[:space:]]*"main.h"' net/batman-adv/"$i"
	done|sed 's/^/missing include for "main.h" in /' > log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "main.h include missing" log log
	fi
}

test_compare_net()
{
	branch="$1"

	rm -rf "${TMPNAME}"
	mkdir "${TMPNAME}"

	upstream_rev="net/master"
	upstream_name="net"

	git archive --remote="${REMOTE}" --format=tar --prefix="${TMPNAME}/batadv/" "$branch" -- net/batman-adv/ Documentation/networking/batman-adv.rst Documentation/ABI/obsolete/sysfs-class-net-batman-adv Documentation/ABI/obsolete/sysfs-class-net-mesh | tar x
	git archive --remote="linux-next/.git/" --format=tar --prefix="${TMPNAME}/net/" "${upstream_rev}" -- net/batman-adv/ Documentation/networking/batman-adv.rst Documentation/ABI/obsolete/sysfs-class-net-batman-adv Documentation/ABI/obsolete/sysfs-class-net-mesh | tar x

	# compare against stripped down MAINTAINERS when available
	git archive --remote="${REMOTE}" --format=tar --prefix="${TMPNAME}/batadv/" "$branch" -- MAINTAINERS | tar x
	git archive --remote="linux-next/.git/" --format=tar --prefix="${TMPNAME}/net/" "${upstream_rev}" -- MAINTAINERS | tar x
	if [ -r "${TMPNAME}/batadv/MAINTAINERS" ]; then
		awk '/^BATMAN ADVANCED$/{f=1};/^$/{f=0};f' "${TMPNAME}/net/MAINTAINERS" > "${TMPNAME}/net/MAINTAINERS.2"
		mv "${TMPNAME}/net/MAINTAINERS.2" "${TMPNAME}/net/MAINTAINERS"
	else
		rm -f "${TMPNAME}/net/MAINTAINERS"
	fi

	# only allow YEAR.RELEASE version numbers and not YEAR.RELEASE.MINOR in net.git
	sed -i 's/^#define BATADV_SOURCE_VERSION "\([0-9][0-9]*\)\.\([0-9][0-9]*\)\(\.[0-9][0-9]*\)*"/#define BATADV_SOURCE_VERSION "\1.\2"/' "${TMPNAME}/batadv/net/batman-adv/main.h"

	# compare against batman_adv.h
	git archive --remote="${REMOTE}" --format=tar --prefix="${TMPNAME}/batadv/" "$branch" -- include/uapi/linux/batman_adv.h | tar x
	git archive --remote="linux-next/.git/" --format=tar --prefix="${TMPNAME}/net/" "${upstream_rev}" -- include/uapi/linux/batman_adv.h | tar x

	diff -ruN "${TMPNAME}"/batadv "${TMPNAME}"/net > /home/sven/projekte/build_test/foo.diff
	diff -ruN "${TMPNAME}"/batadv "${TMPNAME}"/net|diffstat -w 71 -q -p2 > "${TMPNAME}"/log
	if [ -s "${TMPNAME}/log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "${branch}" "difference between ${upstream_name} and batadv ${branch}" "${TMPNAME}"/log "${TMPNAME}"/log
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

	git archive --remote="${REMOTE}" --format=tar --prefix="${TMPNAME}/batadv/" "$branch" -- net/batman-adv/ Documentation/networking/batman-adv.rst Documentation/ABI/obsolete/sysfs-class-net-batman-adv Documentation/ABI/obsolete/sysfs-class-net-mesh | tar x
	git archive --remote="linux-next/.git/" --format=tar --prefix="${TMPNAME}/netnext/" "${upstream_rev}" -- net/batman-adv/ Documentation/networking/batman-adv.rst Documentation/ABI/obsolete/sysfs-class-net-batman-adv Documentation/ABI/obsolete/sysfs-class-net-mesh | tar x

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

		MAKE_CONFIG="CONFIG_BATMAN_ADV_DEBUGFS=y CONFIG_BATMAN_ADV_DEBUG=y CONFIG_BATMAN_ADV_TRACING=y CONFIG_BATMAN_ADV_BLA=y CONFIG_BATMAN_ADV_DAT=y CONFIG_BATMAN_ADV_MCAST=y CONFIG_BATMAN_ADV_NC=y CONFIG_BATMAN_ADV_BATMAN_V=y CONFIG_BATMAN_ADV_SYSFS=y KBUILD_SRC=${LINUX_HEADERS}/${LINUX_DEFAULT_VERSION}"

		# don't touch main.h and files which are required by linux/wait.h, packet.h
		sed -i 's/#include "main.h"/#include "main.h" \/\/ IWYU pragma: keep/' "${spath}"/*c "${spath}"/*.h
		sed -i 's/\/\* for linux\/wait.h \*\//\/\* for linux\/wait.h \*\/ \/\/ IWYU pragma: keep/' "${spath}"/*c "${spath}"/*.h
		echo '#include "types.h"' > net/batman-adv/types.c
		echo 'batman-adv-y += types.o' >> net/batman-adv/Makefile

		make KERNELPATH="${LINUX_HEADERS}/${LINUX_DEFAULT_VERSION}" $MAKE_CONFIG clean
		make KERNELPATH="${LINUX_HEADERS}/${LINUX_DEFAULT_VERSION}" -j1 -k CC="iwyu -ferror-limit=1073741824 -Xiwyu --no_fwd_decls -Xiwyu --prefix_header_includes=keep -Xiwyu --no_default_mappings -Xiwyu --transitive_includes_only -Xiwyu --verbose=1 -Xiwyu --mapping_file=$IWYU_KERNEL_MAPPINGS" $MAKE_CONFIG 2> test

		bpath="$(build_path)"

		git add -f "${bpath}" "${spath}"

		sed -i '/^#include ".*net\/batman-adv\/main\.h"$/d' test
		"${FIX_INCLUDE_SORT}" --nosafe_headers --separate_project_includes="$(pwd)/${bpath}" < test

		# remove extra noise
		git checkout -f -- compat-include
		git checkout -f -- compat-sources
		git checkout -f -- net/batman-adv/Makefile
		git checkout -f -- net/batman-adv/types.h

		"${FIX_INCLUDE_SORT}" --reorder --sort_only "${bpath}"/*.c "${bpath}"/*.h
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
	for c in `"${GENERATE_CONFIG}" "${CONFIGS_PER_RUN}" BLA DAT DEBUGFS DEBUG TRACING NC MCAST BATMAN_V SYSFS`; do
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

			test_sparse "${branch}" "${linux_name}" "${config}"
			test_unused_symbols "${branch}" "${linux_name}" "${config}"
			test_wrong_namespace "${branch}" "${linux_name}" "${config}"

			if [ "$branch" != "${SUBMIT_NET_BRANCH}" ]; then
				test_missing_kerneldoc_symbols "${branch}" "${linux_name}" "${config}"
			fi

			"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}/${linux_name}" -j"${JOBS}" clean

			test_smatch "${branch}" "${linux_name}" "${config}"
			"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}/${linux_name}" -j"${JOBS}" clean
		done
	done
}

testbranch()
{
	branch="$1"
	(
		if [ "$branch" != "${SUBMIT_NET_BRANCH}" ]; then
			test_headers "$branch"
		fi

		if [ "$branch" == "${SUBMIT_NET_NEXT_BRANCH}" ]; then
			test_compare_net_next "${branch}"
		fi

		if [ "$branch" == "${SUBMIT_NET_BRANCH}" ]; then
			test_compare_net "${branch}"
		fi

		rm -rf "${TMPNAME}"
		git archive --remote="${REMOTE}" --format=tar --prefix="${TMPNAME}/" "$branch" | tar x
		cd "${TMPNAME}"

		if [ "$branch" != "${SUBMIT_NET_BRANCH}" ]; then
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

		if [ "$branch" != "${SUBMIT_NET_BRANCH}" ]; then
			# TODO enable checkpatch again when less noisy
			test_checkpatch "${branch}"

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

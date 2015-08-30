#! /bin/bash

cd "$(dirname "$0")"

TO=${TO:="linux-merge@lists.open-mesh.org"}
FROM=${FROM:="postmaster@open-mesh.org"}
REMOTE=${REMOTE:="git+ssh://git@git.open-mesh.org/batman-adv.git"}

LINUX_VERSIONS=$(echo linux-2.6.{29..39} linux-3.{0..19} linux-4.{0..2})
LINUX_DEFAULT_VERSION=linux-4.2

CGCC="$(pwd)/sparse/cgcc"
SPARSE="$(pwd)/sparse/sparse"
CPPCHECK="$(pwd)/cppcheck/cppcheck"
SMATCH="$(pwd)/smatch/smatch"
BRACKET="$(pwd)/testhelpers/bracket_align.py"
CHECKPATCH="$(pwd)/linux-next/scripts/checkpatch.pl"
UNUSED_SYMBOLS="$(pwd)/testhelpers/find_unused_symbols.sh"
CHECK_COPYRIGHT="$(pwd)/testhelpers/check_copyright.sh"
WRONG_NAMESPACE="$(pwd)/testhelpers/find_wrong_namespace.sh"
IWYU_KERNEL_MAPPINGS="$(pwd)/testhelpers/kernel_mappings.iwyu"

MAIL_AGGREGATOR="$(pwd)/testhelpers/mail_aggregator.py"
DB="$(pwd)/error.db"
LINUX_HEADERS="$(pwd)/linux-build/"
GENERATE_CONFIG="$(pwd)/testhelpers/generate_config_params.py"

MAKE="/usr/bin/make"
extra_flags='-D__CHECK_ENDIAN__'
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

	if [ ! -x "${SMATCH}" ]; then
		echo "Required tool smatch missing:"
		echo "    git clone http://repo.or.cz/smatch.git smatch"
		echo "    git -C smatch am ../patches/smatch/9999-smatch-Workaround-to-allow-the-check-of-batadv_iv_og.patch"
		echo "    make -C smatch"
		exit 1
	fi

	if [ ! -x "${CHECKPATCH}" ]; then
		echo "Required tool checkpatch missing:"
		echo "    git clone git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git linux-next"
		echo "    git --git-dir=linux-next/.git/ remote add net-next git://git.kernel.org/pub/scm/linux/kernel/git/davem/net-next.git"
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
				| grep -v "gateway_client.c.*max_gw_factor.* is assigned a value that is never used" \
				| grep -v "gateway_client.c.*max_tq.* is assigned a value that is never used" \
				| grep -v "translation-table.c.*best_tq.* is assigned a value that is never used" \
				| grep -v "main.c.*tvlv_value.* is assigned a value that is never used" \
				| grep -v "bridge_loop_avoidance.c.* The function 'batadv_bla_backbone_table_seq_print_text' is never used" \
				| grep -v "bridge_loop_avoidance.c.* The function 'batadv_bla_claim_table_seq_print_text' is never used" \
				| grep -v "distributed-arp-table.c.* The function 'batadv_dat_cache_seq_print_text' is never used" \
				| grep -v "distributed-arp-table.c.* The function 'batadv_dat_status_update' is never used" \
				| grep -v "network-coding.c.* The function 'batadv_nc_nodes_seq_print_text' is never used" \
				| grep -v "network-coding.c.* The function 'batadv_nc_status_update' is never used" \
				| grep -v "bat_iv_ogm.c.* Possible null pointer dereference: router - otherwise it is redundant to check it against null" \
				| grep -v "gateway_client.c.* Possible null pointer dereference: next_gw - otherwise it is redundant to check it against null" \
				| grep -v "main.c.* Possible null pointer dereference: tvlv_value - otherwise it is redundant to check it against null" \
				| grep -v "Cppcheck cannot find all the include files" \
				|tee log) &> logfull
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "cppcheck $branch" log logfull
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
		"${MAIL_AGGREGATOR}" "${DB}" add "Multiline comment ending at a non-empty line $branch" log log
	fi

	grep -nE "/\*\*..*$" "${path}"/*.c "${path}"/*.h &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "Comment starting with two asterisk non-empty line $branch" log log
	fi

	grep -nE "[^ ]\*/$" "${path}"/*.c "${path}"/*.h &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "Comment ending without space $branch" log log
	fi

	grep -nE "/\*$" "${path}"/*.c "${path}"/*.h &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "Multiline comment starting with empty line $branch" log log
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
				"${MAIL_AGGREGATOR}" "${DB}" add "checkpatch $branch $i" logfull logfull
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
				"${MAIL_AGGREGATOR}" "${DB}" add "bracket_align $branch $i" logfull logfull
			fi
		fi
	done
}

test_sparse()
{
	branch="$1"
	linux_name="$2"
	config="$3"

	(EXTRA_CFLAGS="-Werror $extra_flags" "${MAKE}" CHECK="${SPARSE} -Wsparse-all -Wno-ptr-subtraction-blows -D__CHECK_ENDIAN__" $config CC="${CGCC}" KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" 3>&2 2>&1 1>&3 \
			|grep -v "hard-interface.c.*subtraction of functions? Share your drugs" \
			|grep -v "No such file: c" \
			|tee log) &> logfull
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "sparse $branch ${linux_name} $(simplify_config_string "${config}")" log logfull
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
		"${MAIL_AGGREGATOR}" "${DB}" add "unused_symbols ${branch} ${linux_name} $(simplify_config_string "${config}")" log log
	fi
}

test_wrong_namespace()
{
	branch="$1"
	linux_name="$2"
	config="$3"

	"${WRONG_NAMESPACE}" &> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "wrong namespace symbols ${branch} ${linux_name} $(simplify_config_string "${config}")" log log
	fi
}

test_smatch()
{
	branch="$1"
	linux_name="$2"
	config="$3"
	path="$(source_path)"

	EXTRA_CFLAGS="-Werror $extra_flags" "${MAKE}" CHECK="${SMATCH} -p=kernel --two-passes --file-output" $config CC="${CGCC}" KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" &> /dev/null
	# installed filters:
	#
	# disabled for now: filter batadv_mcast_get_bridge - Linus says this was intentional to support compat code
	#	| grep -v batadv_mcast_get_bridge.*unreachable \
	# ether_addr_equal_64bits - we don't care about upstream "problems"
	# atomic_dec_and_test - yet another upstream regression
	# batadv_mcast_has_bridge - yet another upstream regression
	cat "${path}"/*.smatch \
		| grep -v ether_addr_equal_64bits.*unreachable \
		| grep -v atomic_dec_and_test.*info:\ ignoring\ unreachable\ code. \
		| grep -v batadv_mcast_has_bridge.*info:\ ignoring\ unreachable\ code. \
		> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "smatch $branch ${linux_name} $config" log log
	fi
}

test_copyright()
{
	branch="$1"

	"${CHECK_COPYRIGHT}" \
	&> log
	if [ -s "log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "copyright ${branch}" log log
	fi
}

test_compare_net_next()
{
	branch="$1"

	rm -rf tmp
	mkdir tmp

	git archive --remote="${REMOTE}" --format=tar --prefix="tmp/batadv/" "$branch" -- net/batman-adv/ Documentation/networking/batman-adv.txt Documentation/ABI/testing/sysfs-class-net-batman-adv Documentation/ABI/testing/sysfs-class-net-mesh | tar x
	git archive --remote="linux-next/.git/" --format=tar --prefix="tmp/netnext/" net-next/master -- net/batman-adv/ Documentation/networking/batman-adv.txt Documentation/ABI/testing/sysfs-class-net-batman-adv Documentation/ABI/testing/sysfs-class-net-mesh | tar x

	diff -ruN tmp/batadv tmp/netnext|diffstat -w 71 -q -p2 > tmp/log
	if [ -s "tmp/log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "difference between net-next and batadv ${branch}" tmp/log tmp/log
	fi
}

test_headers()
{
	branch="$1"

	rm -rf tmp
	git clone -b "$branch" "${REMOTE}" tmp
	(
		cd tmp || exit

		MAKE_CONFIG="CONFIG_BATMAN_ADV_NC=y CONFIG_BATMAN_ADV_DEBUG=y KBUILD_SRC=${LINUX_HEADERS}/${LINUX_DEFAULT_VERSION}"

		# don't touch main.h, bat_algo.h and files which are required by linux/wait.h, packet.h
		sed -i 's/#include "main.h"/#include "main.h" \/\/ IWYU pragma: keep/' net/batman-adv/*c net/batman-adv/*.h
		sed -i 's/#include "bat_algo.h"/#include "bat_algo.h" \/\/ IWYU pragma: keep/' net/batman-adv/*c net/batman-adv/*.h
		sed -i 's/\/\* for linux\/wait.h \*\//\/\* for linux\/wait.h \*\/ \/\/ IWYU pragma: keep/' net/batman-adv/*c net/batman-adv/*.h
		sed -i 's/\/\* for packet.h \*\//\/\* for packet.h \*\/ \/\/ IWYU pragma: keep/' net/batman-adv/*c net/batman-adv/*.h

		make KERNELPATH="${LINUX_HEADERS}/${LINUX_DEFAULT_VERSION}" $MAKE_CONFIG clean
		make KERNELPATH="${LINUX_HEADERS}/${LINUX_DEFAULT_VERSION}" -j1 -k CC="iwyu -Xiwyu --prefix_header_includes=keep -Xiwyu --no_default_mappings -Xiwyu --transitive_includes_only -Xiwyu --verbose=1 -Xiwyu --mapping_file=$IWYU_KERNEL_MAPPINGS" $MAKE_CONFIG 2> test

		fix_include --nosafe_headers --noblank_lines --separate_project_includes="$(pwd)/net/batman-adv" < test

		# remove extra noise
		sed -i 's/ \/\/ IWYU pragma: keep//' net/batman-adv/*c net/batman-adv/*.h
		sed -i '/struct batadv_algo_ops;/d' net/batman-adv/main.h
		sed -i '/struct batadv_hard_iface;/d' net/batman-adv/main.h
		sed -i '/struct batadv_orig_node;/d' net/batman-adv/main.h
		sed -i '/struct batadv_priv;/d' net/batman-adv/main.h
		git diff > log

	)

	if [ -s "tmp/log" ]; then
		"${MAIL_AGGREGATOR}" "${DB}" add "headers ${branch}" tmp/log tmp/log
	fi
	rm -rf tmp
}

testbranch()
{
	branch="$1"
	(
		test_headers "$branch"

		if [ "$branch" == "next" ]; then
			test_compare_net_next "${branch}"
		fi

		rm -rf tmp
		git archive --remote="${REMOTE}" --format=tar --prefix="tmp/" "$branch" | tar x
		cd tmp

		test_cppcheck "${branch}"
		test_comments "${branch}"
		test_copyright "${branch}"

		for c in `"${GENERATE_CONFIG}" BLA DAT DEBUG NC MCAST`; do
			config="`echo $c|sed 's/\+/ /g'`"

			for linux_name in ${LINUX_VERSIONS}; do
				rm -f log logfull

				test_sparse "${branch}" "${linux_name}" "${config}"
				test_unused_symbols "${branch}" "${linux_name}" "${config}"
				test_wrong_namespace "${branch}" "${linux_name}" "${config}"
				"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" clean

				if [[ "$linux_name" != "linux-2.6."* ]]; then
				echo "-"${linux_name}
					test_smatch "${branch}" "${linux_name}" "${config}"
					"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" clean
				fi
			done
		done


		test_checkpatch "${branch}"
		test_brackets "${branch}"
	)
}

check_external

# update linux next for checkpatch/net-next
git --git-dir=linux-next/.git/ --work-tree=linux-next remote update --prune
git --git-dir=linux-next/.git/ --work-tree=linux-next reset --hard origin/master

"${MAIL_AGGREGATOR}" "${DB}" create
testbranch "master"
testbranch "next"
"${MAIL_AGGREGATOR}" "${DB}" send "${FROM}" "${TO}" "Build check errors found: `date '+%Y-%m-%d'`"

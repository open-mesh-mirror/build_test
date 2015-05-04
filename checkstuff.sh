#! /bin/bash

cd /home/batman/build_test/

CGCC="$(pwd)/sparse/cgcc"
SPARSE="$(pwd)/sparse/sparse"
CPPCHECK="$(pwd)/cppcheck/cppcheck"
SMATCH="$(pwd)/smatch/smatch"
BRACKET="$(pwd)/bracket_align.py"
CHECKPATCH="$(pwd)/linux-next/scripts/checkpatch.pl"
UNUSED_SYMBOLS="$(pwd)/find_unused_symbols.sh"
CHECK_COPYRIGHT="$(pwd)/check_copyright.sh"
WRONG_NAMESPACE="$(pwd)/find_wrong_namespace.sh"

MAIL_AGGREGATOR="$(pwd)/mail_aggregator.py"
DB="$(pwd)/error.db"
LINUX_HEADERS="$(pwd)/linux-build/"
GENERATE_CONFIG="$(pwd)/generate_config_params.py"

MAKE="/usr/bin/make"

TO="linux-merge@lists.open-mesh.org"
#TO="sven@narfation.org"
FROM="postmaster@open-mesh.org"
REMOTE="git+ssh://git@git.open-mesh.org/batman-adv.git"
extra_flags='-D__CHECK_ENDIAN__'
export LANG=C

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

testbranch()
{
	branch="$1"
	(
		rm -rf tmp
		git archive --remote="${REMOTE}" --format=tar --prefix="tmp/" "$branch" | tar x
		cd tmp

		test_cppcheck "${branch}"
		test_comments "${branch}"
		test_copyright "${branch}"

		for c in `"${GENERATE_CONFIG}" BLA DAT DEBUG NC MCAST`; do
			config="`echo $c|sed 's/\+/ /g'`"
			# 2.6.x
			for i in `seq 29 39`; do
				linux_name="linux-2.6.$i"

				test_sparse "${branch}" "${linux_name}" "${config}"
				test_unused_symbols "${branch}" "${linux_name}" "${config}"
				test_wrong_namespace "${branch}" "${linux_name}" "${config}"
				"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" clean

				#test_smatch "${branch}" "${linux_name}" "${config}"
				#"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" clean
			done

			# 3.x
			for i in `seq 0 19`; do 
				linux_name="linux-3.$i"

				rm -f log logfull

				test_sparse "${branch}" "${linux_name}" "${config}"
				test_unused_symbols "${branch}" "${linux_name}" "${config}"
				test_wrong_namespace "${branch}" "${linux_name}" "${config}"
				"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/linux-3.$i clean

				test_smatch "${branch}" "${linux_name}" "${config}"
				"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" clean
			done

			# 4.x
			for i in `seq 0 0`; do
				linux_name="linux-4.$i"

				rm -f log logfull

				test_sparse "${branch}" "${linux_name}" "${config}"
				test_unused_symbols "${branch}" "${linux_name}" "${config}"
				test_wrong_namespace "${branch}" "${linux_name}" "${config}"
				"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/linux-4.$i clean

				test_smatch "${branch}" "${linux_name}" "${config}"
				"${MAKE}" $config KERNELPATH="${LINUX_HEADERS}"/"${linux_name}" clean
			done
		done


		test_checkpatch "${branch}"
		test_brackets "${branch}"
	)
}

# update linux next for checkpatch
git --git-dir=linux-next/.git/ --work-tree=linux-next remote update --prune
git --git-dir=linux-next/.git/ --work-tree=linux-next reset --hard origin/master

"${MAIL_AGGREGATOR}" "${DB}" create
testbranch "master"
testbranch "next"
"${MAIL_AGGREGATOR}" "${DB}" send "${FROM}" "${TO}" "Build check errors found: `date '+%Y-%m-%d'`"

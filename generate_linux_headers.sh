#! /bin/bash
set -e

LINUX_REPOSITORY=${LINUX_REPOSITORY:="git+ssh://git@git.open-mesh.org/linux-merge.git"}
MAKE_AMD64=${MAKE_AMD64:=1}
. linux-versions

if [ -e "linux-build.img" ]; then
	echo "Please delete linux-build.img before running this script"
	exit 1
fi

if mountpoint -q -- "linux-build"; then
	echo "Please umount linux-build before running this script"
	exit 1
fi

prepare_source()
{
	LINUX_VERSION="$1"

	rm -f ./kernel/configs/debug_kernel.config
	cat >> ./kernel/configs/debug_kernel.config << EOF
# small configuration
CONFIG_SMP=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODVERSIONS=y
CONFIG_MODULE_SRCVERSION_ALL=y
CONFIG_64BIT=y
CONFIG_HW_RANDOM_VIRTIO=y
CONFIG_VIRTIO_BALLOON=y
CONFIG_VSOCKETS=y
CONFIG_VIRTIO_VSOCKETS=y
CONFIG_IOMMU_SUPPORT=y
CONFIG_VIRTIO_IOMMU=y
CONFIG_CRC16=y
CONFIG_LIBCRC32C=y
CONFIG_DEBUG_FS=y
CONFIG_IPV6=y
CONFIG_BRIDGE=y
CONFIG_VLAN_8021Q=y
CONFIG_9P_FS_POSIX_ACL=y
CONFIG_9P_FS_SECURITY=y
CONFIG_EXT4_FS=y
CONFIG_HW_RANDOM=y
CONFIG_SCSI=y
CONFIG_DEVTMPFS=y
CONFIG_PVH=y
CONFIG_PARAVIRT_TIME_ACCOUNTING=y
CONFIG_PARAVIRT_SPINLOCKS=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_BINFMT_MISC=y
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_CROSS_MEMORY_ATTACH=y
CONFIG_UNIX=y
CONFIG_TMPFS=y
CONFIG_CGROUPS=y
CONFIG_BLK_CGROUP=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_NET_CLASSID=y
CONFIG_CGROUP_NET_PRIO=y
CONFIG_CGROUP_PERF=y
CONFIG_CGROUP_SCHED=y
CONFIG_INOTIFY_USER=y
CONFIG_CFG80211=y
CONFIG_DUMMY=y
CONFIG_PACKET=y
CONFIG_VETH=y
CONFIG_IP_MULTICAST=y
CONFIG_NET_IPGRE_DEMUX=y
CONFIG_NET_IPGRE=y
CONFIG_NET_IPGRE_BROADCAST=y
CONFIG_NO_HZ_IDLE=y
CONFIG_CPU_IDLE_GOV_HALTPOLL=y
CONFIG_PVPANIC=y
EOF


	if [ "${LINUX_VERSION}" = "${LINUX_DEFAULT_VERSION}" ]; then
	cat >> ./kernel/configs/debug_kernel.config << EOF
#debug stuff
CONFIG_STACKPROTECTOR=y
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_SOFTLOCKUP_DETECTOR=y
CONFIG_HARDLOCKUP_DETECTOR=y
CONFIG_DETECT_HUNG_TASK=y
CONFIG_SCHED_STACK_END_CHECK=y
CONFIG_DEBUG_RT_MUTEXES=y
CONFIG_DEBUG_SPINLOCK=y
CONFIG_DEBUG_MUTEXES=y
CONFIG_PROVE_LOCKING=y
CONFIG_LOCK_STAT=y
CONFIG_DEBUG_LOCKDEP=y
CONFIG_DEBUG_ATOMIC_SLEEP=y
CONFIG_DEBUG_LIST=y
CONFIG_DEBUG_PLIST=y
CONFIG_DEBUG_SG=y
CONFIG_DEBUG_NOTIFIERS=y
CONFIG_X86_VERBOSE_BOOTUP=y
CONFIG_STRICT_KERNEL_RWX=y
CONFIG_DEBUG_RODATA_TEST=n
CONFIG_STRICT_MODULE_RWX=y
CONFIG_PAGE_EXTENSION=y
CONFIG_DEBUG_PAGEALLOC=y
CONFIG_DEBUG_OBJECTS=y
CONFIG_DEBUG_OBJECTS_FREE=y
CONFIG_DEBUG_OBJECTS_TIMERS=y
CONFIG_DEBUG_OBJECTS_WORK=y
CONFIG_DEBUG_OBJECTS_RCU_HEAD=y
CONFIG_DEBUG_OBJECTS_PERCPU_COUNTER=y
CONFIG_DEBUG_KERNEL=y
CONFIG_DEBUG_KMEMLEAK=y
CONFIG_DEBUG_STACK_USAGE=y
CONFIG_DEBUG_INFO=y
CONFIG_DEBUG_INFO_DWARF5=y
CONFIG_GDB_SCRIPTS=y
CONFIG_READABLE_ASM=y
CONFIG_STACK_VALIDATION=y
CONFIG_WQ_WATCHDOG=y
CONFIG_DEBUG_KOBJECT_RELEASE=y
CONFIG_DEBUG_WQ_FORCE_RR_CPU=y
CONFIG_DEBUG_SECTION_MISMATCH=y
CONFIG_UNWINDER_ORC=y
CONFIG_FTRACE=y
CONFIG_FUNCTION_TRACER=y
CONFIG_FUNCTION_GRAPH_TRACER=y
CONFIG_FTRACE_SYSCALLS=y
CONFIG_TRACER_SNAPSHOT=y
CONFIG_TRACER_SNAPSHOT_PER_CPU_SWAP=y
CONFIG_STACK_TRACER=y
CONFIG_UPROBE_EVENTS=y
CONFIG_DYNAMIC_FTRACE=y
CONFIG_FUNCTION_PROFILER=y
CONFIG_HIST_TRIGGERS=y
CONFIG_SYMBOLIC_ERRNAME=y
CONFIG_DYNAMIC_DEBUG=y
CONFIG_PRINTK_TIME=y
CONFIG_PRINTK_CALLER=y
CONFIG_DEBUG_MISC=y
CONFIG_SLUB_DEBUG=y
EOF
	fi

	if [ "${MAKE_AMD64}" != "0" ]; then
		cat >> ./kernel/configs/debug_kernel.config << EOF
CONFIG_64BIT=y
EOF
	fi

	# avoid build of vmlinux
	echo "CONFIG_MODVERSIONS=n" >> ./kernel/configs/debug_kernel.config

	make allnoconfig
	make kvm_guest.config
	make debug_kernel.config

	if [ "${LINUX_VERSION}" = "${LINUX_DEFAULT_VERSION}" ]; then
		../../smatch/smatch_scripts/build_kernel_data.sh
	else
		make prepare
		make modules
	fi
}

clean_source()
{
	find . -type f -iname "*.S" -print0 | xargs --null rm -f
	find . -type f -iname "*.c" | grep -v -e '/scripts/' | xargs -d '\n' rm -f
	find . -type f -iname "*.o" -print0 | xargs --null rm -f
	find . -type f -iname "*.cmd" -not -iname "auto.conf.cmd" -print0 | xargs --null rm -f
	find . -type f -iname "modules.order" -print0 | xargs --null rm -f
	find . -type f -iname "vmlinu*" -not -iname "*.h" -print0 | xargs --null rm -f
	find arch -maxdepth 1 -type d -not -iname i386 -not -iname x86_64 -not -iname x86 -not -iname arch -print0 | xargs --null rm -rf
	find include -maxdepth 1 -type d -iname "asm-*" -not -iname asm-i386 -not -iname asm-x86_64 -not -iname asm-x86 -not -iname asm-generic  -not -iname include -print0 | xargs --null rm -rf
	rm -rf Documentation
	rm -f linux
	find |grep -v -e '/include/' -e '/arch/' -e '/scripts/'|grep "\.h$"|xargs -d '\n' rm -f
	rm -f .config.old
}


prepare_sparse()
{
	outpath="linux-build/sparse/"
	git clone git://git.kernel.org/pub/scm/devel/sparse/sparse.git "${outpath}"
	git -C "${outpath}" reset --hard ce1a6720f69e6233ec9abd4e9aae5945e05fda41
	git -C "${outpath}" am ../../patches/sparse/0001-Disable-warning-directive-in-macro-s-argument-list-w.patch
	CFLAGS="-march=native -O3" make -C "${outpath}"
}

prepare_smatch()
{
	outpath="linux-build/smatch/"

	git clone https://repo.or.cz/smatch.git/ "${outpath}"
	git -C "${outpath}" reset --hard 721ca29e1f857b9bda9d55dda989e0fb1c72e590
	git -C "${outpath}" am ../../patches/smatch/9999-smatch-disable-verbose-check_unused_ret.patch
	CFLAGS="-march=native -O3" make -C "${outpath}"
}

prepare_linux_headers()
{
	mkdir -p linux-build/linux/
	for version in ${LINUX_VERSIONS}; do
		outpath="linux-build/linux/${version}/"
		git archive --remote="${LINUX_REPOSITORY}" --format tar --prefix="${outpath}" "${version}"|tar x
		[ ! -d "patches/linux/${version}" ] || git apply --directory="${outpath}" "patches/linux/${version}/"*.patch

		(
			set -e
			cd "${outpath}"

			prepare_source "${version}"
			clean_source
		)
	done
}

rm -f linux-build.img
rm -rf linux-build
mkdir -p linux-build/

prepare_sparse
prepare_smatch
prepare_linux_headers

mksquashfs linux-build linux-build.img
rm -rf linux-build
mkdir -p linux-build

echo "done"
echo "Please mount the image:"
echo "    mount -o loop linux-build.img linux-build"

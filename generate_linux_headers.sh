#! /bin/bash
set -e

LINUX_REPOSITORY=${LINUX_REPOSITORY:="git+ssh://git@git.open-mesh.org/linux-merge.git"}
MAKE_AMD64=${MAKE_AMD64:=1}

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
	rm -f .config
	make allnoconfig
	cat >> .config << EOF
CONFIG_SMP=y
CONFIG_EMBEDDED=n
CONFIG_EXPERT=n
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODVERSIONS=y
CONFIG_MODULE_SRCVERSION_ALL=y
CONFIG_HW_RANDOM_VIRTIO=y
CONFIG_NET_9P_VIRTIO=y
CONFIG_SCSI_VIRTIO=y
CONFIG_VIRTIO_BALLOON=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_VIRTIO_INPUT=y
CONFIG_VIRTIO_MMIO=y
CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_PCI_LEGACY=y
CONFIG_CRC16=y
CONFIG_LIBCRC32C=y
CONFIG_CRYPTO_SHA512=y
CONFIG_NET=y
CONFIG_INET=y
CONFIG_DEBUG_FS=y
CONFIG_IPV6=y
CONFIG_BRIDGE=y
CONFIG_VLAN_8021Q=y
CONFIG_WIRELESS=n
CONFIG_NET_9P=y
CONFIG_NETWORK_FILESYSTEMS=y
CONFIG_9P_FS=y
CONFIG_9P_FS_POSIX_ACL=y
CONFIG_9P_FS_SECURITY=y
CONFIG_BLOCK=y
CONFIG_BLK_DEV=y
CONFIG_EXT4_FS=y
CONFIG_EXT4_USE_FOR_EXT23=y
CONFIG_TTY=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_HW_RANDOM=y
CONFIG_VHOST_RING=y
CONFIG_GENERIC_ALLOCATOR=y
CONFIG_SCSI_LOWLEVEL=y
CONFIG_SCSI=y
CONFIG_NETDEVICES=y
CONFIG_NET_CORE=y
CONFIG_DEVTMPFS=y
CONFIG_HYPERVISOR_GUEST=y
CONFIG_PARAVIRT=y
CONFIG_KVM_GUEST=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_BINFMT_MISC=y
CONFIG_PCI=y
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
CONFIG_CGROUP_HUGETLB=y
CONFIG_CGROUP_NET_CLASSID=y
CONFIG_CGROUP_NET_PRIO=y
CONFIG_CGROUP_PERF=y
CONFIG_CGROUP_SCHED=y
CONFIG_DEVPTS_MULTIPLE_INSTANCES=y
CONFIG_INOTIFY_USER=y
CONFIG_FHANDLE=y
CONFIG_E1000=y
CONFIG_CPU_FREQ=y
CONFIG_CONFIG_X86_ACPI_CPUFREQ=y
CONFIG_CPU_FREQ_GOV_ONDEMAND=y
CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y
CONFIG_CFG80211=y
CONFIG_PARAVIRT_SPINLOCKS=y
CONFIG_DUMMY=y
CONFIG_PACKET=y
CONFIG_VETH=y
CONFIG_IP_MULTICAST=y
CONFIG_NET_IPGRE_DEMUX=y
CONFIG_NET_IP_TUNNEL=y
CONFIG_NET_IPGRE=y
CONFIG_NET_IPGRE_BROADCAST=y

# CONFIG_CC_STACKPROTECTOR_STRONG is not set
CONFIG_LOCKUP_DETECTOR=y
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
CONFIG_DEBUG_PI_LIST=y
CONFIG_DEBUG_SG=y
CONFIG_DEBUG_NOTIFIERS=y
CONFIG_PROVE_RCU_REPEATEDLY=y
CONFIG_SPARSE_RCU_POINTER=y
CONFIG_DEBUG_STRICT_USER_COPY_CHECKS=y
CONFIG_X86_VERBOSE_BOOTUP=y
CONFIG_DEBUG_RODATA=y
CONFIG_DEBUG_RODATA_TEST=n
CONFIG_DEBUG_SET_MODULE_RONX=y
CONFIG_PAGE_EXTENSION=y
CONFIG_DEBUG_PAGEALLOC=y
CONFIG_DEBUG_OBJECTS=y
CONFIG_DEBUG_OBJECTS_FREE=y
CONFIG_DEBUG_OBJECTS_TIMERS=y
CONFIG_DEBUG_OBJECTS_WORK=y
CONFIG_DEBUG_OBJECTS_RCU_HEAD=y
CONFIG_DEBUG_OBJECTS_PERCPU_COUNTER=y
CONFIG_DEBUG_KMEMLEAK=y
CONFIG_DEBUG_STACK_USAGE=y
CONFIG_DEBUG_STACKOVERFLOW=y
CONFIG_DEBUG_INFO=y
CONFIG_DEBUG_INFO_DWARF4=y
CONFIG_GDB_SCRIPTS=y
CONFIG_READABLE_ASM=y
CONFIG_STACK_VALIDATION=y
CONFIG_WQ_WATCHDOG=y
CONFIG_DEBUG_KOBJECT_RELEASE=y
CONFIG_DEBUG_WQ_FORCE_RR_CPU=y
CONFIG_OPTIMIZE_INLINING=y
CONFIG_ENABLE_MUST_CHECK=y
CONFIG_ENABLE_WARN_DEPRECATED=y
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
EOF
	if [ "${MAKE_AMD64}" != "0" ]; then
		cat >> .config << EOF
CONFIG_64BIT=y
CONFIG_X86_VSYSCALL_EMULATION=n
CONFIG_IA32_EMULATION=n
EOF
	fi
	make oldnoconfig
	make prepare
	make modules
}

clean_source()
{
	find . -iname "*.S" -print0 | xargs --null rm -f
	find . -iname "*.c" | grep -v -e '/scripts/' | xargs -d '\n' rm -f
	find . -iname "*.o" -print0 | xargs --null rm -f
	find . -iname "*.cmd" -not -iname "auto.conf.cmd" -print0 | xargs --null rm -f
	find . -iname "modules.order" -print0 | xargs --null rm -f
	find . -iname "vmlinu*" -not -iname "*.h" -print0 | xargs --null rm -f
	find arch -maxdepth 1 -type d -not -iname i386 -not -iname x86_64 -not -iname x86 -not -iname arch -print0 | xargs --null rm -rf
	find include -maxdepth 1 -type d -iname "asm-*" -not -iname asm-i386 -not -iname asm-x86_64 -not -iname asm-x86 -not -iname asm-generic  -not -iname include -print0 | xargs --null rm -rf
	rm -rf Documentation
	rm -f linux
	find |grep -v -e '/include/' -e '/arch/' -e '/scripts/'|grep "\.h$"|xargs -d '\n' rm -f
	rm -f .config.old
}

generate_squashfs()
{
	set -e
	rm -f linux-build.img
	rm -rf linux-build
	mkdir -p linux-build
	mv linux-3* linux-build
	mv linux-4* linux-build
	mksquashfs linux-build linux-build.img
	rm -rf linux-build
	echo ok
}

for i in `seq 16 19`; do
	git archive --remote="${LINUX_REPOSITORY}" --format tar --prefix=linux-3.${i}/ v3.${i}|tar x
	(
		cd "linux-3.${i}" || exit
		if [ -d "../patches/v3.${i}" ]; then
			for p in "../patches/v3.${i}/"*.patch; do
				patch -p1 -i "${p}"
			done
		fi
		prepare_source "3" "${i}"

		clean_source
	)
done

for i in `seq 0 18`; do
	git archive --remote="${LINUX_REPOSITORY}" --format tar --prefix=linux-4.${i}/ v4.${i}|tar x
	(
		cd "linux-4.${i}" || exit
		if [ -d "../patches/v4.${i}" ]; then
			for p in "../patches/v4.${i}/"*.patch; do
				patch -p1 -i "${p}"
			done
		fi
		prepare_source "4" "${i}"

		clean_source
	)
done

generate_squashfs

echo "done"
echo "Please mount the image:"
echo "    mkdir -p linux-build"
echo "    mount -o loop linux-build.img linux-build"

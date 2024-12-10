#!/bin/bash

set -e -u -o pipefail

: "${EXT_MOUNT_OPTIONS:="-o inlinecrypt"}"
: "${F2FS_MOUNT_OPTIONS:="-o inlinecrypt"}"
export EXT_MOUNT_OPTIONS F2FS_MOUNT_OPTIONS

create_partitions()
{
	local rootfs disk partnum part_size

	rootfs=$(basename "$(findmnt / -o SOURCE -n)")
	disk=${rootfs//[0-9]/}
	partnum=$(echo "$rootfs" | grep -o '[0-9]*$')
	echo "rootfs is /dev/$rootfs (partition $partnum on disk /dev/$disk)"
	part_size=$(( 8 * $(tune2fs -l "/dev/$rootfs" | awk '/Block count/{print $3}') ))
	start=$(<"/sys/class/block/$rootfs/start")

	echo "Root filesystem is $part_size sectors starting at $start"
	resizepart "/dev/$disk" "$partnum" "$part_size"
	(( start += part_size ))
	partnum=100

	part_size=10485760
	echo "TEST_DEV is /dev/$disk$partnum: $part_size sectors starting at $start"
	if [ -e "/dev/$disk$partnum" ]; then
		delpart "/dev/$disk" "$partnum"
	fi
	addpart "/dev/$disk" "$partnum" "$start" "$part_size"
	ln -sf "/dev/$disk$partnum" /dev/TEST_DEV
	(( start += part_size ))
	(( partnum++ ))

	part_size=10485760
	echo "SCRATCH_DEV is /dev/$disk$partnum: $part_size sectors starting at $start"
	if [ -e "/dev/$disk$partnum" ]; then
		delpart "/dev/$disk" "$partnum"
	fi
	addpart "/dev/$disk" "$partnum" "$start" "$part_size"
	ln -sf "/dev/$disk$partnum" /dev/SCRATCH_DEV
	(( start += part_size ))
	(( partnum++ ))
}

if [ ! -e /dev/TEST_DEV ]; then
	create_partitions
fi

F2FS=false
while (( $# > 0 )); do
	case $1 in
	--update)
		( cd ~/xfstests-dev && make -j8 install )
		;;
	--f2fs)
		F2FS=true
		;;
	*)
		break
		;;
	esac
	shift
done

TEST_DEV=$(readlink -f /dev/TEST_DEV)
TEST_DIR=/mnt/test
SCRATCH_DEV=$(readlink -f /dev/SCRATCH_DEV)
SCRATCH_MNT=/mnt/scratch
export TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT
mkdir -p $TEST_DIR $SCRATCH_MNT
if $F2FS; then
	if ! dump.f2fs "$TEST_DEV" 2>/dev/null | grep -q '\<encrypt\>'; then
		mkfs.f2fs -f -O encrypt "$TEST_DEV"
	fi
else
	if ! tune2fs -l "$TEST_DEV" 2>/dev/null | grep -q '\<encrypt\>'; then
		mkfs.ext4 -F -O encrypt "$TEST_DEV"
	fi
fi
cd /var/lib/xfstests
./check "$@"

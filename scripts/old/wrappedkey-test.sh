#!/bin/sh

set -e -u

BLOCKDEV=/dev/disk/by-partlabel/userdata

generate=false
if [ "${1:-}" = "--generate" ]; then
	generate=true
fi

# create and mount an ext4 filesystem that supports encryption
if mountpoint /mnt > /dev/null 1>&2; then
	umount /mnt
fi
if ! tune2fs -l /dev/disk/by-partlabel/userdata \
	| grep -q '\<stable_inodes\>.*\<encrypt\>'
then
	mkfs.ext4 -F -O encrypt,stable_inodes $BLOCKDEV
fi
mount $BLOCKDEV -o inlinecrypt /mnt

if $generate; then
	echo "Generating hardware-wrapped key"
	fscryptctl generate_hw_wrapped_key $BLOCKDEV \
		> /tmp/key.longterm
else
	echo "Importing hardware-wrapped key"
	dd if=/dev/zero bs=32 count=1 | tr '\0' 'X' \
		| fscryptctl import_hw_wrapped_key $BLOCKDEV > /tmp/key.longterm
fi

echo "Preparing hardware-wrapped key"
fscryptctl prepare_hw_wrapped_key $BLOCKDEV < /tmp/key.longterm \
	> /tmp/key.ephemeral

echo "Adding hardware-wrapped key"
keyid=$(fscryptctl add_key --hw-wrapped-key < /tmp/key.ephemeral /mnt)

echo "Creating encrypted directory"
rm -rf /mnt/dir
mkdir /mnt/dir
fscryptctl set_policy --hw-wrapped-key --iv-ino-lblk-64 "$keyid" /mnt/dir

echo "Writing data to encrypted file"
dd if=/dev/zero bs=4096 count=100 of=/mnt/dir/file

echo "Syncing"
sync

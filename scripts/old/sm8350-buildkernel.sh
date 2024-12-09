#!/bin/bash

# Builds a boot.img file for sm8350 containing an upstream kernel and a minimal
# Linux initramfs.  Based on
# https://www.linaro.org/blog/let-s-boot-the-mainline-linux-kernel-on-qualcomm-devices
#
# To use, first set the following variables:
#   Linux source directory:
LINUX_DIR=$HOME/src/linux
#   Initramfs to use (see the above blog post for where to get)
INITRAMFS=$HOME/os/initramfs-test-image-qemuarm64-20211018075234-954.rootfs.cpio.gz
#   mkbootimg script (see the above blog post for where to get)
MKBOOTIMG=$HOME/src/skales/mkbootimg
#
# Then run this script to build boot.img.
#
# Then boot the sm8350-hdk into fastboot mode.  To do this, unplug the power and
# USB-C cables, then plug in the power cable.  Then, plug in the USB cable and
# immediately hold vol-down for several seconds.
#
# Then run 'fastboot boot $LINUX_DIR/boot.img'.

set -e -u -o pipefail
SCRIPTDIR=$(dirname "$(realpath "$0")")

CHAINLOAD_USERDATA=false
UPDATE_VIA_NETWORK=false
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
MAKE="make -j$(getconf _NPROCESSORS_ONLN)"
FSCRYPTCTL_DIR=$SCRIPTDIR/..
WRAPPEDKEY_TEST_SCRIPT=$SCRIPTDIR/wrappedkey-test.sh

usage()
{
	echo "Usage: $0 [--chainload-userdata] [--update-via-network]"
}

parse_options()
{
	local longopts="help,chainload-userdata,update-via-network"
	local options

	if ! options=$(getopt -o "" -l "$longopts" -- "$@"); then
		usage 1>&2
		exit 2
	fi

	eval set -- "$options"
	while (( $# >= 0 )); do
		case "$1" in
		--help)
			usage
			exit 0
			;;
		--chainload-userdata)
			CHAINLOAD_USERDATA=true
			;;
		--update-via-network)
			UPDATE_VIA_NETWORK=true
			;;
		--)
			shift
			break
			;;
		*)
			echo 1>&2 "Invalid option: \"$1\""
			usage 1>&2
			exit 2
			;;
		esac
		shift
	done

	if $UPDATE_VIA_NETWORK; then
		CHAINLOAD_USERDATA=true
	fi
}

make_kernel_and_modules()
{
	echo "Making kernel and modules"
	$MAKE defconfig
	cat >> .config << EOF
CONFIG_BLK_INLINE_ENCRYPTION=y
CONFIG_SCSI_UFS_CRYPTO=y
CONFIG_FS_ENCRYPTION=y
CONFIG_FS_ENCRYPTION_INLINE_CRYPT=y
CONFIG_F2FS_FS=y
EOF
	$MAKE olddefconfig
	$MAKE Image.gz dtbs modules
}

make_initramfs()
{
	echo "Making initramfs"
	rm -rf initramfs-extra
	$MAKE modules_install INSTALL_MOD_PATH=initramfs-extra INSTALL_MOD_STRIP=1
	mkdir -p initramfs-extra/{bin,sbin}
	aarch64-linux-gnu-gcc -O2 -Wall "$FSCRYPTCTL_DIR/fscryptctl.c" \
		-o initramfs-extra/bin/fscryptctl
	cp "$WRAPPEDKEY_TEST_SCRIPT" initramfs-extra/bin/wrappedkey-test.sh
	if $CHAINLOAD_USERDATA; then
		cat > initramfs-extra/sbin/init << EOF
#!/bin/ash

mount devtmpfs -t devtmpfs /dev
modprobe -a phy-qcom-qmp ufs_qcom
mount /dev/sda11 /mnt
exec /sbin/switch_root /mnt /sbin/init
EOF
		chmod 755 initramfs-extra/sbin/init
	fi
	cp "$INITRAMFS" initramfs.img.gz
	GZIP="gzip -9"
	if type -P libdeflate-gzip > /dev/null; then
		GZIP="libdeflate-gzip -12"
	fi
	( cd initramfs-extra; find . | cpio -o -H newc | $GZIP ) >> initramfs.img.gz
}

make_bootimage()
{
	CMDLINE="ignore_loglevel earlycon"

	echo "Making bootimage"
	cat arch/arm64/boot/Image.gz \
	    arch/arm64/boot/dts/qcom/sm8350-hdk.dtb > Image.gz+dtb
	$MKBOOTIMG --kernel Image.gz+dtb \
		--cmdline "$CMDLINE" --ramdisk initramfs.img.gz \
		--base 0x80000000 --pagesize 2048 --output boot.img
	echo "Created $LINUX_DIR/boot.img"
}

install_bootimage()
{
	echo "Installing bootimage"
	rsync -rav initramfs-extra/lib/modules/ root@alarm:/lib/modules/
	scp boot.img root@alarm:
	ssh root@alarm "cp boot.img /dev/disk/by-partlabel/boot_a && \
			cp boot.img /dev/disk/by-partlabel/boot_b && \
			sync && reboot"
}

parse_options "$@"
cd "$LINUX_DIR"
make_kernel_and_modules
make_initramfs
make_bootimage
if $UPDATE_VIA_NETWORK; then
	install_bootimage
fi
echo "Done"

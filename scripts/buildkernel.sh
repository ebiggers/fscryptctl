#!/bin/bash
#
# Builds a kernel for the SM8350 or SM8450 HDK, and packs it up into a boot.img
# that is set up to boot into the userdata partition ("root=/dev/sda11").  The
# root filesystem of a Linux distro should be flashed onto this partition first.
#
# The resulting boot.img can be booted by running 'fastboot boot boot.img' while
# the board is in fastboot mode.  To get the board into fastboot mode, unplug
# the power and USB-C cables, then plug in the power cable, then plug in the USB
# cable and immediately hold vol-down for several seconds.

set -e -u -o pipefail
SCRIPTDIR=$(dirname "$(realpath "$0")")

BOARD=$1
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
MAKE="make -j$(getconf _NPROCESSORS_ONLN)"

if ! type -P mkbootimg &> /dev/null; then
	echo 1>&2 "mkbootimg is not installed.  Get it from git://codeaurora.org/quic/kernel/skales"
	exit 1
fi
if [ ! -e MAINTAINERS ]; then
	echo 1>&2 "This script must be run from a Linux source directory"
	exit 1
fi

cp $SCRIPTDIR/kconfig .config
$MAKE olddefconfig
$MAKE Image.gz dtbs
echo placeholder > ramdisk
cat arch/arm64/boot/Image.gz \
    arch/arm64/boot/dts/qcom/$BOARD-hdk.dtb > Image.gz+dtb
mkbootimg --kernel Image.gz+dtb \
	--cmdline "earlycon root=/dev/sda11 rw" \
	--ramdisk ramdisk \
	--base 0x80000000 \
	--pagesize 2048 \
	--output boot.img
echo "Created boot.img"

#!/bin/bash
#
# Retron SQ CFW SD Card Image Builder
# Creates a bootable SD card image with all required partitions
#

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
TOP_DIR=$(cd "$SCRIPT_DIR/../../.."; pwd)
ROCKDEV="$TOP_DIR/rockdev"
OUTPUT_DIR="$TOP_DIR/out"

# Configuration
SDCARD_SIZE_MB=128
VERSION="${CFW_VERSION:-1.1.0}"
SDCARD_IMG="${OUTPUT_DIR}/retron-sq-cfw-v${VERSION}.img"

# Partition layout (sectors, 512 bytes each)
# Must match the Hyperkin original layout
SECTOR_SIZE=512
IDBLOADER_START=2048      # 1MB offset
UBOOT_START=8192          # 4MB offset
TRUST_START=16384         # 8MB offset
BOOT_START=24576          # 12MB offset (24MB partition)
ROOTFS_START=73728        # 36MB offset (24MB partition)
USERDATA_START=122880     # 60MB offset (remaining space)

# Source files - use readlink to resolve symlinks
IDBLOADER_IMG="${ROCKDEV}/idbloader-sdcard.img"
UBOOT_IMG="$TOP_DIR/u-boot/uboot.img"
TRUST_IMG="$TOP_DIR/u-boot/trust.img"
BOOT_IMG="$TOP_DIR/kernel/zboot.img"
ROOTFS_IMG="${OUTPUT_DIR}/rootfs.squashfs"
USERDATA_IMG="${OUTPUT_DIR}/userdata.img"

echo "=============================================="
echo "Retron SQ CFW SD Card Image Builder v${VERSION}"
echo "=============================================="

# Verify source files
echo "Checking source files..."
for img in "$IDBLOADER_IMG" "$UBOOT_IMG" "$TRUST_IMG" "$BOOT_IMG" "$ROOTFS_IMG" "$USERDATA_IMG"; do
    if [ ! -f "$img" ]; then
        echo "ERROR: Missing required file: $img"
        exit 1
    fi
    echo "  Found: $(basename $img) ($(stat -c%s $img) bytes)"
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create empty image
echo ""
echo "Creating ${SDCARD_SIZE_MB}MB SD card image..."
dd if=/dev/zero of="$SDCARD_IMG" bs=1M count=${SDCARD_SIZE_MB} status=none

# Create GPT partition table using sgdisk
echo "Creating GPT partition table..."
sgdisk --clear "$SDCARD_IMG" >/dev/null
sgdisk --new=1:${IDBLOADER_START}:$((UBOOT_START-1)) --change-name=1:idbloader --typecode=1:8301 "$SDCARD_IMG" >/dev/null
sgdisk --new=2:${UBOOT_START}:$((TRUST_START-1)) --change-name=2:uboot --typecode=2:8301 "$SDCARD_IMG" >/dev/null
sgdisk --new=3:${TRUST_START}:$((BOOT_START-1)) --change-name=3:trust --typecode=3:8301 "$SDCARD_IMG" >/dev/null
sgdisk --new=4:${BOOT_START}:$((ROOTFS_START-1)) --change-name=4:boot --typecode=4:8301 "$SDCARD_IMG" >/dev/null
sgdisk --new=5:${ROOTFS_START}:$((USERDATA_START-1)) --change-name=5:rootfs --typecode=5:8301 "$SDCARD_IMG" >/dev/null
sgdisk --new=6:${USERDATA_START}:0 --change-name=6:userdata --typecode=6:0700 "$SDCARD_IMG" >/dev/null

# Set rootfs partition GUID (required by kernel for mounting)
sgdisk --partition-guid=5:614e0000-0000-4b53-8000-1d28000054a9 "$SDCARD_IMG" >/dev/null

# Write partition contents using dd
echo "Writing partition contents..."

echo "  idbloader @ sector ${IDBLOADER_START}..."
dd if="$IDBLOADER_IMG" of="$SDCARD_IMG" seek=${IDBLOADER_START} bs=${SECTOR_SIZE} conv=notrunc status=none

echo "  uboot @ sector ${UBOOT_START}..."
dd if="$UBOOT_IMG" of="$SDCARD_IMG" seek=${UBOOT_START} bs=${SECTOR_SIZE} conv=notrunc status=none

echo "  trust @ sector ${TRUST_START}..."
dd if="$TRUST_IMG" of="$SDCARD_IMG" seek=${TRUST_START} bs=${SECTOR_SIZE} conv=notrunc status=none

echo "  boot @ sector ${BOOT_START}..."
dd if="$BOOT_IMG" of="$SDCARD_IMG" seek=${BOOT_START} bs=${SECTOR_SIZE} conv=notrunc status=none

echo "  rootfs @ sector ${ROOTFS_START}..."
dd if="$ROOTFS_IMG" of="$SDCARD_IMG" seek=${ROOTFS_START} bs=${SECTOR_SIZE} conv=notrunc status=none

echo "  userdata @ sector ${USERDATA_START}..."
dd if="$USERDATA_IMG" of="$SDCARD_IMG" seek=${USERDATA_START} bs=${SECTOR_SIZE} conv=notrunc status=none

# Show partition table
echo ""
echo "Partition layout:"
sgdisk -p "$SDCARD_IMG"

# Calculate checksum
echo ""
echo "Calculating SHA256..."
SHA256=$(sha256sum "$SDCARD_IMG" | cut -d" " -f1)

echo ""
echo "=============================================="
echo "SUCCESS: SD card image created"
echo "  File: $SDCARD_IMG"
echo "  Size: $(stat -c%s $SDCARD_IMG) bytes (${SDCARD_SIZE_MB} MB)"
echo "  SHA256: $SHA256"
echo "=============================================="

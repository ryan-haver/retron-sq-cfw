#!/bin/sh
#
# RetroSQ Enhanced CFW - First Boot Setup
# Creates and formats the FAT32 ROMs partition on first boot
#
# This script runs during S20firstboot to set up the ROM storage partition
# on an inserted SD card. Only runs if an SD card is present with free space.
#

# Don't use set -e - we want graceful failure handling
MARKER_FILE="/var/.first_boot_complete"
LOG_FILE="/tmp/first-boot-setup.log"
SDCARD="/dev/mmcblk0"
ROMS_MOUNT="/mnt/roms"

log() {
    echo "[first-boot] $1" | tee -a $LOG_FILE
    echo "[first-boot] $1" > /dev/console 2>/dev/null || true
}

# Check if already completed
if [ -f "$MARKER_FILE" ]; then
    log "First boot already completed, skipping setup"
    exit 0
fi

log "=== RetroSQ First Boot Setup ==="

# Check if SD card device exists (not present on NAND-only systems)
if [ ! -b "$SDCARD" ]; then
    log "No SD card device found at $SDCARD - running on NAND flash"
    log "Skipping ROM partition setup (use USB or network for ROMs)"
    touch "$MARKER_FILE"
    exit 0
fi

# Find the last partition number
LAST_PART=$(fdisk -l $SDCARD 2>/dev/null | grep "^${SDCARD}p" | tail -1 | sed 's/.*p\([0-9]*\).*/\1/')

if [ -z "$LAST_PART" ]; then
    log "No partitions found on $SDCARD - SD card may not be properly formatted"
    log "Skipping ROM partition setup"
    touch "$MARKER_FILE"
    exit 0
fi

NEXT_PART=$((LAST_PART + 1))
ROMS_PARTITION="${SDCARD}p${NEXT_PART}"

log "Last partition: ${SDCARD}p${LAST_PART}"
log "ROM partition will be: $ROMS_PARTITION"

# Check if ROM partition already exists
if [ -b "$ROMS_PARTITION" ]; then
    log "ROM partition already exists at $ROMS_PARTITION"
    
    # Check if it's formatted
    if blkid "$ROMS_PARTITION" > /dev/null 2>&1; then
        log "Partition is already formatted, skipping"
        touch "$MARKER_FILE"
        exit 0
    fi
fi

# Get the end sector of the last partition
LAST_PART_INFO=$(fdisk -l $SDCARD 2>/dev/null | grep "^${SDCARD}p${LAST_PART}")
LAST_END_SECTOR=$(echo "$LAST_PART_INFO" | awk '{print $3}')

# Get total sectors on the disk
TOTAL_SECTORS=$(fdisk -l $SDCARD 2>/dev/null | grep "^Disk ${SDCARD}:" | grep -o "[0-9]* sectors" | awk '{print $1}')

if [ -z "$LAST_END_SECTOR" ] || [ -z "$TOTAL_SECTORS" ]; then
    log "Could not determine disk geometry - SD card may not support partitioning"
    log "Skipping ROM partition setup"
    touch "$MARKER_FILE"
    exit 0
fi

# Calculate start sector for new partition (next sector after last partition)
NEW_START=$((LAST_END_SECTOR + 1))

# Leave 1MB at the end for safety
NEW_END=$((TOTAL_SECTORS - 2048))

# Check if there's enough space (at least 100MB)
AVAILABLE_SECTORS=$((NEW_END - NEW_START))
MIN_SECTORS=$((100 * 1024 * 1024 / 512))  # 100MB in sectors

if [ "$AVAILABLE_SECTORS" -lt "$MIN_SECTORS" ]; then
    log "WARNING: Not enough space for ROM partition (need 100MB, have $((AVAILABLE_SECTORS * 512 / 1024 / 1024))MB)"
    log "Skipping partition creation"
    touch "$MARKER_FILE"
    exit 0
fi

log "Creating ROM partition: sectors $NEW_START to $NEW_END"
log "Available space: $((AVAILABLE_SECTORS * 512 / 1024 / 1024))MB"

# Create the partition using sfdisk (more scriptable than fdisk)
{
    echo "${NEW_START},${AVAILABLE_SECTORS},c"  # Type c = FAT32 LBA
} | sfdisk -a ${SDCARD} -N ${NEXT_PART} 2>&1 | tee -a $LOG_FILE

# Re-read partition table
partprobe $SDCARD 2>/dev/null || true
sleep 2

# Wait for partition to appear
for i in 1 2 3 4 5; do
    if [ -b "$ROMS_PARTITION" ]; then
        break
    fi
    log "Waiting for partition to appear... ($i/5)"
    sleep 1
done

if [ ! -b "$ROMS_PARTITION" ]; then
    log "WARNING: Partition creation failed - $ROMS_PARTITION not found"
    log "This may be expected on NAND-based systems"
    touch "$MARKER_FILE"
    exit 0
fi

log "Formatting $ROMS_PARTITION as FAT32..."
mkfs.vfat -F 32 -n "RETROSQ" $ROMS_PARTITION 2>&1 | tee -a $LOG_FILE

# Create mount point
mkdir -p $ROMS_MOUNT

# Mount and create directory structure
log "Creating directory structure..."
mount -t vfat $ROMS_PARTITION $ROMS_MOUNT

mkdir -p $ROMS_MOUNT/Roms
mkdir -p $ROMS_MOUNT/Roms/GB
mkdir -p $ROMS_MOUNT/Roms/GBC
mkdir -p $ROMS_MOUNT/Roms/GBA
mkdir -p $ROMS_MOUNT/CartDumps
mkdir -p $ROMS_MOUNT/Cores
mkdir -p $ROMS_MOUNT/Shaders
mkdir -p $ROMS_MOUNT/BIOS
mkdir -p $ROMS_MOUNT/Saves

# Create README
cat > $ROMS_MOUNT/README.txt << 'EOF'
RetroSQ Enhanced CFW - ROM Storage
===================================

Place your files in these folders:

  Roms/      - Game ROM files (manually added)
    GB/      - Game Boy ROMs (.gb)
    GBC/     - Game Boy Color ROMs (.gbc)
    GBA/     - Game Boy Advance ROMs (.gba)

  CartDumps/ - Auto-dumped cartridge ROMs
             (Games inserted in the cart slot are dumped here)

  Cores/     - Additional RetroArch cores (.so files)
  Shaders/   - Custom shaders
  BIOS/      - System BIOS files (gba_bios.bin, etc.)
  Saves/     - Backup save files

This partition was automatically created on first boot.
It uses all remaining space on your SD card.

To access ROMs in RetroArch:
  1. Boot without a cartridge to enter menu
  2. Load Content -> /mnt/roms/Roms/
  3. Select your game

Cores can be downloaded from:
  https://buildbot.libretro.com/nightly/linux/armhf/latest/

For more information, visit:
  https://github.com/SiirRandall/sirrandall-hyperkin-gb

EOF

sync
umount $ROMS_MOUNT

# Mark first boot as complete
touch "$MARKER_FILE"

log "=== First Boot Setup Complete ==="
log "ROM partition created at $ROMS_PARTITION"
log "Mount point: $ROMS_MOUNT"

exit 0

#!/bin/sh
#
# Retron SQ Enhanced CFW - First Boot Setup
# Creates and formats the FAT32 ROMs partition on first boot
#
# This script runs during S20firstboot to set up the ROM storage partition
# on an inserted SD card. Only runs if an SD card is present with free space.
#

# CFW Version - update this with each release
CFW_VERSION="1.0.0"

# Don't use set -e - we want graceful failure handling
# Use persistent storage for marker (not /var which may be tmpfs)
MARKER_FILE="/userdata/.first_boot_complete"
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

log "=== Retron SQ First Boot Setup ==="

# Check if SD card device exists (not present on NAND-only systems)
if [ ! -b "$SDCARD" ]; then
    log "No SD card device found at $SDCARD - running on NAND flash"
    log "Skipping ROM partition setup (use USB or network for ROMs)"
    touch "$MARKER_FILE"
    exit 0
fi

# Find the last partition number using sgdisk (GPT-aware)
# sgdisk -p output format: "Number  Start (sector)    End (sector)  Size..."
LAST_PART=$(sgdisk -p "${SDCARD}" 2>/dev/null | grep "^[[:space:]]*[0-9]" | tail -1 | awk '{print $1}')

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

# Get the end sector of the last partition using sgdisk
LAST_END_SECTOR=$(sgdisk -p "${SDCARD}" 2>/dev/null | grep "^[[:space:]]*${LAST_PART}[[:space:]]" | awk '{print $3}')

# Get total sectors on the disk
TOTAL_SECTORS=$(sgdisk -p "${SDCARD}" 2>/dev/null | grep "^Disk.*sectors" | grep -o "[0-9]* sectors" | awk '{print $1}')

if [ -z "$LAST_END_SECTOR" ] || [ -z "$TOTAL_SECTORS" ]; then
    log "Could not determine disk geometry - SD card may not support partitioning"
    log "Skipping ROM partition setup"
    touch "$MARKER_FILE"
    exit 0
fi

# Calculate start sector for new partition (next sector after last partition)
NEW_START=$((LAST_END_SECTOR + 1))

# Leave 1MB (2048 sectors) at the end for GPT backup and safety margin
# This prevents partition table corruption on some SD cards
NEW_END=$((TOTAL_SECTORS - 2048))

# Require at least 100MB for ROM partition to be useful
# 100MB = 100 * 1024 * 1024 bytes / 512 bytes per sector = 204800 sectors
AVAILABLE_SECTORS=$((NEW_END - NEW_START))
MIN_SECTORS=$((100 * 1024 * 1024 / 512))

if [ "$AVAILABLE_SECTORS" -lt "$MIN_SECTORS" ]; then
    log "WARNING: Not enough space for ROM partition (need 100MB, have $((AVAILABLE_SECTORS * 512 / 1024 / 1024))MB)"
    log "Skipping partition creation"
    touch "$MARKER_FILE"
    exit 0
fi

log "Creating ROM partition: sectors $NEW_START to $NEW_END"
log "Available space: $((AVAILABLE_SECTORS * 512 / 1024 / 1024))MB"

# Create the partition using sgdisk (GPT-aware tool)
# Type code 0700 = Microsoft basic data (used for FAT32)
sgdisk --new="${NEXT_PART}:${NEW_START}:${NEW_END}" \
       --change-name="${NEXT_PART}:ROMS" \
       --typecode="${NEXT_PART}:0700" \
       "${SDCARD}" 2>&1 | tee -a $LOG_FILE

# Re-read partition table
partprobe "${SDCARD}" 2>/dev/null || true
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
mkfs.vfat -F 32 -n "ROMS" $ROMS_PARTITION 2>&1 | tee -a $LOG_FILE

# Create mount point
mkdir -p $ROMS_MOUNT

# Mount and create directory structure
log "Creating directory structure..."
mount -t vfat $ROMS_PARTITION $ROMS_MOUNT

# RetroArch standard folder names for playlist/thumbnail compatibility
mkdir -p "$ROMS_MOUNT/Nintendo - Game Boy"
mkdir -p "$ROMS_MOUNT/Nintendo - Game Boy Color"
mkdir -p "$ROMS_MOUNT/Nintendo - Game Boy Advance"
mkdir -p "$ROMS_MOUNT/Cores"
mkdir -p "$ROMS_MOUNT/Shaders"
mkdir -p "$ROMS_MOUNT/BIOS"
mkdir -p "$ROMS_MOUNT/Savestates"

# Create RetroArch metadata directories for offline functionality
# Thumbnails can be added by users for box art display
mkdir -p "$ROMS_MOUNT/.retroarch/thumbnails/Nintendo - Game Boy/Named_Boxarts"
mkdir -p "$ROMS_MOUNT/.retroarch/thumbnails/Nintendo - Game Boy/Named_Snaps"
mkdir -p "$ROMS_MOUNT/.retroarch/thumbnails/Nintendo - Game Boy/Named_Titles"
mkdir -p "$ROMS_MOUNT/.retroarch/thumbnails/Nintendo - Game Boy Color/Named_Boxarts"
mkdir -p "$ROMS_MOUNT/.retroarch/thumbnails/Nintendo - Game Boy Color/Named_Snaps"
mkdir -p "$ROMS_MOUNT/.retroarch/thumbnails/Nintendo - Game Boy Color/Named_Titles"
mkdir -p "$ROMS_MOUNT/.retroarch/thumbnails/Nintendo - Game Boy Advance/Named_Boxarts"
mkdir -p "$ROMS_MOUNT/.retroarch/thumbnails/Nintendo - Game Boy Advance/Named_Snaps"
mkdir -p "$ROMS_MOUNT/.retroarch/thumbnails/Nintendo - Game Boy Advance/Named_Titles"

# Migrate ROMs from stock firmware NAND storage (one-time)
migrate_roms() {
    # src_dir is function-scoped (no 'local' for POSIX sh compatibility)
    src_dir="/userdata/rom"
    if [ -d "$src_dir" ] && [ "$(ls -A "$src_dir" 2>/dev/null)" ]; then
        log "Migrating ROMs from stock firmware ($src_dir)..."
        
        # Migrate GB ROMs to Game Boy folder (not GBC - they have separate databases)
        for rom in "$src_dir"/*.gb; do
            [ -f "$rom" ] && mv "$rom" "$ROMS_MOUNT/Nintendo - Game Boy/" 2>/dev/null && log "Migrated GB: $(basename "$rom")"
        done
        
        # Migrate GBC ROMs to Game Boy Color folder
        for rom in "$src_dir"/*.gbc; do
            [ -f "$rom" ] && mv "$rom" "$ROMS_MOUNT/Nintendo - Game Boy Color/" 2>/dev/null && log "Migrated GBC: $(basename "$rom")"
        done
        
        # Migrate GBA ROMs to Game Boy Advance folder
        for rom in "$src_dir"/*.gba; do
            [ -f "$rom" ] && mv "$rom" "$ROMS_MOUNT/Nintendo - Game Boy Advance/" 2>/dev/null && log "Migrated GBA: $(basename "$rom")"
        done
        
        # Migrate save files to match their ROM's destination
        # Check for matching ROM to determine correct folder
        for sav in "$src_dir"/*.sav "$src_dir"/*.srm; do
            if [ -f "$sav" ]; then
                base=$(basename "$sav" | sed 's/\.[^.]*$//')
                if [ -f "$ROMS_MOUNT/Nintendo - Game Boy Advance/${base}.gba" ]; then
                    mv "$sav" "$ROMS_MOUNT/Nintendo - Game Boy Advance/" 2>/dev/null && log "Migrated save: $(basename "$sav") -> GBA"
                elif [ -f "$ROMS_MOUNT/Nintendo - Game Boy Color/${base}.gbc" ]; then
                    mv "$sav" "$ROMS_MOUNT/Nintendo - Game Boy Color/" 2>/dev/null && log "Migrated save: $(basename "$sav") -> GBC"
                elif [ -f "$ROMS_MOUNT/Nintendo - Game Boy/${base}.gb" ]; then
                    mv "$sav" "$ROMS_MOUNT/Nintendo - Game Boy/" 2>/dev/null && log "Migrated save: $(basename "$sav") -> GB"
                else
                    # Default to GBC folder if no matching ROM found
                    mv "$sav" "$ROMS_MOUNT/Nintendo - Game Boy Color/" 2>/dev/null && log "Migrated save: $(basename "$sav") -> GBC (default)"
                fi
            fi
        done
        
        log "Migration complete. Cleaning up NAND storage..."
        # Safe rm pattern - ensure src_dir is set before using /*
        [ -n "${src_dir}" ] && rm -rf "${src_dir:?}"/* 2>/dev/null
        sync
    fi
}

migrate_roms

# Create README
cat > "$ROMS_MOUNT/README.txt" << 'EOF'
Retron SQ Enhanced CFW - ROM Storage
====================================

This SD card uses RetroArch standard folder names for full compatibility
with playlists, thumbnails, and the Explore menu.

Folder Structure:
-----------------
  Nintendo - Game Boy/         - GB ROMs (.gb)
  Nintendo - Game Boy Color/   - GBC ROMs (.gbc)
  Nintendo - Game Boy Advance/ - GBA ROMs (.gba)

  Note: GB games can also play in the GBC core, but for proper
  database matching and thumbnails, use the correct folder.

  Cores/      - Additional RetroArch cores (.so files)
  Shaders/    - Custom shaders
  BIOS/       - System BIOS files (gba_bios.bin, etc.)
  Savestates/ - Save states (battery saves are stored with ROMs)

Cartridge Dumps:
----------------
When you insert a cartridge, it is automatically dumped to the
appropriate system folder based on file extension.

Playing Games:
--------------
  1. Insert cartridge OR boot without cartridge to enter menu
  2. Press Start+Select to open RetroArch menu
  3. Load Content -> Browse to system folder
  4. Select your game

Save Files:
-----------
Battery save files (.srm) are stored alongside ROMs in the same folder.
This makes it easy to backup a game and its save together.

EverDrive/Multicart Support:
----------------------------
All ROMs from multicarts are dumped and sorted by system type.
Save files (.sav) from the cart are also copied and renamed to .srm.

Thumbnails (Optional):
----------------------
To add box art to your game library, download thumbnails from:
  https://github.com/libretro-thumbnails

Place PNG files in the .retroarch/thumbnails folders:
  .retroarch/thumbnails/Nintendo - Game Boy/Named_Boxarts/
  .retroarch/thumbnails/Nintendo - Game Boy Color/Named_Boxarts/
  .retroarch/thumbnails/Nintendo - Game Boy Advance/Named_Boxarts/

File names must match your ROM names (without extension).
Example: "Pokemon Red.png" for "Pokemon Red.gb"

Offline Mode:
-------------
This firmware is designed for fully offline use. Game databases
are pre-installed for ROM identification when scanning content.
No internet connection is required.

More Information:
-----------------
  https://github.com/SiirRandall/sirrandall-hyperkin-gb

EOF

# Write CFW version file for identification
echo "$CFW_VERSION" > "$ROMS_MOUNT/.cfw_version"
log "CFW Version: $CFW_VERSION"

sync
umount $ROMS_MOUNT

# Mark first boot as complete (in persistent userdata)
touch "$MARKER_FILE"

log "=== First Boot Setup Complete ==="
log "ROM partition created at $ROMS_PARTITION"
log "Mount point: $ROMS_MOUNT"

exit 0

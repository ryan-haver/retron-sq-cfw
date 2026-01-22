# Retron SQ Custom Firmware v1.0.0

## Release Files

| File | Size | SHA256 |
|------|------|--------|
| retron-sq-cfw-v1.0.0.img | 96 MB | 9679F33A576EAC0CDCC7C7D2A444A31D15567FA9266EDE8D5B25C7F22B052D14 |
| retron-sq-cfw-v1.0.0-update.img | 47 MB | 3CDE21286F4F84F69EA43F4A6AFCFDF368AD54F614B801036C7C7DB494B160A1 |

## Installation

### Method 1: SD Card Image (Recommended)
1. Download 
etron-sq-cfw-v1.0.0.img
2. Write to SD card using Balena Etcher, Win32DiskImager, or dd
3. Insert SD card into Retron SQ and power on
4. First boot will create ROMS partition on remaining SD card space

### Method 2: USB Update (for recovery)
1. Download 
etron-sq-cfw-v1.0.0-update.img
2. Use Rockchip upgrade tool in maskrom mode
3. Flash update.img to internal storage

## Features
- RetroArch with offline game database support
- Pre-configured for GB, GBC, GBA emulation
- Automatic ROM migration from stock firmware location
- FAT32 ROMS partition created on first boot

## Changelog v1.0.0
- Initial release
- Fixed GB ROM migration (was incorrectly going to GBC folder)
- Fixed save file association with correct console folders
- Stripped unnecessary player 2-16 bindings from config
- Disabled video content scanning (game-only device)
- Added filesystem check before mounting ROMS partition
- POSIX sh compliant init scripts

## Technical Details
- Kernel: Linux (Rockchip RK3128)
- Rootfs: Squashfs (24MB)
- Userdata: FAT16 (16MB) with RetroArch config and databases
- SD Card Layout: GPT with boot/rootfs/userdata partitions

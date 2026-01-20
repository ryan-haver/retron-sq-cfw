# Retron SQ CFW Architecture Documentation

## Phase 2 Code Analysis Summary

This document provides a comprehensive analysis of the Retron SQ custom firmware codebase, documenting the boot sequence, application architecture, and key integration points for modification.

---

## Directory Structure Overview

```
retron-sq-cfw/
├── app/                              # Qt/QML applications (not used for game loading)
│   ├── camera/
│   ├── gallery/
│   ├── music/
│   ├── QLauncher/                    # Generic Rockchip launcher (not primary)
│   ├── settings/
│   └── video/
├── buildroot/
│   ├── board/rockchip/rk3128/        # Target board configuration
│   │   └── fs-overlay/etc/           # Filesystem overlay (key scripts)
│   ├── configs/                      # Build configurations
│   │   └── rockchip_rk3128_brk01_defconfig  # Retron SQ config
│   ├── dl/                           # Downloaded source packages
│   └── package/                      # Package definitions
│       ├── hyperkin-loading/         # Cart loading UI (SDL2)
│       ├── retroarch/                # RetroArch emulator
│       ├── libretro-gpsp/            # GBA core
│       ├── libretro-vbam/            # GB/GBC core
│       ├── libretro-mgba/            # Fallback core
│       └── usbmount/                 # USB automount
├── device/rockchip/userdata/
│   └── userdata_brk01/               # Default userdata contents
│       ├── gb.txt                    # ROMs needing special handling
│       ├── retroarch/
│       │   ├── retroarch.cfg         # RetroArch configuration
│       │   ├── retroarch-core-options.cfg
│       │   └── autoconfig/           # Controller mappings
│       └── rom/                      # ROM storage location
├── docker/                           # Build environment (we created)
│   ├── Dockerfile
│   └── README.md
└── prepare-build.sh                  # Build preparation script
```

---

## Boot Sequence Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          POWER ON / RESET                               │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           U-Boot                                        │
│            Loads kernel, initramfs, device tree                         │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      Linux Kernel 4.4.159                               │
│                  "Blurry Fish Butt" (Rockchip BSP)                      │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         SysV Init                                       │
│                    /etc/init.d/rcS                                      │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          S50ui                                          │
│         /etc/init.d/S50ui (installed by hyperkin-loading)               │
│                                                                         │
│   1. source /etc/check_dumper.sh    # Load helper functions             │
│   2. Display Hyperkin logo          # fbset, ppmtofb                    │
│   3. Start input-event-daemon       # Button handling                   │
│   4. $(RunGame)                     # Launch game if cart present       │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
              ┌──────────────────┴──────────────────┐
              │                                     │
              ▼                                     ▼
┌─────────────────────────────┐     ┌─────────────────────────────────────┐
│     Cart Present            │     │        No Cart                      │
│                             │     │                                     │
│  - ROM found in /media/usb0 │     │  - Prints "without any rom file"    │
│  - CheckROM() succeeds      │     │  - Boot sequence ends               │
│                             │     │  - ⚠️ NO UI SHOWN - BLACK SCREEN    │
└──────────────┬──────────────┘     └─────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         RunGame()                                       │
│                   (from check_dumper.sh)                                │
│                                                                         │
│   1. Compare CRC files (cart vs stored)                                 │
│   2. If CRC differs → run hyperkin-loading (copy ROM + saves)           │
│   3. If CRC matches → ROM already cached in /userdata/rom/              │
│   4. Launch RetroArch with appropriate core                             │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      hyperkin-loading                                   │
│              (SDL2 application with progress bar)                       │
│                                                                         │
│   - Displays Splash_Screen_MockUp.jpg                                   │
│   - CopyThread: Copies .gb/.gba/.gbc/.sav from cart                     │
│   - Converts .sav → .srm (RetroArch format)                             │
│   - Shows yellow progress bar (645,624 to 1508,656 scaled)              │
│   - Minimum 3 second display time                                       │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         RetroArch                                       │
│                  /usr/bin/retroarch                                     │
│                                                                         │
│   Config: /userdata/retroarch/retroarch.cfg                             │
│   Cores:  /usr/lib/libretro/*.so                                        │
│   Menu:   RGUI (lightweight menu driver)                                │
│                                                                         │
│   Core Selection (by file extension):                                   │
│   - .gba → gpsp_libretro.so                                             │
│   - .gb/.gbc → vbam_libretro.so                                         │
│   - Listed in gb.txt → mgba_libretro.so (fallback)                      │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Key Scripts Analysis

### `/etc/check_dumper.sh` (Core Game Logic)

**Location:** `buildroot/board/rockchip/rk3128/fs-overlay/etc/check_dumper.sh`  
**Size:** ~140 lines  
**Purpose:** Contains ALL game launch logic - this is THE critical file for Phase 3 modifications

**Constants:**
```bash
DUMPER_PATH="/media/usb0/"      # Cart USB mount point
ROM_PATH="/userdata/rom/"        # Cached ROM storage
RETROARCH_BIN="/usr/bin/retroarch"
RETROARCH_CON="/userdata/retroarch/retroarch.cfg"
```

**Functions:**

| Function | Purpose | Key Behavior |
|----------|---------|--------------|
| `CheckROM()` | Scan cart for ROM files | Returns ROM filename if .gb/.gba/.gbc found in DUMPER_PATH |
| `KillGame()` | Stop emulator | `killall retroarch; /bin/sync` |
| `ResetROM()` | Handle cart swap | Kills retroarch, removes old ROM, copies new, relaunches |
| `RunGame()` | Main entry point | Checks CRC, runs hyperkin-loading if needed, launches retroarch |

**Core Selection Logic (in RunGame):**
```bash
# Extension-based core selection
if [[ "$rom_name" == *.gba ]]; then
    core="/usr/lib/libretro/gpsp_libretro.so"
elif [[ "$rom_name" == *.gb ]] || [[ "$rom_name" == *.gbc ]]; then
    # Check if ROM is in gb.txt (fallback list)
    if grep -q "$rom_name" /userdata/gb.txt; then
        core="/usr/lib/libretro/mgba_libretro.so"
    else
        core="/usr/lib/libretro/vbam_libretro.so"
    fi
fi
```

### `/etc/init.d/S50ui` (Init Script)

**Location:** `buildroot/package/hyperkin-loading/src/S50ui`  
**Purpose:** Main startup script, launched by SysV init

**Key Actions:**
1. Sources `/etc/check_dumper.sh` to import functions
2. Displays Hyperkin logo using framebuffer
3. Starts `input-event-daemon` for button handling
4. Calls `$(RunGame)` to launch game if cart present

### `/etc/reset-btn.sh` (Reset Button Handler)

**Location:** `buildroot/board/rockchip/rk3128/fs-overlay/etc/reset-btn.sh`

**Triggered by:** input-event-daemon when F3 key (reset button) pressed

**Behavior:**
```bash
source /etc/check_dumper.sh
$(ResetROM)  # Handle cart swap
```

---

## USB Hotplug Flow

```
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│   Cart Inserted   │────▶│   udev rule       │────▶│ usbmount/mount.d/ │
│   (USB detected)  │     │   usbmount.rules  │     │                   │
└───────────────────┘     └───────────────────┘     └────────┬──────────┘
                                                              │
                                                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    01_try_launch_retroarch                              │
│              /etc/usbmount/mount.d/01_try_launch_retroarch              │
│                                                                         │
│   source /etc/check_dumper.sh                                           │
│   $(RunGame)   # Launch game when cart mounted                          │
└─────────────────────────────────────────────────────────────────────────┘


┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│   Cart Removed    │────▶│   udev rule       │────▶│ usbmount/umount.d/│
│   (USB removed)   │     │   usbmount.rules  │     │                   │
└───────────────────┘     └───────────────────┘     └────────┬──────────┘
                                                              │
                                                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      01_kill_retroarch                                  │
│            /etc/usbmount/umount.d/01_kill_retroarch                     │
│                                                                         │
│   source /etc/check_dumper.sh                                           │
│   $(KillGame)   # Stop emulator when cart removed                       │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Input Handling

### Button Mapping

**Config:** `buildroot/board/rockchip/rk3128/fs-overlay/etc/input-event-daemon.conf`

```ini
[Global]
listen = /dev/input/by-path/platform-gpio-keys-event

[Keys]
F3 = /etc/reset-btn.sh    # Reset button triggers cart swap
```

### Controller Configuration

**Location:** `/userdata/retroarch/autoconfig/`

| Config File | Controller |
|-------------|------------|
| Hyperkin_SQ.cfg | Built-in gamepad (Vendor: 11812, Product: 18538) |
| hyperkin-adapter.cfg | External adapter |
| usb_gamepad___________NES.cfg | USB NES controller |
| usb_gamepad___________SNES.cfg | USB SNES controller |
| Hyperkin_Genesis_6_Button.cfg | Genesis controller |

**Hyperkin SQ Gamepad Mapping:**
```
A = btn 7    B = btn 3
X = btn 6    Y = btn 2
L = btn 0    R = btn 1
Select = btn 5    Start = btn 4
D-Pad = axis 0/1
```

---

## RetroArch Configuration

### Key Settings (retroarch.cfg)

| Setting | Value | Notes |
|---------|-------|-------|
| `menu_driver` | `"rgui"` | Lightweight menu for ARM |
| `input_driver` | `"udev"` | Linux input subsystem |
| `audio_driver` | `"alsathread"` | ALSA threaded audio |
| `audio_device` | `"hdmi"` | HDMI audio output |
| `autosave_interval` | `"5"` | Save SRAM every 5 seconds |
| `video_fullscreen` | `"true"` | Always fullscreen |

### Enabled Libretro Cores

From `rockchip_rk3128_brk01_defconfig`:

| Package | Core | Systems |
|---------|------|---------|
| BR2_PACKAGE_LIBRETRO_GPSP | gpsp_libretro.so | Game Boy Advance |
| BR2_PACKAGE_LIBRETRO_VBAM | vbam_libretro.so | Game Boy, Game Boy Color |
| BR2_PACKAGE_LIBRETRO_MGBA | mgba_libretro.so | GB/GBC/GBA (fallback) |

### Core Options (retroarch-core-options.cfg)

**gpsp (GBA):**
- `gpsp_bios = "builtin"` - Uses built-in BIOS
- `gpsp_drc = "enabled"` - Dynamic recompilation ON
- `gpsp_save_method = "libretro"` - Standard save handling

**vbam (GB/GBC):**
- `vbam_gbHardware = "gbc"` - Default to GBC mode
- `vbam_usebios = "enabled"` - Use BIOS files

**mgba (fallback):**
- `mgba_skip_bios = "OFF"` - Run BIOS intro
- `mgba_gb_model = "Autodetect"` - Auto-detect GB/GBC

---

## ROM/Save Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     CARTRIDGE (USB Mass Storage)                        │
│                          /media/usb0/                                   │
│                                                                         │
│   Files present on cart:                                                │
│   - GAME.gb / GAME.gba / GAME.gbc    (ROM file)                         │
│   - GAME.sav                          (Save file)                       │
│   - GAME.crc                          (CRC checksum)                    │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     │ hyperkin-loading
                                     │ CopyThread()
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    INTERNAL STORAGE (userdata)                          │
│                        /userdata/rom/                                   │
│                                                                         │
│   After copy:                                                           │
│   - GAME.gb / GAME.gba / GAME.gbc    (ROM copy)                         │
│   - GAME.srm                          (.sav renamed to .srm)            │
│   - GAME.crc                          (CRC for comparison)              │
│                                                                         │
│   ⚠️ NOTE: Saves are NOT written back to cartridge!                     │
│   (USB mounted read-write, but no write code implemented)               │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     │ RetroArch loads
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         RETROARCH                                       │
│                                                                         │
│   - Loads ROM from /userdata/rom/                                       │
│   - Loads/saves SRAM to /userdata/rom/GAME.srm                          │
│   - autosave_interval = 5 (auto-saves every 5 seconds)                  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Modification Points for Phase 3 (Boot Without Cartridge)

### Target: `check_dumper.sh`

The `RunGame()` function is the key modification point. Current behavior when no cart:
```bash
# Current: Does nothing if no ROM found
if [ -z "$rom_file" ]; then
    echo "without any rom file"
    # Boot ends here - black screen
fi
```

**Proposed modification:**
```bash
# Modified: Launch RetroArch menu if no ROM found
if [ -z "$rom_file" ]; then
    echo "No cart detected, launching RetroArch menu"
    $RETROARCH_BIN --config $RETROARCH_CON --menu
fi
```

### Additional Changes Needed

1. **S50ui**: May need adjustment to not wait for cart indefinitely
2. **retroarch.cfg**: Ensure `menu_show_start_screen = "true"` for menu mode
3. **usbmount hooks**: Handle dynamic cart insertion after RetroArch started

---

## File Locations Reference

| Purpose | Path in Source | Installed Location |
|---------|----------------|-------------------|
| Init script | `hyperkin-loading/src/S50ui` | `/etc/init.d/S50ui` |
| Game logic | `fs-overlay/etc/check_dumper.sh` | `/etc/check_dumper.sh` |
| Reset handler | `fs-overlay/etc/reset-btn.sh` | `/etc/reset-btn.sh` |
| Button config | `fs-overlay/etc/input-event-daemon.conf` | `/etc/input-event-daemon.conf` |
| USB mount hook | `hyperkin-loading/src/01_try_launch_retroarch` | `/etc/usbmount/mount.d/` |
| USB unmount hook | `hyperkin-loading/src/01_kill_retroarch` | `/etc/usbmount/umount.d/` |
| RetroArch config | `userdata_brk01/retroarch/retroarch.cfg` | `/userdata/retroarch/retroarch.cfg` |
| Core options | `userdata_brk01/retroarch/retroarch-core-options.cfg` | `/userdata/retroarch/` |
| Controller maps | `userdata_brk01/retroarch/autoconfig/` | `/userdata/retroarch/autoconfig/` |
| Loading UI source | `hyperkin-loading/src/hyperkin-loading.cpp` | `/usr/bin/hyperkin-loading` |

---

## Build Configuration

### Target Config: `rockchip_rk3128_brk01_defconfig`

**Key packages enabled:**
- BR2_PACKAGE_RETROARCH=y
- BR2_PACKAGE_LIBRETRO_GPSP=y
- BR2_PACKAGE_LIBRETRO_MGBA=y
- BR2_PACKAGE_LIBRETRO_VBAM=y
- BR2_PACKAGE_HYPERKIN_LOADING=y
- BR2_PACKAGE_USBMOUNT=y
- BR2_PACKAGE_INPUT_EVENT_DAEMON=y
- BR2_PACKAGE_SDL2=y (with OpenGL ES, ALSA, udev)

### Cross-Compilation

- **Toolchain:** arm-linux-gnueabihf-gcc (in Docker: 9.4.0)
- **Architecture:** ARMv7-A (Cortex-A7)
- **Float ABI:** Hard float (gnueabihf)

---

## RetroArch Integration Details

### Version Information

- **RetroArch Version:** 1.7.4 (commit 3e27a504ed3b)
- **Source:** Local copy in `buildroot/package/retroarch/src/`
- **Build Method:** Autotools with custom configure options

### Build Configuration (retroarch.mk)

**Disabled Features:**
```makefile
--disable-oss           # OSS audio (using ALSA instead)
--disable-python        # Python support
--disable-pulse         # PulseAudio (not available)
--disable-cheevos       # RetroAchievements (no network)
--disable-networking    # Network features disabled
--disable-freetype      # FreeType fonts
--disable-7zip          # 7-zip compression
--disable-ssl           # SSL/TLS
--disable-libxml2       # XML parsing
```

**Enabled Features:**
```makefile
--enable-rgui           # RGUI menu (lightweight)
--enable-zlib           # Compression support
--enable-opengles       # OpenGL ES rendering
--enable-egl            # EGL context
--enable-neon           # ARM NEON SIMD
--enable-floathard      # Hardware float
```

### Patches Applied

| Patch | Purpose |
|-------|---------|
| `0001-udev_input-Enable-alternative-keyboards.patch` | Changes ID_INPUT_KEYBOARD → ID_INPUT_KEY for broader keyboard detection |
| `0002-gfx-video-Support-print-fps-in-retroarch-verbose-log.patch` | Adds RETROARCH_LOG_FPS env variable for FPS debugging |

### Platform Flags

```makefile
LIBRETRO_PLATFORM += buildroot gles armv7 hardfloat neon
```

This tells libretro cores to optimize for:
- ARM v7 architecture
- Hard float ABI
- NEON SIMD instructions
- OpenGL ES rendering

### Command Line Usage

Standard launch command (from check_dumper.sh):
```bash
/usr/bin/retroarch -L /usr/lib/libretro/CORE.so /userdata/rom/GAME.rom --config /userdata/retroarch/retroarch.cfg
```

**Key Arguments:**
- `-L <core>` - Load libretro core
- `--config <cfg>` - Use specific configuration file
- `--menu` - Launch directly to menu (for Phase 3)

### Menu System

- **Driver:** RGUI (Rudimentary Graphical User Interface)
- **Features:** Lightweight, low memory, fast rendering
- **Input:** Works with udev input driver
- **Limitations:** Basic graphics, no thumbnails/screenshots

### Save System

| Setting | Value | Effect |
|---------|-------|--------|
| `autosave_interval` | 5 | Save SRAM every 5 seconds |
| `block_sram_overwrite` | false | Allow SRAM overwrites |
| `savestate_auto_save` | (default) | Manual savestates only |
| `savestate_auto_load` | (default) | Manual savestate loading |

---

## Phase 3 Preparation Checklist

Based on this analysis, Phase 3 (Boot Without Cartridge) requires:

### Files to Modify

1. **`/etc/check_dumper.sh`**
   - Modify `RunGame()` to launch RetroArch menu when no cart
   - Add ROM browser capability for `/userdata/rom/`

2. **`/userdata/retroarch/retroarch.cfg`**
   - Ensure proper menu configuration
   - Set default ROM directory
   - Configure ROM browser paths

3. **`/etc/init.d/S50ui`** (optional)
   - May need timing adjustments for menu boot

### Testing Requirements

1. Test boot sequence without cartridge inserted
2. Verify RetroArch menu launches and is navigable
3. Test ROM selection from internal storage
4. Verify cart hot-plug still works after RetroArch started

---

*Document generated during Phase 2 Code Analysis*
*Last updated: Phase 2 completion*

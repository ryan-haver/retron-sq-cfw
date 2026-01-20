# Retron SQ CFW Docker Build Environment

This directory contains the Docker build environment for compiling the Retron SQ custom firmware.

## Quick Start

### Build the Docker image

```powershell
# From the repository root (retron-sq-cfw/)
docker build -t retron-sq-build ./docker
```

### Run the build environment

**PowerShell (Windows):**
```powershell
docker run -it --rm --user root -v ${PWD}:/workspace retron-sq-build
```

**Bash (Linux/WSL):**
```bash
docker run -it --rm -v $(pwd):/workspace retron-sq-build
```

> **Note:** Use `--user root` on Windows to avoid permission issues with mounted volumes.

## Building the Firmware

Once inside the container:

```bash
# 1. Run the preparation script (handles line endings + config)
cd /workspace
bash prepare-build.sh

# 2. Build all components
./device/rockchip/common/build.sh all

# 3. Create firmware images
./mkfirmware.sh
```

## Build Targets

| Command | Description |
|---------|-------------|
| `./build.sh uboot` | Build U-Boot bootloader |
| `./build.sh kernel` | Build Linux kernel |
| `./build.sh rootfs` | Build Buildroot rootfs |
| `./build.sh all` | Build everything |
| `./build.sh firmware` | Pack firmware images |
| `./mkfirmware.sh` | Create final firmware package |

## Output Files

After a successful build, firmware images are located in:
- `rockdev/` - Individual partition images
- `rockdev/update.img` - Complete firmware update image

## Troubleshooting

### Build fails with permission errors
Run the container as root:
```bash
docker run -it --rm -v $(pwd):/workspace --user root retron-sq-build
```

### Missing .BoardConfig.mk
Create the symlink:
```bash
ln -sf device/rockchip/rk3128/BoardConfig_brk01.mk device/rockchip/.BoardConfig.mk
```

### Out of disk space
Docker builds can require 20GB+. Clean unused images:
```bash
docker system prune -a
```

## Environment Details

- **Base Image:** Ubuntu 20.04 LTS
- **Target Architecture:** ARM (armhf)
- **Cross Compiler:** gcc-arm-linux-gnueabihf
- **Kernel Version:** Linux 4.4.159
- **Buildroot Config:** rockchip_rk3128_brk01

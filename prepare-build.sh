#!/bin/bash
#
# Retron SQ CFW Build Preparation Script
# Run this inside the Docker container before building
#
# Usage: ./prepare-build.sh
#

set -e

echo "=== Retron SQ CFW Build Preparation ==="
echo ""

# Convert all shell scripts and makefiles to Unix line endings
echo "[1/4] Converting line endings..."
find . -type f \( -name "*.sh" -o -name "*.mk" -o -name "Makefile" -o -name "*.txt" \) \
    -exec dos2unix {} \; 2>/dev/null || true

# Create board config symlink if needed
echo "[2/4] Setting up board configuration..."
rm -f device/rockchip/.BoardConfig.mk 2>/dev/null || true
cp device/rockchip/rk3128/BoardConfig_brk01.mk device/rockchip/.BoardConfig.mk
dos2unix device/rockchip/.BoardConfig.mk 2>/dev/null || true
echo "    Created .BoardConfig.mk"

# Source the configuration
echo "[3/4] Sourcing build configuration..."
source device/rockchip/.BoardConfig.mk

# Verify critical variables
echo "[4/4] Verifying configuration..."
echo ""
echo "Build Configuration:"
echo "  Target:      $RK_TARGET_PRODUCT"
echo "  Kernel DTS:  $RK_KERNEL_DTS"
echo "  Buildroot:   $RK_CFG_BUILDROOT"
echo "  Rootfs Type: $RK_ROOTFS_TYPE"
echo "  Arch:        $RK_ARCH"
echo ""

# Check for kernel defconfig
if [ -f "kernel/arch/arm/configs/$RK_KERNEL_DEFCONFIG" ]; then
    echo "✓ Kernel defconfig found: $RK_KERNEL_DEFCONFIG"
else
    echo "✗ WARNING: Kernel defconfig not found: $RK_KERNEL_DEFCONFIG"
fi

# Check for buildroot defconfig
if [ -f "buildroot/configs/${RK_CFG_BUILDROOT}_defconfig" ]; then
    echo "✓ Buildroot defconfig found: ${RK_CFG_BUILDROOT}_defconfig"
else
    echo "✗ WARNING: Buildroot defconfig not found: ${RK_CFG_BUILDROOT}_defconfig"
fi

echo ""
echo "=== Preparation Complete ==="
echo ""
echo "To build the firmware, run:"
echo "  ./device/rockchip/common/build.sh all"
echo ""
echo "Or build individual components:"
echo "  ./device/rockchip/common/build.sh uboot"
echo "  ./device/rockchip/common/build.sh kernel"
echo "  ./device/rockchip/common/build.sh buildroot"
echo ""

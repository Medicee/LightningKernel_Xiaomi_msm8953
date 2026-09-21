#!/bin/bash
# Standalone LightningKernel (Mi A1 / tissot, msm8953) build script.
# Modeled on o2.sh's structure (env-overridable, self-contained, sanity
# checks) but keeps the tissot-specific build steps from the original
# mia1.sh (proton-clang, lightning-tissot_defconfig, treble/nontreble dtbs).

set -euo pipefail

echo "Compile is beginning..."

# ---------------- Sources (overridable via env) ----------------
KERNEL_REPO="${KERNEL_REPO:-https://github.com/Medicee/LightningKernel_Xiaomi_msm8953}"
KERNEL_BRANCH="${KERNEL_BRANCH:-lightlosreb2}"
ANYKERNEL_REPO="${ANYKERNEL_REPO:-https://github.com/prorooter007/AnyKernel3}"
ANYKERNEL_BRANCH="${ANYKERNEL_BRANCH:-tissot}"
DEFCONFIG="${DEFCONFIG:-lightning-tissot_defconfig}"

echo "Cloning kernel source [$KERNEL_REPO @ $KERNEL_BRANCH]..."
git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" kernel
cd kernel

echo "Cloning toolchain (proton-clang)..."
git clone --depth=1 -b master https://github.com/kdrag0n/proton-clang clang

echo "Cloning AnyKernel3 [$ANYKERNEL_REPO @ $ANYKERNEL_BRANCH]..."
git clone --depth=1 -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" AnyKernel

KERNEL_DIR="$(pwd)"
REPACK_DIR="${KERNEL_DIR}/AnyKernel"
IMAGE="${KERNEL_DIR}/out/arch/arm64/boot/Image.gz"
DTB_T="${KERNEL_DIR}/out/arch/arm64/boot/dts/qcom/msm8953-qrd-sku3-tissot-treble.dtb"
DTB="${KERNEL_DIR}/out/arch/arm64/boot/dts/qcom/msm8953-qrd-sku3-tissot-nontreble.dtb"
TANGGAL=$(date +"%Y%m%d-%H")

# ---------------- Toolchain & env setup ----------------
export PATH="${KERNEL_DIR}/clang/bin:/usr/lib/ccache:$PATH"
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache_mia1}"
export CCACHE_COMPILERCHECK=content
export CCACHE_SLOPPINESS=time_macros,include_file_mtime,include_file_ctime
export KBUILD_COMPILER_STRING="$(clang --version | head -n 1 | perl -pe 's/\((?:http|git).*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//' -e 's/^.*clang/clang/')"
export ARCH=arm64
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-jayarajan}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-github-actions}"

MAKE_ARGS="O=out \
  ARCH=arm64 \
  CC=clang \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-"

echo "TOOLCHAIN_PATH: [${KERNEL_DIR}/clang/bin]"
echo "CCACHE_DIR: [$CCACHE_DIR]"
echo "DEFCONFIG: [$DEFCONFIG]"

# ---------------- Sanity check: toolchain resolvable ----------------
if ! command -v clang >/dev/null 2>&1; then
  echo "ERROR: clang not found on PATH. Check the proton-clang clone." >&2
  exit 1
fi
if ! command -v aarch64-linux-gnu-ld >/dev/null 2>&1; then
  echo "ERROR: aarch64-linux-gnu-ld not found on PATH. Check the proton-clang clone." >&2
  exit 1
fi

# ---------------- Config generation ----------------
if [ ! -f "out/.config" ]; then
  echo "Generating defconfig [$DEFCONFIG]......."
  make -j"$(nproc)" $MAKE_ARGS "$DEFCONFIG"
else
  echo "Existing out/.config found, skipping defconfig generation."
fi

# ---------------- Build ----------------
make -j"$(nproc)" $MAKE_ARGS

if [ -f "$IMAGE" ]; then
  echo "The file [$IMAGE] exists. Build successful."
else
  echo "The file [$IMAGE] does not exist. Seems the build failed."
  exit 1
fi

# ---------------- Package with AnyKernel3 ----------------
echo "............. Exporting the required images ............."
rm -rf "$REPACK_DIR/kernel" "$REPACK_DIR/dtb-treble" "$REPACK_DIR/dtb-nontreble"
mkdir -p "$REPACK_DIR/kernel" "$REPACK_DIR/dtb-treble" "$REPACK_DIR/dtb-nontreble"

cp "$IMAGE" "$REPACK_DIR/kernel/"

if [ ! -f "$DTB" ]; then
  echo "ERROR: expected non-treble dtb not found: $DTB" >&2
  exit 1
fi
cp "$DTB" "$REPACK_DIR/dtb-nontreble/"

if [ ! -f "$DTB_T" ]; then
  echo "ERROR: expected treble dtb not found: $DTB_T" >&2
  exit 1
fi
cp "$DTB_T" "$REPACK_DIR/dtb-treble/"

cd "$REPACK_DIR"
ZIP_FILENAME="Lightning_Kernel-${TANGGAL}.zip"
zip -r9 "$ZIP_FILENAME" ./* -x .git .gitignore 'out/*' './*.zip'
mv "$ZIP_FILENAME" "$KERNEL_DIR/"
cd "$KERNEL_DIR"

echo "Done. The flashable zip is: [${KERNEL_DIR}/${ZIP_FILENAME}]"

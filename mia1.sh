#!/bin/bash
# Standalone LightningKernel (Mi A1 / tissot, msm8953) build script.
# Modeled on o2.sh's structure (env-overridable, self-contained, sanity
# checks) but keeps the tissot-specific build steps from the original
# mia1.sh (proton-clang, lightning-tissot_defconfig, treble/nontreble dtbs).

set -euo pipefail

echo "Compile is beginning..."

# ---------------- Sources (overridable via env) ----------------
# NOTE: this script runs from inside the kernel repo itself (the workflow's
# actions/checkout step already puts the kernel source in the working
# directory) - it does NOT clone the kernel repo. Only the toolchain and
# AnyKernel3 are fetched here.
ANYKERNEL_REPO="${ANYKERNEL_REPO:-https://github.com/prorooter007/AnyKernel3}"
ANYKERNEL_BRANCH="${ANYKERNEL_BRANCH:-tissot}"
DEFCONFIG="${DEFCONFIG:-lightning-tissot_defconfig}"

KERNEL_DIR="$(pwd)"

if [ ! -d "clang" ]; then
  echo "Cloning toolchain (proton-clang)..."
  git clone --depth=1 -b master https://github.com/kdrag0n/proton-clang clang
else
  echo "Existing clang/ toolchain found, skipping clone."
fi

if [ ! -d "AnyKernel" ]; then
  echo "Cloning AnyKernel3 [$ANYKERNEL_REPO @ $ANYKERNEL_BRANCH]..."
  git clone --depth=1 -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" AnyKernel
else
  echo "Existing AnyKernel/ found, skipping clone."
fi
REPACK_DIR="${KERNEL_DIR}/AnyKernel"
IMAGE="${KERNEL_DIR}/out/arch/arm64/boot/Image.gz"
DTB_T="${KERNEL_DIR}/out/arch/arm64/boot/dts/qcom/msm8953-qrd-sku3-tissot-treble.dtb"
DTB="${KERNEL_DIR}/out/arch/arm64/boot/dts/qcom/msm8953-qrd-sku3-tissot-nontreble.dtb"
TANGGAL=$(date +"%Y%m%d-%H")

# ---------------- Toolchain & env setup ----------------
# IMPORTANT: clang/bin is appended, not prepended. This is an old (2020-era)
# toolchain whose bundled `ld` chokes on the RELR relocations used by the
# runner's own glibc. Host tools (fixdep, etc.) must link with the runner's
# own gcc/ld, which only happens if system paths win the PATH search - the
# cross prefix (aarch64-linux-gnu-/arm-linux-gnueabi-) and clang are still
# found fine at the end of PATH since nothing else on the runner provides them.
export PATH="$PATH:${KERNEL_DIR}/clang/bin"
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache_mia1}"
export CCACHE_COMPILERCHECK=content
export CCACHE_SLOPPINESS=time_macros,include_file_mtime,include_file_ctime
export KBUILD_COMPILER_STRING="$(clang --version | head -n 1 | perl -pe 's/\((?:http|git).*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//' -e 's/^.*clang/clang/')"
export ARCH=arm64
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-jayarajan}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-github-actions}"

# CC is wrapped with ccache explicitly (a value containing a space) rather
# than relying on /usr/lib/ccache masquerade symlinks, which aren't
# guaranteed to exist for clang on this runner. MAKE_ARGS is an array (not a
# plain string) specifically so that space inside "ccache clang" survives as
# a single argument instead of being word-split in two.
MAKE_ARGS=(
  O=out
  ARCH=arm64
  "CC=ccache clang"
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
)

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
  make -j"$(nproc)" "${MAKE_ARGS[@]}" "$DEFCONFIG"
else
  echo "Existing out/.config found, skipping defconfig generation."
fi

# ---------------- Build ----------------
make -j"$(nproc)" "${MAKE_ARGS[@]}"

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

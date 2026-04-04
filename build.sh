#!/bin/bash

set -e
set -o pipefail

# ============================================================
# Pre-build checks for required toolchains and AnyKernel3
# ============================================================

# Paths
CLANG_DIR=~/toolchains/clang
GCC_DIR=~/toolchains/gcc-aarch64-linux-gnu-9.3
ANYKERNEL_DIR=~/AnyKernel3

# Check Clang
if [ ! -d "$CLANG_DIR" ]; then
  echo -e "\n🔍 Clang toolchain not found. Cloning..."
  git clone --depth=1 --branch lineage-20.0 \
    https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR"
else
  echo -e "\n✅ Clang already present"
fi

# Check GCC
if [ ! -d "$GCC_DIR" ]; then
  echo -e "\n🔍 GCC toolchain not found. Cloning..."
  git clone --depth=1 --branch lineage-23.0 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR"
else
  echo -e "\n✅ GCC already present"
fi

# Check AnyKernel3
if [ ! -d "$ANYKERNEL_DIR" ]; then
  echo -e "\n🔍 AnyKernel3 not found. Cloning..."
  git clone --depth=1 --branch Nitro-X \
    https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
else
  echo -e "\n✅ AnyKernel3 present"
fi

# ============================================================
# Build Script
# ============================================================

KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
BUILD_TYPE="Stable"
VERSION_NUMBER="v1.0.0"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)

ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION_NUMBER}.zip"

# Telegram
: "${TELEGRAM_TOKEN:?Need TELEGRAM_TOKEN}"
: "${TELEGRAM_CHAT_ID:?Need TELEGRAM_CHAT_ID}"

# Paths
export KERNEL_ROOT="$(pwd)"
export CLANG_PATH=$CLANG_DIR
export GCC_PATH=$GCC_DIR
export OUT_DIR=out

export PATH=$CLANG_PATH/bin:$GCC_PATH/bin:$PATH

export ARCH=arm64
export SUBARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

# =====================[ KBUILD INFO ]====================

export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date)"

echo -e "\n👷 Build Info:"
echo "User: $KBUILD_BUILD_USER"
echo "Host: $KBUILD_BUILD_HOST"

# =====================[ START ]=====================

BUILD_START=$(date +%s)

echo -e "\n🧹 Cleaning..."
rm -rf $OUT_DIR
mkdir -p $OUT_DIR

# =====================[ DEFCONFIG ]=====================

echo -e "\n📄 Defconfig..."
make O=$OUT_DIR ARCH=arm64 atoll_defconfig

# 👉 IMPORTANT FIX
make O=$OUT_DIR ARCH=arm64 olddefconfig
make O=$OUT_DIR ARCH=arm64 prepare

# =====================[ BUILD ]=====================

echo -e "\n🚀 Building..."

make -j$(nproc) O=$OUT_DIR \
  ARCH=arm64 \
  CC=clang \
  LLVM=1 \
  LLVM_IAS=1 \
  CLANG_TRIPLE=$CLANG_TRIPLE \
  CROSS_COMPILE=$CROSS_COMPILE \
  KCFLAGS="-Wno-error" \
  KBUILD_BUILD_USER="$KBUILD_BUILD_USER" \
  KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST" \
  KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
  2>&1 | tee $OUT_DIR/build.log

# =====================[ CHECK ]=====================

IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb

if [ ! -f "$IMG" ]; then
  echo -e "\n❌ Build failed!"
  exit 1
fi

echo -e "\n✅ Build success"

# =====================[ VERIFY KBUILD ]=====================

echo -e "\n🔍 Checking KBUILD..."
strings $IMG | grep JOD_BUNNY || echo "⚠️ KBUILD not applied"

# =====================[ PACK ]=====================

echo -e "\n📦 Packing..."

cp $IMG $ANYKERNEL_DIR/zImage

cd $ANYKERNEL_DIR
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md > /dev/null

cp $ZIPNAME $KERNEL_ROOT/

echo -e "\n🎉 Zip created: $ZIPNAME"

# =====================[ TIME ]=====================

BUILD_END=$(date +%s)
DIFF=$((BUILD_END - BUILD_START))

echo -e "\n⏱️ Time: $((DIFF / 60))m $((DIFF % 60))s"

# =====================[ TELEGRAM ]=====================

if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  echo -e "\n📤 Uploading..."

  curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" \
       -F chat_id="$TELEGRAM_CHAT_ID" \
       -F caption="✅ NitroX-Zenith Build

📦 $ZIPNAME
📱 $DEVICE
⚙️ $VARIANT
🧠 $KERNEL_NAME
🕐 $(date)" \
       https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null

  echo -e "\n✅ Uploaded"
else
  echo -e "\n⚠️ Telegram skipped"
fi

echo -e "\n🏁 DONE"

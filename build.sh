#!/bin/bash
set -e
set -o pipefail

# ============================================================
# Paths
# ============================================================
CLANG_DIR=~/toolchains/clang
GCC_DIR=~/toolchains/gcc-aarch64-linux-gnu-9.3
ANYKERNEL_DIR=~/AnyKernel3
OUT_DIR=out

# ============================================================
# Toolchain check
# ============================================================
[ ! -d "$CLANG_DIR" ] && echo -e "\n🔍 Clang not found. Cloning..." && \
    git clone --depth=1 --branch lineage-20.0 \
    https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR" || echo -e "\n✅ Clang present"

[ ! -d "$GCC_DIR" ] && echo -e "\n🔍 GCC not found. Cloning..." && \
    git clone --depth=1 --branch lineage-23.0 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR" || echo -e "\n✅ GCC present"

[ ! -d "$ANYKERNEL_DIR" ] && echo -e "\n🔍 AnyKernel3 not found. Cloning..." && \
    git clone --depth=1 --branch Nitro-X https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR" || echo -e "\n✅ AnyKernel3 present"

# ============================================================
# Build Info
# ============================================================
KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
BUILD_TYPE="Stable"
VERSION_NUMBER="v1.0.0"
ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-$(date +%H%M-%Y%m%d)-${VERSION_NUMBER}.zip"

export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-JOD_BUNNY}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-BUNNY-X}"
export KBUILD_BUILD_TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"

export PATH="$CLANG_DIR/bin:$GCC_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

echo -e "\n👷 Build Info:"
echo "User: $KBUILD_BUILD_USER"
echo "Host: $KBUILD_BUILD_HOST"
echo "Timestamp: $KBUILD_BUILD_TIMESTAMP"

# ============================================================
# Clean build
# ============================================================
echo -e "\n🧹 Cleaning..."
rm -rf $OUT_DIR
mkdir -p $OUT_DIR

# ============================================================
# Defconfig + prepare
# ============================================================
echo -e "\n📄 Defconfig..."
make O=$OUT_DIR ARCH=arm64 atoll_defconfig
make O=$OUT_DIR ARCH=arm64 olddefconfig
make O=$OUT_DIR ARCH=arm64 prepare

# ============================================================
# Build
# ============================================================
echo -e "\n🚀 Building..."
make -j$(nproc) O=$OUT_DIR \
    ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
    CLANG_TRIPLE=$CLANG_TRIPLE CROSS_COMPILE=$CROSS_COMPILE \
    KCFLAGS="-Wno-error" \
    KBUILD_BUILD_USER="$KBUILD_BUILD_USER" \
    KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST" \
    KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
    2>&1 | tee $OUT_DIR/build.log

# ============================================================
# Verify KBUILD
# ============================================================
IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb
DTBO=$OUT_DIR/arch/arm64/boot/dtbo.img
DTB=$OUT_DIR/arch/arm64/boot/dtb.img

[ ! -f "$IMG" ] && echo -e "\n❌ Build failed!" && exit 1

echo -e "\n🔍 Checking KBUILD..."
strings $IMG | grep "$KBUILD_BUILD_USER" || echo "⚠️ KBUILD USER not applied"
strings $IMG | grep "$KBUILD_BUILD_HOST" || echo "⚠️ KBUILD HOST not applied"
strings $IMG | grep "$(date -u +%Y%m%d)" || echo "⚠️ KBUILD TIMESTAMP not applied"

# ============================================================
# Pack AnyKernel3
# ============================================================
echo -e "\n📦 Packing AnyKernel3..."
cp $IMG $ANYKERNEL_DIR/zImage
[ -f "$DTBO" ] && cp $DTBO $ANYKERNEL_DIR/
[ -f "$DTB" ] && cp $DTB $ANYKERNEL_DIR/

cd $ANYKERNEL_DIR
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md > /dev/null
cp $ZIPNAME $KERNEL_ROOT/

echo -e "\n🎉 Zip created: $ZIPNAME"

# ============================================================
# Telegram (optional)
# ============================================================
if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  echo -e "\n📤 Uploading to Telegram..."
  curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" \
       -F chat_id="$TELEGRAM_CHAT_ID" \
       -F caption="✅ NitroX-Zenith Build
📦 $ZIPNAME
📱 $DEVICE
⚙️ $VARIANT
🧠 $KERNEL_NAME
🕐 $(date)" \
       https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument
  echo -e "\n✅ Uploaded"
fi

echo -e "\n🏁 Build finished!"

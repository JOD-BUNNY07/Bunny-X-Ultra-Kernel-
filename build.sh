#!/bin/bash
set -e
set -o pipefail

# ---------------------------
# Paths
# ---------------------------
KERNEL_ROOT="$GITHUB_WORKSPACE"
OUT_DIR="$KERNEL_ROOT/out"
CLANG_DIR="$KERNEL_ROOT/toolchains/clang"
GCC_DIR="$KERNEL_ROOT/toolchains/gcc"
ANYKERNEL_DIR="$KERNEL_ROOT/AnyKernel3"

# ---------------------------
# Toolchain Clone
# ---------------------------
if [ ! -d "$CLANG_DIR" ]; then
    git clone --depth=1 --branch lineage-20.0 \
      https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR"
fi

if [ ! -d "$GCC_DIR" ]; then
    git clone --depth=1 --branch lineage-23.0 \
      https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR"
fi

if [ ! -d "$ANYKERNEL_DIR" ]; then
    git clone --depth=1 --branch Nitro-X \
      https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
fi

chmod -R +x $ANYKERNEL_DIR
mkdir -p $OUT_DIR

# ---------------------------
# Build Info
# ---------------------------
KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
BUILD_TYPE="Stable"
VERSION_NUMBER="v1.0.0"
ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-$(date +%H%M-%Y%m%d)-${VERSION_NUMBER}.zip"

export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"

export PATH="$CLANG_DIR/bin:$GCC_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

# ---------------------------
# Build
# ---------------------------
echo -e "\n🧹 Cleaning..."
rm -rf $OUT_DIR
mkdir -p $OUT_DIR

echo -e "\n📄 Defconfig..."
make O=$OUT_DIR ARCH=arm64 atoll_defconfig
make O=$OUT_DIR ARCH=arm64 olddefconfig
make O=$OUT_DIR ARCH=arm64 prepare

echo -e "\n🚀 Building..."
make -j$(nproc) O=$OUT_DIR \
  ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
  CLANG_TRIPLE=$CLANG_TRIPLE CROSS_COMPILE=$CROSS_COMPILE \
  KCFLAGS="-Wno-error" \
  KBUILD_BUILD_USER=$KBUILD_BUILD_USER \
  KBUILD_BUILD_HOST=$KBUILD_BUILD_HOST \
  KBUILD_BUILD_TIMESTAMP=$KBUILD_BUILD_TIMESTAMP \
  2>&1 | tee $OUT_DIR/build.log

# ---------------------------
# Verify KBUILD
# ---------------------------
IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb
if [ ! -f "$IMG" ]; then
    echo -e "\n❌ Build failed!"
    exit 1
fi

echo -e "\n🔍 Checking KBUILD..."
strings -a $IMG | grep -E "$KBUILD_BUILD_USER|$KBUILD_BUILD_HOST|$KBUILD_BUILD_TIMESTAMP" || echo "⚠️ KBUILD not applied"

# ---------------------------
# AnyKernel Packing
# ---------------------------
cp $IMG $ANYKERNEL_DIR/zImage
cd $ANYKERNEL_DIR
chmod +w .
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md
cp $ZIPNAME $KERNEL_ROOT/
echo -e "\n🎉 Zip created: $ZIPNAME"

# ---------------------------
# Telegram Upload
# ---------------------------
if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    echo -e "\n📤 Uploading to Telegram..."
    curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" \
         -F chat_id="$TELEGRAM_CHAT_ID" \
         -F caption="✅ NitroX-Zenith Kernel Build

📦 $ZIPNAME
📱 Device: $DEVICE
⚙️ Variant: $VARIANT
🧠 Kernel: $KERNEL_NAME
🕐 Build Timestamp: $KBUILD_BUILD_TIMESTAMP" \
         https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null
    echo -e "\n✅ Uploaded to Telegram"
else
    echo -e "\n⚠️ TELEGRAM_TOKEN or TELEGRAM_CHAT_ID missing, skipping upload"
fi

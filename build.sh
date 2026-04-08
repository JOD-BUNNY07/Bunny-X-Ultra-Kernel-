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
# Build Info (GitHub Actions থেকে ভ্যালু না পেলে ডিফল্ট সেট হবে)
# ---------------------------
KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
BUILD_TYPE="Stable"
VERSION_NUMBER="v1.0.0"
DATE=$(date +%Y%m%d-%H%M)
ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${DATE}-${VERSION_NUMBER}.zip"

# YAML থেকে আসা ভেরিয়েবল চেক
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-JOD_BUNNY}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-BUNNY-X}"
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(date)}"

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

echo -e "\n🚀 Building..."
# ভেরিয়েবলগুলো এখানে সরাসরি পাস করা হয়েছে যা KBUILD ফিক্স করবে
make -j$(nproc) O=$OUT_DIR \
  ARCH=arm64 \
  CC=clang \
  LLVM=1 \
  LLVM_IAS=1 \
  CLANG_TRIPLE=$CLANG_TRIPLE \
  CROSS_COMPILE=$CROSS_COMPILE \
  KBUILD_BUILD_USER="$KBUILD_BUILD_USER" \
  KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST" \
  KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
  KCFLAGS="-Wno-error" \
  2>&1 | tee $OUT_DIR/build.log

# ---------------------------
# Verify KBUILD
# ---------------------------
RAW_IMG=$OUT_DIR/arch/arm64/boot/Image
IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb

if [ ! -f "$IMG" ]; then
    echo -e "\n❌ Build failed!"
    exit 1
fi

echo -e "\n🔍 Checking KBUILD..."
# RAW Image-এ চেক করা হচ্ছে কারণ strings এখানে নিখুঁত কাজ করে
if strings $RAW_IMG | grep -E -q "$KBUILD_BUILD_USER|$KBUILD_BUILD_HOST"; then
    echo "✅ KBUILD successfully applied!"
else
    echo "⚠️ KBUILD not found in strings, checking anyway..."
    strings -a $IMG | grep -E "$KBUILD_BUILD_USER|$KBUILD_BUILD_HOST" || echo "❌ KBUILD mismatch"
fi

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
# Telegram Upload (Caption updated)
# ---------------------------
if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    echo -e "\n📤 Uploading to Telegram..."
    curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" \
         -F chat_id="$TELEGRAM_CHAT_ID" \
         -F caption="✅ NitroX-Zenith Build Finished!
         
👤 User: $KBUILD_BUILD_USER
💻 Host: $KBUILD_BUILD_HOST
🕐 Time: $KBUILD_BUILD_TIMESTAMP" \
         https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null
    echo -e "\n✅ Uploaded to Telegram"
fi

#!/bin/bash

set -e
set -o pipefail

# =========================
# ROOT
# =========================
KERNEL_ROOT=$(pwd)

# =========================
# TOOLCHAINS
# =========================
CLANG_DIR=$HOME/toolchains/clang
GCC64_DIR=$HOME/toolchains/gcc64
GCC32_DIR=$HOME/toolchains/gcc32
ANYKERNEL_DIR=$KERNEL_ROOT/AnyKernel3
OUT_DIR=$KERNEL_ROOT/out

mkdir -p $HOME/toolchains
mkdir -p $OUT_DIR

# Check Clang
if [ ! -d "$CLANG_DIR" ]; then
  echo -e "\n🔍 \033[1;33mClang toolchain not found. Cloning...\033[0m"
  git clone --depth=1 --branch lineage-20.0 \
    https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR"
else
  echo -e "\n✅ \033[1;32mClang toolchain already present.\033[0m"
fi

# Check GCC
if [ ! -d "$GCC_DIR" ]; then
  echo -e "\n🔍 \033[1;33mGCC toolchain not found. Cloning...\033[0m"
  git clone --depth=1 --branch lineage-23.0 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR"
else
  echo -e "\n✅ \033[1;32mGCC toolchain already present.\033[0m"
fi

# Check AnyKernel3
if [ ! -d "$ANYKERNEL_DIR" ]; then
  echo -e "\n🔍 \033[1;33mAnyKernel3 not found. Cloning...\033[0m"
  git clone --depth=1 --branch Nitro-X \
https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
else
  echo -e "\n✅ \033[1;32mAnyKernel3 folder already present.\033[0m"
fi


# =========================
# ENVIRONMENT (CRITICAL FIX)
# =========================
export PATH=$CLANG_DIR/bin:$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH

export ARCH=arm64
export SUBARCH=arm64

export CC=clang
export REAL_CC=clang
export HOSTCC=clang
export HOSTCXX=clang++

# 👉 FIXED PREFIX
export CROSS_COMPILE=$GCC64_DIR/bin/aarch64-elf-
export CROSS_COMPILE_ARM32=$GCC32_DIR/bin/arm-eabi-
export CLANG_TRIPLE=aarch64-linux-gnu-

export LD=ld.lld

# =========================
# KERNEL INFO
# =========================
KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
VERSION="v1.0.0"

DATE=$(date +%Y%m%d-%H%M)

ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${DATE}-${VERSION}.zip"

# =========================
# KBUILD INFO
# =========================
export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date)"

echo "👤 $KBUILD_BUILD_USER @ $KBUILD_BUILD_HOST"

# =========================
# CLEAN
# =========================
echo "🧹 Cleaning..."
rm -rf $OUT_DIR
mkdir -p $OUT_DIR

# =========================
# DEFCONFIG
# =========================
echo "📄 Running defconfig..."

make O=$OUT_DIR ARCH=arm64 atoll_defconfig

# 👉 STACK PROTECTOR FIX
scripts/config --file $OUT_DIR/.config --disable CONFIG_CC_STACKPROTECTOR_STRONG || true

make O=$OUT_DIR ARCH=arm64 olddefconfig
make O=$OUT_DIR ARCH=arm64 prepare

# =========================
# BUILD
# =========================
echo "🚀 Building..."

make -j$(nproc) O=$OUT_DIR \
  ARCH=arm64 \
  CC=clang \
  LLVM=1 \
  LLVM_IAS=1 \
  LD=ld.lld \
  CROSS_COMPILE=$CROSS_COMPILE \
  CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32 \
  CLANG_TRIPLE=$CLANG_TRIPLE \
  KCFLAGS="-Wno-error" \
  KBUILD_BUILD_USER=$KBUILD_BUILD_USER \
  KBUILD_BUILD_HOST=$KBUILD_BUILD_HOST \
  KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
  2>&1 | tee $OUT_DIR/build.log

# =========================
# CHECK IMAGE
# =========================
IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb

if [ ! -f "$IMG" ]; then
  echo "❌ Build failed!"
  exit 1
fi

echo "✅ Build success"

# =========================
# VERIFY KBUILD
# =========================
strings $IMG | grep JOD_BUNNY || echo "⚠️ KBUILD not applied"

# =========================
# PACK ZIP
# =========================
echo "📦 Packing..."

cp $IMG $ANYKERNEL_DIR/zImage

cd $ANYKERNEL_DIR
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md > /dev/null

cp $ZIPNAME $KERNEL_ROOT/

echo "🎉 Zip: $ZIPNAME"

# =========================
# TELEGRAM
# =========================
if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  echo "📤 Uploading..."

  curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" \
       -F chat_id="$TELEGRAM_CHAT_ID" \
       -F caption="✅ NitroX-Zenith Build

📦 $ZIPNAME
📱 $DEVICE
⚙️ $VARIANT
🧠 $KERNEL_NAME
🕐 $(date)" \
       https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null

  echo "✅ Uploaded"
else
  echo "⚠️ Telegram skipped"
fi

echo "🏁 DONE"

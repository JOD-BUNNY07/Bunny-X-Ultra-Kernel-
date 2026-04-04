#!/bin/bash

set -e
set -o pipefail

# =========================
# PATHS
# =========================
KERNEL_ROOT=$(pwd)

CLANG_DIR=$HOME/toolchains/clang
GCC_DIR=$HOME/toolchains/gcc-aarch64-linux-gnu-9.3
ANYKERNEL_DIR=$KERNEL_ROOT/AnyKernel3
OUT_DIR=$KERNEL_ROOT/out

mkdir -p $HOME/toolchains
mkdir -p $OUT_DIR

# =========================
# CLANG
# =========================
if [ ! -d "$CLANG_DIR" ]; then
  echo "🔍 Cloning Clang..."
  git clone --depth=1 --branch lineage-20.0 \
    https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR"
else
  echo "✅ Clang present"
fi

# =========================
# GCC
# =========================
if [ ! -d "$GCC_DIR" ]; then
  echo "🔍 Cloning GCC..."
  git clone --depth=1 --branch lineage-23.0 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR"
else
  echo "✅ GCC present"
fi

# =========================
# ANYKERNEL3
# =========================
if [ ! -d "$ANYKERNEL_DIR" ]; then
  echo "🔍 Cloning AnyKernel3..."
  git clone --depth=1 -b Nitro-X \
    https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
fi

# =========================
# ENVIRONMENT
# =========================
export PATH=$CLANG_DIR/bin:$GCC_DIR/bin:$PATH

export ARCH=arm64
export SUBARCH=arm64

export CC=clang
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-
export LD=ld.lld

# =========================
# KERNEL INFO
# =========================
KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
BUILD_TYPE="Stable"
VERSION_NUMBER="v1.0.0"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)

ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION_NUMBER}.zip"

# =========================
# KBUILD INFO
# =========================
export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date)"

echo "👤 User: $KBUILD_BUILD_USER"
echo "💻 Host: $KBUILD_BUILD_HOST"

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

# 👉 VERY IMPORTANT FIX (missing ছিল আগে)
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
echo "📦 Creating zip..."

cp $IMG $ANYKERNEL_DIR/zImage

cd $ANYKERNEL_DIR
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md > /dev/null

# 👉 IMPORTANT (artifact fix)
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

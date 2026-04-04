#!/bin/bash

set -e
set -o pipefail

# ============================================================
# PATH SETUP
# ============================================================

KERNEL_ROOT=$(pwd)

CLANG_DIR=$HOME/toolchains/clang
GCC_DIR=$HOME/toolchains/gcc-aarch64-linux-gnu-9.3
ANYKERNEL_DIR=$KERNEL_ROOT/AnyKernel3
OUT_DIR=$KERNEL_ROOT/out

mkdir -p $HOME/toolchains

# ============================================================
# CLANG
# ============================================================

if [ ! -d "$CLANG_DIR" ]; then
    echo -e "\n🔍 Clang not found. Cloning..."
    git clone --depth=1 --branch lineage-20.0 \
    https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR"
else
    echo -e "\n✅ Clang present"
fi

# ============================================================
# GCC
# ============================================================

if [ ! -d "$GCC_DIR" ]; then
    echo -e "\n🔍 GCC not found. Cloning..."
    git clone --depth=1 --branch lineage-23.0 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR"
else
    echo -e "\n✅ GCC present"
fi

# ============================================================
# ANYKERNEL3
# ============================================================

if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo -e "\n🔍 AnyKernel3 not found. Cloning..."
    git clone --depth=1 --branch Nitro-X \
    https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
else
    echo -e "\n✅ AnyKernel3 present"
fi

# ============================================================
# KERNEL INFO
# ============================================================

KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
BUILD_TYPE="Stable"
VERSION_NUMBER="v1.0.0"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)

ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION_NUMBER}.zip"

# ============================================================
# TELEGRAM
# ============================================================

: "${TELEGRAM_TOKEN:?Need TELEGRAM_TOKEN}"
: "${TELEGRAM_CHAT_ID:?Need TELEGRAM_CHAT_ID}"

# ============================================================
# ENVIRONMENT
# ============================================================

export PATH=$CLANG_DIR/bin:$GCC_DIR/bin:$PATH

export ARCH=arm64
export SUBARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-

# 🔥 KBUILD INFO
export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date)"
export LOCALVERSION="-$KERNEL_NAME-$VARIANT"

echo -e "\n👤 User: $KBUILD_BUILD_USER"
echo -e "💻 Host: $KBUILD_BUILD_HOST"

echo -e "\n🔧 Clang version:"
$CLANG_DIR/bin/clang --version | head -n 1

# ============================================================
# CLEAN
# ============================================================

echo -e "\n🧹 Cleaning..."

rm -rf $OUT_DIR
mkdir -p $OUT_DIR

make O=$OUT_DIR ARCH=arm64 mrproper

# ============================================================
# DEFCONFIG
# ============================================================

echo -e "\n📄 Running defconfig..."

make O=$OUT_DIR ARCH=arm64 atoll_defconfig
make O=$OUT_DIR ARCH=arm64 olddefconfig
make O=$OUT_DIR ARCH=arm64 prepare

# ============================================================
# BUILD START TIMER
# ============================================================

BUILD_START=$(date +%s)

# ============================================================
# BUILD
# ============================================================

echo -e "\n🚀 Building kernel..."

make -j$(nproc) O=$OUT_DIR \
  ARCH=arm64 \
  CC=clang \
  HOSTCC=clang \
  LLVM=1 \
  LLVM_IAS=1 \
  LD=ld.lld \
  AR=llvm-ar \
  NM=llvm-nm \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  STRIP=llvm-strip \
  CLANG_TRIPLE=$CLANG_TRIPLE \
  CROSS_COMPILE=$CROSS_COMPILE \
  KCFLAGS="-Wno-error" \
  KBUILD_BUILD_USER="$KBUILD_BUILD_USER" \
  KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST" \
  KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
  2>&1 | tee $OUT_DIR/build.log

# ============================================================
# CHECK IMAGE
# ============================================================

IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb

if [ ! -f "$IMG" ]; then
    echo -e "\n❌ Build failed!"
    exit 1
fi

echo -e "\n✅ Build success"

# ============================================================
# VERIFY KBUILD
# ============================================================

echo -e "\n🔍 Kernel banner:"

strings $IMG | grep "Linux version"

# ============================================================
# PACKAGING
# ============================================================

echo -e "\n📦 Packing zip..."

cp "$IMG" "$ANYKERNEL_DIR/zImage"

cd $ANYKERNEL_DIR
zip -r9 "$ZIPNAME" * -x "*.git*" "*.zip" README.md > /dev/null

cp "$ZIPNAME" "$KERNEL_ROOT/"

echo -e "\n🎉 Zip created: $ZIPNAME"

# ============================================================
# TIME
# ============================================================

BUILD_END=$(date +%s)
DIFF=$((BUILD_END - BUILD_START))

echo -e "\n⏱️ Build time: $((DIFF / 60))m $((DIFF % 60))s"

# ============================================================
# TELEGRAM UPLOAD
# ============================================================

echo -e "\n📤 Uploading to Telegram..."

curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" \
     -F chat_id="$TELEGRAM_CHAT_ID" \
     -F caption="✅ <b>NitroX-Zenith Kernel Build</b>

📦 <code>$ZIPNAME</code>
📱 <code>$DEVICE</code>
⚙️ <code>$VARIANT</code>
🧠 <code>$KERNEL_NAME</code>
🕐 <code>$(date)</code>" \
     -F parse_mode="HTML" \
     https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null

echo -e "\n✅ Uploaded successfully"

echo -e "\n🏁 DONE"

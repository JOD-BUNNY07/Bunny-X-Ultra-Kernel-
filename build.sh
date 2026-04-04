#!/bin/bash

set -e
set -o pipefail

# =========================
# PATH SETUP
# =========================
KERNEL_ROOT=$(pwd)

CLANG_DIR=$HOME/toolchains/clang
GCC_DIR=$HOME/toolchains/gcc
ANYKERNEL_DIR=$KERNEL_ROOT/AnyKernel3
OUT_DIR=$KERNEL_ROOT/out

mkdir -p $HOME/toolchains
mkdir -p $OUT_DIR

# =========================
# CLANG 17
# =========================
if [ ! -d "$CLANG_DIR" ]; then
    echo "🔍 Clang 17 not found. Cloning..."
    git clone --depth=1 https://github.com/ZyCromerZ/Clang.git "$CLANG_DIR"
else
    echo "✅ Clang present"
fi

# =========================
# GCC
# =========================
if [ ! -d "$GCC_DIR" ]; then
    echo "🔍 GCC not found. Cloning..."
    git clone --depth=1 https://github.com/mvaisakh/gcc-arm64.git "$GCC_DIR"
fi

# =========================
# ANYKERNEL3
# =========================
if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo "🔍 AnyKernel3 not found. Cloning..."
    git clone --depth=1 -b Nitro-X https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
fi

# =========================
# CUSTOM KERNEL INFO
# =========================
KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
VERSION_NO="v1.0.0"

export LOCALVERSION="-$KERNEL_NAME-$VARIANT-$DEVICE-$VERSION_NO"

export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date)"
export KBUILD_COMPILER_STRING="$($CLANG_DIR/bin/clang --version | head -n 1)"

# =========================
# ENVIRONMENT
# =========================
export PATH=$CLANG_DIR/bin:$GCC_DIR/bin:$PATH

export ARCH=arm64
export SUBARCH=arm64

export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-

# =========================
# INFO
# =========================
echo "🔧 Using Clang:"
clang --version | head -n 1

echo "📱 Device: $DEVICE"
echo "🧠 Kernel: $KERNEL_NAME ($VARIANT)"

# =========================
# CLEAN
# =========================
echo "🧹 Cleaning..."
rm -rf $OUT_DIR
mkdir -p $OUT_DIR
ccache -C || true

# =========================
# DEFCONFIG
# =========================
echo "📄 Running defconfig..."
make O=$OUT_DIR ARCH=arm64 atoll_defconfig

make O=$OUT_DIR ARCH=arm64 olddefconfig
make O=$OUT_DIR ARCH=arm64 prepare

# =========================
# BUILD
# =========================
echo "🚀 Building kernel..."

make -j$(nproc) O=$OUT_DIR \
    ARCH=arm64 \
    CC=clang \
    LLVM=1 \
    LLVM_IAS=1 \
    LD=$CLANG_DIR/bin/ld.lld \
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

echo "✅ Build successful"

# =========================
# VERIFY
# =========================
echo "🔍 Verifying KBUILD..."
strings $IMG | grep JOD_BUNNY || echo "⚠️ KBUILD not applied!"

# =========================
# PACK
# =========================
echo "📦 Creating zip..."

cp $IMG $ANYKERNEL_DIR/zImage

cd $ANYKERNEL_DIR

ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${VERSION_NO}-$(date +%H%M-%d%m).zip"

zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md > /dev/null

cp $ZIPNAME $KERNEL_ROOT/

echo "🎉 Zip created: $ZIPNAME"

# =========================
# TELEGRAM
# =========================
if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    echo "📤 Uploading to Telegram..."

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

    echo "✅ Uploaded to Telegram"
else
    echo "⚠️ Telegram skipped"
fi

echo "🏁 DONE"

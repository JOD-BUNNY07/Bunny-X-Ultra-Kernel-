#!/bin/bash

set -e
set -o pipefail

# =========================
# ROOT PATH
# =========================
KERNEL_ROOT=$(pwd)

# =========================
# TOOLCHAIN PATHS
# =========================
CLANG_DIR=$HOME/toolchains/clang
GCC64_DIR=$HOME/toolchains/gcc64
GCC32_DIR=$HOME/toolchains/gcc32
ANYKERNEL_DIR=$KERNEL_ROOT/AnyKernel3
OUT_DIR=$KERNEL_ROOT/out

mkdir -p $HOME/toolchains
mkdir -p $OUT_DIR

# =========================
# CLANG 17
# =========================
if [ ! -d "$CLANG_DIR" ]; then
    echo "🔍 Cloning Clang 17..."
    git clone --depth=1 https://github.com/ZyCromerZ/Clang.git "$CLANG_DIR"
else
    echo "✅ Clang already present"
fi

# =========================
# GCC 64
# =========================
if [ ! -d "$GCC64_DIR" ]; then
    echo "🔍 Cloning GCC64..."
    git clone --depth=1 https://github.com/mvaisakh/gcc-arm64.git "$GCC64_DIR"
fi

# =========================
# GCC 32 (IMPORTANT)
# =========================
if [ ! -d "$GCC32_DIR" ]; then
    echo "🔍 Cloning GCC32..."
    git clone --depth=1 https://github.com/mvaisakh/gcc-arm.git "$GCC32_DIR"
fi

# =========================
# ANYKERNEL3
# =========================
if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo "🔍 Cloning AnyKernel3..."
    git clone --depth=1 -b Nitro-X https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
fi

# =========================
# EXPORT PATH (CRITICAL FIX)
# =========================
export PATH=$CLANG_DIR/bin:$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH

# Verify clang
echo "🔧 Using Clang:"
$CLANG_DIR/bin/clang --version | head -n 1

# =========================
# ENVIRONMENT
# =========================
export ARCH=arm64
export SUBARCH=arm64

export CC=clang
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export CLANG_TRIPLE=aarch64-linux-gnu-

# =========================
# KERNEL INFO
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

echo "✅ Build successful"

# =========================
# VERIFY KBUILD
# =========================
echo "🔍 Checking KBUILD..."
strings $IMG | grep JOD_BUNNY || echo "⚠️ KBUILD not applied!"

# =========================
# PACK ZIP
# =========================
echo "📦 Creating zip..."

cp $IMG $ANYKERNEL_DIR/zImage

cd $ANYKERNEL_DIR

ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${VERSION_NO}-$(date +%H%M-%d%m).zip"

zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md > /dev/null

cp $ZIPNAME $KERNEL_ROOT/

echo "🎉 Zip created: $ZIPNAME"

# =========================
# TELEGRAM UPLOAD
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

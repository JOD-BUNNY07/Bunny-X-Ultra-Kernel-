#!/bin/bash

set -e
set -o pipefail

# ================= PATH SETUP =================

export KERNEL_ROOT="$(pwd)"
CLANG_DIR=$HOME/toolchains/clang
GCC_DIR=$HOME/toolchains/gcc
ANYKERNEL_DIR=$KERNEL_ROOT/AnyKernel3
OUT_DIR=$KERNEL_ROOT/out

mkdir -p $HOME/toolchains
mkdir -p $OUT_DIR

# ================= TOOLCHAINS =================

# Clang 17 (r498229)
if [ ! -d "$CLANG_DIR" ]; then
    echo "🔍 Clang 17 not found. Cloning..."
    git clone --depth=1 https://github.com/ZyCromerZ/Clang.git "$CLANG_DIR"
else
    echo "✅ Clang already present"
fi

# GCC 9.3
if [ ! -d "$GCC_DIR" ]; then
    echo "🔍 GCC not found. Cloning..."
    git clone --depth=1 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git \
    "$GCC_DIR"
else
    echo "✅ GCC already present"
fi

# AnyKernel3
if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo "🔍 AnyKernel3 not found. Cloning..."
    git clone --depth=1 --branch Nitro-X \
    https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
else
    echo "✅ AnyKernel3 already present"
fi

# ================= BUILD CONFIG =================

KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"

DATE=$(date +%Y%m%d-%H%M)
ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${DATE}.zip"

# ================= ENV =================

export PATH=$CLANG_DIR/bin:$GCC_DIR/bin:$PATH
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date)"

# ================= CLEAN =================

echo "🧹 Cleaning..."
rm -rf $OUT_DIR
mkdir -p $OUT_DIR
ccache -C || true

# ================= INFO =================

echo "🔧 Compiler Info:"
clang --version | head -n 1
aarch64-linux-gcc --version | head -n 1

echo "📱 Device: $DEVICE"

# ================= DEFCONFIG =================

echo "⚙️ Running defconfig..."
make O=$OUT_DIR ARCH=arm64 atoll_defconfig

echo "⚙️ Preparing kernel..."
make O=$OUT_DIR ARCH=arm64 olddefconfig
make O=$OUT_DIR ARCH=arm64 prepare

# ================= BUILD =================

echo "🚀 Building kernel..."

make -j$(nproc) O=$OUT_DIR \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    LD=ld.lld \
    KCFLAGS="-Wno-error" \
    CLANG_TRIPLE=$CLANG_TRIPLE \
    CROSS_COMPILE=$CROSS_COMPILE \
    KBUILD_BUILD_USER=$KBUILD_BUILD_USER \
    KBUILD_BUILD_HOST=$KBUILD_BUILD_HOST \
    KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
    2>&1 | tee $OUT_DIR/build.log

# ================= CHECK =================

IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb

if [ ! -f "$IMG" ]; then
    echo "❌ Build failed: Image not found"
    exit 1
fi

echo "✅ Kernel compiled successfully"

# ================= VERIFY USER =================

echo "🔍 Checking KBUILD..."
strings $IMG | grep JOD || echo "⚠️ KBUILD not applied!"

# ================= PACK =================

echo "📦 Packing zip..."

cp $IMG $ANYKERNEL_DIR/zImage

cd $ANYKERNEL_DIR
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" > /dev/null

cp $ZIPNAME $KERNEL_ROOT/

echo "🎉 Zip created: $ZIPNAME"

# ================= TELEGRAM UPLOAD =================

if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    echo "📤 Uploading to Telegram..."

    curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" \
         -F chat_id="$TELEGRAM_CHAT_ID" \
         -F caption="✅ <b>Kernel Build Success</b>

📦 <code>$ZIPNAME</code>
📱 <code>$DEVICE</code>
🧠 <code>BunnyX-PERF Kernel</code>
👤 <code>JOD_BUNNY</code>
🕐 <code>$(date)</code>" \
         -F parse_mode="HTML" \
         "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument"

    echo "✅ Uploaded to Telegram"
else
    echo "⚠️ Telegram not configured"
fi

echo "🏁 DONE"

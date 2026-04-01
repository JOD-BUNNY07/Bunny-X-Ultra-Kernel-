#!/bin/bash

set -e
set -o pipefail

# ============================================================
# Pre-build checks for required toolchains and AnyKernel3
# ============================================================

# Paths
CLANG_DIR=$HOME/toolchains/clang
GCC_DIR=$HOME/toolchains/gcc-aarch64-linux-gnu-9.3
ANYKERNEL_DIR=$HOME/AnyKernel3
OUT_DIR=$HOME/out

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

# ============================================================
# Kernel Build Config
# ============================================================

KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
BUILD_TYPE="Stable"
VERSION_NUMBER="v1.0.0"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)
BASE_ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION_NUMBER}"
ZIPNAME="${BASE_ZIPNAME}.zip"

# Telegram
: "${TELEGRAM_TOKEN:?Need TELEGRAM_TOKEN environment variable}"
: "${TELEGRAM_CHAT_ID:?Need TELEGRAM_CHAT_ID environment variable}"

# ============================================================
# Export Environment
# ============================================================

export KERNEL_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export CLANG_PATH=$CLANG_DIR
export GCC_PATH=$GCC_DIR
export ANYKERNEL_DIR=$ANYKERNEL_DIR
export OUT_DIR=$OUT_DIR

export PATH=$CLANG_PATH/bin:$GCC_PATH/bin:$PATH
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export BUILD_TIME=$(date '+%a %b %d %H:%M:%S IST %Y')
export KBUILD_BUILD_TIMESTAMP="$BUILD_TIME"

# ============================================================
# Start Build
# ============================================================

BUILD_START=$(date +%s)
echo -e "\n🛠️  Starting Kernel Build: $BASE_ZIPNAME"

echo -e "\n🧹 Cleaning output and ccache..."
make O=$OUT_DIR mrproper
rm -f "$ANYKERNEL_DIR/zImage"
ccache -C > /dev/null 2>&1

echo -e "\n🔧 Compiler Info:"
clang --version | head -n 1
aarch64-linux-gcc --version | head -n 1

echo -e "\n📱 Target Device: $DEVICE"

# =====================[ DEFCONFIG ]====================
echo -e "\n📄 Setting up defconfig..."
make O=$OUT_DIR ARCH=arm64 atoll_defconfig || {
    echo -e "\n❌ Defconfig failed. Exiting."
    exit 1
}

echo -e "\n🔧 Preparing kernel (olddefconfig + prepare)..."
make O=$OUT_DIR ARCH=arm64 olddefconfig
make O=$OUT_DIR ARCH=arm64 prepare

# ===================== COMPILING =====================
echo -e "\n🚀 Starting compilation..."
JOBS=$(( $(nproc) - 1 ))
make -j$JOBS O=$OUT_DIR \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    CLANG_TRIPLE=$CLANG_TRIPLE \
    CROSS_COMPILE=$CROSS_COMPILE \
    2>&1 | tee $OUT_DIR/full_build.log | grep --line-buffered -E "warning:|error:" | sed \
    -e 's/warning:/\x1b[1;33mwarning:\x1b[0m/g' \
    -e 's/error:/\x1b[1;31merror:\x1b[0m/g'

# ===================== CHECK IMAGE =====================
KERNEL_IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb
if [ ! -f "$KERNEL_IMG" ]; then
    echo -e "\n❌ Build failed: Image.gz-dtb not found!"
    exit 1
fi
echo -e "\n✅ Kernel image compiled successfully."

# ===================== PACKAGING =====================
echo -e "\n📦 Packing kernel into flashable zip..."
cp "$KERNEL_IMG" "$ANYKERNEL_DIR/zImage"

cd $ANYKERNEL_DIR || exit 1
zip -r9 "$ZIPNAME" * -x "*.zip" "*.git*" README.md > /dev/null

if [ $? -eq 0 ]; then
    echo -e "\n🎉 Flashable zip created: $ANYKERNEL_DIR/$ZIPNAME"
else
    echo -e "\n❌ Failed to create zip."
    exit 1
fi

BUILD_END=$(date +%s)
DIFF=$((BUILD_END - BUILD_START))
echo -e "\n⏱️ Build completed in $((DIFF / 60))m $((DIFF % 60))s"

# ===================== TELEGRAM UPLOAD =====================
if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    echo -e "\n📤 Uploading zip to Telegram..."
    curl -s -F document=@"$ANYKERNEL_DIR/$ZIPNAME" \
         -F chat_id="$TELEGRAM_CHAT_ID" \
         -F caption="✅ Kernel Build Success
📦 $ZIPNAME
📱 $DEVICE
🕐 $(date)" \
         -F parse_mode="HTML" \
         "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" > /dev/null
    if [ $? -eq 0 ]; then
        echo -e "\n✅ Uploaded to Telegram successfully!"
    else
        echo -e "\n❌ Telegram upload failed."
    fi
else
    echo -e "\n⚠️ Skipping Telegram upload — credentials not set."
fi

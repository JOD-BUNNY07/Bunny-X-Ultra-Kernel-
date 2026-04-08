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
[[ ! -d "$CLANG_DIR" ]] && git clone --depth=1 --branch lineage-20.0 https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR"
[[ ! -d "$GCC_DIR" ]] && git clone --depth=1 --branch lineage-23.0 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR"
[[ ! -d "$ANYKERNEL_DIR" ]] && git clone --depth=1 --branch Nitro-X https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"

chmod -R +x $ANYKERNEL_DIR
mkdir -p $OUT_DIR

# ---------------------------
# Build Info
# ---------------------------
export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date)"

# ---------------------------
# 🛠 1. Defconfig Cleanup (The Fix for 'unexpected data')
# ---------------------------
echo -e "\n🧹 Fixing defconfig formatting..."
DEFCONFIG="arch/arm64/configs/atoll_defconfig"
# লাইনের শুরুতে থাকা '+' এবং '-' চিহ্ন সরিয়ে ফেলা হচ্ছে
sed -i 's/^[+-]//g' "$DEFCONFIG"
sed -i 's/^[ \t]*//' "$DEFCONFIG"

# ---------------------------
# 🛠 2. Hard-Fix Makefile (The Fix for KBUILD not applying)
# ---------------------------
echo -e "\n🛠 Patching Makefile variables..."
# সরাসরি Makefile-এ থাকা ডিফল্ট ভেরিয়েবলগুলোকে রিপ্লেস করা
sed -i "s/KBUILD_BUILD_USER :=.*/KBUILD_BUILD_USER := $KBUILD_BUILD_USER/g" Makefile
sed -i "s/KBUILD_BUILD_HOST :=.*/KBUILD_BUILD_HOST := $KBUILD_BUILD_HOST/g" Makefile

# ---------------------------
# Build Environment
# ---------------------------
export PATH="$CLANG_DIR/bin:$GCC_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

echo -e "\n🧹 Cleaning..."
rm -rf $OUT_DIR && mkdir -p $OUT_DIR

echo -e "\n📄 Generating Defconfig..."
make O=$OUT_DIR ARCH=arm64 atoll_defconfig

# 🛠 Force apply into .config
echo "CONFIG_KBUILD_BUILD_USER=\"$KBUILD_BUILD_USER\"" >> $OUT_DIR/.config
echo "CONFIG_KBUILD_BUILD_HOST=\"$KBUILD_BUILD_HOST\"" >> $OUT_DIR/.config
echo "CONFIG_LOCALVERSION_AUTO=n" >> $OUT_DIR/.config

make O=$OUT_DIR ARCH=arm64 olddefconfig

echo -e "\n🚀 Starting Build..."
make -j$(nproc) O=$OUT_DIR \
  ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
  CLANG_TRIPLE=$CLANG_TRIPLE CROSS_COMPILE=$CROSS_COMPILE \
  KBUILD_BUILD_USER="$KBUILD_BUILD_USER" \
  KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST" \
  KCFLAGS="-Wno-error" 2>&1 | tee $OUT_DIR/build.log

# ---------------------------
# Verification
# ---------------------------
RAW_IMG=$OUT_DIR/arch/arm64/boot/Image
IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb

if [ ! -f "$IMG" ]; then
    echo -e "\n❌ Build failed!"
    exit 1
fi

echo -e "\n🔍 Checking KBUILD again..."
# এবার strings ইমেজ ফাইলের ভেতর আপনার দেওয়া নাম খোঁজার চেষ্টা করবে
if strings $RAW_IMG | grep -E -i "$KBUILD_BUILD_USER|$KBUILD_BUILD_HOST"; then
    echo "✅ KBUILD APPLIED!"
else
    echo "❌ KBUILD still not found in strings, but zip is being created."
fi

# ---------------------------
# Packing
# ---------------------------
cp $IMG $ANYKERNEL_DIR/zImage
cd $ANYKERNEL_DIR
ZIPNAME="NitroX-Zenith-RMX2061-$(date +%H%M).zip"
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md
cp $ZIPNAME $KERNEL_ROOT/

if [[ -n "$TELEGRAM_TOKEN" ]]; then
    curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" -F chat_id="$TELEGRAM_CHAT_ID" \
         -F caption="✅ Build Finished! User: $KBUILD_BUILD_USER" \
         https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null
fi

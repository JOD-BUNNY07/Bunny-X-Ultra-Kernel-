#!/bin/bash
set -e
set -o pipefail

# ---------------------------
# Paths & Setup
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
# 🛠 Kernel Information
# ---------------------------
export KERNEL_NAME="NitroX-Zenith"
export DEVICE="Realme 6 Pro (RMX2061)"
export VARIANT="KSU-Next (Stable)"
export VERSION="v1.0.0"
export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date)"

# ---------------------------
# 🛠 FIX: Force Patch Build Scripts (The Ultimate Fix)
# ---------------------------
echo -e "\n🛠 Patching compilation scripts to force User/Host..."
if [ -f "scripts/mkcompile_h" ]; then
    # কার্নেলের ইন্টারনাল স্ক্রিপ্টকে বাধ্য করা হচ্ছে যাতে সে সিস্টেমের বদলে আপনার নাম ব্যবহার করে
    sed -i "s/\`whoami\`/echo $KBUILD_BUILD_USER/g" scripts/mkcompile_h
    sed -i "s/\`hostname\`/echo $KBUILD_BUILD_HOST/g" scripts/mkcompile_h
    sed -i "s/\$(whoami)/$KBUILD_BUILD_USER/g" scripts/mkcompile_h
    sed -i "s/\$(hostname)/$KBUILD_BUILD_HOST/g" scripts/mkcompile_h
fi

# ---------------------------
# Build Environment
# ---------------------------
export PATH="$CLANG_DIR/bin:$GCC_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

echo -e "\n🧹 Cleaning out directory..."
rm -rf $OUT_DIR && mkdir -p $OUT_DIR

echo -e "\n📄 Generating Defconfig..."
make O=$OUT_DIR ARCH=arm64 atoll_defconfig

# 🛠 Force apply KBUILD into .config to avoid overrides
echo "CONFIG_KBUILD_BUILD_USER=\"$KBUILD_BUILD_USER\"" >> $OUT_DIR/.config
echo "CONFIG_KBUILD_BUILD_HOST=\"$KBUILD_BUILD_HOST\"" >> $OUT_DIR/.config
echo "CONFIG_LOCALVERSION_AUTO=n" >> $OUT_DIR/.config

make O=$OUT_DIR ARCH=arm64 olddefconfig

echo -e "\n🚀 Starting Kernel Build..."
make -j$(nproc) O=$OUT_DIR \
  ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
  CLANG_TRIPLE=$CLANG_TRIPLE CROSS_COMPILE=$CROSS_COMPILE \
  KBUILD_BUILD_USER="$KBUILD_BUILD_USER" \
  KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST" \
  KCFLAGS="-Wno-error" 2>&1 | tee $OUT_DIR/build.log

# ---------------------------
# Verification & Packing
# ---------------------------
RAW_IMG=$OUT_DIR/arch/arm64/boot/Image
IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb

if [ ! -f "$IMG" ]; then
    echo -e "\n❌ Build failed! Check the log."
    exit 1
fi

# 🔍 Final KBUILD check
echo -e "\n🔍 Verifying KBUILD info in Image..."
if strings $RAW_IMG | grep -E -i "$KBUILD_BUILD_USER|$KBUILD_BUILD_HOST"; then
    echo "✅ SUCCESS: KBUILD Info Applied!"
else
    echo "⚠️ Warning: Strings check failed, but proceeding to pack."
fi

cp $IMG $ANYKERNEL_DIR/zImage
cd $ANYKERNEL_DIR
DATE=$(date +%Y%m%d-%H%M)
ZIPNAME="${KERNEL_NAME}-${VERSION}-RMX2061-${DATE}.zip"
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md
cp $ZIPNAME $KERNEL_ROOT/

# ---------------------------
# 📤 Telegram Upload with Info
# ---------------------------
if [[ -n "$TELEGRAM_TOKEN" ]]; then
    CAPTION="✅ **Kernel Build Success!**

📝 **Kernel Name:** $KERNEL_NAME
📱 **Device:** $DEVICE
🛠 **Variant:** $VARIANT
🔢 **Version:** $VERSION
👤 **Built by:** $KBUILD_BUILD_USER
💻 **Host:** $KBUILD_BUILD_HOST
📅 **Date:** $(date +'%d-%m-%Y %H:%M')"

    curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" -F chat_id="$TELEGRAM_CHAT_ID" \
         -F caption="$CAPTION" -F parse_mode="Markdown" \
         https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null
fi

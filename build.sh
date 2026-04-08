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
    echo -e "\n📦 Cloning Clang..."
    git clone --depth=1 --branch lineage-20.0 \
      https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR"
fi

if [ ! -d "$GCC_DIR" ]; then
    echo -e "\n📦 Cloning GCC..."
    git clone --depth=1 --branch lineage-23.0 \
      https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR"
fi

if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo -e "\n📦 Cloning AnyKernel3..."
    git clone --depth=1 --branch Nitro-X \
      https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
fi

chmod -R +x $ANYKERNEL_DIR
mkdir -p $OUT_DIR

# ---------------------------
# Build Info
# ---------------------------
KERNEL_NAME="NitroX-Zenith"
DEVICE="RMX2061"
VARIANT="KSUN"
BUILD_TYPE="Stable"
VERSION_NUMBER="v1.0.0"
DATE=$(date +%Y%m%d-%H%M)
ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${DATE}-${VERSION_NUMBER}.zip"

# Environment Variables (Prioritize GitHub Actions)
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-JOD_BUNNY}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-BUNNY-X}"
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(date)}"

export PATH="$CLANG_DIR/bin:$GCC_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-

# ---------------------------
# Build Process
# ---------------------------
echo -e "\n🧹 Cleaning out directory..."
rm -rf $OUT_DIR
mkdir -p $OUT_DIR

echo -e "\n📄 Generating Defconfig..."
make O=$OUT_DIR ARCH=arm64 atoll_defconfig

# --- জোরপূর্বক KBUILD তথ্য ইনজেক্ট করা ---
echo -e "\n🛠 Forcing KBUILD info into .config..."
sed -i "s/CONFIG_LOCALVERSION_AUTO=y/CONFIG_LOCALVERSION_AUTO=n/" $OUT_DIR/.config
sed -i "/CONFIG_KBUILD_BUILD_USER/d" $OUT_DIR/.config
sed -i "/CONFIG_KBUILD_BUILD_HOST/d" $OUT_DIR/.config
echo "CONFIG_KBUILD_BUILD_USER=\"$KBUILD_BUILD_USER\"" >> $OUT_DIR/.config
echo "CONFIG_KBUILD_BUILD_HOST=\"$KBUILD_BUILD_HOST\"" >> $OUT_DIR/.config

make O=$OUT_DIR ARCH=arm64 olddefconfig

echo -e "\n🚀 Starting Kernel Build..."
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
# Verification
# ---------------------------
IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb
RAW_IMG=$OUT_DIR/arch/arm64/boot/Image

if [ ! -f "$IMG" ]; then
    echo -e "\n❌ Build failed! Image.gz-dtb not found."
    exit 1
fi

echo -e "\n🔍 Verifying KBUILD details..."
# Image ফাইলে আপনার নাম চেক করা হচ্ছে (এটি সবথেকে নির্ভুল পদ্ধতি)
if strings $RAW_IMG | grep -E -q "$KBUILD_BUILD_USER|$KBUILD_BUILD_HOST"; then
    echo "✅ Success: KBUILD applied perfectly!"
else
    echo "⚠️ Warning: KBUILD not found in strings, checking compressed image..."
    strings $IMG | grep -E "$KBUILD_BUILD_USER|$KBUILD_BUILD_HOST" || echo "❌ KBUILD verification failed."
fi

# ---------------------------
# Packing
# ---------------------------
echo -e "\n📦 Packing AnyKernel3..."
cp $IMG $ANYKERNEL_DIR/zImage
cd $ANYKERNEL_DIR
chmod +w .
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md
cp $ZIPNAME $KERNEL_ROOT/
echo -e "\n🎉 Zip created: $ZIPNAME"

# ---------------------------
# Telegram Upload
# ---------------------------
if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    echo -e "\n📤 Uploading to Telegram..."
    curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" \
         -F chat_id="$TELEGRAM_CHAT_ID" \
         -F caption="✅ **NitroX-Zenith Kernel Build Success**

👤 **Build User:** $KBUILD_BUILD_USER
💻 **Build Host:** $KBUILD_BUILD_HOST
📱 **Device:** $DEVICE
⚙️ **Variant:** $VARIANT
🕐 **Time:** $KBUILD_BUILD_TIMESTAMP" \
         https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null
    echo -e "\n✅ Upload successful!"
else
    echo -e "\n⚠️ Telegram Token/ChatID missing, skipping upload."
fi

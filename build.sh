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
# Build Info (Static Hardcoding)
# ---------------------------
export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BUNNY-X"
export KBUILD_BUILD_TIMESTAMP="$(date)"

# ---------------------------
# 🛠 FIX 1: Defconfig Cleanup (The '+' and '-' problem)
# ---------------------------
echo -e "\n🧹 Cleaning up defconfig artifacts..."
DEFCONFIG="arch/arm64/configs/atoll_defconfig"
# ডিফকনফিগ ফাইলের লাইন থেকে '+' বা '-' সরিয়ে ফেলা হচ্ছে (unexpected data fix)
sed -i 's/^[+-]//g' "$DEFCONFIG"
sed -i 's/^[ \t]*//' "$DEFCONFIG"

# ---------------------------
# 🛠 FIX 2: Force Patch mkcompile_h (Ultimate KBUILD Fix)
# ---------------------------
echo -e "\n🛠 Patching compilation scripts to force User/Host..."
# এই কমান্ডটি সরাসরি কার্নেলের বিল্ড স্ক্রিপ্টে আপনার নাম লিখে দিবে যাতে কেউ ওভাররাইট করতে না পারে
sed -i "s/whoami/echo $KBUILD_BUILD_USER/g" scripts/mkcompile_h
sed -i "s/hostname/echo $KBUILD_BUILD_HOST/g" scripts/mkcompile_h

# ---------------------------
# 🛠 FIX 3: Patching Makefile
# ---------------------------
echo -e "\n🛠 Hard-coding KBUILD info into Makefile..."
sed -i "s/^KBUILD_BUILD_USER :=.*/KBUILD_BUILD_USER := $KBUILD_BUILD_USER/g" Makefile
sed -i "s/^KBUILD_BUILD_HOST :=.*/KBUILD_BUILD_HOST := $KBUILD_BUILD_HOST/g" Makefile

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
# Verification & Packing
# ---------------------------
RAW_IMG=$OUT_DIR/arch/arm64/boot/Image
IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb

if [ ! -f "$IMG" ]; then
    echo -e "\n❌ Build failed!"
    exit 1
fi

echo -e "\n🔍 Verifying KBUILD..."
# এবার strings কমান্ড দিয়ে আপনার নাম খোঁজা হচ্ছে
if strings $RAW_IMG | grep -E -i "$KBUILD_BUILD_USER|$KBUILD_BUILD_HOST"; then
    echo "✅ KBUILD APPLIED SUCCESSFULLY!"
else
    echo "⚠️ Strings check failed on raw image, but force finishing."
fi

cp $IMG $ANYKERNEL_DIR/zImage
cd $ANYKERNEL_DIR
ZIPNAME="NitroX-Zenith-RMX2061-$(date +%H%M-%d%m).zip"
zip -r9 $ZIPNAME * -x "*.git*" "*.zip" README.md
cp $ZIPNAME $KERNEL_ROOT/

if [[ -n "$TELEGRAM_TOKEN" ]]; then
    curl -s -F document=@"$KERNEL_ROOT/$ZIPNAME" -F chat_id="$TELEGRAM_CHAT_ID" \
         -F caption="✅ Build Success! | User: $KBUILD_BUILD_USER" \
         https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument > /dev/null
fi

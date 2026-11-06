#!/bin/sh
# Compilation rapide du noyau hors pmbootstrap, pour itérer sur le DTS :
# même commit et même config que le paquet pmos/linux-lg-d855.
#
#   tools/build-kernel.sh              → arbre dans build/linux
#   tools/build-kernel.sh ~/src/linux  → arbre existant
#   DTB_ONLY=1 tools/build-kernel.sh   → seulement le DTB (quelques secondes)
#
# Prérequis : gcc-arm-linux-gnueabihf bc bison flex libssl-dev
# Résultat : out/zImage, out/<dtb>.dtb, out/zImage-dtb
set -eu

top=$(cd "$(dirname "$0")/.." && pwd)
src=${1:-$top/build/linux}
cross=${CROSS_COMPILE:-arm-linux-gnueabihf-}
dtb=qcom-msm8974pro-lge-d855

# Clone au bon commit et (ré)écrit la config si besoin
"$top/pmos/make-config.sh" "$src" >/dev/null

cp "$top/dts/$dtb.dts" "$src/arch/arm/boot/dts/qcom/"
grep -q "$dtb.dtb" "$src/arch/arm/boot/dts/qcom/Makefile" || \
	echo "dtb-\$(CONFIG_ARCH_QCOM) += $dtb.dtb" >> "$src/arch/arm/boot/dts/qcom/Makefile"

cd "$src"
targets="qcom/$dtb.dtb"
[ -n "${DTB_ONLY:-}" ] || targets="zImage $targets"
make ARCH=arm CROSS_COMPILE="$cross" -j"$(nproc)" $targets

mkdir -p "$top/out"
cp "arch/arm/boot/dts/qcom/$dtb.dtb" "$top/out/"
if [ -z "${DTB_ONLY:-}" ]; then
	cp arch/arm/boot/zImage "$top/out/"
	cat arch/arm/boot/zImage "arch/arm/boot/dts/qcom/$dtb.dtb" > "$top/out/zImage-dtb"
	echo "OK : $top/out/zImage-dtb"
else
	echo "OK : $top/out/$dtb.dtb"
fi

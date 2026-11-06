#!/bin/sh
# Construit zImage + DTB du G3 à partir du fork msm8974-mainline,
# avec le DTS de ce dépôt. Hors pmbootstrap, pour itérer vite.
#
# Prérequis (Debian/Ubuntu) :
#   apt install gcc-arm-linux-gnueabihf bc bison flex libssl-dev device-tree-compiler
#
# Usage : tools/build-kernel.sh [chemin/vers/linux]
set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd)
KSRC=${1:-$REPO/build/linux}
BRANCH=${BRANCH:-qcom-msm8974-6.16.y}
CROSS=${CROSS_COMPILE:-arm-linux-gnueabihf-}
DTS=qcom-msm8974pro-lge-d855

if [ ! -d "$KSRC/.git" ]; then
	git clone --depth 1 -b "$BRANCH" https://github.com/msm8974-mainline/linux "$KSRC"
fi

# Le DTS de ce dépôt fait foi : on le recopie à chaque build
cp "$REPO/dts/$DTS.dts" "$KSRC/arch/arm/boot/dts/qcom/"
grep -q "$DTS.dtb" "$KSRC/arch/arm/boot/dts/qcom/Makefile" || \
	sed -i "s/^\tqcom-msm8974pro-htc-m8.dtb \\\\$/&\n\t$DTS.dtb \\\\/" \
		"$KSRC/arch/arm/boot/dts/qcom/Makefile"

cd "$KSRC"
if [ ! -f .config ]; then
	# Config de base du fork ; pmOS ajoute ensuite ses fragments.
	make ARCH=arm CROSS_COMPILE="$CROSS" qcom_defconfig
	./scripts/config \
		-e USB_CONFIGFS -e USB_CONFIGFS_RNDIS -e USB_CONFIGFS_ECM \
		-e USB_CHIPIDEA -e USB_CHIPIDEA_UDC -e USB_CHIPIDEA_HOST \
		-e MMC_SDHCI_MSM -e BRCMFMAC -e BRCMFMAC_SDIO \
		-e RMI4_I2C -e RMI4_F12 -e CHARGER_BQ24190 -e BATTERY_MAX17040 \
		-e LEDS_LM3697 -e BACKLIGHT_LED -e REGULATOR_TPS65132 \
		-e DEVTMPFS -e DEVTMPFS_MOUNT
	make ARCH=arm CROSS_COMPILE="$CROSS" olddefconfig
fi

make ARCH=arm CROSS_COMPILE="$CROSS" -j"$(nproc)" zImage "qcom/$DTS.dtb"

mkdir -p "$REPO/out"
cp arch/arm/boot/zImage "$REPO/out/"
cp "arch/arm/boot/dts/qcom/$DTS.dtb" "$REPO/out/"
cat arch/arm/boot/zImage "arch/arm/boot/dts/qcom/$DTS.dtb" > "$REPO/out/zImage-dtb"
echo "OK : $REPO/out/zImage-dtb"

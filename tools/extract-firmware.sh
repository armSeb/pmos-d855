#!/bin/sh
# À lancer SUR LE TÉLÉPHONE (pmOS booté, rootfs sur microSD).
# Monte en lecture seule les partitions Android de l'eMMC et copie les
# firmwares utiles vers /lib/firmware. Rien n'est écrit sur l'eMMC.
#
# Usage : sudo sh extract-firmware.sh [destination]
set -eu

DEST=${1:-/lib/firmware}
MNT=$(mktemp -d)
BYNAME=/dev/disk/by-partlabel

part() {
	# Les noms de partitions G3 : modem, persist, system (à vérifier avec
	# ls /dev/disk/by-partlabel)
	[ -e "$BYNAME/$1" ] && echo "$BYNAME/$1" || { echo "partition $1 introuvable" >&2; return 1; }
}

mkdir -p "$DEST/qcom/msm8974/lge/d855" "$DEST/brcm"

# 1. Partition modem (vfat) : remoteprocs Qualcomm
if p=$(part modem); then
	mkdir -p "$MNT/modem"
	mount -o ro "$p" "$MNT/modem"
	for f in mba.mbn modem.mdt modem.b* adsp.mdt adsp.b* venus.mdt venus.b* \
		 wcnss.mdt wcnss.b*; do
		for src in "$MNT"/modem/image/$f; do
			[ -e "$src" ] && cp -v "$src" "$DEST/qcom/msm8974/lge/d855/"
		done
	done
	umount "$MNT/modem"
fi

# 2. Partition system : WiFi Broadcom, tactile, GPU
if p=$(part system); then
	mkdir -p "$MNT/system"
	mount -o ro "$p" "$MNT/system"
	S="$MNT/system"
	# Firmware WiFi BCM4339 (le nom exact varie selon la ROM)
	for f in "$S"/vendor/firmware/fw_bcmdhd.bin "$S"/etc/firmware/fw_bcmdhd.bin \
		 "$S"/vendor/firmware/fw_bcm4339*.bin; do
		[ -e "$f" ] && cp -v "$f" "$DEST/brcm/brcmfmac4339-sdio.bin" && break
	done
	# NVRAM WiFi : brcmfmac cherche brcmfmac4339-sdio.<compatible>.txt
	for f in "$S"/etc/wifi/bcmdhd.cal "$S"/vendor/firmware/bcmdhd.cal \
		 "$S"/etc/wifi/nvram*.txt; do
		[ -e "$f" ] && cp -v "$f" "$DEST/brcm/brcmfmac4339-sdio.lge,d855.txt" && break
	done
	# Microcode Adreno 330 (si absent de linux-firmware)
	for f in a330_pm4.fw a330_pfp.fw; do
		for src in "$S"/etc/firmware/$f "$S"/vendor/firmware/$f; do
			[ -e "$src" ] && cp -v "$src" "$DEST/qcom/" && break
		done
	done
	umount "$MNT/system"
fi

rmdir "$MNT"/* "$MNT" 2>/dev/null || true
echo
echo "Copié dans $DEST. Les fichiers .bXX doivent rester à côté de leur .mdt."
echo "Penser à ajouter firmware-name dans le DTS pour les remoteprocs, ex. :"
echo "  firmware-name = \"qcom/msm8974/lge/d855/modem.mdt\";"

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

D="$DEST/qcom/msm8974/lge/d855"
mkdir -p "$D"

# 1. Partition modem (vfat) : remoteprocs Qualcomm
if p=$(part modem); then
	mkdir -p "$MNT/modem"
	mount -o ro "$p" "$MNT/modem"
	for f in mba.mbn modem.mdt modem.b* adsp.mdt adsp.b* venus.mdt venus.b* \
		 wcnss.mdt wcnss.b*; do
		for src in "$MNT"/modem/image/$f; do
			[ -e "$src" ] && cp -v "$src" "$D/"
		done
	done
	umount "$MNT/modem"
fi

# 2. Partition system : NV WiFi (WCNSS/wcn36xx), GPU
if p=$(part system); then
	mkdir -p "$MNT/system"
	mount -o ro "$p" "$MNT/system"
	S="$MNT/system"
	# Calibration WiFi de la puce iris (lue par wcnss_ctrl, firmware-name du DTS)
	for f in "$S"/etc/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin \
		 "$S"/vendor/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin; do
		[ -e "$f" ] && cp -v "$f" "$D/" && break
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
[ -e "$D/wcnss.mdt" ] && [ -e "$D/WCNSS_qcom_wlan_nv.bin" ] \
	&& echo "WiFi/BT : OK (redémarrer, ou : echo start > /sys/class/remoteproc/remoteproc*/state)" \
	|| echo "WiFi/BT : wcnss.mdt ou WCNSS_qcom_wlan_nv.bin manquant (chercher : find / -name 'WCNSS*nv*')"

#!/bin/sh
# À lancer SUR LE TÉLÉPHONE (pmOS booté, rootfs sur microSD).
# Monte en lecture seule les partitions Android de l'eMMC et copie les
# firmwares utiles vers /lib/firmware. Rien n'est écrit sur l'eMMC.
#
# Usage : sudo sh extract-firmware.sh [destination]
# Lancé automatiquement au premier démarrage par extract-firmware-lg-d855.service
# (paquet device-lg-d855), tant que wcnss.mdt est absent.
set -eu

DEST=${1:-/lib/firmware}
MNT=$(mktemp -d)
BYNAME=/dev/disk/by-partlabel

part() {
	# Les noms de partitions G3 : modem, persist, system (à vérifier avec
	# ls /dev/disk/by-partlabel)
	[ -e "$BYNAME/$1" ] && echo "$BYNAME/$1" || { echo "partition $1 introuvable" >&2; return 1; }
}

# Au premier démarrage (service extract-firmware-lg-d855), udev peut ne pas
# avoir encore créé les liens by-partlabel : on les attend un peu.
i=0
while [ ! -e "$BYNAME/modem" ] && [ $i -lt 20 ]; do
	sleep 0.5; i=$((i + 1))
done

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

# 2. Microcode du GPU Adreno 330 (a330_pm4.fw, a330_pfp.fw), si absent de
#    linux-firmware : cherché dans system (system-as-root : system/system/…).
mkdir -p "$DEST/qcom"
if [ ! -e "$DEST/qcom/a330_pm4.fw" ] || [ ! -e "$DEST/qcom/a330_pfp.fw" ]; then
	if p=$(part system); then
		mkdir -p "$MNT/system"
		if mount -o ro "$p" "$MNT/system"; then
			for f in a330_pm4.fw a330_pfp.fw; do
				src=$(find "$MNT/system" -name "$f" -type f 2>/dev/null | head -n1)
				[ -n "$src" ] && cp -v "$src" "$DEST/qcom/$f"
			done
			umount "$MNT/system"
		fi
	fi
fi

# 3. Calibration WiFi de la puce iris (WCNSS_qcom_wlan_nv.bin, lue par
#    wcnss_ctrl : firmware-name du DTS). Son emplacement dépend de la ROM
#    (system/etc/firmware/wlan/prima, system/system/... en system-as-root,
#    vendor, persist) : on la cherche dans system puis persist.
nv=WCNSS_qcom_wlan_nv.bin
for pl in system persist; do
	[ -e "$D/$nv" ] && break
	p=$(part $pl) || continue
	mkdir -p "$MNT/$pl"
	mount -o ro "$p" "$MNT/$pl" || continue
	f=$(find "$MNT/$pl" -name "$nv" -type f 2>/dev/null | head -n1)
	[ -n "$f" ] || f=$(find "$MNT/$pl" -iname 'WCNSS*nv*.bin' -type f 2>/dev/null | head -n1)
	[ -n "$f" ] && cp -v "$f" "$D/$nv"
	umount "$MNT/$pl"
done

rmdir "$MNT"/* "$MNT" 2>/dev/null || true
echo
echo "Copié dans $DEST. Les fichiers .bXX doivent rester à côté de leur .mdt."
[ -e "$D/wcnss.mdt" ] && [ -e "$D/WCNSS_qcom_wlan_nv.bin" ] \
	&& echo "WiFi/BT : OK, redémarrer pour charger la calibration" \
	|| echo "WiFi/BT : wcnss.mdt ou $nv introuvable (ls /dev/disk/by-partlabel pour voir les partitions)"
[ -e "$DEST/qcom/a330_pm4.fw" ] && [ -e "$DEST/qcom/a330_pfp.fw" ] \
	&& echo "GPU : microcode a330 OK" \
	|| echo "GPU : a330_pm4.fw / a330_pfp.fw introuvables (paquet linux-firmware-qcom ?)"

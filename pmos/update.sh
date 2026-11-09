#!/bin/sh
# Met à jour le G3 sans réécrire la carte : reconstruit linux-lg-d855 et
# device-lg-d855, les installe sur le téléphone (pmbootstrap sideload), puis
# démarre le boot.img régénéré sur le téléphone via le fastboot de lk2nd.
#
#   pmos/update.sh                       # téléphone en 172.16.42.1 (USB)
#   HOST=192.168.1.42 pmos/update.sh     # autre adresse
#   NO_BOOT=1 pmos/update.sh             # installer seulement
#   BOOT_ONLY=1 pmos/update.sh           # ni build ni installation : récupère
#                                        # /boot/boot.img (régénéré par apk, ex.
#                                        # après apk add/upgrade) et le démarre
#   CMDLINE="... sdhci.debug_quirks2=0x4" pmos/update.sh
#                                        # remplace la ligne de commande
#
# Prérequis : pmbootstrap configuré (pmbootstrap init / install-sdcard.sh),
# SSH vers le téléphone (clé conseillée : sudo est demandé sur le téléphone),
# fastboot.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
host=${HOST:-172.16.42.1}
user=${USER_PMOS:-$(pmbootstrap config user)}
pkgs="linux-lg-d855 device-lg-d855"

die() { echo "ERREUR : $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

work=$(pmbootstrap config work) || die "pas de config pmbootstrap"
. "$here/common.sh"
aports="$work/cache_git/pmaports"

ping -c1 -W2 "$host" >/dev/null 2>&1 || die "$host ne répond pas (téléphone démarré, câble USB ? HOST=<ip wifi> sinon)"

if [ -z "${BOOT_ONLY:-}" ]; then
	step "Paquets"
	"$here/sync.sh" "$aports"
	release_chroots
	pmbootstrap checksum $pkgs
	pmbootstrap build $pkgs

	step "Installation sur $user@$host"
	pmbootstrap sideload --host "$host" --user "$user" --arch armv7 $pkgs
	release_chroots
fi

step "Récupération du boot.img régénéré"
mkdir -p "$top/out"
scp -q "$user@$host:/boot/boot.img" "$top/out/boot.img"
echo "  $top/out/boot.img ($(wc -c < "$top/out/boot.img") octets)"

if [ -n "${NO_BOOT:-}" ]; then
	echo "NO_BOOT : démarrer plus tard avec  fastboot boot $top/out/boot.img"
	exit 0
fi

step "Redémarrage vers lk2nd (fastboot)"
# lk2nd démarre l'Android flashé derrière lui ; « reboot bootloader » doit le
# garder en fastboot. Sinon : maintenir Vol− pendant le redémarrage.
ssh -t "$user@$host" sudo reboot bootloader || true
echo "  attente de fastboot (60 s ; si rien ne vient, maintenir Vol− au démarrage)…"
i=0
until fastboot devices 2>/dev/null | grep -q .; do
	i=$((i + 1))
	[ $i -lt 60 ] || die "pas de fastboot : redémarrer en maintenant Vol−, puis  fastboot boot $top/out/boot.img"
	sleep 1
done

step "Démarrage du nouveau noyau"
if [ -n "${CMDLINE:-}" ]; then
	fastboot --cmdline "$CMDLINE" boot "$top/out/boot.img"
else
	fastboot boot "$top/out/boot.img"
fi
echo
echo "Une fois démarré : ssh $user@$host"

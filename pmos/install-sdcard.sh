#!/bin/sh
# Installe postmarketOS (noyau mainline) pour le LG G3 D855 sur une carte
# microSD, de façon reproductible. Android reste intact sur l'eMMC.
#
#   pmos/install-sdcard.sh /dev/sdX            # UI par défaut : console
#   UI=phosh pmos/install-sdcard.sh /dev/sdX   # une fois l'affichage fonctionnel
#   APORTS=~/src/pmaports pmos/install-sdcard.sh /dev/sdX   # clone pmaports ailleurs
#
# Prérequis : pmbootstrap installé, `pmbootstrap init` lancé au moins une fois
# (n'importe quel appareil : il sert à créer la config et le clone pmaports) ;
# sgdisk (paquet gdisk), sfdisk/findmnt (util-linux), e2fsprogs.
#
# Démarrage : lk2nd est flashé dans la partition boot de l'eMMC ; le noyau et
# l'initramfs sont envoyés par USB (`pmbootstrap flasher boot`, équivalent de
# `fastboot boot`) et trouvent la racine sur la carte par son label pmOS_root.
#
# Étapes :
#   1. vérifie la carte (disque entier, pas monté, < 64 Go) et demande confirmation ;
#   2. met à jour le clone pmaports (origin/main doit exister) ;
#   3. copie les paquets du dépôt dans pmaports/device/testing (sync.sh) et calcule les sommes ;
#   4. sélectionne l'appareil et l'UI dans la config pmbootstrap ;
#   5. pmbootstrap install --sdcard : partitionne et remplit directement la carte
#      (table GPT, pmOS_boot + pmOS_root sur toute la carte) ;
#   6. vérifie sur la carte que pmOS_boot contient boot.img, vmlinuz et initramfs ;
#   7. affiche la commande de démarrage.
#
# Contrairement à la Maxwell, aucune conversion de table n'est nécessaire (le
# noyau lit la GPT, lk2nd ne lit pas la carte) : pmbootstrap écrit la carte
# lui-même.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dev=${1:-}
ui=${UI:-console}
device=lg-d855

die() { echo "ERREUR : $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

[ -n "$dev" ] || die "usage : $0 /dev/sdX   (variable UI=… facultative, défaut console)"
command -v pmbootstrap >/dev/null || die "pmbootstrap introuvable"
for t in lsblk blkid sfdisk sgdisk findmnt partx dd e2fsck resize2fs; do
	command -v "$t" >/dev/null || die "$t introuvable (util-linux, gdisk, coreutils, e2fsprogs)"
done

# --- 1. la carte -----------------------------------------------------------
step "Carte $dev"
[ -b "$dev" ] || die "$dev n'est pas un périphérique bloc"
[ "$(lsblk -dno TYPE "$dev")" = disk ] || die "$dev n'est pas un disque entier (donner /dev/sdX, pas /dev/sdX1)"
[ "$(lsblk -dno RM "$dev" | tr -d ' ')" = 1 ] || \
	echo "ATTENTION : $dev n'est pas signalé comme amovible (normal pour certains lecteurs USB)."
size=$(lsblk -dbno SIZE "$dev")
[ "$size" -le $((64 * 1024 * 1024 * 1024)) ] || die "$dev fait plus de 64 Go : ce n'est sans doute pas la carte"
if lsblk -no MOUNTPOINT "$dev" | grep -q .; then
	die "une partition de $dev est montée, la démonter d'abord"
fi
lsblk -o NAME,SIZE,MODEL,LABEL,FSTYPE "$dev"
printf 'Tout le contenu de %s sera EFFACÉ. Retaper le chemin pour confirmer : ' "$dev"
read -r answer
[ "$answer" = "$dev" ] || die "confirmation incorrecte, rien n'a été fait"

work=$(pmbootstrap config work 2>/dev/null) || die "pas de config pmbootstrap : lancer « pmbootstrap init » une fois"

# --- 2. pmaports ------------------------------------------------------------
step "Clone pmaports"
aports=${APORTS:-$work/cache_git/pmaports}
[ -d "$aports/.git" ] || die "$aports n'est pas un clone git (pmbootstrap init ?)"
git -C "$aports" fetch origin || die "git fetch du clone pmaports a échoué ($(git -C "$aports" remote get-url origin))"
git -C "$aports" rev-parse --verify -q origin/main >/dev/null || \
	die "origin/main absent dans $aports — branches distantes : $(git -C "$aports" branch -r | tr '\n' ' ')
     (pmbootstrap et pmaports désaccordés : mettre pmbootstrap à jour, ou recloner pmaports)"
if [ "$(git -C "$aports" rev-parse --abbrev-ref HEAD)" = main ]; then
	git -C "$aports" merge -q --ff-only origin/main || \
		echo "ATTENTION : avance rapide impossible dans $aports (modifications locales ?), on continue"
else
	echo "ATTENTION : $aports n'est pas sur main, pas de mise à jour"
fi

# --- 3. paquets -------------------------------------------------------------
step "Paquets $device"
"$here/sync.sh" "$aports"
pmbootstrap checksum "linux-$device" "device-$device"

# --- 4. config ----------------------------------------------------------------
step "Configuration : device=$device, ui=$ui"
pmbootstrap config device "$device"
pmbootstrap config ui "$ui"
# Changer d'UI peut changer de canal (systemd-edge pour phosh) : des chroots
# créés pour un autre canal font échouer l'installation. On les supprime
# (seulement les chroots : paquets construits et caches conservés).
#
# Un run interrompu peut laisser des montages que pmbootstrap ne suit plus
# (« Failed to shut down all chroots ») : on les démonte nous-mêmes, du plus
# profond au moins profond, avant de laisser pmbootstrap faire le ménage.
release_chroots() {
	pmbootstrap shutdown >/dev/null 2>&1 || true
	findmnt -rno TARGET | grep -F "$work/" | sort -r | while IFS= read -r m; do
		sudo umount "$m" 2>/dev/null || sudo umount -l "$m" 2>/dev/null || true
	done
	if findmnt -rno TARGET | grep -qF "$work/"; then
		echo "Montages restants sous $work :" >&2
		findmnt -rno TARGET | grep -F "$work/" >&2
		die "impossible de tout démonter (un shell est-il resté dans un chroot ?)"
	fi
}
release_chroots
pmbootstrap -y zap

# --- 5. installation sur la carte --------------------------------------------
step "Installation sur $dev (compilation du noyau au premier passage : long)"
if lsblk -no MOUNTPOINT "$dev" | grep -q .; then
	die "une partition de $dev a été montée entre-temps, la démonter puis relancer"
fi
pmbootstrap -y install --sdcard="$dev"
sync

# --- 6. vérification de la partition de boot --------------------------------
step "Carte : contenu de pmOS_boot"
if command -v partprobe >/dev/null; then sudo partprobe "$dev" 2>/dev/null || true; fi
sleep 2
bootp=$(lsblk -lnpo NAME,LABEL "$dev" | awk '$2 == "pmOS_boot" { print $1 }')
[ -n "$bootp" ] || die "aucune partition pmOS_boot sur $dev"
mnt=$(mktemp -d)
cleanup() { sudo umount "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true; }
trap cleanup EXIT
sudo mount -o ro "$bootp" "$mnt"
ok=1
for f in boot.img vmlinuz initramfs; do
	if [ -s "$mnt/$f" ]; then
		printf '  %-10s %s octets\n' "$f" "$(stat -c %s "$mnt/$f")"
	else
		echo "  $f MANQUANT"; ok=0
	fi
done
cleanup
trap - EXIT
[ "$ok" = 1 ] || die "pmOS_boot est incomplète"
sudo sfdisk -l "$dev" | sed -n '/^Device/,$p'

# --- 7. démarrage -----------------------------------------------------------
step "Carte prête"
cat <<'EOF'
1. Insérer la carte dans le G3, le démarrer en maintenant Vol− : lk2nd reste
   en fastboot (sinon il démarre l'Android flashé derrière lui).
   Vérifier côté PC : fastboot devices
2. Envoyer le noyau, sans rien flasher :
     pmbootstrap flasher boot
3. Réseau USB : ssh user@172.16.42.1
   En cas d'échec avant la racine : pmbootstrap flasher boot --cmdline pmos.debug-shell
   puis telnet 172.16.42.1
EOF

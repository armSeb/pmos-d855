#!/bin/sh
# Installe postmarketOS (noyau mainline) pour le LG G3 D855 sur une carte
# microSD, de façon reproductible. Android reste intact sur l'eMMC.
#
#   pmos/install-sdcard.sh /dev/sdX            # UI par défaut : console
#   UI=phosh pmos/install-sdcard.sh /dev/sdX   # une fois l'affichage fonctionnel
#   APORTS=~/src/pmaports pmos/install-sdcard.sh /dev/sdX   # clone pmaports ailleurs
#   REUSE_IMAGE=1 pmos/install-sdcard.sh /dev/sdX   # réécrire la dernière image, sans rien reconstruire
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
#   5. pmbootstrap install → image disque ;
#   6. image : vérifie que la partition de boot contient boot.img, vmlinuz et initramfs ;
#   7. écrit l'image sur la carte, agrandit la racine à toute la carte ;
#   8. affiche la commande de démarrage.
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

if [ -n "${REUSE_IMAGE:-}" ]; then
	step "Réutilisation de la dernière image construite (REUSE_IMAGE)"
else
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
	pmbootstrap -y zap

	# --- 5. installation dans une image --------------------------------------
	step "Installation dans une image (compilation du noyau au premier passage : long)"
	pmbootstrap install
fi
img="$work/chroot_native/home/pmos/rootfs/$device.img"
[ -f "$img" ] || die "image introuvable : $img"
img_size=$(stat -c %s "$img")
echo "  image : $img ($((img_size / 1024 / 1024)) Mio)"
[ "$img_size" -le "$size" ] || die "l'image ($img_size o) ne tient pas sur la carte ($size o) : carte plus grande, ou UI plus légère"

# --- 6. vérification de /boot dans l'image ---------------------------------
# La table GPT de pmbootstrap est conservée : le noyau Linux la lit, et lk2nd
# ne lit pas la carte (le noyau arrive par USB).
step "Image : contenu de la partition de boot"
p1_start=$(sudo sfdisk -d "$img" | sed -n 's/^[^ ]*1 : start= *\([0-9]*\),.*/\1/p')
[ -n "$p1_start" ] || die "début de p1 introuvable dans l'image"
mnt=$(mktemp -d)
cleanup() { sudo umount "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true; }
trap cleanup EXIT
sudo mount -o ro,loop,offset=$((p1_start * 512)) "$img" "$mnt"
echo "  p1 : $(findmnt -no FSTYPE "$mnt"), commence au secteur $p1_start"
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
[ "$ok" = 1 ] || die "la partition de boot est incomplète (carte non écrite)"

# --- 7. écriture sur la carte -----------------------------------------------
step "Écriture sur $dev"
if lsblk -no MOUNTPOINT "$dev" | grep -q .; then
	die "une partition de $dev a été montée entre-temps, la démonter puis relancer"
fi
sudo dd if="$img" of="$dev" bs=4M conv=fsync status=progress
sync
if command -v partprobe >/dev/null; then sudo partprobe "$dev" 2>/dev/null || true; fi

step "Agrandissement de la racine (p2) à toute la carte"
case "$dev" in
	*[0-9]) p2="${dev}p2" ;;	# /dev/mmcblk0 → /dev/mmcblk0p2
	*) p2="${dev}2" ;;
esac
# GPT : déplacer l'en-tête de secours en fin de carte avant d'agrandir
if [ "$(sudo blkid -p -o value -s PTTYPE "$dev")" = gpt ]; then
	sudo sgdisk -e "$dev" >/dev/null
fi
echo ', +' | sudo sfdisk -q --no-reread -N 2 "$dev"
if command -v partprobe >/dev/null; then sudo partprobe "$dev" 2>/dev/null || true; fi
sudo partx -u "$dev" 2>/dev/null || true
sleep 2
[ -b "$p2" ] || die "$p2 introuvable"
rc=0; sudo e2fsck -f -p "$p2" || rc=$?
[ "$rc" -le 1 ] || die "e2fsck sur $p2 a échoué (code $rc)"
sudo resize2fs "$p2"
sudo sfdisk -l "$dev" | sed -n '/^Device/,$p'

# --- 8. démarrage -----------------------------------------------------------
step "Carte prête"
cat <<'EOF'
1. Insérer la carte dans le G3, le démarrer : lk2nd attend en mode fastboot
   (écran noir possible). Vérifier côté PC : fastboot devices
2. Envoyer le noyau, sans rien flasher :
     pmbootstrap flasher boot
3. Réseau USB : ssh user@172.16.42.1
   En cas d'échec avant la racine : pmbootstrap flasher boot --cmdline pmos.debug-shell
   puis telnet 172.16.42.1
EOF

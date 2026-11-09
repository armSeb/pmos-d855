#!/bin/sh
# Installe postmarketOS (noyau mainline) pour le LG G3 D855 sur une carte
# microSD, de façon reproductible. Android reste intact sur l'eMMC.
#
#   pmos/install-sdcard.sh /dev/sdX              # UI par défaut : Phosh
#   UI=console pmos/install-sdcard.sh /dev/sdX   # sans interface graphique
#   EXTRA="gnome-maps loupe" pmos/install-sdcard.sh /dev/sdX   # paquets en plus
#   APORTS=~/src/pmaports pmos/install-sdcard.sh /dev/sdX   # clone pmaports ailleurs
#
# Prérequis : pmbootstrap installé, `pmbootstrap init` lancé au moins une fois
# (n'importe quel appareil : il sert à créer la config et le clone pmaports) ;
# sgdisk (paquet gdisk), sfdisk/findmnt (util-linux), e2fsprogs.
#
# Démarrage : lk2nd (patché pour lire la microSD, tools/build-lk2nd.sh) est
# flashé dans la partition boot de l'eMMC ; il lit extlinux/extlinux.conf sur
# pmOS_boot et démarre pmOS seul. Carte absente → Android derrière lk2nd.
#
# Étapes :
#   1. vérifie la carte (disque entier, pas monté, < 64 Go) et demande confirmation ;
#   2. met à jour le clone pmaports (origin/main doit exister) ;
#   3. copie les paquets du dépôt dans pmaports/device/testing (sync.sh) et calcule les sommes ;
#   4. sélectionne l'appareil, l'UI et les paquets en plus dans la config
#      pmbootstrap (les applications recommandées par l'UI sont installées) ;
#   5. pmbootstrap install --sdcard : partitionne et remplit directement la carte
#      (table MBR, deviceinfo_partition_type="msdos", lue par lk2nd ;
#      pmOS_boot en ext2 + pmOS_root sur toute la carte) ;
#   6. vérifie sur la carte que pmOS_boot contient boot.img, vmlinuz et initramfs ;
#   7. affiche la commande de démarrage.
#
# Aucune conversion de table après coup : le deviceinfo demande déjà une
# table MBR à pmbootstrap, qui écrit la carte lui-même.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dev=${1:-}
ui=${UI:-phosh}
extra=${EXTRA:-}
device=lg-d855

die() { echo "ERREUR : $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

[ -n "$dev" ] || die "usage : $0 /dev/sdX   (variables UI=… et EXTRA=… facultatives, UI par défaut phosh)"
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
. "$here/common.sh"

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
# Paquets en plus (liste séparée par des virgules pour pmbootstrap), ou aucun
if [ -n "$extra" ]; then
	pmbootstrap config extra_packages "$(echo "$extra" | tr -s ' ' ',')"
else
	pmbootstrap config extra_packages none
fi
# Changer d'UI peut changer de canal (systemd-edge pour phosh) : des chroots
# créés pour un autre canal font échouer l'installation. On les supprime
# (seulement les chroots : paquets construits et caches conservés).
release_chroots
pmbootstrap -y zap

# --- 5. installation sur la carte --------------------------------------------
step "Installation sur $dev (compilation du noyau au premier passage : long)"
if lsblk -no MOUNTPOINT "$dev" | grep -q .; then
	die "une partition de $dev a été montée entre-temps, la démonter puis relancer"
fi
pmbootstrap -y install --sdcard="$dev"
sync
release_chroots

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
for f in boot.img vmlinuz initramfs extlinux/extlinux.conf; do
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
1. Insérer la carte dans le G3 et le démarrer : lk2nd lit extlinux.conf sur
   la carte et démarre pmOS (Phosh) sans PC.
2. Réseau USB : ssh user@172.16.42.1 (ou le WiFi une fois configuré).
3. En cas d'échec avant la racine : démarrer en maintenant Vol− (lk2nd reste
   en fastboot), puis depuis le PC :
     pmbootstrap flasher boot --cmdline pmos.debug-shell
   puis telnet 172.16.42.1
EOF

#!/bin/sh
# Télécharge lk2nd-msm8974, le « bumpe » pour l'aboot LG et le flashe dans la
# partition boot du G3, avec sauvegarde et vérification par relecture.
#
#   tools/flash-lk2nd.sh                    # dernière release, mode Download (défaut)
#   METHOD=fastboot tools/flash-lk2nd.sh    # mise à jour quand lk2nd tourne déjà
#   METHOD=twrp tools/flash-lk2nd.sh        # depuis TWRP (adb)
#   LK2ND_VERSION=21.0 tools/flash-lk2nd.sh # release donnée (tag GitHub)
#   LK2ND_IMG=mon-lk2nd.img tools/flash-lk2nd.sh   # image locale (build perso)
#   NO_FLASH=1 tools/flash-lk2nd.sh         # télécharge + bumpe seulement
#
# Méthodes :
#   download : mode Download LG (éteint, Vol+ en branchant l'USB), via LGLAF
#              (github.com/Lekensteyn/lglaf, développé sur D855), cloné dans
#              build/lglaf. Prérequis : python3-usb (pyusb), python3-cryptography,
#              règle udev 1004:633e (le script l'indique si l'accès échoue).
#   fastboot : le fastboot de lk2nd. L'aboot LG stock du G3 n'a pas de fastboot,
#              donc seulement pour mettre à jour un lk2nd qui démarre déjà.
#   twrp     : adb depuis TWRP (Vol− + Power, voir README).
#
# Le bump ne fonctionne qu'avec un aboot vulnérable (celui qui accepte déjà
# TWRP et les ROM custom). Sinon : « Secure booting error » au démarrage, et
# retour à TWRP pour restaurer la sauvegarde faite ici.
set -eu

top=$(cd "$(dirname "$0")/.." && pwd)
out="$top/out/lk2nd"
method=${METHOD:-download}
lglaf_commit=7eeac45d2258df5e7eb20916781a62bc728b00d3

die() { echo "ERREUR : $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

mkdir -p "$out" "$top/backups"
command -v python3 >/dev/null || die "python3 introuvable"

# --- 1. image lk2nd -----------------------------------------------------------
if [ -n "${LK2ND_IMG:-}" ]; then
	step "Image locale $LK2ND_IMG"
	[ -f "$LK2ND_IMG" ] || die "$LK2ND_IMG introuvable"
	cp "$LK2ND_IMG" "$out/lk2nd-msm8974.img"
else
	command -v curl >/dev/null || die "curl introuvable"
	base=https://github.com/msm8916-mainline/lk2nd/releases
	if [ -n "${LK2ND_VERSION:-}" ]; then
		url="$base/download/$LK2ND_VERSION/lk2nd-msm8974.img"
	else
		url="$base/latest/download/lk2nd-msm8974.img"
	fi
	step "Téléchargement $url"
	curl -fL --retry 3 -o "$out/lk2nd-msm8974.img" "$url"
fi
img="$out/lk2nd-msm8974.img"

# --- 2. contrôles -------------------------------------------------------------
step "Contrôle de l'image"
[ "$(head -c 8 "$img")" = "ANDROID!" ] || die "$img n'est pas une image boot Android"
grep -aq 'lge,d855' "$img" || die "$img ne contient pas le G3 (lge,d855) : mauvaise cible lk2nd ?"
echo "  $(wc -c < "$img") octets, contient lge,d855"

# --- 3. bump ------------------------------------------------------------------
step "Bump LG"
python3 -I "$top/tools/lg-bump.py" "$img" "$out/lk2nd-msm8974-bumped.img"
bumped="$out/lk2nd-msm8974-bumped.img"
sha=$(sha256sum "$bumped" | cut -d' ' -f1)
size=$(wc -c < "$bumped")
echo "  sha256 $sha"

if [ -n "${NO_FLASH:-}" ]; then
	echo
	echo "Image prête : $bumped (NO_FLASH : rien n'a été écrit sur le téléphone)"
	exit 0
fi

# --- 4a. mise à jour depuis lk2nd ---------------------------------------------
if [ "$method" = fastboot ]; then
	command -v fastboot >/dev/null || die "fastboot introuvable"
	step "Mise à jour via le fastboot de lk2nd"
	fastboot devices | grep -q . || die "aucun appareil fastboot (lk2nd démarré ?)"
	printf 'Flasher %s dans la partition lk2nd ? [o/N] ' "$bumped"
	read -r ok; [ "$ok" = o ] || die "annulé"
	fastboot flash lk2nd "$bumped"
	fastboot reboot
	exit 0
fi

# --- 4b. mode Download (LGLAF) -------------------------------------------------
if [ "$method" = download ]; then
	lglaf="$top/build/lglaf"
	step "LGLAF"
	if [ ! -f "$lglaf/partitions.py" ]; then
		git init -q "$lglaf"
		git -C "$lglaf" remote add origin https://github.com/Lekensteyn/lglaf
		git -C "$lglaf" fetch -q --depth 1 origin "$lglaf_commit"
		git -C "$lglaf" checkout -q --detach FETCH_HEAD
	fi
	python3 -c 'import usb.core, cryptography' 2>/dev/null || \
		die "modules Python manquants : apt install python3-usb python3-cryptography (ou pip install pyusb cryptography)"
	laf() { (cd "$lglaf" && python3 "$@"); }

	step "Téléphone en mode Download"
	if command -v lsusb >/dev/null && ! lsusb -d 1004: >/dev/null 2>&1; then
		die "aucun appareil LG en USB. Éteindre (batterie), maintenir Vol+ et brancher l'USB, attendre « Firmware Update »"
	fi
	laf partitions.py --list boot || die "LGLAF ne parle pas au téléphone. Accès USB : sudo cp $lglaf/rules.d/42-usb-lglaf.rules /etc/udev/rules.d/ && sudo udevadm control --reload, puis rebrancher"

	step "Sauvegarde de la partition boot actuelle"
	bak="$top/backups/boot-$(date +%Y%m%d-%H%M%S).img"
	laf partitions.py --dump "$bak" boot
	[ -s "$bak" ] || die "sauvegarde vide, abandon"
	echo "  $bak ($(wc -c < "$bak") octets)"

	printf '\nÉcrire lk2nd bumpé dans la partition boot ? [o/N] '
	read -r ok; [ "$ok" = o ] || die "annulé (rien n'a été écrit)"

	step "Écriture"
	laf partitions.py --restore "$bumped" boot

	step "Vérification (relecture)"
	check="$out/boot-readback.img"
	laf partitions.py --dump "$check" boot
	got=$(head -c "$size" "$check" | sha256sum | cut -d' ' -f1)
	rm -f "$check"
	if [ "$got" != "$sha" ]; then
		echo "ÉCHEC : la partition ne correspond pas à l'image." >&2
		echo "Restaurer : (cd $lglaf && python3 partitions.py --restore $bak boot)" >&2
		exit 1
	fi
	echo "  OK, contenu identique"

	printf '\nRedémarrer le téléphone maintenant ? [o/N] '
	read -r ok
	if [ "$ok" = o ]; then laf lglaf.py -c '!CTRL RSET' >/dev/null 2>&1 || true; fi
	cat <<EOF

lk2nd est flashé. Sauvegarde de l'ancienne partition boot : $bak

  fastboot devices        # lk2nd doit répondre (écran noir possible)

Si « Secure booting error » : mode Download (éteint, Vol+ + USB), puis
  (cd $lglaf && python3 partitions.py --restore $bak boot)
EOF
	exit 0
fi

[ "$method" = twrp ] || die "METHOD inconnue : $method (download, fastboot ou twrp)"

# --- 4c. premier flash depuis TWRP --------------------------------------------
command -v adb >/dev/null || die "adb introuvable"
step "Téléphone"
state=$(adb get-state 2>/dev/null || true)
[ "$state" = recovery ] || die "pas de téléphone en recovery (état adb : ${state:-aucun}) — démarrer TWRP"
model=$(adb shell getprop ro.product.device | tr -d '\r')
echo "  appareil : $model"
case "$model" in
	*d855*|g3) ;;
	*) printf 'ATTENTION : ce n'"'"'est pas reconnu comme un D855. Continuer ? [o/N] '
	   read -r ok; [ "$ok" = o ] || die "annulé" ;;
esac
boot=$(adb shell 'for p in /dev/block/bootdevice/by-name/boot /dev/block/platform/msm_sdcc.1/by-name/boot; do [ -e "$p" ] && readlink -f "$p" && break; done' | tr -d '\r')
[ -n "$boot" ] || die "partition boot introuvable sur le téléphone"
echo "  partition boot : $boot"

step "Sauvegarde de la partition boot actuelle"
bak="$top/backups/boot-$(date +%Y%m%d-%H%M%S).img"
adb shell "dd if=$boot of=/tmp/boot-backup.img bs=4096" >/dev/null 2>&1
adb pull /tmp/boot-backup.img "$bak" >/dev/null
adb shell rm -f /tmp/boot-backup.img
[ -s "$bak" ] || die "sauvegarde vide, abandon"
echo "  $bak ($(wc -c < "$bak") octets)"

printf '\nÉcrire lk2nd bumpé dans %s ? [o/N] ' "$boot"
read -r ok; [ "$ok" = o ] || die "annulé (rien n'a été écrit)"

step "Écriture"
adb push "$bumped" /tmp/lk2nd.img >/dev/null
adb shell "dd if=/tmp/lk2nd.img of=$boot bs=4096 && sync"

step "Vérification (relecture)"
got=$(adb shell "dd if=$boot bs=1 count=$size 2>/dev/null | sha256sum" | cut -d' ' -f1 | tr -d '\r')
adb shell rm -f /tmp/lk2nd.img
if [ "$got" != "$sha" ]; then
	echo "ÉCHEC : la partition ne correspond pas à l'image (lu $got)." >&2
	echo "Restaurer : adb push $bak /tmp/b.img && adb shell dd if=/tmp/b.img of=$boot" >&2
	exit 1
fi
echo "  OK, contenu identique"

cat <<EOF

lk2nd est flashé. Sauvegarde de l'ancienne partition boot : $bak

  adb reboot
  fastboot devices        # lk2nd doit répondre (écran noir possible)

Si « Secure booting error » : retour TWRP (Vol− + Power) puis
  adb push $bak /tmp/b.img && adb shell dd if=/tmp/b.img of=$boot
EOF

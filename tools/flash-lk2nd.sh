#!/bin/sh
# Télécharge lk2nd-msm8974, le « bumpe » pour l'aboot LG et le flashe dans la
# partition boot du G3 depuis TWRP (adb), avec sauvegarde et vérification.
#
#   tools/flash-lk2nd.sh                    # dernière release, flash via TWRP
#   LK2ND_VERSION=21.0 tools/flash-lk2nd.sh # release donnée (tag GitHub)
#   LK2ND_IMG=mon-lk2nd.img tools/flash-lk2nd.sh   # image locale (build perso)
#   NO_FLASH=1 tools/flash-lk2nd.sh         # télécharge + bumpe seulement
#   METHOD=fastboot tools/flash-lk2nd.sh    # mise à jour quand lk2nd tourne déjà
#
# Prérequis : curl, python3, adb (et fastboot pour METHOD=fastboot).
# Le téléphone doit être dans TWRP (Vol− + Power, voir README), sauf en
# METHOD=fastboot. Le G3 stock n'a pas de fastboot : avant lk2nd, seul TWRP
# permet d'écrire la partition boot.
#
# Le bump ne fonctionne qu'avec un aboot vulnérable (celui qui accepte déjà
# TWRP et les ROM custom). Sinon : « Secure booting error » au démarrage, et
# retour à TWRP pour restaurer la sauvegarde faite ici.
set -eu

top=$(cd "$(dirname "$0")/.." && pwd)
out="$top/out/lk2nd"
method=${METHOD:-twrp}

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

# --- 4b. premier flash depuis TWRP --------------------------------------------
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

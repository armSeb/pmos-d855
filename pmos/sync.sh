#!/bin/sh
# Recopie dans les paquets pmaports les fichiers maintenus ailleurs dans le dépôt,
# puis (optionnel) les installe dans un checkout pmaports :
#   pmos/sync.sh                       → met à jour pmos/ seulement
#   pmos/sync.sh ~/.local/var/pmbootstrap/cache_git/pmaports
#                                      → copie aussi dans pmaports/device/testing/
#
# pmaports contient déjà un port downstream (device-lg-d855 + linux-lg-d855,
# noyau 3.4) : on le retire du checkout, sinon pmbootstrap voit deux paquets
# du même nom.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
k="$here/linux-lg-d855"

cp "$top/dts/qcom-msm8974pro-lge-d855.dts" "$k/"
cp "$top/tools/devmem32/devmem32.c" "$top/tools/mdp-dump.sh" \
   "$top/tools/extract-firmware.sh" "$top/tools/mmcc-trace.sh" "$here/device-lg-d855/"
[ -f "$k/config-lg-d855.armv7" ] || {
	echo "manque $k/config-lg-d855.armv7 (lancer pmos/make-config.sh)" >&2; exit 1; }

if [ $# -ge 1 ]; then
	aports=$1
	dst="$aports/device/testing"
	[ -d "$dst" ] || { echo "$dst introuvable (chemin pmaports ?)" >&2; exit 1; }
	for old in $(find "$aports/device" -mindepth 2 -maxdepth 2 -type d \
			\( -name linux-lg-d855 -o -name device-lg-d855 \)); do
		echo "retrait de ${old#"$aports"/}"
		rm -rf "$old"
	done
	cp -r "$k" "$here/device-lg-d855" "$dst/"
	rm -f "$dst/linux-lg-d855/lg-d855.fragment"
	echo "copié dans $dst — ensuite : pmbootstrap checksum linux-lg-d855 device-lg-d855"
fi

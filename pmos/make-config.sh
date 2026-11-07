#!/bin/sh
# Régénère pmos/linux-lg-d855/config-lg-d855.armv7 :
#   msm8974_defconfig (du fork, au commit épinglé dans l'APKBUILD, patches du
#   paquet appliqués) + lg-d855.fragment
#
#   pmos/make-config.sh              → clone le fork dans build/linux si besoin
#   pmos/make-config.sh ~/src/linux  → utilise un arbre existant (même commit !)
#
# Prérequis : git, make, gcc (hôte), flex, bison ; pas besoin du compilateur ARM.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
k="$here/linux-lg-d855"

commit=$(sed -n 's/^_commit="\([0-9a-f]*\)"/\1/p' "$k/APKBUILD")
[ -n "$commit" ] || { echo "_commit introuvable dans $k/APKBUILD" >&2; exit 1; }
src=${1:-$top/build/linux}

if [ ! -d "$src/.git" ]; then
	git init -q "$src"
	git -C "$src" remote add origin https://github.com/msm8974-mainline/linux
fi
if [ "$(git -C "$src" rev-parse HEAD 2>/dev/null || true)" != "$commit" ]; then
	git -C "$src" fetch -q --depth 1 origin "$commit"
	git -C "$src" checkout -q --detach FETCH_HEAD
fi

# Patches du paquet (certains ajoutent des options Kconfig) : appliqués dans
# l'arbre de travail s'ils ne le sont pas déjà
for p in "$k"/*.patch; do
	[ -e "$p" ] || continue
	if git -C "$src" apply --check "$p" 2>/dev/null; then
		git -C "$src" apply "$p"
	elif git -C "$src" apply -R --check "$p" 2>/dev/null; then
		:	# déjà appliqué
	else
		echo "le patch $(basename "$p") ne s'applique pas sur $src" >&2; exit 1
	fi
done

cd "$src"
ARCH=arm ./scripts/kconfig/merge_config.sh -m \
	arch/arm/configs/msm8974_defconfig "$k/lg-d855.fragment"
make ARCH=arm olddefconfig >/dev/null

# Vérifie que chaque option du fragment a bien été retenue
grep -E '^(CONFIG_[A-Z0-9_]+)=' "$k/lg-d855.fragment" | while IFS= read -r line; do
	opt=${line%%=*}
	got=$(grep -E "^$opt=|^# $opt is not set" .config || echo "$opt absent")
	if [ "$line" != "$got" ] && ! { [ "${line#*=}" = n ] && [ "$got" = "# $opt is not set" ]; }; then
		echo "  différence : voulu $line, obtenu $got"
	fi
done

cp .config "$k/config-lg-d855.armv7"
echo "écrit : $k/config-lg-d855.armv7 (commit $commit)"

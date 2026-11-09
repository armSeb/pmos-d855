#!/bin/sh
# Construit lk2nd-msm8974 avec les patchs de tools/lk2nd/ (carte SD activée
# pour le D855 : lk2nd trouve alors /boot/extlinux/extlinux.conf de pmOS sur
# la microSD, sans rien écrire dans l'eMMC à chaque mise à jour du noyau).
#
#   tools/build-lk2nd.sh                    → out/lk2nd-msm8974.img
#   LK2ND_IMG=out/lk2nd-msm8974.img tools/flash-lk2nd.sh   (bump + flash)
#
# Tester avant de flasher : depuis le fastboot de lk2nd (Vol−),
#   fastboot boot out/lk2nd-msm8974.img
#
# Dépendances : git, make, arm-none-eabi-gcc (Debian : gcc-arm-none-eabi,
# Arch : arm-none-eabi-gcc), dtc, python3.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
src="$top/build/lk2nd"
repo=https://github.com/msm8916-mainline/lk2nd
commit=cf45aefd22d744b2bf9b39455afae697ce430063

command -v arm-none-eabi-gcc >/dev/null || { echo "arm-none-eabi-gcc manquant" >&2; exit 1; }

if [ ! -d "$src/.git" ]; then
	git clone --filter=blob:none "$repo" "$src"
fi
cd "$src"
git fetch -q origin "$commit" 2>/dev/null || git fetch -q origin
git checkout -q -f "$commit"
git clean -qfdx
for p in "$here"/lk2nd/*.patch; do
	echo "patch : $(basename "$p")"
	git apply "$p"
done

make TOOLCHAIN_PREFIX=arm-none-eabi- lk2nd-msm8974 -j"$(nproc)" >/dev/null
mkdir -p "$top/out"
cp build-lk2nd-msm8974/lk2nd.img "$top/out/lk2nd-msm8974.img"
echo "→ $top/out/lk2nd-msm8974.img"

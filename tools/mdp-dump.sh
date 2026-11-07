#!/bin/sh
# À lancer SUR LE TÉLÉPHONE (shell de debug pmOS ou SSH, en root), juste
# après le démarrage, écran encore allumé par le bootloader.
#
# Lit en lecture seule les registres du MDP5 (MSM8974) pour retrouver le
# framebuffer que le bootloader LG affiche : adresse, taille, stride, format.
# Ces valeurs servent à déclarer un simple-framebuffer dans le DTS.
#
# Prérequis : busybox avec l'applet devmem (initramfs pmOS), /dev/mem, et le
# noyau démarré avec clk_ignore_unused (sinon les horloges du MDP sont
# coupées et les lectures renvoient 0 ou bloquent).
#
# Usage : sh mdp-dump.sh

dm() { busybox devmem "$1" 32 2>/dev/null || echo "?"; }
hex2dec() { printf '%d' "$1" 2>/dev/null || echo 0; }

MDP=0xfd900100	# reg "mdp_phys" du nœud mdp dans qcom-msm8974.dtsi

# Offsets des pipes (mdp5_cfg.c, msm8x74v2_config)
pipes="VIG0:0x1100 VIG1:0x1500 VIG2:0x1900 RGB0:0x1d00 RGB1:0x2100 RGB2:0x2500 DMA0:0x2900 DMA1:0x2d00"

echo "MDP5 HW_VERSION : $(dm 0xfd900000)"
echo
printf '%-5s %-11s %-11s %-11s %-11s %-11s %-11s %s\n' pipe SRC0_ADDR IMG_SIZE SRC_SIZE OUT_SIZE OUT_XY STRIDE_A SRC_FORMAT
for p in $pipes; do
	name=${p%%:*}
	off=${p#*:}
	base=$((MDP + off))
	addr=$(dm $((base + 0x14)))
	printf '%-5s %-11s %-11s %-11s %-11s %-11s %-11s %s\n' "$name" "$addr" \
		"$(dm $((base + 0x04)))" "$(dm $((base + 0x00)))" "$(dm $((base + 0x0c)))" \
		"$(dm $((base + 0x10)))" "$(dm $((base + 0x24)))" \
		"$(dm $((base + 0x30)))"
done

echo
echo "Lecture : IMG_SIZE (image source entière), SRC_SIZE, OUT_SIZE = 0xHHHHWWWW (hauteur << 16 | largeur),"
echo "STRIDE_A bits 0-15 = octets par ligne, SRC0_ADDR = adresse physique."
echo "Les pipes actives ont un SRC0_ADDR non nul. En DSI couplé, on attend"
echo "deux pipes de 720 de large, dont les adresses diffèrent de 720 * octets/pixel."

# Résumé pour la première pipe active
for p in $pipes; do
	base=$((MDP + ${p#*:}))
	addr=$(dm $((base + 0x14)))
	[ "$(hex2dec "$addr")" -ne 0 ] || continue
	size=$(hex2dec "$(dm $((base + 0x04)))")
	stride=$(( $(hex2dec "$(dm $((base + 0x24)))") & 0xffff ))
	w=$((size & 0xffff)); h=$((size >> 16))
	bpp=0; [ "$w" -gt 0 ] && bpp=$((stride / w))
	echo
	echo "Première pipe active : ${p%%:*} à $addr, image source ${w}x${h}, stride $stride ($bpp octets/pixel)"
	break
done

#!/bin/sh
# Relève brute des registres de l'affichage (MDSS) de la MSM8974, tels que le
# bootloader LG les a programmés pour le panel en DSI couplé (« split
# display ») : MDP top (SPLIT_DPL), CTL, pipes, mélangeurs (LM), interfaces
# (INTF), DSI0/DSI1 (contrôleur, PLL, PHY) et horloges MDSS.
# Sert de référence pour le support du split display dans MDP5.
#
# À lancer en root, l'affichage hérité du bootloader encore actif (simpledrm,
# pas de pilote msm d'affichage) : sinon les lectures peuvent figer le SoC.
#
# Usage : sudo mdss-snapshot [fichier]   (défaut /root/mdss-snapshot.txt)
set -eu

out=${1:-/root/mdss-snapshot.txt}
[ "$(id -u)" = 0 ] || { echo "à lancer en root" >&2; exit 1; }
command -v devmem32 >/dev/null || { echo "devmem32 manquant" >&2; exit 1; }

# bloc NOM ADRESSE NOMBRE_DE_MOTS
bloc() {
	printf '\n### %s @ %s (%d mots)\n' "$1" "$2" "$3"
	devmem32 "$2" "$3" --dump
}

MDP=0xfd900100		# mdp_phys (registres MDP5 relatifs à cette base)
{
	echo "# mdss-snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ) $(uname -r)"
	bloc MDSS_TOP        0xfd900000 64
	bloc MDP_TOP         $MDP 256			# HW_VERSION, DISP_INTF_SEL, SPLIT_DPL_* (0x2f4, 0x2f8, 0x3f0)
	bloc CTL0-4          $((MDP + 0x500)) 320	# 5 x 0x100
	bloc PIPES           $((MDP + 0x1100)) 2048	# VIG0-2, RGB0-2, DMA0-1 (0x400 chacune)
	bloc LM0-2           $((MDP + 0x3100)) 768	# 3 x 0x400
	bloc INTF0-3         $((MDP + 0x12400)) 512	# eDP, DSI1, DSI2, HDMI (0x200 chacune)
	bloc DSI0            0xfd922800 384		# ctrl 0x800, PLL 0xa00, PHY 0xb00, régulateur 0xd80
	bloc DSI1            0xfd922e00 384
	bloc MMCC_MDSS       0xfd8c2000 256		# RCG/CBCR MDSS : mdp, byte0/1, pclk0/1, esc0/1
} > "$out" 2>&1
sync
echo "→ $out ($(wc -l < "$out") lignes)"

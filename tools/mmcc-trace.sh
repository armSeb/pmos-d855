#!/bin/sh
# Charge mmcc-msm8974 (bloqué au démarrage) en traçant chaque accès regmap,
# pour trouver l'écriture qui casse l'affichage hérité du bootloader.
# L'écran va probablement passer au bleu : lancer depuis SSH (WiFi).
#
# Usage : sudo mmcc-trace [dossier]     (défaut /root/mmcc-trace)
# Résultat : regmap.txt (trace), dmesg.txt, mdp-avant.txt, mdp-apres.txt
set -eu

out=${1:-/root/mmcc-trace}
T=/sys/kernel/tracing

[ "$(id -u)" = 0 ] || { echo "à lancer en root" >&2; exit 1; }
if grep -q '^mmcc_msm8974 ' /proc/modules; then
	echo "mmcc-msm8974 est déjà chargé : redémarrer d'abord" >&2
	exit 1
fi
mkdir -p "$out"
[ -d "$T/events" ] || mount -t tracefs tracefs "$T"

command -v mdp-dump >/dev/null && mdp-dump > "$out/mdp-avant.txt" 2>&1 || true
dmesg -c > /dev/null 2>&1 || true

echo 0 > "$T/tracing_on"
echo > "$T/trace"
echo 32768 > "$T/buffer_size_kb"
echo 1 > "$T/events/regmap/regmap_reg_write/enable"
echo 1 > "$T/events/regmap/regmap_reg_read/enable"
echo 1 > "$T/tracing_on"

echo "chargement de mmcc-msm8974…"
modprobe mmcc-msm8974 dyndbg=+p || echo "modprobe a échoué ($?)"
sleep 2

echo 0 > "$T/tracing_on"
echo 0 > "$T/events/regmap/regmap_reg_write/enable"
echo 0 > "$T/events/regmap/regmap_reg_read/enable"
grep -v '^#' "$T/trace" > "$out/regmap.txt"
dmesg > "$out/dmesg.txt" 2>&1 || true
echo "écritures : $(grep -c regmap_reg_write "$out/regmap.txt") ; lectures : $(grep -c regmap_reg_read "$out/regmap.txt")"
tar -C "$(dirname "$out")" -czf "$out.tar.gz" "$(basename "$out")"
sync
echo "→ $out.tar.gz"

# En dernier : si le domaine d'alimentation MDSS a été coupé, lire ses
# registres peut figer le téléphone (la trace est déjà sauvegardée).
if command -v mdp-dump >/dev/null; then
	echo "lecture des registres MDP après chargement…"
	mdp-dump > "$out/mdp-apres.txt" 2>&1 || true
	tar -C "$(dirname "$out")" -czf "$out.tar.gz" "$(basename "$out")"
	sync
fi

# Fonctions partagées par les scripts de pmos/ (à sourcer, après avoir défini
# die() et la variable work = dossier de travail pmbootstrap).

# Un run pmbootstrap interrompu, ou « install --sdcard », peut laisser des
# montages que pmbootstrap ne suit plus : il échoue ensuite au démontage
# (« umount: …/sys/devices: non monté », « Failed to shut down all chroots »).
# On démonte nous-mêmes tout ce qui reste sous le dossier de travail, du plus
# profond au moins profond.
release_chroots() {
	pmbootstrap shutdown >/dev/null 2>&1 || true
	findmnt -rno TARGET | grep -F "$work/" | sort -r | while IFS= read -r m; do
		sudo umount "$m" 2>/dev/null || sudo umount -l "$m" 2>/dev/null || true
	done
	if findmnt -rno TARGET | grep -qF "$work/"; then
		echo "Montages restants sous $work :" >&2
		findmnt -rno TARGET | grep -F "$work/" >&2
		die "impossible de tout démonter (un shell est-il resté dans un chroot ?)"
	fi
}

# Adreno 330 (freedreno a3xx) : le moteur de rendu GL de GTK4 (ngl) bloque
# le GPU (« hangcheck detected gpu lockup », gnome-control-center), même à
# fréquence GPU fixe. Rendu logiciel cairo pour GTK4 en attendant un
# correctif côté Mesa/GTK ; même principe que soc-qcom-msm8953 (a506).
export GSK_RENDERER=cairo

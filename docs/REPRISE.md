# Point de reprise — affichage natif (MDP5/DSI)

Note de passation entre sessions de travail. Le README reste la référence
pour l'état général ; ce fichier décrit le chantier en cours.

## Ce qui marche
- Démarrage autonome : lk2nd patché (carte SD, `tools/build-lk2nd.sh`) →
  extlinux sur pmOS_boot (ext2, table MBR).
- Mise à jour : `NO_BOOT=1 HOST=<ip wifi> pmos/update.sh`, puis `sudo reboot`.
- WiFi/BT (wcn36xx), Phosh en rendu logiciel (simpledrm), GPU Adreno 330
  (FD330, GLES 3.0) avec `msm allow_vram_carveout=1 vram=128m`.
- mmcc ne casse plus l'affichage (patch 0004).
- msm se lie en split display : DSI0 + DSI1 couplés, CTL0/LM0/INTF1 +
  CTL1/LM1/INTF2 (patch 0006). Registres MDP, timings INTF, pipes et PLL DSI
  (VCO 362,8 MHz) identiques au bootloader.
- Rétroéclairage LM3697 OK avec OVP 24 V (patch 0008, registre 0x1a = 0x02).

## Le problème en cours
Écran noir en affichage natif : rétroéclairage allumé, rémanence de l'ancienne
console, quelques traits verticaux colorés à gauche. Le panel n'est pas
initialisé : power mode relu à 0x00 (attendu 0x9c), DSI0 renvoie -61.

Hypothèse testée par le patch 0009 (pkgrel 24) : le bootloader et le pilote downstream écrivent
`CMD_DMA_CTRL = 0x94000000` (BROADCAST_EN) sur les deux contrôleurs
(`qcom,mdss-dsi-panel-broadcast-mode = <1>` dans le DT LG) ; mainline ne le
fait pas. La relecture de debug passe par DSI1 seul.
Premier essai (pkgrel 23) : écritures sans erreur, mais la lecture expirait
(« Set max pkt size failed, -110 ») car DSI0 n'était pas préparé pour les
lectures alors que le déclenchement part sur les deux hôtes ; corrigé en
pkgrel 24.

Test :
```
dmesg | grep -i -E "power mode|lgd|dsi|panel" | grep -v "dependency cycle"
```

pkgrel 24 : la lecture marche (« power mode: 0x00 (0) ») mais le panel répond
0x00, avec `dsi_err_worker: status=6` (erreurs PHY lane 0 + FIFO).
Constat dans le DT LG downstream : la séquence d'init ne contient ni 0x11
(sleep out) ni 0x29 (display on) ; ordre d'alim : vdd, ENP, reset <1 5>,
puis ENN, avec reprogrammation I2C du TPS65132 après chaque enable ; reset
fait après l'init du DSI en LP11 (lp11-init).

pkgrel 25 : paramètre `keep_init` du pilote panel
(`options panel-lge-g3-lgd-sic keep_init=1`) : garde le panel tel que le
bootloader l'a laissé, sans reset ni init. Si l'image s'affiche, la chaîne
vidéo est bonne et seule l'init du panel est en cause.

keep_init testé : écran toujours noir, power mode 0x00. Les registres DSI
(contrôleur, PHY, PLL), horloges et MDP natifs sont identiques à ceux du
bootloader (snapshots comparés) à part LN_CFG_4/TIMING_CTRL_5-6 déjà testés.
Piste : le DT LG alimente le panneau par `vdd-supply = <&pm8941_l10>` (1,8 V,
seul consommateur de L10) en plus de L12 ; notre DTS n'en faisait rien.
pkgrel 26 : L10 fixé à 1,8 V et toujours allumé.

pkgrel 26 (L10) : aucun changement. pkgrel 27 : en sync, toutes les
lectures par DSI1 renvoient 0x00 (réponse DCS courte valide, ECC correct),
y compris l'ID 0xda-0xdc, avant reset, après reset et après init : la
relecture par DSI1 ne renseigne pas sur l'état du panneau.
pkgrel 28 : essai sans `qcom,sync-dual-dsi` (commandes envoyées et relues
séparément sur chaque lien, broadcast inactif).

pkgrel 28-29 (sans sync) : DSI0 ne répond à aucune lecture (RDBK vide,
ACK_ERR_STATUS 0x10000000, erreurs PHY lane 0), DSI1 répond toujours 0x00.
Les relectures ne disent rien de l'état du panneau ; elles sont désormais
désactivées par défaut (`debug_reads=1` pour les remettre).
pkgrel 30 : retour au sync/broadcast et séquence d'allumage calquée sur LG :
reset maintenu, vrai cycle d'alimentation du TPS65132 au premier prepare,
VSP, 5 ms, reset relâché, VSN, tensions reprogrammées après chaque enable ;
plus de soft reset DCS en tête d'init ; 120 ms après le sleep out.

pkgrel 30 : toujours noir (fantôme). Vérifié en mode msm : lcd-vpos/vneg
activés à 5,5 V, L10/L12 à 1,8 V, GPIO 56/91/100 à 1, reset PM8941 GPIO19
à 1 (relâché). L10 était en mode « idle » (LPM, charge 0) : pkgrel 31 lui
déclare la charge LG de 100 mA (HPM).

TPS65132 relu en mode msm (`i2cget -f -y 2 0x3e`, avant pkgrel 31) :
0x00 = 0x0f (VPOS 4,0 + 15 × 0,1 = 5,5 V), 0x01 = 0x0f (VNEG −5,5 V),
0x03 = 0x43 (décharges actives VPOS/VNEG + bit 6 APPS = 1). Le pilote mainline
n'écrit jamais APPS : 0x43 vient de LG (EEPROM ou bootloader).
ATTENTION : 0x0f est la valeur écrite par Linux, pas celle du bootloader. Au
démarrage, `lcd-vpos/lcd-vneg: Bringing 5000000uV into 5500000-5500000uV` :
le bootloader laisse ±5,0 V (0x0a) et le cœur regulator force ±5,5 V dès la
sonde du TPS65132 (~25,2 s), sans aucun consommateur.

pkgrel 31 (L10 en HPM, opmode « normal » confirmé) : toujours noir.
Test `clk_ignore_unused pd_ignore_unused regulator_ignore_unused` +
`keep_init=1` : l'écran devient noir vers 25-26 s, AVANT le bind de msm
(26,5 s) et avant `keeping the bootloader panel state` (29,6 s). Ce n'est
donc ni msm ni le GDSC. Événements dans cette fenêtre : passage VSP/VSN de
5,0 à 5,5 V (25,19 / 25,51 s) et sonde du LM3697 (25,67-25,85 s, reset
logiciel du rétroéclairage). À départager par `module_blacklist=`.

Résultats `module_blacklist=` (avec les *_ignore_unused) :
- sans tps65132 : le LM3697 éteint le rétroéclairage à sa sonde (attendu) ;
- sans lm3697 : rétroéclairage gardé, l'image part en fantôme ;
- sans lm3697 ni tps65132 (msm chargé) : l'image disparaît ;
- sans lm3697 ni msm (TPS65132 à 5,5 V) : console intacte.
Coupable : la sonde de msm (MDSS/MDP/DSI). Le runtime PM coupe le GDSC MDSS
et les horloges du cœur ; `pd_ignore_unused` ne l'empêche pas. Le passage
de VSP/VSN à 5,5 V est inoffensif.

pkgrel 32 : simpledrm tient `power-domains = <&mmcc MDSS_GDSC>` et les
horloges AHB/AXI/MDP/LUT/VSYNC/ESC0/ESC1 (nœud framebuffer du DTS), mmcc
passé en =y. Attendu : la console survit au chargement de msm. Test ensuite
avec `keep_init=1` : si l'image reste après le bind de msm, la chaîne vidéo
msm est bonne ; sinon, regarder le trou entre le retrait de simpledrm
(aperture) et le premier modeset.

pkgrel 32 + `keep_init=1` : **affichage natif OK** (console visible via
msm, split display DSI0+DSI1). Le rétroéclairage s'éteint à la sonde du
LM3697 puis se rallume, mais bien plus faible qu'au bootloader :
default-brightness-level = 177 sur 2047 (11 bits) avec le mappage
exponentiel par défaut du LM3697 (registre 0x16 = 0x00). Reste : la
séquence d'init du panneau (reset + init) sans keep_init.

Rappel : avec `keep_init` (aucun reset, aucune init), l'écran devenait noir
aussi. Le panneau perd donc son état, ou cesse d'afficher, au moment où msm
prend la main, indépendamment de notre séquence d'init.
Prochaine piste : l'ordre des étapes côté DSI quand msm prend la main
(coupure du GDSC MDSS entre la sonde et l'activation, LP11 avant reset).

Pistes suivantes si 0x9c n'apparaît pas :
- comparer la séquence d'init du panel avec le downstream (mode LP, délais,
  ordre reset/alims) ;
- vérifier qui déclenche le DMA (DSI1 seul en sync) et le contenu de
  CMD_DMA_CTRL/ CMD_MODE_DMA_CTRL relu en natif (`tools/mdss-snapshot.sh`) ;
- lire le registre d'erreurs DSI (ACK/timeout) après chaque commande.

## Patches noyau (pmos/linux-lg-d855)
| # | Objet |
|---|-------|
| 0001 | quirk carte MSSD0 |
| 0002 | pilote panel LGD SIC 1440p dual-DSI (+ relecture power mode) |
| 0003 | simpledrm : interconnect |
| 0004 | mmcc : ne pas garer mdp_clk_src sur XO à l'enregistrement |
| 0005 | adreno : paramètre headless_gpu |
| 0006 | MDP5 : split display DSI couplé sans source split (MSM8974) |
| 0007 | DSI : adresse du second contrôleur MSM8974 (0xfd922e00) |
| 0008 | LM3697 : réglage OVP du boost |
| 0009 | DSI : broadcast du DMA de commandes en DSI couplé synchronisé |

DTS : DSI1 `interrupts = <5>` (bug amont : <4>), nœud `fb_panel` factice
désactivé pour que fw_devlink ne retarde pas simpledrm.

## Câblage (manuel de service)
Reset panel PM8941 GPIO 19 ; IOVCC = L12 ; TPS65132 ENP GPIO 56 / ENN
GPIO 100 ; LM3697 enable GPIO 91 ; I2C commun GPIO 83/84 = blsp2_i2c5.

## État du téléphone
- greetd désactivé pour les tests (`sudo systemctl enable greetd` pour le
  remettre).
- Repli si le démarrage casse : ajouter `module_blacklist=msm` à la ligne
  `append` de `/boot/extlinux/extlinux.conf`.

## Travail de développement
- Noyau : arbre de travail avec les patches appliqués, compilé par
  `make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- <obj> </dev/null`
  (`</dev/null` évite le blocage sur une question de config).
- Référence downstream : drivers/video/msm/mdss et DT LG (noyau LG 3.4).
- Plus tard : remettre Phosh avec le GPU, retirer la relecture de debug,
  proposer en amont les correctifs (adresse et IRQ DSI1, mmcc, OVP LM3697,
  carte SD lk2nd), périphériques du fork archeYR/lg-d855-mainline.

pkgrel 33 : default-brightness-level 1600 (choisi à l'œil, mappage
exponentiel). Phosh lancé à la main par greetd sur l'affichage natif avec
keep_init : fonctionne, fluidité encore perfectible.

Sans keep_init (pkgrel 32/33) : toujours noir, alors que le GDSC tient. Le
coupable est bien notre séquence de mise sous tension/init du panneau.
pkgrel 34 : paramètre `init_steps` du pilote panel pour la bissecter sans
recompiler (masque : 1 cycle DSV, 2 reset, 4 table LG, 8 sleep out +
display on, 16 commandes en HS ; défaut 15). `keep_init=1` = étapes 0 au
premier prepare. device-lg-d855 r16 : `keep_init=1` dans modprobe.d (écran
utilisable en attendant) ; tests au démarrage avec
`panel_lge_g3_lgd_sic.keep_init=0 panel_lge_g3_lgd_sic.init_steps=N` sur la
ligne de commande. Ordre proposé : 8 (sleep out/display on seuls), 12
(table + on, sans reset), 14 (reset + table + on, sans cycle DSV), 15, puis
+16 (HS) sur celui qui échoue.

Bissection `init_steps` (keep_init=0) : 8, 12 et 14 affichent, 15 reste
noir. Le cycle VSP/VSN (coupure 20 ms puis rallumage) est le seul coupable ;
reset + table LG + sleep out/display on sont corrects.
linux-lg-d855 r35 : défaut 14 (sans cycle DSV) ; device-lg-d855 r17 :
keep_init retiré de modprobe.d. À vérifier : extinction/rallumage de
l'écran sous Phosh (unprepare coupe VSP/VSN et met le reset, le prepare
suivant est une vraie remise sous tension, proche du cas 15).
Rétroéclairage encore faible : vérifier brightness et le registre 0x16.

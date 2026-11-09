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

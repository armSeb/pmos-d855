# postmarketOS mainline pour LG G3 (D855)

Portage de postmarketOS sur le LG G3 international (D855, Snapdragon 801 /
MSM8974AC) avec un noyau **mainline** (fork
[msm8974-mainline/linux](https://github.com/msm8974-mainline/linux), 6.16) au
lieu de l'ancien noyau downstream 3.4, et à terme **Phosh**.

## Contenu du dépôt

| Chemin | Rôle |
|---|---|
| `dts/qcom-msm8974pro-lge-d855.dts` | Device tree mainline (source de référence) |
| `pmos/install-sdcard.sh` | **Construit et écrit une microSD démarrable** (procédure complète) |
| `pmos/linux-lg-d855/`, `pmos/device-lg-d855/` | Paquets pmOS : noyau épinglé + config, deviceinfo |
| `pmos/sync.sh`, `pmos/make-config.sh` | Copie des paquets dans pmaports, régénération de la config noyau ([détails](pmos/README.md)) |
| `tools/flash-lk2nd.sh`, `tools/lg-bump.py` | Téléchargement, bump LG et flash de lk2nd (mode Download, fastboot ou TWRP) |
| `tools/build-kernel.sh` | Compilation rapide zImage + DTB hors pmbootstrap (`DTB_ONLY=1` pour le DTB seul) |
| `tools/extract-firmware.sh` | Copie des firmwares depuis les partitions Android (à lancer sur le téléphone) |

## État du DTS

Le squelette compile proprement contre le fork 6.16 (aucun avertissement
propre au fichier). **Rien n'a encore été testé sur le matériel.**

| Bloc | Composant | Dans le DTS | Driver mainline |
|---|---|---|---|
| eMMC | SDHC1 | activé | oui |
| microSD | SDHC2, CD = TLMM 95 | activé | oui |
| USB | ChipIdea + HS PHY | activé (gadget/OTG) | oui |
| Boutons | Volume (PM8941 GPIO 2/3), power | activé | oui |
| Chargeur | bq24296 @ blsp1_i2c1 0x6b | activé | oui (`bq24190_charger`) |
| Jauge | MAX17048 @ 0x36, IRQ TLMM 9 | activé | oui (`max17040_battery`) |
| Tactile | Synaptics S3528 @ blsp1_i2c2 0x20, IRQ TLMM 73, reset TLMM 8 | activé | oui (RMI4) |
| WiFi | BCM4339 sur SDHC3, REG_ON TLMM 69, host-wake TLMM 44 | activé | oui (`brcmfmac`, firmware requis) |
| Rétroéclairage | LM3697 @ blsp2_i2c5 0x36, HWEN TLMM 91 | désactivé | oui (`leds-lm3697`) |
| Alim. panel | TPS65132 @ 0x3e, EN TLMM 56 / 100 | désactivé | oui |
| Panel | LGD SIC 1440p, vidéo, **double DSI** | absent | **à écrire** |
| GPU | Adreno 330 | désactivé (attend le panel) | oui (freedreno) |
| Bluetooth | BCM4339, BLSP1 UART5 | absent | nœud UART à ajouter |
| Modem / ADSP | remoteprocs MSS / ADSP | désactivés | oui (firmware requis) |
| Audio, capteurs, caméra, NFC | | absents | |

Câblage relevé dans le noyau LineageOS
[`android_kernel_lge_g3` (lineage-18.1)](https://github.com/LineageOS/android_kernel_lge_g3/tree/lineage-18.1/arch/arm/boot/dts/msm8974pro-g3-global_com),
fichiers `msm8974pro-g3-global_com/*`, `msm8974pro-lge-common/*`,
`arch/arm/mach-msm/lge/wifi_bcm_lge.c` et `8974ac-g3/board-8974-g3-*.c`.
Modèles mainline : Nexus 5 (même conception LG pour l'alimentation, le
chargeur et la jauge) et Xperia Z3 (microSD sur SDHC2, WiFi sur SDHC3).

## Premier boot

Principe : **seul lk2nd est flashé**. Le noyau est envoyé par USB à chaque
essai, le rootfs est sur la microSD, Android reste intact sur l'eMMC.

### 0. Sauvegardes (depuis TWRP)

```sh
adb shell dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot.img
adb shell dd if=/dev/block/bootdevice/by-name/recovery of=/sdcard/recovery.img
adb pull /sdcard/boot.img /sdcard/recovery.img .
```

### 1. lk2nd (bumpé)

L'aboot LG refuse toute image non signée (« Secure booting error ») sauf si
elle est « bumpée ». Le script télécharge lk2nd, le bumpe, sauvegarde la
partition boot actuelle dans `backups/`, l'écrit et relit pour vérifier.

Par défaut il passe par le **mode Download** LG, avec
[LGLAF](https://github.com/Lekensteyn/lglaf) (développé sur D855) :

```sh
sudo apt install python3-usb python3-cryptography
# téléphone éteint (batterie retirée/remise), maintenir Vol+ et brancher l'USB
tools/flash-lk2nd.sh
fastboot devices                       # après redémarrage : lk2nd répond (écran noir possible)
```

Si LGLAF n'a pas accès à l'USB, le script donne la règle udev à installer.
L'aboot stock du G3 n'a pas de fastboot : `METHOD=fastboot` ne sert qu'à
mettre à jour un lk2nd qui démarre déjà. `METHOD=twrp` passe par adb.
Autres variantes : `NO_FLASH=1`, `LK2ND_IMG=…`, `LK2ND_VERSION=…`.
Le bump seul : `tools/lg-bump.py lk2nd.img`.

### 2. Carte microSD

```sh
pmbootstrap init                       # une fois, n'importe quel appareil
pmos/install-sdcard.sh /dev/sdX        # UI console par défaut ; UI=phosh plus tard
```

Le script met à jour pmaports, y copie les paquets du dépôt (en retirant
l'ancien port downstream), construit l'image, vérifie la partition de boot,
l'écrit sur la carte et agrandit la racine. `REUSE_IMAGE=1` réécrit la
dernière image sans rien reconstruire.

### 3. Boot sans rien flasher

```sh
fastboot devices                       # lk2nd doit répondre
pmbootstrap flasher boot               # envoie boot.img (noyau + initramfs)
ssh user@172.16.42.1
```

L'initramfs trouve `pmOS_root` par son label, sur la microSD.
Si le boot échoue avant le rootfs :
`pmbootstrap flasher boot --cmdline pmos.debug-shell`, puis `telnet 172.16.42.1`.

### 4. Itérer sur le DTS

```sh
DTB_ONLY=1 tools/build-kernel.sh       # vérifie le DTS en quelques secondes
tools/build-kernel.sh                  # zImage + DTB dans out/
```

## Firmwares

Une fois booté, `tools/extract-firmware.sh` monte en lecture seule les
partitions `modem` et `system` et copie dans `/lib/firmware` :

- remoteprocs Qualcomm (`mba.mbn`, `modem.mdt`/`.bXX`, `adsp.*`, `venus.*`),
  rangés dans `qcom/msm8974/lge/d855/` ;
- WiFi : `brcm/brcmfmac4339-sdio.bin` et la NVRAM renommée
  `brcm/brcmfmac4339-sdio.lge,d855.txt` (nom dérivé du compatible du DTS) ;
- microcode Adreno 330 si nécessaire.

À terme : paquet `firmware-lg-d855` ou `msm-firmware-loader`.

## Feuille de route

1. Boot console : eMMC, microSD, USB réseau, boutons. ← **on en est là**
2. Affichage via simple-framebuffer laissé par lk2nd (adresse à relever, voir le `chosen` du DTS).
3. Driver du panel LGD SIC en double DSI : génération avec
   [linux-mdss-dsi-panel-driver-generator](https://github.com/msm8916-mainline/linux-mdss-dsi-panel-driver-generator)
   à partir de `msm8974pro-lge-common/msm8974pro-lge-panel.dtsi`, puis
   `mdss_dsi0` + `mdss_dsi1` couplés, rétroéclairage LM3697, TPS65132.
4. GPU, Phosh.
5. WiFi, batterie, Bluetooth.
6. Modem (MSS + rmtfs + ModemManager), puis audio.
7. Upstream du DTS dans le fork msm8974-mainline puis dans Linux (ajouter son `Signed-off-by` avant l'envoi).

## Remarque sur les révisions matérielles

Le downstream gère des révisions de carte (`evb1` à `rev_12`). Le DTS vise
les téléphones commerciaux (rev ≥ 1.0) : microSD sur SDHC2, WiFi sur SDHC3,
chargeur bq24296, LM3697 sur HVLED1+2. Les prototypes `rev_a` et antérieurs
sont câblés différemment.

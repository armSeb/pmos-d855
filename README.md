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
| `pmos/update.sh` | **Mise à jour** : reconstruit les paquets, les installe sur le téléphone (sideload) et démarre le nouveau noyau |
| `pmos/sync.sh`, `pmos/make-config.sh` | Copie des paquets dans pmaports, régénération de la config noyau ([détails](pmos/README.md)) |
| `tools/flash-lk2nd.sh`, `tools/lg-bump.py` | Téléchargement, bump LG et flash de lk2nd (mode Download, fastboot ou TWRP) |
| `tools/devmem32/` | Lecture/écriture de registres par `/dev/mem` (installé sur le téléphone) |
| `tools/mdp-dump.sh` | Relève le framebuffer du bootloader (registres MDP5), à lancer sur le téléphone |
| `tools/build-kernel.sh` | Compilation rapide zImage + DTB hors pmbootstrap (`DTB_ONLY=1` pour le DTB seul) |
| `tools/extract-firmware.sh` | Copie des firmwares depuis les partitions Android (à lancer sur le téléphone) |

## État du DTS

Le squelette compile proprement contre le fork 6.16 (aucun avertissement
propre au fichier).

Testé sur le matériel : lk2nd bumpé flashé dans `boot` par
`tools/flash-lk2nd.sh` (méthode fastboot depuis l'aboot LG) démarre
directement en mode fastboot. Le noyau mainline n'a pas encore été démarré.

| Bloc | Composant | Dans le DTS | Driver mainline |
|---|---|---|---|
| eMMC | SDHC1 | activé, testé (HS200) | oui |
| microSD | SDHC2, CD = TLMM 95, horloge 6 mA | activé, **testé en UHS** | oui |
| USB | ChipIdea + HS PHY | activé (gadget/OTG) | oui |
| Boutons | Volume (PM8941 GPIO 2/3), power | activé | oui |
| Chargeur | bq24296 @ blsp1_i2c1 0x6b | activé | oui (`bq24190_charger`) |
| Jauge | MAX17048 @ 0x36, IRQ TLMM 9 | activé | oui (`max17040_battery`) |
| Tactile | Synaptics S3528 @ blsp1_i2c2 0x20, IRQ TLMM 73, reset TLMM 8 | activé, **testé** | oui (RMI4) |
| WiFi | WCNSS Pronto + iris WCN3680 (interne au SoC) | **testé** ✓ | oui (`wcn36xx`, firmware via `extract-firmware`) |
| Rétroéclairage | LM3697 @ blsp2_i2c5 0x36, HWEN TLMM 91 | désactivé | oui (`leds-lm3697`) |
| Alim. panel | TPS65132 @ 0x3e, EN TLMM 56 / 100 | désactivé | oui |
| Panel | LGD SIC 1440p, vidéo, **double DSI** | décrit, désactivé | driver écrit (patch 0002) ; **MDP5 ne gère pas le DSI couplé** |
| GPU | Adreno 330 | désactivé (attend le panel) | oui (freedreno) |
| Bluetooth | WCNSS (même puce que le WiFi) | activé | oui (`btqcomsmd`, firmware requis) |
| Modem / ADSP | remoteprocs MSS / ADSP | désactivés | oui (firmware requis) |
| Audio, capteurs, caméra, NFC | | absents | |

Câblage relevé dans le noyau LineageOS
[`android_kernel_lge_g3` (lineage-18.1)](https://github.com/LineageOS/android_kernel_lge_g3/tree/lineage-18.1/arch/arm/boot/dts/msm8974pro-g3-global_com),
fichiers `msm8974pro-g3-global_com/*`, `msm8974pro-lge-common/*`,
`arch/arm/mach-msm/lge/8974ac-g3/board-8974-g3-*.c` et `lineageos_d855_defconfig`.
Modèles mainline : Nexus 5 (même conception LG pour l'alimentation, le
chargeur et la jauge), Xperia Z3 (microSD sur SDHC2) et OnePlus One
(WiFi/BT WCNSS).

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

Le script détecte comment le téléphone est connecté, dans cet ordre :

- **fastboot** : l'aboot LG passe en fastboot quand la partition `boot` est
  invalide (par exemple après un premier essai non bumpé). Le script flashe
  alors directement lk2nd bumpé dans `boot`, redémarre et attend que lk2nd
  réponde. Sous lk2nd, il met à jour la partition `lk2nd`. Pas de sauvegarde
  possible par ce chemin.
- **mode Download** (éteint, Vol+ en branchant l'USB), via
  [LGLAF](https://github.com/Lekensteyn/lglaf), avec sauvegarde de `boot`
  dans `backups/` et relecture. Prérequis : `python3-usb python3-cryptography`.
- **TWRP** (adb), avec sauvegarde et relecture.

```sh
tools/flash-lk2nd.sh                   # ou METHOD=fastboot|download|twrp
fastboot getvar all | grep -i lk2nd    # lk2nd répond (écran noir possible)
```

Autres variantes : `NO_FLASH=1`, `LK2ND_IMG=…`, `LK2ND_VERSION=…`.
Le bump seul : `tools/lg-bump.py lk2nd.img`.

### 2. Carte microSD

```sh
pmbootstrap init                       # une fois, n'importe quel appareil
pmos/install-sdcard.sh /dev/sdX        # UI console par défaut ; UI=phosh plus tard
```

Le script met à jour pmaports, y copie les paquets du dépôt (en retirant
l'ancien port downstream), installe directement sur la carte avec
`pmbootstrap install --sdcard` puis vérifie la partition de boot.

### 3. Boot sans rien flasher

lk2nd démarre l'Android flashé derrière lui (`fastboot flash boot boot.img`
depuis lk2nd l'écrit après lui, LineageOS reste donc utilisable). Pour
rester dans le fastboot de lk2nd, maintenir **Vol−** au démarrage.

```sh
fastboot devices                       # lk2nd doit répondre
pmbootstrap flasher boot               # envoie boot.img (noyau + initramfs)
ssh user@172.16.42.1
```

L'initramfs trouve `pmOS_root` par son label, sur la microSD.
Si le boot échoue avant le rootfs :
`pmbootstrap flasher boot --cmdline pmos.debug-shell`, puis `telnet 172.16.42.1`.

### Mettre à jour (sans réécrire la carte)

Le téléphone démarré sous pmOS et joignable en SSH (172.16.42.1 par l'USB) :

```sh
git pull
pmos/update.sh
```

Le script recopie les paquets dans pmaports, recalcule les sommes, construit
`linux-lg-d855` et `device-lg-d855`, les installe sur le téléphone avec
`pmbootstrap sideload`, récupère le `boot.img` régénéré, redémarre vers lk2nd
et le démarre par fastboot. Si le téléphone ne reste pas en fastboot,
maintenir Vol− pendant le redémarrage. `CMDLINE="…"` remplace la ligne de
commande pour un essai, `NO_BOOT=1` s'arrête après l'installation.

Le paquet `device-lg-d855` installe aussi les outils de bring-up :
`i2cdetect`/`i2cget` (i2c-tools), `gpioinfo`/`gpioget` (libgpiod), `evtest`,
`lsusb`, `iw`, `strace`, `devmem32` et `mdp-dump`.

### 4. Relever le framebuffer du bootloader

Dans le shell de debug ou en SSH, écran encore allumé par le bootloader :

```sh
sudo mdp-dump       # installé par device-lg-d855
```

### 5. Itérer sur le DTS

```sh
DTB_ONLY=1 tools/build-kernel.sh       # vérifie le DTS en quelques secondes
tools/build-kernel.sh                  # zImage + DTB dans out/
```

## Démarrage autonome (sans PC)

lk2nd cherche `extlinux/extlinux.conf` sur les partitions ext2. Sur MSM8974,
il ne lit la microSD que si l'entrée du téléphone l'active
(`lk2nd,sd-mmc`), ce que l'entrée D855 officielle ne fait pas encore :
`tools/lk2nd/0001-…patch` l'ajoute (à proposer en amont).

pmOS génère `/boot/extlinux/extlinux.conf` (`deviceinfo_generate_extlinux_config`)
à chaque mise à jour du noyau : il n'y a plus rien à flasher. Carte présente →
pmOS ; carte absente → l'Android derrière lk2nd (LineageOS) démarre.

```
tools/build-lk2nd.sh                         # → out/lk2nd-msm8974.img
fastboot boot out/lk2nd-msm8974.img          # essai en RAM, depuis lk2nd (Vol−)
LK2ND_IMG=out/lk2nd-msm8974.img tools/flash-lk2nd.sh   # puis flash (bump inclus)
```

Contraintes de lk : table de partitions **MBR** (son lecteur ignore le GPT,
d'où `deviceinfo_partition_type="msdos"`) et `pmOS_boot` en **ext2** (pas
d'extents). Pour convertir une carte GPT existante sans perdre les données,
depuis le PC, carte démontée : `sudo sgdisk --gpttombr=1:2 /dev/sdX`.

Secours, si la lecture de la carte échoue : `lk2nd-flash-boot` (paquet
`device-lg-d855`, désactivé par défaut) recopie `/boot/boot.img` dans la
partition `boot` derrière lk2nd. Limite : 15,5 MiB (la partition fait
16 MiB), il faut alors un initramfs en lzma (`deviceinfo_initfs_compression`).

## Firmwares

Une fois booté, `sudo extract-firmware` (installé par `device-lg-d855`,
source `tools/extract-firmware.sh`) monte en lecture seule les
partitions `modem` et `system` et copie dans `/lib/firmware` :

- remoteprocs Qualcomm (`mba.mbn`, `modem.mdt`/`.bXX`, `adsp.*`, `venus.*`),
  rangés dans `qcom/msm8974/lge/d855/` ;
- WiFi/BT : `wcnss.mdt`/`.bXX` (partition `modem`) et la calibration
  `WCNSS_qcom_wlan_nv.bin` (`system/etc/firmware/wlan/prima/`), dans le même
  dossier (chemins fixés par `firmware-name` dans le DTS) ;
- microcode Adreno 330 si nécessaire.

À terme : paquet `firmware-lg-d855` ou `msm-firmware-loader`.

## Feuille de route

0. lk2nd bumpé démarre. ✓
1. Boot console : eMMC, microSD, USB réseau, boutons. ← **on en est là**
2. Affichage via le framebuffer laissé par le bootloader (simple-framebuffer +
   simpledrm) : 1440x2560 RGB888 à `0x03200000`, stride 4320 (relevé avec
   `mdp-dump`). Deux pièges trouvés : `mmcc-msm8974` reprogrammait MMPLL1/3
   à chaud et cassait l'affichage dans la première seconde (patch 0004), et
   le bus multimédia (MMSS NoC) doit rester tel que le bootloader l'a réglé
   (driver désactivé, vote BIMC par simpledrm, patch 0003). ← **on en est là**
3. Affichage natif. Le driver du panel est écrit
   (`pmos/linux-lg-d855/0002-…patch`, compatible `lge,g3-panel-lgd-sic`)
   et le DTS décrit DSI0 + DSI1 couplés, le rétroéclairage LM3697 et le
   TPS65132, mais tout reste désactivé : le driver MDP5 mainline de la
   MSM8974 ne sait pas piloter deux interfaces DSI couplées (seul le côté
   DSI le gère, et DPU ne prend pas en charge la MSM8974). Il faudra
   ajouter ce support à MDP5 avant de pouvoir l'activer.
4. GPU, Phosh.
5. WiFi, batterie, Bluetooth.
6. Modem (MSS + rmtfs + ModemManager), puis audio.
7. Upstream du DTS dans le fork msm8974-mainline puis dans Linux (ajouter son `Signed-off-by` avant l'envoi).

## Remarque sur les révisions matérielles

Le downstream gère des révisions de carte (`evb1` à `rev_12`). Le DTS vise
les téléphones commerciaux (rev ≥ 1.0) : microSD sur SDHC2, WiFi/BT par le
WCNSS interne (pas de SDIO : « WIFI doesn't use any sdcc from rev_b »),
chargeur bq24296, LM3697 sur HVLED1+2. Les prototypes `rev_a` et antérieurs
sont câblés différemment.

# Paquets postmarketOS

- `install-sdcard.sh /dev/sdX` : construit une image et l'écrit sur une microSD
  démarrable (voir le README principal, « Premier boot »).
- `sync.sh <pmaports>` : copie les deux paquets dans `pmaports/device/testing/`,
  après avoir rafraîchi les fichiers dont la source est ailleurs dans le dépôt
  (le DTS). Retire au passage l'ancien port downstream de pmaports.
- `make-config.sh [arbre]` : régénère `linux-lg-d855/config-lg-d855.armv7`
  à partir de `msm8974_defconfig` du fork et de `linux-lg-d855/lg-d855.fragment`.

## Paquets

| Paquet | Contenu |
|---|---|
| `linux-lg-d855` | Fork [msm8974-mainline/linux](https://github.com/msm8974-mainline/linux) épinglé (`_commit`), + `qcom-msm8974pro-lge-d855.dts`. Installe `vmlinuz`, les modules et les DTB. |
| `device-lg-d855` | `deviceinfo` : boot.img fastboot avec DTB appendé, offsets lk2nd. |

## Changer de version du noyau

1. Mettre le nouveau commit (branche `qcom-msm8974-6.y`) dans `_commit` et
   `pkgver` de `linux-lg-d855/APKBUILD`, remettre `pkgrel=0`.
2. `pmos/make-config.sh` : la config est régénérée sur ce commit ; le script
   signale toute option du fragment qui n'a pas été retenue.
3. `pmos/install-sdcard.sh /dev/sdX`.

## Modifier la config du noyau

Ajouter les options dans `lg-d855.fragment`, puis `pmos/make-config.sh`.
Ne pas éditer `config-lg-d855.armv7` à la main : il serait écrasé.

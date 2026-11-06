#!/usr/bin/env python3
"""« Bump » d'une image boot Android pour les bootloaders LG (G2, G3…).

L'aboot LG vérifie la signature de boot/recovery, mais accepte une image qui
se termine juste après son contenu par le « magic » LG (16 octets) : c'est la
faille Bump (CyboLabs, 2014). Même principe que open_bump.py, en Python 3 :

  1. lit l'en-tête boot (v0, avec dt_size Qualcomm) ;
  2. calcule la taille utile (en-tête + kernel + ramdisk + second + dt,
     chacun arrondi à la page) ;
  3. retire ce qui dépasse s'il s'agit de bourrage (zéros) ou du marqueur
     Samsung « SEANDROIDENFORCE » qu'ajoutent les images lk2nd ;
  4. ajoute le magic LG.

Usage : lg-bump.py entrée.img [sortie.img]
"""
import struct
import sys

LG_MAGIC = bytes.fromhex("41a9e467744d1d1ba429f2ecea655279")
SAMSUNG_MARKER = b"SEANDROIDENFORCE"


def die(msg):
    sys.exit(f"lg-bump : {msg}")


def bump(data: bytes) -> bytes:
    if data[:8] != b"ANDROID!":
        die("pas une image boot Android (magic ANDROID! absent)")
    if data.endswith(LG_MAGIC):
        print("lg-bump : image déjà bumpée, inchangée")
        return data

    (kernel, _, ramdisk, _, second, _, _, page, dt) = struct.unpack_from("<9I", data, 8)
    if page not in (2048, 4096):
        die(f"taille de page inattendue : {page}")

    def up(n):
        return (n + page - 1) // page * page

    useful = page + up(kernel) + up(ramdisk) + up(second) + up(dt)
    if useful > len(data):
        die(f"image tronquée : {len(data)} octets, {useful} attendus")

    tail = data[useful:]
    if tail and tail.strip(b"\0") not in (b"", SAMSUNG_MARKER):
        die(f"{len(tail)} octets inconnus après le contenu de l'image, abandon")

    return data[:useful] + LG_MAGIC


def main():
    if len(sys.argv) not in (2, 3):
        die("usage : lg-bump.py entrée.img [sortie.img]")
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) == 3 else src.rsplit(".img", 1)[0] + "-bumped.img"
    with open(src, "rb") as f:
        out = bump(f.read())
    with open(dst, "wb") as f:
        f.write(out)
    print(f"lg-bump : {dst} ({len(out)} octets)")


if __name__ == "__main__":
    main()

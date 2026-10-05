# -*- coding: utf-8 -*-
"""El rastro de la caballada (tanda 7): pinta assets/terreno/huellas_caballada.png, la textura de los
calcos (Decal) de Caminos/RastroDeLaCaballada en scenes/World.tscn.

No es el barro pisoteado de los senderos de la aguada (huellas_hacienda.png, de aguada.py): es el paso
de cuatro caballos sueltos, de una sola vez, sobre la estepa seca: la tierra removida por el galope, en
manchones, y los vasos (una media luna cerrada adelante y abierta en el talón), todos para el mismo
lado. Los vasos y la cantidad de pisadas están agrandados a propósito: con el tamaño real, el rastro no
se veía desde arriba del caballo. No toca el terreno.

    py tools/terreno/rastro.py
"""
import math
import os

import numpy as np
from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEMILLA = 1881
ANCHO, LARGO = 256, 1024      # el calco mide 2,8 m x 7,4 m: unos 91 puntos por metro a lo ancho
PISADAS = 88                  # cuatro caballos al galope: más de las que serían, para que se lea de a caballo
VASO = 17.0                   # largo del vaso en puntos (unos 19 cm: agrandado, para que se vea)


def pintar():
    r = np.random.default_rng(SEMILLA)
    yy, xx = np.mgrid[0:LARGO, 0:ANCHO].astype(np.float64)
    u = (xx - ANCHO / 2) / (ANCHO / 2)
    borde = np.clip(1.0 - np.abs(u) ** 3, 0, 1)
    # la tierra removida: apenas, en manchones, para que el rastro se lea de lejos como una franja
    manchas = 0.5 + 0.5 * np.sin(yy / LARGO * 2 * math.pi * 2 + np.sin(xx / 33.0) * 1.7) * np.sin(xx / ANCHO * math.pi * 1.8 + 0.6)
    alfa = np.clip(1.0 - np.abs(u) ** 1.8, 0, 1) ** 1.4 * (0.2 + 0.3 * manchas)
    rgb = np.zeros((LARGO, ANCHO, 3)) + np.array([0.29, 0.23, 0.165])
    rgb *= (0.88 + 0.12 * manchas)[..., None]
    for _ in range(PISADAS):
        cx = ANCHO / 2 + r.normal(0, ANCHO * 0.17)
        cy = r.uniform(0, LARGO)
        giro = r.normal(0, 0.22)                     # todos van para el mismo lado
        tam = VASO * r.uniform(0.9, 1.12)
        dy = (yy - cy + LARGO / 2) % LARGO - LARGO / 2    # en vuelta: la imagen se repite a lo largo
        dx = xx - cx
        a = dx * math.cos(giro) + dy * math.sin(giro)     # a lo ancho del vaso
        b = -dx * math.sin(giro) + dy * math.cos(giro)    # a lo largo: la punta mira hacia +b
        d = np.sqrt((a / (tam * 0.46)) ** 2 + (b / (tam * 0.5)) ** 2)
        anillo = np.clip(1.0 - np.abs(d - 0.7) / 0.4, 0, 1)
        talon = np.clip((b + tam * 0.18) / (tam * 0.2), 0, 1)   # abierto atrás
        marca = (anillo * talon) ** 1.2
        rgb *= (1 - 0.62 * marca)[..., None]
        alfa = np.maximum(alfa, marca * 0.96 * borde)
    im = np.concatenate([np.clip(rgb, 0, 1), np.clip(alfa, 0, 1)[..., None]], -1)
    destino = os.path.join(RAIZ, 'assets', 'terreno', 'huellas_caballada.png')
    Image.fromarray((im * 255 + 0.5).astype(np.uint8), 'RGBA').save(destino)
    print('listo:', destino)


if __name__ == '__main__':
    pintar()

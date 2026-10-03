# Telon de montanias que sigue a la camara (cuelga del nodo Estrellas): coordenadas relativas a la camara.
# Dos capas en una sola malla: la cordillera nevada al oeste y cerros de bosque oscuro delante.
# Colores por vertice (roca, nieve, bosque), en sRGB: el material los pasa a lineal.
import json, math
import numpy as np
import os
AQUI = os.path.dirname(os.path.abspath(__file__))
ENTRADA = os.path.join(AQUI, 'entrada')
SALIDA = os.path.join(AQUI, 'salida')
os.makedirs(SALIDA, exist_ok=True)
os.chdir(SALIDA)                  # todo lo que se escribe queda en salida/

rng = np.random.default_rng(1881)
BASE = -22.0          # el pie queda apenas debajo del horizonte (lo tapa el terreno con niebla)


def fbm1(n, octavas, semilla, suav=1.0):
    r = np.random.default_rng(semilla)
    total = np.zeros(n)
    amp = 1.0
    for o in range(octavas):
        k = 2 ** o
        pts = r.normal(size=k * 4 + 4)
        xs = np.linspace(0, len(pts) - 3, n)
        i = np.floor(xs).astype(int)
        t = xs - i
        t = t * t * (3 - 2 * t)
        total += (pts[i] * (1 - t) + pts[i + 1] * t) * amp
        amp *= 0.5 * suav
    return total / (np.abs(total).max() + 1e-9)


def fbm2(na, nr, semilla, octavas=5):
    r = np.random.default_rng(semilla)
    total = np.zeros((nr, na))
    amp = 1.0
    for o in range(octavas):
        ka = 6 * 2 ** o
        kr = 2 * 2 ** o
        g = r.normal(size=(kr + 2, ka + 2))
        ya = np.linspace(0, ka, na)
        yr = np.linspace(0, kr, nr)
        ia = np.clip(np.floor(ya).astype(int), 0, ka - 1)
        ir = np.clip(np.floor(yr).astype(int), 0, kr - 1)
        ta = ya - ia
        tr = yr - ir
        ta = ta * ta * (3 - 2 * ta)
        tr = tr * tr * (3 - 2 * tr)
        a00 = g[ir][:, ia]; a01 = g[ir][:, ia + 1]; a10 = g[ir + 1][:, ia]; a11 = g[ir + 1][:, ia + 1]
        v = (a00 * (1 - ta) + a01 * ta) * (1 - tr[:, None]) + (a10 * (1 - ta) + a11 * ta) * tr[:, None]
        total += v * amp
        amp *= 0.5
    return total / (np.abs(total).max() + 1e-9)


def hexf(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float) / 255.0


V, C, I = [], [], []


def capa(a0, a1, r0, r1, na, nr, alto_fn, color_fn, semilla):
    """Franja polar de alturas: azimut a0..a1 (grados, 180 = oeste), radio r0..r1."""
    base = len(V)
    az = np.radians(np.linspace(a0, a1, na))
    rr = np.linspace(r0, r1, nr)
    ruido = fbm2(na, nr, semilla)
    H = alto_fn(az, rr, ruido)
    # bordes de la franja al pie (para que no se vea un corte)
    for j in range(nr):
        for i in range(na):
            x = rr[j] * math.cos(az[i])
            z = rr[j] * math.sin(az[i])
            V.append([x, BASE + H[j, i], z])
    # normales aproximadas para el color (pendiente)
    for j in range(nr):
        for i in range(na):
            dh_a = (H[j, min(i + 1, na - 1)] - H[j, max(i - 1, 0)]) / (2 * rr[j] * (az[1] - az[0]))
            dh_r = (H[min(j + 1, nr - 1), i] - H[max(j - 1, 0), i]) / (2 * (rr[1] - rr[0]))
            pend = math.hypot(dh_a, dh_r)
            C.append(list(color_fn(H[j, i], pend, ruido[j, i], j / (nr - 1), az[i])) + [1.0])
    for j in range(nr - 1):
        for i in range(na - 1):
            a = base + j * na + i
            b = a + 1
            c = a + na
            d = c + 1
            # caras mirando hacia el centro (la camara)
            I.extend([a, c, b, b, c, d])


# ---------------------------------------------------------------- cordillera nevada (oeste)
def alto_cordillera(az, rr, ruido):
    a = np.degrees(az)
    env = np.clip((a - 118) / 22, 0, 1) * np.clip((246 - a) / 22, 0, 1)
    env = env * env * (3 - 2 * env)
    cresta = 290 + 100 * fbm1(len(a), 6, 11, 1.1)                       # 190 a 390 m
    picos = (1 - np.abs(fbm1(len(a), 7, 12, 1.35))) ** 3 * 230           # picos agudos (ruido "crestado")
    perfil_r = np.sin(np.clip((rr - rr[0]) / (rr[-1] - rr[0]), 0, 1) * math.pi) ** 0.7
    quebradas = 0.62 + 0.38 * (1 - np.abs(ruido)) ** 1.5                 # valles entre cerros
    H = (cresta + picos)[None, :] * env[None, :] * perfil_r[:, None] * quebradas
    return np.maximum(H, 0) + 10


ROCA = hexf('#55585f'); ROCA2 = hexf('#65635f'); NIEVE = hexf('#dfe4e7'); BOSQUE = hexf('#36403d')


def color_cordillera(h, pend, ruido, t, az):
    linea_nieve = 345 + 45 * ruido
    nieve = np.clip((h - linea_nieve) / 60, 0, 1) * (1 - np.clip((pend - 0.95) / 0.4, 0, 1) * 0.6)
    roca = ROCA * (1 - t) + ROCA2 * t
    bosque = np.clip((150 - h) / 90, 0, 1)
    c = roca * (1 - bosque) + BOSQUE * bosque
    return c * (1 - nieve) + NIEVE * nieve


capa(100, 262, 3150, 3850, 340, 26, alto_cordillera, color_cordillera, 21)


# ---------------------------------------------------------------- cerros de bosque delante
def alto_cerros(az, rr, ruido):
    a = np.degrees(az)
    env = np.clip((a - 120) / 25, 0, 1) * np.clip((242 - a) / 25, 0, 1)
    env = env * env * (3 - 2 * env)
    cresta = 115 + 55 * fbm1(len(a), 6, 31, 1.15)          # 60 a 170 m, quebrado
    perfil_r = np.sin(np.clip((rr - rr[0]) / (rr[-1] - rr[0]), 0, 1) * math.pi) ** 1.1
    H = cresta[None, :] * env[None, :] * perfil_r[:, None] * (1 + 0.2 * ruido)
    return np.maximum(H, 0) + 6


BOSQUE2 = hexf('#38433f'); BOSQUE3 = hexf('#454b3f')


def color_cerros(h, pend, ruido, t, az):
    k = np.clip(0.5 + ruido * 0.4, 0, 1)
    return BOSQUE2 * (1 - k) + BOSQUE3 * k


capa(112, 250, 2650, 3000, 260, 12, alto_cerros, color_cerros, 33)


json.dump({'v': V, 'c': C, 'i': I}, open('malla_cordillera.json', 'w'))
print('vertices', len(V), 'triangulos', len(I) // 3)

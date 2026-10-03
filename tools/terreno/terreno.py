# Terreno nuevo: escalon del noreste emparejado, lago Nahuel Huapi al oeste, rio Limay,
# mapa de mezcla de suelos (splat) y mapa de color con manchas grandes.
# Grilla: 1025 x 1025, celda 4 m; x = -2048 + 4*col, z = -2048 + 4*fila; altura en metros = crudo * 0.01.
import json, math
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from scipy.ndimage import gaussian_filter, sobel, distance_transform_edt
import os
AQUI = os.path.dirname(os.path.abspath(__file__))
ENTRADA = os.path.join(AQUI, 'entrada')
SALIDA = os.path.join(AQUI, 'salida')
os.makedirs(SALIDA, exist_ok=True)
os.chdir(SALIDA)                  # todo lo que se escribe queda en salida/

R = 1025
h0 = np.fromfile(os.path.join(ENTRADA, 'alturas_originales.bin'), dtype=np.float32).reshape(R, R).astype(np.float64) * 0.01
cols = np.arange(R)
X = (-2048.0 + 4.0 * cols)[None, :].repeat(R, 0)
Z = (-2048.0 + 4.0 * cols)[:, None].repeat(R, 1)
h = h0.copy()

# ---------------------------------------------------------------- 1. escalon del noreste
# El rectangulo filas 0..460, columnas 564..1024 estaba 2 m mas alto, con un corte a pique.
F1, C1 = 460, 564
paso_v = []
for r in range(0, F1 + 1):
    izq = 2 * h0[r, C1 - 1] - h0[r, C1 - 2]
    paso_v.append(h0[r, C1] - izq)
paso_h = []
for c in range(C1, R):
    abajo = 2 * h0[F1 + 1, c] - h0[F1 + 2, c]
    paso_h.append(h0[F1, c] - abajo)
escalon = float(np.median(paso_v + paso_h))
print('escalon medido', round(escalon, 3), 'm')
dentro = (np.arange(R)[:, None] <= F1) & (np.arange(R)[None, :] >= C1)
h[dentro] -= escalon
# coser lo que quede del borde con un suavizado angosto a lo largo de las dos lineas
borde = np.zeros((R, R), bool)
borde[0:F1 + 1, C1 - 6:C1 + 6] = True
borde[F1 - 5:F1 + 7, C1 - 6:R] = True
suave = gaussian_filter(h, 3.0)
w = gaussian_filter(borde.astype(float), 3.0)
w = np.clip(w * 1.6, 0, 1)
h = h * (1 - w) + suave * w

# ---------------------------------------------------------------- 2. lago Nahuel Huapi (oeste)
WL_LAGO = -3.0
LCX, LCZ, LRX, LRZ = -1560.0, -40.0, 480.0, 640.0
rng = np.random.default_rng(3)
armonicos = [(k, rng.uniform(0.02, 0.09) / (1 + 0.15 * k), rng.uniform(0, 2 * np.pi)) for k in range(2, 9)]


def borde_lago(theta):
    v = 1.0
    for k, a, f in armonicos:
        v += a * np.cos(k * theta + f)
    return v


th = np.arctan2((Z - LCZ) / LRZ, (X - LCX) / LRX)
q = np.sqrt(((X - LCX) / LRX) ** 2 + ((Z - LCZ) / LRZ) ** 2) / borde_lago(th)


A_PLAYA = 16.0                     # subida de la playa por unidad de q (~2,9 %: 17 m de agua baja y despues orilla)


def suave01(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def smin(a, b, k):
    hh = np.clip(k - np.abs(a - b), 0, None) / k
    return np.minimum(a, b) - hh * hh * k * 0.25


adentro = WL_LAGO - 0.5 - 6.5 * np.clip(1 - q, 0, 1) ** 0.8
playa = WL_LAGO - 0.5 + A_PLAYA * (q - 1)
# adentro: el fondo baja; afuera: el terreno alto se rebaja en una playa que sube suave hasta juntarse con el campo
h = np.where(q < 1.0, np.minimum(h, adentro), smin(h, playa, 1.0))
# piso minimo pasando la orilla: el borde de la malla del lago (q = 1.10) siempre queda tapado por tierra
w_piso = suave01((q - 1.06) / 0.04) * (1 - suave01((q - 1.5) / 0.2))
h = h * (1 - w_piso) + np.maximum(h, WL_LAGO + 0.2) * w_piso

# ---------------------------------------------------------------- 3. rio Limay
ctrl = [(-1180, 5), (-1080, 6), (-1000, 4), (-900, -12), (-790, -30), (-680, -38), (-580, -38), (-500, -38),
        (-440, -38), (-395, -46), (-355, -76), (-332, -130), (-322, -200), (-325, -280), (-308, -380),
        (-262, -490), (-185, -600), (-95, -705), (0, -812), (100, -922), (200, -1032), (300, -1165),
        (400, -1292), (520, -1420), (650, -1515), (800, -1584), (1000, -1632), (1200, -1580),
        (1400, -1500), (1600, -1364), (1800, -1150), (2000, -900), (2150, -760)]


def catmull(p, paso=1.0):
    p = np.array(p, float)
    p = np.vstack([p[0] * 2 - p[1], p, p[-1] * 2 - p[-2]])
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        L = np.linalg.norm(p2 - p1)
        n = max(2, int(L / paso))
        for k in range(n):
            tt = k / n
            t2, t3 = tt * tt, tt * tt * tt
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * tt + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(p[-2])
    return np.array(out)


cl = catmull(ctrl, 1.0)
seg = np.linalg.norm(np.diff(cl, axis=0), axis=1)
s_cl = np.concatenate([[0], np.cumsum(seg)])
LARGO = s_cl[-1]
print('largo del rio', round(LARGO), 'm')
PEND = 0.00025                     # 25 cm por km
W_C = 12.0                         # medio ancho del cauce (agua de ~24 m)
PROF = 1.0                         # hondura en el medio (se cruza vadeando)
W_B = 30.0                         # ancho de la barranca que vuelve al terreno


def nivel_rio(s):
    return WL_LAGO - PEND * s


arbol = cKDTree(cl)
pts = np.stack([X.ravel(), Z.ravel()], -1)
d_rio, i_rio = arbol.query(pts, distance_upper_bound=W_C + 2 + W_B + 8)
d_rio = d_rio.reshape(R, R)
i_rio = np.clip(i_rio.reshape(R, R), 0, len(cl) - 1)
cerca = np.isfinite(d_rio)
s_px = s_cl[i_rio]
wl_px = nivel_rio(s_px)
fondo = wl_px - PROF
orilla = wl_px + 0.35
dd = np.where(cerca, d_rio, 1e9)
# perfil transversal
t1 = np.clip((dd - (W_C - 4)) / 6.0, 0, 1)
t1 = t1 * t1 * (3 - 2 * t1)
cauce = fondo * (1 - t1) + orilla * t1
t2 = np.clip((dd - (W_C + 2)) / W_B, 0, 1)
t2 = t2 * t2 * (3 - 2 * t2)
perfil_rio = np.where(dd <= W_C + 2, cauce, orilla * (1 - t2) + h * t2)
h_rio = np.where(cerca, perfil_rio, h)
# dentro del lago manda el lago (el rio nace adentro)
h = np.where(q < 1.0, np.minimum(h, h_rio), h_rio)

# ---------------------------------------------------------------- 4. control: que no se mueva el piso bajo lo que ya esta
nodos = json.load(open(os.path.join(ENTRADA, 'nodos.json')))
peor = (0, '')
for n in nodos:
    c = int(round((n['x'] + 2048) / 4)); r = int(round((n['z'] + 2048) / 4))
    if 0 <= c < R and 0 <= r < R:
        dlt = abs(h[r, c] - h0[r, c])
        if dlt > peor[0]:
            peor = (dlt, n['n'])
print('mayor cambio de altura bajo un nodo existente', round(peor[0], 3), peor[1])

# ---------------------------------------------------------------- 5. mezcla de suelos (R estepa, G tierra, B vega, A canto)
def ruido_grilla(escala_m, semilla):
    r_ = np.random.default_rng(semilla)
    n = r_.normal(size=(R, R))
    n = gaussian_filter(n, escala_m / 4.0, mode='wrap')
    return (n - n.min()) / (n.max() - n.min())


gy = sobel(h, 0) / (8 * 4.0)
gx = sobel(h, 1) / (8 * 4.0)
pend = np.sqrt(gx * gx + gy * gy)            # tangente de la pendiente

estepa = np.ones((R, R))
tierra = np.clip((ruido_grilla(60, 21) - 0.62) / 0.12, 0, 1) * 0.65
# tierra pisada alrededor de los lugares
lugares = [((202, 156), 16, 26), ((240, 160), 20, 30), ((-170, -250), 22, 34), ((-430, 60), 10, 26),
           ((0, -220), 8, 14), ((90, -420), 5, 10), ((40, 320), 5, 9), ((-6.5, -1.0), 3, 6),
           # tanda 3: la calle del campamento de la tropa (tres manchas en hilera), el fortin nuevo y su corral.
           # En la escena se pintaron a mano sobre splat.png (con un sendero fino entre los dos que aca no esta).
           ((-1047, 320), 9, 20), ((-1029, 321), 9, 20), ((-1011, 322), 9, 20), ((-905, 415), 7.5, 15), ((-898.6, 402.5), 3, 8)]
for (lx, lz), r0, r1 in lugares:
    if (lx, lz) == (-430, 60):
        # la tolderia es una hilera norte-sur: se usa la distancia a ese segmento
        zz = np.clip(Z, 15, 95)
        d = np.sqrt((X - lx) ** 2 + (Z - zz) ** 2)
    else:
        d = np.sqrt((X - lx) ** 2 + (Z - lz) ** 2)
    tt = np.clip((r1 - d) / (r1 - r0), 0, 1)
    tierra = np.maximum(tierra, tt * 0.9)
# agua de verdad: donde el piso queda debajo del nivel del lago (dentro de su malla) o del rio (dentro de su cinta)
nivel = np.where(cerca & (dd <= W_C + 3.0), wl_px, -np.inf)
nivel = np.where(q < 1.10, np.maximum(nivel, WL_LAGO), nivel)
agua = h < nivel
# distancia firmada a la linea de agua, en metros (+ en tierra, - bajo el agua); la orilla cae entre dos celdas
d_agua = np.where(agua, -(distance_transform_edt(agua) * 4.0 - 2.0), distance_transform_edt(~agua) * 4.0 - 2.0)
print('celdas con agua', int(agua.sum()))
# orilla: playa de canto rodado de ancho desparejo (en el lago mucho mas ancha que en el rio)
cerca_lago = suave01((1.35 - q) / 0.2)
r_orilla = ruido_grilla(36, 35)
ancho_canto = (1.5 + 3.5 * r_orilla) + cerca_lago * (4.0 + 12.0 * r_orilla)
# pegado al agua, canto mojado parejo; mas arriba, piedras sueltas mezcladas con la estepa (no una faja lisa)
mojado = np.clip((2.5 - d_agua) / 2.0, 0, 1)
sueltas = np.clip((ancho_canto + 3.0 - d_agua) / 6.0, 0, 1) * (0.25 + 0.4 * ruido_grilla(10, 36))
canto_seco = np.maximum(mojado, sueltas)
vega = np.clip((28 - d_agua) / 14, 0, 1) * np.clip((d_agua - ancho_canto + 2) / 6, 0, 1)
vega *= (0.55 + 0.45 * ruido_grilla(30, 31)) * (1 - 0.4 * cerca_lago)
canto = np.where(d_agua >= 0, canto_seco, 1.0)
canto = np.maximum(canto, np.clip((pend - 0.18) / 0.15, 0, 1) * 0.8)
# fondo del agua: canto cerca de la orilla, mas adentro canto con barro (tierra)
fondo_canto = np.clip((10 + d_agua) / 6, 0.5, 1)
barro = np.where(d_agua < 0, 1 - fondo_canto, 0.0)
canto = np.where(d_agua < 0, fondo_canto, canto)
vega = np.where(d_agua < 0, 0.0, vega)
tierra = np.where(d_agua < 0, barro, tierra)
# bajos humedos del valle: algo de vega
vega = np.maximum(vega, np.where(d_agua >= 0, np.clip((-2.2 - h) / 1.2, 0, 1) * 0.2 * ruido_grilla(50, 32), 0.0))
tierra *= (1 - vega)
estepa = np.clip(1 - tierra - vega - canto, 0, 1)
suma = estepa + tierra + vega + canto + 1e-6
splat = np.stack([estepa, tierra, vega, canto], -1) / suma[..., None]
Image.fromarray((splat * 255 + 0.5).astype(np.uint8)).save('splat_nuevo.png')

# ---------------------------------------------------------------- 6. color (multiplica la textura; A = 1 siempre)
g1 = ruido_grilla(40, 41)
g2 = ruido_grilla(140, 42)
g3 = ruido_grilla(420, 43)
g4 = ruido_grilla(18, 44)
# manchas grandes y suaves: mas oscuras y oliva donde hay mata baja, mas claras y pardas donde el suelo esta pelado
brillo = 0.78 + 0.09 * g1 + 0.08 * g2 + 0.03 * g3 + 0.02 * g4       # ~0.78 .. 1.0
calido = (g2 - 0.5) * 0.10 + (g4 - 0.5) * 0.04                     # rojizo vs oliva
oliva = np.clip((0.45 - g1) / 0.25, 0, 1) * 0.06
col = np.stack([brillo * (1 + calido - oliva), brillo * (1.0 + 0.01), brillo * (1 - calido * 1.4 - oliva * 1.5)], -1)
col = np.clip(col, 0, 1)
alpha = np.ones((R, R, 1))
Image.fromarray((np.concatenate([col, alpha], -1) * 255 + 0.5).astype(np.uint8)).save('color_nuevo.png')

# ---------------------------------------------------------------- 7. salida de alturas y del agua
(h / 0.01).astype(np.float32).tofile('height_nuevo.bin')
# rio: centro cada 4 m con nivel de agua y direccion
idx = np.arange(0, len(cl), 4)
rio = [{'x': float(cl[i, 0]), 'z': float(cl[i, 1]), 's': float(s_cl[i]), 'wl': float(nivel_rio(s_cl[i]))} for i in idx]
json.dump({'w': W_C + 3.0, 'puntos': rio}, open('rio.json', 'w'))
# lago: poligono del agua (un poco afuera de la orilla, en q = 1.10) y linea de paredes (q = 0.95, 1,1 m de hondo)
ang = np.linspace(-np.pi, np.pi, 361)[:-1]
def contorno(qq):
    rr = borde_lago(ang) * qq
    return [{'x': float(LCX + LRX * rr[i] * np.cos(ang[i])), 'z': float(LCZ + LRZ * rr[i] * np.sin(ang[i]))} for i in range(len(ang))]
json.dump({'wl': WL_LAGO, 'agua': contorno(1.10), 'paredes': contorno(0.95), 'centro': [LCX, LCZ]}, open('lago.json', 'w'))
# vistas previas
vis = (h - h.min()) / (h.max() - h.min())
Image.fromarray((vis * 255).astype(np.uint8)).resize((512, 512)).save('height_nuevo_prev.png')
Image.fromarray((splat[..., :3] * 255).astype(np.uint8)).resize((512, 512)).save('splat_prev.png')
print('alturas', round(h.min(), 2), round(h.max(), 2))

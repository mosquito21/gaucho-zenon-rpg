# Paso a Chile (tanda 4): un macizo al sudoeste, al sur del lago Nahuel Huapi, con una quebrada
# que sube hacia el oeste hasta un portezuelo. De paso endereza las lineas de 512 m del mapa,
# que es donde el plugin del terreno dejaba rendijas.
#
# Parte de como estaba el terreno antes del paso (entrada/alturas_antes_del_paso.bin, splat_antes_del_paso.png,
# color_antes_del_paso.png y nodos_antes_del_paso.json), asi que se puede correr las veces que haga falta y
# siempre da lo mismo. Escribe en salida/: height_nuevo.bin, splat_nuevo.png,
# color_nuevo.png, paso.json (el recorrido de la senda y donde va cada arbol, arbusto y roca) y
# paso_prev.png (una vista de control). Como se carga en Godot: ver LEEME.md.
# Grilla: 1025 x 1025, celda 4 m; x = -2048 + 4*col, z = -2048 + 4*fila.
import json, math, os
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from scipy.ndimage import gaussian_filter, sobel

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, '..', '..'))
SALIDA = os.path.join(AQUI, 'salida')
ENTRADA = os.path.join(AQUI, 'entrada')
os.makedirs(SALIDA, exist_ok=True)
R = 1025

# ---------------------------------------------------------------- lo que mas se toca
# La senda: puntos (x, z) de este a oeste. El portezuelo es el punto PORTEZUELO de la lista.
SENDA = [(-1060, 600), (-1150, 680), (-1250, 765), (-1350, 830), (-1440, 870), (-1505, 890), (-1545, 900),
         (-1640, 930), (-1780, 965), (-1920, 985), (-2048, 995)]
PORTEZUELO = 6
ALTO_PORTEZUELO = 100.0      # metros que sube la senda desde el llano hasta el portezuelo
BAJADA_OESTE = 22.0          # lo que baja del otro lado, hacia el borde del mapa
ANCHO_PISO = 7.0             # medio ancho del fondo de la quebrada (lo que se camina comodo)
LADERA = (0.5, 0.0035)       # pendiente de las laderas: lineal y cuanto se empina al alejarse
ALTO_CERROS = 120.0          # relieve de los cerros (cuanto suben los filos y bajan las hondonadas)
FALDA = (0.2, 350.0, 0.07)   # el macizo sube con esta pendiente los primeros metros y despues con la otra
NIEVE_DESDE = 92.0           # altura desde la que aparecen los manchones de nieve (lo usa el juego)
SEMILLA = 1881

h0 = np.fromfile(os.path.join(ENTRADA, 'alturas_antes_del_paso.bin'), dtype=np.float32).reshape(R, R).astype(np.float64) * 0.01
cols = np.arange(R)
X = (-2048.0 + 4.0 * cols)[None, :].repeat(R, 0)
Z = (-2048.0 + 4.0 * cols)[:, None].repeat(R, 1)


def suave01(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def ruido(escala_m, semilla):
    """Ruido suave entre 0 y 1 con manchas de unos escala_m metros."""
    r_ = np.random.default_rng(semilla)
    n = gaussian_filter(r_.normal(size=(R, R)), escala_m / 4.0, mode='wrap')
    return (n - n.min()) / (n.max() - n.min())


# ---------------------------------------------------------------- 1. donde va el macizo
# el lago (misma forma que en terreno.py): no se toca ni el agua ni su playa
LCX, LCZ, LRX, LRZ = -1560.0, -40.0, 480.0, 640.0
rng_lago = np.random.default_rng(3)
armonicos = [(k, rng_lago.uniform(0.02, 0.09) / (1 + 0.15 * k), rng_lago.uniform(0, 2 * np.pi)) for k in range(2, 9)]
th = np.arctan2((Z - LCZ) / LRZ, (X - LCX) / LRX)
borde = 1.0
for k, a, f in armonicos:
    borde = borde + a * np.cos(k * th + f)
q = np.sqrt(((X - LCX) / LRX) ** 2 + ((Z - LCZ) / LRZ) ** 2) / borde
# el macizo ocupa el rincon sudoeste: al oeste de x = -1060 y al sur de z = 540, lejos de la orilla del lago.
# adentro: cuantos metros hay desde el borde del macizo (0 afuera). Los cerros crecen de a poco hacia adentro.
def smin_campo(a, b, k):
    hh = np.clip(k - np.abs(a - b), 0, None) / k
    return np.minimum(a, b) - hh * hh * k * 0.25


# el frente del macizo no es una linea recta: entra y sale unos 150 m
ondas = (ruido(260, SEMILLA + 9) - 0.5) * 300.0
adentro = smin_campo(smin_campo(-1060.0 - X + ondas, Z - 540.0 + ondas * 0.6, 160.0), (q - 1.08) * 520.0, 160.0)
# pero cerca de lo que ya esta armado (campamento, fortin nuevo, bosque del lago) no se toca nada
adentro = np.minimum(adentro, np.maximum(-1140.0 - X, Z - 520.0))
adentro = np.clip(adentro, 0, None)
macizo = suave01(adentro / 60.0)

# ---------------------------------------------------------------- 2. los cerros
falda = FALDA[0] * np.minimum(adentro, FALDA[1]) + FALDA[2] * np.clip(adentro - FALDA[1], 0, None)
filos = np.zeros((R, R))
for escala, peso, semilla in ((380, 1.0, 1), (170, 0.55, 2), (70, 0.3, 3), (32, 0.13, 4)):
    filos += peso * (1.0 - np.abs(2.0 * ruido(escala, SEMILLA + semilla) - 1.0))
filos = np.clip((filos / 1.98 - 0.5) / 0.36, -0.45, 1.15)
cerros = np.clip(falda + ALTO_CERROS * (0.3 + 0.7 * suave01(adentro / 450.0)) * filos * suave01(adentro / 90.0), 0, None) * macizo

# ---------------------------------------------------------------- 3. la senda y la quebrada
def catmull(p, paso=1.0):
    p = np.array(p, float)
    p = np.vstack([p[0] * 2 - p[1], p, p[-1] * 2 - p[-2]])
    out, marcas = [], [0]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        n = max(2, int(np.linalg.norm(p2 - p1) / paso))
        for k in range(n):
            tt = k / n
            t2, t3 = tt * tt, tt * tt * tt
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * tt + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
        marcas.append(len(out))
    out.append(p[-2])
    return np.array(out), marcas


eje, marcas = catmull(SENDA, 1.0)
s_eje = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(eje, axis=0), axis=1))])
s_portezuelo = s_eje[marcas[PORTEZUELO]]
print('senda: %d m hasta el portezuelo, %d m en total' % (s_portezuelo, s_eje[-1]))
# perfil del fondo: arranca al ras del llano, sube parejo y se aplana en el portezuelo; despues baja un poco
c0, r0 = int(round((SENDA[0][0] + 2048) / 4)), int(round((SENDA[0][1] + 2048) / 4))
alto_boca = float(h0[r0, c0])
t = np.clip(s_eje / s_portezuelo, 0, 1)
sube = alto_boca + ALTO_PORTEZUELO * (0.62 * t + 0.38 * (0.5 - 0.5 * np.cos(np.pi * t)))
u = np.clip((s_eje - s_portezuelo) / (s_eje[-1] - s_portezuelo), 0, 1)
fondo_eje = np.where(s_eje <= s_portezuelo, sube, alto_boca + ALTO_PORTEZUELO - BAJADA_OESTE * suave01(u * 1.6))
pend = np.diff(fondo_eje) / np.diff(s_eje)
print('pendiente de la senda: maxima %.0f %%, media %.0f %%' % (pend.max() * 100, 100 * ALTO_PORTEZUELO / s_portezuelo))

arbol = cKDTree(eje)
d_senda, i_senda = arbol.query(np.stack([X.ravel(), Z.ravel()], -1))
d_senda = d_senda.reshape(R, R)
i_senda = i_senda.reshape(R, R)
fondo = fondo_eje[i_senda]
lejos = np.clip(d_senda - ANCHO_PISO, 0, None)
quebrada = fondo + LADERA[0] * lejos + LADERA[1] * lejos * lejos


def smin(a, b, k):
    hh = np.clip(k - np.abs(a - b), 0, None) / k
    return np.minimum(a, b) - hh * hh * k * 0.25


h = h0 + cerros
# a los dos lados de la senda el terreno sube por lo menos esto (FILO_LADOS metros a unos 80 m de la senda),
# asi del lado del lago tambien hay un filo y la senda va por una quebrada, no por una ladera
FILO_LADOS = 34.0
abre = suave01(s_eje[i_senda] / 170.0)                       # la boca de la quebrada se abre al llano
zona = (1.0 - suave01((lejos - 105.0) / 95.0)) * abre * suave01((q - 1.06) / 0.14) * suave01(macizo / 0.15)
lomo = FILO_LADOS * suave01(lejos / 78.0) * zona * (1.0 + 0.5 * (ruido(60, SEMILLA + 21) - 0.5))
# dentro de la zona el piso queda por lo menos a la altura de la senda mas el lomo; afuera no cambia
h = h + np.clip(zona * (fondo - h) + lomo, 0, None)
# la quebrada corta los cerros; fuera del macizo no hace nada (ahi el piso ya esta mas bajo que ella)
corte = suave01(macizo / 0.04)
h = h * (1 - corte) + smin(h, quebrada, 6.0) * corte
h = np.where(macizo > 0.002, gaussian_filter(h, 0.8), h)
# el borde del macizo se cose con el llano sin escalon
cose = suave01(macizo / 0.02)
h = h0 * (1 - cose) + h * cose

# ---------------------------------------------------------------- 4. rendijas: lineas de 512 m rectas por tramos
# El plugin dibuja el piso en baldosas; donde una detallada toca a una simplificada sobre una linea de
# 512 m quedaba una rendija. Si sobre esas lineas la altura es recta por tramos de 4 celdas (16 m),
# las dos baldosas coinciden y no hay rendija.
h_antes = h.copy()
indices = np.arange(R)
for k in range(0, R, 128):
    for fila in (True, False):
        linea = h[k, :] if fila else h[:, k]
        nueva = np.interp(indices, indices[::4], linea[::4])
        if fila:
            h[k, :] = nueva
        else:
            h[:, k] = nueva
print('lineas de 512 m: cambio mayor %.2f m, medio %.3f m' % (np.abs(h - h_antes).max(), np.abs(h - h_antes)[::128, :].mean()))

cambio = np.abs(h - h0)
print('alturas: de %.1f a %.1f m; celdas cambiadas %d' % (h.min(), h.max(), int((cambio > 0.005).sum())))
nodos = json.load(open(os.path.join(ENTRADA, 'nodos_antes_del_paso.json')))
movidos = []
for n in nodos:
    fx, fz = (n['x'] + 2048) / 4, (n['z'] + 2048) / 4
    c, r = int(fx), int(fz)
    if 0 <= c < R - 1 and 0 <= r < R - 1:
        ax, az = fx - c, fz - r
        dif = h - h0
        d = (dif[r, c] * (1 - ax) + dif[r, c + 1] * ax) * (1 - az) + (dif[r + 1, c] * (1 - ax) + dif[r + 1, c + 1] * ax) * az
        if abs(d) > 0.02:
            movidos.append({'n': n['n'], 'dy': round(float(d), 3)})
print('nodos de la escena con el piso movido mas de 2 cm:', len(movidos))
json.dump(movidos, open(os.path.join(SALIDA, 'nodos_movidos.json'), 'w'), indent=0)

# ---------------------------------------------------------------- 5. suelos (R estepa, G tierra, B vega, A canto)
splat = np.asarray(Image.open(os.path.join(ENTRADA, 'splat_antes_del_paso.png')).convert('RGBA'), dtype=np.float64) / 255.0
gy = sobel(h, 0) / (8 * 4.0)
gx = sobel(h, 1) / (8 * 4.0)
pendiente = np.sqrt(gx * gx + gy * gy)
en = suave01(macizo / 0.08)
roca = suave01((pendiente - 0.4) / 0.28)                        # ladera empinada: piedra suelta
alta = suave01((h - (NIEVE_DESDE - 18)) / 30.0) * 0.55           # arriba, mas piedra y menos pasto
senda_px = suave01((3.2 - d_senda) / 2.0) * suave01((s_eje[-1] - 60 - s_eje[i_senda]) / 40.0)
mallin = suave01((ANCHO_PISO + 5 - d_senda) / 6.0) * (0.45 + 0.4 * ruido(24, 71)) * (1 - senda_px)
claro = (0.25 + 0.5 * ruido(55, 72)) * suave01((0.45 - pendiente) / 0.2)   # manchones de tierra bajo el bosque
canto_m = np.clip(np.maximum(roca, alta * (0.4 + 0.6 * ruido(30, 73))), 0, 1)
tierra_m = np.clip(np.maximum(senda_px * 0.95, claro * 0.35 * (1 - canto_m)), 0, 1)
vega_m = np.clip(mallin * (1 - canto_m) * (1 - senda_px), 0, 1)
estepa_m = np.clip(1 - canto_m - tierra_m - vega_m, 0, 1)
nuevo = np.stack([estepa_m, tierra_m, vega_m, canto_m], -1)
nuevo /= nuevo.sum(-1, keepdims=True) + 1e-6
splat = splat * (1 - en[..., None]) + nuevo * en[..., None]
# un rastro de tierra pisada desde el fortin nuevo hasta la boca de la quebrada
rastro = np.array([(-930, 452), (-975, 505), (-1020, 560), SENDA[0]], float)
pts = np.concatenate([rastro[i] + (rastro[i + 1] - rastro[i]) * np.linspace(0, 1, 60)[:, None] for i in range(len(rastro) - 1)])
d_rastro = cKDTree(pts).query(np.stack([X.ravel(), Z.ravel()], -1))[0].reshape(R, R)
pisada = suave01((3.5 - d_rastro) / 2.5) * 0.7 * (1 - en)
splat = splat * (1 - pisada[..., None]) + np.array([0.0, 1.0, 0.0, 0.0]) * pisada[..., None]
Image.fromarray((np.clip(splat, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(SALIDA, 'splat_nuevo.png'))

# ---------------------------------------------------------------- 6. color: el bosque de lejos y la roca
color = np.asarray(Image.open(os.path.join(ENTRADA, 'color_antes_del_paso.png')).convert('RGBA'), dtype=np.float64) / 255.0
bosque_lejos = en * suave01((d_senda - 150) / 120.0) * suave01((NIEVE_DESDE + 25 - h) / 40.0) * suave01((0.75 - pendiente) / 0.3)
bosque_lejos *= 0.35 + 0.65 * ruido(70, 81)
tinte_bosque = np.array([0.50, 0.42, 0.30])        # ocres y rojizos de lenga, vistos de lejos
tinte_roca = np.array([0.6, 0.58, 0.58])
rgb = color[..., :3]
rgb = rgb * (1 - bosque_lejos[..., None]) + rgb * tinte_bosque / 0.8 * bosque_lejos[..., None]
piedra = (en * canto_m)[..., None]
rgb = rgb * (1 - piedra) + rgb * tinte_roca * piedra
manchas = 1.0 - en[..., None] * 0.22 * ruido(110, 82)[..., None] - en[..., None] * 0.1 * ruido(26, 83)[..., None]
color[..., :3] = np.clip(rgb * manchas, 0, 1)
Image.fromarray((color * 255 + 0.5).astype(np.uint8)).save(os.path.join(SALIDA, 'color_nuevo.png'))

# ---------------------------------------------------------------- 7. que se planta y donde
rng = np.random.default_rng(SEMILLA)


def altura(x, z):
    fx, fz = (x + 2048) / 4, (z + 2048) / 4
    c, r = min(int(fx), R - 2), min(int(fz), R - 2)
    ax, az = fx - c, fz - r
    return float((h[r, c] * (1 - ax) + h[r, c + 1] * ax) * (1 - az) + (h[r + 1, c] * (1 - ax) + h[r + 1, c + 1] * ax) * az)


def celda(x, z):
    return min(R - 1, max(0, int(round((z + 2048) / 4)))), min(R - 1, max(0, int(round((x + 2048) / 4))))


plantas, puestos = [], []


def plantar(tipo, x, z, escala, separa):
    if any((x - px) ** 2 + (z - pz) ** 2 < max(separa, ps) ** 2 for px, pz, ps in puestos):
        return False
    puestos.append((x, z, separa))
    plantas.append({'tipo': tipo, 'x': round(float(x), 2), 'y': round(altura(x, z), 2), 'z': round(float(z), 2),
                    'giro': round(float(rng.uniform(0, 360)), 1), 'escala': round(float(escala), 2)})
    return True


intentos = 0
while len(plantas) < 270 and intentos < 120000:
    intentos += 1
    i = int(rng.integers(0, marcas[PORTEZUELO] + 140))
    lado = rng.choice([-1.0, 1.0])
    dist = ANCHO_PISO + 2.0 + abs(rng.normal(0, 42.0))
    tang = eje[min(i + 1, len(eje) - 1)] - eje[max(i - 1, 0)]
    normal = np.array([-tang[1], tang[0]]) / (np.linalg.norm(tang) + 1e-9)
    x, z = eje[i] + normal * lado * dist
    if x < -2000 or dist > 190:
        continue
    r, c = celda(x, z)
    if macizo[r, c] < 0.06 or d_senda[r, c] < ANCHO_PISO + 1.5:
        continue
    sobre_fondo = h[r, c] - fondo[r, c]
    p, alto = pendiente[r, c], h[r, c]
    azar = rng.random()
    if p > 0.8:                                # ladera empinada: alguna barda de roca y nada mas
        if azar < 0.25 and sum(1 for q_ in plantas if q_['tipo'].startswith('barda')) < 10:
            plantar('barda_a' if rng.random() < 0.5 else 'barda_b', x, z, rng.uniform(0.8, 1.3), 16.0)
        continue
    if alto > NIEVE_DESDE + 6:                 # arriba: ñire achaparrado, rocas y matas (pocos)
        if azar > 0.45:
            continue
        tipo = rng.choice(['nire_d', 'nire_d', 'roca_a', 'roca_b', 'matorral_barda_b', 'calafate_b'])
        plantar(tipo, x, z, rng.uniform(0.7, 1.1), 8.0)
    elif azar < 0.7:                           # bosque de lenga, mas alto abajo
        tipo = rng.choice(['lenga_c', 'lenga_c', 'lenga_d', 'lenga_a', 'lenga_b'])
        plantar(tipo, x, z, rng.uniform(0.85, 1.3) * (1.0 - 0.25 * suave01((alto - 55) / 40.0)), 4.5)
    elif azar < 0.84:
        plantar(rng.choice(['nire_c', 'nire_a', 'nire_b']), x, z, rng.uniform(0.8, 1.15), 4.5)
    elif azar < 0.94:
        plantar(rng.choice(['calafate_a', 'calafate_b', 'matorral_a', 'matorral_b', 'matorral_barda_a']), x, z, rng.uniform(0.8, 1.2), 3.0)
    else:
        plantar(rng.choice(['roca_a', 'roca_b', 'roca_c']), x, z, rng.uniform(0.6, 1.3), 4.0)
cuenta = {}
for p_ in plantas:
    cuenta[p_['tipo']] = cuenta.get(p_['tipo'], 0) + 1
print('plantas y rocas:', len(plantas), dict(sorted(cuenta.items())))

paso_senda = [{'x': round(float(eje[i, 0]), 1), 'z': round(float(eje[i, 1]), 1), 'y': round(float(fondo_eje[i]), 2), 's': round(float(s_eje[i]), 1)}
              for i in range(0, len(eje), 10)]
json.dump({'senda': paso_senda, 'portezuelo': {'x': SENDA[PORTEZUELO][0], 'z': SENDA[PORTEZUELO][1], 'y': round(float(alto_boca + ALTO_PORTEZUELO), 2)},
           'nieve_desde': NIEVE_DESDE, 'plantas': plantas}, open(os.path.join(SALIDA, 'paso.json'), 'w'))

# ---------------------------------------------------------------- 8. salida de alturas y vista de control
(h / 0.01).astype(np.float32).tofile(os.path.join(SALIDA, 'height_nuevo.bin'))
r_a, r_b, c_a, c_b = 600, 1025, 0, 300          # el rincon sudoeste
nx, nz = -gx[r_a:r_b, c_a:c_b], -gy[r_a:r_b, c_a:c_b]
largo = np.sqrt(nx * nx + nz * nz + 1.0)
luz = np.clip((nx * -0.5 + 0.7 + nz * -0.5) / largo / 0.7, 0.25, 1.3)
vista = splat[r_a:r_b, c_a:c_b, :3] @ np.array([[0.62, 0.58, 0.38], [0.5, 0.42, 0.33], [0.42, 0.5, 0.28]]) + splat[r_a:r_b, c_a:c_b, 3:4] * 0.55
vista = np.clip(vista * color[r_a:r_b, c_a:c_b, :3] * luz[..., None], 0, 1)
nevado = suave01((h[r_a:r_b, c_a:c_b] - NIEVE_DESDE) / 60.0)[..., None] * 0.6
vista = vista * (1 - nevado) + nevado
im = Image.fromarray((vista * 255).astype(np.uint8)).resize((900, 1275), Image.BILINEAR)
from PIL import ImageDraw
dib = ImageDraw.Draw(im)
for p_ in plantas:
    px, pz = ((p_['x'] + 2048) / 4 - c_a) * 3, ((p_['z'] + 2048) / 4 - r_a) * 3
    dib.ellipse([px - 2, pz - 2, px + 2, pz + 2], fill=(200, 60, 30) if 'lenga' in p_['tipo'] or 'nire' in p_['tipo'] else (40, 40, 40))
for a, b in zip(paso_senda[:-1], paso_senda[1:]):
    dib.line([((a['x'] + 2048) / 4 - c_a) * 3, ((a['z'] + 2048) / 4 - r_a) * 3, ((b['x'] + 2048) / 4 - c_a) * 3, ((b['z'] + 2048) / 4 - r_a) * 3], fill=(255, 255, 0), width=1)
im.save(os.path.join(SALIDA, 'paso_prev.png'))
print('listo')

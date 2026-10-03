# Mallas de agua: el rio (cinta que sigue el cauce, con la direccion del agua en el color de vertice)
# y el lago (abanico desde el centro hasta un poco mas alla de la orilla). Salida JSON para Godot.
import json, math
import numpy as np
import os
AQUI = os.path.dirname(os.path.abspath(__file__))
ENTRADA = os.path.join(AQUI, 'entrada')
SALIDA = os.path.join(AQUI, 'salida')
os.makedirs(SALIDA, exist_ok=True)
os.chdir(SALIDA)                  # todo lo que se escribe queda en salida/

rio = json.load(open('rio.json'))
lago = json.load(open('lago.json'))
LCX, LCZ, LRX, LRZ = -1560.0, -40.0, 480.0, 640.0
rng = np.random.default_rng(3)
armonicos = [(k, rng.uniform(0.02, 0.09) / (1 + 0.15 * k), rng.uniform(0, 2 * np.pi)) for k in range(2, 9)]


def q_lago(x, z):
    th = math.atan2((z - LCZ) / LRZ, (x - LCX) / LRX)
    b = 1.0 + sum(a * math.cos(k * th + f) for k, a, f in armonicos)
    return math.sqrt(((x - LCX) / LRX) ** 2 + ((z - LCZ) / LRZ) ** 2) / b


# ---------------------------------------------------------------- rio
# La cinta del rio arranca justo donde termina la malla del lago (q = 1.10): la primera fila se apoya sobre
# ese borde, asi las dos aguas no se enciman (encimadas se veia una mancha mas oscura).
Q_LAGO = 1.10
FLUJO_LAGO = (0.53, 0.51)
W = rio['w']
across = [-1.0, -0.5, 0.0, 0.5, 1.0]
todos = rio['puntos']


def marco(lista, i):
    a = lista[max(0, i - 1)]
    b = lista[min(len(lista) - 1, i + 1)]
    tx, tz = b['x'] - a['x'], b['z'] - a['z']
    L = math.hypot(tx, tz) or 1.0
    return tx / L, tz / L


# primera fila con los cinco vertices afuera del lago
i1 = 0
for i in range(len(todos)):
    tx, tz = marco(todos, i)
    p = todos[i]
    if all(q_lago(p['x'] - tz * W * f, p['z'] + tx * W * f) >= Q_LAGO + 0.004 for f in across):
        i1 = i
        break
pts = todos[i1:]
n = len(pts)
s0 = pts[0]['s']
WL_LAGO = lago['wl']
verts, uvs, cols, idx = [], [], [], []
# fila apoyada en el borde del lago: cada vertice se corre hacia atras (contra la corriente) hasta q = 1.10
tx, tz = marco(pts, 0)
nx, nz = -tz, tx
for f in across:
    x0, z0 = pts[0]['x'] + nx * W * f, pts[0]['z'] + nz * W * f
    lo, hi = -80.0, 0.0                     # lo: adentro del lago, hi: afuera
    for _ in range(50):
        mid = 0.5 * (lo + hi)
        if q_lago(x0 + tx * mid, z0 + tz * mid) >= Q_LAGO:
            hi = mid
        else:
            lo = mid
    verts.append([x0 + tx * hi, WL_LAGO, z0 + tz * hi])
    uvs.append([0.0, (f + 1) * W / 12.0])
    cols.append([FLUJO_LAGO[0], FLUJO_LAGO[1], 0.0, 1.0])
# el resto: nivel y direccion del agua pasan de los del lago a los del rio en los primeros 40 m
for i, p in enumerate(pts):
    tx, tz = marco(pts, i)
    nx, nz = -tz, tx
    k = min(1.0, (p['s'] - s0) / 40.0)
    k = k * k * (3 - 2 * k)
    nivel = WL_LAGO + (p['wl'] - WL_LAGO) * k
    fx = FLUJO_LAGO[0] + (tx * 0.5 + 0.5 - FLUJO_LAGO[0]) * k
    fz = FLUJO_LAGO[1] + (tz * 0.5 + 0.5 - FLUJO_LAGO[1]) * k
    for f in across:
        verts.append([p['x'] + nx * W * f, nivel, p['z'] + nz * W * f])
        uvs.append([p['s'] / 12.0, (f + 1) * W / 12.0])
        cols.append([fx, fz, 0.0, 1.0])
n += 1
m = len(across)
for i in range(n - 1):
    for k in range(m - 1):
        a0 = i * m + k
        a1 = a0 + 1
        b0 = a0 + m
        b1 = b0 + 1
        idx += [a0, b0, a1, a1, b0, b1]
json.dump({'v': verts, 'uv': uvs, 'c': cols, 'i': idx}, open('malla_rio.json', 'w'))
print('rio: puntos', n, 'vertices', len(verts), 'triangulos', len(idx) // 3, 'nivel', round(pts[0]['wl'], 3), '->', round(pts[-1]['wl'], 3))

# ---------------------------------------------------------------- lago (abanico, con dos anillos intermedios)
wl = lago['wl']
borde = lago['agua']
cx, cz = lago['centro']
verts, uvs, cols, idx = [[cx, wl, cz]], [[cx / 25.0, cz / 25.0]], [[0.5, 0.5, 0.0, 1.0]], []
anillos = [0.33, 0.66, 1.0]
nb = len(borde)
for r in anillos:
    for p in borde:
        x = cx + (p['x'] - cx) * r
        z = cz + (p['z'] - cz) * r
        verts.append([x, wl, z])
        uvs.append([x / 25.0, z / 25.0])
        cols.append([0.53, 0.51, 0.0, 1.0])       # deriva muy lenta hacia el este
for j in range(nb):
    idx += [0, 1 + j, 1 + (j + 1) % nb]          # orden que Godot ve de frente desde arriba
for a in range(len(anillos) - 1):
    o0 = 1 + a * nb
    o1 = 1 + (a + 1) * nb
    for j in range(nb):
        j2 = (j + 1) % nb
        idx += [o0 + j, o1 + j, o0 + j2, o1 + j, o1 + j2, o0 + j2]
paredes = lago['paredes']
json.dump({'v': verts, 'uv': uvs, 'c': cols, 'i': idx, 'paredes': [[p['x'], p['z']] for p in paredes], 'wl': wl}, open('malla_lago.json', 'w'))
print('lago: vertices', len(verts), 'triangulos', len(idx) // 3)

# La aguada del cerro (tanda 6): un ojo de agua con su vega entre el Mojon del Cerro y la tolderia, y
# una loma debajo del mojon, para que desde arriba se vea la aguada y, mas alla, los toldos (es lo que
# dicen los textos de la historia).
#
# Parte de como estaba el terreno justo antes (entrada/alturas_antes_de_la_aguada.bin,
# splat_antes_de_la_aguada.png y color_antes_de_la_aguada.png), asi que se puede correr las veces que
# haga falta y siempre da lo mismo. Escribe en salida/: height_nuevo.bin, normal_nuevo.png, splat_nuevo.png,
# color_nuevo.png, aguada.json (nivel y borde del agua, donde van los juncos y los senderos de la
# hacienda) y aguada_prev.png (vista de control). Tambien pinta assets/terreno/huellas_hacienda.png,
# el barro pisoteado de los senderos. Como se carga en Godot: ver LEEME.md.
# Grilla: 1025 x 1025, celda 4 m; x = -2048 + 4*col, z = -2048 + 4*fila.
import json, math, os
import numpy as np
from PIL import Image

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, '..', '..'))
SALIDA = os.path.join(AQUI, 'salida')
ENTRADA = os.path.join(AQUI, 'entrada')
os.makedirs(SALIDA, exist_ok=True)
R = 1025

# ---------------------------------------------------------------- lo que mas se toca
AGUADA = (-105.0, 240.0)     # centro del ojo de agua (queda en la linea que va del mojon a la tolderia)
RADIOS = (15.0, 11.0)        # medio largo y medio ancho del agua, en metros
GIRO = 25.0                  # cuanto esta girado el ovalo, en grados
LOBULO = (9.0, -5.0, 8.0)    # un segundo ojo pegado al primero: corrimiento (x, z) y radio
HONDO = 1.15                 # hondura del pozo en el medio, en metros
BAJO_EL_BORDE = 0.32         # el agua queda esto por debajo del suelo de alrededor
VEGA = 2.3                   # hasta donde llega el pasto verde, en "radios" del pozo
MOJON = (40.0, 320.0)        # la loma va debajo del Mojon del Cerro
ALTO_LOMA = 8.0              # metros que sube
RADIO_LOMA = 74.0            # hasta donde llega la falda
CIMA_LOMA = 6.0              # radio de la parte llana de arriba
# Los senderos de la hacienda salen de la orilla hacia: la tolderia, la estancia y el fortin.
RUMBOS = [((-430.0, 60.0), 62.0), ((-170.0, -250.0), 48.0), ((240.0, 160.0), 42.0)]
SEMILLA = 1881

h = np.fromfile(os.path.join(ENTRADA, 'alturas_antes_de_la_aguada.bin'), dtype=np.float32).reshape(R, R).astype(np.float64) * 0.01
ejes = -2048.0 + 4.0 * np.arange(R)
X = ejes[None, :].repeat(R, 0)
Z = ejes[:, None].repeat(R, 1)
rng = np.random.default_rng(SEMILLA)


def suave01(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def ondas(x, z, largo, semilla):
    """Ruido suave entre -1 y 1 (suma de ondas), con manchas de unos `largo` metros."""
    r_ = np.random.default_rng(semilla)
    total = 0.0
    for k in range(5):
        ang = r_.uniform(0, 2 * math.pi)
        f = 2 * math.pi / (largo * r_.uniform(0.6, 1.6))
        total = total + np.sin((x * math.cos(ang) + z * math.sin(ang)) * f + r_.uniform(0, 2 * math.pi))
    return total / 5.0


def q_pozo(x, z):
    """Distancia al pozo en 'radios': 0 en el medio, 1 en el borde del hueco (algo mas afuera que el agua)."""
    c, s = math.cos(math.radians(GIRO)), math.sin(math.radians(GIRO))
    dx, dz = x - AGUADA[0], z - AGUADA[1]
    u, v = dx * c + dz * s, -dx * s + dz * c
    q1 = np.sqrt((u / (RADIOS[0] * 1.5)) ** 2 + (v / (RADIOS[1] * 1.5)) ** 2)
    q2 = np.sqrt((dx - LOBULO[0]) ** 2 + (dz - LOBULO[1]) ** 2) / (LOBULO[2] * 1.5)
    # union suave de los dos ojos, con el borde apenas desparejo
    k = 0.35
    m = np.clip(0.5 + 0.5 * (q2 - q1) / k, 0, 1)
    return (q2 * (1 - m) + q1 * m - k * m * (1 - m)) * (1.0 + 0.1 * ondas(x, z, 16.0, SEMILLA + 3))


# ---------------------------------------------------------------- 1. la loma del mojon
d_mojon = np.sqrt((X - MOJON[0]) ** 2 + (Z - MOJON[1]) ** 2)
t = np.clip((d_mojon - CIMA_LOMA) / (RADIO_LOMA - CIMA_LOMA), 0, 1)
loma = ALTO_LOMA * (1 + np.cos(math.pi * t)) / 2.0
loma *= 1.0 + 0.05 * ondas(X, Z, 38.0, SEMILLA + 1) * suave01(t / 0.25)      # la falda, apenas despareja; la cima, llana
h1 = h + loma

# ---------------------------------------------------------------- 2. el pozo de la aguada
q = q_pozo(X, Z)
anillo = (q > 1.1) & (q < 1.5)
base = float(h[anillo].mean())                                 # el suelo de alrededor
empareja = suave01((2.0 - q) / 0.8)                            # cerca del agua el suelo queda parejo: la orilla sale limpia
h2 = h1 * (1 - empareja) + base * empareja
h2 -= HONDO * (1 + np.cos(math.pi * np.clip(q, 0, 1))) / 2.0
nivel = base - BAJO_EL_BORDE
print('aguada: suelo de alrededor %.2f m, nivel del agua %.2f m, fondo %.2f m' % (base, nivel, h2[q < 0.2].min()))
agua = (h2 < nivel) & (q < 1.2)
print('agua: %d celdas (unos %d m2)' % (int(agua.sum()), int(agua.sum()) * 16))

# ---------------------------------------------------------------- 3. suelos (R estepa, G tierra, B vega, A canto)
splat = np.asarray(Image.open(os.path.join(ENTRADA, 'splat_antes_de_la_aguada.png')).convert('RGBA'), dtype=np.float64) / 255.0
borde_vega = VEGA * (1.0 + 0.22 * ondas(X, Z, 30.0, SEMILLA + 5))
vega_m = suave01((borde_vega - q) / 0.7)
ang = np.arctan2(Z - AGUADA[1], X - AGUADA[0])
# donde abreva la hacienda: tres sectores de la orilla, hacia donde salen los senderos
barro = np.zeros_like(q)
for destino, _largo in RUMBOS:
    a0 = math.atan2(destino[1] - AGUADA[1], destino[0] - AGUADA[0])
    dif = np.abs(np.angle(np.exp(1j * (ang - a0))))
    barro = np.maximum(barro, suave01((0.75 - dif) / 0.4))
barro *= suave01((q - 0.5) / 0.12) * suave01((1.45 - q) / 0.3)
fondo = suave01((0.62 - q) / 0.1)
canto_m = np.clip(suave01((0.74 - q) / 0.06) * suave01((q - 0.52) / 0.06) * 0.55 + fondo * 0.35, 0, 1)
tierra_m = np.clip(np.maximum(barro * 0.8, fondo * 0.6), 0, 1) * (1 - canto_m)
vega_ok = np.clip(vega_m * (1 - tierra_m) * (1 - canto_m), 0, 1)
nuevo = np.stack([np.clip(1 - canto_m - tierra_m - vega_ok, 0, 1), tierra_m, vega_ok, canto_m], -1)
nuevo /= nuevo.sum(-1, keepdims=True) + 1e-6
en = np.clip(np.maximum(vega_m, fondo), 0, 1)
splat = splat * (1 - en[..., None]) + nuevo * en[..., None]
# en la falda de la loma, algo de piedra suelta donde mas empina
gz, gx = np.gradient(h2, 4.0)
pendiente = np.sqrt(gx * gx + gz * gz)
piedra = suave01((pendiente - 0.11) / 0.07) * suave01((RADIO_LOMA - d_mojon) / 10.0) * (0.3 + 0.25 * (ondas(X, Z, 14.0, SEMILLA + 7) + 1) / 2)
splat = splat * (1 - piedra[..., None]) + np.array([0.0, 0.0, 0.0, 1.0]) * piedra[..., None]
Image.fromarray((np.clip(splat, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(SALIDA, 'splat_nuevo.png'))

# ---------------------------------------------------------------- 4. color: la vega, mas verde y mas oscura
color = np.asarray(Image.open(os.path.join(ENTRADA, 'color_antes_de_la_aguada.png')).convert('RGBA'), dtype=np.float64) / 255.0
tinte = np.array([0.86, 0.97, 0.8])
color[..., :3] = np.clip(color[..., :3] * (1 - vega_ok[..., None]) + color[..., :3] * tinte * vega_ok[..., None], 0, 1)
Image.fromarray((color * 255 + 0.5).astype(np.uint8)).save(os.path.join(SALIDA, 'color_nuevo.png'))

# ---------------------------------------------------------------- 5. el borde del agua, los juncos y los senderos
def q_punto(x, z):
    return float(q_pozo(np.array([[x]]), np.array([[z]]))[0, 0])


def alto(x, z):
    """Altura del piso nuevo en un punto, como la dibuja el juego (dos triangulos por celda, diagonal 10-01)."""
    c = (x + 2048.0) / 4.0
    f = (z + 2048.0) / 4.0
    c0, f0 = int(math.floor(c)), int(math.floor(f))
    fx, fz = c - c0, f - f0
    h00, h10, h01, h11 = h2[f0, c0], h2[f0, c0 + 1], h2[f0 + 1, c0], h2[f0 + 1, c0 + 1]
    if fx + fz <= 1.0:
        return h00 + (h10 - h00) * fx + (h01 - h00) * fz
    return h11 + (h01 - h11) * (1 - fx) + (h10 - h11) * (1 - fz)


def radio_hasta(a, q_meta):
    """A que distancia del centro, hacia ese angulo, el pozo llega a q_meta."""
    lo, hi = 0.0, 80.0
    for _ in range(40):
        mid = (lo + hi) / 2
        if q_punto(AGUADA[0] + math.cos(a) * mid, AGUADA[1] + math.sin(a) * mid) < q_meta:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


# La malla del agua llega un poco mas alla de la orilla (el resto queda tapado por el piso).
borde = []
for i in range(48):
    a = 2 * math.pi * i / 48
    r_ = radio_hasta(a, 0.95)
    borde.append([round(AGUADA[0] + math.cos(a) * r_, 2), round(AGUADA[1] + math.sin(a) * r_, 2)])

# La orilla de verdad: donde el piso cruza el nivel del agua.
def radio_orilla(a):
    lo, hi = 0.0, 60.0
    for _ in range(40):
        mid = (lo + hi) / 2
        if alto(AGUADA[0] + math.cos(a) * mid, AGUADA[1] + math.sin(a) * mid) < nivel:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


juncos = []
for i in range(22):
    a = 2 * math.pi * (i + rng.uniform(-0.3, 0.3)) / 22
    # menos juncos donde abreva la hacienda (ahi esta pisado)
    pisado = any(abs(math.remainder(a - math.atan2(d[1] - AGUADA[1], d[0] - AGUADA[0]), 2 * math.pi)) < 0.5 for d, _ in RUMBOS)
    if pisado and rng.uniform() < 0.75:
        continue
    r_ = radio_orilla(a) + rng.uniform(-1.6, 0.6)
    x, z = AGUADA[0] + math.cos(a) * r_, AGUADA[1] + math.sin(a) * r_
    juncos.append({'x': round(x, 2), 'z': round(z, 2), 'y': round(float(alto(x, z)), 3), 'giro': round(float(rng.uniform(0, 360)), 1),
                   'escala': round(float(rng.uniform(0.8, 1.3)), 2)})

senderos = []
for destino, largo in RUMBOS:
    a = math.atan2(destino[1] - AGUADA[1], destino[0] - AGUADA[0])
    r0 = radio_orilla(a) + 1.0
    puntos = []
    n = int(largo / 3.0)
    desvio = rng.uniform(-0.25, 0.25)
    for k in range(n + 1):
        s = r0 + largo * k / n
        tuerce = 2.2 * math.sin(k / n * math.pi * 1.5 + desvio * 6) * (k / n)      # el sendero no va a regla
        x = AGUADA[0] + math.cos(a) * s - math.sin(a) * tuerce
        z = AGUADA[1] + math.sin(a) * s + math.cos(a) * tuerce
        puntos.append([round(x, 2), round(float(alto(x, z)), 3), round(z, 2)])
    senderos.append(puntos)

json.dump({'centro': list(AGUADA), 'nivel': round(nivel, 3), 'suelo': round(base, 3), 'borde': borde, 'juncos': juncos,
           'senderos': senderos, 'mojon': {'x': MOJON[0], 'z': MOJON[1], 'y': round(float(alto(MOJON[0], MOJON[1])), 3)},
           'zonas': [[MOJON[0], MOJON[1], RADIO_LOMA + 4], [AGUADA[0], AGUADA[1], max(RADIOS) * 1.5 * 2.1]]},
          open(os.path.join(SALIDA, 'aguada.json'), 'w'), indent=0)
print('juncos %d, senderos %s puntos, mojon a %.2f m de alto' % (len(juncos), [len(s) for s in senderos], alto(MOJON[0], MOJON[1])))
print('pendiente mas fuerte de la loma: %.0f %%' % (100 * pendiente[d_mojon < RADIO_LOMA].max()))

# ---------------------------------------------------------------- 6. el barro pisoteado de los senderos
def pintar_huellas():
    w, alto_px = 256, 1024
    r_ = np.random.default_rng(SEMILLA + 11)
    yy, xx = np.mgrid[0:alto_px, 0:w].astype(np.float64)
    u = (xx - w / 2) / (w / 2)
    # el barro: mas tapado en el medio, se pierde hacia los costados, con manchones
    manchas = 0.5 + 0.5 * np.sin(yy / alto_px * 2 * math.pi * 3 + np.sin(xx / 40.0) * 1.5) * np.sin(xx / w * math.pi * 2.3 + 1.0)
    alfa = np.clip(1.0 - np.abs(u) ** 1.6, 0, 1) ** 1.3 * (0.42 + 0.2 * manchas)
    rgb = np.zeros((alto_px, w, 3)) + np.array([0.33, 0.27, 0.2])
    rgb *= (0.9 + 0.1 * manchas)[..., None]
    # pisadas: medias lunas oscuras, de a pares (la pezuña partida), yendo y viniendo
    for _ in range(190):
        cx = w / 2 + r_.normal(0, w * 0.2)
        cy = r_.uniform(0, alto_px)
        giro = r_.choice([0.0, math.pi]) + r_.normal(0, 0.35)
        tam = r_.uniform(7.0, 10.5)
        for lado in (-1, 1):
            # todo en vuelta: la imagen se repite a lo largo
            dy = (yy - cy + alto_px / 2) % alto_px - alto_px / 2
            dx = xx - cx
            a = dx * math.cos(giro) + dy * math.sin(giro) - lado * tam * 0.34
            b = -dx * math.sin(giro) + dy * math.cos(giro)
            d = np.sqrt((a / (tam * 0.3)) ** 2 + (b / (tam * 0.62)) ** 2)
            marca = np.clip(1.25 - d, 0, 1) ** 1.5
            rgb *= (1 - 0.5 * marca)[..., None]
            alfa = np.maximum(alfa, marca * 0.85 * np.clip(1.0 - np.abs(u) ** 3, 0, 1))
    im = np.concatenate([np.clip(rgb, 0, 1), np.clip(alfa, 0, 1)[..., None]], -1)
    Image.fromarray((im * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(RAIZ, 'assets', 'terreno', 'huellas_hacienda.png'))


pintar_huellas()

# ---------------------------------------------------------------- 7. salida de alturas, normales y vista de control
crudas = (h2 / 0.01).astype(np.float32)
crudas.tofile(os.path.join(SALIDA, 'height_nuevo.bin'))


def normales(alturas):
    """El mapa de normales, con la misma cuenta que el plugin (tools/bump2normal_tex.gdshader): alturas
    crudas y los cuatro vecinos. El plugin lo rehace solo, pero de a pedazos y con la ventana del editor
    a la vista; con el editor en segundo plano lo guardo roto. Este sale siempre igual."""
    a = alturas.astype(np.float64)
    izq, der, atras, adel = np.roll(a, 1, 1), np.roll(a, -1, 1), np.roll(a, 1, 0), np.roll(a, -1, 0)
    izq[:, 0], der[:, -1], atras[0, :], adel[-1, :] = a[:, 0], a[:, -1], a[0, :], a[-1, :]
    n = np.stack([izq - der, np.full_like(a, 2.0), adel - atras], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return np.clip((0.5 * (n[..., [0, 2, 1]] + 1.0)) * 255.0 + 0.5, 0, 255).astype(np.uint8)


Image.fromarray(normales(crudas)).save(os.path.join(SALIDA, 'normal_nuevo.png'))
c_a, c_b = int((-190 + 2048) / 4), int((120 + 2048) / 4)
f_a, f_b = int((180 + 2048) / 4), int((400 + 2048) / 4)
vista = splat[f_a:f_b, c_a:c_b, :3] @ np.array([[0.62, 0.58, 0.38], [0.5, 0.42, 0.33], [0.42, 0.5, 0.28]]) + splat[f_a:f_b, c_a:c_b, 3:4] * 0.55
sombra = 0.75 + 0.25 * np.clip(1.0 - (gx[f_a:f_b, c_a:c_b] + gz[f_a:f_b, c_a:c_b]) * 3.0, 0, 1.3)
vista = np.clip(vista * sombra[..., None], 0, 1)
vista[agua[f_a:f_b, c_a:c_b]] = (0.25, 0.4, 0.45)
im = Image.fromarray((vista * 255).astype(np.uint8)).resize(((c_b - c_a) * 6, (f_b - f_a) * 6), Image.NEAREST)
im.save(os.path.join(SALIDA, 'aguada_prev.png'))
print('listo: salida/height_nuevo.bin, normal_nuevo.png, splat_nuevo.png, color_nuevo.png, aguada.json, aguada_prev.png')

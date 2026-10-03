# Genera las 4 texturas de suelo del HTerrain (Classic4), estilizadas y a escala real:
# cada textura cubre 4 m (una celda del mapa) en 1024 px -> 256 px por metro.
# Salida por slot: albedo_bump (RGB color sRGB + A altura) y normal_roughness (RGB normal GL + A rugosidad).
# 0 estepa seca, 1 tierra pisada y grava, 2 vega (pasto de orilla), 3 canto rodado y roca.
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

N = 1024
PXM = N / 4.0          # pixeles por metro
AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = sys.argv[1] if len(sys.argv) > 1 else os.path.join(AQUI, 'salida', 'texturas')
rng = np.random.default_rng(1881)


def hexf(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def ruido(escala_m, semilla, octavas=3):
    """Ruido periodico (sin costuras) con detalle de ~escala_m metros. Devuelve [0,1]."""
    r = np.random.default_rng(semilla)
    total = np.zeros((N, N), np.float32)
    amp, peso = 1.0, 0.0
    fy = np.fft.fftfreq(N)[:, None] * N
    fx = np.fft.fftfreq(N)[None, :] * N
    f = np.sqrt(fx * fx + fy * fy)
    for o in range(octavas):
        ciclos = (4.0 / escala_m) * (2 ** o)          # ciclos por tile
        filtro = np.exp(-((f - ciclos) ** 2) / (2 * (ciclos * 0.5 + 0.5) ** 2))
        filtro[0, 0] = 0
        w = r.normal(size=(N, N)) + 1j * r.normal(size=(N, N))
        n = np.real(np.fft.ifft2(np.fft.fft2(w.real) * filtro))
        n = (n - n.mean()) / (n.std() + 1e-6)
        total += n * amp
        peso += amp
        amp *= 0.5
    total /= peso
    total = (total - total.min()) / (total.max() - total.min())
    return total


def sello_envolvente(dibujar):
    """Dibuja con wrap-around: llama a dibujar(draw, dx, dy) en los 9 desplazamientos."""
    def f(draw):
        for dx in (-N, 0, N):
            for dy in (-N, 0, N):
                dibujar(draw, dx, dy)
    return f


def piedritas(color_img, alt, cantidad, r_min_cm, r_max_cm, colores, semilla, alt_peso=1.0, aplastar=(0.6, 1.0)):
    """Piedras como elipses suaves: pinta color y suma altura (bump)."""
    r = np.random.default_rng(semilla)
    capa_c = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    capa_h = Image.new('L', (N, N), 0)
    dc = ImageDraw.Draw(capa_c)
    dh = ImageDraw.Draw(capa_h)
    for _ in range(cantidad):
        x, y = r.uniform(0, N), r.uniform(0, N)
        rad = r.uniform(r_min_cm, r_max_cm) / 100.0 * PXM
        ap = r.uniform(*aplastar)
        ang = r.uniform(0, np.pi)
        col = colores[r.integers(len(colores))] * r.uniform(0.9, 1.1)
        c255 = tuple(int(max(0, min(255, v * 255))) for v in col) + (255,)
        rx, ry = rad, rad * ap
        # elipse rotada aproximada con poligono
        pts = []
        for k in range(14):
            t = 2 * np.pi * k / 14
            px_ = rx * np.cos(t) * (1 + r.uniform(-0.08, 0.08))
            py_ = ry * np.sin(t) * (1 + r.uniform(-0.08, 0.08))
            pts.append((px_ * np.cos(ang) - py_ * np.sin(ang), px_ * np.sin(ang) + py_ * np.cos(ang)))
        for dx in (-N, 0, N):
            for dy in (-N, 0, N):
                poly = [(x + dx + a, y + dy + b) for a, b in pts]
                dc.polygon(poly, fill=c255)
                dh.polygon(poly, fill=int(150 + 100 * alt_peso * r.uniform(0.6, 1.0)))
    # bordes suaves
    capa_c = capa_c.filter(ImageFilter.GaussianBlur(0.8))
    capa_h = capa_h.filter(ImageFilter.GaussianBlur(max(1.0, r_max_cm / 100 * PXM * 0.35)))
    a = np.asarray(capa_c, np.float32) / 255.0
    m = a[..., 3:4]
    # sombreado: un poco mas oscuras abajo a la derecha (volumen)
    color_img[:] = color_img * (1 - m) + a[..., :3] * m
    alt[:] = np.maximum(alt, np.asarray(capa_h, np.float32) / 255.0)


def briznas(color_img, alt, cantidad, largo_cm, ancho_px, colores, semilla, alpha=0.75, curva=0.25):
    """Briznas de pasto seco o verde: trazos cortos, finos y suaves."""
    r = np.random.default_rng(semilla)
    capa = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    capa_h = Image.new('L', (N, N), 0)
    d = ImageDraw.Draw(capa)
    dh = ImageDraw.Draw(capa_h)
    for _ in range(cantidad):
        x, y = r.uniform(0, N), r.uniform(0, N)
        L = r.uniform(*largo_cm) / 100.0 * PXM
        ang = r.uniform(0, 2 * np.pi)
        cv = r.uniform(-curva, curva)
        col = colores[r.integers(len(colores))] * r.uniform(0.88, 1.12)
        c255 = tuple(int(max(0, min(255, v * 255))) for v in col) + (int(255 * alpha * r.uniform(0.6, 1.0)),)
        pts = []
        for k in range(5):
            t = k / 4
            a2 = ang + cv * t
            pts.append((x + np.cos(a2) * L * t, y + np.sin(a2) * L * t))
        for dx in (-N, 0, N):
            for dy in (-N, 0, N):
                p2 = [(a + dx, b + dy) for a, b in pts]
                d.line(p2, fill=c255, width=int(ancho_px))
                dh.line(p2, fill=110, width=int(ancho_px))
    capa = capa.filter(ImageFilter.GaussianBlur(0.6))
    a = np.asarray(capa, np.float32) / 255.0
    m = a[..., 3:4]
    color_img[:] = color_img * (1 - m) + a[..., :3] * m
    alt[:] = np.maximum(alt, np.asarray(capa_h.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0 * 0.8)


def mezcla_base(c1, c2, escala_m, semilla, contraste=1.0):
    n = ruido(escala_m, semilla)
    n = np.clip((n - 0.5) * contraste + 0.5, 0, 1)[..., None]
    return hexf(c1)[None, None, :] * (1 - n) + hexf(c2)[None, None, :] * n


def granulado(color_img, fuerza, semilla):
    """Grano fino de arena: variacion de brillo de 1-2 px, muy sutil."""
    r = np.random.default_rng(semilla)
    g = r.normal(0, 1, (N, N)).astype(np.float32)
    g = np.asarray(Image.fromarray(((g - g.min()) / (g.max() - g.min()) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255.0
    color_img[:] = color_img * (1 + (g[..., None] - 0.5) * fuerza)


def normal_desde_altura(alt, fuerza):
    a = alt.astype(np.float32)
    dx = (np.roll(a, -1, 1) - np.roll(a, 1, 1)) * 0.5
    dy = (np.roll(a, -1, 0) - np.roll(a, 1, 0)) * 0.5
    nx = -dx * fuerza
    ny = dy * fuerza          # imagen con Y hacia abajo -> normal estilo OpenGL (Y arriba)
    nz = np.ones_like(a)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5


AJUSTE = {'estepa': (0.79, 0.80, 0.74), 'tierra': (0.84, 0.84, 0.80), 'vega': (0.88, 0.88, 0.85), 'canto': (0.84, 0.80, 0.70)}


def guardar(nombre, color, alt, rough, fuerza_normal):
    color = np.clip(color * np.array(AJUSTE[nombre], np.float32)[None, None, :], 0, 1)
    alt = np.clip(alt, 0, 1)
    ab = np.dstack([color, alt]) * 255
    Image.fromarray(ab.astype(np.uint8)).save(os.path.join(SALIDA, f'suelo_{nombre}_albedo_bump.png'))
    nrm = normal_desde_altura(np.asarray(Image.fromarray((alt * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0, fuerza_normal)
    nr = np.dstack([nrm, np.full((N, N), rough, np.float32)]) * 255
    Image.fromarray(nr.astype(np.uint8)).save(os.path.join(SALIDA, f'suelo_{nombre}_normal_roughness.png'))
    m = color.reshape(-1, 3).mean(0) * 255
    print(nombre, 'media', m.round(1))


# ---------------------------------------------------------------- 0 estepa seca
def estepa():
    col = mezcla_base('#8d7c5d', '#9c8a66', 1.2, 10, 1.3)
    olivo = ruido(2.5, 11)[..., None]
    col = col * (1 - 0.35 * olivo) + hexf('#7e7656')[None, None, :] * 0.35 * olivo
    costra = np.clip((ruido(0.9, 18) - 0.55) / 0.25, 0, 1)[..., None]
    col = col * (1 - 0.25 * costra) + hexf('#6a6650')[None, None, :] * 0.25 * costra
    granulado(col, 0.10, 12)
    alt = ruido(0.6, 13) * 0.35
    piedritas(col, alt, 2600, 0.4, 1.0, [hexf('#a39a88'), hexf('#7d7364'), hexf('#8f8676'), hexf('#6f6658')], 14, 0.6)
    piedritas(col, alt, 260, 1.0, 2.6, [hexf('#9a9284'), hexf('#7a7264'), hexf('#a69c8a')], 15, 1.0)
    briznas(col, alt, 900, (2.0, 6.0), 2, [hexf('#b39d6c'), hexf('#a38e60'), hexf('#c2ad7c')], 16, alpha=0.55)
    briznas(col, alt, 160, (1.5, 4.0), 2, [hexf('#7d7a52'), hexf('#6f6e4b')], 17, alpha=0.5)
    guardar('estepa', col, alt, 0.97, 2.5)


# ---------------------------------------------------------------- 1 tierra pisada y grava
def tierra():
    col = mezcla_base('#9a8a6e', '#8a7b62', 0.9, 20, 1.2)
    granulado(col, 0.12, 21)
    alt = ruido(0.5, 22) * 0.3
    piedritas(col, alt, 4200, 0.4, 1.2, [hexf('#a8a090'), hexf('#837a6c'), hexf('#958c7c'), hexf('#6f675b')], 23, 0.7)
    piedritas(col, alt, 520, 1.2, 3.0, [hexf('#9d9586'), hexf('#7b7366'), hexf('#aaa092')], 24, 1.0)
    briznas(col, alt, 220, (1.5, 4.5), 2, [hexf('#b09a6c'), hexf('#a08c62')], 25, alpha=0.45)
    guardar('tierra', col, alt, 0.98, 2.2)


# ---------------------------------------------------------------- 2 vega (pasto de orilla)
def vega():
    col = mezcla_base('#77714c', '#847b53', 1.0, 30, 1.2)
    granulado(col, 0.08, 31)
    alt = ruido(0.5, 32) * 0.3
    briznas(col, alt, 4200, (2.5, 7.0), 2, [hexf('#8a8352'), hexf('#7b784a'), hexf('#968c5d'), hexf('#a3976a')], 33, alpha=0.7, curva=0.4)
    briznas(col, alt, 1800, (2.0, 5.0), 2, [hexf('#b3a06d'), hexf('#a99766')], 34, alpha=0.55, curva=0.3)
    piedritas(col, alt, 260, 0.5, 1.4, [hexf('#8f877a'), hexf('#756e62')], 35, 0.6)
    guardar('vega', col, alt, 0.95, 2.0)


# ---------------------------------------------------------------- 3 canto rodado y roca
def canto():
    """Cantos rodados apretados (celdas de Voronoi con forma de domo) y arena gruesa entre ellos."""
    from scipy.spatial import cKDTree
    r = np.random.default_rng(45)
    # puntos con jitter sobre una grilla, con tamanios variados
    pts = []
    paso = 26
    for gy in range(0, N, paso):
        for gx in range(0, N, paso):
            pts.append((gx + r.uniform(0, paso), gy + r.uniform(0, paso)))
    pts = np.array(pts) % N
    arbol = cKDTree(pts, boxsize=N)
    yy, xx = np.mgrid[0:N, 0:N]
    q = np.stack([xx.ravel() + 0.5, yy.ravel() + 0.5], -1) % N
    d, idx = arbol.query(q, k=2)
    d1 = d[:, 0].reshape(N, N)
    d2 = d[:, 1].reshape(N, N)
    cel = idx[:, 0].reshape(N, N)
    borde = (d2 - d1)                     # 0 en el borde entre dos cantos
    radio = np.clip(borde / 2.0, 0, None)
    # algunos cantos mas chicos o ausentes (dejan arena)
    tam = r.uniform(0.55, 1.0, len(pts))
    hay = r.uniform(0, 1, len(pts)) > 0.06
    # domo redondeado: limitado por el borde con el vecino y por un radio propio (canto redondo)
    r_propio = 0.9 * paso * tam[cel]
    redondo = np.clip((r_propio - d1) / 5.0, 0, 1)
    domo = np.minimum(np.clip(radio / 8.0, 0, 1), redondo)
    domo = np.sqrt(domo)
    domo = domo * hay[cel] * (0.6 + 0.4 * tam[cel])
    hueco = domo < 0.15
    # colores por canto
    paleta = [hexf('#9a958c'), hexf('#837d74'), hexf('#8f897f'), hexf('#a49e94'), hexf('#77716a'), hexf('#8a7f70')]
    colc = np.array([paleta[i] for i in r.integers(len(paleta), size=len(pts))]) * r.uniform(0.9, 1.08, (len(pts), 1))
    col = colc[cel]
    # leve degradado dentro de cada canto (mas claro arriba) y vetas sutiles
    vetas = ruido(0.25, 46)[..., None]
    col = col * (0.92 + 0.12 * vetas) * (0.86 + 0.14 * domo[..., None])
    # arena gruesa en los huecos
    arena = mezcla_base('#857a68', '#6f675a', 0.6, 47, 1.2)
    granulado(arena, 0.2, 48)
    m = np.clip((0.2 - domo) / 0.12, 0, 1)[..., None]
    col = col * (1 - m) + arena * m
    granulado(col, 0.06, 49)
    alt = np.clip(domo * 0.9 + ruido(0.5, 50) * 0.08, 0, 1)
    guardar('canto', col, alt, 0.88, 4.0)


if __name__ == '__main__':
    os.makedirs(SALIDA, exist_ok=True)
    estepa(); tierra(); vega(); canto()

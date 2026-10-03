# Cajas, bolsas y sacos de relleno (tanda 3, item 4).
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from zmod import Malla, T, R, S, lin, mezcla, catenaria
from mathutils import Vector

PINO = lin('#8a7352')
PINO_OSCURO = lin('#5e4c36')
HUECO = lin('#2a221b')
SOGA = lin('#a39063')
ARPILLERA = lin('#9a8762')
ARPILLERA_OSC = lin('#7a6a4c')
LIENZO = lin('#b0a68b')
PAJA = lin('#c4a85e')
GRANO = lin('#b8923e')
CUERO_CRUDO = lin('#9a8163')
PELO = lin('#6a4a34')
LONA = lin('#a39a80')
LONA_SUCIA = lin('#7d745e')
TIENTO = lin('#4e3a2b')
LANA = lin('#b9b09a')


def cajon(m, largo, ancho, alto, tablas=3, tapa=True, manijas=True, color=PINO):
    """Cajon de tablas con listones en las puntas. Local: apoyado en z = 0, centrado en XY, largo en X."""
    g = 0.018
    m.caja((0, 0, alto / 2), (largo - 2 * g, ancho - 2 * g, alto - 0.01), HUECO)
    h = alto / tablas
    for i in range(tablas):
        z = h * (i + 0.5)
        for y in (-ancho / 2 + g / 2, ancho / 2 - g / 2):
            m.caja((0, y, z), (largo, g, h - 0.008), color, var=0.12, rot=(0, 0, m.rng.uniform(-0.25, 0.25)))
        for x in (-largo / 2 + g / 2, largo / 2 - g / 2):
            m.caja((x, 0, z), (g, ancho - 2 * g, h - 0.008), color, var=0.12)
    for x in (-largo / 2 + 0.07, largo / 2 - 0.07):
        for y in (-ancho / 2 - 0.006, ancho / 2 + 0.006):
            m.caja((x, y, alto / 2), (0.055, 0.02, alto), mezcla(color, PINO_OSCURO, 0.45), var=0.08)
    if tapa:
        n = max(2, int(round(ancho / 0.13)))
        for i in range(n):
            y = -ancho / 2 + ancho / n * (i + 0.5)
            m.caja((0, y, alto + g / 2), (largo + 0.01, ancho / n - 0.008, g), color, var=0.12)
    if manijas:
        for s in (-1, 1):
            x = s * (largo / 2 + 0.004)
            m.tubo([(x, -0.07, alto * 0.72), (x + s * 0.03, -0.05, alto * 0.5), (x + s * 0.035, 0, alto * 0.42),
                    (x + s * 0.03, 0.05, alto * 0.5), (x, 0.07, alto * 0.72)], 0.009, SOGA, lados=4, var=0.1)


def armar_cajon_largo():
    m = Malla('CajonLargo', semilla=21)
    cajon(m, 0.95, 0.38, 0.3)
    m.caja((0.12, -0.191, 0.15), (0.3, 0.004, 0.12), mezcla(PINO, HUECO, 0.55))        # marca pintada, sin letras
    m.objeto()
    zmod.choque_caja('CajonLargo', (0, 0, 0.16), (0.97, 0.4, 0.32))


def armar_cajas_apiladas():
    m = Malla('CajasApiladas', semilla=23)
    with m.en(T(-0.42, 0.0, 0), R(0, 0, 4)):
        cajon(m, 0.78, 0.55, 0.5, tablas=4)
    with m.en(T(0.44, 0.06, 0), R(0, 0, -7)):
        cajon(m, 0.8, 0.52, 0.46, tablas=4, tapa=False, manijas=False)
        m.almohada((0, 0, 0.4), (0.74, 0.46, 0.18), PAJA, e=0.6, u=10, v=6, ruido=0.035, frec=6.0, var=0.12)   # paja de embalar
        m.esfera((0.12, 0.04, 0.47), (0.1, 0.1, 0.07), lin('#4a5a4e'), u=8, v=5)                               # porron entre la paja
    with m.en(T(0.98, -0.3, 0.02), R(0, -68, -12)):                                                           # la tapa, apoyada
        for i in range(4):
            m.caja((0, -0.195 + i * 0.13, 0), (0.8, 0.122, 0.018), PINO, var=0.12)
        for x in (-0.3, 0.3):
            m.caja((x, 0, 0.016), (0.05, 0.5, 0.016), PINO_OSCURO, var=0.08)
    with m.en(T(-0.36, 0.02, 0.52), R(0, 0, -14)):
        cajon(m, 0.6, 0.4, 0.34)
    with m.en(T(-0.5, -0.05, 0.86), R(0, 0, 24)):
        cajon(m, 0.36, 0.28, 0.22, tablas=2, manijas=False)
    m.objeto()
    zmod.choque_caja('CajasIzq', (-0.42, 0, 0.44), (0.82, 0.6, 0.88))
    zmod.choque_caja('CajasDer', (0.5, 0.0, 0.25), (0.95, 0.62, 0.5))


def bolsa(m, radio, alto, color, torcida=0.0):
    """Bolsa chica de lienzo atada por el cuello."""
    m.esfera((0, 0, alto * 0.42), (radio, radio * 0.92, alto * 0.45), color, u=9, v=6, ruido=0.02, frec=5.0, var=0.06, sombra=0.25)
    m.tubo([(0, 0, alto * 0.8), (torcida * 0.3, 0, alto * 0.93), (torcida, 0, alto * 1.08)],
           [radio * 0.42, radio * 0.2, radio * 0.4], color, lados=7, var=0.06)
    m.cilindro((torcida * 0.3, 0, alto * 0.915), (torcida * 0.32, 0, alto * 0.95), radio * 0.24, TIENTO, lados=7)


def armar_bolsas():
    m = Malla('Bolsas', semilla=25)
    with m.en(T(0, 0, 0)):
        bolsa(m, 0.17, 0.42, LIENZO, 0.03)
    with m.en(T(0.31, 0.1, 0), R(0, 0, 50)):
        bolsa(m, 0.13, 0.33, mezcla(LIENZO, ARPILLERA, 0.6), -0.04)
    with m.en(T(0.12, -0.27, 0.11), R(78, 0, 20)):                 # una caida de costado
        bolsa(m, 0.12, 0.3, mezcla(LIENZO, lin('#8d7a63'), 0.5), 0.02)
    m.objeto()


def armar_saco_abierto():
    m = Malla('SacoAbierto', semilla=27)
    perfil = [(0.0, 0.17), (0.06, 0.25), (0.25, 0.29), (0.5, 0.275), (0.66, 0.25), (0.7, 0.27)]
    filas = []
    for z, r in perfil:
        fila = []
        for j in range(12):
            a = 2 * math.pi * j / 12
            k = 1.0 + 0.07 * math.sin(3 * a + z * 9) + m.rng.uniform(-0.02, 0.02)
            fila.append((r * k * math.cos(a), r * k * math.sin(a) * 0.92, z))
        filas.append(fila)
    m.rejilla(filas, ARPILLERA, color_dentro=ARPILLERA_OSC, cerrar_u=True, var=0.07, sombra=0.3)
    # borde arrollado
    m.tubo([(0.275 * math.cos(2 * math.pi * j / 12), 0.25 * math.sin(2 * math.pi * j / 12), 0.7) for j in range(13)],
           0.03, mezcla(ARPILLERA, LIENZO, 0.3), lados=5, tapas=False, var=0.06)
    m.almohada((0, 0, 0.635), (0.43, 0.39, 0.1), GRANO, e=0.8, u=10, v=6, ruido=0.012, frec=14.0, var=0.12)
    m.cilindro((0, 0, 0.005), (0, 0, 0.03), 0.2, ARPILLERA_OSC, lados=10)
    m.objeto()
    zmod.choque_cilindro('SacoAbierto', (0, 0, 0), (0, 0, 0.72), 0.3)


def armar_fardo():
    """Fardo de lana prensada envuelto en arpillera y atado con tientos."""
    m = Malla('Fardo', semilla=29)
    m.almohada((0, 0, 0.27), (0.95, 0.62, 0.54), ARPILLERA, e=0.42, u=14, v=10, ruido=0.02, frec=4.0, var=0.07, sombra=0.25)
    h, e = (0.475, 0.31, 0.27), 0.42

    def sobre(dx, dy, dz):          # el mismo calculo de la almohada, un poco hacia afuera
        return (math.copysign(abs(dx) ** e, dx) * h[0] * 1.03, math.copysign(abs(dy) ** e, dy) * h[1] * 1.035,
                0.27 + math.copysign(abs(dz) ** e, dz) * h[2] * 1.035)

    for x in (-0.28, 0.0, 0.28):
        xs = math.copysign((abs(x) / h[0]) ** (1 / e), x)
        r = math.sqrt(1 - xs * xs)
        m.tubo([sobre(xs, r * math.cos(a), r * math.sin(a)) for a in [math.radians(g) for g in range(0, 361, 15)]],
               0.012, TIENTO, lados=4, tapas=False)
    m.tubo([sobre(math.cos(a), 0, math.sin(a)) for a in [math.radians(g) for g in range(0, 361, 15)]],
           0.012, TIENTO, lados=4, tapas=False)
    m.esfera((0.42, 0.2, 0.44), (0.07, 0.08, 0.06), LANA, u=7, v=5, ruido=0.02, frec=9.0)             # lana que asoma por una rotura
    m.objeto()
    zmod.choque_caja('Fardo', (0, 0, 0.27), (0.95, 0.62, 0.54))


def armar_tercio():
    """Tercio de yerba: bulto retobado en cuero crudo, cosido con tientos."""
    m = Malla('Tercio', semilla=31)
    with m.en(T(0, 0, 0.19)):
        xs = [-0.3, -0.27, -0.16, 0.0, 0.16, 0.27, 0.3]
        rs = [0.08, 0.16, 0.19, 0.195, 0.19, 0.16, 0.08]
        caras = m.tubo([(x, 0, 0) for x in xs], rs, CUERO_CRUDO, lados=10, var=0.1)
        for f in caras:                                         # manchones de pelo
            if m.rng.random() < 0.22:
                m.pintar([f], mezcla(PELO, CUERO_CRUDO, m.rng.uniform(0.0, 0.4)))
        m.tubo([(x, 0.02 * math.sin(x * 40), 0.196 if abs(x) < 0.2 else 0.17) for x in [-0.27 + 0.045 * i for i in range(13)]],
               0.007, TIENTO, lados=3, tapas=False)
        for x in (-0.3, 0.3):
            m.esfera((x * 1.04, 0, 0), (0.035, 0.075, 0.075), mezcla(CUERO_CRUDO, TIENTO, 0.5), u=7, v=5)
    m.objeto()
    zmod.choque_caja('Tercio', (0, 0, 0.19), (0.62, 0.38, 0.38))


def armar_bulto_lona():
    """Carga tapada con una lona y atada con sogas."""
    m = Malla('BultoLona', semilla=33)
    largo, ancho, alto = 1.7, 1.1, 0.82

    def superficie(u, v):
        """u: angulo alrededor (0..2pi), v: 0 en el borde del suelo, 1 arriba."""
        e = 0.45
        a = v * math.pi / 2
        cx, sx = math.cos(u), math.sin(u)
        r = math.cos(a) ** e
        bulto = 1.0 + 0.06 * math.sin(3 * u + 1.3) * (1 - v) + 0.04 * math.sin(5 * u) * v
        return Vector((math.copysign(abs(cx) ** e, cx) * r * largo / 2 * bulto,
                       math.copysign(abs(sx) ** e, sx) * r * ancho / 2 * bulto,
                       (math.sin(a) ** e) * alto))

    n_u, n_v = 20, 6
    filas = []
    for i in range(n_v + 1):
        v = i / n_v
        fila = [superficie(2 * math.pi * j / n_u, v) for j in range(n_u)]
        if i == 0:                                              # el borde de la lona hace ondas sobre el suelo
            fila = [Vector((p.x * (1.07 + 0.05 * math.sin(j * 2.1)), p.y * (1.07 + 0.05 * math.cos(j * 1.7)), 0.01))
                    for j, p in enumerate(fila)]
        filas.append(fila)
    m.rejilla(filas, lambda co: mezcla(LONA_SUCIA, LONA, min(1.0, co.z / 0.5)), doble=False, cerrar_u=True, var=0.05)
    # (la ultima fila de la grilla ya cierra arriba)
    for u0 in (math.radians(55), math.radians(125)):
        m.tubo([superficie(u0 if t <= 1 else u0 + math.pi, t if t <= 1 else 2 - t) * 1.012 + Vector((0, 0, 0.008))
                for t in [i / 6 for i in range(13)]], 0.012, SOGA, lados=4, tapas=False, var=0.1)
    m.tubo([superficie(0.0 if t <= 1 else math.pi, t if t <= 1 else 2 - t) * 1.012 + Vector((0, 0, 0.008))
            for t in [i / 6 for i in range(13)]], 0.012, SOGA, lados=4, tapas=False, var=0.1)
    for u0, d in ((math.radians(55), 1), (math.radians(235), 1), (math.radians(125), 1), (math.radians(305), 1), (0.0, 1), (math.pi, 1)):
        p = superficie(u0, 0.0) * 1.1
        m.palo((p.x, p.y, 0.16), (p.x * 1.03, p.y * 1.03, -0.02), 0.02, 0.012, PINO_OSCURO, lados=5, tramos=1)     # estacas
    m.objeto()
    zmod.choque_caja('BultoLona', (0, 0, 0.4), (1.6, 1.0, 0.8))


LISTA = [
    ('cajon_largo', 'props', armar_cajon_largo, dict(vistas=((-62, 22), (118, 22)), figura=False)),
    ('cajas_apiladas', 'props', armar_cajas_apiladas, dict(vistas=((-62, 18), (118, 22)))),
    ('bolsas', 'props', armar_bolsas, dict(vistas=((-62, 22), (118, 22)), figura=False)),
    ('saco_abierto', 'props', armar_saco_abierto, dict(vistas=((-62, 30), (118, 22)), figura=False)),
    ('fardo', 'props', armar_fardo, dict(vistas=((-62, 22), (118, 22)), figura=False)),
    ('tercio', 'props', armar_tercio, dict(vistas=((-62, 22), (118, 22)), figura=False)),
    ('bulto_lona', 'props', armar_bulto_lona, dict(vistas=((-62, 18), (118, 22)))),
]

if __name__ == '__main__':
    zmod.producir(LISTA, sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

# Pase libre de la tanda 3: leña apilada con hacha, tendal de ropa, cruz del camino y osamenta.
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from zmod import Malla, T, R, S, lin, mezcla, catenaria
from mathutils import Vector

CORTEZA = lin('#5b5048')
LENIA = lin('#9a8163')
LENIA_OSC = lin('#6f5c48')
PALO = lin('#6d5a45')
PALO_CLARO = lin('#8a7352')
ACERO = lin('#4a4a4b')
SOGA = lin('#9a8860')
LIENZO = lin('#b5ab92')
LIENZO_GRIS = lin('#8f8a7c')
PANO_AZUL = lin('#4d5964')
ROJO = lin('#8a4238')
OCRE = lin('#a8894e')
PIEDRA = lin('#77726a')
PIEDRA_CLARA = lin('#8f897e')
TIENTO = lin('#4e3a2b')
HUESO = lin('#b0a890')
HUESO_OSC = lin('#8f8876')
BARRO_COCIDO = lin('#8a5f45')


def lenio(m, c, largo, radio, giro_z=0.0, inclina=0.0):
    """Un leño partido: corteza por fuera, madera clara en las puntas."""
    with m.en(T(*c), R(0, inclina, giro_z)):
        m.cilindro((-largo / 2, 0, 0), (largo / 2, 0, 0), radio, m.rng.choice([CORTEZA, mezcla(CORTEZA, LENIA_OSC, 0.5), LENIA_OSC]),
                   r1=radio * m.rng.uniform(0.85, 1.0), lados=6, var=0.12, color_tapa=mezcla(LENIA, LENIA_OSC, m.rng.uniform(0, 0.4)),
                   giro=m.rng.uniform(0, 1))


def armar_lenia():
    m = Malla('Lenia', semilla=91, materiales=('Mate', 'Metal'))
    # pila entre dos estacas
    for x in (-0.85, 0.85):
        m.palo((x, 0, -0.05), (x + m.rng.uniform(-0.03, 0.03), 0, 0.95), 0.035, 0.028, PALO, lados=5, curva=0.01, var=0.1)
    z = 0.075
    fila = 0
    while z < 0.75:
        r = 0.07
        cantidad = 11 - fila // 2
        ancho = 1.55 - fila * 0.06
        for i in range(cantidad):
            x = -ancho / 2 + ancho * (i + 0.5) / cantidad + m.rng.uniform(-0.015, 0.015)
            radio = m.rng.uniform(0.055, 0.082)
            # los leños van a lo largo de Y; la pila se ve de frente
            with m.en(T(x, m.rng.uniform(-0.03, 0.03), z + m.rng.uniform(-0.01, 0.01)), R(0, 0, 90 + m.rng.uniform(-4, 4))):
                m.cilindro((-0.26, 0, 0), (0.26, 0, 0), radio, m.rng.choice([CORTEZA, mezcla(CORTEZA, LENIA_OSC, 0.5), LENIA_OSC]),
                           r1=radio * m.rng.uniform(0.85, 1.0), lados=6, var=0.12,
                           color_tapa=mezcla(LENIA, LENIA_OSC, m.rng.uniform(0, 0.4)), giro=m.rng.uniform(0, 1))
        z += 0.128
        fila += 1
    # tronco de hachar con el hacha clavada, y unas astillas
    with m.en(T(1.75, -0.35, 0)):
        m.tubo([(0, 0, 0), (0, 0, 0.42)], [0.24, 0.22], CORTEZA, lados=9, var=0.1, color_tapa=LENIA)
        with m.en(T(0.02, 0.0, 0.42), R(0, -32, 20)):
            m.palo((0, 0, 0.02), (0, 0, 0.74), 0.02, 0.017, PALO_CLARO, lados=5, tramos=2, curva=0.01)       # mango
            m.prisma([(-0.02, 0.0), (0.15, -0.035), (0.17, 0.11), (-0.02, 0.085)], -0.014, 0.014, ACERO, mat='Metal')   # hoja
        for i in range(7):
            a = m.rng.uniform(0, 6.28)
            d = m.rng.uniform(0.35, 0.75)
            m.caja((d * math.cos(a), d * math.sin(a), 0.012), (m.rng.uniform(0.08, 0.16), 0.03, 0.015), LENIA,
                   rot=(m.rng.uniform(-8, 8), m.rng.uniform(-8, 8), m.rng.uniform(0, 180)), var=0.1)
        for c, g in (((-0.42, 0.25, 0.07), 30), ((-0.5, -0.2, 0.07), 100), ((0.35, 0.42, 0.07), -20)):
            lenio(m, c, 0.5, 0.07, giro_z=g)
    m.objeto()
    zmod.choque_caja('LeniaPila', (0, 0, 0.42), (1.85, 0.6, 0.85))
    zmod.choque_cilindro('LeniaTronco', (1.75, -0.35, 0), (1.75, -0.35, 0.45), 0.26)


def prenda_colgada(m, x, z_soga, ancho, largo, color, mangas=False, ondas=0.03):
    """Un paño colgado de la soga: un rectangulo doblado sobre ella, con algo de onda."""
    filas = []
    for i in range(5):
        t = i / 4
        fila = []
        for j in range(5):
            u = j / 4
            fila.append((x - ancho / 2 + ancho * u, 0.02 + ondas * math.sin(u * 5 + t * 3 + x) * t, z_soga - largo * t))
        filas.append(fila)
    m.rejilla(filas, color, var=0.05, grosor=0.01)
    if mangas:
        for s in (-1, 1):
            filas = []
            for i in range(3):
                t = i / 2
                filas.append([(x + s * (ancho / 2 + 0.02 + 0.2 * t) - 0.0, 0.02 + 0.02 * t, z_soga - 0.05 - 0.25 * t - 0.16 * u) for u in (0, 1)])
            m.rejilla(filas, color, var=0.05, grosor=0.01)


def armar_tendal():
    m = Malla('Tendal', semilla=93)
    a, b = Vector((-2.3, 0, 1.75)), Vector((2.3, 0, 1.68))
    m.palo((a.x, 0, -0.05), (a.x - 0.05, 0, 1.9), 0.04, 0.03, PALO, lados=6, curva=0.012, var=0.1, color_tapa=PALO_CLARO)
    m.palo((b.x, 0, -0.05), (b.x + 0.06, 0, 1.85), 0.04, 0.03, PALO, lados=6, curva=0.012, var=0.1, color_tapa=PALO_CLARO)
    m.palo((a.x - 0.03, 0, 1.2), (a.x - 0.75, 0, 0.0), 0.022, 0.02, PALO, lados=4, tramos=1)        # puntal
    soga = catenaria(a, b, 0.22, 16)
    m.tubo(soga, 0.008, SOGA, lados=3, tapas=False, var=0.08)

    def z_en(x):
        t = (x - a.x) / (b.x - a.x)
        return a.z + (b.z - a.z) * t - 0.22 * 4 * t * (1 - t)

    prenda_colgada(m, -1.55, z_en(-1.55), 0.55, 0.72, LIENZO, mangas=True)            # camisa
    prenda_colgada(m, -0.75, z_en(-0.75), 0.42, 0.9, LIENZO_GRIS)                     # calzoncillo
    prenda_colgada(m, -0.05, z_en(-0.05), 0.5, 0.5, ROJO)                             # pañuelo grande
    prenda_colgada(m, 0.75, z_en(0.75), 0.6, 0.78, mezcla(LIENZO, OCRE, 0.35), mangas=True)
    prenda_colgada(m, 1.6, z_en(1.6), 0.7, 1.05, PANO_AZUL, ondas=0.04)               # manta
    m.objeto()
    zmod.choque_caja('TendalPaloA', (a.x, 0, 0.9), (0.14, 0.14, 1.8))
    zmod.choque_caja('TendalPaloB', (b.x, 0, 0.9), (0.14, 0.14, 1.8))


def armar_cruz():
    """Cruz de palo a la vera del camino, sobre un monton de piedras, con un trapo atado."""
    m = Malla('CruzDelCamino', semilla=95)
    for i in range(11):
        ang = m.rng.uniform(0, 6.28)
        d = m.rng.uniform(0.0, 0.62)
        r = m.rng.uniform(0.13, 0.24)
        m.ico((d * math.cos(ang), d * math.sin(ang) * 1.5, r * 0.35 + (0.12 if d < 0.25 else 0.0)), (r, r * m.rng.uniform(0.7, 1.0), r * 0.6),
              m.rng.choice([PIEDRA, PIEDRA_CLARA]), sub=1, ruido=r * 0.2, frec=3.5, var=0.12, sombra=0.25, liso=False,
              rot=(0, 0, m.rng.uniform(0, 180)))
    with m.en(R(4, -6, 0)):
        m.palo((0, 0, 0.0), (0.02, 0, 1.55), 0.045, 0.036, CORTEZA, lados=6, curva=0.012, var=0.12, color_tapa=PALO_CLARO)
        m.palo((-0.42, 0.01, 1.14), (0.44, 0.0, 1.2), 0.036, 0.03, CORTEZA, lados=6, curva=0.012, var=0.12, color_tapa=PALO_CLARO)
        for g in (35, -35):                                                      # atadura en cruz
            with m.en(T(0.01, -0.005, 1.17), R(0, g, 0)):
                m.cilindro((-0.075, -0.04, 0), (0.075, -0.04, 0), 0.012, TIENTO, lados=4)
                m.cilindro((-0.075, 0.045, 0), (0.075, 0.045, 0), 0.012, TIENTO, lados=4)
        filas = []
        for i in range(4):
            t = i / 3
            filas.append([(0.3 + 0.1 * u + 0.05 * math.sin(t * 4), -0.03 + 0.03 * math.sin(t * 5 + u), 1.17 - 0.42 * t) for u in (0, 0.5, 1)])
        m.rejilla(filas, mezcla(ROJO, CORTEZA, 0.25), var=0.07, grosor=0.008)                                   # trapo descolorido
    m.tubo([(0.42, -0.5, 0.0), (0.42, -0.5, 0.11), (0.42, -0.5, 0.17)], [0.07, 0.085, 0.05], BARRO_COCIDO, lados=8, var=0.08)   # jarrito
    m.objeto()
    zmod.choque_cilindro('CruzPiedras', (0, 0, 0), (0, 0, 0.4), 0.55)


def armar_osamenta():
    """Osamenta de vacuno blanqueada por el sol: calavera con guampas, espinazo y costillas."""
    m = Malla('Osamenta', semilla=97)
    # calavera, echada de lado
    with m.en(T(-0.95, 0.1, 0.11), R(8, 12, 25)):
        m.almohada((0.0, 0, 0.0), (0.5, 0.22, 0.2), HUESO, e=0.7, u=10, v=6, ruido=0.012, frec=6.0, var=0.06, sombra=0.25)
        m.almohada((-0.27, 0, -0.015), (0.2, 0.13, 0.12), HUESO, e=0.75, u=8, v=5, var=0.06)                      # hocico
        for s in (-1, 1):
            m.esfera((0.08, s * 0.1, 0.035), (0.045, 0.02, 0.04), lin('#3a352f'), u=6, v=4)                        # cuencas
            m.tubo([(0.2, s * 0.09, 0.06), (0.24, s * 0.22, 0.1), (0.2, s * 0.34, 0.2), (0.12, s * 0.38, 0.3)],
                   [0.035, 0.03, 0.02, 0.006], mezcla(HUESO_OSC, lin('#5a5046'), 0.4), lados=6, var=0.08)          # guampas
    # espinazo y costillas, medio enterradas
    espina = [(-0.55 + 0.21 * i, 0.03 * math.sin(i * 0.9), 0.1 + 0.035 * math.sin(i * 0.7)) for i in range(8)]
    m.tubo(espina, [0.03, 0.035, 0.038, 0.038, 0.036, 0.034, 0.03, 0.022], HUESO_OSC, lados=6, var=0.08)
    for i in range(1, 7):
        x, y0, z0 = espina[i]
        for s in (-1, 1):
            alto = 0.34 - 0.03 * abs(i - 3)
            if s < 0 and i in (2, 5):
                continue                                                          # alguna costilla ya falta
            m.tubo([(x, y0, z0), (x + 0.02, y0 + s * 0.16, z0 + alto * 0.75), (x + 0.03, y0 + s * 0.3, z0 + alto * 0.55),
                    (x + 0.03, y0 + s * 0.36, z0 + 0.02), (x + 0.02, y0 + s * 0.33, -0.03)],
                   [0.016, 0.016, 0.015, 0.013, 0.01], HUESO, lados=4, var=0.07)
    # huesos sueltos
    for c, g, largo in (((1.3, 0.35, 0.03), 40, 0.42), ((1.15, -0.4, 0.03), -65, 0.36), ((0.3, 0.75, 0.03), 10, 0.3)):
        with m.en(T(*c), R(0, 0, g)):
            m.tubo([(-largo / 2, 0, 0), (-largo / 2 + 0.05, 0, 0), (largo / 2 - 0.05, 0, 0), (largo / 2, 0, 0)],
                   [0.035, 0.02, 0.02, 0.035], HUESO, lados=5, var=0.07)
    m.objeto()


LISTA = [
    ('lenia', 'props', armar_lenia, dict(vistas=((-62, 16), (118, 20)))),
    ('tendal', 'props', armar_tendal, dict(vistas=((-75, 10), (105, 12)))),
    ('cruz_camino', 'props', armar_cruz, dict(vistas=((-70, 10), (60, 14)))),
    ('osamenta', 'props', armar_osamenta, dict(vistas=((-62, 22), (118, 24)), figura=False)),
]

if __name__ == '__main__':
    zmod.producir(LISTA, sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

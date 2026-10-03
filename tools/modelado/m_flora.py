# Variaciones de vegetacion (tanda 3, item 5): segundas siluetas de lenga y ñire, matorral de barda y barda.
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from zmod import Malla, T, R, S, lin, mezcla
from mathutils import Vector

CORTEZA = lin('#5b5048')
CORTEZA_CLARA = lin('#7d7366')
CORTEZA_NIRE = lin('#4d4038')
RAMA_SECA = lin('#8a8073')
NARANJA = lin('#b8703a')
OCRE = lin('#c79a4a')
OXIDO = lin('#9c4f33')
OLIVA = lin('#6f7045')
AMARILLO = lin('#c2a64e')
VERDE_NIRE = lin('#5f6a45')
VERDE_SECO = lin('#7d7a48')
ROJO_NIRE = lin('#8f3f30')
BORRAVINO = lin('#7b3a2e')
NENEO = lin('#8a8552')
NENEO_CLARO = lin('#a39c64')
MOLLE = lin('#4f5238')
MOLLE_CLARO = lin('#666142')
PIEDRA = lin('#77726a')
BARDA_CLARA = lin('#9a8a6e')
BARDA_OCRE = lin('#8c7458')
BARDA_OSC = lin('#6e675e')
BARDA_ROJIZA = lin('#7d5f4c')


def lenga_alta(m, alto, radio, colores, piso=2.3, inclina=0.0, pisos=7):
    """Lenga de porte alto y angosto: fuste derecho y follaje en pisos que se achican hacia la punta."""
    punta = Vector((inclina * alto, 0, alto * 0.93))
    eje = [Vector((0, 0, -0.15))]
    for i in range(1, 5):
        t = i / 4
        eje.append(Vector((inclina * alto * t ** 1.6 + m.rng.uniform(-0.07, 0.07), m.rng.uniform(-0.07, 0.07), alto * 0.93 * t)))
    m.tubo(eje, [0.25, 0.19, 0.14, 0.09, 0.03], CORTEZA, lados=7, var=0.14, sombra=0.2)
    m.cilindro((0, 0, -0.15), (0, 0, 0.12), 0.32, CORTEZA, r1=0.25, lados=7, var=0.14)              # el pie, mas ancho

    def en_eje(z):
        t = max(0.0, min(1.0, z / (alto * 0.93)))
        f = t * 4
        i = min(3, int(f))
        return eje[i].lerp(eje[i + 1], f - i)

    # el follaje sube en espiral alrededor del fuste (angulo aureo), para que no queden pisos parejos como platos
    cantidad = pisos * 4
    for k in range(cantidad):
        t = k / (cantidad - 1)
        z = piso + (alto - piso - 0.55) * t + m.rng.uniform(-0.25, 0.25)
        r = radio * (1.0 - 0.74 * t ** 1.15) * m.rng.uniform(0.8, 1.15)
        centro = en_eje(z)
        a = k * 2.39996 + m.rng.uniform(-0.35, 0.35)
        d = r * m.rng.uniform(0.3, 0.68)
        c = centro + Vector((d * math.cos(a), d * math.sin(a), 0))
        tam = max(0.42, r * m.rng.uniform(0.5, 0.72))
        m.copa(c, (tam, tam, tam * m.rng.uniform(0.8, 1.0)), m.rng.choice(colores), centro, sub=2, ruido=0.16 * tam + 0.05,
               frec=1.3, var=0.07, sombra=0.14)
        if k % 6 == 0:                                                           # alguna rama a la vista
            m.palo(centro - Vector((0, 0, 0.2)), c - Vector((0, 0, tam * 0.3)), 0.05, 0.025, CORTEZA, lados=4, curva=0.02, tramos=2)
    tam = radio * 0.3
    m.copa(punta + Vector((0, 0, 0.05)), (tam, tam, tam * 1.5), m.rng.choice(colores), punta - Vector((0, 0, 0.6)), sub=2,
           ruido=0.08, frec=1.5, var=0.07, sombra=0.25)
    # ramas secas de abajo
    for i in range(3):
        a = m.rng.uniform(0, 6.28)
        z = m.rng.uniform(1.0, piso - 0.2)
        largo = m.rng.uniform(0.5, 0.9)
        m.palo((0, 0, z), (largo * math.cos(a), largo * math.sin(a), z + m.rng.uniform(0.0, 0.3)), 0.03, 0.008, RAMA_SECA,
               lados=4, curva=0.05, tramos=2)


def armar_lenga_c():
    m = Malla('LengaC', semilla=61)
    lenga_alta(m, 9.2, 1.9, [NARANJA, OCRE, OXIDO, NARANJA, mezcla(NARANJA, OLIVA, 0.4)])
    m.objeto()
    zmod.choque_cilindro('TroncoLengaC', (0, 0, 0), (0, 0, 2.2), 0.3)


def armar_lenga_d():
    m = Malla('LengaD', semilla=67)
    lenga_alta(m, 6.6, 1.45, [AMARILLO, mezcla(AMARILLO, OLIVA, 0.5), OLIVA, OCRE], piso=1.7, inclina=0.07, pisos=6)
    m.objeto()
    zmod.choque_cilindro('TroncoLengaD', (0, 0, 0), (0, 0, 2.0), 0.26)


def armar_nire_c():
    """Ñire de porte arbustivo alto: varios troncos retorcidos desde el pie y copa irregular, verde que amarillea."""
    m = Malla('NireC', semilla=71)
    colores = [VERDE_NIRE, VERDE_NIRE, VERDE_SECO, mezcla(VERDE_SECO, OCRE, 0.5), mezcla(VERDE_NIRE, OXIDO, 0.45)]
    copa = Vector((0.15, 0, 2.7))
    puntas = []
    for i, a in enumerate((0.3, 2.3, 4.3)):
        base = Vector((0.16 * math.cos(a), 0.16 * math.sin(a), -0.1))
        eje = [base]
        for k in range(1, 5):
            t = k / 4
            eje.append(Vector((base.x + (0.9 + 0.25 * i) * t * math.cos(a + 0.9 * t) + m.rng.uniform(-0.12, 0.12),
                               base.y + (0.9 + 0.25 * i) * t * math.sin(a + 0.9 * t) + m.rng.uniform(-0.12, 0.12),
                               (2.6 + 0.35 * i) * t ** 0.85)))
        m.tubo(eje, [0.13, 0.1, 0.075, 0.05, 0.02], CORTEZA_NIRE, lados=6, var=0.14)
        puntas.append(eje)
    for eje in puntas:
        for k in (2, 3, 4):
            for _ in range(2):
                c = eje[k] + Vector((m.rng.uniform(-0.6, 0.6), m.rng.uniform(-0.6, 0.6), m.rng.uniform(-0.1, 0.5)))
                tam = m.rng.uniform(0.55, 0.85)
                m.copa(c, (tam, tam, tam * m.rng.uniform(0.6, 0.8)), m.rng.choice(colores), copa, sub=2, ruido=0.16, frec=1.5,
                       var=0.07, sombra=0.3)
    m.copa(copa + Vector((0, 0, 0.75)), (0.8, 0.75, 0.6), m.rng.choice(colores), copa, sub=2, ruido=0.16, frec=1.5, var=0.07, sombra=0.25)
    for i in range(6):                                                           # ramitas secas del pie
        a = m.rng.uniform(0, 6.28)
        z = m.rng.uniform(0.4, 1.4)
        largo = m.rng.uniform(0.6, 1.1)
        m.palo((0.1 * math.cos(a), 0.1 * math.sin(a), z), (largo * math.cos(a), largo * math.sin(a), z + m.rng.uniform(0.1, 0.5)),
               0.025, 0.006, RAMA_SECA, lados=4, curva=0.06, tramos=2)
    m.objeto()
    zmod.choque_cilindro('TroncoNireC', (0, 0, 0), (0, 0, 1.6), 0.32)


def armar_nire_d():
    """Ñire achaparrado: mata baja y ancha, peinada por el viento del oeste (se vuelca hacia +X, el este)."""
    m = Malla('NireD', semilla=73)
    colores = [ROJO_NIRE, ROJO_NIRE, BORRAVINO, mezcla(ROJO_NIRE, NARANJA, 0.45), mezcla(BORRAVINO, CORTEZA_NIRE, 0.3)]
    copa = Vector((0.9, 0, 0.5))
    for i, a in enumerate((-0.7, 0.0, 0.8, 2.6, -2.5)):
        alcance = 1.9 if abs(a) < 1.2 else 0.9
        eje = [Vector((0.1 * math.cos(a), 0.1 * math.sin(a), -0.1))]
        for k in range(1, 4):
            t = k / 3
            eje.append(Vector((alcance * t * math.cos(a) + 0.5 * t * t + m.rng.uniform(-0.1, 0.1),
                               alcance * t * math.sin(a) + m.rng.uniform(-0.1, 0.1), 0.25 + 0.9 * math.sin(t * 1.9))))
        m.tubo(eje, [0.1, 0.075, 0.05, 0.018], CORTEZA_NIRE, lados=5, var=0.14)
        for k in (2, 3):
            c = eje[k] + Vector((m.rng.uniform(0.0, 0.35), m.rng.uniform(-0.25, 0.25), 0.18))
            tam = m.rng.uniform(0.6, 0.85)
            m.copa(c, (tam * 1.15, tam, tam * 0.55), m.rng.choice(colores), copa, sub=2, ruido=0.14, frec=1.6, var=0.07, sombra=0.3)
    for p in ((1.2, 0.5, 1.15), (1.7, -0.35, 1.05), (0.5, -0.2, 1.1)):
        m.copa(p, (0.75, 0.7, 0.42), m.rng.choice(colores), copa, sub=2, ruido=0.14, frec=1.6, var=0.07, sombra=0.25)
    # la mata llega al suelo del lado del viento: follaje bajo alrededor del pie
    for p in ((-0.55, 0.1, 0.38), (-0.2, 0.85, 0.36), (-0.15, -0.8, 0.4), (0.7, 1.15, 0.42), (0.8, -1.1, 0.4), (0.4, 0.2, 0.62),
              (1.6, 0.9, 0.5), (1.75, -0.95, 0.5), (2.35, 0.1, 0.62)):
        tam = m.rng.uniform(0.55, 0.75)
        m.copa(p, (tam, tam, tam * 0.62), m.rng.choice(colores), copa - Vector((0, 0, 0.6)), sub=2, ruido=0.14, frec=1.6, var=0.07, sombra=0.35)
    for i in range(4):                                                           # puntas secas hacia sotavento
        y = m.rng.uniform(-0.8, 0.8)
        m.palo((1.6, y, 1.0), (2.6 + m.rng.uniform(0, 0.4), y * 1.2, 1.25 + m.rng.uniform(0, 0.3)), 0.022, 0.005, RAMA_SECA,
               lados=4, curva=0.05, tramos=2)
    m.objeto()


def neneo(m, c, radio, alto):
    """Cojin de neneo: media bola apretada, mas clara arriba."""
    caras = m.esfera((c[0], c[1], c[2]), (radio, radio * m.rng.uniform(0.85, 1.0), alto), NENEO, u=10, v=8, ruido=0.05, frec=5.0, var=0.07)
    z0 = c[2]
    m.pintar(caras, lambda co: mezcla(mezcla(NENEO, MOLLE, 0.45), NENEO_CLARO, max(0.0, min(1.0, (co.z - z0) / alto))), var=0.07)


def armar_matorral_barda_a():
    m = Malla('MatorralBardaA', semilla=77)
    neneo(m, (0, 0, 0.02), 0.72, 0.5)
    neneo(m, (0.95, 0.35, 0.0), 0.5, 0.36)
    neneo(m, (-0.5, 0.85, 0.0), 0.42, 0.3)
    neneo(m, (0.5, -0.8, 0.0), 0.33, 0.24)
    for p, r in (((-0.9, -0.3, 0.04), 0.22), ((1.4, -0.35, 0.03), 0.16), ((0.2, 1.3, 0.03), 0.18)):
        m.ico(p, (r, r * 0.8, r * 0.55), PIEDRA, sub=1, ruido=0.04, frec=4.0, var=0.12)
    for i in range(7):                                                           # varas secas de la flor
        a = m.rng.uniform(0, 6.28)
        r = m.rng.uniform(0.1, 0.5)
        m.palo((r * math.cos(a), r * math.sin(a), 0.35), (r * 1.5 * math.cos(a), r * 1.5 * math.sin(a), 0.75 + m.rng.uniform(0, 0.15)),
               0.008, 0.004, lin('#b6a877'), lados=3, tramos=1)
    m.objeto()


def armar_matorral_barda_b():
    """Mata espinosa y oscura de la barda (molle), abierta, con un neneo al pie."""
    m = Malla('MatorralBardaB', semilla=79)
    copa = Vector((0, 0, 0.6))
    for i in range(13):
        a = 2 * math.pi * i / 13 + m.rng.uniform(-0.2, 0.2)
        alcance = m.rng.uniform(0.6, 1.05)
        alto = m.rng.uniform(0.7, 1.35)
        medio = Vector((alcance * 0.55 * math.cos(a), alcance * 0.55 * math.sin(a), alto * 0.6))
        punta = Vector((alcance * math.cos(a + 0.3), alcance * math.sin(a + 0.3), alto))
        m.tubo([(0.06 * math.cos(a), 0.06 * math.sin(a), -0.05), medio, punta], [0.035, 0.022, 0.006], mezcla(CORTEZA_NIRE, RAMA_SECA, m.rng.uniform(0.2, 0.8)),
               lados=4, var=0.1)
        if i % 3 != 2:
            tam = m.rng.uniform(0.3, 0.46)
            m.copa(medio.lerp(punta, m.rng.uniform(0.3, 0.8)) + Vector((0, 0, 0.05)), (tam, tam, tam * 0.7),
                   m.rng.choice([MOLLE, MOLLE, MOLLE_CLARO, mezcla(MOLLE, OXIDO, 0.3)]), copa, sub=1, ruido=0.1, frec=2.5, var=0.09, sombra=0.3)
    m.copa((0, 0, 0.55), (0.5, 0.5, 0.42), MOLLE, copa - Vector((0, 0, 0.4)), sub=2, ruido=0.12, frec=2.0, var=0.09, sombra=0.3)
    neneo(m, (1.05, -0.5, 0.0), 0.4, 0.28)
    m.ico((-0.9, 0.6, 0.04), (0.24, 0.2, 0.14), PIEDRA, sub=1, ruido=0.04, frec=4.0, var=0.12)
    m.objeto()


def losa(m, cx, cy, z0, z1, rx, ry, color, n=12, ruido=0.2, giro=0.0, color_arriba=None):
    """Un estrato de roca: contorno irregular, cara casi a pique y techo plano. Devuelve los puntos para el choque."""
    anillos = []
    desvio = [m.rng.uniform(-ruido, ruido) for _ in range(n)]
    for z, escala in ((z0 - 0.3, 1.04), ((z0 + z1) / 2, 1.0), (z1, 0.93)):
        anillo = []
        for j in range(n):
            a = giro + 2 * math.pi * j / n
            k = escala * (1.0 + desvio[j] + m.rng.uniform(-0.04, 0.04))
            # contorno entre elipse y rectangulo: los estratos se parten en bloques
            c, s = math.cos(a), math.sin(a)
            x = math.copysign(abs(c) ** 0.6, c) * rx * k
            y = math.copysign(abs(s) ** 0.6, s) * ry * k
            anillo.append((cx + x, cy + y, z + (m.rng.uniform(-0.05, 0.05) if z == z1 else 0.0)))
        anillos.append(anillo)
    m.rejilla(anillos, color, doble=False, cerrar_u=True, var=0.1, sombra=0.35, liso=False)
    m.cara(anillos[-1], color_arriba or mezcla(color, lin('#b0a58a'), 0.25), var=0.05)
    return anillos[0] + anillos[-1]


def piedras_al_pie(m, puntos, color):
    for x, y, r in puntos:
        m.ico((x, y, r * 0.3), (r, r * m.rng.uniform(0.7, 1.0), r * m.rng.uniform(0.5, 0.75)), color, sub=1, ruido=r * 0.2, frec=3.0,
              var=0.12, sombra=0.3, liso=False, rot=(0, 0, m.rng.uniform(0, 180)))


def armar_barda_a():
    """Barda: un frente de roca en estratos, de unos 7 m de largo y 3 de alto, con derrumbe al pie."""
    m = Malla('BardaA', semilla=83)
    capas = [losa(m, 0.0, 0.0, 0.0, 1.0, 3.7, 1.9, BARDA_OCRE, ruido=0.14),
             losa(m, 0.2, 0.25, 1.0, 1.75, 3.2, 1.5, BARDA_CLARA, ruido=0.16, giro=0.2),
             losa(m, -0.3, 0.4, 1.75, 2.55, 2.5, 1.25, BARDA_ROJIZA, ruido=0.18, giro=0.5),
             losa(m, 0.1, 0.55, 2.55, 3.05, 2.75, 1.3, BARDA_OSC, ruido=0.12, giro=0.1, color_arriba=mezcla(BARDA_OSC, NENEO, 0.3))]
    piedras_al_pie(m, [(-2.6, -2.3, 0.45), (-1.2, -2.6, 0.3), (0.6, -2.5, 0.55), (2.1, -2.2, 0.35), (3.4, -1.6, 0.4),
                       (-3.9, -1.2, 0.3), (1.4, -3.1, 0.22), (-0.3, -3.2, 0.2)], BARDA_OCRE)
    neneo(m, (1.6, 0.7, 3.02), 0.4, 0.26)
    neneo(m, (-1.3, -2.1, 0.0), 0.36, 0.25)
    m.objeto(angulo_filo=30)
    for i, puntos in enumerate(capas):
        zmod.choque_convexo('BardaA%d' % i, puntos)


def armar_barda_b():
    """Barda baja: un escalon de roca de 4 m, para repetir o poner suelta."""
    m = Malla('BardaB', semilla=89)
    capas = [losa(m, 0.0, 0.0, 0.0, 0.75, 2.2, 1.3, BARDA_CLARA, ruido=0.16, n=10),
             losa(m, 0.3, 0.2, 0.75, 1.35, 1.5, 0.95, BARDA_OSC, ruido=0.16, n=10, giro=0.3, color_arriba=mezcla(BARDA_OSC, NENEO, 0.25))]
    piedras_al_pie(m, [(-1.5, -1.5, 0.3), (0.2, -1.8, 0.4), (1.7, -1.3, 0.25), (2.5, -0.3, 0.3), (-2.5, -0.2, 0.24)], BARDA_CLARA)
    neneo(m, (-0.7, -0.3, 0.74), 0.3, 0.2)
    m.objeto(angulo_filo=30)
    for i, puntos in enumerate(capas):
        zmod.choque_convexo('BardaB%d' % i, puntos)


LISTA = [
    ('lenga_c', 'flora', armar_lenga_c, dict(vistas=((-62, 10), (30, 12)))),
    ('lenga_d', 'flora', armar_lenga_d, dict(vistas=((-62, 10), (30, 12)))),
    ('nire_c', 'flora', armar_nire_c, dict(vistas=((-62, 10), (30, 12)))),
    ('nire_d', 'flora', armar_nire_d, dict(vistas=((-62, 14), (-90, 14)))),
    ('matorral_barda_a', 'flora', armar_matorral_barda_a, dict(vistas=((-62, 18), (30, 18)))),
    ('matorral_barda_b', 'flora', armar_matorral_barda_b, dict(vistas=((-62, 18), (30, 18)))),
    ('barda_a', 'flora', armar_barda_a, dict(vistas=((-70, 12), (110, 16)))),
    ('barda_b', 'flora', armar_barda_b, dict(vistas=((-70, 14), (110, 16)))),
]

if __name__ == '__main__':
    zmod.producir(LISTA, sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

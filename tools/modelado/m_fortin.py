# Fortin nuevo (tanda 3, item 3): mas chico y mas rustico que el del Salitral.
# Redondo, de palo a pique sobre un terraplen de tierra, con un rancho de barro, una ramada y un mangrullo de palos.
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from zmod import Malla, T, R, S, lin, mezcla, catenaria
from mathutils import Vector

PALO_VIEJO = lin('#7a6b5a')
PALO_OSC = lin('#5a4e42')
PALO_CLARO = lin('#8a7352')
BARRO = lin('#8a7459')
BARRO_OSC = lin('#6b5843')
PAJA = lin('#b39a5c')
PAJA_VIEJA = lin('#8a7f63')
TIERRA = lin('#6f5e4a')
TIERRA_OSC = lin('#574a3b')
TIENTO = lin('#4e3a2b')
CUERO_VACA = lin('#7a5a40')
CUERO_CLARO = lin('#c2b79f')
HUECO = lin('#211c18')
RAMAS = lin('#5d5440')
CELESTE = lin('#6f8a99')
BLANCO = lin('#bdb9a8')

RADIO = 7.25
MEDIO_PORTON = 1.3
ANG_PORTON = math.degrees(math.asin(MEDIO_PORTON / RADIO))      # medio angulo que ocupa el porton (mira a -Y)


def en_porton(grados):
    """Que tan adentro del hueco del porton cae un angulo (0 = afuera, 1 = en el medio)."""
    d = abs(((grados + 90.0 + 180.0) % 360.0) - 180.0)
    return max(0.0, 1.0 - d / (ANG_PORTON * 1.7))


def terraplen(m):
    perfil = [(8.75, -0.4), (8.1, 0.2), (7.55, 0.46), (7.0, 0.48), (6.45, 0.22), (5.9, -0.3)]       # de afuera hacia adentro
    n = 48
    filas = []
    for r, z in perfil:
        fila = []
        for j in range(n):
            g = 360.0 * j / n
            a = math.radians(g)
            baja = 1.0 - min(1.0, en_porton(g) * 1.6)                                     # el paso del porton, gastado
            rr = r + m.rng.uniform(-0.12, 0.12)
            zz = z * (baja if z > 0 else 1.0) + (m.rng.uniform(-0.04, 0.05) if z > 0 else 0.0)
            fila.append((rr * math.cos(a), rr * math.sin(a), zz))
        filas.append(fila)
    m.rejilla(filas, lambda co: mezcla(TIERRA_OSC, TIERRA, max(0.0, min(1.0, co.z / 0.4 + 0.3))), doble=False,
              cerrar_u=True, var=0.07)


def empalizada(m):
    paso = 0.235
    n = int(2 * math.pi * RADIO / paso)
    for i in range(n):
        g = 360.0 * i / n
        if en_porton(g) > 0.42 or m.rng.random() < 0.035:
            continue
        a = math.radians(g + m.rng.uniform(-0.25, 0.25))
        r = RADIO + m.rng.uniform(-0.05, 0.05)
        alto = m.rng.uniform(2.05, 2.75)
        if m.rng.random() < 0.06:
            alto *= m.rng.uniform(0.55, 0.8)                                               # alguno quebrado
        grosor = m.rng.uniform(0.045, 0.078)
        pie = Vector((r * math.cos(a), r * math.sin(a), 0.2))
        inclina = Vector((m.rng.uniform(-0.05, 0.05), m.rng.uniform(-0.05, 0.05), 0))
        punta = pie + Vector((0, 0, alto + 0.28)) + inclina * alto
        medio = pie.lerp(punta, 0.86) + Vector((m.rng.uniform(-0.02, 0.02), m.rng.uniform(-0.02, 0.02), 0))
        color = mezcla(PALO_VIEJO, PALO_OSC, m.rng.uniform(0.0, 0.7))
        m.tubo([pie, medio, punta], [grosor, grosor * 0.86, grosor * 0.3], color, lados=5, sombra=0.3,
               color_tapa=PALO_CLARO, giro=m.rng.uniform(0, 1))
    # varas atadas por dentro
    for z, rr in ((1.3, RADIO - 0.1), (2.25, RADIO - 0.09)):
        tramo = []
        for g in range(int(-90 + ANG_PORTON * 1.5), int(270 - ANG_PORTON * 1.5) + 1, 9):
            a = math.radians(g)
            tramo.append((rr * math.cos(a), rr * math.sin(a), z + m.rng.uniform(-0.03, 0.03)))
        m.tubo(tramo, 0.035, PALO_VIEJO, lados=5, var=0.1)
    # porton: dos horcones gruesos con travesaño y la tranquera de varas corrida a un lado
    for s in (-1, 1):
        x = s * (MEDIO_PORTON + 0.05)
        y = -math.sqrt(RADIO ** 2 - x ** 2)
        m.palo((x, y, -0.1), (x + s * 0.03, y, 3.35), 0.125, 0.095, PALO_OSC, lados=7, curva=0.008, var=0.1, color_tapa=PALO_CLARO)
    yp = -math.sqrt(RADIO ** 2 - MEDIO_PORTON ** 2)
    m.palo((-MEDIO_PORTON - 0.35, yp, 3.12), (MEDIO_PORTON + 0.4, yp + 0.03, 3.2), 0.07, 0.06, PALO_VIEJO, lados=6, curva=0.01, var=0.1)
    for s in (-1, 1):
        m.cilindro((s * (MEDIO_PORTON + 0.05) - 0.14, yp, 3.15), (s * (MEDIO_PORTON + 0.05) + 0.14, yp, 3.16), 0.1, TIENTO, lados=6)
    for i, z in enumerate((0.55, 1.0, 1.45)):                                              # varas de la tranquera, abiertas
        m.palo((MEDIO_PORTON + 0.05, yp - 0.12 - 0.05 * i, z), (MEDIO_PORTON + 0.9 + 0.2 * i, yp - 2.3 + 0.1 * i, 0.06 + 0.02 * i),
               0.045, 0.04, PALO_VIEJO, lados=5, curva=0.01, var=0.1)


def rancho(m, largo=3.8, ancho=2.8, alto=1.75):
    """Rancho de palo a pique y barro, techo de paja a dos aguas. Local: centrado, la puerta mira a -Y."""
    g = 0.22
    hx, hy = largo / 2, ancho / 2
    px0, px1 = -0.2, 0.7                                                 # hueco de la puerta en la pared del frente
    vuelo, sube = 0.42, 1.0
    barro = dict(var=0.06, sombra=0.25)
    m.caja((0, hy - g / 2, alto / 2), (largo, g, alto), BARRO, **barro)                                 # fondo
    for s in (-1, 1):
        m.caja((s * (hx - g / 2), 0, alto / 2), (g, ancho - 2 * g, alto), BARRO, **barro)                # costados
        with m.en(T(s * (hx - g / 2), 0, 0), R(0, 0, 90)):
            m.prisma([(-hy, alto), (hy, alto), (0, alto + sube)], -g / 2, g / 2, BARRO_OSC, var=0.06)   # hastial
    m.caja(((-hx + px0) / 2, -hy + g / 2, alto / 2), (px0 + hx, g, alto), BARRO, **barro)                # frente, a la izquierda de la puerta
    m.caja(((px1 + hx) / 2, -hy + g / 2, alto / 2), (hx - px1, g, alto), BARRO, **barro)                 # frente, a la derecha
    m.caja(((px0 + px1) / 2, -hy + g / 2, alto - 0.12), (px1 - px0, g, 0.24), BARRO_OSC, var=0.06)       # dintel
    m.caja(((px0 + px1) / 2, -hy + g * 0.8, alto / 2 - 0.12), (px1 - px0, 0.04, alto - 0.24), HUECO)     # lo oscuro de adentro
    m.caja((-1.15, -hy + 0.03, 1.18), (0.42, 0.08, 0.34), HUECO)                                         # ventanuco
    m.palo((-1.4, -hy - 0.02, 0.98), (-0.9, -hy - 0.02, 0.98), 0.03, 0.03, PALO_OSC, lados=5, tramos=1)
    # palos del palo a pique que asoman del barro
    for i in range(11):
        x = -hx + 0.12 + i * (largo - 0.24) / 10
        if px0 - 0.1 < x < px1 + 0.1:
            continue
        m.palo((x, -hy - 0.012, 0), (x + m.rng.uniform(-0.02, 0.02), -hy - 0.012, alto), 0.035, 0.03, PALO_VIEJO,
               lados=4, tramos=1, tapas=False, var=0.12)
    for s in (-1, 1):
        for i in range(5):
            y = -hy + 0.15 + i * (ancho - 0.3) / 4
            m.palo((s * (hx + 0.012), y, 0), (s * (hx + 0.012), y, alto + (1.0 - abs(y) / hy) * 0.9), 0.035, 0.03, PALO_VIEJO,
                   lados=4, tramos=1, tapas=False, var=0.12)
    for x in (px0 - 0.07, px1 + 0.07):                                                                   # jambas
        m.palo((x, -hy - 0.02, 0), (x, -hy - 0.02, alto - 0.02), 0.055, 0.05, PALO_OSC, lados=6, tramos=1, var=0.1)
    # cuero de vaca que hace de puerta, corrido a un lado
    filas = []
    for i in range(5):
        t = i / 4
        filas.append([(px0 + 0.04 + 0.5 * u * (1.0 - 0.25 * t) + 0.0, -hy - 0.05 - 0.05 * math.sin(u * 7 + t * 2) * (0.3 + t),
                       (alto - 0.26) * (1 - t) + 0.07) for u in [j / 4 for j in range(5)]])
    caras = m.rejilla([list(reversed(f)) for f in filas], CUERO_VACA, color_dentro=mezcla(CUERO_VACA, CUERO_CLARO, 0.5), var=0.08)
    for f in caras[10:18]:
        m.pintar([f], CUERO_CLARO, var=0.05)                                                             # una mancha overa
    # techo de paja a dos aguas, con el alero desparejo
    for s in (-1, 1):
        filas = []
        for i in range(6):
            t = i / 5
            fila = []
            for j in range(11):
                x = -hx - 0.3 + (largo + 0.6) * j / 10
                y = s * (hy + vuelo) * t
                z = alto + sube * (1 - t) - 0.14 * t + 0.03 * math.sin(j * 1.7 + i) - 0.05 * math.sin(math.pi * t)
                if i == 5:
                    z += m.rng.uniform(-0.07, 0.03)
                    y += s * m.rng.uniform(-0.03, 0.08)
                fila.append((x, y, z + 0.1))
            filas.append(fila if s > 0 else list(reversed(fila)))
        m.rejilla(filas, lambda co: mezcla(PAJA_VIEJA, PAJA, max(0.0, min(1.0, (co.z - alto) / sube))),
                  color_dentro=mezcla(PAJA_VIEJA, HUECO, 0.5), grosor=0.13, canto=mezcla(PAJA_VIEJA, HUECO, 0.25), var=0.09)
    m.tubo([(-hx - 0.34 + (largo + 0.68) * j / 8, 0.0, alto + sube + 0.12 + 0.025 * math.sin(j * 2.3)) for j in range(9)],
           0.13, PAJA_VIEJA, lados=7, var=0.1)                                                           # caballete
    for x in (-1.1, 0.25, 1.3):                                                                          # tientos que sujetan la paja
        m.tubo([(x, -hy - vuelo * 0.9, alto + 0.0), (x, 0, alto + sube + 0.26), (x, hy + vuelo * 0.9, alto + 0.0)],
               0.018, TIENTO, lados=3, tapas=False)
    # ramada al costado derecho: dos horcones y un techo de ramas
    for y in (-hy + 0.2, hy - 0.2):
        m.palo((hx + 2.0, y, -0.05), (hx + 2.02, y, 1.95), 0.07, 0.055, PALO_VIEJO, lados=6, curva=0.012, var=0.1)
        m.cilindro((hx + 2.0, y - 0.07, 1.86), (hx + 2.0, y + 0.07, 1.9), 0.02, TIENTO, lados=4)
    m.palo((hx + 2.04, -hy - 0.1, 1.9), (hx + 2.0, hy + 0.1, 1.93), 0.045, 0.04, PALO_VIEJO, lados=5, var=0.1)
    for i in range(6):
        y = -hy + 0.1 + i * (ancho - 0.2) / 5
        m.palo((hx - 0.1, y, alto + 0.12), (hx + 2.25, y + m.rng.uniform(-0.1, 0.1), 1.93), 0.03, 0.022, PALO_VIEJO,
               lados=4, curva=0.01, var=0.12)
    filas = []
    for i in range(4):
        t = i / 3
        filas.append([(hx - 0.05 + 2.35 * t + m.rng.uniform(-0.05, 0.05), -hy - 0.15 + (ancho + 0.3) * j / 6,
                       alto + 0.2 + (1.99 - alto - 0.2) * t + 0.05 * math.sin(j * 2.1 + i * 1.3)) for j in range(7)])
    m.rejilla([list(reversed(f)) for f in filas], RAMAS, color_dentro=mezcla(RAMAS, HUECO, 0.45), grosor=0.07,
              canto=mezcla(RAMAS, HUECO, 0.3), var=0.14)


def mangrullo(m, alto=6.2, base=0.95, arriba=0.6):
    """Mangrullo de cuatro palos con cruces de varas atadas, plataforma, baranda y escalera. Local: centrado."""
    esquinas = [(-1, -1), (1, -1), (1, 1), (-1, 1)]

    def pata(i, z, afuera=1.0):
        k = (base + (arriba - base) * z / alto) * afuera
        return Vector((esquinas[i][0] * k, esquinas[i][1] * k, z))

    for i in range(4):
        m.palo(pata(i, -0.1), pata(i, alto + 0.55), 0.095, 0.06, PALO_OSC, lados=7, curva=0.006, tramos=4, var=0.1,
               color_tapa=PALO_CLARO)
    for i in range(4):
        k = (i + 1) % 4
        for z0, z1 in ((0.45, 2.9), (3.15, 5.2)):
            m.palo(pata(i, z0), pata(k, z1), 0.04, 0.034, PALO_VIEJO, lados=5, curva=0.01, var=0.12)
            m.palo(pata(k, z0), pata(i, z1), 0.04, 0.034, PALO_VIEJO, lados=5, curva=0.01, var=0.12)
        for z in (3.02, 5.38):
            m.palo(pata(i, z, 1.06), pata(k, z, 1.06), 0.045, 0.04, PALO_VIEJO, lados=5, curva=0.006, var=0.12)
            for p in (pata(i, z),):
                m.cilindro(p - Vector((0, 0, 0.06)), p + Vector((0, 0, 0.06)), 0.085, TIENTO, lados=6)      # atadura
        m.palo(pata(i, alto + 0.42, 1.05), pata(k, alto + 0.42, 1.05), 0.035, 0.03, PALO_VIEJO, lados=5, curva=0.006, var=0.12)   # baranda
    zp = 5.46
    kp = base + (arriba - base) * zp / alto
    for j in range(9):                                                                            # piso de varas
        x = -kp - 0.12 + (2 * kp + 0.24) * j / 8
        m.palo((x, -kp - 0.16, zp + 0.035), (x + m.rng.uniform(-0.03, 0.03), kp + 0.16, zp + 0.035), 0.04, 0.035,
               mezcla(PALO_VIEJO, PALO_CLARO, m.rng.uniform(0, 0.5)), lados=5, curva=0.004, tramos=1)
    # escalera de dos largueros apoyada en la plataforma
    pie_a, pie_b = Vector((-0.28, -base - 1.75, 0.0)), Vector((0.28, -base - 1.75, 0.0))
    top_a, top_b = Vector((-0.22, -kp - 0.14, zp + 0.5)), Vector((0.22, -kp - 0.14, zp + 0.5))
    m.palo(pie_a, top_a, 0.04, 0.032, PALO_VIEJO, lados=5, curva=0.004, var=0.1)
    m.palo(pie_b, top_b, 0.04, 0.032, PALO_VIEJO, lados=5, curva=0.004, var=0.1)
    for i in range(1, 15):
        t = i / 15.5
        m.palo(pie_a.lerp(top_a, t) + Vector((-0.06, 0, 0)), pie_b.lerp(top_b, t) + Vector((0.06, 0, 0)), 0.022, 0.02,
               PALO_CLARO, lados=4, tramos=1, var=0.12)
    # banderin gastado en la punta de un palo
    asta = pata(2, alto + 0.5)
    m.palo(asta, asta + Vector((0.05, 0.02, 1.5)), 0.022, 0.014, PALO_VIEJO, lados=5, tramos=1)
    filas = []
    for j in range(4):
        v = j / 3
        filas.append([(asta.x + 0.06 + 0.72 * u * (1 - 0.1 * u), asta.y + 0.02 + 0.07 * math.sin(u * 6.5 + v) * u,
                       asta.z + 1.45 - 0.42 * v - 0.22 * u ** 1.5) for u in [i / 5 for i in range(6)]])
    caras = m.rejilla(filas, BLANCO, var=0.04)
    for indice, f in enumerate(caras):
        if (indice % 30) // 10 != 1:
            m.pintar([f], CELESTE, var=0.05)


def armar_fortin():
    m = Malla('FortinNuevo', semilla=51)
    terraplen(m)
    empalizada(m)
    M_rancho = T(-1.2, 3.6, 0)
    M_mangrullo = T(-3.6, -1.2, 0) @ R(0, 0, 35)
    with m.en(M_rancho):
        rancho(m)
    with m.en(M_mangrullo):
        mangrullo(m)
    m.objeto()
    # choque: la empalizada en tramos rectos (deja libre el porton), el rancho y las patas del mangrullo
    n = 14
    libre = ANG_PORTON * 1.25
    paso = (360.0 - 2 * libre) / n
    for i in range(n):
        g = -90.0 + libre + paso * (i + 0.5)
        a = math.radians(g)
        cuerda = 2 * RADIO * math.sin(math.radians(paso / 2)) + 0.25
        rc = RADIO * math.cos(math.radians(paso / 2))
        zmod.choque_caja('Empalizada%02d' % i, (rc * math.cos(a), rc * math.sin(a), 1.6), (0.5, cuerda, 3.4), rot=(0, 0, g))
    zmod.choque_caja('Rancho', tuple(M_rancho @ Vector((0, 0, 1.1))), (3.9, 2.9, 2.2))
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        zmod.choque_caja('Mangrullo%d' % i, tuple(M_mangrullo @ Vector((sx * 0.92, sy * 0.92, 1.2))), (0.28, 0.28, 2.4), rot=(0, 0, 35))
    for s, nombre in ((-1, 'Izq'), (1, 'Der')):
        zmod.choque_caja('Ramada' + nombre, tuple(M_rancho @ Vector((1.9 + 2.0, s * 1.2, 1.0))), (0.2, 0.2, 2.0))


LISTA = [
    ('fortin_nuevo', 'edificios', armar_fortin, dict(vistas=((-78, 16), (-30, 32), (120, 22), (-90, 75)), res=(760, 570))),
]

if __name__ == '__main__':
    zmod.producir(LISTA, sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

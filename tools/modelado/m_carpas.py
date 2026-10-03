# Campamento de tropa (tanda 3, item 1): carpa de tropa (dos variantes), carpa de comando y mastil con bandera.
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from zmod import Malla, T, R, S, lin, mezcla, catenaria
from mathutils import Vector

LONA = lin('#b3a98f')
LONA_SUCIA = lin('#8a8069')
LONA_DENTRO = lin('#6f6857')
ROJO = lin('#7d3d34')
CREMA = lin('#a89e84')
PALO = lin('#6d5a45')
PALO_CLARO = lin('#8a7352')
SOGA = lin('#a39063')
ESTACA = lin('#5e4c36')
MANTA = lin('#56606a')
MANTA_OSC = lin('#3b3f45')
PAJA = lin('#b39a5c')
CUERO = lin('#5a4234')
PAPEL = lin('#d8cfb4')
TINTA = lin('#2b2a2b')
LATA = lin('#8a8a85')
CELESTE = lin('#6f8a99')
BLANCO = lin('#bdb9a8')
SOL = lin('#b08f45')
PIEDRA = lin('#77726a')


def lona(sucia_hasta=0.6, clara=LONA, sucia=LONA_SUCIA):
    return lambda co: mezcla(sucia, clara, max(0.0, min(1.0, co.z / sucia_hasta)))


def agua(m, s, y0, y1, ancho, z_cumbrera, z_alero, nt=6, ny=8, comba=0.05, borde=None, cumbrera=None, alero=None,
         color=None, x0=0.0):
    """Un paño de techo, de la cumbrera (x0) al alero (x0 + s*ancho). cumbrera(y) y alero(y) suman altura a cada
    punta del paño; borde(y) solo a la ultima fila (los festones del ruedo)."""
    filas = []
    for i in range(nt + 1):
        t = i / nt
        fila = []
        for j in range(ny + 1):
            y = y0 + (y1 - y0) * j / ny
            x = x0 + s * (ancho * t - comba * 0.6 * math.sin(math.pi * t))
            zc = z_cumbrera + (cumbrera(y) if cumbrera else 0.0)
            za = z_alero + (alero(y) if alero else 0.0)
            z = zc + (za - zc) * t - comba * math.sin(math.pi * t)
            if borde and i == nt:
                z += borde(y)
            fila.append((x, y, z))
        filas.append(fila if s < 0 else list(reversed(fila)))
    m.rejilla(filas, color or lona(), color_dentro=LONA_DENTRO, var=0.035)


def estaca(m, x, y, hacia=(0, 0), alto=0.16):
    m.palo((x, y, -0.03), (x + hacia[0] * 0.07, y + hacia[1] * 0.07, alto), 0.02, 0.016, ESTACA, lados=5, tramos=1, var=0.1)


def viento(m, desde, hasta, r=0.007):
    """Soga tirante de un palo a una estaca."""
    m.tubo(catenaria(desde, hasta, 0.04, 4), r, SOGA, lados=3, tapas=False, var=0.08)
    d = (Vector(hasta) - Vector(desde))
    d.z = 0
    d = d.normalized() if d.length > 1e-6 else Vector((1, 0, 0))
    estaca(m, hasta[0], hasta[1], hacia=(d.x, d.y))


def carpa_tropa(m, abierta=True, largo=2.4, ancho=2.0, alto=1.5, hundida=0.0, clara=LONA, sucia=LONA_SUCIA):
    """Carpa de dos aguas de la tropa. Frente hacia -Y."""
    w, yf, yb = ancho / 2, -largo / 2, largo / 2
    paso = largo / 4
    color = lona(0.55, clara, sucia)
    borde = lambda y: 0.02 + 0.05 * abs(math.sin(math.pi * (y - yf) / paso))
    cumbrera = lambda y: -hundida * math.sin(math.pi * (y - yf) / largo)
    for s in (-1, 1):
        agua(m, s, yf, yb, w, alto, 0.0, borde=borde, cumbrera=cumbrera, color=color)
        for k in range(5):
            estaca(m, s * (w + 0.05), yf + k * paso, hacia=(s, 0), alto=0.13)
    # fondo cerrado
    filas = []
    for i in range(5):
        t = i / 4
        filas.append([((2 * j / 4 - 1) * w * t, yb + 0.035 * math.sin(math.pi * t), alto * (1 - t) + 0.02 * t) for j in range(5)])
    m.rejilla(filas, color, color_dentro=LONA_DENTRO, var=0.035)
    # frente: dos solapas
    A = Vector((0, yf, alto))
    izq = [[A, A], [Vector((-w * 0.5, yf - 0.02, alto * 0.5)), Vector((-0.02, yf - 0.03, alto * 0.5))],
           [Vector((-w, yf, 0.02)), Vector((-0.05 if abierta else 0.0, yf - 0.04, 0.02))]]
    m.rejilla([list(reversed(f)) for f in izq], color, color_dentro=LONA_DENTRO, var=0.035)
    if abierta:
        # la solapa derecha, volcada hacia atras sobre el paño (gira 90 grados sobre el canto del frente)
        h2 = 1.0 + (alto / w) ** 2
        pie = Vector((w * (alto / w) ** 2 / h2, 0, alto / h2))          # pie de la perpendicular desde la base del centro
        dist = math.hypot(pie.x, pie.z)
        normal = Vector((alto, 0, w)).normalized()
        C = Vector((pie.x, yf + dist, pie.z)) + normal * 0.05
        B = Vector((w, yf, 0.02))
        m.rejilla([[A + normal * 0.02, A + normal * 0.02], [A.lerp(B, 0.5) + normal * 0.03, A.lerp(C, 0.5) + normal * 0.04],
                   [B + normal * 0.02, C]], color, color_dentro=LONA_DENTRO, var=0.035)
        m.tubo([C, C + Vector((0.02, 0.2, -0.02))], 0.006, SOGA, lados=3)
        # adentro: paja, una manta y un poncho arrollado
        m.almohada((0.42, 0.05, 0.035), (0.8, largo - 0.5, 0.07), PAJA, e=0.5, u=10, v=6, ruido=0.015, frec=8.0, var=0.1)
        m.almohada((0.42, 0.25, 0.085), (0.7, largo - 1.1, 0.05), MANTA, e=0.5, u=10, v=6, var=0.06)
        m.tubo([(0.14, yb - 0.35, 0.13), (0.72, yb - 0.3, 0.13)], 0.09, MANTA_OSC, lados=8, var=0.08)
    else:
        der = [[A, A], [Vector((0.02, yf - 0.03, alto * 0.5)), Vector((w * 0.5, yf - 0.02, alto * 0.5))],
               [Vector((0.0, yf - 0.04, 0.02)), Vector((w, yf, 0.02))]]
        m.rejilla([list(reversed(f)) for f in der], color, color_dentro=LONA_DENTRO, var=0.035)
        for z in (0.3, 0.62, 0.94):                               # ataduras del cierre
            m.cilindro((-0.03, yf - 0.045, z), (0.03, yf - 0.045, z), 0.009, SOGA, lados=4)
    # palos y vientos
    for y in (yf, yb):
        m.palo((0, y, 0), (0, y, alto + 0.09), 0.03, 0.024, PALO, lados=6, curva=0.004, var=0.1, color_tapa=PALO_CLARO)
    m.palo((0, yf - 0.06, alto - 0.015), (0, yb + 0.06, alto - 0.015 - hundida * 0.2), 0.02, 0.02, PALO, lados=5, curva=0.004, var=0.1)
    viento(m, (0, yf, alto + 0.05), (0.1, yf - 1.15, 0.0))
    viento(m, (0, yb, alto + 0.05), (-0.08, yb + 1.15, 0.0))
    return [(-w, yf, 0), (w, yf, 0), (-w, yb, 0), (w, yb, 0), (0, yf, alto), (0, yb, alto)]


def armar_carpa_tropa():
    m = Malla('CarpaTropa', semilla=41)
    cuna = carpa_tropa(m, abierta=True)
    m.objeto()
    zmod.choque_convexo('CarpaTropa', cuna)


def armar_carpa_tropa_b():
    m = Malla('CarpaTropaB', semilla=43)
    cuna = carpa_tropa(m, abierta=False, largo=2.2, ancho=1.9, alto=1.4, hundida=0.07,
                       clara=lin('#a89f88'), sucia=lin('#7d7461'))
    m.caja((0.52, 0.2, 0.6), (0.3, 0.26, 0.012), lin('#8f8672'), rot=(0, 55.8, 0))      # un remiendo
    m.objeto()
    zmod.choque_convexo('CarpaTropaB', cuna)


def cenefa(m, puntos, afuera, alto=0.15, paso=0.3, color=None):
    """Tira festoneada que cuelga de una linea de puntos (el borde de un techo)."""
    puntos = [Vector(p) for p in puntos]
    cara = (puntos[1] - puntos[0]).cross(Vector((0, 0, -1)))
    if cara.x * afuera[0] + cara.y * afuera[1] < 0:               # que la cara de afuera mire hacia afuera
        puntos.reverse()
    arriba, abajo = [], []
    largo = 0.0
    previo = None
    for p in puntos:
        p = Vector(p)
        if previo is not None:
            largo += (p - previo).length
        previo = p
        cae = 0.05 + (alto - 0.05) * abs(math.sin(math.pi * largo / paso))
        arriba.append(p)
        abajo.append(p + Vector((afuera[0] * 0.02, afuera[1] * 0.02, -cae)))
    m.rejilla([arriba, abajo], color or mezcla(LONA, LONA_SUCIA, 0.25), color_dentro=LONA_DENTRO, var=0.04)


def muestreo(a, b, paso=0.05):
    a, b = Vector(a), Vector(b)
    n = max(1, int(round((b - a).length / paso)))
    return [a.lerp(b, i / n) for i in range(n + 1)]


def cortina(m, x0, x1, y, z0, z1, raya=0.11):
    """Cortina a rayas, recogida en pliegues."""
    cols = int(round((x1 - x0) / (raya / 2)))
    filas = []
    for i in range(5):
        t = i / 4
        z = z1 + (z0 - z1) * t
        fila = []
        for j in range(cols + 1):
            x = x0 + (x1 - x0) * j / cols
            pliegue = 0.06 * math.sin((x - x0) * 2 * math.pi / 0.28 + t * 0.8) * (0.4 + 0.6 * t)
            fila.append((x, y + pliegue, z))
        filas.append(fila)
    m.rejilla(filas, lambda co: (ROJO if int(math.floor((co.x - x0) / raya)) % 2 == 0 else CREMA),
              color_dentro=None, var=0.03, por_cara=True)


def mesa_de_campana(m):
    """Mesa de tijera con un mapa, tintero y papeles. Local: centrada, tablero a 0,74 m."""
    m.caja((0, 0, 0.74), (1.05, 0.62, 0.035), PALO_CLARO, var=0.08)
    for y in (-0.24, 0.24):
        m.palo((-0.42, y, 0.0), (0.42, y, 0.72), 0.022, 0.022, PALO, lados=5, tramos=1, var=0.1)
        m.palo((0.42, y, 0.0), (-0.42, y, 0.72), 0.022, 0.022, PALO, lados=5, tramos=1, var=0.1)
    m.palo((0, -0.24, 0.36), (0, 0.24, 0.36), 0.016, 0.016, PALO, lados=5, tramos=1)
    # mapa: papel grande algo enrollado en las puntas, con el rio y la costa apenas marcados
    filas = []
    for j in range(4):
        v = j / 3
        fila = []
        for i in range(6):
            u = i / 5
            rollo = 0.035 * (max(0.0, abs(u - 0.5) * 2 - 0.82) / 0.18) ** 2
            fila.append((-0.36 + 0.72 * u, -0.22 + 0.42 * v, 0.762 + rollo))
        filas.append(fila)
    m.rejilla(filas, PAPEL, doble=False, var=0.03)
    m.tubo([(-0.3, 0.1, 0.766), (-0.12, 0.02, 0.766), (0.04, 0.06, 0.766), (0.22, -0.08, 0.766), (0.31, -0.06, 0.766)],
           0.004, mezcla(CELESTE, TINTA, 0.35), lados=3, tapas=False)                                  # el rio
    m.cilindro((0.4, 0.2, 0.757), (0.4, 0.2, 0.8), 0.022, TINTA, lados=7)                              # tintero
    m.caja((0.36, -0.18, 0.762), (0.16, 0.11, 0.008), mezcla(PAPEL, CREMA, 0.5), rot=(0, 0, 18))      # papeles
    m.caja((-0.43, -0.2, 0.775), (0.1, 0.07, 0.03), CUERO, rot=(0, 0, -12))                           # libreta


def banquito(m):
    """Banquito de tijera con asiento de cuero."""
    for y in (-0.15, 0.15):
        m.palo((-0.17, y, 0.0), (0.17, y, 0.42), 0.016, 0.016, PALO, lados=5, tramos=1)
        m.palo((0.17, y, 0.0), (-0.17, y, 0.42), 0.016, 0.016, PALO, lados=5, tramos=1)
    for x in (-0.17, 0.17):
        m.palo((x, -0.17, 0.42), (x, 0.17, 0.42), 0.016, 0.016, PALO, lados=5, tramos=1)
    m.rejilla([[(-0.17, -0.16, 0.425), (-0.17, 0.16, 0.425)], [(0.0, -0.16, 0.39), (0.0, 0.16, 0.39)],
               [(0.17, -0.16, 0.425), (0.17, 0.16, 0.425)]], CUERO, grosor=0.006, var=0.05)


def baul(m, largo=0.82, ancho=0.46, alto=0.4):
    m.caja((0, 0, alto * 0.42), (largo, ancho, alto * 0.84), CUERO, var=0.06, sombra=0.2)
    m.almohada((0, 0, alto * 0.86), (largo + 0.02, ancho + 0.02, alto * 0.3), mezcla(CUERO, TINTA, 0.25), e=0.55, u=10, v=6)
    for x in (-largo * 0.3, largo * 0.3):
        m.caja((x, 0, alto * 0.5), (0.045, ancho + 0.012, alto * 1.0), mezcla(CUERO, TINTA, 0.45))
    m.caja((0, -ancho / 2 - 0.006, alto * 0.62), (0.07, 0.012, 0.08), LATA, mat='Metal')


def catre(m, largo=1.9, ancho=0.72):
    for x in (-ancho / 2, ancho / 2):
        m.palo((x, -largo / 2, 0.38), (x, largo / 2, 0.38), 0.022, 0.022, PALO, lados=5, tramos=1)
    for y in (-largo / 2 + 0.2, 0, largo / 2 - 0.2):
        m.palo((-ancho / 2, y, 0.0), (ancho / 2, y, 0.4), 0.02, 0.02, PALO, lados=5, tramos=1)
        m.palo((ancho / 2, y, 0.0), (-ancho / 2, y, 0.4), 0.02, 0.02, PALO, lados=5, tramos=1)
    m.almohada((0, 0, 0.42), (ancho, largo, 0.09), LONA_SUCIA, e=0.45, u=10, v=6)
    m.almohada((0, 0.25, 0.47), (ancho + 0.04, largo - 0.55, 0.06), MANTA, e=0.45, u=10, v=6, var=0.05)
    m.almohada((0, -largo / 2 + 0.2, 0.5), (0.5, 0.28, 0.1), LONA, e=0.6, u=8, v=5)


def armar_carpa_comando():
    """Carpa de pared de los oficiales, con alero al frente, cenefa festoneada y cortinas a rayas
    (como la de la foto de Roca y sus oficiales). Frente hacia -Y."""
    m = Malla('CarpaComando', semilla=45)
    w, yf, yb, hw, H = 1.8, -2.1, 2.1, 1.35, 2.75
    ya = yf - 1.75                                                   # hasta donde llega el alero
    color = lona(0.7)
    for s in (-1, 1):
        agua(m, s, yf, yb, w, H, hw, nt=5, ny=10, comba=0.06, color=color)                       # techo
        agua(m, s, ya, yf, w, H - 0.22, hw - 0.12, nt=4, ny=4, comba=0.07, color=color,
             cumbrera=lambda y: 0.22 * (y - ya) / (yf - ya), alero=lambda y: 0.12 * (y - ya) / (yf - ya))   # alero
        # pared lateral, con el pie un poco abierto
        filas = []
        for i in range(3):
            t = i / 2
            fila = [(s * (w + 0.07 * t + 0.02 * math.sin(math.pi * t)), yf + (yb - yf) * j / 10, hw * (1 - t) + 0.02 * t)
                    for j in range(11)]
            filas.append(fila if s < 0 else list(reversed(fila)))
        m.rejilla(filas, color, color_dentro=LONA_DENTRO, var=0.035)
        cenefa(m, muestreo((s * w, ya, hw - 0.12), (s * w, yf, hw)) + muestreo((s * w, yf, hw), (s * w, yb, hw))[1:], (s, 0))
        cenefa(m, muestreo((0, ya, H - 0.22), (s * w, ya, hw - 0.12)), (0, -1))
        for k in range(5):                                           # vientos de la pared
            y = yf + (yb - yf) * k / 4
            viento(m, (s * w, y, hw), (s * (w + 1.05), y + 0.05, 0.0))
        viento(m, (s * (w - 0.05), ya, hw - 0.1), (s * (w + 0.75), ya - 0.9, 0.0))
        m.palo((s * (w - 0.05), ya, 0), (s * (w - 0.05), ya, hw - 0.04), 0.028, 0.024, PALO, lados=6, curva=0.004, var=0.1)
    # fondo: pared y hastial
    m.rejilla([[(-w + 2 * w * j / 6, yb + 0.03 * (1 if 0 < j < 6 else 0), hw) for j in range(7)],
               [(-w - 0.05 + (2 * w + 0.1) * j / 6, yb + 0.05, 0.02) for j in range(7)]], color, color_dentro=LONA_DENTRO, var=0.035)
    for y, signo in ((yb, 1), (yf, -1)):
        filas = []
        for i in range(4):
            t = i / 3
            fila = [((2 * j / 4 - 1) * w * t, y + signo * 0.02 * math.sin(math.pi * t), H + (hw - H) * t) for j in range(5)]
            filas.append(fila if signo > 0 else list(reversed(fila)))
        m.rejilla(filas, color, color_dentro=LONA_DENTRO, var=0.035)
    # frente: cortinas a rayas recogidas a los lados de la entrada
    cortina(m, -w + 0.03, -0.72, yf - 0.02, 0.03, hw)
    cortina(m, 0.72, w - 0.03, yf - 0.02, 0.03, hw)
    m.palo((-w, yf, hw), (w, yf, hw), 0.018, 0.018, PALO, lados=5, tramos=1)                     # varilla de las cortinas
    # palos mayores, cumbrera y vientos
    for y, alto in ((yf, H + 0.12), (yb, H + 0.12), (ya, H - 0.16)):
        m.palo((0, y, 0), (0, y, alto), 0.042, 0.032, PALO, lados=7, curva=0.004, var=0.1, color_tapa=PALO_CLARO)
    m.palo((0, ya - 0.05, H - 0.24), (0, yb + 0.08, H - 0.02), 0.026, 0.026, PALO, lados=6, curva=0.003, var=0.1)
    viento(m, (0, ya, H - 0.2), (0.15, ya - 2.1, 0.0), r=0.009)
    viento(m, (0, yb, H + 0.08), (-0.1, yb + 2.0, 0.0), r=0.009)
    # bajo el alero: la mesa con el mapa, un banquito y un baul
    with m.en(T(0.72, yf - 0.95, 0), R(0, 0, 8)):
        mesa_de_campana(m)
    with m.en(T(0.55, yf - 0.28, 0), R(0, 0, 100)):
        banquito(m)
    with m.en(T(-1.05, yf - 0.75, 0), R(0, 0, 84)):
        baul(m)
    # adentro: catre y otro baul
    with m.en(T(-1.2, 0.9, 0)):
        catre(m)
    with m.en(T(1.1, 1.5, 0), R(0, 0, 90)):
        baul(m, 0.7, 0.42, 0.36)
    m.almohada((0.2, 0.6, 0.012), (2.0, 2.4, 0.03), mezcla(MANTA_OSC, CUERO, 0.5), e=0.35, u=10, v=6)   # jerga en el piso
    m.objeto()
    zmod.choque_caja('ComandoIzq', (-w - 0.03, 0, hw / 2), (0.14, yb - yf, hw))
    zmod.choque_caja('ComandoDer', (w + 0.03, 0, hw / 2), (0.14, yb - yf, hw))
    zmod.choque_caja('ComandoFondo', (0, yb + 0.03, hw / 2), (2 * w, 0.14, hw))
    zmod.choque_caja('ComandoCortinaIzq', (-1.26, yf, hw / 2), (1.08, 0.14, hw))
    zmod.choque_caja('ComandoCortinaDer', (1.26, yf, hw / 2), (1.08, 0.14, hw))
    zmod.choque_caja('ComandoMesa', (0.72, yf - 0.95, 0.4), (1.1, 0.7, 0.8), rot=(0, 0, 8))
    zmod.choque_caja('ComandoBaul', (-1.05, yf - 0.75, 0.22), (0.5, 0.86, 0.44))
    zmod.choque_caja('ComandoCatre', (-1.2, 0.9, 0.28), (0.76, 1.94, 0.56))
    for nombre, x in (('PaloIzq', -w + 0.05), ('PaloMedio', 0.0), ('PaloDer', w - 0.05)):
        zmod.choque_caja('Comando' + nombre, (x, ya, 0.7), (0.1, 0.1, 1.4))


def armar_mastil():
    """Mastil de palo con la bandera de guerra (con sol), descolorida y caida, y unas piedras al pie."""
    m = Malla('MastilBandera', semilla=47)
    alto = 6.6
    m.palo((0, 0, -0.1), (0.06, 0.02, alto), 0.075, 0.035, PALO, lados=7, curva=0.006, tramos=4, var=0.1, color_tapa=PALO_CLARO)
    for a, r in ((20, 0.2), (140, 0.24), (255, 0.21), (320, 0.3)):
        ar = math.radians(a)
        m.ico((r * math.cos(ar), r * math.sin(ar), 0.05), (0.16, 0.13, 0.1), PIEDRA, sub=1, ruido=0.03, frec=4.0, var=0.12)
    # bandera: 1,5 x 0,95 m, tres franjas; cuelga y hace una onda
    ancho, alto_b, z1 = 1.5, 0.95, alto - 0.12
    nu, nv = 10, 6
    filas = []
    for j in range(nv + 1):
        v = j / nv
        fila = []
        for i in range(nu + 1):
            u = i / nu
            x = 0.07 + ancho * u * (1.0 - 0.12 * u)
            y = 0.02 + 0.13 * math.sin(u * 2 * math.pi * 1.15 + v * 0.9) * u
            z = z1 - alto_b * v - 0.42 * (u ** 1.6) * (1.0 - 0.25 * v)
            fila.append((x, y, z))
        filas.append(fila)

    # se pinta por cara segun la fila de la grilla (no por la altura, porque la bandera esta caida)
    caras = m.rejilla(filas, BLANCO, var=0.03)
    por_fila = nu * 2                                      # triangulos por fila en cada lado
    total = por_fila * nv
    for indice, f in enumerate(caras):
        fila = (indice % total) // por_fila
        if fila < 2 or fila >= 4:
            m.pintar([f], CELESTE, var=0.04)
    # sol, de los dos lados
    centro = Vector(filas[3][5])
    normal = (Vector(filas[3][6]) - Vector(filas[3][4])).cross(Vector(filas[2][5]) - Vector(filas[4][5])).normalized()
    for lado in (1, -1):
        m.cilindro(centro + normal * lado * 0.004, centro + normal * lado * 0.018, 0.11, SOL, lados=10)
    m.tubo([(0.05, 0.0, z1 + 0.05), (0.03, 0.03, 3.0), (0.02, 0.05, 1.1)], 0.005, SOGA, lados=3, tapas=False)   # driza
    m.cilindro((0.0, 0.04, 1.05), (0.03, 0.09, 1.1), 0.012, ESTACA, lados=4)                                     # cornamusa
    m.objeto()
    zmod.choque_cilindro('Mastil', (0, 0, 0), (0, 0, 2.0), 0.2)


LISTA = [
    ('carpa_tropa', 'edificios', armar_carpa_tropa, dict(vistas=((-62, 14), (118, 18)))),
    ('carpa_tropa_b', 'edificios', armar_carpa_tropa_b, dict(vistas=((-62, 14), (118, 18)))),
    ('carpa_comando', 'edificios', armar_carpa_comando, dict(vistas=((-70, 12), (-115, 18), (110, 22)), res=(720, 540))),
    ('mastil_bandera', 'props', armar_mastil, dict(vistas=((-75, 8), (20, 10)))),
]

if __name__ == '__main__':
    zmod.producir(LISTA, sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

# Tanda 6: lo que llevan los caballos de la toldería en el cruce a Chile (marcado "revisar").
# Las dos piezas se apoyan sobre el recado de un caballo: su origen va en el lomo, a la altura del
# asiento (en Blender, X cruza al caballo, -Y es hacia la cabeza y Z es arriba).
#   carga_cueros: dos cueros enrollados atravesados, una manta doblada encima y una bolsa de cuero a
#       cada lado. Sin palos de toldo (en el monte no se llevan: Cox 1863, Musters 1871).
#   montura_mantas: la montura alta de las mujeres, "un montón de cojines de cuero" y mantas (Cox 1863,
#       2.a parte, cap. V; Musters 1871, cap. III), para la anciana.
#   boleadoras_al_cinto: las boleadoras como las lleva Zenón, con los ramales dando dos vueltas a la
#       cintura por encima del tirador y las tres bolas colgando atrás de la cadera derecha. Su origen
#       es el hueso de la cadera de Zenón (X: su izquierda; -Y: adelante; Z: arriba).
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from zmod import Malla, T, R, S, lin, mezcla
from mathutils import Vector

CUERO_CRUDO = lin('#8f7a5e')
CUERO_OSC = lin('#6b5540')
PELO = lin('#6a4a34')
PELO_CLARO = lin('#9a8468')
TIENTO = lin('#4e3a2b')
MANTA_OCRE = lin('#8f7448')
MANTA_PARDA = lin('#5f5244')
MANTA_GRIS = lin('#7d776a')
ROJO = lin('#7a3b33')
LANA_CRUDA = lin('#8a8270')


def manchar(m, caras, color, cuanto):
    """Manchones de pelo sobre el cuero."""
    for f in caras:
        if m.rng.random() < cuanto:
            m.pintar([f], mezcla(color, CUERO_CRUDO, m.rng.uniform(0.0, 0.45)))


def rollo(m, y, z, largo, radio, color, giro=0.0):
    """Un cuero enrollado, atravesado sobre el lomo, atado con dos tientos."""
    with m.en(T(0, y, z), R(0, 0, giro)):
        h = largo / 2.0
        caras = m.tubo([(-h, 0, 0), (-h + 0.03, 0, 0), (h - 0.03, 0, 0), (h, 0, 0)], [radio * 0.72, radio, radio, radio * 0.72],
                       color, lados=9, color_tapa=PELO, var=0.1)
        manchar(m, caras, PELO, 0.28)
        for x in (-h * 0.55, h * 0.55):
            m.tubo([(x - 0.012, 0, 0), (x + 0.012, 0, 0)], radio + 0.006, TIENTO, lados=9, tapas=False)


def armar_carga_cueros():
    m = Malla('CargaCueros', semilla=61)
    # dos cueros enrollados, uno delante del otro, apenas cruzados
    rollo(m, -0.15, 0.1, 0.84, 0.105, CUERO_CRUDO, giro=3)
    rollo(m, 0.14, 0.095, 0.78, 0.1, mezcla(CUERO_CRUDO, CUERO_OSC, 0.4), giro=-4)
    # una manta doblada encima, con una sola guarda roja apagada
    m.almohada((0, 0.0, 0.215), (0.52, 0.4, 0.085), MANTA_OCRE, e=0.42, u=10, v=6, ruido=0.012, frec=5.0, var=0.08)
    m.caja((0, -0.125, 0.258), (0.44, 0.035, 0.006), ROJO, var=0.05)
    m.caja((0, 0.125, 0.258), (0.44, 0.035, 0.006), MANTA_PARDA, var=0.05)
    # una bolsa de cuero a cada lado, colgada de un tiento que pasa por arriba
    for s in (-1, 1):
        with m.en(T(s * 0.44, 0.02, -0.26), R(0, s * 7, 0)):
            caras = m.almohada((0, 0, 0), (0.17, 0.36, 0.4), CUERO_OSC, e=0.55, u=10, v=7, ruido=0.014, frec=4.0, var=0.1)
            manchar(m, caras, PELO_CLARO, 0.12)
            m.almohada((0, 0, 0.19), (0.15, 0.3, 0.07), mezcla(CUERO_OSC, TIENTO, 0.5), e=0.6, u=8, v=5)   # la boca, fruncida
        for y in (-0.1, 0.12):
            m.tubo([(s * 0.42, y, -0.08), (s * 0.4, y, 0.1), (s * 0.26, y, 0.2), (0, y, 0.265)], 0.008, TIENTO, lados=4, tapas=False)
    m.objeto()


def armar_montura_mantas():
    m = Malla('MonturaMantas', semilla=67)
    # abajo, un cuero con el pelo hacia arriba que cuelga a los costados
    caras = m.almohada((0, 0, 0.0), (0.68, 0.62, 0.07), CUERO_CRUDO, e=0.45, u=12, v=6, ruido=0.012, frec=4.0, var=0.1)
    manchar(m, caras, PELO, 0.5)
    for s in (-1, 1):
        caras = m.almohada((s * 0.33, 0, -0.14), (0.07, 0.56, 0.32), CUERO_CRUDO, e=0.5, u=8, v=6, ruido=0.01, frec=4.0, var=0.1,
                           rot=(0, s * 12, 0))
        manchar(m, caras, PELO, 0.5)
    # en el medio, dos cojines de cuero rellenos y una manta doblada
    m.almohada((0, -0.03, 0.055), (0.56, 0.5, 0.075), CUERO_OSC, e=0.5, u=10, v=6, ruido=0.012, frec=5.0, var=0.1)
    m.almohada((0, 0.0, 0.115), (0.52, 0.46, 0.07), MANTA_PARDA, e=0.42, u=10, v=6, ruido=0.01, frec=5.0, var=0.08)
    m.caja((0, -0.17, 0.152), (0.46, 0.03, 0.006), ROJO, var=0.05)
    m.caja((0, 0.17, 0.152), (0.46, 0.03, 0.006), MANTA_GRIS, var=0.05)
    # arriba, lana cruda: donde se sienta
    m.almohada((0, 0.01, 0.168), (0.46, 0.4, 0.06), LANA_CRUDA, e=0.5, u=10, v=6, ruido=0.016, frec=7.0, var=0.12)
    # la cincha que lo sujeta todo
    for y in (-0.16, 0.16):
        m.tubo([(-0.36, y, -0.27), (-0.345, y, -0.02), (-0.27, y, 0.13), (0, y, 0.205), (0.27, y, 0.13), (0.345, y, -0.02), (0.36, y, -0.27)],
               0.011, TIENTO, lados=4, tapas=False)
    m.objeto()


def armar_boleadoras_al_cinto():
    m = Malla('BoleadorasAlCinto', semilla=71)
    radio = 0.2            # el de la cintura de Zenón por fuera del tirador, medido en su malla
    cuelga = math.radians(36)   # dónde cuelgan las bolas: 0 es la cadera derecha; 90, la espalda

    def cintura(a, r=radio):
        return (-r * math.cos(a), r * math.sin(a))

    def alto(a, base):
        # los ramales bajan un poco del lado donde tiran las bolas
        return base - 0.014 * (0.5 + 0.5 * math.cos(a - cuelga))

    # las dos vueltas de tiento torcido
    for base, desfase, color in ((0.052, 0.0, TIENTO), (0.036, 0.4, mezcla(TIENTO, CUERO_OSC, 0.5))):
        pts = []
        for i in range(31):
            a = 2.0 * math.pi * i / 30 + desfase
            x, y = cintura(a, radio + (0.004 if desfase else 0.0))
            pts.append((x, y, alto(a, base)))
        m.tubo(pts, 0.0065, color, lados=5, tapas=False, var=0.08)
    # las tres bolas retobadas: dos grandes y la manija, más chica y más arriba
    for corre, largo, r, color in ((-0.2, 0.105, 0.024, mezcla(CUERO_CRUDO, CUERO_OSC, 0.25)),
                                   (0.02, 0.2, 0.031, CUERO_CRUDO),
                                   (0.22, 0.155, 0.031, mezcla(CUERO_CRUDO, PELO_CLARO, 0.4))):
        a = cuelga + corre
        x0, y0 = cintura(a)
        z0 = alto(a, 0.044)
        # más abajo la pierna es más angosta que la cintura: la bola cuelga a plomo y la toca apenas
        x1, y1 = cintura(a, radio + r * 0.55)
        z1 = z0 - largo
        m.tubo([(x0, y0, z0), ((x0 + x1) / 2, (y0 + y1) / 2, z0 - largo * 0.5), (x1, y1, z1 + r * 0.8)], 0.0045, TIENTO,
               lados=4, tapas=False)
        m.esfera((x1, y1, z1), (r, r, r * 1.08), color, u=9, v=7, ruido=0.002, frec=9.0, var=0.1)
        # la costura del retobo y el nudo de arriba
        m.tubo([(x1, y1, z1 + r * 1.02), (x1, y1, z1 + r * 1.25)], [0.011, 0.006], TIENTO, lados=5)
    m.objeto()


LISTA = [
    ('carga_cueros', 'props', armar_carga_cueros, dict(vistas=((-62, 16), (118, 20)), figura=False)),
    ('montura_mantas', 'props', armar_montura_mantas, dict(vistas=((-62, 16), (118, 20)), figura=False)),
    ('boleadoras_al_cinto', 'props', armar_boleadoras_al_cinto, dict(vistas=((-150, 14), (118, 20)), figura=False)),
]

if __name__ == '__main__':
    zmod.producir(LISTA, sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

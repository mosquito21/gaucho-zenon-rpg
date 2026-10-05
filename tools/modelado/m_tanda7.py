# Tanda 7: lo que Zenón lleva en el anca de Ceniza cuando hace un conchabo.
# Las dos piezas se apoyan sobre el anca: su origen va en el lomo, a la altura del asiento (en
# Blender, X cruza al caballo, -Y es hacia la cabeza y Z es arriba), igual que las de la tanda 6.
#   atado_lenia: la leña de jarilla y de alpataco, en dos haces atados con tientos, uno a cada costado del anca.
#       (Leña de jarilla y de alpataco en el alto Limay: Olascoaga 1880. "Verificar".)
#   ponchos_doblados: tres ponchos doblados, uno sobre otro, atados en cruz con un tiento. Son los de
#       la tejedora de la toldería (marcado "revisar"): lana en colores de la tierra, guardas sobrias y
#       un solo rojo apagado. Sin figuras: no copio ningún diseño que no pueda respaldar.
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from zmod import Malla, T, R, S, lin, mezcla

JARILLA = lin('#6f6248')        # rama fina, gris verdosa
ALPATACO = lin('#54412f')       # rama más gruesa y oscura
CORTE = lin('#8f7d58')          # la madera del corte (en el juego el sol la aclara)
TIENTO = lin('#4e3a2b')
LANA_OCRE = lin('#8f7448')
LANA_PARDA = lin('#5f5244')
LANA_GRIS = lin('#7d776a')
LANA_CRUDA = lin('#8a8270')
LANA_NEGRA = lin('#3b352f')
ROJO = lin('#7a3b33')


def haz(m, lado):
    """Un haz de ramas a lo largo del caballo, colgado de ese costado del anca (lado: -1 o 1)."""
    largo = 0.98
    radio_haz = 0.092
    # cuelga un poco más bajo que el lomo y con la punta de adelante apenas levantada
    with m.en(T(lado * 0.385, 0.06, -0.2), R(-6, 0, lado * 4)):
        for i in range(11):
            a = m.rng.uniform(0, 2 * math.pi)
            r = radio_haz * math.sqrt(m.rng.random())
            x = r * math.cos(a) * 0.8
            z = r * math.sin(a)
            h = largo / 2.0 * m.rng.uniform(0.8, 1.0)
            corre = m.rng.uniform(-0.05, 0.05)
            gruesa = m.rng.random() < 0.35
            radio = m.rng.uniform(0.018, 0.026) if gruesa else m.rng.uniform(0.011, 0.016)
            color = mezcla(ALPATACO if gruesa else JARILLA, JARILLA if gruesa else ALPATACO, m.rng.uniform(0.0, 0.3))
            t = lambda k: m.rng.uniform(-k, k)
            # el corte, hacia adelante; la punta fina de la rama, hacia atrás
            pts = [(x + t(0.015), -h + corre, z + t(0.015)), (x + t(0.02), -h * 0.35 + corre, z + t(0.02)),
                   (x + t(0.02), h * 0.3 + corre, z + t(0.02)), (x + t(0.03), h + corre, z + t(0.03))]
            m.tubo(pts, [radio, radio * 0.95, radio * 0.86, radio * 0.66], color, lados=5, color_tapa=CORTE, var=0.12)
            # alguna ramita que se abre hacia afuera y hacia atrás
            if m.rng.random() < 0.4:
                y0 = m.rng.uniform(-h * 0.3, h * 0.6) + corre
                m.tubo([(x, y0, z), (x + lado * m.rng.uniform(0.02, 0.07), y0 + 0.1, z + t(0.06)), (x + lado * m.rng.uniform(0.04, 0.12), y0 + 0.19, z + t(0.1))],
                       [radio * 0.5, radio * 0.38, radio * 0.2], color, lados=4, var=0.1)
        # los dos tientos que cierran el haz
        for y in (-0.25, 0.27):
            vuelta = []
            for k in range(11):
                a = 2.0 * math.pi * k / 10
                vuelta.append(((radio_haz + 0.014) * 0.84 * math.cos(a), y + 0.006 * math.sin(a * 2), (radio_haz + 0.014) * math.sin(a)))
            m.tubo(vuelta, 0.007, TIENTO, lados=4, tapas=False, var=0.06)


def armar_atado_lenia():
    m = Malla('AtadoLenia', semilla=73)
    # La leña va en dos haces, uno a cada costado del anca, para que no moleste lo que vaya arriba
    # (los ponchos o el tercio de yerba) ni las piernas del jinete.
    for lado in (-1, 1):
        haz(m, lado)
    # los tientos que cruzan por arriba del anca y sostienen los dos haces
    for y in (-0.19, 0.33):
        m.tubo([(-0.385, y, -0.11), (-0.3, y, 0.0), (-0.12, y, 0.035), (0.12, y, 0.035), (0.3, y, 0.0), (0.385, y, -0.11)],
               0.007, TIENTO, lados=4, tapas=False, var=0.06)
    m.objeto()


def armar_ponchos_doblados():
    m = Malla('PonchosDoblados', semilla=79)
    # de abajo arriba: pardo, crudo con guarda negra, ocre con una guarda roja
    pisos = ((0.0, (0.54, 0.44, 0.075), LANA_PARDA, LANA_GRIS, 3.0),
             (0.07, (0.52, 0.42, 0.07), LANA_CRUDA, LANA_NEGRA, -4.0),
             (0.136, (0.5, 0.4, 0.07), LANA_OCRE, ROJO, 2.0))
    for z, tam, color, guarda, giro in pisos:
        with m.en(T(0, 0, z + tam[2] / 2.0), R(0, 0, giro)):
            m.almohada((0, 0, 0), tam, color, e=0.4, u=12, v=6, ruido=0.01, frec=6.0, var=0.08)
            # el doblez: una línea más oscura al medio, a lo largo
            m.caja((0, 0, tam[2] * 0.02), (tam[0] * 0.98, 0.006, tam[2] * 0.82), mezcla(color, LANA_NEGRA, 0.35), var=0.03)
            # las guardas, cerca de los dos bordes, y los flecos apenas marcados
            for s in (-1, 1):
                m.caja((s * tam[0] * 0.36, 0, tam[2] * 0.42), (0.035, tam[1] * 0.9, 0.008), guarda, var=0.05)
                m.caja((s * tam[0] * 0.43, 0, tam[2] * 0.4), (0.012, tam[1] * 0.9, 0.008), mezcla(guarda, color, 0.5), var=0.05)
    # el tiento en cruz que los mantiene juntos
    alto = 0.136 + 0.07
    m.tubo([(-0.275, 0, -0.005), (-0.27, 0, alto * 0.6), (-0.2, 0, alto + 0.004), (0.2, 0, alto + 0.004), (0.27, 0, alto * 0.6), (0.275, 0, -0.005)],
           0.007, TIENTO, lados=4, tapas=False)
    m.tubo([(0, -0.225, -0.005), (0, -0.22, alto * 0.6), (0, -0.16, alto + 0.006), (0, 0.16, alto + 0.006), (0, 0.22, alto * 0.6), (0, 0.225, -0.005)],
           0.007, TIENTO, lados=4, tapas=False)
    m.objeto()


def armar_tercio_al_anca():
    """El tercio de yerba que Ceferino le manda a la tejedora, atravesado en el anca. Es el de
    m_bultos.py (assets/props/tercio.glb), un poco más chico, atado al recado y SIN caja de choque:
    con ella, montado, Ceniza chocaba contra su propia carga y no avanzaba."""
    m = Malla('TercioAlAnca', semilla=31)
    cuero = lin('#9a8163')
    pelo = lin('#6a4a34')
    with m.en(T(0, 0, 0.165)):
        xs = [-0.28, -0.25, -0.15, 0.0, 0.15, 0.25, 0.28]
        rs = [0.07, 0.145, 0.17, 0.175, 0.17, 0.145, 0.07]
        caras = m.tubo([(x, 0, 0) for x in xs], rs, cuero, lados=10, var=0.1)
        for f in caras:                                         # manchones de pelo
            if m.rng.random() < 0.22:
                m.pintar([f], mezcla(pelo, cuero, m.rng.uniform(0.0, 0.4)))
        # la costura del retobo, por arriba
        m.tubo([(x, 0.02 * math.sin(x * 40), 0.176 if abs(x) < 0.19 else 0.152) for x in [-0.25 + 0.042 * i for i in range(13)]],
               0.007, TIENTO, lados=3, tapas=False)
        for x in (-0.28, 0.28):
            m.esfera((x * 1.04, 0, 0), (0.032, 0.068, 0.068), mezcla(cuero, TIENTO, 0.5), u=7, v=5)
        # los dos tientos que lo abrazan y bajan a los costados del recado
        for x in (-0.14, 0.14):
            vuelta = []
            for k in range(11):
                a = 2.0 * math.pi * k / 10
                vuelta.append((x, 0.182 * math.cos(a), 0.182 * math.sin(a)))
            m.tubo(vuelta, 0.007, TIENTO, lados=4, tapas=False, var=0.06)
    for x in (-0.14, 0.14):
        for s in (-1, 1):
            m.tubo([(x, s * 0.16, 0.08), (x * 1.6, s * 0.24, -0.04), (x * 1.9, s * 0.28, -0.2)], 0.006, TIENTO, lados=4, tapas=False)
    m.objeto()


LISTA = [
    ('atado_lenia', 'props', armar_atado_lenia, dict(vistas=((-62, 16), (118, 20)), figura=False)),
    ('ponchos_doblados', 'props', armar_ponchos_doblados, dict(vistas=((-62, 16), (118, 20)), figura=False)),
    ('tercio_al_anca', 'props', armar_tercio_al_anca, dict(vistas=((-62, 16), (118, 20)), figura=False)),
]

if __name__ == '__main__':
    zmod.producir(LISTA, sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

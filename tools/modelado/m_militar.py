# Equipo militar de 1881: fusil Remington, pabellon de fusiles, mochila, cantimplora y armero.
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from zmod import Malla, T, R, S, lin, mezcla, catenaria
from mathutils import Vector, Matrix

NOGAL = lin('#4a3324')
NOGAL_CLARO = lin('#6a4a33')
ACERO = lin('#3b3a3a')
ACERO_CLARO = lin('#6f7070')
CUERO = lin('#5a4234')
CUERO_OSCURO = lin('#3a2a20')
LONA = lin('#b9b097')
LONA_SUCIA = lin('#9c9078')
MANTA = lin('#56606a')
LATA = lin('#8a8a85')
PANO = lin('#a08a62')
CORCHO = lin('#6b4a2e')
MADERA = lin('#6b5440')
MADERA_GRIS = lin('#7a6a58')


def fusil(m, bayoneta=False, correa=True):
    """Remington rolling block de 1,28 m. Local: X a lo largo (culata en 0, boca en 1,28), Z hacia las miras."""
    m.prisma([(0.0, -0.105), (0.30, -0.05), (0.37, -0.04), (0.37, 0.016), (0.24, 0.012), (0.0, 0.006)],
             -0.021, 0.021, NOGAL, var=0.08)
    m.caja((0.006, 0, -0.05), (0.012, 0.044, 0.112), ACERO, mat='Metal')                 # cantonera
    m.caja((0.42, 0, -0.012), (0.105, 0.04, 0.062), ACERO, mat='Metal')                  # caja del mecanismo
    m.cilindro((0.43, -0.022, 0.012), (0.43, 0.022, 0.012), 0.016, ACERO_CLARO, lados=6, mat='Metal')   # bloque rodante
    m.caja((0.392, 0, 0.034), (0.014, 0.012, 0.05), ACERO, rot=(0, -28, 0), mat='Metal')  # martillo
    m.tubo([(0.385, 0, -0.043), (0.395, 0, -0.078), (0.445, 0, -0.082), (0.465, 0, -0.043)], 0.0035, ACERO,
           lados=4, tapas=False, mat='Metal')                                           # guardamonte
    m.tubo([(0.47, 0, -0.012), (0.80, 0, -0.01), (1.04, 0, -0.006)], [0.02, 0.018, 0.016], NOGAL, lados=6, var=0.08)
    m.tubo([(0.45, 0, 0.006), (1.28, 0, 0.006)], [0.0115, 0.009], ACERO, lados=6, mat='Metal')            # cañon
    for x in (0.62, 0.84, 1.03):
        m.cilindro((x - 0.011, 0, -0.003), (x + 0.011, 0, -0.003), 0.0225, ACERO_CLARO, lados=6, mat='Metal')
    m.tubo([(0.6, 0, -0.026), (1.265, 0, -0.012)], 0.003, ACERO_CLARO, lados=4, mat='Metal')                # baqueta
    m.caja((0.56, 0, 0.022), (0.03, 0.012, 0.012), ACERO, mat='Metal')                    # alza
    m.caja((1.25, 0, 0.02), (0.008, 0.004, 0.012), ACERO, mat='Metal')                    # punto de mira
    if correa:
        puntos = catenaria((0.2, 0, -0.072), (0.84, 0, -0.03), 0.07, 8)
        m.rejilla([[p + Vector((0, -0.012, 0)) for p in puntos], [p + Vector((0, 0.012, 0)) for p in puntos]],
                  CUERO, grosor=0.004, var=0.06)
    if bayoneta:
        m.cilindro((1.2, 0.018, 0.006), (1.27, 0.018, 0.006), 0.012, ACERO_CLARO, lados=6, mat='Metal')
        m.tubo([(1.26, 0.02, 0.006), (1.3, 0.024, 0.006), (1.76, 0.024, 0.006)], [0.006, 0.007, 0.001], ACERO_CLARO,
               lados=3, mat='Metal')


def apoyado(pie, punta_hacia, giro=0.0):
    """Matriz que pone un fusil con la culata en 'pie' y el cañon apuntando hacia 'punta_hacia'."""
    pie, punta = Vector(pie), Vector(punta_hacia)
    x = (punta - pie).normalized()
    y = Vector((0, 0, 1)).cross(x).normalized()
    z = x.cross(y)
    M = Matrix((x, y, z)).transposed().to_4x4()
    M.translation = pie
    # la culata apoya su talon: se sube lo que baja la cantonera
    return M @ T(0, 0, 0) @ R(giro, 0, 0) @ T(0, 0, 0.05)


def armar_fusil():
    m = Malla('FusilRemington', semilla=3)
    with m.en(T(-0.64, 0, 0.03), R(90, 0, 0)):       # acostado de lado en el suelo
        fusil(m)
    m.objeto()


def armar_pabellon():
    m = Malla('PabellonFusiles', semilla=5)
    radio, alto = 0.44, 1.2
    for i, a in enumerate((90, 210, 330)):
        ar = math.radians(a)
        pie = (radio * math.cos(ar), radio * math.sin(ar), 0.0)
        # cada cañon pasa un poco al costado del eje para que se crucen sin atravesarse
        desvio = Vector((-math.sin(ar), math.cos(ar), 0)) * 0.035
        with m.en(apoyado(pie, Vector((0, 0, alto)) + desvio)):
            fusil(m, bayoneta=True, correa=(i != 1))
    ar = math.radians(150)
    with m.en(apoyado((0.62 * math.cos(ar), 0.62 * math.sin(ar), 0.0), (0.05, 0.02, 1.0), giro=25)):
        fusil(m, bayoneta=False)
    # correa que ata las bocas
    m.tubo([(0.05 * math.cos(math.radians(a)), 0.05 * math.sin(math.radians(a)), 1.13) for a in range(0, 361, 60)],
           0.008, CUERO, lados=4, tapas=False)
    m.objeto()
    zmod.choque_cilindro('Pabellon', (0, 0, 0), (0, 0, 1.3), 0.4)


def mochila(m):
    """Mochila de lona con la manta arrollada en herradura y la marmita atras. Local: espalda hacia -Y."""
    m.caja((0, 0, 0.18), (0.36, 0.13, 0.34), LONA, var=0.05, sombra=0.25)
    m.caja((0, 0.004, 0.345), (0.375, 0.15, 0.03), mezcla(LONA, LONA_SUCIA, 0.3), rot=(4, 0, 0))     # tapa
    m.caja((0, 0.072, 0.25), (0.37, 0.012, 0.2), mezcla(LONA, LONA_SUCIA, 0.25))                     # solapa
    for x in (-0.09, 0.09):
        m.caja((x, 0.08, 0.19), (0.028, 0.008, 0.34), CUERO_OSCURO)
        m.caja((x, 0.086, 0.13), (0.036, 0.006, 0.03), LATA, mat='Metal')
    herradura = [(-0.215, 0, 0.03), (-0.22, 0, 0.3)]
    for i in range(1, 8):
        a = math.pi - math.pi * i / 8.0
        herradura.append((0.22 * math.cos(a), 0, 0.3 + 0.115 * math.sin(a)))
    herradura += [(0.22, 0, 0.3), (0.215, 0, 0.03)]
    m.tubo(herradura, 0.052, MANTA, lados=8, var=0.07, color_tapa=mezcla(MANTA, (0, 0, 0), 0.35))
    for p in ((-0.218, 0, 0.14), (0.218, 0, 0.14), (0, 0, 0.415)):
        eje = Vector((0, 0, 1)) if abs(p[0]) > 0.1 else Vector((1, 0, 0))
        m.cilindro(Vector(p) - eje * 0.012, Vector(p) + eje * 0.012, 0.056, CUERO_OSCURO, lados=8)
    m.cilindro((0, 0.07, 0.2), (0, 0.125, 0.2), 0.078, LATA, lados=10, mat='Metal', color_tapa=mezcla(LATA, (0, 0, 0), 0.2))
    for x in (-0.11, 0.11):                                             # tirantes que cuelgan del lado de la espalda
        puntos = [(x, -0.066, 0.34), (x * 1.15, -0.1, 0.2), (x * 1.3, -0.09, 0.05), (x * 1.7, -0.1, 0.004), (x * 2.3, -0.16, 0.004)]
        m.rejilla([[Vector(p) + Vector((-0.018, 0, 0)) for p in puntos], [Vector(p) + Vector((0.018, 0, 0)) for p in puntos]],
                  CUERO, grosor=0.004, var=0.05)


def armar_mochila():
    m = Malla('Mochila', semilla=7)
    with m.en(R(-9, 0, 0)):
        mochila(m)
    m.objeto()
    zmod.choque_caja('Mochila', (0, 0.01, 0.2), (0.46, 0.24, 0.42))


def cantimplora(m):
    """Caramañola redonda forrada en paño, con tapon de corcho y correa. Local: parada, de canto."""
    m.esfera((0, 0, 0.095), (0.09, 0.042, 0.09), PANO, u=10, v=6, var=0.05, sombra=0.2)
    m.tubo([(0, 0, 0.176 + 0.0), (0, 0, 0.176 + 0.03)], 0.014, LATA, lados=6, mat='Metal')
    m.cilindro((0, 0, 0.206), (0, 0, 0.226), 0.011, CORCHO, lados=6)
    # costura del forro
    m.tubo([(0.092 * math.cos(a), 0, 0.095 + 0.092 * math.sin(a)) for a in [math.radians(g) for g in range(-70, 251, 40)]],
           0.004, mezcla(PANO, (0, 0, 0), 0.35), lados=3, tapas=False)


def armar_cantimplora():
    """Acostada en el suelo, con la correa tendida adelante."""
    m = Malla('Cantimplora', semilla=9)
    with m.en(T(0, 0.095, 0.042), R(90, 0, 0)):
        cantimplora(m)
    dentro, fuera = [Vector((-0.062, -0.075, 0.05))], [Vector((-0.04, -0.075, 0.05))]
    for g in range(115, 426, 22):
        a = math.radians(g)
        dentro.append(Vector((0.159 * math.cos(a), -0.26 + 0.119 * math.sin(a), 0.006)))
        fuera.append(Vector((0.181 * math.cos(a), -0.26 + 0.141 * math.sin(a), 0.006)))
    dentro.append(Vector((0.04, -0.075, 0.05)))
    fuera.append(Vector((0.062, -0.075, 0.05)))
    m.rejilla([fuera, dentro], CUERO, grosor=0.004, var=0.05)
    m.objeto()


def armar_armero():
    """Armero de palos para el rancho del fortin: cinco fusiles parados y dos mochilas colgadas."""
    m = Malla('Armero', semilla=11)
    ancho = 1.5
    for x in (-ancho / 2, ancho / 2):
        m.palo((x, 0, 0), (x, 0.02, 1.25), 0.045, 0.036, MADERA_GRIS, lados=6, var=0.1, color_tapa=NOGAL_CLARO)
        m.palo((x, 0, 0.0), (x, -0.42, 0.0), 0.04, 0.035, MADERA_GRIS, lados=6, var=0.1)
    m.palo((-ancho / 2 - 0.08, 0.005, 1.02), (ancho / 2 + 0.08, 0.005, 1.02), 0.03, 0.028, MADERA, lados=6, var=0.1)
    m.palo((-ancho / 2 - 0.05, -0.36, 0.05), (ancho / 2 + 0.05, -0.36, 0.05), 0.035, 0.035, MADERA, lados=6, var=0.1)
    for x in (-ancho / 2, ancho / 2):                       # ataduras de tiento
        m.cilindro((x - 0.05, 0.005, 1.02), (x + 0.05, 0.005, 1.02), 0.04, CUERO, lados=6)
    for i in range(5):
        x = -0.52 + i * 0.26 + m.rng.uniform(-0.02, 0.02)
        pie = (x, -0.34 + m.rng.uniform(-0.02, 0.02), 0.07)
        with m.en(apoyado(pie, (x + m.rng.uniform(-0.015, 0.015), 0.03, 1.07), giro=m.rng.uniform(-8, 8))):
            fusil(m, correa=(i % 2 == 0))
    for x, giro in ((-ancho / 2 - 0.0, 90), (ancho / 2 + 0.0, -90)):
        with m.en(T(x + (0.11 if giro > 0 else -0.11) * -1, 0.02, 0.62), R(0, 0, giro), S(0.9)):
            mochila(m)
    with m.en(T(0.39, 0.05, 0.86), R(0, 0, 180)):
        cantimplora(m)
    m.objeto()
    zmod.choque_caja('Armero', (0, -0.16, 0.65), (ancho + 0.5, 0.6, 1.3))


LISTA = [
    ('fusil_remington', 'props', armar_fusil, dict(vistas=((-70, 35), (60, 60)), figura=False)),
    ('pabellon_fusiles', 'props', armar_pabellon, dict(vistas=((-62, 14), (30, 40)))),
    ('mochila', 'props', armar_mochila, dict(vistas=((-62, 20), (118, 20)), figura=False)),
    ('cantimplora', 'props', armar_cantimplora, dict(vistas=((-62, 25), (100, 30)), figura=False)),
    ('armero', 'props', armar_armero, dict(vistas=((-62, 14), (118, 18)))),
]

if __name__ == '__main__':
    zmod.producir(LISTA, sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

# Las manos de Zenón.
#
# El modelo de Hunyuan traía los dedos pegados en una paleta larga, rosada y con las rayas de la
# camisa corridas encima. La primera versión de este programa (11 de noviembre de 2026) las cambió por
# manos armadas con tubos de un solo color: tenían dedos, pero parecían hechas con salchichas. Esta
# es la segunda: la mano se modela como una sola pieza, de adentro hacia afuera, y se le pinta la piel.
#
# Cómo se hace:
#   1. La forma. La mano se describe como un "campo de distancias": para cada punto del espacio, a
#      cuánto queda de la piel. Se arma sumando piezas blandas (los huesos de la palma, los nudillos,
#      la base del pulgar, las tres falanges de cada dedo, más gruesas en las articulaciones) que se
#      funden entre sí como arcilla. De ese campo sale la malla, y se aliviana.
#   2. La piel. Una imagen pintada por programa, punto por punto, sabiendo dónde cae cada uno: más
#      clara en la palma, más oscura en los huecos entre los dedos, rojiza en los nudillos, con los
#      pliegues de cada articulación, las líneas de la palma y las uñas.
#   3. El esqueleto. Es el de Mixamo, que trae dos cadenas por mano (índice y pulgar; el índice mueve
#      los cuatro dedos, como un mitón). Los huesos de los dedos se mudan a las articulaciones nuevas
#      sin cambiarles la orientación, así los clips doblan los dedos igual que antes.
#
# Se corre con Blender 5.2 sin ventana, desde la raíz del proyecto, SOBRE EL MODELO DE LAS MANOS
# VIEJAS (el de antes del 11 de noviembre, guardado en .revision/respaldo-2026-11-11/):
#   "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b .revision/respaldo-2026-11-11/assets/personajes/gaucho_zenon_animado.blend -P tools/modelado/manos_zenon.py -- <carpeta de salida> [--previa] [--solo-mano] [--fino]
# Si esa carpeta no está (no se sube a git), el mismo modelo es el de la versión v0.1.1. Desde cmd o
# Git Bash (no desde PowerShell, que rompe el archivo):
#   git show v0.1.1:assets/personajes/gaucho_zenon_animado.blend > zenon_manos_viejas.blend
# Escribe en la carpeta de salida gaucho_zenon_animado.blend y .glb (no pisa los de assets/: se copian
# a mano cuando el resultado convence) y la imagen de la piel. Con --previa saca vistas de control;
# con --solo-mano arma y fotografía la mano sola, sin tocar a Zenón (para probar medidas);
# con --fino trabaja con más detalle (tarda el doble).
# Corrido sobre un modelo que ya tiene manos nuevas no hace nada y avisa.
import bpy, bmesh, sys, os, math, time
import numpy as np
import openvdb as vdb
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
SALIDA = os.path.abspath(next((a for a in args if not a.startswith('--')), '.revision/manos'))
PREVIA = '--previa' in args
SOLO_MANO = '--solo-mano' in args
FINO = '--fino' in args
os.makedirs(SALIDA, exist_ok=True)

CM = 0.01
# ================================================================ medidas (en centímetros)
# La mano se piensa apoyada con la palma hacia abajo: X va de la muñeca a los dedos, Y hacia el
# pulgar y Z hacia el dorso. El origen es la muñeca (donde nace el hueso de la mano).
#
# Los nudillos: dónde nace cada dedo. Índice, mayor, anular y meñique.
NUDILLOS = {'indice': (8.95, 3.15, -0.15), 'mayor': (9.25, 1.05, -0.05), 'anular': (8.85, -1.05, -0.15), 'menique': (8.05, -3.05, -0.4)}
# Cada dedo: el largo de sus tres falanges; el radio (medio ancho) en el nudillo, en las dos
# articulaciones y en la punta; cuántos grados se abre hacia el pulgar; y cuántos grados viene
# doblada cada articulación con la mano floja (una mano de verdad nunca está derecha como una tabla).
DEDOS = {
    'indice': dict(largos=(4.3, 2.5, 2.2), radios=(1.08, 0.96, 0.84, 0.74), abre=6.0, dobla=(7.0, 12.0, 8.0)),
    'mayor': dict(largos=(4.7, 2.9, 2.3), radios=(1.11, 0.98, 0.86, 0.76), abre=1.0, dobla=(8.0, 14.0, 9.0)),
    'anular': dict(largos=(4.3, 2.7, 2.3), radios=(1.04, 0.93, 0.81, 0.72), abre=-4.5, dobla=(9.0, 16.0, 10.0)),
    'menique': dict(largos=(3.4, 2.0, 2.0), radios=(0.92, 0.81, 0.71, 0.63), abre=-10.0, dobla=(10.0, 18.0, 11.0)),
}
# Cuánto más chato que ancho es un dedo (falange por falange) y cuánto se afina entre articulaciones.
CHATOS = (0.88, 0.88, 0.84)
CINTURA = 0.95
# Largo de la uña, desde la punta del dedo hacia atrás.
UNIA = 1.1
# El pulgar: dónde nace (junto a la muñeca), el largo de sus tres huesos (el primero va por adentro
# de la palma: es la base carnosa), sus radios y cuánto viene doblado. Hacia dónde apunta lo dice el
# hueso de Mixamo, para que los clips lo muevan bien.
PULGAR = dict(nace=(2.0, 2.6, -1.0), largos=(4.3, 3.1, 2.7), radios=(1.95, 1.33, 1.17, 1.0), dobla=(0.0, 6.0, 12.0),
              chatos=(1.0, 0.9, 0.82), unia=1.35)
# La palma: de dónde salen los cuatro huesos que van a los nudillos (X, las cuatro Y, Z), el radio en
# cada punta, el canto del lado del meñique y la almohadilla de la base de los dedos.
PALMA = dict(carpo_x=1.2, carpo_y=(1.9, 0.65, -0.65, -1.9), carpo_z=-0.35, radio_carpo=1.42, radio_nudillo=1.22,
             canto=((1.8, -2.7, -1.0), (6.6, -3.2, -0.95), 1.5, 1.15),
             almohadilla=((8.0, 2.9, -1.0), (7.4, -2.8, -1.05), 0.95, 0.9),
             nudillo_alto=0.62, nudillo_radio=0.82)
# La muñeca: medio ancho, cuánto más chata que ancha, y hasta dónde entra en la manga.
MUNECA = dict(ancho=3.05, chato=0.7, desde=-5.5, hasta=0.9, z=-0.35)
# El tono de la piel, como se ve en pantalla (rojo, verde, azul, de 0 a 1). Con None se mide en la
# cara de Zenón. Medido en el juego, al mismo sol, la cara da un castaño más oscuro y menos rosado que
# lo que salía midiendo la textura: este valor está elegido mirando las fotos del juego.
TONO = (0.4, 0.24, 0.175)
# Cuántos triángulos lleva cada mano y el lado de la imagen de la piel, en puntos.
CARAS = 5200
TEXTURA = 1024
# Cada cuánto se mira el campo para sacar la malla (más chico, más detalle y más tiempo).
GRANO = 0.08 if FINO else 0.11
# El corte del modelo viejo: a cuántos centímetros de la muñeca, hacia el codo (lo que queda es manga).
CORTE = 0.4


def informe(*cosas):
    print('[manos]', *cosas)
    sys.stdout.flush()


def paso(x, a, b):
    """Sube suave de 0 a 1 mientras x va de a a b (si a es mayor que b, baja)."""
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def versor(v):
    v = np.array(v, dtype=np.float64)
    return v / np.linalg.norm(v)


# ================================================================ la forma: el campo de distancias
def suma(a, b, k):
    """Junta dos piezas fundiéndolas en una franja de ancho k (como arcilla)."""
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def resta(a, b, k):
    """A la pieza a le saca la pieza b, con el borde redondeado."""
    h = np.maximum(k - np.abs(a + b), 0.0) / k
    return np.maximum(a, -b) + h * h * k * 0.25


def cono(x, y, z, largo, ra, rb, chato=1.0):
    """Dos bolas de radios ra y rb unidas por un cono, a lo largo de x (de 0 a largo), achatado en z."""
    z = z / chato
    rho = np.sqrt(y * y + z * z)
    b = (ra - rb) / largo
    a = math.sqrt(max(1.0 - b * b, 1e-6))
    k = a * x - b * rho
    return np.where(k < 0.0, np.sqrt(rho * rho + x * x) - ra,
                    np.where(k > a * largo, np.sqrt(rho * rho + (x - largo) ** 2) - rb, a * rho + b * x - ra))


def cono_entre(X, Y, Z, desde, hasta, ra, rb, chato=1.0, dorso=(0.0, 0.0, 1.0)):
    desde = np.array(desde, dtype=np.float64)
    eje = np.array(hasta, dtype=np.float64) - desde
    largo = float(np.linalg.norm(eje))
    eje /= largo
    costado = versor(np.cross(dorso, eje))
    arriba = np.cross(eje, costado)
    qx, qy, qz = X - desde[0], Y - desde[1], Z - desde[2]
    return cono(qx * eje[0] + qy * eje[1] + qz * eje[2], qx * costado[0] + qy * costado[1] + qz * costado[2],
                qx * arriba[0] + qy * arriba[1] + qz * arriba[2], largo, ra, rb, chato)


class Cadena:
    """Un dedo: tres tramos seguidos desde donde nace, cada uno doblado un poco más que el anterior."""

    def __init__(self, nombre, nace, adelante, costado, largos, radios, dobla, chatos, unia):
        self.nombre = nombre
        self.largos = tuple(largos)
        self.radios = tuple(radios)
        self.chatos = tuple(chatos)
        self.unia = unia
        adelante = versor(adelante)
        self.costado = versor(np.array(costado, dtype=np.float64) - adelante * np.dot(costado, adelante))
        dorso0 = np.cross(adelante, self.costado)
        self.tramos = []  # (origen, dirección, dorso, largo)
        p = np.array(nace, dtype=np.float64)
        self.juntas = [p.copy()]
        curva = 0.0
        for i in range(3):
            curva += math.radians(dobla[i])
            direccion = math.cos(curva) * adelante - math.sin(curva) * dorso0
            dorso = math.sin(curva) * adelante + math.cos(curva) * dorso0
            # El último tramo termina un radio antes: la punta es una bola.
            largo = largos[i] - (radios[3] if i == 2 else 0.0)
            self.tramos.append((p.copy(), direccion, dorso, largo))
            p = p + direccion * largo
            self.juntas.append(p.copy())
        self.punta = self.juntas[3] + self.tramos[2][1] * radios[3]

    def local(self, i, X, Y, Z):
        """Dónde cae cada punto visto desde el tramo i: a lo largo, de costado y hacia el dorso."""
        o, d, dor, _largo = self.tramos[i]
        c = self.costado
        qx, qy, qz = X - o[0], Y - o[1], Z - o[2]
        return (qx * d[0] + qy * d[1] + qz * d[2], qx * c[0] + qy * c[1] + qz * c[2], qx * dor[0] + qy * dor[1] + qz * dor[2])

    def distancia(self, X, Y, Z, desde=0):
        total = None
        for i in range(desde, 3):
            x, y, z = self.local(i, X, Y, Z)
            largo = self.tramos[i][3]
            ra, rb, ch = self.radios[i], self.radios[i + 1], self.chatos[i]
            medio = 0.5 * (ra + rb) * CINTURA
            d = np.minimum(cono(x, y, z, largo * 0.5, ra, medio, ch), cono(x - largo * 0.5, y, z, largo * 0.5, medio, rb, ch))
            if i == 2 and self.unia > 0.0:
                # El lecho de la uña: la yema queda apenas rebajada por arriba, con el escalón de la cutícula.
                radio_aqui = rb + (ra - rb) * np.clip(1.0 - x / largo, 0.0, 1.0)
                lecho = np.maximum(radio_aqui * ch * 0.8 - z, (largo + rb - self.unia) - x)
                d = resta(d, lecho, 0.07)
            total = d if total is None else suma(total, d, 0.16)
        return total

    def recorrido(self, X, Y, Z):
        """Cuántos centímetros lleva andados el dedo, desde donde nace, a la altura de cada punto."""
        x1 = self.local(0, X, Y, Z)[0]
        x2 = self.local(1, X, Y, Z)[0]
        x3 = self.local(2, X, Y, Z)[0]
        l1, l2 = self.tramos[0][3], self.tramos[1][3]
        return np.where(x2 < 0.0, np.minimum(x1, l1), np.where(x3 < 0.0, l1 + np.minimum(x2, l2), l1 + l2 + x3))


class Mano:
    """La mano entera, en las medidas de arriba. `rumbo_pulgar` es hacia dónde apunta el pulgar y
    `nudillo_x`, a cuántos centímetros de la muñeca está el primer hueso de los dedos."""

    def __init__(self, rumbo_pulgar, nudillo_x):
        self.nudillo_x = nudillo_x
        self.dedos = []
        for nombre, d in DEDOS.items():
            abre = math.radians(d['abre'])
            self.dedos.append(Cadena(nombre, NUDILLOS[nombre], (math.cos(abre), math.sin(abre), 0.0), (-math.sin(abre), math.cos(abre), 0.0),
                                     d['largos'], d['radios'], d['dobla'], CHATOS, UNIA))
        # El pulgar está girado: la uña mira hacia afuera y hacia arriba, no hacia el dorso.
        rumbo = versor(rumbo_pulgar)
        unia_mira = np.array((-0.2, 0.85, 0.45))
        unia_mira = versor(unia_mira - rumbo * np.dot(unia_mira, rumbo))
        self.pulgar = Cadena('pulgar', PULGAR['nace'], rumbo, np.cross(unia_mira, rumbo), PULGAR['largos'], PULGAR['radios'],
                             PULGAR['dobla'], PULGAR['chatos'], PULGAR['unia'])
        self.cadenas = self.dedos + [self.pulgar]

    def cuerpo(self, X, Y, Z):
        """La palma con la muñeca: todo menos los dedos y el pulgar."""
        p = PALMA
        d = None
        for cadena, y in zip(self.dedos, p['carpo_y']):
            hueso = cono_entre(X, Y, Z, (p['carpo_x'], y, p['carpo_z']), cadena.juntas[0], p['radio_carpo'], p['radio_nudillo'])
            d = hueso if d is None else suma(d, hueso, 1.3)
        d = suma(d, cono_entre(X, Y, Z, p['canto'][0], p['canto'][1], p['canto'][2], p['canto'][3]), 1.2)
        d = suma(d, cono_entre(X, Y, Z, p['almohadilla'][0], p['almohadilla'][1], p['almohadilla'][2], p['almohadilla'][3]), 0.9)
        m = MUNECA
        d = suma(d, cono_entre(X, Y, Z, (m['desde'] - 1.0, 0.0, m['z']), (m['hasta'], 0.0, m['z']), m['ancho'] * 1.02, m['ancho'] * 0.97, m['chato']), 1.0)
        # Los tendones del dorso: un lomo apenas marcado de cada nudillo hacia la muñeca.
        for cadena, y in zip(self.dedos, p['carpo_y']):
            n = cadena.juntas[0]
            d = suma(d, cono_entre(X, Y, Z, (n[0] - 0.9, n[1], n[2] + 0.8), (2.6, y * 0.75, 0.3), 0.36, 0.3), 0.5)
        # El hueso del costado de la muñeca, del lado del meñique, y los cuatro nudillos.
        d = suma(d, np.sqrt((X - 0.2) ** 2 + (Y + 2.45) ** 2 + (Z - 0.75) ** 2) - 0.85, 0.7)
        for i, cadena in enumerate(self.dedos):
            n = cadena.juntas[0]
            radio = p['nudillo_radio'] * (0.86 if i == 3 else 1.0)
            d = suma(d, np.sqrt((X - n[0] + 0.25) ** 2 + (Y - n[1]) ** 2 + (Z - n[2] - p['nudillo_alto']) ** 2) - radio, 0.55)
        return d

    def campo(self, X, Y, Z):
        """A cuánto queda cada punto de la piel (negativo, adentro de la mano)."""
        cuerpo = self.cuerpo(X, Y, Z)
        # Cada dedo se funde con la palma (la membrana entre los dedos), pero no con el dedo de al lado.
        d = suma(cuerpo, self.pulgar.distancia(X, Y, Z), 1.2)
        for cadena in self.dedos:
            d = np.minimum(d, suma(cuerpo, cadena.distancia(X, Y, Z), 0.5))
        # Adentro de la manga termina en un corte derecho.
        return np.maximum(d, MUNECA['desde'] - X)

    def campo_en(self, P):
        return self.campo(P[:, 0], P[:, 1], P[:, 2])

    def normal_en(self, P, e=0.02):
        g = np.empty_like(P)
        for i in range(3):
            corrido = np.zeros(3)
            corrido[i] = e
            g[:, i] = self.campo_en(P + corrido) - self.campo_en(P - corrido)
        return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)

    # ------------------------------------------------------------ la malla
    def malla(self):
        """Saca la malla del campo: mira el campo cada GRANO centímetros y busca dónde vale cero."""
        t0 = time.time()
        desde = np.array((MUNECA['desde'] - 0.6, -5.4, -7.2))
        hasta = np.array((20.6, 11.6, 2.6))
        ejes = [np.arange(desde[i], hasta[i], GRANO, dtype=np.float32) for i in range(3)]
        campo = self.campo(ejes[0][:, None, None], ejes[1][None, :, None], ejes[2][None, None, :]).astype(np.float32)
        rejilla = vdb.FloatGrid(1.0)
        rejilla.copyFromArray(np.ascontiguousarray(campo))
        puntos, triangulos, cuadrados = rejilla.convertToPolygons(isovalue=0.0, adaptivity=0.0)
        puntos = np.asarray(puntos, dtype=np.float64) * GRANO + desde
        caras = [tuple(int(i) for i in c) for c in triangulos] + [tuple(int(i) for i in c) for c in cuadrados]
        informe('campo de %s puntos; malla fina: %d vértices, %d caras (%.0f s)' % ('x'.join(str(len(e)) for e in ejes), len(puntos), len(caras), time.time() - t0))
        # A Blender, para aliviarla. Se trabaja en metros.
        fina = bpy.data.meshes.new('ManoFina')
        fina.from_pydata([tuple(p * CM) for p in puntos], [], caras)
        fina.update()
        objeto = bpy.data.objects.new('ManoDeZenon', fina)
        bpy.context.scene.collection.objects.link(objeto)
        n_tri = len(triangulos) + 2 * len(cuadrados)
        aliviar = objeto.modifiers.new('Aliviar', 'DECIMATE')
        aliviar.ratio = min(1.0, CARAS / max(n_tri, 1))
        liviana = bpy.data.meshes.new_from_object(objeto.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        objeto.modifiers.clear()
        objeto.data = liviana
        bpy.data.meshes.remove(fina)
        liviana.name = 'ManoDeZenon'
        bm = bmesh.new()
        bm.from_mesh(liviana)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        # Los vértices vuelven a apoyarse justo sobre la piel (al aliviar se corren un poco).
        P = np.array([v.co[:] for v in bm.verts]) / CM
        for _ in range(3):
            P = P - self.normal_en(P) * self.campo_en(P)[:, None]
        for v, p in zip(bm.verts, P):
            v.co = Vector(p * CM)
        # Que las caras miren hacia afuera: se compara con hacia dónde crece el campo.
        cara = bm.faces[0]
        afuera = self.normal_en(np.array([cara.calc_center_median()[:]]) / CM)[0]
        if np.dot(afuera, cara.normal[:]) < 0.0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        for c in bm.faces:
            c.smooth = True
        bm.to_mesh(liviana)
        bm.free()
        # El desplegado, para pintarle la piel. Antes se deselecciona todo: en modo edición entran
        # todos los objetos seleccionados, y Blender desplegaba también el cuerpo de Zenón (le
        # arruinaba la textura y dejaba las piezas de la mano en miniatura).
        bpy.ops.object.select_all(action='DESELECT')
        bpy.context.view_layer.objects.active = objeto
        objeto.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.01)
        bpy.ops.object.mode_set(mode='OBJECT')
        objeto.select_set(False)
        informe('malla liviana: %d vértices, %d triángulos' % (len(liviana.vertices), len(liviana.polygons)))
        return objeto

    # ------------------------------------------------------------ a qué hueso sigue cada punto
    def pesos(self, P):
        """Cuánto sigue cada punto a cada hueso: {nombre del hueso: pesos}.
        El esqueleto de Mixamo dobla los cuatro dedos con una sola cadena de huesos (el índice), como
        un mitón: los cuatro giran alrededor de las mismas tres líneas, las de los huesos. Por eso
        cada dedo se reparte según esas líneas y no según sus propios nudillos: si no, al cerrar el
        puño el meñique (que tiene los nudillos más atrás) se desgarra. El pulgar va con sus huesos, y
        la muñeca reparte entre el antebrazo y la mano."""
        X, Y, Z = P[:, 0], P[:, 1], P[:, 2]
        lineas = self.huesos()
        x1, x2 = lineas['HandIndex2'][0], lineas['HandIndex3'][0]
        d_dedos = np.stack([c.distancia(X, Y, Z) for c in self.dedos]).min(axis=0)
        d_pulgar = self.pulgar.distancia(X, Y, Z)
        # Cuánto es del pulgar cada punto (de a poco: la membrana entre el pulgar y el índice es de los dos).
        del_pulgar = paso(d_dedos - d_pulgar, -0.6, 0.6)
        pesos = {n: np.zeros(len(P)) for n in ('ForeArm', 'Hand', 'HandIndex1', 'HandIndex2', 'HandIndex3', 'HandThumb1', 'HandThumb2', 'HandThumb3')}
        dedo = paso(X, self.nudillo_x - 0.5, self.nudillo_x + 0.9) * (1.0 - del_pulgar)
        b12 = paso(X, x1 - 0.55, x1 + 0.55)
        b23 = paso(X, x2 - 0.5, x2 + 0.5)
        pesos['HandIndex1'] = dedo * (1.0 - b12)
        pesos['HandIndex2'] = dedo * b12 * (1.0 - b23)
        pesos['HandIndex3'] = dedo * b12 * b23
        s = self.pulgar.recorrido(X, Y, Z)
        l1, l2 = self.pulgar.tramos[0][3], self.pulgar.tramos[1][3]
        dedo = paso(s, 1.0, 3.2) * del_pulgar
        b12 = paso(s, l1 - 0.6, l1 + 0.6)
        b23 = paso(s, l1 + l2 - 0.5, l1 + l2 + 0.5)
        pesos['HandThumb1'] = dedo * (1.0 - b12)
        pesos['HandThumb2'] = dedo * b12 * (1.0 - b23)
        pesos['HandThumb3'] = dedo * b12 * b23
        pesos['Hand'] = 1.0 - sum(pesos[n] for n in pesos if n not in ('Hand', 'ForeArm'))
        brazo = paso(X, 0.6, -2.6)
        for n in pesos:
            pesos[n] *= (1.0 - brazo)
        pesos['ForeArm'] = brazo
        return pesos

    def huesos(self):
        """Dónde van los huesos de los dedos (cabeza de cada uno): las articulaciones de los dedos
        del medio, llevadas a la línea del centro de la mano, y las del pulgar."""
        medio = [np.mean([c.juntas[i] for c in self.dedos[:3]], axis=0) for i in (1, 2)]
        punta = np.mean([c.punta for c in self.dedos[:3]], axis=0)
        return {'HandIndex2': (medio[0][0], 0.0, medio[0][2]), 'HandIndex3': (medio[1][0], 0.0, medio[1][2]),
                'HandIndex4': (punta[0], 0.0, punta[2]),
                'HandThumb1': tuple(self.pulgar.juntas[0]), 'HandThumb2': tuple(self.pulgar.juntas[1]),
                'HandThumb3': tuple(self.pulgar.juntas[2]), 'HandThumb4': tuple(self.pulgar.punta)}


# ================================================================ la piel: la imagen pintada
def ruido(P, escala, semilla):
    """Manchas suaves entre 0 y 1, siempre las mismas en cada lugar."""
    q = P / escala
    base = np.floor(q).astype(np.int64)
    f = q - base
    f = f * f * (3.0 - 2.0 * f)

    def azar(ix, iy, iz):
        n = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + semilla * 144665) & 0xffffffff
        n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
        return ((n ^ (n >> 16)) & 0xffff) / 65535.0

    total = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                peso = (f[:, 0] if dx else 1.0 - f[:, 0]) * (f[:, 1] if dy else 1.0 - f[:, 1]) * (f[:, 2] if dz else 1.0 - f[:, 2])
                total = total + peso * azar(base[:, 0] + dx, base[:, 1] + dy, base[:, 2] + dz)
    return total


def raya(x, donde, ancho):
    """Una raya fina: 1 en el medio, 0 a los costados."""
    return np.exp(-((x - donde) / ancho) ** 2)


def pintar(mano, P, N, tono):
    """El color de la piel en cada punto P de la mano (N es hacia dónde mira la piel ahí)."""
    X, Y, Z = P[:, 0], P[:, 1], P[:, 2]
    tono = np.array(tono)
    cuerpo = mano.cuerpo(X, Y, Z)
    d_cadenas = np.stack([c.distancia(X, Y, Z) for c in mano.cadenas])
    cual = np.argmin(d_cadenas, axis=0)
    # Hacia dónde queda el dorso en cada punto: en la palma, arriba; en cada dedo, el dorso de su falange.
    dorso = N[:, 2].copy()
    en_dedo = np.zeros(len(P))
    pliegues = np.zeros(len(P))
    rojez = np.zeros(len(P))
    unia = np.zeros(len(P))
    luna = np.zeros(len(P))
    borde_libre = np.zeros(len(P))
    contorno = np.zeros(len(P))
    yema = np.zeros(len(P))
    for i, c in enumerate(mano.cadenas):
        es_pulgar = c is mano.pulgar
        s = c.recorrido(X, Y, Z)
        # Cuánto es de este dedo cada punto. Entra de a poco: con un corte seco quedaba una raya
        # derecha en la base del pulgar, donde la piel pasaba de "palma" a "dedo".
        mio = (cual == i) * paso(d_cadenas[i] - cuerpo, 0.5, 0.1) * (paso(s, 2.0, 4.2) if es_pulgar else paso(s, 0.2, 0.9))
        if not mio.any():
            continue
        x1, y1, z1 = c.local(0, X, Y, Z)
        x2, y2, z2 = c.local(1, X, Y, Z)
        x3, y3, z3 = c.local(2, X, Y, Z)
        l1, l2, l3 = c.tramos[0][3], c.tramos[1][3], c.tramos[2][3]
        tramo = np.where(x2 < 0.0, 0, np.where(x3 < 0.0, 1, 2))
        dorsos = np.stack([N @ c.tramos[k][2] for k in range(3)])
        dorso_aqui = np.choose(tramo, dorsos)
        dorso = dorso * (1.0 - mio) + dorso_aqui * mio
        en_dedo = np.maximum(en_dedo, mio)
        arriba = paso(dorso_aqui, 0.1, 0.5)
        abajo = paso(dorso_aqui, -0.1, -0.5)
        r1, r2, r3 = c.radios[1], c.radios[2], c.radios[3]
        mias = np.zeros(len(P))
        # Las arrugas del dorso sobre cada articulación (arqueadas) y los pliegues de abajo.
        for corrido, fuerza in ((-0.36, 0.7), (-0.15, 1.0), (0.07, 1.0), (0.29, 0.6)):
            mias += fuerza * 0.2 * raya(x2 - 0.1 * (y2 / r1) ** 2, corrido, 0.024) * arriba * paso(np.abs(y2), r1 * 0.95, r1 * 0.6)
        for corrido in (-0.11, 0.11):
            mias += 0.24 * raya(x2 + 0.05 * (y2 / r1) ** 2, corrido, 0.03) * abajo
        for corrido, fuerza in ((-0.2, 0.8), (-0.03, 1.0)):
            mias += fuerza * 0.17 * raya(x3 - 0.08 * (y3 / r2) ** 2, corrido, 0.022) * arriba * paso(np.abs(y3), r2 * 0.95, r2 * 0.6)
        mias += 0.22 * raya(x3 + 0.04 * (y3 / r2) ** 2, -0.02, 0.03) * abajo
        if not es_pulgar:
            mias += 0.2 * raya(x1, 1.85, 0.035) * abajo
        pliegues += mio * mias
        # Los nudillos, más rojizos.
        rojez += mio * arriba * (0.8 * np.exp(-(x2 / 0.6) ** 2) + 0.55 * np.exp(-(x3 / 0.42) ** 2))
        # La uña, sobre el lecho rebajado: el nacimiento curvo (cutícula), la lúnula y el borde libre.
        medio_ancho = r3 * 0.8
        lado = np.clip(np.abs(y3) / medio_ancho, 0.0, 1.6)
        nace = (l3 + r3 - c.unia) + 0.05 + 0.2 * lado ** 2
        termina = (l3 + r3 * 0.78) - 0.2 * lado ** 2
        encima = paso(dorsos[2], 0.2, 0.5)
        dentro = paso(x3, nace - 0.025, nace + 0.025) * paso(x3, termina + 0.025, termina - 0.025) * paso(lado, 1.04, 0.96) * encima
        casi = paso(x3, nace - 0.1, nace - 0.04) * paso(x3, termina + 0.1, termina + 0.04) * paso(lado, 1.2, 1.1) * encima
        unia += mio * dentro
        contorno += mio * np.clip(casi - dentro, 0.0, 1.0)
        luna += mio * dentro * paso(x3, nace + 0.3, nace + 0.1) * paso(lado, 0.85, 0.5)
        borde_libre += mio * dentro * paso(x3, termina - 0.085, termina - 0.05)
        yema += mio * abajo * paso(x3, l3 * 0.15, l3 * 0.6)
    # Los nudillos de la mano, por arriba.
    arriba_mano = paso(N[:, 2], 0.2, 0.6) * (1.0 - en_dedo)
    for c in mano.dedos:
        n = c.juntas[0]
        rojez += 0.75 * arriba_mano * np.exp(-((X - n[0] + 0.25) ** 2 + (Y - n[1]) ** 2) / 0.8 ** 2)
    # Las tres líneas de la palma.
    abajo_mano = paso(N[:, 2], -0.25, -0.65) * (1.0 - en_dedo)
    lineas = raya(X, 7.4 + 0.19 * Y + 0.12 * np.sin(Y * 1.3), 0.06) * paso(Y, -4.4, -3.4) * paso(Y, 2.7, 1.7)
    lineas += raya(X, 5.45 + 0.246 * Y + 0.1 * np.sin(Y * 1.1 + 1.0), 0.06) * paso(Y, -3.1, -2.1) * paso(Y, 4.4, 3.4)
    lineas += raya(np.sqrt((X - 3.2) ** 2 + (Y - 3.9) ** 2), 3.3, 0.065) * paso(Y, 3.6, 2.8) * paso(X, 0.4, 1.4) * paso(X, 7.0, 6.0)
    pliegues += 0.17 * abajo_mano * np.clip(lineas, 0.0, 1.0)
    # Los pliegues de la muñeca, por abajo.
    pliegues += 0.16 * paso(N[:, 2], -0.2, -0.6) * (raya(X, 0.15, 0.04) + 0.7 * raya(X, -0.35, 0.04))

    # La sombra de los huecos (entre los dedos, bajo las almohadillas): cuánto tapa la propia mano.
    sombra = np.zeros(len(P))
    for alto, cuanto in ((0.25, 0.45), (0.7, 0.33), (1.5, 0.22)):
        sombra += cuanto * np.clip((alto - mano.campo_en(P + N * alto)) / alto, 0.0, 1.0)
    # Dónde la piel hace lomo (tendones, nudillos) y dónde hace surco: se mira el campo alrededor.
    t1 = np.cross(N, (0.0, 0.0, 1.0))
    chico = np.linalg.norm(t1, axis=1) < 0.2
    t1[chico] = np.cross(N[chico], (1.0, 0.0, 0.0))
    t1 /= np.linalg.norm(t1, axis=1, keepdims=True)
    t2 = np.cross(N, t1)
    paso_c = 0.22
    curva = sum(mano.campo_en(P + t * paso_c) for t in (t1, -t1, t2, -t2)) / 4.0 * 2.0 / paso_c ** 2
    lomo = np.clip((curva - 0.75) / 1.6, 0.0, 1.0)
    surco = np.clip(-curva / 1.4, 0.0, 1.0)

    palmar = paso(dorso, 0.1, -0.55)
    color_dorso = tono
    color_palma = np.clip(tono * 1.2 + np.array((0.045, 0.012, 0.0)), 0.0, 1.0)
    color = color_dorso[None, :] * (1.0 - palmar[:, None]) + color_palma[None, :] * palmar[:, None]
    # Las manchas de la piel: unas grandes y suaves y un grano fino.
    color *= (1.0 + 0.09 * (ruido(P, 1.7, 3) - 0.5) + 0.05 * (ruido(P, 0.45, 7) - 0.5) + 0.035 * (ruido(P, 0.11, 11) - 0.5))[:, None]
    # Yemas y almohadillas, más rosadas.
    almohadillas = np.clip(yema + 0.6 * abajo_mano * (np.exp(-((X - 3.6) ** 2 + (Y - 3.0) ** 2) / 2.2 ** 2) + np.exp(-((X - 7.7) ** 2) / 0.9 ** 2)), 0.0, 1.0)
    color = color * (1.0 - 0.22 * almohadillas[:, None]) + (color * np.array((1.12, 0.9, 0.9)))[:, :] * (0.22 * almohadillas[:, None])
    rojez = np.clip(rojez, 0.0, 1.0)
    color = color * (1.0 - 0.5 * rojez[:, None]) + color * np.array((1.05, 0.84, 0.8)) * (0.5 * rojez[:, None])
    color *= (1.0 + 0.1 * lomo)[:, None]
    color *= (1.0 - 0.28 * surco)[:, None]
    color *= (1.0 - np.clip(pliegues, 0.0, 0.5))[:, None]
    # La uña.
    unia = np.clip(unia, 0.0, 1.0)
    color_unia = tono * 0.62 + np.array((0.82, 0.7, 0.62)) * 0.38
    color_unia = color_unia[None, :] * (1.0 + 0.1 * np.clip(luna, 0.0, 1.0)[:, None])
    libre = 0.65 * np.clip(borde_libre, 0.0, 1.0)[:, None]
    color_unia = color_unia * (1.0 - libre) + np.array((0.7, 0.65, 0.56))[None, :] * libre
    color *= (1.0 - 0.3 * np.clip(contorno, 0.0, 1.0))[:, None]
    color = color * (1.0 - unia[:, None] * 0.92) + color_unia * (unia[:, None] * 0.92)
    # La sombra propia, que en la piel tira al rojo oscuro.
    sombra = np.clip(sombra, 0.0, 1.0)[:, None]
    color = color * (1.0 - sombra) + color * np.array((0.5, 0.4, 0.37)) * sombra
    return np.clip(color, 0.0, 1.0)


def piel(mano, objeto, tono):
    """Pinta la imagen de la piel para la malla de la mano (ya desplegada) y se la pone de material."""
    t0 = time.time()
    malla = objeto.data
    uv = malla.uv_layers.active.data
    T = len(malla.polygons)
    tri_uv = np.array([[uv[li].uv[:] for li in p.loop_indices] for p in malla.polygons])
    tri_v = np.array([p.vertices[:] for p in malla.polygons])
    V = np.array([v.co[:] for v in malla.vertices]) / CM
    VN = mano.normal_en(V)
    tam = TEXTURA
    posicion = np.zeros((tam, tam, 3))
    normal = np.zeros((tam, tam, 3))
    cubierto = np.zeros((tam, tam), dtype=bool)
    for t in range(T):
        a, b, c = tri_uv[t] * tam
        x0, x1 = int(max(math.floor(min(a[0], b[0], c[0])) - 1, 0)), int(min(math.ceil(max(a[0], b[0], c[0])) + 1, tam))
        y0, y1 = int(max(math.floor(min(a[1], b[1], c[1])) - 1, 0)), int(min(math.ceil(max(a[1], b[1], c[1])) + 1, tam))
        if x1 <= x0 or y1 <= y0:
            continue
        px, py = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(det) < 1e-12:
            continue
        w0 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / det
        w1 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / det
        w2 = 1.0 - w0 - w1
        # Un punto de más alrededor de cada triángulo, para que no queden costuras sin pintar.
        dentro = (w0 >= -0.6 / tam * 30) & (w1 >= -0.6 / tam * 30) & (w2 >= -0.6 / tam * 30)
        estricto = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        dentro &= estricto | ~cubierto[y0:y1, x0:x1]
        if not dentro.any():
            continue
        i0, i1, i2 = tri_v[t]
        w = np.stack([w0[dentro], w1[dentro], w2[dentro]], axis=1)
        posicion[y0:y1, x0:x1][dentro] = w @ V[[i0, i1, i2]]
        normal[y0:y1, x0:x1][dentro] = w @ VN[[i0, i1, i2]]
        cubierto[y0:y1, x0:x1] |= dentro
    P = posicion[cubierto]
    N = normal[cubierto]
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    # Cada punto de la imagen se apoya justo sobre la piel antes de pintarlo.
    P = P - mano.normal_en(P) * mano.campo_en(P)[:, None]
    color = np.zeros((tam, tam, 3))
    color[cubierto] = pintar(mano, P, N, tono)
    # Lo que queda sin pintar toma el color de al lado (si no, al achicar la imagen se cuela el negro).
    lleno = cubierto.copy()
    for _ in range(12):
        suma_c = np.zeros_like(color)
        cuenta = np.zeros((tam, tam))
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            suma_c += np.roll(color * lleno[:, :, None], (dy, dx), axis=(0, 1))
            cuenta += np.roll(lleno, (dy, dx), axis=(0, 1))
        nuevo = ~lleno & (cuenta > 0)
        color[nuevo] = suma_c[nuevo] / cuenta[nuevo][:, None]
        lleno |= nuevo
    color[~lleno] = np.array(tono)
    imagen = bpy.data.images.new('ZenonT_manos', tam, tam, alpha=False)
    imagen.colorspace_settings.name = 'sRGB'
    imagen.pixels.foreach_set(np.concatenate([color, np.ones((tam, tam, 1))], axis=2).astype(np.float32).ravel())
    imagen.filepath_raw = os.path.join(SALIDA, 'ZenonT_manos.png')
    imagen.file_format = 'PNG'
    imagen.save()
    imagen.pack()
    material = bpy.data.materials.new('ZenonT_piel')
    material.use_nodes = True
    nodos = material.node_tree
    principal = next(n for n in nodos.nodes if n.type == 'BSDF_PRINCIPLED')
    principal.inputs['Roughness'].default_value = 0.82
    principal.inputs['Metallic'].default_value = 0.0
    textura = nodos.nodes.new('ShaderNodeTexImage')
    textura.image = imagen
    nodos.links.new(textura.outputs['Color'], principal.inputs['Base Color'])
    objeto.data.materials.clear()
    objeto.data.materials.append(material)
    informe('piel pintada: %d de %d puntos (%.0f s)' % (int(cubierto.sum()), tam * tam, time.time() - t0))
    return material


# ================================================================ las vistas de control
def preparar_fotos():
    esc = bpy.context.scene
    esc.render.engine = 'CYCLES'
    esc.cycles.device = 'CPU'
    esc.cycles.samples = 32
    esc.cycles.use_denoising = True
    esc.render.resolution_x = 720
    esc.render.resolution_y = 540
    esc.view_settings.view_transform = 'Standard'
    if esc.world is None:
        esc.world = bpy.data.worlds.new('Mundo')
    esc.world.use_nodes = True
    fondo = next((n for n in esc.world.node_tree.nodes if n.type == 'BACKGROUND'), None)
    if fondo is not None:
        fondo.inputs[0].default_value = (0.5, 0.56, 0.62, 1)
        fondo.inputs[1].default_value = 0.9
    sol = bpy.data.objects.new('SolPrevia', bpy.data.lights.new('SolPrevia', 'SUN'))
    sol.data.energy = 3.2
    sol.data.angle = math.radians(6.0)
    sol.rotation_euler = (math.radians(48), 0, math.radians(35))
    esc.collection.objects.link(sol)
    camara = bpy.data.objects.new('CamPrevia', bpy.data.cameras.new('CamPrevia'))
    esc.collection.objects.link(camara)
    esc.camera = camara

    def foto(nombre, mira, desde, lente=70):
        camara.data.lens = lente
        camara.location = Vector(mira) + Vector(desde)
        camara.rotation_euler = (Vector(mira) - camara.location).to_track_quat('-Z', 'Y').to_euler()
        esc.render.filepath = os.path.join(SALIDA, 'previa_%s.png' % nombre)
        bpy.ops.render.render(write_still=True)

    return foto, (sol, camara)


# ================================================================ Zenón
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
cuerpo_malla = next(o for o in bpy.data.objects if o.type == 'MESH' and o.find_armature() == arm)
if any(m and m.name == 'ZenonT_piel' for m in cuerpo_malla.data.materials):
    informe('este modelo ya tiene las manos nuevas: no hago nada (hay que partir del de las manos viejas)')
    sys.exit(0)
MA = arm.matrix_world
MM = cuerpo_malla.matrix_world
A_MALLA = MM.inverted()


def hueso(nombre):
    return arm.data.bones['mixamorig:' + nombre]


def medir_piel():
    """El tono de la piel de la cara, como está guardado en la textura de Zenón: de los puntos que
    pintan la cabeza, los de tono piel (ni barba, ni sombrero, ni pañuelo)."""
    material = cuerpo_malla.data.materials[0]
    imagen = next(n.image for n in material.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image)
    ancho, alto = imagen.size
    pix = np.array(imagen.pixels[:], dtype=np.float32).reshape(alto, ancho, 4)
    gi = cuerpo_malla.vertex_groups['mixamorig:Head'].index
    de_cabeza = {v.index for v in cuerpo_malla.data.vertices if any(g.group == gi and g.weight > 0.9 for g in v.groups)}
    uv = cuerpo_malla.data.uv_layers[0].data
    cabeza = MA @ hueso('Head').head_local
    muestras = []
    for poli in cuerpo_malla.data.polygons:
        if not all(v in de_cabeza for v in poli.vertices):
            continue
        centro = MM @ poli.center
        mira = (MM.to_3x3() @ poli.normal).normalized()
        if mira.y > -0.5 or centro.z < cabeza.z + 0.07 or centro.z > cabeza.z + 0.17:
            continue
        for li in poli.loop_indices:
            u, v = uv[li].uv
            muestras.append(pix[min(int(v * alto), alto - 1), min(int(u * ancho), ancho - 1)][:3])
    m = np.array(muestras)
    piel_cara = m[(m[:, 0] > m[:, 1] * 1.12) & (m[:, 1] > m[:, 2] * 1.05) & (m[:, 0] > 0.12) & (m[:, 0] < 0.8) & (m[:, 0] < m[:, 2] * 4.0)]
    informe('piel de la cara en la textura: mediana #%02x%02x%02x (%d muestras)' % (tuple(int(round(c * 255)) for c in np.median(piel_cara, axis=0)) + (len(piel_cara),)))
    return tuple(float(c) for c in np.median(piel_cara, axis=0))


def marco(lado):
    """Los ejes de la mano en el mundo, con el cuerpo en T: la muñeca, hacia los dedos, hacia el
    pulgar (adelante) y hacia el dorso (arriba)."""
    muneca = MA @ hueso(lado + 'Hand').head_local
    nudillo = MA @ hueso(lado + 'HandIndex1').head_local
    a = (nudillo - muneca).normalized()
    arriba = Vector((0, 0, 1))
    arriba = (arriba - a * arriba.dot(a)).normalized()
    pulgar = Vector((0, -1, 0))
    pulgar = (pulgar - a * pulgar.dot(a) - arriba * pulgar.dot(arriba)).normalized()
    return muneca, a, pulgar, arriba


MARCOS = {lado: marco(lado) for lado in ('Left', 'Right')}


def al_mundo(lado, p):
    """De las medidas de la mano (centímetros) a un punto del mundo, para ese lado."""
    muneca, a, pulgar, arriba = MARCOS[lado]
    return muneca + (a * p[0] + pulgar * p[1] + arriba * p[2]) * CM


def a_la_mano(lado, direccion_mundo):
    _muneca, a, pulgar, arriba = MARCOS[lado]
    return np.array((direccion_mundo.dot(a), direccion_mundo.dot(pulgar), direccion_mundo.dot(arriba)))


# Hacia dónde apunta el pulgar: lo dice el hueso (el derecho; el izquierdo es su espejo).
rumbos = {}
for lado in ('Left', 'Right'):
    h = hueso(lado + 'HandThumb1')
    rumbos[lado] = a_la_mano(lado, (MA.to_3x3() @ (h.tail_local - h.head_local)).normalized())
informe('rumbo del pulgar: derecho %s, izquierdo %s (se usa el derecho; difieren %.1f grados)' % (
    np.round(rumbos['Right'], 2), np.round(rumbos['Left'], 2), math.degrees(math.acos(min(1.0, float(np.dot(rumbos['Right'], rumbos['Left'])))))))
largo_palma = (MA @ hueso('RightHandIndex1').head_local - MA @ hueso('RightHand').head_local).length / CM
informe('de la muñeca al nudillo del hueso: %.2f cm' % largo_palma)

tono = TONO if TONO is not None else medir_piel()
if TONO is not None:
    medir_piel()
informe('tono de la piel: #%02x%02x%02x' % tuple(int(round(c * 255)) for c in tono))

MANO = Mano(rumbos['Right'], largo_palma)
mano_objeto = MANO.malla()
material_piel = piel(MANO, mano_objeto, tono)

if SOLO_MANO or PREVIA:
    foto, utiles = preparar_fotos()
    cuerpo_malla.hide_render = True
    centro = (0.085, 0.02, -0.01)
    for nombre, desde in (('mano_dorso', (0.0, 0.0, 0.5)), ('mano_palma', (0.0, 0.0, -0.5)), ('mano_perfil', (0.02, 0.5, 0.06)),
                          ('mano_tres_cuartos', (0.28, 0.3, 0.26)), ('mano_punta', (0.42, 0.1, 0.12)), ('mano_canto', (0.02, -0.5, 0.08)),
                          ('mano_unias', (0.2, 0.06, 0.2))):
        foto(nombre, centro if nombre != 'mano_unias' else (0.16, 0.01, -0.01), desde, 70 if nombre != 'mano_unias' else 110)
    cuerpo_malla.hide_render = False
    if SOLO_MANO:
        informe('LISTO (solo la mano)')
        sys.exit(0)

# ---------------------------------------------------------------- los huesos de los dedos
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
A_ARM = MA.inverted()
for lado in ('Left', 'Right'):
    for nombre, p in MANO.huesos().items():
        h = arm.data.edit_bones['mixamorig:' + lado + nombre]
        h.use_connect = False
        m = h.matrix.copy()
        m.translation = A_ARM @ al_mundo(lado, p)
        h.matrix = m
    # Cada hueso llega hasta donde nace el siguiente (el largo no cambia cómo se mueve; es para verlo bien).
    for cadena in (('HandIndex1', 'HandIndex2', 'HandIndex3', 'HandIndex4'), ('HandThumb1', 'HandThumb2', 'HandThumb3', 'HandThumb4')):
        for este, sigue in zip(cadena, cadena[1:]):
            h = arm.data.edit_bones['mixamorig:' + lado + este]
            h.length = max((arm.data.edit_bones['mixamorig:' + lado + sigue].head - h.head).length, 0.5)
        arm.data.edit_bones['mixamorig:' + lado + cadena[-1]].length = 1.0
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------- cortar la mano vieja y poner la nueva
bpy.context.view_layer.objects.active = cuerpo_malla
cuerpo_malla.data.materials.append(material_piel)
I_PIEL = len(cuerpo_malla.data.materials) - 1
GRUPO = {g.name: g.index for g in cuerpo_malla.vertex_groups}
datos = mano_objeto.data
V_MANO = np.array([v.co[:] for v in datos.vertices]) / CM
PESOS = MANO.pesos(V_MANO)
uv_mano = datos.uv_layers.active.data
TRIS = [(tuple(p.vertices), [tuple(uv_mano[li].uv) for li in p.loop_indices]) for p in datos.polygons]

bm = bmesh.new()
bm.from_mesh(cuerpo_malla.data)
capa = bm.verts.layers.deform.verify()
capa_uv = bm.loops.layers.uv.verify()
N_ANTES = len(bm.verts)
for lado in ('Left', 'Right'):
    muneca, a, pulgar, arriba = MARCOS[lado]
    H = 'mixamorig:' + lado
    # Todo lo que queda más allá del plano, hacia los dedos, se va.
    corte = muneca - a * CORTE * CM
    co_local = A_MALLA @ corte
    no_local = (A_MALLA.to_3x3() @ a).normalized()
    de_la_mano = [GRUPO[n] for n in GRUPO if n.startswith(H + 'Hand') or n == H + 'ForeArm']
    del_brazo = [v for v in bm.verts if (v.co - co_local).dot(no_local) > -0.25 / MM.to_scale().x and any(g in v[capa] for g in de_la_mano)]
    geom = set(del_brazo)
    for v in del_brazo:
        geom.update(v.link_edges)
        geom.update(v.link_faces)
    antes = len(bm.verts)
    res = bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-6, plane_co=co_local, plane_no=no_local, clear_outer=True, clear_inner=False)
    borde = [e for e in res['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
    # El hueco del puño de la camisa se tapa con un solo color de la manga (queda detrás de la muñeca).
    uv_borde = next((bucle[capa_uv].uv.copy() for e in borde for bucle in e.link_loops), None)
    for c in bmesh.ops.holes_fill(bm, edges=borde, sides=0)['faces']:
        c.smooth = True
        if uv_borde is not None:
            for bucle in c.loops:
                bucle[capa_uv].uv = uv_borde
    # La mano nueva. La izquierda es el espejo de la derecha: sus caras se dan vuelta.
    nuevos = [bm.verts.new(A_MALLA @ al_mundo(lado, p)) for p in V_MANO]
    for i, v in enumerate(nuevos):
        for nombre, pesos in PESOS.items():
            if pesos[i] > 0.002:
                v[capa][GRUPO[H + nombre]] = float(pesos[i])
    espejo = a.cross(pulgar).dot(arriba) < 0.0
    for indices, uvs in TRIS:
        orden = (0, 2, 1) if espejo else (0, 1, 2)
        try:
            cara = bm.faces.new([nuevos[indices[k]] for k in orden])
        except ValueError:
            continue
        cara.smooth = True
        cara.material_index = I_PIEL
        for bucle, k in zip(cara.loops, orden):
            bucle[capa_uv].uv = uvs[k]
    informe(lado, 'mano vieja afuera (%d vértices menos), mano nueva adentro (%d vértices, %d triángulos)%s' % (
        antes - len(bm.verts) + len(nuevos), len(nuevos), len(TRIS), ', en espejo' if espejo else ''))
bm.to_mesh(cuerpo_malla.data)
bm.free()
cuerpo_malla.data.update()
bpy.data.objects.remove(mano_objeto)
informe('malla de Zenón: %d vértices (antes %d), %d caras' % (len(cuerpo_malla.data.vertices), N_ANTES, len(cuerpo_malla.data.polygons)))

# ---------------------------------------------------------------- vistas de Zenón con las manos puestas
if PREVIA:
    arm.data.pose_position = 'REST'
    centro = al_mundo('Right', (9.0, 0.5, 0.0))
    foto('T_arriba', centro, (0.0, -0.04, 0.55))
    foto('T_abajo', centro, (0.0, -0.04, -0.55))
    foto('T_frente', centro, (0.0, -0.55, 0.1))
    foto('T_punta', centro, (-0.5, -0.2, 0.2))
    foto('T_cuerpo', (0, 0, 1.0), (0.0, -4.2, 0.4), 50)
    arm.data.pose_position = 'POSE'
    for clip, cuadro in (('idle', 40), ('run', 8), ('walk', 12)):
        for pista in arm.animation_data.nla_tracks:
            pista.mute = pista.name != clip
        bpy.context.scene.frame_set(cuadro)
        bpy.context.view_layer.update()
        mano_d = MA @ arm.pose.bones['mixamorig:RightHand'].head
        mano_i = MA @ arm.pose.bones['mixamorig:LeftHand'].head
        foto('%s_mano_der' % clip, mano_d + Vector((0, 0, -0.07)), (-0.35, -0.45, 0.1))
        foto('%s_mano_izq' % clip, mano_i + Vector((0, 0, -0.07)), (0.35, -0.45, 0.1))
        foto('%s_mano_der_afuera' % clip, mano_d + Vector((0, 0, -0.07)), (-0.6, -0.08, 0.06))
        foto('%s_cuerpo' % clip, (0, 0, 1.0), (0.0, -4.2, 0.4), 50)
    for pista in arm.animation_data.nla_tracks:
        pista.mute = False
    for o in utiles:
        bpy.data.objects.remove(o)

# ---------------------------------------------------------------- guardar y exportar
arm.data.pose_position = 'POSE'
bpy.context.preferences.filepaths.save_version = 0
blend = os.path.join(SALIDA, 'gaucho_zenon_animado.blend')
glb = os.path.join(SALIDA, 'gaucho_zenon_animado.glb')
for ruta in (blend, glb):
    if os.path.exists(ruta):
        os.remove(ruta)
bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True, copy=True)
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
cuerpo_malla.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_skins=True, export_apply=False)
informe('ESCRITO', blend, round(os.path.getsize(blend) / 1e6, 2), 'MB |', glb, round(os.path.getsize(glb) / 1e6, 2), 'MB')

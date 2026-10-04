# Copas con hojas (tanda 4): convierte las "bolas" de follaje de un arbol o arbusto en una copa
# hecha de manojos de hojas sueltos alrededor de un nucleo oscuro. El tronco y el choque no se tocan.
#
#   blender -b --factory-startup -P tools/modelado/hojas.py -- lenga_a nire_b ...   (sin nombres: todos)
#   opciones: --sin-previa   --salida <carpeta> (para probar sin pisar assets/flora)
#
# La copa original queda guardada dentro del .blend (objeto "...CopaOriginal", que no se exporta), asi que
# se puede volver a correr las veces que haga falta: siempre parte de la copa original.
# Las hojas llevan el material "Hoja" (assets/materiales/hoja.tres: se ven de los dos lados y se mueven
# con el viento); el nucleo y el tronco siguen con "Mate".
import bpy, bmesh, sys, os, math, random, colorsys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from mathutils import Vector

# nombre: opciones.  colgante: hojas largas que cuelgan (sauce).  tam: tamano de los manojos respecto de la bola.
ARBOLES = {
    'lenga_a': {}, 'lenga_b': {}, 'lenga_c': {}, 'lenga_d': {},
    'nire_a': {}, 'nire_b': {}, 'nire_c': {}, 'nire_d': {},
    'manzano_a': {}, 'manzano_b': {},
    'sauce_a': {'colgante': True}, 'sauce_b': {'colgante': True},
    'calafate_a': {'tam': 0.8, 'oscurecer': 0.8}, 'calafate_b': {'tam': 0.8, 'oscurecer': 0.8},
    'matorral_a': {}, 'matorral_b': {},
    'jarilla': {'tam': 0.9}, 'matorral_barda_b': {},
}
CUBRE = 0.9           # cuanto de la bola tapan las hojas (1 = toda)
NUCLEO = 0.72         # el nucleo es la bola achicada a este tamano
SOMBRA_NUCLEO = 0.58  # y oscurecida
SATURACION = 0.84     # los colores del follaje, un poco mas apagados
BRILLO = 0.93
FRUTA = 0.14          # las bolitas mas chicas que esto (manzanas, bayas) se dejan como estan


def a_srgb(c):
    return tuple(1.055 * max(x, 0.0) ** (1 / 2.4) - 0.055 if x > 0.0031308 else 12.92 * x for x in c)


def a_lineal(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def ajustar(color, rng, brillo=1.0, sat=SATURACION):
    """Color lineal -> un poco mas apagado y con algo de azar."""
    h, s, v = colorsys.rgb_to_hsv(*a_srgb(color[:3]))
    h = (h + rng.uniform(-0.012, 0.012)) % 1.0
    s = min(1.0, s * sat)
    v = min(1.0, v * BRILLO * brillo)
    return a_lineal(colorsys.hsv_to_rgb(h, s, v)) + (1.0,)


def islas(bm):
    """Grupos de caras unidas entre si."""
    vistas = set()
    for cara in bm.faces:
        if cara in vistas:
            continue
        isla, cola = [], [cara]
        vistas.add(cara)
        while cola:
            f = cola.pop()
            isla.append(f)
            for v in f.verts:
                for g in v.link_faces:
                    if g not in vistas:
                        vistas.add(g)
                        cola.append(g)
        yield isla


def es_bola_de_follaje(isla, capa):
    """En los arboles de una sola pieza: una bola de triangulos (icoesfera) de color vivo es follaje."""
    verts = {v for f in isla for v in f.verts}
    if any(len(f.verts) != 3 for f in isla) or (len(verts), len(isla)) not in ((12, 20), (42, 80), (162, 320), (642, 1280)):
        return False
    sat = 0.0
    for f in isla:
        h, s, v = colorsys.rgb_to_hsv(*a_srgb(f.loops[0][capa][:3]))
        sat += s
    return sat / len(isla) > 0.25


def separar_copa(obj):
    """Saca las bolas de follaje de un arbol de una sola pieza a un objeto aparte. Devuelve la copa o None."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    capa = bm.loops.layers.float_color.get('Col') or bm.loops.layers.color.get('Col')
    follaje = [f for isla in islas(bm) if es_bola_de_follaje(isla, capa) for f in isla]
    if not follaje:
        bm.free()
        return None
    tenia_normales = obj.data.has_custom_normals
    copa_bm = bm.copy()
    copa_bm.faces.ensure_lookup_table()
    indices = {f.index for f in follaje}
    bmesh.ops.delete(copa_bm, geom=[f for f in copa_bm.faces if f.index not in indices], context='FACES')
    bmesh.ops.delete(bm, geom=follaje, context='FACES')
    malla = bpy.data.meshes.new(obj.name + 'Copa')
    copa_bm.to_mesh(malla)
    copa_bm.free()
    for m in obj.data.materials:
        malla.materials.append(m)
    bm.to_mesh(obj.data)
    bm.free()
    if tenia_normales:              # el tronco vuelve a normales comunes
        obj.data.set_sharp_from_angle(angle=math.radians(38.0))
    copa = bpy.data.objects.new(obj.name + 'Copa', malla)
    copa.matrix_world = obj.matrix_world.copy()
    bpy.context.scene.collection.objects.link(copa)
    return copa


def hojear(original, opciones, rng):
    """Arma el nucleo y las hojas a partir de la copa original. Devuelve (nucleo, hojas)."""
    colgante = opciones.get('colgante', False)
    tam = opciones.get('tam', 1.0)
    oscurecer = opciones.get('oscurecer', 1.0)
    nombre = original.name.replace('CopaOriginal', '')
    bm = bmesh.new()
    bm.from_mesh(original.data)
    capa = bm.loops.layers.float_color.get('Col') or bm.loops.layers.color.get('Col')
    zs = [v.co.z for v in bm.verts]
    z0, z1 = min(zs), max(zs)
    centro_copa = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
    centro_copa.z -= (z1 - z0) * 0.25

    hojas = bmesh.new()
    capa_h = hojas.loops.layers.float_color.new('Col')
    normales_h = []
    for isla in list(islas(bm)):
        verts = list({v for f in isla for v in f.verts})
        c = sum((v.co for v in verts), Vector()) / len(verts)
        radio = sum((v.co - c).length for v in verts) / len(verts)
        if radio < FRUTA:
            continue                                    # fruta: queda como esta
        # manojos de hojas repartidos por la superficie de la bola
        areas = [f.calc_area() for f in isla]
        lado = min(0.5, max(0.18, radio * 0.46 * tam))
        cantidad = max(8, int(sum(areas) * CUBRE / (0.36 * lado * lado * (1.6 if colgante else 1.0))))
        for f in rng.choices(isla, weights=areas, k=cantidad):
            a, b = rng.random(), rng.random()
            if a + b > 1.0:
                a, b = 1.0 - a, 1.0 - b
            p = f.verts[0].co + (f.verts[1].co - f.verts[0].co) * a + (f.verts[2].co - f.verts[0].co) * b
            afuera = (p - c).normalized()
            p = c + afuera * (p - c).length * rng.uniform(0.86, 1.1)
            suelto = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
            n = (afuera * 0.6 + suelto * 0.4).normalized()
            s = lado * rng.uniform(0.75, 1.25)
            if colgante:
                t = (Vector((0, 0, -1)) * 0.85 + suelto * 0.25).normalized()
                largo, ancho = s * 1.7, s * 0.24
            else:
                t = n.cross(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))).normalized()
                largo, ancho = s, s * 0.36
            lat = n.cross(t).normalized()
            n = t.cross(lat).normalized()
            base = hojas.verts.new(p - t * largo * 0.45 - n * s * 0.06)
            punta = hojas.verts.new(p + t * largo * 0.55 - n * s * 0.1)
            izq = hojas.verts.new(p + lat * ancho + n * s * 0.06)
            der = hojas.verts.new(p - lat * ancho + n * s * 0.06)
            alto = (p.z - z0) / max(z1 - z0, 1e-3)
            color = ajustar(f.loops[0][capa], rng, brillo=oscurecer * rng.uniform(0.86, 1.1) * (0.88 + 0.22 * alto))
            sombra = tuple(x * 0.78 for x in color[:3]) + (1.0,)
            desde = (p - centro_copa).normalized()
            for trio in ((base, der, punta), (base, punta, izq)):
                cara = hojas.faces.new(trio)
                for l in cara.loops:
                    l[capa_h] = sombra if l.vert is base else color
                    normales_h.append(tuple((desde * 0.7 + n * 0.3).normalized()))
        # el nucleo: la misma bola, mas chica y mas oscura
        for v in verts:
            v.co = c + (v.co - c) * NUCLEO
        for f in isla:
            for l in f.loops:
                l[capa] = tuple(x * SOMBRA_NUCLEO * oscurecer for x in ajustar(l[capa], rng)[:3]) + (1.0,)

    # normales del nucleo: desde el centro de la copa, como antes
    bm.normal_update()
    normales_n = []
    for f in bm.faces:
        for l in f.loops:
            d = l.vert.co - centro_copa
            d = d.normalized() if d.length > 1e-6 else Vector((0, 0, 1))
            normales_n.append(tuple((d * 0.75 + l.vert.normal * 0.25).normalized()))
    malla_n = bpy.data.meshes.new(nombre + 'Copa')
    bm.to_mesh(malla_n)
    bm.free()
    malla_n.materials.append(zmod.material('Mate'))
    malla_n.normals_split_custom_set(normales_n)
    nucleo = bpy.data.objects.new(nombre + 'Copa', malla_n)
    nucleo.matrix_world = original.matrix_world.copy()
    bpy.context.scene.collection.objects.link(nucleo)
    # el nucleo casi no se ve: con un tercio de las caras alcanza
    dec = nucleo.modifiers.new('Aligerar', 'DECIMATE')
    dec.ratio = 0.35

    malla_h = bpy.data.meshes.new(nombre + 'Hojas')
    hojas.to_mesh(malla_h)
    hojas.free()
    malla_h.materials.append(zmod.material('Hoja'))
    malla_h.normals_split_custom_set(normales_h)
    obj_h = bpy.data.objects.new(nombre + 'Hojas', malla_h)
    obj_h.matrix_world = original.matrix_world.copy()
    bpy.context.scene.collection.objects.link(obj_h)
    return nucleo, obj_h


def convertir(nombre, opciones, salida, con_previa):
    origen = '%s/flora/%s.blend' % (zmod.ASSETS, nombre)
    bpy.ops.wm.open_mainfile(filepath=origen)
    bpy.context.preferences.filepaths.save_version = 0
    escena = bpy.context.scene
    # si ya se habia convertido: se tiran las hojas y el nucleo, y se parte otra vez de la copa original
    for o in list(escena.objects):
        if o.type == 'MESH' and (o.name.endswith('Hojas') or (o.name.endswith('Copa') and escena.objects.get(o.name + 'Original'))):
            bpy.data.objects.remove(o)
    originales = [o for o in escena.objects if o.type == 'MESH' and o.name.endswith('CopaOriginal')]
    if not originales:
        copas = [o for o in escena.objects if o.type == 'MESH' and o.name.endswith('Copa')]
        if not copas:
            for o in [o for o in escena.objects if o.type == 'MESH' and 'colonly' not in o.name]:
                copa = separar_copa(o)
                if copa:
                    copas.append(copa)
        for o in copas:
            o.name = o.name + 'Original'
            o.data.name = o.name
        originales = copas
    assert originales, 'no encontre follaje en ' + nombre
    rng = random.Random(nombre)
    for o in originales:
        o.hide_render = False
        nucleo, hojas = hojear(o, opciones, rng)
        o.hide_render = True
        o.hide_set(True)
        tris = lambda ob: sum(len(p.vertices) - 2 for p in ob.data.polygons)
        print('COPA %-18s original %5d triangulos -> nucleo %5d (antes de aligerar) + hojas %5d' % (
            nombre, tris(o), tris(nucleo), tris(hojas)))

    ruta = '%s/flora/%s' % (salida, nombre)
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=ruta + '.blend')
    bpy.ops.object.select_all(action='DESELECT')
    exportar = [o for o in escena.objects if o.type == 'MESH' and not o.name.endswith('CopaOriginal')]
    for o in exportar:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=ruta + '.glb', export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True, export_vertex_color='MATERIAL',
                              export_animations=False, export_cameras=False, export_lights=False)
    print('GUARDADO %s.glb  %d KB' % (nombre, os.path.getsize(ruta + '.glb') // 1024))
    zmod._escribir_import(ruta + '.glb.import', sorted({m.name for o in exportar for m in o.data.materials if m}))
    if con_previa:
        os.makedirs(zmod.PREVIAS, exist_ok=True)
        zmod.previa('%s/%s' % (zmod.PREVIAS, nombre), vistas=((-62, 12), (118, 30)))


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    salida = zmod.ASSETS
    if '--salida' in argv:
        i = argv.index('--salida')
        salida = argv[i + 1].replace(os.sep, '/')
        del argv[i:i + 2]
    nombres = [a for a in argv if not a.startswith('--')] or list(ARBOLES)
    for nombre in nombres:
        convertir(nombre, ARBOLES.get(nombre, {}), salida, '--sin-previa' not in argv)

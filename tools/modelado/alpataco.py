# Tanda 7: el alpataco del Jarillal del Naciente.
# No es un modelo nuevo: es el matorral de la ribera (assets/flora/matorral_b) con otro color y más
# bajo. El alpataco es una mata espinosa de la estepa, de ramas finas y hoja chica, gris verdosa; el
# matorral de la ribera es ocre de otoño. Acá se abre matorral_b.blend, se le cambian los colores
# pintados en la malla y se guarda como assets/flora/alpataco (.blend, .glb y .glb.import con los
# materiales compartidos). El original no se toca.
#
#   "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" -b --factory-startup -P tools/modelado/alpataco.py
#
# Los números de arriba (COLOR_HOJA, COLOR_RAMA, CUANTO, ALTO) se pueden cambiar y volver a correr.
import bpy, sys, os, colorsys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from zmod import lin

ORIGEN = 'matorral_b'
COLOR_HOJA = lin('#5c6042')     # gris verdoso apagado
COLOR_RAMA = lin('#5a4a3a')     # la leña del alpataco, oscura
CUANTO = 0.85                   # cuánto se lleva cada color hacia el nuevo (0: queda el del matorral)
SOMBRA = 0.62                   # el sol del juego aclara mucho: se oscurece todo a este tanto
ALTO = 0.72                     # más bajo y más abierto que el matorral
ANCHO = 0.95


def recolorear(obj):
    malla = obj.data
    if not malla.color_attributes:
        return
    capa = malla.color_attributes.active_color or malla.color_attributes[0]
    hojas = [i for i, m in enumerate(malla.materials) if m and m.name == 'Hoja']
    # a qué material pertenece cada esquina o cada vértice de la capa de color
    if capa.domain == 'CORNER':
        dueño = [None] * len(malla.loops)
        for cara in malla.polygons:
            for li in cara.loop_indices:
                dueño[li] = cara.material_index
    else:
        dueño = [None] * len(malla.vertices)
        for cara in malla.polygons:
            for v in cara.vertices:
                dueño[v] = cara.material_index
    for i, dato in enumerate(capa.data):
        r, g, b, a = dato.color
        meta = COLOR_HOJA if dueño[i] in hojas else COLOR_RAMA
        # se conserva el claroscuro de cada cara (su valor), y se cambia el tono
        valor = max(r, g, b)
        ref = max(meta) or 1.0
        nuevo = [c / ref * valor * SOMBRA for c in meta]
        dato.color = (r + (nuevo[0] - r) * CUANTO, g + (nuevo[1] - g) * CUANTO, b + (nuevo[2] - b) * CUANTO, a)


def armar():
    bpy.ops.wm.open_mainfile(filepath='%s/flora/%s.blend' % (zmod.ASSETS, ORIGEN))
    bpy.context.preferences.filepaths.save_version = 0
    for obj in list(bpy.data.objects):
        if obj.type != 'MESH':
            continue
        print('OBJETO %-28s materiales %s  colores %s' % (obj.name, [m.name for m in obj.data.materials if m],
              [(c.name, c.domain, c.data_type) for c in obj.data.color_attributes]))
        if obj.name.endswith('CopaOriginal'):
            continue
        obj.data = obj.data.copy()
        recolorear(obj)
        if not obj.name.endswith('-convcolonly'):
            obj.scale = (obj.scale[0] * ANCHO, obj.scale[1] * ANCHO, obj.scale[2] * ALTO)
    ruta = '%s/flora/alpataco' % zmod.ASSETS
    for ext in ('.blend', '.glb'):
        if os.path.exists(ruta + ext):
            os.remove(ruta + ext)
    bpy.ops.wm.save_as_mainfile(filepath=ruta + '.blend')
    bpy.ops.object.select_all(action='DESELECT')
    exportar = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.name.endswith('CopaOriginal')]
    for o in exportar:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=ruta + '.glb', export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True, export_vertex_color='MATERIAL',
                              export_animations=False, export_cameras=False, export_lights=False)
    print('GUARDADO alpataco.glb  %d KB' % (os.path.getsize(ruta + '.glb') // 1024))
    zmod._escribir_import(ruta + '.glb.import', sorted({m.name for o in exportar for m in o.data.materials if m}))
    if '--sin-previa' not in sys.argv:
        os.makedirs(zmod.PREVIAS, exist_ok=True)
        zmod.previa('%s/alpataco' % zmod.PREVIAS, vistas=((-62, 12), (118, 30)))


if __name__ == '__main__':
    armar()

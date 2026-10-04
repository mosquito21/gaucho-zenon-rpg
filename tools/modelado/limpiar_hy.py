# Limpia un modelo crudo de Hunyuan y lo deja como los demas del proyecto:
# altura real, pies en el origen, mirando a -Y (en Godot, +Z), sombreado suave, material mate con su textura.
# Escribe assets/<cat>/<nombre>.blend y .glb y, para la gente, assets/personajes/mixamo/<nombre>_mixamo.fbx.
import bpy, bmesh, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zmod
from mathutils import Vector, Matrix

ASSETS = zmod.ASSETS
CRUDOS = zmod.BORRADOR + '/hunyuan'          # donde hunyuan_tanda.py deja los <nombre>_hy.glb

MODELOS = {
    # alto: altura total en metros (con sombrero). giro: grados sobre el eje vertical para que mire a -Y.
    'villegas': dict(cat='personajes/npc', alto=1.76, giro=0.0, gente=True),
    'gaucho_1': dict(cat='personajes/npc', alto=1.74, giro=0.0, gente=True),
    'gaucho_2': dict(cat='personajes/npc', alto=1.76, giro=0.0, gente=True),
    'gaucho_3': dict(cat='personajes/npc', alto=1.72, giro=0.0, gente=True),
    'perro': dict(cat='animales', alto=0.82, giro=0.0, gente=False),
    # Huemul macho: el alto es con las astas (la cruz queda a 0,90 m). caras: Hunyuan entrega 40 mil
    # triangulos y los animales van de 8 a 15 mil puntos, asi que se simplifica a esa cantidad de caras.
    'huemul': dict(cat='animales', alto=1.39, giro=0.0, gente=False, caras=26000),
}

args = sys.argv[sys.argv.index('--') + 1:]
for nombre in [a for a in args if not a.startswith('--')]:
    cfg = dict(MODELOS[nombre])
    for a in args:
        if a.startswith('--giro='):
            cfg['giro'] = float(a.split('=')[1])
    zmod.nueva_escena()
    bpy.ops.import_scene.gltf(filepath=os.path.join(CRUDOS, nombre + '_hy.glb'))
    obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    for o in [o for o in bpy.data.objects if o is not obj]:
        bpy.data.objects.remove(o)
    obj.parent = None
    obj.name = nombre
    obj.data.name = nombre
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    antes = len(obj.data.vertices)
    # soldar puntos repetidos y alisar
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    if cfg['giro']:
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(cfg['giro']), 3, 'Z'))
    zs = [v.co.z for v in bm.verts]
    escala = cfg['alto'] / (max(zs) - min(zs))
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    centro = Vector(((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, min(zs)))
    for v in bm.verts:
        v.co = (v.co - centro) * escala
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(obj.data)
    bm.free()
    if cfg.get('caras') and len(obj.data.polygons) > cfg['caras']:
        mod = obj.modifiers.new('Simplificar', 'DECIMATE')       # junta aristas cuidando la forma y la textura
        mod.ratio = cfg['caras'] / len(obj.data.polygons)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if obj.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    # material mate con la textura de color sola
    mat = obj.data.materials[0]
    mat.name = nombre
    nodos = mat.node_tree.nodes
    bsdf = next(n for n in nodos if n.type == 'BSDF_PRINCIPLED')
    color = bsdf.inputs['Base Color'].links[0].from_node
    for n in [n for n in nodos if n not in (bsdf, color) and n.type != 'OUTPUT_MATERIAL']:
        nodos.remove(n)
    bsdf.inputs['Roughness'].default_value = 1.0
    bsdf.inputs['Metallic'].default_value = 0.0
    bsdf.inputs['Specular IOR Level'].default_value = 0.3
    imagen = color.image
    imagen.name = nombre + '_color'
    for im in [im for im in bpy.data.images if im is not imagen and im.users == 0]:
        bpy.data.images.remove(im)
    # la textura sale a un JPG al lado (asi el FBX de Mixamo la lleva adentro) y queda empaquetada en el .blend
    tex_dir = os.path.join(CRUDOS, 'tex')
    os.makedirs(tex_dir, exist_ok=True)
    ruta_tex = os.path.join(tex_dir, nombre + '_color.jpg')
    escena = bpy.context.scene
    if imagen.packed_file and imagen.file_format == 'JPEG':
        with open(ruta_tex, 'wb') as f:                      # los mismos bytes que entrego Hunyuan, sin recomprimir
            f.write(imagen.packed_file.data)
    else:
        escena.view_settings.view_transform = 'Standard'     # sin esto, save_render le cambia los colores
        escena.render.image_settings.file_format = 'JPEG'
        escena.render.image_settings.quality = 92
        imagen.save_render(ruta_tex, scene=escena)
    nueva = bpy.data.images.load(ruta_tex)
    color.image = nueva
    bpy.data.images.remove(imagen)
    nueva.name = nombre + '_color'
    nueva.pack()
    cs = [obj.matrix_world @ v.co for v in obj.data.vertices]
    print('LIMPIO %-9s vertices %d -> %d  caras %d  alto %.3f  ancho %.3f  fondo %.3f  textura %s' % (
        nombre, antes, len(obj.data.vertices), len(obj.data.polygons), max(c.z for c in cs),
        max(c.x for c in cs) - min(c.x for c in cs), max(c.y for c in cs) - min(c.y for c in cs), tuple(nueva.size)))
    base = '%s/%s/%s' % (ASSETS, cfg['cat'], nombre)
    for ext in ('.blend', '.glb'):
        if os.path.exists(base + ext):
            os.remove(base + ext)
    bpy.ops.wm.save_as_mainfile(filepath=base + '.blend')
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=base + '.glb', export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_animations=False, export_image_format='JPEG', export_jpeg_quality=90)
    print('GUARDADO', os.path.basename(base) + '.glb', os.path.getsize(base + '.glb') // 1024, 'KB')
    if cfg['gente']:
        fbx = '%s/personajes/mixamo/%s_mixamo.fbx' % (ASSETS, nombre)
        bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, path_mode='COPY', embed_textures=True,
                                 bake_anim=False, add_leaf_bones=False, mesh_smooth_type='FACE')
        print('GUARDADO', os.path.basename(fbx), os.path.getsize(fbx) // 1024, 'KB')
    if '--sin-previa' not in args:
        zmod.previa(os.path.join(zmod.PREVIAS, 'limpio_' + nombre), vistas=((-75, 8), (105, 8)), res=(420, 500), muestras=16)

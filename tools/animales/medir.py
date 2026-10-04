# Saca tres vistas planas de un animal (costado, frente y arriba) para leer las medidas de su receta.
# Uso, desde la raiz del proyecto (despues se les dibuja la grilla con grilla.py):
#   "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" -b --factory-startup -P tools/animales/medir.py -- guanaco
#   py tools/animales/grilla.py guanaco
# Deja .revision/animales/medida_<nombre>_<vista>.png y, con la grilla, medida_<nombre>_<vista>_g.jpg
import bpy, sys, json, os
from mathutils import Vector
SAL = os.path.abspath('.revision/animales').replace(os.sep, '/')
for nombre in sys.argv[sys.argv.index('--') + 1:]:
    bpy.ops.wm.open_mainfile(filepath='assets/animales/%s.blend' % nombre)
    esc = bpy.context.scene
    o = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    cs = [v.co for v in o.data.vertices]
    mn = Vector((min(c.x for c in cs), min(c.y for c in cs), min(c.z for c in cs)))
    mx = Vector((max(c.x for c in cs), max(c.y for c in cs), max(c.z for c in cs)))
    cen = (mn + mx) / 2
    cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam'))
    esc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    esc.camera = cam
    esc.render.engine = 'BLENDER_WORKBENCH'
    esc.display.shading.light = 'STUDIO'
    esc.display.shading.color_type = 'TEXTURE'
    mundo = bpy.data.worlds.new('F'); mundo.color = (0.75, 0.75, 0.75); esc.world = mundo
    esc.view_settings.view_transform = 'Standard'
    esc.render.image_settings.file_format = 'PNG'
    info = {}
    # vista: (direccion desde donde mira, eje horizontal de la imagen, eje vertical)
    for vista, desde, ancho_m, alto_m in (('costado', Vector((1, 0, 0)), mx.y - mn.y, mx.z - mn.z),
                                          ('frente', Vector((0, -1, 0)), mx.x - mn.x, mx.z - mn.z),
                                          ('arriba', Vector((0, 0, 1)), mx.x - mn.x, mx.y - mn.y)):
        margen = 0.12
        ancho_m += margen * 2; alto_m += margen * 2
        ppm = min(1500 / ancho_m, 1000 / alto_m)
        W, H = int(ancho_m * ppm), int(alto_m * ppm)
        esc.render.resolution_x, esc.render.resolution_y, esc.render.resolution_percentage = W, H, 100
        cam.data.ortho_scale = max(ancho_m, alto_m)
        cam.location = cen + desde * 10
        arriba = 'Y' if vista != 'arriba' else 'Y'
        cam.rotation_euler = (-desde).to_track_quat('-Z', 'Y').to_euler()
        ruta = '%s/medida_%s_%s.png' % (SAL, nombre, vista)
        esc.render.filepath = ruta
        bpy.ops.render.render(write_still=True)
        bpy.context.view_layer.update()
        # ejes de la imagen en el mundo
        der = cam.matrix_world.to_3x3() @ Vector((1, 0, 0))
        arr = cam.matrix_world.to_3x3() @ Vector((0, 1, 0))
        info[vista] = dict(W=W, H=H, ppm=ppm, cen=list(cen), der=list(der), arr=list(arr))
    json.dump(info, open('%s/medida_%s.json' % (SAL, nombre), 'w'))
    print('MEDIDO', nombre, [round(a, 3) for a in mn], [round(a, 3) for a in mx])

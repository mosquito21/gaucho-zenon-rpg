# Saca una hoja de cuadros de cada clip de un personaje ya armado, para mirarlo sin abrir Blender.
# Uso, desde la raiz del proyecto:
#   "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" -b assets/personajes/npc/dona_rosario_animado.blend -P tools/npc/ver_clips.py
# Deja .revision/npc_previas/<nombre>_<clip>.png: arriba cuatro momentos del clip vistos de frente, abajo los mismos de costado.
# No guarda nada en el .blend: la camara se agrega solo en memoria.
import bpy, os
import numpy as np
from mathutils import Vector

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.normpath(os.path.join(AQUI, '..', '..', '.revision', 'npc_previas'))
os.makedirs(SALIDA, exist_ok=True)
NOMBRE = os.path.basename(bpy.data.filepath).replace('_animado.blend', '')
ANCHO, ALTO = 300, 420

escena = bpy.context.scene
armadura = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
for pista in armadura.animation_data.nla_tracks:
    pista.mute = True

# Las prendas llevan el color pintado en los vertices; para la previa se les pone ese color como color de vista.
for o in bpy.data.objects:
    if o.type == 'MESH' and o.data.color_attributes:
        col = np.zeros(len(o.data.color_attributes[0].data) * 4, dtype=np.float32)
        o.data.color_attributes[0].data.foreach_get('color', col)
        medio = col.reshape(-1, 4).mean(axis=0)
        for m in o.data.materials:
            if m:
                m.diffuse_color = (float(medio[0]), float(medio[1]), float(medio[2]), 1.0)

camara = bpy.data.objects.new('CamPrevia', bpy.data.cameras.new('CamPrevia'))
escena.collection.objects.link(camara)
camara.data.type = 'ORTHO'
camara.data.ortho_scale = 2.3
escena.camera = camara
escena.render.engine = 'BLENDER_WORKBENCH'
escena.display.shading.light = 'STUDIO'
escena.display.shading.color_type = 'TEXTURE'
mundo = bpy.data.worlds.new('FondoPrevia')              # fondo gris claro (sin mundo, el render sale con fondo negro)
mundo.color = (0.72, 0.72, 0.72)
escena.world = mundo
escena.view_settings.view_transform = 'Standard'       # colores tal cual, sin el oscurecido de AgX
escena.render.resolution_x = ANCHO
escena.render.resolution_y = ALTO
escena.render.resolution_percentage = 100
escena.render.film_transparent = False
escena.render.image_settings.file_format = 'PNG'
MIRA = Vector((0.0, 0.0, 0.95))
VISTAS = [Vector((1.3, -3.0, 0.5)), Vector((3.2, 0.0, 0.3))]      # de frente (tres cuartos) y de costado


def leer(ruta):
    im = bpy.data.images.load(ruta)
    px = np.zeros(ANCHO * ALTO * 4, dtype=np.float32)
    im.pixels.foreach_get(px)
    bpy.data.images.remove(im)
    return px.reshape(ALTO, ANCHO, 4)


for accion in bpy.data.actions:
    armadura.animation_data.action = accion
    f0, f1 = accion.frame_range
    filas = []
    for desde in VISTAS:
        camara.location = MIRA + desde.normalized() * 6.0
        camara.rotation_euler = (MIRA - camara.location).to_track_quat('-Z', 'Y').to_euler()
        fila = []
        for k in range(4):
            escena.frame_set(int(f0 + (f1 - f0) * k / 4.0))
            tmp = os.path.join(SALIDA, '_tmp.png')
            escena.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            fila.append(leer(tmp))
        filas.append(np.concatenate(fila, axis=1))
    hoja = np.concatenate(filas[::-1], axis=0)          # las imagenes de Blender van de abajo hacia arriba
    salida = bpy.data.images.new('hoja', ANCHO * 4, ALTO * 2)
    salida.pixels.foreach_set(hoja.ravel())
    salida.filepath_raw = os.path.join(SALIDA, f'{NOMBRE}_{accion.name}.png')
    salida.file_format = 'PNG'
    salida.save()
    bpy.data.images.remove(salida)
    print('PREVIA', NOMBRE, accion.name, 'cuadros', int(f0), 'a', int(f1))
if os.path.exists(os.path.join(SALIDA, '_tmp.png')):
    os.remove(os.path.join(SALIDA, '_tmp.png'))

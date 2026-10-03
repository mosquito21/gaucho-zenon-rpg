# Primeros planos de un personaje animado en un momento de un clip (para revisar manos, bordes de prendas, etc.).
# blender -b <personaje>_animado.blend -P ver_detalle.py -- <salida_sin_ext> <accion> <cuadros 0..1 separados por coma>
#         <centro x,y,z> <distancia> <azimutes separados por coma> [elevacion]
import bpy, sys, os, math
from mathutils import Vector
a = sys.argv[sys.argv.index('--') + 1:]
salida, nombre_accion = a[0], a[1]
cuadros = [float(x) for x in a[2].split(',')]
centro = Vector([float(x) for x in a[3].split(',')])
dist = float(a[4])
azimutes = [float(x) for x in a[5].split(',')]
elev = math.radians(float(a[6])) if len(a) > 6 else math.radians(8)
escena = bpy.context.scene
armadura = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
accion = bpy.data.actions[nombre_accion]
if armadura.animation_data is None:
    armadura.animation_data_create()
for pista in armadura.animation_data.nla_tracks:
    pista.mute = True
armadura.animation_data.action = accion
mundo = bpy.data.worlds.new('Previa')
mundo.use_nodes = True
fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
fondo.inputs['Color'].default_value = (0.75, 0.78, 0.8, 1)
fondo.inputs['Strength'].default_value = 1.0
escena.world = mundo
sol = bpy.data.objects.new('Sol', bpy.data.lights.new('Sol', 'SUN'))
sol.data.energy = 2.2
sol.data.angle = math.radians(20)
sol.rotation_euler = (math.radians(55), 0, math.radians(-35))
escena.collection.objects.link(sol)
camara = bpy.data.objects.new('Camara', bpy.data.cameras.new('Camara'))
camara.data.lens = 50
escena.collection.objects.link(camara)
escena.camera = camara
escena.render.engine = 'CYCLES'
escena.cycles.device = 'CPU'
escena.cycles.samples = 16
escena.cycles.use_denoising = True
escena.view_settings.view_transform = 'Standard'
escena.render.resolution_x, escena.render.resolution_y = 440, 440
escena.render.image_settings.file_format = 'PNG'
f0, f1 = accion.frame_range
k = 0
for c in cuadros:
    escena.frame_set(int(round(f0 + (f1 - f0) * c)))
    for az in azimutes:
        ar = math.radians(az)
        camara.location = centro + Vector((math.cos(elev) * math.cos(ar), math.cos(elev) * math.sin(ar), math.sin(elev))) * dist
        camara.rotation_euler = (centro - camara.location).to_track_quat('-Z', 'Y').to_euler()
        escena.render.filepath = '%s_%d.png' % (salida, k)
        bpy.ops.render.render(write_still=True)
        k += 1
print('DETALLE', k, 'imagenes')

# Arma un personaje animado (NPC) a partir de lo que se bajo de Mixamo.
# Uso, desde la raiz del proyecto, con Blender sin ventana:
#   "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" -b --factory-startup -P tools/npc/armar_npc.py -- dona_rosario
# Agregar --pisar para rehacer uno que ya existe.
#
# Lee, sin modificar nada: el T-Pose y los clips (assets/personajes/animaciones/), el modelo quieto
# (assets/personajes/npc/<nombre>.blend), su textura JPG y la prenda (assets/personajes/prendas/<prenda>.blend).
# Escribe solo: assets/personajes/npc/<nombre>_animado.blend y <nombre>_animado.glb.
import bpy, bmesh, sys, json, os, math

AQUI = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.normpath(os.path.join(AQUI, '..', '..', 'assets', 'personajes')).replace('\\', '/')
args = sys.argv[sys.argv.index('--') + 1:]
NOMBRE = args[0]
PISAR = '--pisar' in args
receta = json.load(open(os.path.join(AQUI, 'recetas.json'), encoding='utf-8'))['personajes'][NOMBRE]
SALIDA_BLEND = f"{BASE}/npc/{NOMBRE}_animado.blend"
SALIDA_GLB = f"{BASE}/npc/{NOMBRE}_animado.glb"
TOLERANCIA = 0.002                          # 2 mm


def informe(*a):
    print('ARMADO', NOMBRE, *a)


def abortar(motivo):
    informe('ABORTADO:', motivo, '(no se escribio nada)')
    sys.exit(1)


for ruta in (SALIDA_BLEND, SALIDA_GLB):
    if os.path.exists(ruta) and not PISAR:
        abortar('ya existe ' + os.path.basename(ruta) + ' (usar --pisar para rehacerlo)')
for ruta in [receta['tpose']] + list(receta['clips'].values()):
    if not os.path.exists(f"{BASE}/{ruta}"):
        abortar('falta ' + ruta)

bpy.ops.wm.read_factory_settings(use_empty=True)
# Sin copias automaticas .blend1 (solo en este Blender sin ventana; no cambia la configuracion del usuario).
bpy.context.preferences.filepaths.save_version = 0
escena = bpy.context.scene

# ---------------------------------------------------------------- 1. personaje con esqueleto
bpy.ops.import_scene.fbx(filepath=f"{BASE}/{receta['tpose']}")
armadura = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
cuerpo = [o for o in bpy.data.objects if o.type == 'MESH'][0]
armadura.name = ''.join(p.capitalize() for p in NOMBRE.split('_'))
cuerpo.name = 'CuerpoMalla'
if armadura.animation_data:
    armadura.animation_data.action = None
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
informe('huesos', len(armadura.data.bones), 'vertices', len(cuerpo.data.vertices))

# ---------------------------------------------------------------- 2. control contra el modelo quieto
# La malla que devuelve Mixamo tiene que coincidir punto por punto con el modelo quieto: asi la prenda,
# hecha a la medida de ese modelo, calza sin moverla y el personaje mira para el mismo lado.
with bpy.data.libraries.load(f"{BASE}/npc/{NOMBRE}.blend", link=False) as (src, dst):
    dst.objects = list(src.objects)
quieto = [o for o in dst.objects if o is not None and o.type == 'MESH'][0]
PRESTADO = receta.get('prestado')            # nombre del personaje que presta el esqueleto y los clips, o nada
if PRESTADO:
    # ------------------------------------------------------------ 2b. esqueleto prestado
    # El personaje todavia no paso por Mixamo. Toma el esqueleto y los clips de otro de cuerpo parecido (el T-Pose
    # y los clips de la receta son los de ese otro): el esqueleto se agranda o achica hasta que los brazos queden
    # a la altura de los suyos, y cada punto de su cuerpo copia los pesos del punto mas cercano del cuerpo prestado.
    # Sirve para estar parado, hablar o sentarse. Cuando tenga su propio esqueleto de Mixamo, se saca 'prestado'
    # de la receta y se rehace con --pisar.
    escena.collection.objects.link(quieto)

    def altura_brazos(obj):
        puntos = [obj.matrix_world @ v.co for v in obj.data.vertices]
        medio = max(abs(p.x) for p in puntos)
        zs = sorted(p.z for p in puntos if 0.5 * medio < abs(p.x) < 0.8 * medio)
        return zs[len(zs) // 2], medio

    z_suyo, medio_suyo = altura_brazos(quieto)
    z_otro, medio_otro = altura_brazos(cuerpo)
    escala = z_suyo / z_otro
    armadura.scale = armadura.scale * escala
    bpy.context.view_layer.update()
    informe('esqueleto prestado de', PRESTADO, '| escala', round(escala, 3), '| brazos a', round(z_suyo, 3),
            'm | envergadura suya', round(2 * medio_suyo, 3), 'y del prestado', round(2 * medio_otro * escala, 3))
    dt = quieto.modifiers.new('Pesos', 'DATA_TRANSFER')
    dt.object = cuerpo
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = quieto
    quieto.select_set(True)
    bpy.ops.object.datalayout_transfer(modifier='Pesos')
    bpy.ops.object.modifier_apply(modifier='Pesos')
    # Los dedos pasan a moverse con la mano (las manos de dos personajes nunca coinciden dedo por dedo) y cada
    # punto se queda con sus cuatro huesos de mas peso, que es lo que usa Godot.
    manos = {}
    for lado in ('Left', 'Right'):
        nombre_mano = [g.name for g in armadura.data.bones if g.name.split(':')[-1] == lado + 'Hand'][0]
        manos[lado] = quieto.vertex_groups.get(nombre_mano) or quieto.vertex_groups.new(name=nombre_mano)
    por_indice = {g.index: g for g in quieto.vertex_groups}
    for v in quieto.data.vertices:
        pesos = {}
        for g in v.groups:
            corto = por_indice[g.group].name.split(':')[-1]
            destino = g.group
            if 'Hand' in corto and corto not in ('LeftHand', 'RightHand'):
                destino = manos['Left' if corto.startswith('Left') else 'Right'].index
            pesos[destino] = pesos.get(destino, 0.0) + g.weight
        mayores = sorted(pesos.items(), key=lambda par: -par[1])[:4]
        total = sum(w for _, w in mayores)
        for gi in [g.group for g in v.groups]:
            por_indice[gi].remove([v.index])
        for gi, w in mayores:
            if total > 1e-6:
                por_indice[gi].add([v.index], w / total, 'REPLACE')
    usados = {g.group for v in quieto.data.vertices for g in v.groups if g.weight > 1e-4}
    for g in [g for g in quieto.vertex_groups if g.index not in usados]:
        quieto.vertex_groups.remove(g)
    mundo = quieto.matrix_world.copy()
    quieto.parent = armadura
    quieto.matrix_world = mundo
    quieto.modifiers.new('Armature', 'ARMATURE').object = armadura
    datos_prestados = cuerpo.data
    bpy.data.objects.remove(cuerpo)
    bpy.data.meshes.remove(datos_prestados)
    cuerpo = quieto
    cuerpo.name = 'CuerpoMalla'
    informe('cuerpo', len(cuerpo.data.vertices), 'vertices | huesos que lo mueven', len(cuerpo.vertex_groups))
else:
    if len(quieto.data.vertices) != len(cuerpo.data.vertices):
        abortar('distinta cantidad de vertices que el modelo quieto')
    peor = 0.0
    suma = 0.0
    for va, vb in zip(cuerpo.data.vertices, quieto.data.vertices):
        d = ((cuerpo.matrix_world @ va.co) - (quieto.matrix_world @ vb.co)).length
        suma += d
        peor = max(peor, d)
    media = suma / len(cuerpo.data.vertices)
    informe('control contra el modelo quieto: media_mm', round(media * 1000, 3), 'max_mm', round(peor * 1000, 3))
    if media > TOLERANCIA:
        abortar('la malla de Mixamo no coincide con el modelo quieto')

    # ------------------------------------------------------------ 3. material: el del modelo quieto, con su JPG
    # (el que se ve hoy en el juego; Mixamo devuelve la textura en PNG, que pesa cinco veces mas)
    material = quieto.data.materials[0]
    jpg = f"{BASE}/npc/{NOMBRE}_{NOMBRE}_color.jpg"
    if os.path.exists(jpg):
        imagen = bpy.data.images.load(jpg)
        imagen.pack()
        for n in material.node_tree.nodes:
            if n.type == 'TEX_IMAGE':
                n.image = imagen
        informe('textura', os.path.basename(jpg), round(os.path.getsize(jpg) / 1e6, 2), 'MB')
    else:
        informe('textura: no hay JPG extraido, queda la del modelo quieto')
    cuerpo.data.materials.clear()
    cuerpo.data.materials.append(material)
    datos_quieto = quieto.data
    bpy.data.objects.remove(quieto)
    bpy.data.meshes.remove(datos_quieto)
    material.name = NOMBRE


# ---------------------------------------------------------------- 4. clips
def cadera():
    return [pb for pb in armadura.pose.bones if pb.name.endswith('Hips')][0]


def medir(accion):
    """Cuanto salta el esqueleto entre el ultimo cuadro y el primero (si se repite) y cuanto se corre del lugar."""
    armadura.animation_data.action = accion
    f0, f1 = int(accion.frame_range[0]), int(accion.frame_range[1])
    posiciones = []
    for f in range(f0, f1 + 1, max(1, (f1 - f0) // 40)):
        escena.frame_set(f)
        posiciones.append((armadura.matrix_world @ cadera().matrix).translation.copy())
    escena.frame_set(f0)
    a = {pb.name: (armadura.matrix_world @ pb.matrix).translation.copy() for pb in armadura.pose.bones}
    escena.frame_set(f1)
    b = {pb.name: (armadura.matrix_world @ pb.matrix).translation.copy() for pb in armadura.pose.bones}
    salto = max((a[n] - b[n]).length for n in a)
    p0 = posiciones[0]
    deriva = max(math.hypot(p.x - p0.x, p.y - p0.y) for p in posiciones)
    # altura de la parte de abajo del cuerpo cerca de la cadera, a mitad del clip (sirve para poner un asiento)
    escena.frame_set((f0 + f1) // 2)
    c = (armadura.matrix_world @ cadera().matrix).translation
    ev = cuerpo.evaluated_get(bpy.context.evaluated_depsgraph_get())
    malla = ev.to_mesh()
    bajo = min((ev.matrix_world @ v.co).z for v in malla.vertices
               if math.hypot((ev.matrix_world @ v.co).x - c.x, (ev.matrix_world @ v.co).y - c.y) < 0.18)
    ev.to_mesh_clear()
    armadura.animation_data.action = None
    return f0, f1, salto, deriva, min(p.z for p in posiciones), max(p.z for p in posiciones), bajo


armadura.animation_data_create()
acciones = []
for nombre_clip, archivo in receta['clips'].items():
    antes = set(bpy.data.objects)
    acciones_antes = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=f"{BASE}/{archivo}")
    nuevos = [o for o in bpy.data.objects if o not in antes]
    arm_clip = [o for o in nuevos if o.type == 'ARMATURE'][0]
    if len(arm_clip.data.bones) != len(armadura.data.bones):
        abortar(f'el clip {archivo} tiene otro esqueleto')
    accion = [x for x in bpy.data.actions if x not in acciones_antes][0]
    accion.name = nombre_clip
    accion.use_fake_user = True
    for o in nuevos:
        bpy.data.objects.remove(o)
    acciones.append(accion)
# Recortes: un clip nuevo hecho con un tramo de otro (por ejemplo, la parte tranquila de un clip que en el
# medio hace un gesto grande). Con "ida_y_vuelta" el tramo se reproduce y despues se desanda, asi empalma solo.
for nombre_nuevo, r in receta.get('recortes', {}).items():
    nueva = bpy.data.actions[r['de']].copy()
    nueva.name = nombre_nuevo
    nueva.use_fake_user = True
    cuadros = list(range(r['desde'], r['hasta'] + 1))
    if r.get('ida_y_vuelta'):
        cuadros += list(range(r['hasta'] - 1, r['desde'], -1))
    for fc in nueva.fcurves:
        valores = [fc.evaluate(f) for f in cuadros]
        fc.keyframe_points.clear()
        fc.keyframe_points.add(len(valores))
        co = []
        for i, v in enumerate(valores):
            co += [1.0 + i, v]
        fc.keyframe_points.foreach_set('co', co)
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
        fc.update()
    acciones.append(nueva)
# Separar los brazos del cuerpo unos grados en todos los clips (opcional, "separar_brazos" en la receta). Sirve
# cuando el personaje lleva una prenda ancha en la cadera y la mano, al colgar, se le mete adentro.
grados = float(receta.get('separar_brazos', 0))
if grados:
    from mathutils import Matrix, Quaternion, Vector
    mundo_arm = armadura.matrix_world.to_3x3().normalized()
    for lado in ('Left', 'Right'):
        brazo = [pb for pb in armadura.pose.bones if pb.name.split(':')[-1] == lado + 'Arm'][0]
        ruta = 'pose.bones["%s"].rotation_quaternion' % brazo.name
        for accion in acciones:
            curvas = [accion.fcurves.find(ruta, index=i) for i in range(4)]
            if any(c is None for c in curvas):
                continue
            # el giro se calcula una vez, con el brazo como esta a mitad del clip, y se aplica igual a todos los cuadros
            armadura.animation_data.action = accion
            escena.frame_set(int(sum(accion.frame_range) / 2))
            hueso = (mundo_arm @ brazo.matrix.to_3x3()).normalized()
            mejor = None
            for signo in (1, -1):
                giro = Matrix.Rotation(math.radians(grados * signo), 3, 'Y')
                punta = giro @ hueso @ Vector((0.0, 1.0, 0.0))    # hacia donde queda apuntando el brazo
                if mejor is None or abs(punta.x) > mejor[0]:
                    mejor = (abs(punta.x), (hueso.inverted() @ giro @ hueso).to_quaternion())
            delta = mejor[1]
            for k in range(len(curvas[0].keyframe_points)):
                q = Quaternion([c.keyframe_points[k].co[1] for c in curvas]) @ delta
                for i, c in enumerate(curvas):
                    c.keyframe_points[k].co[1] = q[i]
                    c.keyframe_points[k].handle_left[1] = q[i]
                    c.keyframe_points[k].handle_right[1] = q[i]
            for c in curvas:
                c.update()
    armadura.animation_data.action = None
    informe('brazos separados del cuerpo', grados, 'grados en', len(acciones), 'clips')
for accion in acciones:
    f0, f1, salto, deriva, zmin, zmax, bajo = medir(accion)
    informe('clip', accion.name, 'cuadros', f1 - f0 + 1, 'segundos', round((f1 - f0) / 30.0, 2),
            '| salto_al_repetir_cm', round(salto * 100, 1), '| se_corre_cm', round(deriva * 100, 1),
            '| cadera_m', round(zmin, 2), 'a', round(zmax, 2), '| bajo_cadera_m', round(bajo, 2))
for accion in acciones:
    pista = armadura.animation_data.nla_tracks.new()
    pista.name = accion.name
    pista.strips.new(accion.name, int(accion.frame_range[0]), accion)
escena.frame_set(1)

# ---------------------------------------------------------------- 5. prenda larga, pegada al mismo esqueleto
prenda = None
if receta.get('prenda'):
    with bpy.data.libraries.load(f"{BASE}/prendas/{receta['prenda']}.blend", link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n == receta['prenda']]
    prenda = dst.objects[0]
    escena.collection.objects.link(prenda)
    mundo = prenda.matrix_world.copy()
    prenda.parent = armadura
    prenda.matrix_world = mundo
    # Los pesos de cada punto de la prenda se copian del punto mas cercano del cuerpo, pero nunca de los
    # brazos ni de las manos: en la pose en T los bordes de un kupam o de un delantal quedan cerca de los
    # brazos y, si se pegan a ellos, salen puntas cuando el personaje los baja.
    def es_brazo(nombre_hueso):
        return 'Arm' in nombre_hueso or 'Hand' in nombre_hueso
    fuente = cuerpo.copy()
    fuente.data = cuerpo.data.copy()
    escena.collection.objects.link(fuente)
    grupos_brazo = {g.index for g in fuente.vertex_groups if es_brazo(g.name)}
    bm = bmesh.new()
    bm.from_mesh(fuente.data)
    capa = bm.verts.layers.deform.verify()
    sobran = [v for v in bm.verts if sum(p for gi, p in v[capa].items() if gi in grupos_brazo) > 0.35]
    bmesh.ops.delete(bm, geom=sobran, context='VERTS')
    bm.to_mesh(fuente.data)
    bm.free()
    dt = prenda.modifiers.new('Pesos', 'DATA_TRANSFER')
    dt.object = fuente
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = prenda
    prenda.select_set(True)
    bpy.ops.object.datalayout_transfer(modifier='Pesos')
    bpy.ops.object.modifier_apply(modifier='Pesos')
    datos_fuente = fuente.data
    bpy.data.objects.remove(fuente)
    bpy.data.meshes.remove(datos_fuente)
    # lo poco que haya quedado de brazo se saca, y los pesos de cada punto se llevan a que sumen 1
    for g in [g for g in prenda.vertex_groups if es_brazo(g.name)]:
        prenda.vertex_groups.remove(g)
    pecho = [g for g in prenda.vertex_groups if g.name.endswith('Spine2')][0]
    sueltos = 0
    for v in prenda.data.vertices:
        total = sum(g.weight for g in v.groups)
        if total > 1e-6:
            for g in v.groups:
                g.weight /= total
        else:
            pecho.add([v.index], 1.0, 'REPLACE')
            sueltos += 1
    if receta.get('falda'):
        # Pollera o kupam de alguien que se sienta ("falda": true en la receta): la mitad de atras cuelga de la cadera
        # y no sigue a las piernas. Si no, al sentarse las pantorrillas se llevan el ruedo de atras hacia adelante
        # y el borde se quiebra. Adelante sigue igual (muslos y pantorrillas); a los costados se mezclan.
        nombre_cadera = [b.name for b in armadura.data.bones if b.name.endswith('Hips')][0]
        cadera_g = prenda.vertex_groups.get(nombre_cadera) or prenda.vertex_groups.new(name=nombre_cadera)
        ys = [(prenda.matrix_world @ v.co).y for v in prenda.data.vertices]
        medio_y, ancho_y = (min(ys) + max(ys)) / 2.0, (max(ys) - min(ys)) / 2.0
        por_indice = {g.index: g for g in prenda.vertex_groups}
        for v, y in zip(prenda.data.vertices, ys):
            t = min(1.0, max(0.0, ((y - medio_y) / ancho_y + 0.15) / 0.7))     # 0 adelante, 1 bien atras
            atras = t * t * (3.0 - 2.0 * t)
            if atras <= 0.0:
                continue
            for gi, peso in [(g.group, g.weight) for g in v.groups]:
                por_indice[gi].add([v.index], peso * (1.0 - atras), 'REPLACE')
            cadera_g.add([v.index], atras, 'ADD')
        informe('falda: la mitad de atras de la prenda cuelga de la cadera')
    usados = {g.group for v in prenda.data.vertices for g in v.groups if g.weight > 1e-4}
    for g in [g for g in prenda.vertex_groups if g.index not in usados]:
        prenda.vertex_groups.remove(g)
    mod = prenda.modifiers.new('Armature', 'ARMATURE')
    mod.object = armadura
    tapado = receta.get('ocultar_cuerpo_entre')
    if tapado:
        # El cuerpo que queda siempre debajo de la prenda (entre esas dos alturas, en metros, con el personaje en T)
        # se saca: asi, al sentarse, la cadera y los muslos no asoman a traves de la tela.
        bm = bmesh.new()
        bm.from_mesh(cuerpo.data)
        sobran = [f for f in bm.faces if all(tapado[0] < (cuerpo.matrix_world @ v.co).z < tapado[1] for v in f.verts)]
        bmesh.ops.delete(bm, geom=sobran, context='FACES')
        bm.to_mesh(cuerpo.data)
        bm.free()
        informe('cuerpo tapado por la prenda: se sacaron', len(sobran), 'caras entre', tapado[0], 'y', tapado[1], 'm')
    informe('prenda', prenda.name, 'vertices', len(prenda.data.vertices), 'huesos que la mueven',
            sorted(g.name.split(':')[-1] for g in prenda.vertex_groups), '| puntos sin peso pasados al pecho', sueltos)

# ---------------------------------------------------------------- 6. limpiar, guardar y exportar
# Cada clip trajo su propia copia de la malla, el material y la textura: se van.
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
for ruta in (SALIDA_BLEND, SALIDA_GLB):
    if os.path.exists(ruta):
        os.remove(ruta)
# Comprimido: Mixamo trae una clave por cuadro en cada canal de cada hueso y sin comprimir pesa cuatro veces mas.
bpy.ops.wm.save_as_mainfile(filepath=SALIDA_BLEND, compress=True)
bpy.ops.object.select_all(action='DESELECT')
for o in [armadura, cuerpo] + ([prenda] if prenda else []):
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=SALIDA_GLB, export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_skins=True, export_apply=False,
                          export_image_format='JPEG', export_jpeg_quality=90)
informe('ESCRITO', os.path.basename(SALIDA_BLEND), round(os.path.getsize(SALIDA_BLEND) / 1e6, 2), 'MB |',
        os.path.basename(SALIDA_GLB), round(os.path.getsize(SALIDA_GLB) / 1e6, 2), 'MB')

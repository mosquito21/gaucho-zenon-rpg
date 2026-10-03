# zmod.py: utilidades para modelar a mano en Blender sin ventana (tanda 3). Ver LEEME.md de esta carpeta.
# Convenciones del proyecto: un objeto de malla por modelo, colores pintados en el atributo 'Col'
# (por esquina, lineal), materiales por nombre ('Mate', 'Metal', 'Brasa', 'Llama') que Godot reemplaza
# por los de assets/materiales/, y cajas de choque con el sufijo '-convcolonly'.
import bpy, bmesh, math, random, os
from contextlib import contextmanager
from mathutils import Vector, Matrix, Euler, noise


def lin(c):
    """sRGB ('#rrggbb' o tupla 0..1) -> lineal. Una tupla ya lineal se pasa tal cual con L(...)."""
    if isinstance(c, str):
        c = c.lstrip('#')
        c = tuple(int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return tuple((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c[:3])


def mezcla(a, b, t):
    a = lin(a) if isinstance(a, str) else a
    b = lin(b) if isinstance(b, str) else b
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def R(rx=0.0, ry=0.0, rz=0.0):
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_matrix().to_4x4()


def S(sx=1.0, sy=None, sz=None):
    sy = sx if sy is None else sy
    sz = sx if sz is None else sz
    return Matrix.Diagonal((sx, sy, sz, 1.0))


def catenaria(p0, p1, flecha, n=8):
    """Puntos de una soga colgada entre p0 y p1 que baja 'flecha' en el medio."""
    p0, p1 = Vector(p0), Vector(p1)
    return [p0.lerp(p1, i / n) - Vector((0, 0, flecha * 4.0 * (i / n) * (1.0 - i / n))) for i in range(n + 1)]


class Malla:
    def __init__(self, nombre, semilla=1, materiales=('Mate',)):
        self.nombre = nombre
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new('Col')
        self.materiales = list(materiales)
        self.rng = random.Random(semilla)
        self.pila = [Matrix.Identity(4)]
        self.normales_copa = {}          # cara -> centro de copa (para el follaje)

    # ------------------------------------------------------------ transformaciones
    @property
    def M(self):
        return self.pila[-1]

    @contextmanager
    def en(self, *mats):
        m = self.pila[-1]
        for x in mats:
            m = m @ x
        self.pila.append(m)
        try:
            yield
        finally:
            self.pila.pop()

    def mat(self, nombre):
        if nombre not in self.materiales:
            self.materiales.append(nombre)
        return self.materiales.index(nombre)

    # ------------------------------------------------------------ color
    def pintar(self, caras, color, var=0.0, sombra=0.0, mat='Mate', liso=True, por_cara=False):
        """color: hex, tupla lineal o funcion(co)->color lineal. var: variacion de valor por cara.
        sombra: degrade vertical (abajo mas oscuro) dentro de este grupo de caras."""
        caras = list(caras)
        if not caras:
            return caras
        mi = self.mat(mat)
        fijo = None if callable(color) else (lin(color) if isinstance(color, str) else tuple(color))
        zs = [v.co.z for f in caras for v in f.verts]
        z0, z1 = min(zs), max(zs)
        for f in caras:
            k = 1.0 + (self.rng.uniform(-var, var) if var else 0.0)
            f.material_index = mi
            f.smooth = liso
            centro = f.calc_center_median() if por_cara else None
            for l in f.loops:
                c = fijo if fijo is not None else color(centro if por_cara else l.vert.co)
                t = (l.vert.co.z - z0) / (z1 - z0) if z1 - z0 > 1e-6 else 1.0
                s = k * (1.0 - sombra * (1.0 - t))
                l[self.col] = (c[0] * s, c[1] * s, c[2] * s, 1.0)
        return caras

    # ------------------------------------------------------------ primitivas
    def caja(self, c, tam, color, rot=None, **kw):
        M = self.M @ T(*c)
        if rot:
            M = M @ R(*rot)
        hx, hy, hz = tam[0] / 2.0, tam[1] / 2.0, tam[2] / 2.0
        vs = [self.bm.verts.new(M @ Vector((x * hx, y * hy, z * hz)))
              for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        return self.pintar([self.bm.faces.new([vs[i] for i in q]) for q in idx], color, **kw)

    def tubo(self, puntos, radios, color, lados=7, tapas=True, color_tapa=None, giro=0.0, **kw):
        """Tubo a lo largo de una poligonal (coordenadas locales). radios: numero o lista."""
        pts = [Vector(p) for p in puntos]
        n = len(pts)
        if not isinstance(radios, (list, tuple)):
            radios = [radios] * n
        tangentes = []
        for i in range(n):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, n - 1)]
            tangentes.append((b - a).normalized())
        t0 = tangentes[0]
        ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
        normal = (ref - t0 * ref.dot(t0)).normalized()
        anillos = []
        for i in range(n):
            t = tangentes[i]
            normal = (normal - t * normal.dot(t)).normalized()      # transporte paralelo
            binormal = t.cross(normal)
            anillo = []
            for j in range(lados):
                a = giro + 2.0 * math.pi * j / lados
                p = pts[i] + (normal * math.cos(a) + binormal * math.sin(a)) * radios[i]
                anillo.append(self.bm.verts.new(self.M @ p))
            anillos.append(anillo)
        caras = []
        for i in range(n - 1):
            for j in range(lados):
                k = (j + 1) % lados
                caras.append(self.bm.faces.new([anillos[i][j], anillos[i][k], anillos[i + 1][k], anillos[i + 1][j]]))
        self.pintar(caras, color, **kw)
        if tapas:
            kt = dict(kw)
            kt.pop('sombra', None)
            tapa = []
            if radios[0] > 1e-5:
                tapa.append(self.bm.faces.new(list(reversed(anillos[0]))))
            if radios[-1] > 1e-5:
                tapa.append(self.bm.faces.new(anillos[-1]))
            self.pintar(tapa, color_tapa if color_tapa is not None else color, **kt)
            caras += tapa
        return caras

    def cilindro(self, p0, p1, r0, color, r1=None, **kw):
        return self.tubo([p0, p1], [r0, r0 if r1 is None else r1], color, **kw)

    def palo(self, p0, p1, r0, r1, color, curva=0.03, tramos=3, **kw):
        """Palo o tronco algo torcido, mas fino en la punta."""
        p0, p1 = Vector(p0), Vector(p1)
        largo = (p1 - p0).length
        pts, rs = [], []
        for i in range(tramos + 1):
            t = i / tramos
            p = p0.lerp(p1, t)
            if 0 < i < tramos:
                p += Vector((self.rng.uniform(-1, 1), self.rng.uniform(-1, 1), self.rng.uniform(-0.3, 0.3))) * curva * largo
            pts.append(p)
            rs.append(r0 + (r1 - r0) * t)
        return self.tubo(pts, rs, color, **kw)

    def esfera(self, c, radio, color, u=8, v=6, ruido=0.0, frec=1.5, rot=None, **kw):
        """Esfera de paralelos. radio: numero o (rx, ry, rz). ruido: abolladuras en metros."""
        r = (radio, radio, radio) if not isinstance(radio, (list, tuple)) else radio
        M = self.M @ T(*c)
        if rot:
            M = M @ R(*rot)
        ret = bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=1.0, matrix=M @ S(*r))
        return self._blanda(ret['verts'], M.to_translation(), color, ruido, frec, **kw)

    def ico(self, c, radio, color, sub=1, ruido=0.0, frec=1.5, rot=None, **kw):
        r = (radio, radio, radio) if not isinstance(radio, (list, tuple)) else radio
        M = self.M @ T(*c)
        if rot:
            M = M @ R(*rot)
        ret = bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=1.0, matrix=M @ S(*r))
        return self._blanda(ret['verts'], M.to_translation(), color, ruido, frec, **kw)

    def almohada(self, c, tam, color, e=0.5, u=12, v=8, ruido=0.0, frec=1.5, rot=None, **kw):
        """Caja inflada de bordes redondos (fardos, bolsas, bultos). e: 1 = elipsoide, 0.3 = casi una caja."""
        M = self.M @ T(*c)
        if rot:
            M = M @ R(*rot)
        ret = bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=1.0)
        h = (tam[0] / 2.0, tam[1] / 2.0, tam[2] / 2.0)
        for vert in ret['verts']:
            d = vert.co
            vert.co = M @ Vector([math.copysign(abs(d[i]) ** e, d[i]) * h[i] for i in range(3)])
        return self._blanda(ret['verts'], M.to_translation(), color, ruido, frec, **kw)

    def _blanda(self, verts, centro, color, ruido, frec, **kw):
        if ruido:
            semilla = Vector((self.rng.uniform(0, 50), self.rng.uniform(0, 50), self.rng.uniform(0, 50)))
            for vert in verts:
                d = vert.co - centro
                if d.length > 1e-6:
                    vert.co += d.normalized() * noise.noise(vert.co * frec + semilla) * ruido
        caras = {f for vert in verts for f in vert.link_faces}
        return self.pintar(caras, color, **kw)

    def rejilla(self, filas, color, doble=True, color_dentro=None, grosor=0.012, cerrar_u=False, canto=None, **kw):
        """Paño a partir de una grilla de puntos (lista de filas). Con doble=True tiene dos caras.
        canto: color del borde que une las dos caras (para paños gruesos: paja, cueros, tablas)."""
        g = [[Vector(p) for p in fila] for fila in filas]
        n, m = len(g), len(g[0])

        def caras_de(vs, invertir):
            out = []
            for i in range(n - 1):
                for j in range(m - 1 + (1 if cerrar_u else 0)):
                    k = (j + 1) % m
                    a, b, c, d = vs[i][j], vs[i][k], vs[i + 1][k], vs[i + 1][j]
                    if doble:       # la misma diagonal en las dos caras: si no, la de adentro asoma en paños alabeados
                        for t in ((a, b, c), (a, c, d)):
                            out.append(self.bm.faces.new(tuple(reversed(t)) if invertir else t))
                    else:
                        out.append(self.bm.faces.new((a, b, c, d)))
            return out

        fuera = [[self.bm.verts.new(self.M @ p) for p in fila] for fila in g]
        caras = self.pintar(caras_de(fuera, False), color, **kw)
        if doble:
            self.bm.normal_update()
            dentro = [[self.bm.verts.new(v.co - v.normal * grosor) for v in fila] for fila in fuera]
            caras += self.pintar(caras_de(dentro, True), color_dentro if color_dentro is not None else color, **kw)
            if canto is not None and not cerrar_u:
                borde = ([(0, j) for j in range(m)] + [(i, m - 1) for i in range(1, n)]
                         + [(n - 1, j) for j in range(m - 2, -1, -1)] + [(i, 0) for i in range(n - 2, 0, -1)])
                centro = sum((v.co for fila in fuera for v in fila), Vector()) / (n * m)
                nuevas = []
                for a, b in zip(borde, borde[1:] + borde[:1]):
                    f = self.bm.faces.new([fuera[a[0]][a[1]], fuera[b[0]][b[1]], dentro[b[0]][b[1]], dentro[a[0]][a[1]]])
                    f.normal_update()
                    if f.normal.dot(f.calc_center_median() - centro) < 0:
                        f.normal_flip()
                    nuevas.append(f)
                caras += self.pintar(nuevas, canto, **kw)
        return caras

    def prisma(self, perfil, y0, y1, color, **kw):
        """Perfil en el plano XZ (antihorario visto de frente, desde -Y) estirado de y0 a y1."""
        a = [self.bm.verts.new(self.M @ Vector((x, y0, z))) for x, z in perfil]
        b = [self.bm.verts.new(self.M @ Vector((x, y1, z))) for x, z in perfil]
        n = len(perfil)
        caras = [self.bm.faces.new(a), self.bm.faces.new(list(reversed(b)))]
        for i in range(n):
            k = (i + 1) % n
            caras.append(self.bm.faces.new([a[i], b[i], b[k], a[k]]))
        return self.pintar(caras, color, **kw)

    def cara(self, puntos, color, doble=False, **kw):
        vs = [self.bm.verts.new(self.M @ Vector(p)) for p in puntos]
        caras = [self.bm.faces.new(vs)]
        if doble:
            caras.append(self.bm.faces.new([self.bm.verts.new(v.co) for v in reversed(vs)]))
        return self.pintar(caras, color, **kw)

    def copa(self, c, radio, color, centro_copa, sub=2, ruido=0.25, frec=0.9, **kw):
        """Masa de follaje: una bola abollada cuyas normales miran desde el centro de la copa."""
        caras = self.ico(c, radio, color, sub=sub, ruido=ruido, frec=frec, **kw)
        centro = self.M @ Vector(centro_copa)
        for f in caras:
            self.normales_copa[f] = centro
        return caras

    # ------------------------------------------------------------ salida
    def volumen(self):
        self.bm.normal_update()
        return self.bm.calc_volume(signed=True)

    def objeto(self, angulo_filo=38.0):
        self.bm.normal_update()
        malla = bpy.data.meshes.new(self.nombre)
        # normales de copa: mezcla de la normal de la cara con la direccion desde el centro de la copa
        normales = None
        if self.normales_copa:
            self.bm.faces.ensure_lookup_table()
            normales = []
            for f in self.bm.faces:
                centro = self.normales_copa.get(f)
                for l in f.loops:
                    if centro is None:
                        normales.append(tuple(l.vert.normal if f.smooth else f.normal))
                    else:
                        d = (l.vert.co - centro)
                        d = d.normalized() if d.length > 1e-6 else Vector((0, 0, 1))
                        normales.append(tuple((d * 0.75 + l.vert.normal * 0.25).normalized()))
        self.bm.to_mesh(malla)
        for nombre in self.materiales:
            malla.materials.append(material(nombre))
        if normales is not None:
            malla.normals_split_custom_set(normales)
        else:
            malla.set_sharp_from_angle(angle=math.radians(angulo_filo))
        obj = bpy.data.objects.new(self.nombre, malla)
        bpy.context.scene.collection.objects.link(obj)
        tris = sum(len(p.vertices) - 2 for p in malla.polygons)
        print('MALLA %-22s vertices %5d  triangulos %5d  medidas %s  materiales %s' % (
            self.nombre, len(malla.vertices), tris, tuple(round(d, 2) for d in obj.dimensions), self.materiales))
        self.bm.free()
        return obj


def material(nombre):
    m = bpy.data.materials.get(nombre)
    if m:
        return m
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    nodos = m.node_tree.nodes
    bsdf = next(n for n in nodos if n.type == 'BSDF_PRINCIPLED')
    col = nodos.new('ShaderNodeVertexColor')
    col.layer_name = 'Col'
    m.node_tree.links.new(col.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 1.0
    if nombre == 'Metal':
        bsdf.inputs['Metallic'].default_value = 0.35
        bsdf.inputs['Roughness'].default_value = 0.72
    if nombre in ('Brasa', 'Llama'):
        m.node_tree.links.new(col.outputs['Color'], bsdf.inputs['Emission Color'])
        bsdf.inputs['Emission Strength'].default_value = 2.0 if nombre == 'Brasa' else 3.0
    return m


def nueva_escena():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0


def choque_caja(nombre, c, tam, rot=None):
    """Caja de choque (Godot la convierte en forma convexa y no la dibuja)."""
    m = Malla('Col' + nombre + '-convcolonly', materiales=())
    m.caja(c, tam, (1, 1, 1), rot=rot)
    m.bm.normal_update()
    malla = bpy.data.meshes.new(m.nombre)
    m.bm.to_mesh(malla)
    m.bm.free()
    obj = bpy.data.objects.new(m.nombre, malla)
    bpy.context.scene.collection.objects.link(obj)
    obj.display_type = 'WIRE'
    obj.hide_render = True
    return obj


def choque_cilindro(nombre, p0, p1, radio, lados=8):
    m = Malla('Col' + nombre + '-convcolonly', materiales=())
    m.cilindro(p0, p1, radio, (1, 1, 1), lados=lados)
    malla = bpy.data.meshes.new(m.nombre)
    m.bm.to_mesh(malla)
    m.bm.free()
    obj = bpy.data.objects.new(m.nombre, malla)
    bpy.context.scene.collection.objects.link(obj)
    obj.display_type = 'WIRE'
    obj.hide_render = True
    return obj


def guardar(ruta_sin_ext):
    """Guarda <ruta>.blend y exporta <ruta>.glb con todo lo que hay en la escena."""
    os.makedirs(os.path.dirname(ruta_sin_ext), exist_ok=True)
    for ext in ('.blend', '.glb'):
        if os.path.exists(ruta_sin_ext + ext):
            os.remove(ruta_sin_ext + ext)
    bpy.ops.wm.save_as_mainfile(filepath=ruta_sin_ext + '.blend')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=ruta_sin_ext + '.glb', export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True, export_vertex_color='MATERIAL',
                              export_animations=False, export_cameras=False, export_lights=False)
    print('GUARDADO %s.glb  %d KB' % (os.path.basename(ruta_sin_ext), os.path.getsize(ruta_sin_ext + '.glb') // 1024))
    _escribir_import(ruta_sin_ext + '.glb.import',
                     sorted({m.name for o in bpy.context.scene.objects if o.type == 'MESH' for m in o.data.materials if m}))


def _escribir_import(ruta, materiales):
    """Deja dicho en el .import que cada material del modelo es el compartido de assets/materiales/.
    Godot completa el resto del archivo (uid, rutas) cuando lo importa."""
    import re
    bloque = '_subresources={\n"materials": {\n' + ',\n'.join(
        '"%s": {\n"use_external/enabled": true,\n"use_external/fallback_path": "res://assets/materiales/%s.tres",\n'
        '"use_external/path": "res://assets/materiales/%s.tres"\n}' % (n, n.lower(), n.lower()) for n in materiales) + '\n}\n}\n'
    if os.path.exists(ruta):
        texto = open(ruta, encoding='utf-8').read()
        if all('"%s": {' % n in texto for n in materiales):
            return
        if '_subresources={}\n' in texto:
            nuevo = texto.replace('_subresources={}\n', bloque)
        else:       # el bloque termina en una linea '}' seguida de otra clave o del fin del archivo
            nuevo = re.sub(r'_subresources=\{.*?\n\}\n(?=[a-z_]|\Z)', lambda _: bloque, texto, count=1, flags=re.S)
        assert nuevo != texto, 'no encontre _subresources en ' + ruta
    else:
        nuevo = '[remap]\n\nimporter="scene"\ntype="PackedScene"\n\n[params]\n\n' + bloque
    open(ruta, 'w', encoding='utf-8', newline='\n').write(nuevo)


def figura_de_referencia(x, y):
    """Un muñeco de 1,82 m (la altura de Zenon) para medir proporciones en las vistas previas. No se exporta."""
    m = Malla('ReferenciaZenon')
    gris = (0.22, 0.2, 0.18)
    with m.en(T(x, y, 0)):
        m.caja((-0.1, 0, 0.45), (0.15, 0.17, 0.9), gris)
        m.caja((0.1, 0, 0.45), (0.15, 0.17, 0.9), gris)
        m.caja((0, 0, 1.2), (0.44, 0.24, 0.62), gris)
        m.caja((-0.29, 0, 1.18), (0.11, 0.13, 0.62), gris)
        m.caja((0.29, 0, 1.18), (0.11, 0.13, 0.62), gris)
        m.esfera((0, 0, 1.68), 0.14, (0.35, 0.25, 0.2))
    return m.objeto()


def previa(ruta, vistas=((-62, 16), (118, 16), (-20, 55)), res=(560, 420), figura=True, muestras=20, margen=1.12, cabeza=0.0):
    """Vistas previas con Cycles en CPU (no usa la placa). Deja <ruta>_0.png, _1.png..."""
    escena = bpy.context.scene
    modelos = [o for o in escena.objects if o.type == 'MESH' and not o.hide_render]
    mn = Vector((1e9, 1e9, 1e9))
    mx = -mn
    for o in modelos:
        for esquina in o.bound_box:
            p = o.matrix_world @ Vector(esquina)
            mn = Vector((min(mn.x, p.x), min(mn.y, p.y), min(mn.z, p.z)))
            mx = Vector((max(mx.x, p.x), max(mx.y, p.y), max(mx.z, p.z)))
    if cabeza:                      # primer plano de la cabeza: solo los ultimos 'cabeza' metros de arriba
        mn = Vector((-0.2, -0.22, mx.z - cabeza))
        mx = Vector((0.2, 0.22, mx.z))
        figura = False
    extras = []
    if figura:
        extras.append(figura_de_referencia(mx.x + 0.55, mn.y))
        mx.x += 0.9
        mx.z = max(mx.z, 1.82)
    suelo = Malla('Suelo')
    lado = max(mx.x - mn.x, mx.y - mn.y) * 4 + 20
    suelo.caja(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, -0.01), (lado, lado, 0.02), '#7a6f52')
    extras.append(suelo.objeto())
    centro = (mn + mx) / 2
    radio = (mx - mn).length / 2
    mundo = bpy.data.worlds.new('Previa')
    mundo.use_nodes = True
    fondo = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
    fondo.inputs['Color'].default_value = (0.62, 0.72, 0.76, 1)
    fondo.inputs['Strength'].default_value = 0.9
    escena.world = mundo
    sol = bpy.data.objects.new('Sol', bpy.data.lights.new('Sol', 'SUN'))
    sol.data.energy = 3.2
    sol.data.angle = math.radians(12)
    sol.rotation_euler = (math.radians(52), 0, math.radians(-38))
    escena.collection.objects.link(sol)
    camara = bpy.data.objects.new('Camara', bpy.data.cameras.new('Camara'))
    camara.data.lens = 50
    escena.collection.objects.link(camara)
    escena.camera = camara
    escena.render.engine = 'CYCLES'
    escena.cycles.device = 'CPU'
    escena.cycles.samples = muestras
    escena.cycles.use_denoising = True
    escena.view_settings.view_transform = 'Standard'
    escena.render.resolution_x, escena.render.resolution_y = res
    escena.render.image_settings.file_format = 'PNG'
    medio_campo = math.atan(min(36.0, 36.0 * res[1] / res[0]) / 2.0 / camara.data.lens)
    dist = radio * margen / math.sin(medio_campo)
    for i, (az, el) in enumerate(vistas):
        a, e = math.radians(az), math.radians(el)
        camara.location = centro + Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))) * dist
        camara.rotation_euler = (centro - camara.location).to_track_quat('-Z', 'Y').to_euler()
        escena.render.filepath = '%s_%d.png' % (ruta, i)
        bpy.ops.render.render(write_still=True)
    for o in extras + [sol, camara]:
        bpy.data.objects.remove(o)


if __name__ == '__main__':
    # Prueba: las primitivas cerradas tienen que quedar con las caras hacia afuera (volumen positivo).
    for nombre, armar, esperado in (
        ('caja', lambda m: m.caja((0, 0, 0), (2, 3, 4), '#808080'), 24.0),
        ('cilindro', lambda m: m.cilindro((0, 0, 0), (0, 0, 2), 1.0, '#808080', lados=64), math.pi * 2),
        ('tubo torcido', lambda m: m.tubo([(0, 0, 0), (1, 0, 1), (2, 0, 1)], 0.2, '#808080', lados=12), None),
        ('esfera', lambda m: m.esfera((0, 0, 0), 1.0, '#808080', u=32, v=16), 4.0 / 3.0 * math.pi),
        ('ico', lambda m: m.ico((0, 0, 0), 1.0, '#808080', sub=3), 4.0 / 3.0 * math.pi),
        ('prisma', lambda m: m.prisma([(0, 0), (2, 0), (2, 1), (0, 1)], 0, 3, '#808080'), 6.0),
    ):
        m = Malla('prueba')
        armar(m)
        v = m.volumen()
        assert v > 0, '%s: caras hacia adentro (volumen %.3f)' % (nombre, v)
        assert esperado is None or abs(v - esperado) / esperado < 0.05, '%s: volumen %.3f, esperado %.3f' % (nombre, v, esperado)
        print('PRUEBA', nombre, 'volumen %.3f' % v, 'bien')
    assert abs(lin('#808080')[0] - 0.2159) < 1e-3
    print('PRUEBA zmod: todo bien')


# ---------------------------------------------------------------- produccion por lista
RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')).replace(os.sep, '/')
ASSETS = os.environ.get('ZENON_ASSETS', RAIZ + '/assets')
# Las vistas previas y lo crudo de Hunyuan van a .revision/modelado/ (ni Godot ni git miran esa carpeta).
BORRADOR = RAIZ + '/.revision/modelado'
PREVIAS = os.environ.get('ZENON_PREVIAS', BORRADOR + '/previas')


def choque_convexo(nombre, puntos):
    """Forma de choque convexa a partir de una nube de puntos (por ejemplo, la cuña de una carpa)."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in puntos]
    bmesh.ops.convex_hull(bm, input=vs)
    malla = bpy.data.meshes.new('Col' + nombre + '-convcolonly')
    bm.to_mesh(malla)
    bm.free()
    obj = bpy.data.objects.new(malla.name, malla)
    bpy.context.scene.collection.objects.link(obj)
    obj.display_type = 'WIRE'
    obj.hide_render = True
    return obj


def producir(lista, argv):
    """lista: [(nombre, categoria, funcion que arma la escena, opciones de previa)]. argv: nombres a armar
    (vacio = todos) y, si se quiere, --sin-previa."""
    solo = [a for a in argv if not a.startswith('--')]
    for nombre, categoria, armar, *resto in lista:
        if solo and nombre not in solo:
            continue
        nueva_escena()
        armar()
        guardar('%s/%s/%s' % (ASSETS, categoria, nombre))
        if '--sin-previa' not in argv:
            os.makedirs(PREVIAS, exist_ok=True)
            previa(os.path.join(PREVIAS, nombre), **(resto[0] if resto else {}))

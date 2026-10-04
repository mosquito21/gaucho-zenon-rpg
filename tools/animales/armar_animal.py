# Le arma el esqueleto y los ciclos (idle, walk, graze, trot y las marchas de mas de su receta) a un animal de assets/animales/ y escribe
# assets/animales/<nombre>_animado.blend y .glb. No toca el modelo original.
# Uso, desde la raiz del proyecto:
#   "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" -b --factory-startup -P tools/animales/armar_animal.py -- ceniza vaca
# Opciones: --sin-previa (no saca las hojas de cuadros) y --prueba (no escribe en assets/: deja todo en .revision/animales/).
# Las medidas de cada animal estan en recetas.py; las hojas de cuadros van a .revision/animales/.
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector, Matrix, Euler

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
sys.dont_write_bytecode = True               # sin __pycache__ en la carpeta de la herramienta
from recetas import RECETAS

RAIZ = os.path.normpath(os.path.join(AQUI, '..', '..')).replace(os.sep, '/')
ASSETS = RAIZ + '/assets/animales'
PREVIAS = RAIZ + '/.revision/animales'
FPS = 30
X = Vector((1.0, 0.0, 0.0))


def P(x, yz):
    return Vector((x, yz[0], yz[1]))


def suave(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------- 1. malla
def abrir(nombre):
    bpy.ops.wm.open_mainfile(filepath='%s/%s.blend' % (ASSETS, nombre))
    malla = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    for o in [o for o in bpy.data.objects if o is not malla]:
        bpy.data.objects.remove(o)
    # Los puntos repetidos en las costuras de la textura se sueldan: si no, al doblarse se abren rajas.
    bm = bmesh.new()
    bm.from_mesh(malla.data)
    antes = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bm.to_mesh(malla.data)
    bm.free()
    print('MALLA', nombre, 'vertices', antes, '->', len(malla.data.vertices))
    bpy.context.scene.render.fps = FPS
    return malla


def coords(malla):
    co = np.zeros(len(malla.data.vertices) * 3, dtype=np.float32)
    malla.data.vertices.foreach_get('co', co)
    return co.reshape(-1, 3)


# ---------------------------------------------------------------- 2. esqueleto
def centro_x(co, yz, lado, r):
    """Centro de la pata a esa altura: promedio en x de los puntos de la malla cercanos, del mismo lado."""
    cerca = (np.abs(co[:, 1] - yz[0]) < r) & (np.abs(co[:, 2] - yz[1]) < r * 0.6) & (co[:, 0] * lado > 0.01)
    return float(np.abs(co[cerca, 0]).mean()) if cerca.sum() > 8 else None


def armar_esqueleto(malla, r):
    co = coords(malla)
    arm = bpy.data.objects.new('Esqueleto', bpy.data.armatures.new('Esqueleto'))
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones

    def hueso(nombre, cabeza, cola, padre=None, conectar=False):
        b = eb.new(nombre)
        b.head, b.tail = cabeza, cola
        b.align_roll(X.cross(b.tail - b.head))       # el eje X del hueso queda de costado: girar en X es doblar hacia adelante o atras
        b.parent = padre
        b.use_connect = conectar
        return b

    def cadena(prefijo, puntos, padre, x=0.0):
        """puntos: principio y despues el final de cada hueso."""
        for i in range(len(puntos) - 1):
            nombre = prefijo if len(puntos) == 2 else '%s%d' % (prefijo, i + 1)
            padre = hueso(nombre, P(x, puntos[i]), P(x, puntos[i + 1]), padre, i > 0)
        return padre

    e = r['espina']                                   # base de la cola, lomo, cruz, base del cuello
    cuerpo = hueso('cuerpo', P(0, e[1]), P(0, e[2]))
    cadera = hueso('cadera', P(0, e[1]), P(0, e[0]), cuerpo)
    pecho = hueso('pecho', P(0, e[2]), P(0, e[3]), cuerpo, True)
    ultimo = cadena('cuello', [e[3]] + r['cuello'], pecho)
    cabeza = hueso('cabeza', P(0, r['cuello'][-1]), P(0, r['cabeza']), ultimo, True)
    if r.get('orejas'):
        o = r['orejas']
        for lado, s in (('L', 1), ('R', -1)):
            hueso('oreja_' + lado, P(s * o['x'], o['base']), P(s * o.get('x_punta', o['x']) , o['punta']), cabeza)
    if r.get('cuernos'):
        c = r['cuernos']
        for lado, s in (('L', 1), ('R', -1)):
            hueso('cuerno_' + lado, Vector((s * c['base'][0], c['base'][1], c['base'][2])), Vector((s * c['punta'][0], c['punta'][1], c['punta'][2])), cabeza)
    if r.get('cola'):
        cadena('cola', r['cola'], cadera)
    for pref, clave, padre in (('del', 'del', pecho), ('tras', 'tras', cadera)):
        if clave not in r:
            continue
        pt = r[clave]['p']                            # pivote, codo o rodilla, carpo o garron, nudo, punta del pie
        for lado, s in (('L', 1), ('R', -1)):
            xs = [centro_x(co, pt[i], s, r[clave].get('radio', max(0.02, 0.045 * float(co[:, 2].max())))) for i in (2, 3)]
            xs = [v for v in xs if v is not None]
            x = s * (r[clave]['x'] if not xs or r[clave].get('x_fijo') else sum(xs) / len(xs))
            ant = padre
            for i, parte in enumerate(('sup', 'med', 'inf', 'pie')):
                ant = hueso('%s_%s_%s' % (pref, parte, lado), P(x, pt[i]), P(x, pt[i + 1]), ant, i > 0)
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


# ---------------------------------------------------------------- 3. pesos
def pesar(malla, arm, r):
    # Los pesos automaticos de Blender fallan sobre las mallas de Hunyuan ("failed to find solution"). Se calculan sobre
    # un molde limpio del mismo animal (la malla rehecha en cubitos) y se pasan a la malla de verdad por cercania.
    # Tambien fallan con animales chicos (el zorro): el molde y una copia del esqueleto se llevan a la talla del caballo.
    from mathutils.kdtree import KDTree
    TALLA = 1.9
    k = TALLA / float(coords(malla)[:, 2].max())
    if r.get('molde'):
        # La malla propia no sirve de molde (a la oveja, al sacarle los cuernos, le quedo la cabeza rota y el molde sale
        # en pedacitos): se usa la de otro animal con el mismo cuerpo.
        with bpy.data.libraries.load('%s/%s.blend' % (ASSETS, r['molde'])) as (origen, destino):
            destino.objects = [r['molde']]
        molde = destino.objects[0]
    else:
        molde = malla.copy()
        molde.data = malla.data.copy()
    arm2 = arm.copy()
    arm2.data = arm.data.copy()
    bpy.ops.object.select_all(action='DESELECT')
    for o in (molde, arm2):
        bpy.context.scene.collection.objects.link(o)
        o.scale = (k, k, k)
        o.select_set(True)
    bpy.context.view_layer.objects.active = molde
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = molde.modifiers.new('Molde', 'REMESH')
    mod.mode = 'VOXEL'
    mod.voxel_size = TALLA / 150.0
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = arm2
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    nombres = [b.name for b in arm.data.bones]
    Wm = np.zeros((len(molde.data.vertices), len(nombres)), dtype=np.float32)
    indice = {molde.vertex_groups[nm].index: j for j, nm in enumerate(nombres) if nm in molde.vertex_groups}
    for v in molde.data.vertices:
        for g in v.groups:
            if g.group in indice:
                Wm[v.index, indice[g.group]] = g.weight
    com = coords(molde) / k
    bien = np.where(Wm.sum(axis=1) >= 1e-4)[0]
    sin_peso = len(com) - len(bien)
    if len(bien) == 0:
        raise RuntimeError('los pesos automaticos fallaron tambien sobre el molde')
    arbol = KDTree(len(bien))
    for j, i in enumerate(bien):
        arbol.insert(com[i], j)
    arbol.balance()
    co = coords(malla)
    n = len(co)
    W = np.zeros((n, len(nombres)), dtype=np.float32)
    for i in range(n):
        for _, j, d in arbol.find_n(co[i], 6):
            W[i] += Wm[bien[j]] / (d * k + 0.002)
    for o in (molde, arm2):
        bpy.data.objects.remove(o)
    malla.parent = arm
    malla.modifiers.new('Armature', 'ARMATURE').object = arm
    # Zonas rigidas (estribos, cuernos): la caja entera sigue a un solo hueso.
    for (x0, x1, y0, y1, z0, z1), hueso in r.get('rigido', []):
        dentro = (np.abs(co[:, 0]) >= x0) & (np.abs(co[:, 0]) <= x1) & (co[:, 1] >= y0) & (co[:, 1] <= y1) & (co[:, 2] >= z0) & (co[:, 2] <= z1)
        W[dentro] = 0.0
        W[dentro, nombres.index(hueso)] = 1.0
        print('RIGIDO', hueso, int(dentro.sum()), 'puntos')
    # Las patas no arrastran la panza: el hueso de arriba de cada pata pierde fuerza hacia el medio del cuerpo.
    for j, nm in enumerate(nombres):
        if '_sup_' in nm:
            lado = 1.0 if nm.endswith('_L') else -1.0
            xp = abs(arm.data.bones[nm].head_local.x)
            W[:, j] *= np.clip((co[:, 0] * lado) / (xp * 0.6), 0.0, 1.0) ** 1.5
    # Como mucho cuatro huesos por punto, y que sumen 1.
    orden = np.argsort(-W, axis=1)[:, 4:]
    np.put_along_axis(W, orden, 0.0, axis=1)
    suma = W.sum(axis=1, keepdims=True)
    vacio = suma[:, 0] < 1e-6
    W[vacio, nombres.index('cuerpo')] = 1.0
    W /= W.sum(axis=1, keepdims=True)
    for g in list(malla.vertex_groups):
        malla.vertex_groups.remove(g)
    for j, nm in enumerate(nombres):
        g = malla.vertex_groups.new(name=nm)
        for i in np.where(W[:, j] > 0.002)[0]:
            g.add([int(i)], float(W[i, j]), 'REPLACE')
    print('PESOS puntos', n, '| molde', len(com), 'puntos,', sin_peso, 'sin peso | huesos', len(nombres))
    return W, nombres


# ---------------------------------------------------------------- 4. patas
def rot2(v, a):
    c, s = math.cos(a), math.sin(a)
    return np.array((v[0] * c - v[1] * s, v[0] * s + v[1] * c))


class Pata:
    """Una pata de tres huesos y pie. Dado donde esta el pivote y donde tiene que estar el nudo, dobla las
    articulaciones en su sentido natural (el que traen en reposo) hasta que la pata mide lo justo."""

    def __init__(self, arm, pref, lado, flex):
        self.nombres = ['%s_%s_%s' % (pref, parte, lado) for parte in ('sup', 'med', 'inf', 'pie')]
        hs = [arm.data.bones[nm] for nm in self.nombres]
        self.M = [h.matrix_local.to_3x3() for h in hs]
        self.padre = hs[0].parent.name
        self.rel = (hs[0].parent.matrix_local.inverted() @ hs[0].matrix_local)     # donde cuelga del pecho o la cadera
        yz = lambda v: np.array((v.y, v.z))
        self.A0, self.D0, self.E0 = hs[0].head_local.copy(), hs[3].head_local.copy(), hs[3].tail_local.copy()
        self.u, self.v, self.w = yz(hs[1].head_local - hs[0].head_local), yz(hs[2].head_local - hs[1].head_local), yz(hs[3].head_local - hs[2].head_local)
        ang = lambda a, b: math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1])
        self.g1 = math.copysign(flex[0], ang(self.u, self.v))
        self.g2 = math.copysign(flex[1], ang(self.v, self.w))
        self.qs, self.largos = self.tabla(self.g2)
        self.largo_max = float(self.largos[0])
        self.largo_reposo = float(np.linalg.norm(self.u + self.v + self.w))

    def tabla(self, g2):
        """Cuanto mide la pata segun cuanto se dobla (q), de lo mas estirada en adelante."""
        qs = np.linspace(-1.2, 2.4, 721)
        largos = np.array([np.linalg.norm(self.forma(q, g2)[3]) for q in qs])
        tope = int(np.argmax(largos))
        return qs[tope:], np.minimum.accumulate(largos[tope:])

    def forma(self, q, g2=None):
        v = rot2(self.v, self.g1 * q)
        w = rot2(self.w, (self.g1 + (self.g2 if g2 is None else g2)) * q)
        return self.u, v, w, self.u + v + w

    def resolver(self, A, T, flex2=None):
        """Devuelve las orientaciones (3x3, espacio de la armadura) de sup, med e inf y cuanto falto para llegar.
        flex2: otro reparto de la flexion para la articulacion de abajo (ver 'carpo_apoyo' en paso)."""
        t = T - A
        d = t.length
        if flex2 is None:
            g2, qs, largos, largo_max = None, self.qs, self.largos, self.largo_max
        else:
            g2 = math.copysign(flex2, self.g2)
            qs, largos = self.tabla(g2)
            largo_max = float(largos[0])
        q = float(np.interp(-min(d, largo_max), -largos, qs))
        u, v, w, e = self.forma(q, g2)
        ae = e / np.linalg.norm(e)
        be = np.array((-ae[1], ae[0]))
        a = t / d
        n = (X - a * X.dot(a)).normalized()
        b = n.cross(a)
        Q = []
        for h in (u, v, w):
            dire = (a * float(h @ ae) + b * float(h @ be)).normalized()
            Q.append(Matrix((n, dire, n.cross(dire))).transposed())
        return Q, n, max(0.0, d - largo_max)


# ---------------------------------------------------------------- 5. animacion
class Animador:
    def __init__(self, arm, malla, r):
        self.arm, self.malla, self.r = arm, malla, r
        self.pb = arm.pose.bones
        for b in self.pb:
            b.rotation_mode = 'QUATERNION'
        self.M = {b.name: b.bone.matrix_local.to_3x3() for b in self.pb}
        self.patas = {}
        for pref in ('del', 'tras'):
            if pref in r:
                for lado in ('L', 'R'):
                    self.patas[pref + '_' + lado] = Pata(arm, pref, lado, r[pref].get('flex', (1.0, 1.0)))
        del_, tras = self.patas.get('del_L'), self.patas.get('tras_L')
        self.centro = ((del_.A0 if del_ else tras.A0) + tras.A0) / 2.0          # el cuerpo cabecea y se ladea sobre este punto
        self.centro.x = 0.0
        self.largo_pata = tras.A0.z - tras.D0.z
        self.ultimo_q = {}
        self.falta = 0.0
        self.fases = {}
        for clave in ('del_L', 'tras_L'):
            if clave in self.patas:
                print('PATA %-6s en reposo mide %.3f m y estirada %.3f m' % (clave, self.patas[clave].largo_reposo, self.patas[clave].largo_max))
        arm.animation_data_create()

    def gira(self, nombre, rx=0.0, ry=0.0, rz=0.0):
        """Gira un hueso respecto de su padre. Ejes del animal: rx baja la cabeza (o levanta la cola),
        ry se ladea hacia su izquierda, rz dobla hacia su izquierda. En radianes."""
        if nombre not in self.M:
            return
        D = Euler((rx, ry, rz), 'XYZ').to_matrix()
        self.pb[nombre].rotation_quaternion = (self.M[nombre].inverted() @ D @ self.M[nombre]).to_quaternion()

    def cuerpo(self, dx=0.0, dy=0.0, dz=0.0, rx=0.0, ry=0.0, rz=0.0):
        """Mueve y gira todo el cuerpo alrededor de su centro (no de la cabeza del hueso)."""
        D = Euler((rx, ry, rz), 'XYZ').to_matrix()
        cab = self.arm.data.bones['cuerpo'].head_local
        mov = D @ (cab - self.centro) - (cab - self.centro) + Vector((dx, dy, dz))
        self.pb['cuerpo'].rotation_quaternion = (self.M['cuerpo'].inverted() @ D @ self.M['cuerpo']).to_quaternion()
        self.pb['cuerpo'].location = self.M['cuerpo'].inverted() @ mov

    def pies(self, pies):
        """pies: {pata: (corrimiento de la punta del pie (x, y, z), giro del pie en radianes, punta hacia abajo)}.
        Las patas que no figuran quedan apoyadas donde estan en reposo. Un tercer dato, si viene, es el reparto
        de la flexion de esa pata en ese momento (ver 'carpo_apoyo' en paso)."""
        bpy.context.view_layer.update()
        for clave, pata in self.patas.items():
            mov, giro, *flex2 = pies.get(clave, ((0.0, 0.0, 0.0), 0.0))
            padre = self.pb[pata.padre].matrix
            A = (padre @ pata.rel).translation
            R = Matrix.Rotation(giro, 3, 'X')
            T = pata.E0 + Vector(mov) + R @ (pata.D0 - pata.E0)
            Q, n, falta = pata.resolver(A, T, *flex2)
            self.falta = max(self.falta, falta)
            Q.append(R @ pata.M[3])
            P_ = padre.to_3x3()
            for i, nm in enumerate(pata.nombres):
                L = (pata.M[i - 1].inverted() @ pata.M[i]) if i else pata.rel.to_3x3()
                self.pb[nm].rotation_quaternion = ((P_ @ L).inverted() @ Q[i]).to_quaternion()
                P_ = Q[i]

    def clave(self, cuadro):
        for b in self.pb:
            q = b.rotation_quaternion.copy()
            ant = self.ultimo_q.get(b.name)
            if ant is not None and ant.dot(q) < 0.0:      # el mismo giro con el signo cambiado: se evita el salto
                q.negate()
                b.rotation_quaternion = q
            self.ultimo_q[b.name] = q
            b.keyframe_insert('rotation_quaternion', frame=cuadro)
        self.pb['cuerpo'].keyframe_insert('location', frame=cuadro)

    def clip(self, nombre, segundos, pose):
        """pose(t, fase) acomoda los huesos para el momento t (segundos); fase va de 0 a 1."""
        accion = bpy.data.actions.new(nombre)
        accion.use_fake_user = True
        self.arm.animation_data.action = accion
        self.ultimo_q, self.falta = {}, 0.0
        cuadros = int(round(segundos * FPS))
        for f in range(cuadros + 1):
            for b in self.pb:
                b.rotation_quaternion = (1, 0, 0, 0)
                b.location = (0, 0, 0)
            fase = (f % cuadros) / cuadros            # el ultimo cuadro repite el primero: el bucle no salta
            pose(fase * segundos, fase)
            self.clave(f)
        self.arm.animation_data.action = None
        print('CLIP %-6s %.2f s  %d cuadros  le falto pata: %.1f cm' % (nombre, segundos, cuadros, self.falta * 100))
        return accion

    # ---- paso de una pata dentro del ciclo
    def paso(self, fase, m, delantera):
        """Devuelve (corrimiento de la punta del pie, giro del pie) para una pata en la fase 0..1 de su propio ciclo.
        Apoyo: el pie va hacia atras a velocidad pareja, pegado al suelo. Vuelo: vuelve hacia adelante levantado."""
        S, beta = m['zancada'], m['apoyo']
        alto = m['alto_del' if delantera else 'alto_tras']
        giro_max = math.radians(m['giro_del' if delantera else 'giro_tras'])
        despegue = math.radians(m.get('despegue', 18.0))
        ade = m.get('adelanta_del' if delantera else 'adelanta_tras', 0.0)      # el apoyo entero corrido hacia adelante
        # 'carpo_apoyo': con zancadas largas el cuerpo va bajo y la mano apoyada tiene que encogerse; con el reparto de
        # la receta ('flex') lo hace quebrando el carpo hacia adelante. Mientras apoya usa este otro reparto (0,5 deja
        # la cana a plomo y encoge desde el codo) y en el vuelo vuelve al suyo, que es el que pliega la mano.
        ca = m.get('carpo_apoyo') if delantera else None
        if fase < beta:
            s = fase / beta
            return ((0.0, -S / 2 + S * s - ade, 0.0), despegue * suave((s - 0.78) / 0.22)) + (() if ca is None else (ca,))
        s = (fase - beta) / (1.0 - beta)
        if ca is not None:
            ca += (self.r['del'].get('flex', (1.0, 1.0))[1] - ca) * suave(s / 0.25) * suave((1.0 - s) / 0.25)
        # La velocidad del apoyo, para que el pie salga y llegue sin tiron. Con apoyos cortos (galope) eso lo manda
        # mucho mas atras y mas adelante de lo que la pata alcanza: 'empalme' dice que parte de esa velocidad conserva.
        vel = S * (1.0 - beta) / beta * m.get('empalme', 1.0)
        h00, h10, h01, h11 = 2 * s ** 3 - 3 * s ** 2 + 1, s ** 3 - 2 * s ** 2 + s, -2 * s ** 3 + 3 * s ** 2, s ** 3 - s ** 2
        y = h00 * S / 2 + h10 * vel - h01 * S / 2 + h11 * vel
        z = alto * math.sin(math.pi * s ** 0.9) ** m.get('vuelo', 2)      # 'vuelo' 1: el pie sube y baja de golpe (suspension)
        if s < 0.35:
            giro = despegue + (giro_max - despegue) * suave(s / 0.35)
        else:
            giro = giro_max * (1.0 - suave((s - 0.35) / 0.55))
        return ((0.0, y - ade, z), giro) + (() if ca is None else (ca,))


def mover(an, r):
    """Arma los clips del animal."""
    L = an.largo_pata
    cuadrupedo = 'del' in r
    cuello = ['cuello%d' % (i + 1) for i in range(len(r['cuello']))] if len(r['cuello']) > 1 else ['cuello']
    cola = ['cola%d' % (i + 1) for i in range(len(r.get('cola', [])) - 1)] if len(r.get('cola', [])) > 2 else (['cola'] if r.get('cola') else [])
    rad = math.radians
    est = r.get('estilo', {})

    def cola_y_orejas(t, vaiven=1.0, periodo=3.0, alza=0.0, ondea=0.0):
        for i, nm in enumerate(cola):
            an.gira(nm, rx=rad(est.get('cola_alza', 0.0)) * (i == 0) + rad(alza) * (1.0 if i == 0 else 0.25)
                    + rad(ondea) * math.sin(2 * math.pi * (t / periodo - 0.18 * i)),
                    rz=rad(est.get('cola_vaiven', 4.0)) * vaiven * math.sin(2 * math.pi * (t / periodo - 0.13 * i)))

    def marcha(nombre, m, fases):
        """Las marchas de siempre (paso, trote) mueven el cuerpo dos veces por ciclo. Una marcha que no es pareja a los
        dos lados (galope) trae en la receta sus 'fases' por pata y los movimientos de una vez por ciclo: 'cabeceo1'
        (el tronco se hamaca), 'bote1', 'recoge_tras' y 'recoge_del', 'cuello1'. Sin esas claves todo eso da cero."""
        T = m['T']
        fases = m.get('fases', fases)

        def pose(t, f):
            dos = 4 * math.pi * (f - m['apoyo'] / 2)            # lo mas bajo, a mitad del apoyo
            una = 2 * math.pi * f
            vez = lambda en: math.cos(2 * math.pi * (f - m.get(en, 0.0)))      # una vez por ciclo, lo mas alto en esa fase
            an.cuerpo(dz=-m['agache'] - m.get('bote', 0.0) * math.cos(dos) + m.get('bote1', 0.0) * vez('bote1_en'),
                      rx=rad(m.get('cabeceo', 0.0)) * math.cos(4 * math.pi * (f - fases['tras_L'] - m['apoyo'] / 2))
                      + rad(m.get('cabeceo1', 0.0)) * vez('cabeceo1_en'),
                      dx=m.get('vaiven', 0.0) * math.cos(una - 2 * math.pi * fases['tras_L'] - math.pi * m['apoyo']))
            an.gira('cadera', rx=-rad(m.get('recoge_tras', 0.0)) * vez('recoge_en'),
                    ry=-rad(m.get('ladeo', 0.0)) * math.cos(una - 2 * math.pi * fases['tras_L'] - math.pi * m['apoyo']),
                    rz=-rad(m.get('quiebre', 0.0)) * math.cos(una - 2 * math.pi * fases['tras_L']))
            if cuadrupedo:
                an.gira('pecho', rx=rad(m.get('recoge_del', 0.0)) * vez('recoge_en'),
                        ry=-rad(m.get('ladeo', 0.0)) * 0.6 * math.cos(una - 2 * math.pi * fases['del_L'] - math.pi * m['apoyo']),
                        rz=-rad(m.get('quiebre', 0.0)) * 0.7 * math.cos(una - 2 * math.pi * fases['del_L']))
            asiente = rad(m.get('asiente', 0.0)) * math.cos(4 * math.pi * (f - fases.get('del_L', 0.25) - m['apoyo'] / 2))
            for i, nm in enumerate(cuello):
                an.gira(nm, rx=asiente / len(cuello) + rad(m.get('cuello_baja', 0.0)) / len(cuello)
                        - rad(m.get('cuello1', 0.0)) * vez('cabeceo1_en') / len(cuello))
            an.gira('cabeza', rx=-asiente * 0.6 - rad(m.get('hocico', 0.0)))
            cola_y_orejas(t, m.get('cola', 1.0), T, m.get('cola_alza', 0.0), m.get('cola_ondea', 0.0))
            an.pies({clave: an.paso((f - fases[clave]) % 1.0, m, clave.startswith('del')) for clave in an.patas})
        an.fases[nombre] = fases
        accion = an.clip(nombre, T, pose)
        print('VELOCIDAD natural de %s: %.2f m/s' % (nombre, m['zancada'] / (m['apoyo'] * accion.frame_range[1] / FPS)))
        return accion

    clips = []
    # ---- quieto: respira, cambia el peso, mueve la cola y una oreja
    def idle(t, f):
        resp = (1 - math.cos(2 * math.pi * t / 3.0)) / 2
        peso = math.sin(2 * math.pi * f)
        an.cuerpo(dz=-0.004 * L * resp, dx=0.008 * L * peso, rx=rad(0.5) * resp, ry=rad(0.8) * peso)
        an.gira('pecho', rx=-rad(0.9) * resp)
        mira = math.sin(2 * math.pi * f) * suave(f / 0.25) * suave((1 - f) / 0.25)
        for nm in cuello:
            an.gira(nm, rx=rad(1.2) * resp / len(cuello) + rad(est.get('mira_baja', 3.0)) * abs(mira) / len(cuello), rz=rad(est.get('mira', 14.0)) * mira / len(cuello))
        an.gira('cabeza', rx=rad(2.0) * math.sin(2 * math.pi * 2 * f), rz=rad(5.0) * mira)
        golpe = math.sin(math.pi * suave((f - 0.70) / 0.12)) if 0.70 < f < 0.82 else 0.0     # un coletazo
        for i, nm in enumerate(cola):
            an.gira(nm, rz=rad(est.get('cola_vaiven', 4.0)) * math.sin(2 * math.pi * (t / 3.0 - 0.13 * i)) + rad(est.get('coletazo', 16.0)) * golpe * (1 if i else 0.5))
        for nm, cuando, lado in (('oreja_L', 0.18, 1), ('oreja_R', 0.55, -1)):
            tiron = rad(est.get('oreja', 22.0)) * (math.sin(math.pi * (f - cuando) / 0.07) if cuando < f < cuando + 0.07 else 0.0)
            if nm in an.M and abs(an.M[nm].col[1].x) > 0.6:
                an.gira(nm, rz=tiron * lado)
            else:
                an.gira(nm, rx=-tiron)
        an.pies({})
    clips.append(an.clip('idle', 6.0, idle))

    if cuadrupedo:
        fases_paso = {'tras_L': 0.0, 'del_L': 0.25, 'tras_R': 0.5, 'del_R': 0.75}     # cuatro tiempos, lateral
        fases_trote = {'tras_L': 0.0, 'del_R': 0.0, 'tras_R': 0.5, 'del_L': 0.5}       # diagonales
    else:
        fases_paso = fases_trote = {'tras_L': 0.0, 'tras_R': 0.5}
    clips.append(marcha('walk', r['walk'], fases_paso))

    # ---- pastar: baja la cabeza, come con golpecitos, la levanta
    g = r['graze']
    assert g['T'] % 3.0 == 0.0, 'graze dura un multiplo de 3 s: es lo que tardan la respiracion y el vaiven de la cola'

    def graze(t, f):
        dur = g['T']
        abajo = suave(t / g['baja']) * suave((dur - t) / g['baja'])
        resp = (1 - math.cos(2 * math.pi * t / 3.0)) / 2
        come = abajo * math.sin(2 * math.pi * t * g.get('ritmo', 1.5)) * suave((t - g['baja']) / 0.5) * suave((dur - g['baja'] - t) / 0.5)
        lado = abajo * math.sin(2 * math.pi * t / 3.0)
        an.cuerpo(dz=-g.get('agache', 0.0) * abajo - 0.004 * L * resp, rx=rad(g.get('cuerpo', 0.0)) * abajo)
        an.gira('pecho', rx=rad(g.get('pecho', 0.0)) * abajo - rad(0.9) * resp)
        for i, nm in enumerate(cuello):
            an.gira(nm, rx=rad(g['cuello'][i]) * abajo + rad(1.5) * come, rz=rad(g.get('barre', 6.0)) * lado / len(cuello))
        an.gira('cabeza', rx=rad(g['cabeza']) * abajo + rad(g.get('mordisco', 5.0)) * come)
        cola_y_orejas(t)
        an.pies({})
    clips.append(an.clip('graze', g['T'], graze))

    if 'trot' in r:
        clips.append(marcha('trot', r['trot'], fases_trote))
    for nombre in r.get('otras_marchas', ()):         # las marchas de mas van despues de las de siempre
        clips.append(marcha(nombre, r[nombre], fases_trote))
    return clips


# ---------------------------------------------------------------- 6. control, guardado y vistas
def apoyo(an, W, nombres, clips, r):
    """Control: en marcha, lo mas bajo de cada pie tiene que quedar a la altura del suelo mientras apoya y no hundirse nunca."""
    co0 = coords(an.malla)
    pies = {clave: W[:, nombres.index(pata.nombres[3])] > 0.5 for clave, pata in an.patas.items()}
    for accion in clips:
        if accion.name not in an.fases:
            continue
        an.arm.animation_data.action = accion
        beta, n = r[accion.name]['apoyo'], int(accion.frame_range[1])
        hunde = flota = 0.0
        for f in range(n):
            bpy.context.scene.frame_set(f)
            ev = an.malla.evaluated_get(bpy.context.evaluated_depsgraph_get())
            me = ev.to_mesh()
            c = np.zeros(len(me.vertices) * 3, dtype=np.float32)
            me.vertices.foreach_get('co', c)
            ev.to_mesh_clear()
            c = c.reshape(-1, 3)
            for clave, pie in pies.items():
                dz = float(c[pie, 2].min() - co0[pie, 2].min())
                hunde = max(hunde, -dz)
                if (f / n - an.fases[accion.name][clave]) % 1.0 < beta * 0.75:
                    flota = max(flota, dz)
        print('APOYO %-5s un pie se hunde como mucho %.1f cm y en el apoyo se despega como mucho %.1f cm' % (accion.name, hunde * 100, flota * 100))
    an.arm.animation_data.action = None


def guardar(nombre, arm, malla, clips, prueba):
    for accion in clips:
        pista = arm.animation_data.nla_tracks.new()
        pista.name = accion.name
        pista.strips.new(accion.name, 0, accion)
    carpeta = PREVIAS if prueba else ASSETS
    base = '%s/%s_animado' % (carpeta, nombre)
    for ext in ('.blend', '.glb'):
        if os.path.exists(base + ext):
            os.remove(base + ext)
    bpy.ops.wm.save_as_mainfile(filepath=base + '.blend', compress=True)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    malla.select_set(True)
    bpy.ops.export_scene.gltf(filepath=base + '.glb', export_format='GLB', use_selection=True,
                              export_animations=True, export_animation_mode='NLA_TRACKS',
                              export_skins=True, export_apply=False, export_yup=True,
                              export_image_format='JPEG', export_jpeg_quality=90)
    # Control: el GLB tiene que traer los clips con su nombre y su duracion, y un solo esqueleto.
    import json, struct
    with open(base + '.glb', 'rb') as f:
        f.seek(12)
        largo = struct.unpack('<I', f.read(4))[0]
        f.read(4)
        g = json.loads(f.read(largo))
    duracion = lambda a: max(g['accessors'][smp['input']]['max'][0] for smp in a['samplers'])
    traidos = {a['name']: round(duracion(a), 2) for a in g.get('animations', [])}
    assert set(traidos) == {a.name for a in clips} and len(g['skins']) == 1, traidos
    print('ESCRITO %s_animado.glb %.2f MB, .blend %.2f MB | huesos %d | clips %s | imagenes %d' % (
        nombre, os.path.getsize(base + '.glb') / 1e6, os.path.getsize(base + '.blend') / 1e6, len(g['skins'][0]['joints']), traidos, len(g.get('images', []))))


def hojas(nombre, arm, malla, clips, r):
    """Dos hojas por animal: <nombre>_costado.png (una fila por clip, ocho momentos de cada uno; la raya roja es el suelo)
    y <nombre>_detalle.png (cuatro momentos en grande, de tres cuartos, para mirar como se dobla la malla)."""
    esc = bpy.context.scene
    co = coords(malla)
    mn, mx = Vector(co.min(axis=0).tolist()), Vector(co.max(axis=0).tolist())
    cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam'))
    esc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    esc.camera = cam
    esc.render.engine = 'BLENDER_WORKBENCH'
    esc.display.shading.light = 'STUDIO'
    esc.display.shading.color_type = 'TEXTURE'
    mundo = bpy.data.worlds.new('Fondo')
    mundo.color = (0.74, 0.74, 0.74)
    esc.world = mundo
    esc.view_settings.view_transform = 'Standard'
    esc.render.image_settings.file_format = 'PNG'
    esc.render.resolution_percentage = 100
    largo, alto = (mx.y - mn.y) * 1.35, mx.z * 1.12 + 0.05
    centro = Vector((0, (mn.y + mx.y) / 2, alto / 2 - 0.03))
    por_nombre = {a.name: a for a in clips}
    tmp = PREVIAS + '/_tmp.png'

    def foto(accion, parte, desde, ancho_px, ancho_m, suelo=False):
        alto_px = max(120, int(ancho_px * alto / ancho_m * (1.0 if suelo else 1.3)))
        esc.render.resolution_x, esc.render.resolution_y = ancho_px, alto_px
        cam.data.ortho_scale = max(ancho_m, alto * (1.0 if suelo else 1.3))
        cam.location = centro + Vector(desde).normalized() * 12
        cam.rotation_euler = (centro - cam.location).to_track_quat('-Z', 'Y').to_euler()
        arm.animation_data.action = accion
        esc.frame_set(int(round(accion.frame_range[1] * parte)))
        esc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(tmp)
        px = np.zeros(ancho_px * alto_px * 4, dtype=np.float32)
        im.pixels.foreach_get(px)
        bpy.data.images.remove(im)
        px = px.reshape(alto_px, ancho_px, 4)
        if suelo:
            px[max(0, min(alto_px - 1, int(alto_px / 2 - centro.z * ancho_px / ancho_m))), :, :3] = (0.9, 0.1, 0.1)
        px[:, 0, :3] = 0.3
        return px

    def escribir(filas, ruta):
        hoja = np.concatenate(filas[::-1], axis=0)       # las imagenes de Blender van de abajo hacia arriba
        sal = bpy.data.images.new('hoja', hoja.shape[1], hoja.shape[0])
        sal.pixels.foreach_set(hoja.ravel())
        sal.filepath_raw = ruta
        sal.file_format = 'PNG'
        sal.save()
        bpy.data.images.remove(sal)

    escribir([np.concatenate([foto(a, k / 8, (1, 0, 0.06), 250, largo, True) for k in range(8)], axis=1) for a in clips],
             '%s/%s_costado.png' % (PREVIAS, nombre))
    marcha2 = 'trot' if 'trot' in por_nombre else 'idle'
    adelante, atras = (0.9, -0.8, 0.22), (0.9, 1, 0.22)
    detalle = [(('walk', 0.15, adelante), ('walk', 0.65, atras)), (('graze', 0.5, adelante), (marcha2, 0.3 if marcha2 == 'trot' else 0.76, atras))]
    for c in r.get('otras_marchas', ()):              # una fila por marcha de mas, en los dos momentos que diga su receta
        a, b = r[c].get('detalle', (0.15, 0.65))
        detalle.append(((c, a, adelante), (c, b, atras)))
    escribir([np.concatenate([foto(por_nombre[c], parte, desde, 740, largo * 1.12) for c, parte, desde in fila], axis=1) for fila in detalle],
             '%s/%s_detalle.png' % (PREVIAS, nombre))
    arm.animation_data.action = None
    if os.path.exists(tmp):
        os.remove(tmp)
    bpy.data.objects.remove(cam)
    print('HOJAS', nombre, [a.name for a in clips])


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:]
    os.makedirs(PREVIAS, exist_ok=True)
    for nombre in [a for a in args if not a.startswith('--')]:
        r = RECETAS[nombre]
        if isinstance(r, str):                        # otro pelaje del mismo animal
            r = RECETAS[r]
        malla = abrir(nombre)
        arm = armar_esqueleto(malla, r)
        W, nombres = pesar(malla, arm, r)
        an = Animador(arm, malla, r)
        clips = mover(an, r)
        apoyo(an, W, nombres, clips, r)
        if '--sin-previa' not in args:
            hojas(nombre, arm, malla, clips, r)
        guardar(nombre, arm, malla, clips, '--prueba' in args)

class_name Porte
extends SkeletonModifier3D

## El porte de un personaje: su manera de pararse y de moverse.
## Se suma por encima de cualquier clip de Mixamo, sin tocarlo: encorva o yergue la espalda, baja o
## levanta la cabeza, deja caer los hombros, hace que cada tanto mire hacia un lado y que se meza
## apenas, como quien cambia el peso de pierna. Lo crean player.gd (Zenón) y npc_animado.gd (la gente),
## que le pasan los números; no hace falta ponerlo a mano en la escena.

## Espalda, en grados: positivo encorva, negativo yergue (pecho afuera).
var encorvar := 0.0
## Cabeza, en grados: positivo la baja, negativo levanta el mentón.
var cabeza := 0.0
## Hombros, en grados: positivo los deja caer hacia adelante, negativo los echa atrás.
var hombros := 0.0
## Cuántos grados gira la cabeza cuando mira alrededor (0: no mira).
var mirar := 0.0
## Cada cuántos segundos, más o menos, mira hacia un lado.
var mirar_cada := 7.0
## A quién sigue con la mirada, en grados desde su frente (positivo, hacia su izquierda). Lo pone
## npc_animado.gd mientras Zenón le pasa cerca; con NAN no sigue a nadie y mira por su cuenta.
var seguir := NAN
## Grados de vaivén lento del tronco.
var mecer := 0.0
## Grados que se abren los brazos hacia afuera, para que las manos no se metan en el cuerpo.
var abrir_brazos := 0.0
## Largo de los dedos: 1 los deja como vienen en el modelo; 0.6 los acorta al 60 %.
var dedos := 1.0

## Sentado en un caballo (tanda 6): 0 es a pie y 1 es sentado en el recado, con las piernas a los
## estribos y las manos adelante. Los valores del medio son el momento de subir o de bajar.
## Los puntos del recado los da el caballo (montura() de npc_animado.gd) y se pasan con sentar().
var montado := 0.0
## Cuánto se echa hacia adelante sobre el recado, en grados (al galope, más).
var inclinar := 0.0
## Cuánto se abren las rodillas hacia afuera (0 las deja mirando al frente).
var abrir_rodillas := 0.55
var _puntos := {}

var _t := 0.0
var _mira := 0.0
var _mira_meta := 0.0
var _mira_falta := 0.0
var _seguia := false
var _huesos := {}
# Los ejes del cuerpo dentro del esqueleto: hacia su izquierda, hacia arriba y hacia el frente.
# No se dan por sabidos, se miden en _ready: según cómo se exportó el modelo, "arriba" es Y o es -Z
# (los de este juego, que pasaron por Blender, vienen acostados: arriba es -Z).
var _lado := Vector3.RIGHT
var _arriba := Vector3.UP
var _frente := Vector3.BACK

func _ready() -> void:
	# Cada personaje arranca en un momento distinto, para que no se muevan todos a la vez.
	_t = randf() * 60.0
	_mira_falta = randf() * mirar_cada
	var esqueleto := get_skeleton()
	if esqueleto == null:
		return
	for nombre: String in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "RightShoulder",
			"LeftArm", "RightArm", "LeftHandIndex1", "RightHandIndex1", "LeftHandThumb1", "RightHandThumb1",
			"LeftForeArm", "RightForeArm", "LeftHand", "RightHand",
			"LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		_huesos[nombre] = esqueleto.find_bone("mixamorig_" + nombre)
	if _huesos["Hips"] >= 0 and _huesos["Head"] >= 0 and _huesos["LeftArm"] >= 0 and _huesos["RightArm"] >= 0:
		_arriba = _eje(_descanso(esqueleto, "Head") - _descanso(esqueleto, "Hips"))
		_lado = _eje(_descanso(esqueleto, "LeftArm") - _descanso(esqueleto, "RightArm"))
		_frente = _lado.cross(_arriba)
		assert(not _frente.is_zero_approx(), "Porte: no pude medir los ejes del esqueleto de %s" % esqueleto.get_path())

func _process_modification_with_delta(delta: float) -> void:
	var esqueleto := get_skeleton()
	if esqueleto == null:
		return
	_t += delta
	# Mirar alrededor: cada tanto elige un lado, gira despacio, se queda un momento y vuelve al frente.
	# Si está siguiendo a alguien con la mirada, eso manda; al soltarlo vuelve al frente y sigue con lo suyo.
	if not is_nan(seguir):
		_mira_meta = seguir
		_mira_falta = mirar_cada * 0.5
		_seguia = true
	elif _seguia:
		_seguia = false
		_mira_meta = 0.0
	elif mirar > 0.0:
		_mira_falta -= delta
		if _mira_falta <= 0.0:
			if absf(_mira_meta) > 1.0:
				_mira_meta = 0.0
				_mira_falta = mirar_cada * randf_range(0.7, 1.4)
			else:
				_mira_meta = randf_range(0.5, 1.0) * mirar * (1.0 if randf() < 0.5 else -1.0)
				_mira_falta = mirar_cada * randf_range(0.2, 0.45)
	else:
		_mira_meta = 0.0
	_mira = lerpf(_mira, _mira_meta, clampf(delta * (4.0 if _seguia else 2.2), 0.0, 1.0))
	var vaiven := sin(_t * 0.55) * mecer
	# Los brazos cuelgan (o gesticulan) como dice el clip: se anota hacia dónde apuntan antes de
	# tocar la espalda y los hombros, y al final se los vuelve a dejar así. Si no, al encorvar la
	# espalda o dejar caer los hombros el brazo entero gira y la mano se mete en la cadera.
	var brazo_izq := _orientacion(esqueleto, "LeftArm")
	var brazo_der := _orientacion(esqueleto, "RightArm")

	# Girar sobre el eje del lado inclina hacia adelante, sobre el de arriba hace mirar a los costados
	# y sobre el del frente ladea.
	_girar(esqueleto, "Spine", _lado, encorvar * 0.3 + inclinar * montado)
	_girar(esqueleto, "Spine", _frente, vaiven)
	_girar(esqueleto, "Spine1", _lado, encorvar * 0.35)
	_girar(esqueleto, "Spine2", _lado, encorvar * 0.35)
	_girar(esqueleto, "Spine2", _frente, -vaiven * 0.6)
	_girar(esqueleto, "Spine2", _arriba, _mira * 0.2)
	# El cuello compensa parte de lo encorvado, para que siga mirando al frente y no al piso.
	_girar(esqueleto, "Neck", _lado, cabeza * 0.4 - encorvar * 0.3)
	_girar(esqueleto, "Neck", _arriba, _mira * 0.3)
	_girar(esqueleto, "Head", _lado, cabeza * 0.6 - encorvar * 0.2)
	_girar(esqueleto, "Head", _arriba, _mira * 0.5)
	_girar(esqueleto, "LeftShoulder", _frente, -hombros)
	_girar(esqueleto, "LeftShoulder", _arriba, -hombros * 0.8)
	_girar(esqueleto, "RightShoulder", _frente, hombros)
	_girar(esqueleto, "RightShoulder", _arriba, hombros * 0.8)
	_orientar(esqueleto, "LeftArm", Basis(_frente, deg_to_rad(abrir_brazos)) * brazo_izq)
	_orientar(esqueleto, "RightArm", Basis(_frente, deg_to_rad(-abrir_brazos)) * brazo_der)
	if montado > 0.001 and not _puntos.is_empty():
		_sentar(esqueleto)
	# Dedos más cortos: se achica el primer hueso de cada dedo a lo largo (su eje Y) y el resto lo sigue.
	if not is_equal_approx(dedos, 1.0):
		for nombre: String in ["LeftHandIndex1", "RightHandIndex1", "LeftHandThumb1", "RightHandThumb1"]:
			var indice: int = _huesos.get(nombre, -1)
			if indice >= 0:
				var largo := dedos if nombre.contains("Index") else lerpf(1.0, dedos, 0.6)
				esqueleto.set_bone_pose_scale(indice, Vector3(1.0, largo, 1.0))

## Los puntos del recado donde se sienta: {"asiento", "estribo_izq", "estribo_der", "manos"} (Node3D).
## Con un diccionario vacío se baja. Cuánto está sentado lo dice `montado`.
func sentar(puntos: Dictionary) -> void:
	_puntos = puntos
	if puntos.is_empty():
		montado = 0.0

## La postura de jinete, encima de lo que diga el clip: la cadera va al asiento, los tobillos a los
## estribos (doblando la rodilla hacia adelante y afuera) y las manos a las riendas.
func _sentar(esqueleto: Skeleton3D) -> void:
	var asiento := _puntos.get("asiento") as Node3D
	if asiento == null or not is_instance_valid(asiento):
		return
	var a_esqueleto := esqueleto.global_transform.affine_inverse()
	var cadera: int = _huesos.get("Hips", -1)
	if cadera < 0:
		return
	var pose := esqueleto.get_bone_global_pose(cadera)
	pose.origin = pose.origin.lerp(a_esqueleto * asiento.global_position, montado)
	esqueleto.set_bone_global_pose(cadera, pose)
	for lado: Array in [["Left", "estribo_izq", 1.0], ["Right", "estribo_der", -1.0]]:
		var estribo := _puntos.get(lado[1]) as Node3D
		if estribo == null:
			continue
		var afuera: Vector3 = _lado * float(lado[2])
		_alcanzar(esqueleto, lado[0] + "UpLeg", lado[0] + "Leg", lado[0] + "Foot",
				a_esqueleto * estribo.global_position, _frente + afuera * abrir_rodillas + _arriba * 0.2)
		# El pie queda como en la pose de descanso (plano y mirando al frente), con la punta apenas
		# afuera y el taco apenas más bajo, como quien pisa el estribo.
		var pie: int = _huesos.get(lado[0] + "Foot", -1)
		if pie >= 0:
			var pose_pie := esqueleto.get_bone_global_pose(pie)
			var plano := Basis(_arriba, deg_to_rad(12.0) * float(lado[2])) * Basis(_lado, deg_to_rad(-8.0)) * esqueleto.get_bone_global_rest(pie).basis
			pose_pie.basis = pose_pie.basis.orthonormalized().slerp(plano.orthonormalized(), clampf(montado, 0.0, 1.0))
			esqueleto.set_bone_global_pose(pie, pose_pie)
	var manos := _puntos.get("manos") as Node3D
	if manos != null:
		# La izquierda lleva las riendas, al medio; la derecha descansa más abajo y afuera.
		var riendas := a_esqueleto * manos.global_position
		var cm := 0.01 / maxf(esqueleto.global_transform.basis.x.length(), 0.0001)  # un centímetro, en las unidades del esqueleto
		_alcanzar(esqueleto, "LeftArm", "LeftForeArm", "LeftHand", riendas + _lado * 3.0 * cm, _lado * 0.7 - _arriba - _frente * 0.5)
		_alcanzar(esqueleto, "RightArm", "RightForeArm", "RightHand", riendas - _lado * 16.0 * cm - _arriba * 12.0 * cm - _frente * 14.0 * cm, -_lado * 0.7 - _arriba - _frente * 0.5)

## Lleva la punta de una cadena de dos huesos (muslo y pierna, o brazo y antebrazo) a un punto del
## espacio del esqueleto, doblando la articulación del medio hacia `codo`. Se mezcla según `montado`.
func _alcanzar(esqueleto: Skeleton3D, arriba: String, medio: String, punta: String, meta: Vector3, codo: Vector3) -> void:
	var i_arriba: int = _huesos.get(arriba, -1)
	var i_medio: int = _huesos.get(medio, -1)
	var i_punta: int = _huesos.get(punta, -1)
	if i_arriba < 0 or i_medio < 0 or i_punta < 0:
		return
	var a := esqueleto.get_bone_global_pose(i_arriba).origin
	var l1 := a.distance_to(esqueleto.get_bone_global_pose(i_medio).origin)
	var l2 := esqueleto.get_bone_global_pose(i_medio).origin.distance_to(esqueleto.get_bone_global_pose(i_punta).origin)
	var hacia := meta - a
	var d := clampf(hacia.length(), absf(l1 - l2) + 0.001 * l1, (l1 + l2) * 0.999)
	var dir := hacia.normalized()
	var coseno := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var fuera := (codo - dir * codo.dot(dir)).normalized()
	var articulacion := a + dir * (l1 * coseno) + fuera * (l1 * sqrt(1.0 - coseno * coseno))
	_apuntar(esqueleto, arriba, medio, articulacion - a)
	_apuntar(esqueleto, medio, punta, a + dir * d - articulacion)

## Gira un hueso para que apunte (hacia su hueso hijo) en esa dirección, mezclado según `montado`.
func _apuntar(esqueleto: Skeleton3D, hueso: String, hijo: String, direccion: Vector3) -> void:
	var indice: int = _huesos.get(hueso, -1)
	var i_hijo: int = _huesos.get(hijo, -1)
	if indice < 0 or i_hijo < 0 or direccion.is_zero_approx():
		return
	var pose := esqueleto.get_bone_global_pose(indice)
	var actual := esqueleto.get_bone_global_pose(i_hijo).origin - pose.origin
	if actual.is_zero_approx():
		return
	var giro := Quaternion(actual.normalized(), direccion.normalized())
	pose.basis = Basis(Quaternion.IDENTITY.slerp(giro, clampf(montado, 0.0, 1.0))) * pose.basis
	esqueleto.set_bone_global_pose(indice, pose)

## Dónde está un hueso con el personaje en su pose de descanso (la T).
func _descanso(esqueleto: Skeleton3D, hueso: String) -> Vector3:
	return esqueleto.get_bone_global_rest(_huesos[hueso]).origin

## El eje derecho más parecido a una dirección medida (X, Y o Z, con su signo).
func _eje(direccion: Vector3) -> Vector3:
	var eje := Vector3.ZERO
	var i := direccion.abs().max_axis_index()
	eje[i] = signf(direccion[i])
	return eje

## Hacia dónde apunta un hueso ahora (en el espacio del cuerpo).
func _orientacion(esqueleto: Skeleton3D, hueso: String) -> Basis:
	var indice: int = _huesos.get(hueso, -1)
	return esqueleto.get_bone_global_pose(indice).basis if indice >= 0 else Basis.IDENTITY

## Deja un hueso apuntando hacia donde se le dice, sin moverlo de su lugar.
func _orientar(esqueleto: Skeleton3D, hueso: String, orientacion: Basis) -> void:
	var indice: int = _huesos.get(hueso, -1)
	if indice < 0:
		return
	var pose := esqueleto.get_bone_global_pose(indice)
	pose.basis = orientacion
	esqueleto.set_bone_global_pose(indice, pose)

## Gira un hueso tantos grados sobre un eje del cuerpo (no del hueso), encima de la pose que ya trae.
func _girar(esqueleto: Skeleton3D, hueso: String, eje: Vector3, grados: float) -> void:
	var indice: int = _huesos.get(hueso, -1)
	if indice < 0 or is_zero_approx(grados):
		return
	var pose := esqueleto.get_bone_global_pose(indice)
	pose.basis = Basis(eje, deg_to_rad(grados)) * pose.basis
	esqueleto.set_bone_global_pose(indice, pose)

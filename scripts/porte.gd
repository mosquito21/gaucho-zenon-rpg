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
## Grados de vaivén lento del tronco.
var mecer := 0.0
## Grados que se abren los brazos hacia afuera, para que las manos no se metan en el cuerpo.
var abrir_brazos := 0.0
## Largo de los dedos: 1 los deja como vienen en el modelo; 0.6 los acorta al 60 %.
var dedos := 1.0

var _t := 0.0
var _mira := 0.0
var _mira_meta := 0.0
var _mira_falta := 0.0
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
			"LeftArm", "RightArm", "LeftHandIndex1", "RightHandIndex1", "LeftHandThumb1", "RightHandThumb1"]:
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
	if mirar > 0.0:
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
	_mira = lerpf(_mira, _mira_meta, clampf(delta * 2.2, 0.0, 1.0))
	var vaiven := sin(_t * 0.55) * mecer
	# Los brazos cuelgan (o gesticulan) como dice el clip: se anota hacia dónde apuntan antes de
	# tocar la espalda y los hombros, y al final se los vuelve a dejar así. Si no, al encorvar la
	# espalda o dejar caer los hombros el brazo entero gira y la mano se mete en la cadera.
	var brazo_izq := _orientacion(esqueleto, "LeftArm")
	var brazo_der := _orientacion(esqueleto, "RightArm")

	# Girar sobre el eje del lado inclina hacia adelante, sobre el de arriba hace mirar a los costados
	# y sobre el del frente ladea.
	_girar(esqueleto, "Spine", _lado, encorvar * 0.3)
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
	# Dedos más cortos: se achica el primer hueso de cada dedo a lo largo (su eje Y) y el resto lo sigue.
	if not is_equal_approx(dedos, 1.0):
		for nombre: String in ["LeftHandIndex1", "RightHandIndex1", "LeftHandThumb1", "RightHandThumb1"]:
			var indice: int = _huesos.get(nombre, -1)
			if indice >= 0:
				var largo := dedos if nombre.contains("Index") else lerpf(1.0, dedos, 0.6)
				esqueleto.set_bone_pose_scale(indice, Vector3(1.0, largo, 1.0))

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

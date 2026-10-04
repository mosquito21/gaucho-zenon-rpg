extends Node3D

## Pone en movimiento a un personaje armado con Mixamo (los "<nombre>_animado.glb").
## Va en el nodo del personaje, el que tiene adentro a "Modelo". Reproduce los clips de la
## lista en orden y vuelve a empezar; si un nombre aparece varias veces, ese clip se repite.
## También lo usan los caballos y los perros (clips "idle" y "graze").
##
## Desde la tanda 6 además lo hace andar, si se le pide: una ronda corta entre puntos, seguir a
## alguien en fila, ir hasta quien lo llama (Ceniza cuando Zenón silba), ir llevado (Ceniza
## montada) o ir sentado en un caballo. Anda en línea recta siguiendo la altura del suelo: no
## esquiva nada, así que las rondas van por lugares despejados. No toca los trabajos ni la charla.

## Clips a reproducir, en orden. Los nombres son los que trae el GLB (idle, talking, etc.).
@export var clips: Array[String] = ["idle"]
## Segundos que tarda en pasar suave de un clip al siguiente.
@export var mezcla: float = 0.4
## Arranca en un clip y en un momento al azar, para que no se muevan todos a la vez.
@export var arranque_al_azar: bool = true
## A más de esta distancia de la cámara (en metros) la animación se detiene, para no gastar
## en mover a quien no se ve. Al acercarse sigue donde estaba.
@export var distancia_animado: float = 130.0

@export_group("Andar")
## Los clips de andar del modelo y la velocidad (metros por segundo) a la que cada uno pisa sin
## patinar. A la gente con el esqueleto de Zenón que no trae "walk" se le presta el de Zenón.
@export var marchas: Dictionary = {"walk": 1.55}
## Ronda: los puntos por los que pasa, en metros desde donde está parado (x hacia el este, y hacia
## el sur). Va de uno a otro, vuelve a su lugar y empieza de nuevo. Vacía: no camina.
@export var ronda: PackedVector2Array = PackedVector2Array()
## Segundos que se queda en cada punto de la ronda.
@export var pausa_ronda: float = 9.0
## Velocidad de la ronda, en metros por segundo.
@export var velocidad_ronda: float = 1.1
## A cuántos metros de Zenón deja de caminar y se queda mirándolo.
@export var parar_cerca: float = 4.0
## A quién sigue de cerca, pisando por donde pisa y a la velocidad de la ronda (el perro del
## capataz). Vacío: a nadie.
@export var sigue_a: NodePath
## Cuántos metros al costado de quien sigue va, en vez de justo detrás (el perro: así el capataz no
## lo atraviesa cuando vuelve sobre sus pasos).
@export var al_costado: float = 0.0

@export_group("Montura")
## Solo para los caballos. Dónde va sentado el jinete, dónde pisan los estribos (el izquierdo; el
## derecho es su espejo) y dónde lleva las manos, en metros: x al costado, y arriba, z hacia la cabeza.
## Medidos sobre el modelo de Ceniza (los otros pelajes son el mismo modelo): el asiento es donde va
## la cadera del jinete, unos diez centímetros por encima del cojinillo; el estribo, donde va el tobillo.
@export var asiento := Vector3(0.0, 1.59, 0.2)
@export var estribo := Vector3(0.335, 0.92, 0.32)
@export var manos := Vector3(0.0, 1.66, 0.46)

@export_group("Porte")
## Ritmo: 1 es el del clip. Menos es más lento y pesado; más es más rápido y nervioso.
@export_range(0.5, 1.5, 0.01) var ritmo: float = 1.0
## Espalda, en grados: positivo encorva, negativo yergue (pecho afuera).
@export_range(-15.0, 30.0, 0.5) var encorvar: float = 0.0
## Cabeza, en grados: positivo la baja, negativo levanta el mentón.
@export_range(-15.0, 20.0, 0.5) var cabeza: float = 0.0
## Hombros, en grados: positivo los deja caer hacia adelante, negativo los echa atrás.
@export_range(-10.0, 15.0, 0.5) var hombros: float = 0.0
## Cuántos grados gira la cabeza cuando mira alrededor (0: no mira).
@export_range(0.0, 45.0, 1.0) var mirar: float = 0.0
## Cada cuántos segundos, más o menos, mira hacia un lado.
@export_range(2.0, 20.0, 0.5) var mirar_cada: float = 7.0
## Grados de vaivén lento del tronco, como quien cambia el peso de pierna.
@export_range(0.0, 5.0, 0.1) var mecer: float = 0.0
## Grados que se abren los brazos hacia afuera, para que las manos no se metan en el cuerpo o en la ropa.
@export_range(0.0, 20.0, 0.5) var abrir_brazos: float = 0.0
## Largo de los dedos: 1 los deja como vienen en el modelo; menos los acorta (solo en personajes con dedos).
@export_range(0.4, 1.0, 0.01) var dedos: float = 1.0

const ZENON_GLB := "res://assets/personajes/gaucho_zenon_animado.glb"
## Los clips de Zenón que se prestan, y a qué altura lleva él la cadera (para ajustarlos a cada cuerpo).
static var _de_zenon := {}
static var _cadera_zenon := 0.0

enum Modo { QUIETO, RONDA, FILA, VIENE, LLEVADO, SENTADO, CAMINO }

var _anim: AnimationPlayer
var _porte: Porte
var _turno: int = 0
var _falta_revisar: float = 0.0

var _modo := Modo.QUIETO
## El clip de andar que está puesto ("" si está con su lista de siempre).
var _andando := ""
## La velocidad con la que elige el clip de andar (en fila, la de los últimos momentos).
var _tranco := 0.0
var _casa := Vector3.ZERO
var _giro_casa := 0.0
## Cuánto queda el nodo por encima del suelo (casi siempre nada). Se mide al dar el primer paso.
var _alto := NAN
## El punto de la ronda hacia el que va (el 0 es su lugar; arranca parado ahí, así que va al 1).
var _punto := 1
var _descanso := 0.0
var _jugador: Node3D
var _hablando := false
var _atendiendo := false
# Fila y llamado
var _guia: Node3D
var _separacion := 2.5
var _espera_desde := 45.0
var _paso_fila := 0.0
var _migas: Array[Vector3] = []
var _largo_migas := 0.0
var _hasta := 2.5
var _camino := PackedVector3Array()
# Montura (caballos) y jinete (gente sentada en un caballo)
var _montura := {}
var _caballo: Node3D


func _ready() -> void:
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		push_warning("%s: no hay AnimationPlayer debajo de este nodo (¿el Modelo es un _animado.glb?)" % name)
		return
	var validos: Array[String] = []
	for clip in clips:
		if _anim.has_animation(clip):
			validos.append(clip)
		else:
			push_warning("%s: el modelo no tiene el clip '%s'" % [name, clip])
	clips = validos
	if clips.is_empty():
		return
	_armar_porte()
	_anim.playback_default_blend_time = mezcla
	_anim.animation_finished.connect(_al_terminar)
	if arranque_al_azar:
		_turno = randi() % clips.size()
	_tocar()
	if arranque_al_azar:
		_anim.seek(randf() * _anim.current_animation_length, true)
	_casa = global_position
	# El giro se lleva siempre en el mundo: casi toda la gente cuelga de un lugar que está girado
	# (el fortín, la pulpería, la toldería) y con el giro propio caminaba de perfil.
	_giro_casa = global_rotation.y
	if not ronda.is_empty():
		_modo = Modo.RONDA
		_descanso = randf() * pausa_ronda
	elif not sigue_a.is_empty() and get_node_or_null(sigue_a) is Node3D:
		seguir(get_node(sigue_a) as Node3D, 1.6, 40.0, velocidad_ronda)


func _process(delta: float) -> void:
	if _anim == null:
		return
	if _modo != Modo.QUIETO and _modo != Modo.LLEVADO:
		_andar(delta)
	# Dos o tres veces por segundo mira si la cámara está cerca; si no, deja la animación en pausa.
	_falta_revisar -= delta
	if _falta_revisar > 0.0:
		return
	_falta_revisar = 0.4
	var camara := get_viewport().get_camera_3d()
	if camara == null:
		return
	var cerca := camara.global_position.distance_squared_to(global_position) < distancia_animado * distancia_animado
	_anim.active = cerca
	if _porte != null:
		_porte.active = cerca


func _al_terminar(_clip: StringName) -> void:
	if _andando != "":
		return
	_turno = (_turno + 1) % clips.size()
	_tocar()


## Cuando Zenón le habla: si el modelo trae el clip "talking", lo hace una vez y después sigue
## con su lista de siempre. Lo llama scripts/Historia.gd al abrir la charla.
func gesto_de_hablar() -> void:
	_hablando = true
	if _anim != null and _andando == "" and _anim.has_animation("talking") and _anim.current_animation != "talking":
		_anim.play("talking", -1.0, ritmo)


## Cada vez que empieza un clip va un poquito más rápido o más lento, para que no se repita igual.
func _tocar() -> void:
	_anim.play(clips[_turno], -1.0, ritmo * randf_range(0.93, 1.07))


## El porte se suma por encima de los clips (ver scripts/porte.gd). Si todo está en cero, no se crea.
func _armar_porte(aunque_sea_neutro := false) -> void:
	if _porte != null:
		return
	if not aunque_sea_neutro and is_zero_approx(absf(encorvar) + absf(cabeza) + absf(hombros) + mirar + mecer + abrir_brazos + absf(1.0 - dedos)):
		return
	var esqueleto := find_child("Skeleton3D", true, false) as Skeleton3D
	if esqueleto == null:
		return
	_porte = Porte.new()
	_porte.name = "Porte"
	_porte.encorvar = encorvar
	_porte.cabeza = cabeza
	_porte.hombros = hombros
	_porte.mirar = mirar
	_porte.mirar_cada = mirar_cada
	_porte.mecer = mecer
	_porte.abrir_brazos = abrir_brazos
	_porte.dedos = dedos
	esqueleto.add_child(_porte)


# ------------------------------------------------------------------ andar

## Sigue a alguien en fila: pisa por donde pisó, queda a `separacion` metros y, si el guía se le va
## a más de `espera_desde`, se para a esperarlo. `paso` es la velocidad de la fila (0: la suya).
func seguir(guia: Node3D, separacion := 2.5, espera_desde := 45.0, paso := 0.0) -> void:
	_guia = guia
	_separacion = separacion
	_espera_desde = espera_desde
	_paso_fila = paso
	_migas.clear()
	_largo_migas = 0.0
	_modo = Modo.FILA


## Va derecho hasta alguien y se para a `hasta` metros (Ceniza cuando Zenón silba).
func venir(a_quien: Node3D, hasta := 2.5) -> void:
	_guia = a_quien
	_hasta = hasta
	_modo = Modo.VIENE


## Camina una sola vez por esos puntos del mundo y se queda en el último.
func andar_por(puntos: PackedVector3Array, velocidad := 1.3) -> void:
	_camino = puntos
	_paso_fila = velocidad
	_modo = Modo.CAMINO


## Deja de andar y vuelve a su lista de clips, donde esté.
func quedarse() -> void:
	_modo = Modo.RONDA if not ronda.is_empty() else Modo.QUIETO
	_casa = global_position if ronda.is_empty() else _casa
	_dejar_de_andar()


## ¿Está yendo hacia alguien o siguiéndolo?
func en_camino() -> bool:
	return _modo == Modo.VIENE or (_modo == Modo.FILA and _andando != "")


## Lo lleva otro (Ceniza montada): quien lo lleva lo mueve y le dice cómo pisa con pisar().
func llevar(si: bool) -> void:
	_modo = Modo.LLEVADO if si else Modo.QUIETO
	if not si:
		_casa = global_position
		_dejar_de_andar()


## Pone el clip de andar que corresponde a esa velocidad (o el que se le diga), al ritmo justo
## para que los pies no patinen. Con velocidad cero vuelve a la lista de clips de siempre.
func pisar(velocidad: float, clip := "") -> void:
	if _anim == null:
		return
	if velocidad < 0.05:
		_dejar_de_andar()
		return
	if clip == "":
		# En fila la velocidad baja un instante en cada quiebre del camino: el clip se elige con la de
		# los últimos momentos, no con la del cuadro, o cambiaba de paso por nada.
		_tranco = lerpf(_tranco, velocidad, minf(get_process_delta_time() * 1.5, 1.0)) if _modo == Modo.FILA and _andando != "" else velocidad
		var mejor := 1e9
		for nombre: String in marchas:
			# El clip que ya está puesto corre con ventaja, para no cambiar de paso a cada rato en el límite.
			# Más ventaja si anda solo, que va regulando la velocidad de a poco; llevado por el jinete
			# tiene que cambiar enseguida, porque sus tres velocidades caen cerca de los límites.
			var ventaja := 0.0 if nombre != _andando else (0.05 if _modo == Modo.LLEVADO else 0.2)
			var lejos := absf(log(_tranco / maxf(float(marchas[nombre]), 0.01))) - ventaja
			if lejos < mejor:
				mejor = lejos
				clip = nombre
	if clip == "" or (not _anim.has_animation(clip) and not _prestar(clip)):
		return
	if _andando != clip:
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		# Solo al cambiar de clip: llamado en cada cuadro, play() apila una mezcla nueva cada vez.
		_anim.play(clip, 0.35)
	_andando = clip
	_anim.speed_scale = clampf(velocidad / maxf(float(marchas.get(clip, velocidad)), 0.01), 0.5, 1.7)


func _dejar_de_andar() -> void:
	if _andando == "":
		return
	_andando = ""
	_anim.speed_scale = 1.0
	_tocar()


func _andar(delta: float) -> void:
	match _modo:
		Modo.RONDA:
			if _atender(delta):
				return
			if _descanso > 0.0:
				_descanso -= delta
				_dejar_de_andar()
				# De vuelta en su lugar (lo que sigue es el primer punto), mira hacia donde miraba.
				if _punto == 1:
					global_rotation.y = rotate_toward(global_rotation.y, _giro_casa, 2.0 * delta)
				return
			var meta := _lugar_de_ronda(_punto)
			if _paso_hacia(meta, velocidad_ronda, delta):
				# Se detiene donde da la vuelta o dobla fuerte; por los puntos de paso sigue de largo.
				var antes := _lugar_de_ronda(_punto - 1)
				var despues := _lugar_de_ronda(_punto + 1)
				var dobla := (meta - antes).normalized().dot((despues - meta).normalized()) < 0.5
				_punto = (_punto + 1) % (ronda.size() + 1)
				if dobla or _punto == 1:
					_descanso = pausa_ronda * randf_range(0.7, 1.3)
		Modo.FILA:
			_en_fila(delta)
		Modo.VIENE:
			if _guia == null or not is_instance_valid(_guia):
				quedarse()
				return
			var falta := _plano(global_position, _guia.global_position)
			if falta <= _hasta:
				quedarse()
				return
			# De lejos viene al trote largo; al arrimarse, afloja.
			var rapido: float = 0.0
			for nombre: String in marchas:
				rapido = maxf(rapido, float(marchas[nombre]) if not nombre.begins_with("gallop") else 0.0)
			_paso_hacia(_guia.global_position, clampf((falta - _hasta) * 0.9 + 1.0, 1.0, rapido), delta)
		Modo.CAMINO:
			if _camino.is_empty():
				_modo = Modo.QUIETO
				_dejar_de_andar()
			elif _paso_hacia(_camino[0], _paso_fila, delta):
				_camino.remove_at(0)
		Modo.SENTADO:
			if _caballo == null or not is_instance_valid(_caballo):
				_modo = Modo.QUIETO
				return
			var montura: Dictionary = _caballo.montura()
			global_transform = Transform3D(_caballo.global_transform.basis.orthonormalized(), (montura["asiento"] as Node3D).global_position)


## El punto número tanto de la ronda, en el mundo (el 0 es su lugar de siempre; da la vuelta al final).
func _lugar_de_ronda(numero: int) -> Vector3:
	numero = posmod(numero, ronda.size() + 1)
	if numero == 0:
		return _casa
	return _casa + Vector3(ronda[numero - 1].x, 0.0, ronda[numero - 1].y)


func _en_fila(delta: float) -> void:
	if _guia == null or not is_instance_valid(_guia):
		quedarse()
		return
	var g := _guia.global_position + _guia.global_transform.basis.x * al_costado
	# Si el guía se fue lejos (o apareció en otro lado), se olvida del camino andado y lo espera ahí.
	if _plano(global_position, g) > _espera_desde:
		_migas.clear()
		_largo_migas = 0.0
		_dejar_de_andar()
		return
	if _migas.is_empty():
		_migas.append(g)
	elif _plano(g, _migas[-1]) > 0.6:
		_largo_migas += _plano(g, _migas[-1])
		_migas.append(g)
	# Si yendo derecho a una miga de más adelante se ahorra mucho camino, el rastro da un rodeo (el guía
	# volvió sobre sus pasos): lo corta ahí, en vez de desandar la ida y la vuelta.
	var andado := _plano(global_position, _migas[0])
	var corte := 0
	for i in range(1, _migas.size()):
		andado += _plano(_migas[i - 1], _migas[i])
		if andado > _plano(global_position, _migas[i]) * 1.3 + 1.5:
			corte = i
	for i in corte:
		_largo_migas -= _plano(_migas[0], _migas[1])
		_migas.pop_front()
	# Y si el guía quedó más cerca que la próxima miga (viene de vuelta hacia acá), va derecho a él.
	if _plano(global_position, g) < _plano(global_position, _migas[0]):
		_migas.clear()
		_migas.append(g)
		_largo_migas = 0.0
	var falta := _plano(global_position, _migas[0]) + _largo_migas + _plano(_migas[-1], g)
	# Parado, no arranca hasta que el guía se aleje un poco más: con el guía moviéndose apenas,
	# arrancaba y paraba en cada cuadro.
	if falta <= _separacion + (0.3 if _andando == "" else 0.0):
		_dejar_de_andar()
		return
	var tope := _paso_fila if _paso_fila > 0.0 else float(marchas.values()[0])
	# Si se atrasa, apura hasta un quinto más, de a poco (de golpe, los caballos cambiaban de paso sin parar).
	var velocidad := clampf((falta - _separacion) * 1.2 + 0.25, 0.25, tope * clampf(1.0 + (falta - _separacion - 4.0) * 0.1, 1.0, 1.2))
	if _paso_hacia(_migas[0], velocidad, delta) and _migas.size() > 1:
		_largo_migas -= _plano(_migas[0], _migas[1])
		_migas.pop_front()


## Con Zenón cerca, o mientras le habla, deja de caminar y lo mira. Verdadero si lo está atendiendo.
func _atender(delta: float) -> bool:
	if _jugador == null or not is_instance_valid(_jugador):
		_jugador = get_tree().current_scene.get_node_or_null("Player") as Node3D if get_tree().current_scene != null else null
		if _jugador == null:
			return false
	if _hablando and not Historia.ocupado:
		_hablando = false
	var hacia := _jugador.global_position - global_position
	hacia.y = 0.0
	_atendiendo = _hablando or hacia.length() < parar_cerca + (1.0 if _atendiendo else 0.0)
	if not _atendiendo:
		return false
	_dejar_de_andar()
	if hacia.length() > 0.3:
		global_rotation.y = rotate_toward(global_rotation.y, atan2(hacia.x, hacia.z), 3.0 * delta)
	return true


## Da un paso hacia un punto a esa velocidad, girando el cuerpo hacia donde va, pegado al suelo.
## Devuelve verdadero cuando llegó.
func _paso_hacia(meta: Vector3, velocidad: float, delta: float) -> bool:
	var falta := Vector2(meta.x - global_position.x, meta.z - global_position.z)
	var dist := falta.length()
	if dist < 0.12:
		return true
	var rumbo := atan2(falta.x, falta.y)
	var giro := rotate_toward(global_rotation.y, rumbo, 3.5 * delta)
	# Los de cuatro patas se inclinan con la cuesta, igual que Ceniza montada; la gente va derecha.
	var cabeceo := 0.0
	if marchas.has("trot"):
		var frente := Vector2(sin(giro), cos(giro))
		var sube := Historia.altura_suelo(global_position.x + frente.x * 0.7, global_position.z + frente.y * 0.7) - Historia.altura_suelo(global_position.x - frente.x * 0.6, global_position.z - frente.y * 0.6)
		cabeceo = lerp_angle(global_rotation.x, -clampf(atan2(sube, 1.3), -0.4, 0.4), clampf(6.0 * delta, 0.0, 1.0))
	global_rotation = Vector3(cabeceo, giro, 0.0)
	# Primero se da vuelta; recién cuando mira más o menos hacia donde va, avanza.
	var de_frente := cos(angle_difference(giro, rumbo))
	if de_frente < 0.5:
		pisar(0.4)
		return false
	if is_nan(_alto):
		_alto = clampf(global_position.y - Historia.altura_suelo(global_position.x, global_position.z), -0.5, 1.0)
	var paso := minf(velocidad * de_frente * delta, dist)
	var x := global_position.x + falta.x / dist * paso
	var z := global_position.z + falta.y / dist * paso
	global_position = Vector3(x, Historia.altura_suelo(x, z) + _alto, z)
	pisar(velocidad * de_frente)
	return paso >= dist - 0.01


func _plano(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Le presta a este personaje un clip de Zenón (tienen el mismo esqueleto de Mixamo): copia el clip,
## lo apunta a su esqueleto y ajusta la altura de la cadera a su cuerpo. Falso si no se puede.
func _prestar(nombre: String) -> bool:
	var esqueleto := find_child("Skeleton3D", true, false) as Skeleton3D
	if esqueleto == null or esqueleto.find_bone("mixamorig_Hips") < 0:
		return false
	if not _de_zenon.has(nombre):
		_de_zenon[nombre] = null
		var escena := load(ZENON_GLB) as PackedScene
		if escena != null:
			var zenon := escena.instantiate()
			var su_anim := zenon.find_child("AnimationPlayer", true, false) as AnimationPlayer
			var su_esqueleto := zenon.find_child("Skeleton3D", true, false) as Skeleton3D
			if su_anim != null and su_anim.has_animation(nombre) and su_esqueleto != null:
				_de_zenon[nombre] = su_anim.get_animation(nombre)
				_cadera_zenon = su_esqueleto.get_bone_rest(su_esqueleto.find_bone("mixamorig_Hips")).origin.length()
			zenon.free()
	var original := _de_zenon[nombre] as Animation
	if original == null or _cadera_zenon <= 0.0:
		return false
	var copia := original.duplicate() as Animation
	var raiz := _anim.get_node(_anim.root_node)
	var ruta := str(raiz.get_path_to(esqueleto))
	var talla := esqueleto.get_bone_rest(esqueleto.find_bone("mixamorig_Hips")).origin.length() / _cadera_zenon
	for i in range(copia.get_track_count() - 1, -1, -1):
		var hueso := String(copia.track_get_path(i).get_concatenated_subnames())
		if esqueleto.find_bone(hueso) < 0:
			copia.remove_track(i)
			continue
		copia.track_set_path(i, NodePath(ruta + ":" + hueso))
		if copia.track_get_type(i) == Animation.TYPE_POSITION_3D:
			if hueso != "mixamorig_Hips":
				copia.remove_track(i)  # el largo de cada hueso es el de este cuerpo, no el de Zenón
				continue
			for k in copia.track_get_key_count(i):
				copia.track_set_key_value(i, k, (copia.track_get_key_value(i, k) as Vector3) * talla)
	copia.loop_mode = Animation.LOOP_LINEAR
	var biblioteca := _anim.get_animation_library("")
	if biblioteca == null or biblioteca.has_animation(nombre):
		return biblioteca != null
	biblioteca.add_animation(nombre, copia)
	# El clip prestado pisa a la velocidad de Zenón, ajustada al largo de pierna de este cuerpo.
	if marchas.has(nombre):
		marchas[nombre] = float(marchas[nombre]) * talla
	return true


# ------------------------------------------------------------------ montura y jinete

## Solo caballos. Los puntos del recado, atados al lomo para que suban y bajen con el andar:
## {"asiento", "estribo_izq", "estribo_der", "manos"} (Node3D). Se arman la primera vez que se piden.
func montura() -> Dictionary:
	if not _montura.is_empty():
		return _montura
	var esqueleto := find_child("Skeleton3D", true, false) as Skeleton3D
	if esqueleto == null or esqueleto.find_bone("cuerpo") < 0:
		return {}
	var lomo := BoneAttachment3D.new()
	lomo.name = "Lomo"
	lomo.bone_name = "cuerpo"
	esqueleto.add_child(lomo)
	# Los puntos se dan en el espacio del caballo (este nodo) y se pasan al del hueso en reposo.
	var a_hueso := (esqueleto.global_transform * esqueleto.get_bone_global_rest(esqueleto.find_bone("cuerpo"))).affine_inverse() * global_transform
	var puntos := {"asiento": asiento, "estribo_izq": estribo, "estribo_der": estribo * Vector3(-1.0, 1.0, 1.0),
		"manos": manos}
	for nombre: String in puntos:
		var punto := Node3D.new()
		punto.name = nombre.capitalize().replace(" ", "")
		lomo.add_child(punto)
		punto.transform = a_hueso * Transform3D(Basis.IDENTITY, puntos[nombre])
		_montura[nombre] = punto
	return _montura


## Sienta a este personaje en un caballo (otro nodo con este mismo script). Con null, se baja.
## Si tenía donde sentarse (un hijo llamado "Asiento": el tronco de la anciana), eso no viaja con él.
func sentarse_en(caballo: Node3D) -> void:
	_caballo = caballo
	var banco := get_node_or_null("Asiento") as Node3D
	if banco != null:
		banco.visible = caballo == null
	if caballo == null:
		_modo = Modo.QUIETO
		if _porte != null:
			_porte.sentar({})
		return
	_armar_porte(true)
	if _porte == null or not caballo.has_method("montura"):
		return
	_dejar_de_andar()
	_porte.sentar(caballo.montura())
	_porte.montado = 1.0
	_modo = Modo.SENTADO

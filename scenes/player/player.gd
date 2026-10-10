extends CharacterBody3D

## Zenón silbó para llamar a Ceniza (lo escucha scripts/sonidos.gd, que hace sonar el silbido).
signal silbo

@export var walk_speed := 4.0
@export var run_speed := 8.0
@export var jump_velocity := 4.5

@export var mouse_sensitivity := 0.004
@export var min_pitch_deg := -70.0
@export var max_pitch_deg := 55.0

@export var zoom_min := 1.8
@export var zoom_max := 7.0
@export var zoom_speed := 0.4

## Cámara sobre el hombro derecho: corrimiento lateral y altura sobre el pivote.
@export var hombro := 0.6
@export var altura_camara := 0.4
@export var suavizado_camara := 10.0

## El porte de Zenón: un gaucho cansado, con el peso en los hombros (ver scripts/porte.gd).
## Se suma por encima de los clips de Mixamo; con todo en cero queda como venía de Mixamo.
@export_group("Porte")
## Espalda encorvada, en grados.
@export_range(-10.0, 25.0, 0.5) var porte_encorvar := 7.0
## Cabeza gacha, en grados.
@export_range(-10.0, 20.0, 0.5) var porte_cabeza := 4.0
## Hombros caídos, en grados.
@export_range(-10.0, 15.0, 0.5) var porte_hombros := 5.0
## Cuando está quieto, cada tanto mira hacia un lado: cuántos grados gira la cabeza.
@export_range(0.0, 45.0, 1.0) var porte_mirar := 24.0
## Vaivén lento del tronco cuando está quieto, en grados.
@export_range(0.0, 5.0, 0.1) var porte_mecer := 1.6
## Cuánto se abren los brazos hacia afuera, en grados, para que las manos no se metan en las caderas.
@export_range(0.0, 20.0, 0.5) var porte_abrir_brazos := 5.0
## Largo de los dedos: 1 es como viene el modelo (muy largos); 0.6 los acorta al 60 %.
@export_range(0.4, 1.0, 0.01) var porte_dedos := 0.6
## El cuerpo sigue a la cámara con un instante de atraso en vez de girar clavado a ella (0: clavado).
@export_range(0.0, 1.0, 0.05) var soltura_giro := 0.6
## Con la S, Zenón se da vuelta y camina hacia la cámara. Apagado, camina para atrás sin darse
## vuelta, como antes.
@export var darse_vuelta_al_volver := true

## Ceniza (tanda 6). Montado es un estado de este mismo cuerpo: Zenón va sentado en el recado y el
## caballo anda con inercia, dobla más abierto cuanto más rápido va y no camina de costado.
## Teclas: E la monta (arrimado a ella), Q se baja; a pie, Q la silba y viene. Montado, W anda,
## Shift sube de marcha (paso, trote, galope) y S la baja o frena.
@export_group("Caballo")
## Velocidad de cada marcha, en metros por segundo.
@export var paso_caballo := 1.8
@export var trote_caballo := 5.8
@export var galope_caballo := 12.5
## Inercia: cuántos metros por segundo gana cada segundo al arrancar...
@export var aceleracion_caballo := 3.0
## ...cuántos pierde al soltar la W...
@export var freno_caballo := 3.5
## ...y cuántos pierde al sofrenar con la S.
@export var sofrenada_caballo := 8.0
## Cuántos grados por segundo dobla al paso y al galope (entre los dos, lo que corresponda).
@export var giro_al_paso := 110.0
@export var giro_al_galope := 38.0
## Montado, la cámara sube y se aleja estos metros.
@export var camara_sube_montado := 0.7
@export var camara_aleja_montado := 2.2
## Cuánto más abre la cámara al galope, en grados.
@export var camara_abre_al_galope := 9.0
## Hasta cuántos metros Ceniza viene andando cuando se la silba. De más lejos, o con algo en el
## medio, aparece fuera de cuadro a unos cuarenta metros y llega al trote.
@export var silbido_alcance := 150.0
## Cuántas pisadas de Ceniza quedan marcadas en el suelo detrás de ella (0: ninguna).
@export var huellas_de_cascos := 160
## Cuánto se sienta sobre los garrones al sofrenarla con la S, en grados.
@export var sentada_al_sofrenar := 5.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var yaw: float = 0.0
var pitch: float = deg_to_rad(-12.0)
var camera_distance := 3.8
var _distancia_actual := 3.8

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

@onready var ray_interact: RayCast3D = $CameraPivot/Camera3D/RayInteract

# Ajustá la ruta si tu UI está en otro lado
@onready var interact_label: Label = $UI/InteractLabel
@onready var cuerpo: Node3D = get_node_or_null("Cuerpo") as Node3D
@onready var _boleadoras: Node3D = get_node_or_null("Cuerpo/BoleadorasAlCinto") as Node3D

var current_interactable: Interactable = null

# El recado y la seña viven en la historia (scripts/Historia.gd), para que se guarden con la partida.
# Recado: 0 ninguno, 1 llevando, 2 entregado.
# Exploración del fortín: 0 ninguna, 1 yendo al mojón, 2 mojón visto, 3 hecha.
var estado_recado: int:
	get: return Historia.v("recado")
	set(valor): Historia.poner("recado", valor)
var estado_exploracion: int:
	get: return Historia.v("sena")
	set(valor): Historia.poner("sena", valor)
var _periodo := "Día"
var _aviso: Label
var _aviso_tiempo := 0.0

# Clips de Mixamo, animados en el lugar: el avance lo da el CharacterBody3D.
# Velocidad natural de cada clip en m/s, para que los pies no patinen.
const CLIPS_EN_LOOP := ["idle", "walk", "run", "strafe_left", "strafe_left_walk", "strafe_right", "strafe_right_walk"]
const PASO_CLIP := {"walk": 1.55, "run": 4.0, "strafe_left_walk": 1.6, "strafe_right_walk": 1.6, "strafe_left": 4.1, "strafe_right": 4.1}
var _anim: AnimationPlayer
var _saltando := false
var _porte: Porte
var _polvo: GPUParticles3D
var _fov_base := 60.0
var _yaw_anterior := 0.0
var _atraso_giro := 0.0
# Cuánto está girado el cuerpo respecto de la cámara (0: mira hacia donde mira la cámara;
# media vuelta: mira hacia la cámara).
var _vuelta := 0.0

var montado := false
var _ceniza: Node3D
# 1 paso, 2 trote, 3 galope.
var _marcha := 1
var _rapidez := 0.0
# Hacia dónde mira el caballo (la cámara gira aparte, con el mouse).
var _rumbo := 0.0
# 0 a pie, 1 sentado en el recado; en el medio, subiendo o bajando.
var _subiendo := 0.0
var _cuerpo_de := Transform3D()
var _cabeceo := 0.0
var _shift_tiempo := 0.0
var _parado := 0.0
var _quiere_bajar := false
var _choque_montado: Array[CollisionShape3D] = []
var _pivote_alto := 0.6
var _huellas: MultiMesh
var _huella_n := 0
var _huella_falta := 0.0
var _sofrenando := 0.0
## La intro (scripts/Intro.gd) maneja a Zenón como a un títere: lo pone donde va cada plano con
## titere_poner() y lo deja montar aunque haya algo en pantalla. Con titere_anda, montado, anda al
## paso hacia donde apunta `yaw` sin que nadie toque una tecla.
var titere := false
var titere_anda := false
# A cuánto queda el centro de este cuerpo del suelo que pisa (media cápsula más el margen del choque).
const ALTO_DEL_CUERPO := 1.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	ray_interact.enabled = true
	ray_interact.add_exception(self)
	_armar_animaciones()
	interact_label.text = ""
	interact_label.offset_left = -460.0
	interact_label.offset_right = 460.0
	interact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# El snap largo empujaba el cuerpo cada vez que is_on_floor() parpadeaba.
	safe_margin = 0.08
	floor_snap_length = 0.05
	_armar_aviso()
	_armar_polvo()
	_armar_choque_montado()
	_armar_huellas()
	_fov_base = camera.fov
	_pivote_alto = camera_pivot.position.y
	call_deferred("_conectar_ciclo")
	call_deferred("_buscar_ceniza")
	# La historia suma la gente con la que se habla, acomoda el mundo y trae la partida guardada.
	Historia.entrar_al_mundo.call_deferred(self)


func _unhandled_input(event: InputEvent) -> void:
	# Con un diálogo abierto, Zenón no mira ni interactúa: las teclas son del cuadro.
	if Historia.ocupado:
		return
	# Esc abre la pausa (scripts/Ajustes.gd), que suelta el mouse y lo devuelve al seguir.
	# Con el mouse suelto, un clic lo vuelve a capturar y no hace otra cosa.
	var clic: bool = event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	if clic and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return

	# mirar con el mouse
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Ajustes.mouse es el ajuste de sensibilidad del menú (1 es la de siempre).
		yaw -= event.relative.x * mouse_sensitivity * Ajustes.mouse
		pitch -= event.relative.y * mouse_sensitivity * Ajustes.mouse

		var min_pitch := deg_to_rad(min_pitch_deg)
		var max_pitch := deg_to_rad(max_pitch_deg)
		pitch = clamp(pitch, min_pitch, max_pitch)

	# zoom con la ruedita
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = max(zoom_min, camera_distance - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = min(zoom_max, camera_distance + zoom_speed)

	# Tab: recordar adónde hay que ir.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		Historia.recordar()

	# Q: montado, se baja; a pie, silba y Ceniza viene.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		if montado:
			desmontar()
		else:
			silbar()
	# Montado, Shift sube una marcha y la S la baja.
	if montado and event.is_action_pressed("run"):
		poner_marcha(_marcha + 1)
	elif montado and event.is_action_pressed("move_backward"):
		poner_marcha(_marcha - 1)

	# 🔹 Interactuar con E
	if event.is_action_pressed("interact") and current_interactable:
		_do_interact(current_interactable)


func _process(delta: float) -> void:
	_check_interaction()
	_update_hud()
	_tick_aviso(delta)

	# A pie el cuerpo mira hacia donde mira la cámara. Montado mira hacia donde va el caballo,
	# y la cámara gira aparte, alrededor.
	rotation.y = _rumbo if montado else yaw
	camera_pivot.rotation.y = wrapf(yaw - _rumbo, -PI, PI) if montado else 0.0
	camera_pivot.rotation.x = pitch
	_acomodar_camara(delta)
	# En el final en que salda la cuenta, las boleadoras quedaron en lo de Ceferino, salvo que la
	# cuenta estuviera baja y Ceferino se las haya dejado (bandera "boleadoras_quedan").
	if _boleadoras != null:
		_boleadoras.visible = Historia.final_elegido != "solitario" or Historia.flags.has("boleadoras_quedan")
	if montado or _subiendo > 0.0:
		_acomodar_jinete(delta)
	else:
		_soltar_giro(delta)
		_avisar_que_se_silba()
	# Al correr, el polvo se levanta de las botas y la cámara abre apenas el campo de visión.
	# "Corriendo" es ir más rápido que a mitad de camino entre el paso y la corrida, valgan lo que valgan.
	var corriendo := absf(velocity.y) < 2.5 and Vector2(velocity.x, velocity.z).length() > (walk_speed + run_speed) * 0.5
	var abre := 4.0 if corriendo else 0.0
	if montado:
		# A caballo, el polvo sale al trote y al galope, y la cámara abre más cuanto más rápido va.
		corriendo = _rapidez > trote_caballo * 0.7
		abre = camara_abre_al_galope * clampf((_rapidez - paso_caballo) / maxf(galope_caballo - paso_caballo, 0.1), 0.0, 1.0)
	if _polvo != null:
		_polvo.emitting = corriendo
		_polvo.amount_ratio = clampf(_rapidez / maxf(galope_caballo, 0.1), 0.45, 1.0) if montado else 0.45
	camera.fov = lerpf(camera.fov, _fov_base + abre, clampf(3.0 * delta, 0.0, 1.0))


func _check_interaction() -> void:
	current_interactable = null

	# La gente y el fogón no hace falta apuntarles: alcanza con tenerlos cerca y adelante.
	current_interactable = Historia.persona_cerca(self)
	if current_interactable != null:
		return

	if not ray_interact.is_colliding():
		return

	current_interactable = _buscar_interactable(ray_interact.get_collider())
	# A la gente y al fogón se les habla de cerca: eso lo decide Historia.persona_cerca con su alcance.
	if current_interactable != null and current_interactable.rol in [Interactable.Rol.PERSONA, Interactable.Rol.FOGON, Interactable.Rol.CHANGA]:
		current_interactable = null


func _update_hud() -> void:
	if not interact_label:
		return

	if _aviso != null:
		_aviso.visible = not Historia.ocupado
	if Historia.ocupado:
		interact_label.text = ""
	elif current_interactable and current_interactable.has_method("texto_mira"):
		interact_label.text = current_interactable.texto_mira(self)
	elif current_interactable:
		interact_label.text = current_interactable.interact_text
	else:
		interact_label.text = ""



func _do_interact(obj: Interactable) -> void:
	var linea := ""
	if obj.has_method("al_interactuar"):
		linea = str(obj.al_interactuar(self))
	else:
		linea = "No hay nada que hacer acá."
	if linea == "":
		return  # Se abrió un diálogo: no hay cartel que mostrar.
	mostrar_aviso(linea)
	print(linea)


func _physics_process(delta: float) -> void:
	if montado:
		_mover_montado(delta)
		return

	# gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# movimiento relativo a hacia dónde mira el jugador
	var move_dir := Vector3.ZERO

	# Con un diálogo abierto, o mientras termina de bajarse del caballo, no se mueve.
	var libre := not Historia.ocupado and _subiendo <= 0.0
	if libre and Input.is_action_pressed("move_forward"):
		move_dir -= transform.basis.z
	if libre and Input.is_action_pressed("move_backward"):
		move_dir += transform.basis.z
	if libre and Input.is_action_pressed("move_left"):
		move_dir -= transform.basis.x
	if libre and Input.is_action_pressed("move_right"):
		move_dir += transform.basis.x

	move_dir.y = 0.0

	var target_speed := 0.0
	if move_dir != Vector3.ZERO:
		move_dir = move_dir.normalized()
		# caminar / correr
		if Input.is_action_pressed("run"):
			target_speed = run_speed
		else:
			target_speed = walk_speed

		velocity.x = move_dir.x * target_speed
		velocity.z = move_dir.z * target_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# salto
	if libre and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_empezar_salto()

	move_and_slide()
	_frenar_en_el_borde()
	_recuperar_suelo()
	_animar_gaucho(delta)


## Polvo de tierra a la altura de las botas. Se prende solo al correr. Usa el material del humo
## (bocanadas suaves que reciben la luz), teñido de tierra, y lo lleva el viento del oeste.
func _armar_polvo() -> void:
	var material := load("res://assets/materiales/humo.tres") as Material
	if material == null:
		return
	var proceso := ParticleProcessMaterial.new()
	proceso.direction = Vector3(0.0, 1.0, 0.0)
	proceso.spread = 55.0
	proceso.initial_velocity_min = 0.3
	proceso.initial_velocity_max = 0.9
	proceso.gravity = Vector3(0.5, 0.25, 0.1)
	proceso.scale_min = 0.5
	proceso.scale_max = 1.1
	proceso.angle_min = -180.0
	proceso.angle_max = 180.0
	var crece := Curve.new()
	crece.add_point(Vector2(0.0, 0.4))
	crece.add_point(Vector2(1.0, 1.0))
	var textura_crece := CurveTexture.new()
	textura_crece.curve = crece
	proceso.scale_curve = textura_crece
	var rampa := Gradient.new()
	rampa.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	rampa.colors = PackedColorArray([Color(0.8, 0.7, 0.55, 0.0), Color(0.8, 0.7, 0.55, 0.45), Color(0.8, 0.7, 0.55, 0.0)])
	var textura_rampa := GradientTexture1D.new()
	textura_rampa.gradient = rampa
	proceso.color_ramp = textura_rampa
	var bocanada := QuadMesh.new()
	bocanada.size = Vector2(1.0, 1.0)
	_polvo = GPUParticles3D.new()
	_polvo.name = "Polvo"
	_polvo.amount = 30
	_polvo.amount_ratio = 0.45
	_polvo.lifetime = 1.1
	_polvo.local_coords = false
	_polvo.emitting = false
	_polvo.process_material = proceso
	_polvo.draw_pass_1 = bocanada
	_polvo.material_override = material
	_polvo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_polvo.position = Vector3(0.0, -0.8, 0.2)
	add_child(_polvo)


## El cuerpo de Zenón gira con la cámara, pero con un instante de atraso, y al doblar caminando
## se inclina apenas hacia adentro de la curva. Solo mueve el modelo: el choque y la dirección
## en la que camina siguen clavados a la cámara, como antes.
func _soltar_giro(delta: float) -> void:
	if cuerpo == null:
		return
	var giro := wrapf(yaw - _yaw_anterior, -PI, PI)
	_yaw_anterior = yaw
	# Hacia dónde va, visto desde la cámara: -Z es alejarse de ella y +Z es venir hacia ella.
	var local := global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var peso_vuelta := clampf(8.0 * delta, 0.0, 1.0)
	if darse_vuelta_al_volver and local.z > 0.1:
		# Viene hacia la cámara: se da vuelta y mira hacia donde camina.
		_vuelta = lerp_angle(_vuelta, atan2(-local.x, -local.z), peso_vuelta)
	elif local.length() > 0.25 or absf(_vuelta) < 0.3:
		# Avanza, va de costado o ya está casi de espaldas a la cámara: vuelve a mirar hacia adelante.
		_vuelta = lerp_angle(_vuelta, 0.0, peso_vuelta)
	else:
		# Quieto y dado vuelta: se queda mirando hacia donde venía aunque la cámara gire a su
		# alrededor, hasta que la cámara vuelve a quedarle a la espalda.
		_vuelta -= giro
		giro = 0.0
	_vuelta = wrapf(_vuelta, -PI, PI)
	_atraso_giro = clampf(_atraso_giro - giro * soltura_giro, -0.8, 0.8)
	_atraso_giro = lerpf(_atraso_giro, 0.0, clampf(9.0 * delta, 0.0, 1.0))
	cuerpo.rotation.y = _atraso_giro + _vuelta
	var andando := local.length() > 1.0
	var ladeo := clampf(giro / maxf(delta, 0.001) * 0.02, -0.07, 0.07) if andando else 0.0
	cuerpo.rotation.z = lerpf(cuerpo.rotation.z, ladeo * soltura_giro, clampf(6.0 * delta, 0.0, 1.0))


func _acomodar_camara(delta: float) -> void:
	var peso := clampf(suavizado_camara * delta, 0.0, 1.0)
	# Montado, la cámara sube hasta la altura del jinete y se aleja.
	var arriba := smoothstep(0.0, 1.0, _subiendo)
	camera_pivot.position.y = _pivote_alto + camara_sube_montado * arriba
	_distancia_actual = lerpf(_distancia_actual, camera_distance + camara_aleja_montado * arriba, peso)
	var deseada := Vector3(hombro, altura_camara, _distancia_actual)
	var origen := camera_pivot.global_position
	var destino := camera_pivot.global_transform * deseada
	var consulta := PhysicsRayQueryParameters3D.create(origen, destino)
	consulta.exclude = [get_rid()]
	consulta.collide_with_areas = false
	var golpe := get_world_3d().direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		camera.position = deseada
	else:
		# Si hay terreno o una pared atrás, la cámara se arrima sin meterse adentro.
		var libre := clampf((origen.distance_to(golpe.position) - 0.3) / deseada.length(), 0.15, 1.0)
		camera.position = deseada * libre


func _frenar_en_el_borde() -> void:
	var terreno := get_parent().get_node_or_null("HTerrain")
	if terreno == null or not terreno.has_method("world_to_map") or not terreno.has_method("get_data"):
		return
	var datos = terreno.get_data()
	if datos == null:
		return
	var res: float = float(datos.get_resolution() - 1)
	var escala: Vector3 = terreno.map_scale
	# La niebla cierra hacia los 420 m. El freno queda un poco más lejos
	# para que el corte del mapa siga tapado cuando el mapa es de unos pocos km.
	var margen: float = 480.0 / maxf(escala.x, 0.001)
	margen = clampf(margen, 0.05, res * 0.25)
	var mapa: Vector3 = terreno.world_to_map(global_position)
	var x: float = clampf(mapa.x, margen, res - margen)
	var z: float = clampf(mapa.z, margen, res - margen)
	if is_equal_approx(x, mapa.x) and is_equal_approx(z, mapa.z):
		return
	var h: float = datos.get_interpolated_height_at(Vector3(x, 0.0, z))
	var mundo: Vector3 = terreno.get_internal_transform() * Vector3(x, h, z)
	global_position.x = mundo.x
	global_position.z = mundo.z
	velocity.x = 0.0
	velocity.z = 0.0


func _recuperar_suelo() -> void:
	if is_on_floor():
		return
	var forma := $CollisionShape3D.shape as CapsuleShape3D
	var media := forma.height * 0.5 if forma != null else 1.0
	var desde := global_position + Vector3(0.0, 40.0, 0.0)
	var hasta := global_position + Vector3(0.0, -120.0, 0.0)
	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	consulta.exclude = [get_rid()]
	consulta.collide_with_areas = false
	var golpe := get_world_3d().direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		return
	var piso: float = golpe.position.y + media
	# Solo si atravesó el suelo varios metros. Un parpadeo al caminar no cuenta.
	if global_position.y < piso - 3.0:
		global_position.y = piso
		if velocity.y < 0.0:
			velocity.y = 0.0


func _buscar_interactable(nodo: Node) -> Interactable:
	if nodo == null:
		return null
	if nodo is Interactable:
		return nodo
	for hijo in nodo.get_children():
		if hijo is Interactable:
			return hijo
	var padre := nodo.get_parent()
	var pasos := 0
	while padre != null and pasos < 4:
		if padre is Interactable:
			return padre
		for hijo in padre.get_children():
			if hijo is Interactable:
				return hijo
		padre = padre.get_parent()
		pasos += 1
	return null


func _conectar_ciclo() -> void:
	var mundo := get_tree().current_scene
	if mundo == null:
		return
	var ciclo := mundo.get_node_or_null("SistemaDiaNoche")
	if ciclo == null or not ciclo.has_signal("cambio_periodo"):
		return
	if not ciclo.cambio_periodo.is_connected(_al_cambiar_periodo):
		ciclo.cambio_periodo.connect(_al_cambiar_periodo)
	if ciclo.has_method("obtener_periodo_dia"):
		_periodo = str(ciclo.obtener_periodo_dia())


func _al_cambiar_periodo(nuevo_periodo: String) -> void:
	_periodo = nuevo_periodo
	if estado_recado == 1 and nuevo_periodo == "Atardecer":
		mostrar_aviso("El sol baja sobre la estepa. Todavía hay luz para llegar al hito.")
	elif estado_recado == 1 and (nuevo_periodo == "Noche" or nuevo_periodo == "Crepúsculo"):
		mostrar_aviso("Se hizo de noche. Seguí el humo del palo: es la única seña del recado.")
	elif estado_exploracion == 1 and nuevo_periodo == "Atardecer":
		mostrar_aviso("Atardece. El mojón del cerro se recorta mejor contra el cielo.")


func periodo_del_dia() -> String:
	return _periodo


func tomar_recado() -> String:
	if estado_recado == 2:
		return "Ese recado ya llegó al palo. El puestero no tiene otro por ahora."
	if estado_recado == 1:
		return "Ya llevás el recado. El hito queda al noreste, donde sale el humo."
	estado_recado = 1
	if _periodo == "Noche" or _periodo == "Crepúsculo":
		return "El puestero te da el recado a oscuras. Andá al noreste y no pierdas el humo del palo."
	if _periodo == "Atardecer":
		return "Tomás el recado con el sol bajo. El palo del hito queda al noreste, donde sale el humo."
	return "El puestero te alcanza el recado. Llevalo al palo del hito, al noreste, donde se ve el humo."


func entregar_recado() -> String:
	if estado_recado == 0:
		return "El palo está vacío. Primero tenés que tomar el recado en la posta."
	if estado_recado == 2:
		return "El recado ya quedó atado al palo."
	estado_recado = 2
	if _periodo == "Atardecer":
		return "Dejás el recado con la última luz. Volvé a lo de Don Ceferino."
	if _periodo == "Noche" or _periodo == "Crepúsculo":
		return "Atás el recado al palo de noche. El humo te trajo derecho. Volvé a lo de Don Ceferino."
	return "Dejás el recado en el palo. Volvé a lo de Don Ceferino."


func hablar_en_el_fortin() -> String:
	if estado_exploracion == 0:
		estado_exploracion = 1
		if _periodo == "Noche" or _periodo == "Crepúsculo":
			return "El centinela te manda de noche: andá al mojón del cerro, al sudoeste, y volvé a contar la seña."
		return "El centinela te pide una seña. Andá al mojón del cerro, al sudoeste, y volvé al fortín."
	if estado_exploracion == 1:
		return "Todavía no marcaste el mojón. Queda al sudoeste, un viaje corto desde el fortín."
	if estado_exploracion == 2:
		estado_exploracion = 3
		if _periodo == "Atardecer":
			return "Volvés al fortín con el sol bajo. El centinela anota la seña y te dice que al atardecer el cerro se lee mejor."
		return "Le contás la seña al centinela. El fortín queda anotado: la vuelta del cerro está hecha."
	return "El centinela ya tiene tu seña. Por ahora no hay otra salida."


func marcar_mojon() -> String:
	if estado_exploracion == 0:
		return "Es el mojón del cerro. Sin la orden del fortín no hay nada que marcar."
	if estado_exploracion == 1:
		estado_exploracion = 2
		if _periodo == "Atardecer":
			return "Marcás el mojón con el sol en el horizonte. Volvé al fortín antes de que se apague la luz."
		return "Marcás el mojón del cerro. Ahora volvé al fortín a contarlo."
	return "El mojón ya está marcado. El fortín espera la vuelta."


func mostrar_aviso(linea: String) -> void:
	if _aviso == null:
		_armar_aviso()
	if _aviso == null:
		return
	_aviso.text = linea
	_aviso_tiempo = maxf(9.0, linea.length() * 0.1)


func _armar_aviso() -> void:
	var capa := get_node_or_null("UI") as CanvasLayer
	if capa == null:
		return
	_aviso = capa.get_node_or_null("AvisoLabel") as Label
	if _aviso == null:
		_aviso = Label.new()
		_aviso.name = "AvisoLabel"
		capa.add_child(_aviso)
	_aviso.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# Un aviso de varios renglones (el de Tab con conchabos a medias) crece hacia arriba, no fuera de la pantalla.
	_aviso.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_aviso.offset_left = -460.0
	_aviso.offset_right = 460.0
	_aviso.offset_top = -150.0
	_aviso.offset_bottom = -70.0
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aviso.add_theme_font_size_override("font_size", 26)
	_aviso.add_theme_color_override("font_color", Color(0.98, 0.93, 0.78))
	_aviso.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_aviso.add_theme_constant_override("shadow_offset_x", 2)
	_aviso.add_theme_constant_override("shadow_offset_y", 2)
	_aviso.text = ""


func _tick_aviso(delta: float) -> void:
	if _aviso == null or _aviso.text == "":
		return
	_aviso_tiempo -= delta
	if _aviso_tiempo <= 0.0:
		_aviso.text = ""


func _armar_animaciones() -> void:
	if cuerpo == null:
		return
	_anim = cuerpo.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		return
	for nombre: String in CLIPS_EN_LOOP:
		if _anim.has_animation(nombre):
			_anim.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR
	_anim.play("idle")
	var esqueleto := cuerpo.find_child("Skeleton3D", true, false) as Skeleton3D
	if esqueleto != null:
		_porte = Porte.new()
		_porte.name = "Porte"
		_porte.encorvar = porte_encorvar
		_porte.cabeza = porte_cabeza
		_porte.hombros = porte_hombros
		_porte.abrir_brazos = porte_abrir_brazos
		_porte.dedos = porte_dedos
		_porte.mirar_cada = 6.0
		esqueleto.add_child(_porte)


func _empezar_salto() -> void:
	if _anim == null or not _anim.has_animation("jump"):
		return
	_saltando = true
	# El clip de Mixamo arranca agachándose; el cuerpo ya está en el aire, así que se saltea el envión.
	_anim.play("jump", 0.1, 1.4)
	_anim.seek(0.55, true)


func _animar_gaucho(_delta: float) -> void:
	if _anim == null:
		return
	if not is_on_floor():
		return
	if _saltando and _anim.current_animation == "jump" and _anim.current_animation_position < 1.1:
		return
	_saltando = false

	# Velocidad vista desde el gaucho: -Z es adelante, +X es a su derecha.
	var local := global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var rapidez := local.length()
	if _porte != null:
		# Quieto, mira alrededor y se mece; andando, mira al frente y al correr se echa un poco adelante.
		_porte.mirar = porte_mirar if rapidez < 0.25 else 0.0
		_porte.mecer = lerpf(_porte.mecer, porte_mecer if rapidez < 0.25 else 0.0, 0.08)
		_porte.encorvar = lerpf(_porte.encorvar, porte_encorvar + (5.0 if rapidez > 2.5 else 0.0), 0.1)
	if rapidez < 0.25:
		_poner_clip("idle", 1.0)
		return

	var clip := ""
	var sentido := 1.0
	if darse_vuelta_al_volver and local.z > 0.1:
		# Viene hacia la cámara: el cuerpo se da vuelta (_soltar_giro), así que camina de frente.
		clip = "walk" if rapidez < 2.5 else "run"
	elif absf(local.z) >= absf(local.x):
		clip = "walk" if rapidez < 2.5 else "run"
		if local.z > 0.0:
			sentido = -1.0
	else:
		var lado := "strafe_right" if local.x > 0.0 else "strafe_left"
		clip = lado + "_walk" if rapidez < 2.5 else lado
	var escala := clampf(rapidez / float(PASO_CLIP.get(clip, rapidez)), 0.6, 2.0)
	_poner_clip(clip, escala * sentido)


func _poner_clip(nombre: String, escala: float) -> void:
	if not _anim.has_animation(nombre):
		return
	# Con el mismo clip, play() no lo reinicia: solo actualiza la velocidad.
	_anim.play(nombre, 0.3, escala)


# ------------------------------------------------------------------ Ceniza

func _buscar_ceniza() -> void:
	_ceniza = get_parent().get_node_or_null("Ceniza") as Node3D
	if _ceniza != null and not _ceniza.has_method("montura"):
		_ceniza = null


## Las formas de choque de cuando va montado: el pecho y el anca de Ceniza y el torso del jinete.
## La cápsula de siempre sigue siendo la que pisa el suelo. Así Ceniza no entra por una puerta
## ni mete la cabeza en una pared.
func _armar_choque_montado() -> void:
	# El pecho y el anca son más anchos que la puerta de la pulpería (1,1 m) a propósito, y van altos
	# para no rozar el suelo al trepar una loma.
	for dato: Array in [["ChoquePecho", Vector3(0.0, 0.0, -0.95), 0.62], ["ChoqueAnca", Vector3(0.0, 0.0, 0.7), 0.62],
			["ChoqueJinete", Vector3(0.0, 1.15, -0.1), 0.42]]:
		var forma := CollisionShape3D.new()
		forma.name = dato[0]
		var bola := SphereShape3D.new()
		bola.radius = dato[2]
		forma.shape = bola
		forma.position = dato[1]
		forma.disabled = true
		add_child(forma)
		_choque_montado.append(forma)


## Sube a Ceniza. `de_una` es para cuando se carga una partida: aparece ya montado.
func montar(de_una := false) -> void:
	if montado or _ceniza == null or (not de_una and ((Historia.ocupado and not titere) or _subiendo > 0.0)):
		return
	_cuerpo_de = cuerpo.global_transform if cuerpo != null else global_transform
	_ceniza.llevar(true)
	_prender_choque_de_ceniza(false)
	# Este cuerpo pasa a ser el del caballo: se pone donde está ella, mirando hacia donde mira.
	_rumbo = _ceniza.global_rotation.y + PI
	# Y con la inclinación que ella trae (si vino sola al silbido, la de la cuesta que pisa).
	_cabeceo = -_ceniza.global_rotation.x
	global_position = Vector3(_ceniza.global_position.x, _ceniza.global_position.y + ALTO_DEL_CUERPO, _ceniza.global_position.z)
	velocity = Vector3.ZERO
	_rapidez = 0.0
	_marcha = 1
	_quiere_bajar = false
	montado = true
	for forma in _choque_montado:
		forma.set_deferred("disabled", false)
	if _porte != null:
		_porte.sentar(_ceniza.montura())
	_subiendo = 1.0 if de_una else 0.001
	if not titere and not Historia.flags.has("_pista_montar"):
		Historia.flags["_pista_montar"] = true
		mostrar_aviso("W: andar al paso. Shift: más ligero (trote, galope). S: sofrenar. Q: bajarse.")


## Se baja de Ceniza, que queda donde está. Si viene andando, primero la sofrena.
func desmontar() -> void:
	if not montado or _subiendo < 1.0 or Historia.ocupado:
		return
	if _rapidez > 0.4:
		_quiere_bajar = true
		return
	_quiere_bajar = false
	montado = false
	for forma in _choque_montado:
		forma.set_deferred("disabled", true)
	_ceniza.llevar(false)
	_cuerpo_de = cuerpo.global_transform if cuerpo != null else global_transform
	# Se baja por el lado de montar (el izquierdo); si está tapado, por el otro, o hacia atrás.
	var lugar := global_position
	for corrida: Vector3 in [Vector3(-1.2, 0.0, 0.0), Vector3(1.2, 0.0, 0.0), Vector3(-1.1, 0.0, 1.7), Vector3(1.1, 0.0, 1.7)]:
		var candidato: Vector3 = global_position + global_transform.basis * corrida
		candidato.y = Historia.altura_suelo(candidato.x, candidato.z) + ALTO_DEL_CUERPO
		if _lugar_libre(candidato):
			lugar = candidato
			break
	global_position = lugar
	velocity = Vector3.ZERO
	_rapidez = 0.0
	_prender_choque_de_ceniza(true)
	if not Historia.flags.has("_pista_silbar"):
		Historia.flags["_pista_silbar"] = true
		mostrar_aviso("Ceniza queda donde la dejás. De lejos, con la Q la silbás y viene.")


## A pie, llama a Ceniza: viene derecho hasta Zenón y se para a un par de metros.
func silbar() -> void:
	if montado or _ceniza == null or Historia.ocupado or _subiendo > 0.0:
		return
	var lejos := Vector2(_ceniza.global_position.x - global_position.x, _ceniza.global_position.z - global_position.z).length()
	if lejos < 4.5:
		mostrar_aviso("Ceniza está acá nomás.")
		return
	if lejos > silbido_alcance or not _camino_libre(_ceniza.global_position):
		# Lejos, o con algo en el medio: aparece fuera de cuadro (detrás de la cámara) y llega al trote.
		var puesta := false
		for radio: float in [40.0, 18.0]:
			for corrimiento: float in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9, PI]:
				var desde := global_position + Vector3(sin(yaw + corrimiento), 0.0, cos(yaw + corrimiento)) * radio
				desde.y = Historia.altura_suelo(desde.x, desde.z)
				if not puesta and desde.y > -1.5 and _camino_libre(desde):
					_ceniza.global_position = desde
					puesta = true
		if not puesta:
			# Zenón está encerrado (adentro del fortín, de un corral): Ceniza no atraviesa cercos.
			silbo.emit()
			mostrar_aviso("Silbás, pero Ceniza no tiene por dónde llegar. Salí a campo abierto y volvé a silbar.")
			return
	silbo.emit()
	_ceniza.venir(self, 2.6)
	mostrar_aviso("Silbás. Ceniza levanta la cabeza y viene.")


func poner_marcha(marcha: int) -> void:
	_marcha = clampi(marcha, 1, 3)
	_parado = 0.0


## Para guardar la partida: dónde quedó Ceniza y si Zenón va montado.
func estado_del_caballo() -> Dictionary:
	if _ceniza == null:
		return {}
	var p := _ceniza.global_position
	return {"ceniza": [p.x, p.y, p.z, _ceniza.global_rotation.y], "montado": montado}


func poner_caballo(partida: Dictionary) -> void:
	if _ceniza == null:
		_buscar_ceniza()
	var c: Array = partida.get("ceniza", [])
	if _ceniza == null or c.size() != 4:
		return
	_ceniza.global_position = Vector3(c[0], c[1], c[2])
	_ceniza.global_rotation = Vector3(0.0, c[3], 0.0)
	if partida.get("montado", false) == true:
		montar(true)


## Para la intro: pone a Zenón en ese lugar en el acto, mirando hacia `rumbo`, a pie o ya montado (con
## Ceniza debajo). No sofrena, no busca dónde bajarse ni muestra pistas. La altura la pone el suelo.
func titere_poner(lugar: Vector3, rumbo: float, a_caballo: bool) -> void:
	titere = true
	titere_anda = false
	if montado:
		montado = false
		for forma in _choque_montado:
			forma.set_deferred("disabled", true)
		_ceniza.llevar(false)
		_prender_choque_de_ceniza(true)
	_subiendo = 0.0
	_quiere_bajar = false
	if cuerpo != null:
		cuerpo.transform = Transform3D.IDENTITY
	if _porte != null:
		_porte.sentar({})
		_porte.inclinar = 0.0
	yaw = rumbo
	_yaw_anterior = rumbo
	_vuelta = 0.0
	_atraso_giro = 0.0
	velocity = Vector3.ZERO
	_rapidez = 0.0
	# Las pisadas de Ceniza que dejó el plano anterior se borran: son de la intro, no del mundo.
	_huella_n = 0
	if _huellas != null:
		_huellas.visible_instance_count = 0
	var suelo := Historia.altura_suelo(lugar.x, lugar.z)
	if a_caballo and _ceniza != null:
		_ceniza.global_transform = Transform3D(Basis(Vector3.UP, rumbo + PI), Vector3(lugar.x, suelo, lugar.z))
		montar(true)
	else:
		global_position = Vector3(lugar.x, suelo + ALTO_DEL_CUERPO, lugar.z)


## El andar montado: la marcha elegida da la velocidad a la que quiere ir, y llega de a poco.
## Va hacia donde mira la cámara (A y D la corren hacia los costados), doblando a lo que le da
## el cuerpo a esa velocidad.
func _mover_montado(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var libre := not Historia.ocupado and _subiendo >= 1.0
	var avanza := (libre and Input.is_action_pressed("move_forward")) or (titere_anda and _subiendo >= 1.0)
	var costado := Input.get_axis("move_left", "move_right") if libre else 0.0
	var sofrena := (libre and Input.is_action_pressed("move_backward")) or _quiere_bajar
	# Con Shift apretado un rato sube otra marcha, sin tener que soltarlo.
	if libre and Input.is_action_pressed("run"):
		_shift_tiempo += delta
		if _shift_tiempo > 0.9:
			_shift_tiempo = 0.0
			poner_marcha(_marcha + 1)
	else:
		_shift_tiempo = 0.0
	var meta := 0.0
	if (avanza or costado != 0.0) and not sofrena:
		meta = [paso_caballo, trote_caballo, galope_caballo][_marcha - 1]
		var deseo := yaw - atan2(costado, 1.0 if avanza else 0.0)
		var giro := deg_to_rad(lerpf(giro_al_paso, giro_al_galope, clampf(_rapidez / maxf(galope_caballo, 0.1), 0.0, 1.0)))
		_rumbo = wrapf(rotate_toward(_rumbo, deseo, giro * delta), -PI, PI)
	var cambio := aceleracion_caballo if meta > _rapidez else (sofrenada_caballo if sofrena else freno_caballo)
	_rapidez = move_toward(_rapidez, meta, cambio * delta)
	# Sofrenada de golpe, se sienta un poco sobre los garrones.
	_sofrenando = lerpf(_sofrenando, 1.0 if sofrena and _rapidez > 1.5 else 0.0, clampf(7.0 * delta, 0.0, 1.0))
	if _rapidez < 0.2 and meta == 0.0:
		# Parada un rato, la próxima vez arranca al paso.
		_parado += delta
		if _parado > 2.0:
			_marcha = 1
		if _quiere_bajar:
			_rapidez = 0.0
			desmontar()
			return
	else:
		_parado = 0.0
	velocity.x = -sin(_rumbo) * _rapidez
	velocity.z = -cos(_rumbo) * _rapidez
	move_and_slide()
	# Si algo la frenó (una pared, un cerco), no sigue empujando a la velocidad de antes.
	_rapidez = minf(_rapidez, Vector2(velocity.x, velocity.z).length() + 0.3)
	_frenar_en_el_borde()
	_recuperar_suelo()
	if _anim != null:
		_poner_clip("idle", 1.0)
	if _porte != null:
		_porte.mirar = 0.0
		_porte.mecer = lerpf(_porte.mecer, 0.0, 0.08)
		_porte.encorvar = lerpf(_porte.encorvar, porte_encorvar, 0.1)
		# Al galope se echa sobre el recado.
		_porte.inclinar = lerpf(_porte.inclinar, 14.0 * clampf(_rapidez / maxf(galope_caballo, 0.1), 0.0, 1.0), 0.08)


## Pone a Ceniza debajo de este cuerpo y a Zenón en el recado. Subiendo o bajando, lo lleva del
## suelo al recado (o al revés) en algo más de medio segundo: no hay clip de montar.
func _acomodar_jinete(delta: float) -> void:
	if _ceniza == null or cuerpo == null:
		return
	_subiendo = move_toward(_subiendo, 1.0 if montado else 0.0, delta / 0.65)
	var s := smoothstep(0.0, 1.0, _subiendo)
	if _porte != null:
		_porte.montado = s
	if montado:
		# Las patas en el suelo, y el cuerpo acompañando la pendiente que pisa.
		var adelante := Vector3(-sin(_rumbo), 0.0, -cos(_rumbo))
		var p := global_position
		var sube := Historia.altura_suelo(p.x + adelante.x * 0.7, p.z + adelante.z * 0.7) - Historia.altura_suelo(p.x - adelante.x * 0.6, p.z - adelante.z * 0.6)
		_cabeceo = lerpf(_cabeceo, clampf(atan2(sube, 1.3), -0.4, 0.4) + deg_to_rad(sentada_al_sofrenar) * _sofrenando, clampf(6.0 * delta, 0.0, 1.0))
		# Los cascos, en el suelo de verdad (y si este cuerpo está en el aire, ella también).
		var cascos := maxf(Historia.altura_suelo(p.x, p.z), p.y - ALTO_DEL_CUERPO - 0.08)
		_ceniza.global_transform = Transform3D(Basis(Vector3.UP, _rumbo + PI) * Basis(Vector3.RIGHT, -_cabeceo), Vector3(p.x, cascos, p.z))
		_ceniza.pisar(_rapidez)
		_marcar_huellas(delta, cascos)
	var asiento := _ceniza.montura().get("asiento") as Node3D
	if asiento == null:
		return
	var base := _ceniza.global_transform.basis.orthonormalized() * Basis(Vector3.UP, PI)
	var sentado := Transform3D(base, asiento.global_position - base.y * 0.1)
	var parado := _cuerpo_de if montado else global_transform
	var ahora := parado.interpolate_with(sentado, s)
	ahora.origin.y += sin(s * PI) * 0.3
	cuerpo.global_transform = ahora
	if _subiendo <= 0.0:
		# Ya está en el suelo: el cuerpo vuelve a colgar de este nodo como siempre.
		cuerpo.transform = Transform3D.IDENTITY
		if _porte != null:
			_porte.sentar({})
			_porte.inclinar = 0.0


## Las pisadas que Ceniza deja atrás cuando va montada: unas manchas oscuras con forma de vaso,
## apoyadas en el suelo. Son siempre las últimas tantas (la más vieja se borra al marcar una nueva).
func _armar_huellas() -> void:
	if huellas_de_cascos <= 0:
		return
	var imagen := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var q := Vector2(x - 15.5, y - 15.5) / 15.5
			# Un anillo abierto hacia atrás, en el talón.
			var marca := q.length() < 0.98 and q.length() > 0.45 and not (q.y > 0.3 and absf(q.x) < 0.4)
			imagen.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0 if marca else 0.0))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 0.07, 0.05, 0.42)
	material.albedo_texture = ImageTexture.create_from_image(imagen)
	var plano := PlaneMesh.new()
	plano.size = Vector2(0.13, 0.15)
	plano.material = material
	_huellas = MultiMesh.new()
	_huellas.transform_format = MultiMesh.TRANSFORM_3D
	_huellas.mesh = plano
	_huellas.instance_count = huellas_de_cascos
	_huellas.visible_instance_count = 0
	var nodo := MultiMeshInstance3D.new()
	nodo.name = "HuellasDeCeniza"
	nodo.multimesh = _huellas
	nodo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Quedan en el mundo, no viajan con Zenón.
	nodo.top_level = true
	add_child(nodo)


func _marcar_huellas(delta: float, suelo: float) -> void:
	if _huellas == null or _rapidez < 0.3 or not is_on_floor():
		return
	_huella_falta -= _rapidez * delta
	if _huella_falta > 0.0:
		return
	# Más ligero, pisadas más separadas. Una de cada lado, alternadas.
	_huella_falta = 0.45 + _rapidez * 0.05
	var lado := 0.17 if _huella_n % 2 == 0 else -0.17
	var base := Basis(Vector3.UP, _rumbo) * Basis(Vector3.RIGHT, _cabeceo)
	var donde := Vector3(global_position.x, suelo + 0.03, global_position.z) + base * Vector3(lado, 0.0, 0.5)
	donde.y = Historia.altura_suelo(donde.x, donde.z) + 0.03
	_huellas.set_instance_transform(_huella_n % _huellas.instance_count, Transform3D(base, donde))
	_huella_n += 1
	_huellas.visible_instance_count = mini(_huella_n, _huellas.instance_count)


## La primera vez que Zenón se aleja a pie de Ceniza, avisa que se la puede llamar.
func _avisar_que_se_silba() -> void:
	if _ceniza == null or Historia.ocupado or Historia.flags.has("_pista_silbar"):
		return
	if global_position.distance_squared_to(_ceniza.global_position) > 30.0 * 30.0:
		Historia.flags["_pista_silbar"] = true
		mostrar_aviso("Ceniza quedó atrás, ensillada. Con la Q la silbás y viene; arrimado a ella, con la E la montás.")


func _prender_choque_de_ceniza(si: bool) -> void:
	# En el acto, no al final del cuadro: si no, al montar, el choque de Ceniza empuja a Zenón afuera.
	var forma := _ceniza.get_node_or_null("Choque/Forma") as CollisionShape3D
	if forma != null:
		forma.disabled = not si
	var montarla := _ceniza.get_node_or_null("Hablar") as Node3D
	if montarla != null:
		montarla.visible = si


## ¿Entra Zenón parado en ese lugar, sin quedar metido en algo?
func _lugar_libre(lugar: Vector3) -> bool:
	var consulta := PhysicsShapeQueryParameters3D.new()
	consulta.shape = $CollisionShape3D.shape
	consulta.transform = Transform3D(Basis.IDENTITY, lugar + Vector3(0.0, 0.25, 0.0))
	consulta.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(consulta, 1).is_empty()


## ¿Hay camino derecho y despejado desde ese punto hasta Zenón? (Ceniza no esquiva nada.)
func _camino_libre(desde: Vector3) -> bool:
	var consulta := PhysicsRayQueryParameters3D.create(desde + Vector3(0.0, 0.9, 0.0), global_position)
	consulta.exclude = [get_rid()]
	var choque := _ceniza.get_node_or_null("Choque") as CollisionObject3D
	if choque != null:
		consulta.exclude = [get_rid(), choque.get_rid()]
	consulta.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(consulta).is_empty()

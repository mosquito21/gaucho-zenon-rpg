extends CharacterBody3D

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

var current_interactable: Interactable = null

# El recado y la seña viven acá para que no se borren al alejarse de la posta.
# Recado: 0 ninguno, 1 llevando, 2 entregado.
# Exploración del fortín: 0 ninguna, 1 yendo al mojón, 2 mojón visto, 3 hecha.
var estado_recado := 0
var estado_exploracion := 0
var _periodo := "Día"
var _aviso: Label
var _aviso_tiempo := 0.0

# Clips de Mixamo, animados en el lugar: el avance lo da el CharacterBody3D.
# Velocidad natural de cada clip en m/s, para que los pies no patinen.
const CLIPS_EN_LOOP := ["idle", "walk", "run", "strafe_left", "strafe_left_walk", "strafe_right", "strafe_right_walk"]
const PASO_CLIP := {"walk": 1.55, "run": 4.0, "strafe_left_walk": 1.6, "strafe_right_walk": 1.6, "strafe_left": 4.1, "strafe_right": 4.1}
var _anim: AnimationPlayer
var _saltando := false


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
	call_deferred("_conectar_ciclo")
	

func _unhandled_input(event: InputEvent) -> void:
	# togglear captura del mouse con ESC
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# mirar con el mouse
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity

		var min_pitch := deg_to_rad(min_pitch_deg)
		var max_pitch := deg_to_rad(max_pitch_deg)
		pitch = clamp(pitch, min_pitch, max_pitch)

	# zoom con la ruedita
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = max(zoom_min, camera_distance - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = min(zoom_max, camera_distance + zoom_speed)

	# 🔹 Interactuar con E
	if event.is_action_pressed("interact") and current_interactable:
		_do_interact(current_interactable)


func _process(delta: float) -> void:
	_check_interaction()
	_update_hud()
	_tick_aviso(delta)

	rotation.y = yaw
	camera_pivot.rotation.x = pitch
	_acomodar_camara(delta)


func _check_interaction() -> void:
	current_interactable = null

	if not ray_interact.is_colliding():
		return

	current_interactable = _buscar_interactable(ray_interact.get_collider())


func _update_hud() -> void:
	if not interact_label:
		return

	if current_interactable and current_interactable.has_method("texto_mira"):
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
	mostrar_aviso(linea)
	print(linea)


func _physics_process(delta: float) -> void:
	# gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# movimiento relativo a hacia dónde mira el jugador
	var move_dir := Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		move_dir -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		move_dir += transform.basis.z
	if Input.is_action_pressed("move_left"):
		move_dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):
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
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_empezar_salto()

	move_and_slide()
	_frenar_en_el_borde()
	_recuperar_suelo()
	_animar_gaucho(delta)


func _acomodar_camara(delta: float) -> void:
	var peso := clampf(suavizado_camara * delta, 0.0, 1.0)
	_distancia_actual = lerpf(_distancia_actual, camera_distance, peso)
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
		mostrar_aviso("El sol baja sobre la estepa. Si dejás el recado ahora, el puestero anota un plus.")
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
		return "Tomás el recado con el sol bajo. El palo del hito queda al noreste; si llegás antes de que cierre la luz, hay un plus."
	return "El puestero te alcanza el recado. Llevalo al palo del hito, al noreste, donde se ve el humo."


func entregar_recado() -> String:
	if estado_recado == 0:
		return "El palo está vacío. Primero tenés que tomar el recado en la posta."
	if estado_recado == 2:
		return "El recado ya quedó atado al palo."
	estado_recado = 2
	if _periodo == "Atardecer":
		return "Dejás el recado con luz de atardecer. El puestero te anota un plus por llegar antes de la noche."
	if _periodo == "Noche" or _periodo == "Crepúsculo":
		return "Atás el recado al palo de noche. El humo te trajo derecho: el trabajo quedó hecho."
	return "Dejás el recado en el palo. El trabajo de mensajería quedó cumplido."


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
	_aviso_tiempo = 9.0


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
	if rapidez < 0.25:
		_poner_clip("idle", 1.0)
		return

	var clip := ""
	var sentido := 1.0
	if absf(local.z) >= absf(local.x):
		clip = "walk" if rapidez < 2.5 else "run"
		if local.z > 0.0:
			sentido = -1.0
	else:
		var lado := "strafe_right" if local.x > 0.0 else "strafe_left"
		clip = lado + "_walk" if rapidez < 2.5 else lado
	var escala := clampf(rapidez / float(PASO_CLIP.get(clip, rapidez)), 0.6, 1.8)
	_poner_clip(clip, escala * sentido)


func _poner_clip(nombre: String, escala: float) -> void:
	if not _anim.has_animation(nombre):
		return
	# Con el mismo clip, play() no lo reinicia: solo actualiza la velocidad.
	_anim.play(nombre, 0.2, escala)

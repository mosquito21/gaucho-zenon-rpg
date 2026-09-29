extends Node

## Sistema de Ciclo Día y Noche para El Gaucho Zenón RPG
## Ambientado en la Patagonia Argentina del Siglo XIX
## 
## IMPORTANTE: Este sistema NO incluye controles de teclado para evitar 
## conflictos con los controles del personaje (WASD, SPACE, E, Mouse).
## El ciclo funciona automáticamente. Para pruebas usar ControlesDebug (F1-F6).

class_name CicloDiaNoche

# Referencias a los nodos necesarios
@export var sol: DirectionalLight3D
@export var ambiente_mundo: WorldEnvironment

# Configuración del ciclo
@export var duracion_ciclo_minutos: float = 10.0  # Duración del ciclo completo en minutos reales
@export var hora_inicial: float = 6.0  # Hora de inicio (6:00 AM)

# Variables del sistema
var tiempo_actual: float = 0.0  # Tiempo en segundos dentro del ciclo
var hora_del_dia: float = 6.0   # Hora actual del día (0-24)

# Configuración de colores para diferentes momentos
var color_amanecer = Color(1.0, 0.6, 0.3)     # Naranja suave del amanecer pampeano
var color_dia = Color(1.0, 0.95, 0.8)         # Luz dorada de la pampa al mediodía
var color_atardecer = Color(1.0, 0.4, 0.1)    # Rojo intenso del atardecer patagónico
var color_noche = Color(0.05, 0.08, 0.15)     # Azul MUY oscuro para noche profunda

# Configuración de intensidad de luz  
var intensidad_dia: float = 2.0     # MUY brillante para mediodía
var intensidad_noche: float = 0.02  # MUY poca luz para noche oscura
var intensidad_crepusculo: float = 0.6

# Variables para el environment  
var energia_cielo_dia: float = 1.0
var energia_cielo_noche: float = 0.05  # Cielo MUY oscuro de noche

signal cambio_periodo(nuevo_periodo: String)
signal nueva_hora(hora: int, minutos: int)

var periodo_anterior: String = ""

# Luna: un mes sinódico son ~29.5 días de juego. Arranca llena para que la primera noche se vea.
const DIAS_CICLO_LUNAR := 29.530588
var dias_transcurridos: float = 14.765
var fase_lunar: float = 0.5
var luz_luna: DirectionalLight3D
var disco_luna: MeshInstance3D
var material_luna: ShaderMaterial
var nubes: Array[MeshInstance3D] = []

func _ready():
	# Esperar un frame para asegurar que todos los nodos estén listos
	await get_tree().process_frame
	
	# Configurar el estado inicial
	tiempo_actual = (hora_inicial / 24.0) * (duracion_ciclo_minutos * 60.0)
	
	print("Sistema de Ciclo Día/Noche iniciado - Patagonia, Siglo XIX")
	print("Duración del ciclo: ", duracion_ciclo_minutos, " minutos")
	
	# Debug: mostrar estado de las referencias
	print("🔍 Debug - Sol asignado: ", sol != null)
	print("🔍 Debug - Ambiente asignado: ", ambiente_mundo != null)
	
	crear_luna()
	crear_nubes()
	actualizar_ciclo()

func _process(delta):
	# Avanzar el tiempo siempre (sin validaciones que bloqueen)
	tiempo_actual += delta
	
	# Si completamos un ciclo, reiniciar
	var duracion_total = duracion_ciclo_minutos * 60.0
	if tiempo_actual >= duracion_total:
		tiempo_actual -= duracion_total
		dias_transcurridos += 1.0
	
	# Calcular la hora actual del día
	hora_del_dia = (tiempo_actual / duracion_total) * 24.0
	
	# Actualizar el ciclo
	actualizar_ciclo()
	
	# Emitir señal de nueva hora cada minuto del juego
	var hora_entera = int(hora_del_dia)
	var minutos = int((hora_del_dia - hora_entera) * 60)
	if minutos % 15 == 0:  # Emitir cada 15 minutos del juego para no saturar
		nueva_hora.emit(hora_entera, minutos)

func actualizar_ciclo():
	# Calcular la rotación del sol (DirectionalLight3D)
	actualizar_rotacion_sol()
	actualizar_luna()
	actualizar_nubes()
	
	# Actualizar colores e intensidad
	actualizar_iluminacion()
	
	# Determinar el período del día y emitir señal si cambió
	var periodo_actual = obtener_periodo_dia()
	if periodo_actual != periodo_anterior:
		cambio_periodo.emit(periodo_actual)
		periodo_anterior = periodo_actual
		print("Nuevo período: ", periodo_actual, " - Hora: ", obtener_hora_formateada())

func actualizar_rotacion_sol():
	# Validar que el sol existe y es válido
	if not sol or not is_instance_valid(sol):
		return
		
	# DirectionalLight3D alumbra hacia su -Z.
	# Pitch negativo baja la luz: 0° en el horizonte (6:00), -90° en el cenit (12:00), -180° al ponerse (18:00).
	# El yaw en 90° hace que recorra este-oeste. De noche sigue bajo el horizonte.
	var angulo_sol = -((hora_del_dia - 6.0) / 24.0) * 360.0
	sol.rotation_degrees = Vector3(angulo_sol, 90.0, 0.0)

func crear_luna() -> void:
	var raiz := get_tree().current_scene
	if raiz == null:
		return
	
	luz_luna = DirectionalLight3D.new()
	luz_luna.name = "Luna"
	luz_luna.light_color = Color(0.72, 0.8, 1.0)
	luz_luna.light_energy = 0.0
	luz_luna.shadow_enabled = true
	luz_luna.shadow_opacity = 0.45
	# Si no, el cielo dibuja un sol chiquito encima de la luna.
	luz_luna.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	raiz.add_child(luz_luna)
	
	var shader := Shader.new()
	shader.code = "shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;
uniform float fase = 0.5;
void fragment() {
	vec3 dir_vista = normalize(VERTEX);
	vec3 arriba = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	if (dot(dir_vista, arriba) < 0.0) {
		discard;
	}
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float z = sqrt(max(1.0 - r * r, 0.0));
	vec3 normal = normalize(vec3(p, z));
	float ang = fase * 6.2831853;
	vec3 luz = normalize(vec3(sin(ang), 0.0, -cos(ang)));
	if (dot(normal, luz) < 0.05) {
		discard;
	}
	float manchas = 0.94 + 0.06 * sin(p.x * 7.0) * sin(p.y * 5.0);
	ALBEDO = vec3(0.96, 0.95, 0.88) * manchas;
}"
	material_luna = ShaderMaterial.new()
	material_luna.shader = shader
	
	var quad := QuadMesh.new()
	quad.size = Vector2(18, 18)
	disco_luna = MeshInstance3D.new()
	disco_luna.name = "DiscoLuna"
	disco_luna.mesh = quad
	disco_luna.material_override = material_luna
	disco_luna.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	raiz.add_child(disco_luna)

func crear_nubes() -> void:
	var raiz := get_tree().current_scene
	if raiz == null:
		return
	var imagen := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2(x - 32.0, y - 32.0) / 26.0
			var d := p.length()
			var alfa := clampf(1.0 - smoothstep(0.15, 1.0, d), 0.0, 0.9)
			imagen.set_pixel(x, y, Color(0.97, 0.97, 0.95, alfa))
	var textura := ImageTexture.create_from_image(imagen)
	var shader := Shader.new()
	shader.code = "shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;
uniform sampler2D nube_tex;
void fragment() {
	vec4 c = texture(nube_tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("nube_tex", textura)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var semillas := [
		Vector3(-70, 22, -150), Vector3(55, 28, -190), Vector3(-15, 16, -240),
		Vector3(90, 24, -130), Vector3(-40, 32, -210), Vector3(20, 18, -280),
	]
	for i in semillas.size():
		var nube := MeshInstance3D.new()
		nube.name = "Nube%d" % i
		nube.mesh = quad
		nube.material_override = mat
		nube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nube.scale = Vector3(160, 55, 1) if i % 2 == 0 else Vector3(210, 70, 1)
		nube.set_meta("offset", semillas[i])
		raiz.add_child(nube)
		nubes.append(nube)

func actualizar_nubes() -> void:
	if nubes.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var de_dia := obtener_periodo_dia() == "Día" or obtener_periodo_dia() == "Amanecer" or obtener_periodo_dia() == "Atardecer"
	var t := float(Time.get_ticks_msec()) * 0.00002
	for nube in nubes:
		if not is_instance_valid(nube):
			continue
		nube.visible = de_dia
		var offset: Vector3 = nube.get_meta("offset")
		var deriva := Vector3(sin(t + offset.x) * 8.0, 0.0, cos(t + offset.z) * 6.0)
		nube.global_position = cam.global_position + offset + deriva
		nube.look_at(cam.global_position, Vector3.UP)
		nube.rotate_object_local(Vector3.UP, PI)

func actualizar_luna() -> void:
	if not luz_luna or not is_instance_valid(luz_luna):
		return
	
	fase_lunar = fmod(dias_transcurridos / DIAS_CICLO_LUNAR, 1.0)
	var angulo_luna = -((hora_del_dia - 6.0) / 24.0) * 360.0 - fase_lunar * 360.0
	luz_luna.rotation_degrees = Vector3(angulo_luna, 90.0, 0.0)
	
	var altura: float = luz_luna.global_transform.basis.z.y
	var iluminada := (1.0 - cos(fase_lunar * TAU)) * 0.5
	var sobre_horizonte := clampf(altura, 0.0, 1.0)
	var peso_noche := 1.0
	match obtener_periodo_dia():
		"Día":
			peso_noche = 0.0
		"Amanecer":
			peso_noche = 0.2
		"Atardecer":
			peso_noche = 0.45
		"Crepúsculo":
			peso_noche = 0.8
		"Noche":
			peso_noche = 1.0
	luz_luna.light_energy = 0.75 * iluminada * sobre_horizonte * peso_noche
	
	if not disco_luna or not is_instance_valid(disco_luna):
		return
	var cam := get_viewport().get_camera_3d()
	# Se apaga cuando ya pasó el horizonte. El shader recorta el disco
	# en esa línea, así no sigue dibujándose dentro del terreno.
	if cam == null or altura < -0.08:
		disco_luna.visible = false
		return
	var direccion: Vector3 = luz_luna.global_transform.basis.z.normalized()
	disco_luna.global_position = cam.global_position + direccion * 260.0
	disco_luna.look_at(cam.global_position, Vector3.UP)
	disco_luna.rotate_object_local(Vector3.UP, PI)
	disco_luna.visible = true
	if material_luna:
		material_luna.set_shader_parameter("fase", fase_lunar)
		disco_luna.visible = peso_noche > 0.05

func actualizar_iluminacion():
	var color_actual: Color
	var intensidad_actual: float
	var energia_ambiente: float
	
	# Determinar color e intensidad basado en la hora
	match obtener_periodo_dia():
		"Amanecer":
			var progreso = (hora_del_dia - 5.0) / 2.0  # 5:00 - 7:00
			color_actual = color_amanecer.lerp(color_dia, progreso)
			intensidad_actual = lerp(intensidad_noche, intensidad_dia, progreso)
			energia_ambiente = lerp(energia_cielo_noche, energia_cielo_dia, progreso)
			
		"Día":
			color_actual = color_dia
			intensidad_actual = intensidad_dia
			energia_ambiente = energia_cielo_dia
			
		"Atardecer":
			var progreso = (hora_del_dia - 17.0) / 2.0  # 17:00 - 19:00
			color_actual = color_dia.lerp(color_atardecer, progreso)
			intensidad_actual = lerp(intensidad_dia, intensidad_crepusculo, progreso)
			energia_ambiente = lerp(energia_cielo_dia, energia_cielo_noche, progreso)
			
		"Crepúsculo":
			var progreso = (hora_del_dia - 19.0) / 2.0  # 19:00 - 21:00
			color_actual = color_atardecer.lerp(color_noche, progreso)
			intensidad_actual = lerp(intensidad_crepusculo, intensidad_noche, progreso)
			energia_ambiente = lerp(energia_cielo_noche * 0.5, energia_cielo_noche, progreso)
			
		"Noche":
			color_actual = color_noche
			intensidad_actual = intensidad_noche
			energia_ambiente = 0.22
			
		_:
			color_actual = color_noche
			intensidad_actual = intensidad_noche
			energia_ambiente = energia_cielo_noche
	
	# Aplicar cambios al sol de forma segura
	if sol and is_instance_valid(sol):
		sol.light_color = color_actual
		sol.light_energy = intensidad_actual
	
	# Auto-encontrar Sol si no está asignado
	if not sol or not is_instance_valid(sol):
		sol = buscar_directional_light()
		if sol:
			print("🔧 Sol auto-asignado: ", sol.name)
	
	# Auto-encontrar WorldEnvironment si no está asignado
	if not ambiente_mundo or not is_instance_valid(ambiente_mundo):
		ambiente_mundo = buscar_world_environment()
		if ambiente_mundo:
			print("🔧 WorldEnvironment auto-asignado: ", ambiente_mundo.name)
	
	# Modificar el ambiente si existe el sky
	if ambiente_mundo and is_instance_valid(ambiente_mundo):
		if ambiente_mundo.environment:
			var env = ambiente_mundo.environment
			
			# FORZAR que use el cielo como background
			env.background_mode = Environment.BG_SKY
			
			# Modificar la luz ambiental según la hora
			env.ambient_light_energy = energia_ambiente * 0.3
			if luz_luna and is_instance_valid(luz_luna):
				env.ambient_light_energy += luz_luna.light_energy * 0.35
			
			# Asegurar que hay Sky configurado
			if not env.sky:
				env.sky = Sky.new()
				print("🔧 Sky creado")
			
			if not env.sky.sky_material:
				env.sky.sky_material = ProceduralSkyMaterial.new()
				print("🔧 ProceduralSkyMaterial creado")
			
			# Modificar el cielo si es posible
			if env.sky and env.sky.sky_material:
				# Si es ProceduralSkyMaterial, cambiar colores según el período
				if env.sky.sky_material is ProceduralSkyMaterial:
					var sky_mat = env.sky.sky_material as ProceduralSkyMaterial
					# Disco del sol: en grados. 1.35 lo dejaba en un puntito.
					sky_mat.sun_angle_max = 22.0
					sky_mat.sun_curve = 0.18
					
					# Configurar colores según el período del día
					match obtener_periodo_dia():
						"Amanecer":
							sky_mat.sky_top_color = Color(0.45, 0.55, 0.85)
							sky_mat.sky_horizon_color = Color(1.0, 0.62, 0.35)
							sky_mat.ground_bottom_color = Color(0.22, 0.16, 0.1)
							sky_mat.ground_horizon_color = Color(0.72, 0.42, 0.22)
							sky_mat.sky_curve = 0.12
							sky_mat.energy_multiplier = 0.7
							
						"Día":
							sky_mat.sky_top_color = Color(0.28, 0.5, 0.85)
							sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.92)
							sky_mat.ground_bottom_color = Color(0.28, 0.24, 0.16)
							sky_mat.ground_horizon_color = Color(0.55, 0.48, 0.36)
							sky_mat.sky_curve = 0.08
							sky_mat.energy_multiplier = 1.0
							
						"Atardecer":
							sky_mat.sky_top_color = Color(0.25, 0.32, 0.62)
							sky_mat.sky_horizon_color = Color(0.95, 0.42, 0.18)
							sky_mat.ground_bottom_color = Color(0.16, 0.1, 0.06)
							sky_mat.ground_horizon_color = Color(0.55, 0.28, 0.12)
							sky_mat.sky_curve = 0.12
							sky_mat.energy_multiplier = 0.65
							
						"Crepúsculo":
							sky_mat.sky_top_color = Color(0.05, 0.08, 0.2)
							sky_mat.sky_horizon_color = Color(0.18, 0.16, 0.32)
							sky_mat.ground_bottom_color = Color(0.04, 0.04, 0.06)
							sky_mat.ground_horizon_color = Color(0.1, 0.08, 0.12)
							sky_mat.sky_curve = 0.15
							sky_mat.energy_multiplier = 0.25
							
						"Noche":
							sky_mat.sky_top_color = Color(0.01, 0.02, 0.06)
							sky_mat.sky_horizon_color = Color(0.03, 0.05, 0.1)
							sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
							sky_mat.ground_horizon_color = Color(0.02, 0.02, 0.04)
							sky_mat.sky_curve = 0.15
							sky_mat.energy_multiplier = 0.08
				# Si no es ProceduralSkyMaterial, no hacer nada

func obtener_periodo_dia() -> String:
	if hora_del_dia >= 5.0 and hora_del_dia < 7.0:
		return "Amanecer"
	elif hora_del_dia >= 7.0 and hora_del_dia < 17.0:
		return "Día"
	elif hora_del_dia >= 17.0 and hora_del_dia < 19.0:
		return "Atardecer"
	elif hora_del_dia >= 19.0 and hora_del_dia < 21.0:
		return "Crepúsculo"
	else:
		return "Noche"

func obtener_hora_formateada() -> String:
	var hora = int(hora_del_dia)
	var minutos = int((hora_del_dia - hora) * 60)
	return "%02d:%02d" % [hora, minutos]

# Función de debug para ver el estado
func debug_estado():
	print("🕐 Hora actual: ", obtener_hora_formateada())
	print("🌅 Período: ", obtener_periodo_dia())
	print("☀️ Sol: ", "✅" if (sol and is_instance_valid(sol)) else "❌")
	print("🌍 Ambiente: ", "✅" if (ambiente_mundo and is_instance_valid(ambiente_mundo)) else "❌")
	print("🌙 Fase lunar: ", "%d%%" % int(fase_lunar * 100.0), " (0 nueva, 50 llena)")

func buscar_directional_light() -> DirectionalLight3D:
	"""Busca automáticamente un DirectionalLight3D en la escena"""
	
	var luces = []
	buscar_nodos_recursivo(get_tree().current_scene, DirectionalLight3D, luces)
	
	for luz in luces:
		if luz.name != "Luna":
			return luz as DirectionalLight3D
	
	return null

func buscar_world_environment() -> WorldEnvironment:
	"""Busca automáticamente un WorldEnvironment en la escena"""
	
	var ambientes = []
	buscar_nodos_recursivo(get_tree().current_scene, WorldEnvironment, ambientes)
	
	if ambientes.size() > 0:
		return ambientes[0] as WorldEnvironment
	
	return null

func buscar_nodos_recursivo(nodo: Node, tipo: Variant, resultado: Array):
	"""Busca nodos recursivamente"""
	
	if is_instance_of(nodo, tipo):
		resultado.append(nodo)
	
	for child in nodo.get_children():
		buscar_nodos_recursivo(child, tipo, resultado)

# Funciones públicas para controlar el ciclo

func establecer_hora(nueva_hora: float):
	"""Establece la hora del día directamente (0-24)"""
	hora_del_dia = clamp(nueva_hora, 0.0, 24.0)
	tiempo_actual = (hora_del_dia / 24.0) * (duracion_ciclo_minutos * 60.0)
	actualizar_ciclo()

func acelerar_tiempo(multiplicador: float):
	"""Acelera o desacelera el paso del tiempo"""
	Engine.time_scale = multiplicador

func pausar_ciclo():
	"""Pausa el ciclo día/noche"""
	set_process(false)

func reanudar_ciclo():
	"""Reanuda el ciclo día/noche"""
	set_process(true)

func obtener_info_tiempo() -> Dictionary:
	"""Retorna información completa del estado actual del tiempo"""
	return {
		"hora_formateada": obtener_hora_formateada(),
		"hora_decimal": hora_del_dia,
		"periodo": obtener_periodo_dia(),
		"progreso_ciclo": tiempo_actual / (duracion_ciclo_minutos * 60.0),
		"duracion_ciclo": duracion_ciclo_minutos
	}

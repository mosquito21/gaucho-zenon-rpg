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

# Claves del día (tanda 4). Cada fila dice cómo se ve el mundo a una hora; entre una fila y la
# siguiente todo se mezcla suave, así el cielo ya no cambia de golpe al pasar de un período a otro.
#   cenit / horizonte: colores del cielo arriba y abajo (la niebla toma el del horizonte)
#   sol / sol_e: color y fuerza de la luz del sol
#   amb / amb_e: color y fuerza de la luz que llena las sombras (tierra de día, azul de noche)
#   nube / nube_s: color de las nubes del lado de la luz y del lado de la sombra
#   resp / resp_f: color y fuerza del resplandor del horizonte hacia el lado del sol
#   noche: 0 de día, 1 de noche cerrada (estrellas y luna)
const CLAVES := [
	{"h": 0.0, "cenit": Color(0.02, 0.035, 0.085), "horizonte": Color(0.05, 0.075, 0.14), "sol": Color(1.0, 0.5, 0.3), "sol_e": 0.0, "amb": Color(0.10, 0.13, 0.22), "amb_e": 0.6, "nube": Color(0.10, 0.12, 0.17), "nube_s": Color(0.03, 0.04, 0.07), "resp": Color(0.2, 0.2, 0.35), "resp_f": 0.0, "noche": 1.0},
	{"h": 4.6, "cenit": Color(0.02, 0.035, 0.085), "horizonte": Color(0.05, 0.075, 0.14), "sol": Color(1.0, 0.5, 0.3), "sol_e": 0.0, "amb": Color(0.10, 0.13, 0.22), "amb_e": 0.6, "nube": Color(0.10, 0.12, 0.17), "nube_s": Color(0.03, 0.04, 0.07), "resp": Color(0.2, 0.2, 0.35), "resp_f": 0.0, "noche": 1.0},
	{"h": 5.4, "cenit": Color(0.07, 0.10, 0.22), "horizonte": Color(0.33, 0.26, 0.32), "sol": Color(1.0, 0.55, 0.32), "sol_e": 0.0, "amb": Color(0.26, 0.25, 0.34), "amb_e": 0.9, "nube": Color(0.38, 0.30, 0.34), "nube_s": Color(0.10, 0.11, 0.18), "resp": Color(0.85, 0.45, 0.30), "resp_f": 0.55, "noche": 0.45},
	{"h": 6.15, "cenit": Color(0.26, 0.36, 0.56), "horizonte": Color(0.74, 0.54, 0.44), "sol": Color(1.0, 0.60, 0.36), "sol_e": 1.6, "amb": Color(0.56, 0.50, 0.52), "amb_e": 1.5, "nube": Color(1.0, 0.72, 0.55), "nube_s": Color(0.42, 0.36, 0.46), "resp": Color(1.0, 0.58, 0.30), "resp_f": 0.85, "noche": 0.05},
	{"h": 7.3, "cenit": Color(0.36, 0.51, 0.68), "horizonte": Color(0.76, 0.70, 0.62), "sol": Color(1.0, 0.84, 0.64), "sol_e": 1.9, "amb": Color(0.62, 0.55, 0.48), "amb_e": 1.3, "nube": Color(0.98, 0.92, 0.84), "nube_s": Color(0.62, 0.62, 0.66), "resp": Color(1.0, 0.8, 0.55), "resp_f": 0.35, "noche": 0.0},
	{"h": 9.5, "cenit": Color(0.40, 0.57, 0.71), "horizonte": Color(0.67, 0.75, 0.75), "sol": Color(1.0, 0.95, 0.86), "sol_e": 1.6, "amb": Color(0.62, 0.59, 0.53), "amb_e": 1.0, "nube": Color(0.95, 0.95, 0.93), "nube_s": Color(0.66, 0.69, 0.72), "resp": Color(1.0, 0.8, 0.55), "resp_f": 0.0, "noche": 0.0},
	{"h": 15.0, "cenit": Color(0.40, 0.57, 0.71), "horizonte": Color(0.67, 0.75, 0.75), "sol": Color(1.0, 0.95, 0.86), "sol_e": 1.6, "amb": Color(0.62, 0.59, 0.53), "amb_e": 1.0, "nube": Color(0.95, 0.95, 0.93), "nube_s": Color(0.66, 0.69, 0.72), "resp": Color(1.0, 0.8, 0.55), "resp_f": 0.0, "noche": 0.0},
	{"h": 16.7, "cenit": Color(0.38, 0.52, 0.68), "horizonte": Color(0.80, 0.73, 0.60), "sol": Color(1.0, 0.83, 0.60), "sol_e": 1.8, "amb": Color(0.62, 0.54, 0.46), "amb_e": 1.25, "nube": Color(1.0, 0.92, 0.80), "nube_s": Color(0.62, 0.60, 0.64), "resp": Color(1.0, 0.75, 0.45), "resp_f": 0.4, "noche": 0.0},
	{"h": 17.6, "cenit": Color(0.30, 0.38, 0.58), "horizonte": Color(0.86, 0.60, 0.40), "sol": Color(1.0, 0.68, 0.40), "sol_e": 1.9, "amb": Color(0.58, 0.50, 0.50), "amb_e": 1.6, "nube": Color(1.0, 0.70, 0.48), "nube_s": Color(0.46, 0.38, 0.48), "resp": Color(1.0, 0.60, 0.36), "resp_f": 0.7, "noche": 0.0},
	{"h": 18.15, "cenit": Color(0.20, 0.25, 0.46), "horizonte": Color(0.72, 0.44, 0.34), "sol": Color(1.0, 0.42, 0.20), "sol_e": 0.8, "amb": Color(0.48, 0.42, 0.48), "amb_e": 1.5, "nube": Color(0.95, 0.50, 0.38), "nube_s": Color(0.30, 0.26, 0.40), "resp": Color(1.0, 0.48, 0.28), "resp_f": 0.85, "noche": 0.1},
	{"h": 19.0, "cenit": Color(0.07, 0.09, 0.22), "horizonte": Color(0.30, 0.24, 0.36), "sol": Color(1.0, 0.42, 0.20), "sol_e": 0.0, "amb": Color(0.26, 0.26, 0.38), "amb_e": 1.0, "nube": Color(0.32, 0.26, 0.36), "nube_s": Color(0.08, 0.09, 0.16), "resp": Color(0.70, 0.35, 0.30), "resp_f": 0.6, "noche": 0.55},
	{"h": 20.3, "cenit": Color(0.02, 0.035, 0.085), "horizonte": Color(0.05, 0.075, 0.14), "sol": Color(1.0, 0.5, 0.3), "sol_e": 0.0, "amb": Color(0.10, 0.13, 0.22), "amb_e": 0.6, "nube": Color(0.10, 0.12, 0.17), "nube_s": Color(0.03, 0.04, 0.07), "resp": Color(0.2, 0.2, 0.35), "resp_f": 0.0, "noche": 1.0},
	{"h": 24.0, "cenit": Color(0.02, 0.035, 0.085), "horizonte": Color(0.05, 0.075, 0.14), "sol": Color(1.0, 0.5, 0.3), "sol_e": 0.0, "amb": Color(0.10, 0.13, 0.22), "amb_e": 0.6, "nube": Color(0.10, 0.12, 0.17), "nube_s": Color(0.03, 0.04, 0.07), "resp": Color(0.2, 0.2, 0.35), "resp_f": 0.0, "noche": 1.0},
]

const COLOR_LUNA := Color(0.62, 0.72, 1.0)
## Fuerza de la luz de la luna llena en lo alto.
@export var fuerza_luna: float = 0.5

## La bruma de lejos del piso y de las copas de los árboles (assets/materiales/bruma.gdshaderinc).
## La distancia y la curva son las de la niebla del ambiente; acá va solo lo que es propio.
@export_group("Bruma de lejos")
## Cuánta bruma tapa, como mucho, lo que está alto: 1 lo borra igual que al llano (el macizo del
## paso desaparece de lejos); 0 lo deja sin nada de bruma.
@export_range(0.0, 1.0, 0.01) var bruma_cumbres: float = 0.3
## Altura, en metros, hasta donde el suelo es "llano" y recibe toda la bruma.
@export var bruma_baja: float = 10.0
## Altura, en metros, desde donde el suelo es "cumbre" y la bruma llega solo al tope de arriba.
@export var bruma_alta: float = 70.0

## La luz de la cordillera del fondo (assets/materiales/cordillera.gdshader). Lo demás (cuánto marcan
## las quebradas, el contraluz, la luna) está en el material, grupo "ajustes".
@export_group("Cordillera")
## El sol que alumbra la cordillera nunca sube más que esto (1 es el cenit; 0,55 son unos 35 grados).
@export_range(0.1, 1.0, 0.01) var altura_sol_relieve: float = 0.55
## Cuánto se corre ese sol hacia el norte (0: sale y se pone como el de verdad).
@export_range(0.0, 2.0, 0.05) var norte_sol_relieve: float = 0.75
## Cuánta luz reciben las laderas en sombra (toman el color del cielo de la hora).
@export_range(0.0, 1.5, 0.05) var sombra_cordillera: float = 0.6

signal cambio_periodo(nuevo_periodo: String)
signal nueva_hora(hora: int, minutos: int)

var periodo_anterior: String = ""
var _ultimo_cuarto: int = -1

## Cuánto se ven las estrellas (0 de día, 1 de noche cerrada). Lo lee EstrellasPatagonia.gd.
var brillo_estrellas: float = 0.0

# Luna: un mes sinódico son ~29.5 días de juego. Arranca llena para que la primera noche se vea.
const DIAS_CICLO_LUNAR := 29.530588
var dias_transcurridos: float = 14.765
var fase_lunar: float = 0.5
var luz_luna: DirectionalLight3D
var disco_luna: MeshInstance3D
var material_luna: ShaderMaterial
# El cielo (assets/materiales/cielo.tres), la cordillera y la bruma de lejos reciben sus colores
# desde acá. La bruma la dibujan el piso y dos materiales: el de las hojas y el mate de casi todo.
const MATERIALES_CON_BRUMA := ["res://assets/materiales/hoja.tres", "res://assets/materiales/mate.tres"]
var cielo: ShaderMaterial
var material_cordillera: ShaderMaterial
var terreno: Node3D
var materiales_con_bruma: Array[ShaderMaterial] = []

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
	_buscar_cielo_y_cordillera()
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

	# Avisar la hora una vez cada 15 minutos del juego (antes salía en cada cuadro de ese minuto)
	var cuarto := int(hora_del_dia * 4.0)
	if cuarto != _ultimo_cuarto:
		_ultimo_cuarto = cuarto
		nueva_hora.emit(int(hora_del_dia), (cuarto % 4) * 15)

func actualizar_ciclo():
	# Calcular la rotación del sol (DirectionalLight3D)
	actualizar_rotacion_sol()
	actualizar_luna()

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
	luz_luna.light_color = COLOR_LUNA
	luz_luna.light_energy = 0.0
	luz_luna.shadow_enabled = true
	luz_luna.shadow_opacity = 0.8
	# Si no, el cielo dibuja un sol chiquito encima de la luna.
	luz_luna.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	raiz.add_child(luz_luna)

	var shader := Shader.new()
	shader.code = "shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform float fase = 0.5;
void vertex() {
	// La luna va al fondo de todo, como el cielo: la tapan las paredes, el terreno y la cordillera.
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = POSITION.w * 1e-8;
}
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

## Busca el material del cielo y el de la cordillera, para pasarles los colores de cada hora.
func _buscar_cielo_y_cordillera() -> void:
	if not ambiente_mundo or not is_instance_valid(ambiente_mundo):
		ambiente_mundo = buscar_world_environment()
	if ambiente_mundo and ambiente_mundo.environment and ambiente_mundo.environment.sky:
		cielo = ambiente_mundo.environment.sky.sky_material as ShaderMaterial
	var cordillera := get_node_or_null("../Estrellas/Cordillera") as MeshInstance3D
	if cordillera and cordillera.mesh and cordillera.mesh.get_surface_count() > 0:
		# La cordillera no usa las luces de la escena: su luz se la pasa actualizar_iluminacion()
		# (assets/materiales/cordillera.gdshader).
		material_cordillera = cordillera.get_active_material(0) as ShaderMaterial
	terreno = get_node_or_null("../HTerrain") as Node3D
	if terreno and not terreno.has_method("set_shader_param"):
		terreno = null
	materiales_con_bruma.clear()
	for ruta: String in MATERIALES_CON_BRUMA:
		var material := load(ruta) as ShaderMaterial
		if material:
			materiales_con_bruma.append(material)

## Mezcla las dos claves del día entre las que cae la hora actual.
func _clave_del_momento() -> Dictionary:
	var i := 0
	while i < CLAVES.size() - 2 and hora_del_dia >= float(CLAVES[i + 1].h):
		i += 1
	var a: Dictionary = CLAVES[i]
	var b: Dictionary = CLAVES[i + 1]
	var t := smoothstep(float(a.h), float(b.h), hora_del_dia)
	var k := {}
	for campo in a:
		if a[campo] is Color:
			k[campo] = (a[campo] as Color).lerp(b[campo], t)
		else:
			k[campo] = lerpf(a[campo], b[campo], t)
	return k

func actualizar_luna() -> void:
	if not luz_luna or not is_instance_valid(luz_luna):
		return

	fase_lunar = fmod(dias_transcurridos / DIAS_CICLO_LUNAR, 1.0)
	var angulo_luna = -((hora_del_dia - 6.0) / 24.0) * 360.0 - fase_lunar * 360.0
	luz_luna.rotation_degrees = Vector3(angulo_luna, 90.0, 0.0)

	var altura: float = luz_luna.global_transform.basis.z.y
	var iluminada := (1.0 - cos(fase_lunar * TAU)) * 0.5
	var sobre_horizonte := clampf(altura * 3.0, 0.0, 1.0)
	var peso_noche: float = _clave_del_momento().noche
	luz_luna.light_energy = fuerza_luna * iluminada * sobre_horizonte * peso_noche
	# Apagada del todo cuando no alumbra: así no se calculan sus sombras de día.
	luz_luna.visible = luz_luna.light_energy > 0.005

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
	var k := _clave_del_momento()
	brillo_estrellas = k.noche

	# Auto-encontrar Sol si no está asignado
	if not sol or not is_instance_valid(sol):
		sol = buscar_directional_light()
		if sol:
			print("🔧 Sol auto-asignado: ", sol.name)

	# El sol: color y fuerza de la hora. Se apaga del todo cuando ya está bajo el horizonte.
	var direccion_sol := Vector3.UP
	if sol and is_instance_valid(sol):
		direccion_sol = sol.global_transform.basis.z.normalized()
		sol.light_color = k.sol
		sol.light_energy = float(k.sol_e) * smoothstep(-0.07, 0.04, direccion_sol.y)
		sol.visible = sol.light_energy > 0.01

	var energia_luna := 0.0
	var direccion_luna := Vector3.DOWN
	if luz_luna and is_instance_valid(luz_luna):
		energia_luna = luz_luna.light_energy
		direccion_luna = luz_luna.global_transform.basis.z.normalized()

	# Auto-encontrar WorldEnvironment si no está asignado
	if not ambiente_mundo or not is_instance_valid(ambiente_mundo):
		ambiente_mundo = buscar_world_environment()
		if ambiente_mundo:
			print("🔧 WorldEnvironment auto-asignado: ", ambiente_mundo.name)
	if not ambiente_mundo or not is_instance_valid(ambiente_mundo) or not ambiente_mundo.environment:
		return
	var env := ambiente_mundo.environment

	# La luz que llena las sombras: color tierra de día, azul de noche, y algo más con luna.
	env.ambient_light_color = k.amb
	env.ambient_light_energy = float(k.amb_e) + energia_luna * 0.6
	# La niebla toma el color del cielo que tiene detrás (fog_aerial_perspective); este es el de respaldo.
	env.fog_light_color = k.horizonte

	if cielo:
		cielo.set_shader_parameter("color_cenit", k.cenit)
		cielo.set_shader_parameter("color_horizonte", k.horizonte)
		cielo.set_shader_parameter("direccion_sol", direccion_sol)
		cielo.set_shader_parameter("color_sol", k.sol)
		cielo.set_shader_parameter("brillo_sol", 1.0 - float(k.noche))
		cielo.set_shader_parameter("color_resplandor", k.resp)
		cielo.set_shader_parameter("fuerza_resplandor", k.resp_f)
		cielo.set_shader_parameter("direccion_luna", direccion_luna)
		cielo.set_shader_parameter("color_luna", COLOR_LUNA)
		cielo.set_shader_parameter("halo_luna", energia_luna)
		cielo.set_shader_parameter("color_nube", k.nube)
		cielo.set_shader_parameter("color_nube_sombra", k.nube_s)
		# Las nubes derivan despacio hacia el este y la cantidad cambia con los días; de noche se abren.
		var t := float(Time.get_ticks_msec()) * 0.001
		cielo.set_shader_parameter("deriva", Vector2(t * 0.0016, t * 0.0005))
		var cobertura := 0.44 + 0.12 * sin(dias_transcurridos * 2.1 + hora_del_dia * 0.26)
		cielo.set_shader_parameter("cobertura", cobertura * (1.0 - 0.45 * float(k.noche)))
	elif env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		# Respaldo: si falta el cielo nuevo, el cielo simple de Godot con los mismos colores.
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		sky_mat.sky_top_color = k.cenit
		sky_mat.sky_horizon_color = k.horizonte
		sky_mat.ground_horizon_color = k.horizonte
		sky_mat.ground_bottom_color = (k.horizonte as Color).darkened(0.4)

	# El pie de la cordillera se funde con el horizonte de cada hora (antes era un gris claro fijo).
	# La cordillera está siempre al oeste: al atardecer le toca el resplandor del sol, igual que al cielo.
	if material_cordillera:
		var lado_oeste := pow(clampf(-direccion_sol.x * 0.5 + 0.5, 0.0, 1.0), 3.0)
		material_cordillera.set_shader_parameter("color_bruma", (k.horizonte as Color).lerp(k.resp, float(k.resp_f) * lado_oeste))
		# La luz de la cordillera (tanda 6). De día, un sol "de relieve": el de verdad, pero nunca más
		# alto que `altura_sol_relieve` y corrido hacia el norte (-Z), que es por donde anda el sol en la
		# Patagonia, así al mediodía las laderas no quedan todas iguales. La sombra toma el color del
		# cielo. De noche, la luna según su fase; el material cuida que la roca no pase al cielo.
		var relieve := Vector3(direccion_sol.x, minf(direccion_sol.y, altura_sol_relieve), direccion_sol.z - norte_sol_relieve)
		material_cordillera.set_shader_parameter("direccion_relieve", relieve.normalized())
		material_cordillera.set_shader_parameter("direccion_sol", direccion_sol)
		material_cordillera.set_shader_parameter("color_sol", k.sol)
		material_cordillera.set_shader_parameter("fuerza_sol", float(k.sol_e) * smoothstep(-0.07, 0.04, direccion_sol.y))
		material_cordillera.set_shader_parameter("color_sombra", k.cenit)
		material_cordillera.set_shader_parameter("fuerza_sombra", sombra_cordillera)
		material_cordillera.set_shader_parameter("color_luna", COLOR_LUNA)
		material_cordillera.set_shader_parameter("fuerza_luna", energia_luna)
		material_cordillera.set_shader_parameter("direccion_luna", direccion_luna)
		material_cordillera.set_shader_parameter("cielo_noche", k.horizonte)

	# El piso, las hojas y el material mate hacen su propia niebla de lejos (assets/materiales/
	# bruma.gdshaderinc): usan los mismos números que la niebla del ambiente y los colores del
	# cielo de esta hora, más el tope para lo que está alto.
	_pasar_bruma("u_bruma", Vector4(env.fog_depth_begin, env.fog_depth_end, env.fog_depth_curve,
			env.fog_density if env.fog_enabled else 0.0))
	_pasar_bruma("u_bruma_color", k.horizonte)
	_pasar_bruma("u_bruma_resplandor", Color(k.resp, float(k.resp_f)))
	_pasar_bruma("u_bruma_sol", direccion_sol)
	_pasar_bruma("u_bruma_cumbres", bruma_cumbres)
	_pasar_bruma("u_bruma_baja", bruma_baja)
	_pasar_bruma("u_bruma_alta", bruma_alta)

## Le pasa un valor de la bruma de lejos a todo lo que la dibuja: el piso, las hojas y el mate.
func _pasar_bruma(nombre: String, valor: Variant) -> void:
	if terreno:
		terreno.set_shader_param(nombre, valor)
	for material in materiales_con_bruma:
		material.set_shader_parameter(nombre, valor)

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

extends Node

## La intro del juego: un minuto y tres cuartos de planos sobre la voz de Zenón y el tema "¿Deseo o
## intuición?" (audio/intro/). La suma scripts/Historia.gd al mundo cuando empieza una partida nueva,
## antes del cartel de "Enero de 1881", y avisa con `terminada` cuando acaba o la saltean.
##
## Todo se arma por programa, como scripts/Dialogo.gd: la cámara, el filtro de los recuerdos, el libro
## de cuentas, el candil y el resto de la utilería. No toca ninguna escena, y al terminar deja el
## mundo como lo encontró.
##
## Cada plano es una función _plano_<nombre>(t, u, arma): t son los segundos desde que empezó el
## plano, u va de 0 a 1 a lo largo del plano, y con `arma` (su primer cuadro) acomoda lo suyo.
## Se saltea con Espacio, Enter o Esc: la primera vez avisa y la segunda saltea.
##
## Para probarla sin jugar: abrir World.tscn con "-- --intro" (la corre entera, sobre la partida de
## prueba) o con "-- --intro-fotos" (salta por los planos y guarda una foto de cada uno en
## .revision/intro/fotos; con "--intro-fotos=12.5,40" saca solo esos segundos).

signal terminada

const DURA := 105.0
## Cada plano: desde qué segundo, su nombre y cuánto color le queda si es un recuerdo (0: sepia
## pleno; 0,2: lavado). Con -1 es el presente, sin filtro.
const PLANOS := [
	[0.0, "negro", -1.0], [9.0, "mostrador", -1.0], [15.6, "libro", -1.0], [21.4, "frasco", 0.2],
	[27.3, "cruz", 0.0], [33.7, "renglones", -1.0], [38.3, "nevada", 0.0], [44.5, "ceniza", 0.2],
	[48.9, "piedritas", -1.0], [54.5, "hilera", -1.0], [61.5, "vado", 0.2], [65.5, "papel", 0.2],
	[70.0, "llanura", -1.0], [75.8, "de_pie", -1.0], [82.5, "cielo", -1.0], [86.3, "noche_larga", -1.0],
	[90.8, "alba", -1.0], [95.1, "andando", -1.0],
]
## Cuánto dura la bajada a negro al entrar y al salir de un recuerdo, de cada lado del corte.
const BAJADA := 0.3
## La tapa del libro, abierta: pasa de la media vuelta y queda apoyada en el mostrador.
const TAPA_ABIERTA := 190.0
const RAYAS := 18
const PIEDRAS := 6

## El filtro de los recuerdos, una copia a la albúmina de 1879: la placa de colodión veía el azul
## como luz y casi nada del rojo (por eso los cielos salían blancos), el objetivo solo enfocaba el
## centro, y la copia quedaba castaña, con los bordes más oscuros.
const FILTRO := "shader_type canvas_item;
uniform sampler2D pantalla : hint_screen_texture, filter_linear_mipmap;
uniform float color = 0.0;
uniform float reloj = 0.0;

float azar(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float r = length(c * vec2(1.0, 0.8));
	vec3 col = textureLod(pantalla, SCREEN_UV, smoothstep(0.22, 0.7, r) * 3.2).rgb;
	float gris = smoothstep(0.03, 0.9, dot(col, vec3(0.14, 0.36, 0.5)));
	vec3 copia = mix(vec3(0.17, 0.1, 0.06), vec3(0.96, 0.9, 0.76), gris);
	copia = mix(copia, col * vec3(1.04, 1.0, 0.9), color);
	copia *= 1.0 - smoothstep(0.3, 0.95, r) * 0.55;
	copia += (azar(SCREEN_UV * 911.0 + reloj) - 0.5) * 0.07;
	COLOR = vec4(copia, 1.0);
}"

## Una hoja del libro: el papel, los renglones y las columnas de la cuenta, y la tinta encima.
const HOJA := "shader_type spatial;
render_mode specular_disabled;
uniform sampler2D tinta : filter_linear_mipmap, repeat_disable;
// Que parte de la hoja se ve (donde empieza y cuanto abarca): el rotulo de la tapa muestra dos renglones.
uniform vec4 zona = vec4(0.0, 0.0, 1.0, 1.0);
uniform float rayado = 1.0;

float raya(float x, float ancho) {
	return 1.0 - smoothstep(0.0, ancho, abs(x));
}

void fragment() {
	vec2 uv = zona.xy + UV * zona.zw;
	vec3 papel = vec3(0.74, 0.67, 0.52) * (0.95 + 0.05 * sin(uv.x * 31.0 + sin(uv.y * 17.0) * 3.0));
	papel = mix(papel, vec3(0.42, 0.5, 0.56), rayado * 0.3 * raya(fract(uv.y * 36.27 - 0.2) - 0.5, 0.04));
	papel = mix(papel, vec3(0.6, 0.25, 0.2), rayado * 0.45 * (raya(uv.x - 0.17, 0.003) + raya(uv.x - 0.8, 0.003) + raya(uv.x - 0.81, 0.002)));
	ALBEDO = mix(papel, vec3(0.08, 0.055, 0.05), min(texture(tinta, uv).r * 2.0, 0.95));
	ROUGHNESS = 1.0;
}"

## Los mismos renglones, sueltos sobre el cielo de la última noche: suben despacio y se suman a la
## imagen, sin taparla.
const RENGLONES := "shader_type canvas_item;
render_mode blend_add;
uniform sampler2D tinta : filter_linear_mipmap, repeat_enable;
uniform float corrido = 0.0;
uniform float fuerza = 0.35;

void fragment() {
	float t = textureLod(tinta, vec2(UV.x * 0.9 + 0.05, UV.y * 0.36 + corrido), 1.6).r;
	float borde = smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.7, 1.0, UV.y));
	COLOR = vec4(vec3(0.95, 0.87, 0.7) * t * fuerza * borde, 1.0);
}"

var _t := 0.0
var _plano := -1
var _lista := false
## Segundos desde que pidieron saltearla (-1: nadie lo pidió).
var _saltea := -1.0
var _aviso_falta := 0.0
## Con "--intro-fotos": los segundos que hay que fotografiar. La intro no corre: salta de uno a otro.
var _fotos := PackedFloat32Array()

var _mundo: Node
## scenes/player/player.gd (no tiene nombre de clase: por eso va sin tipo).
var _jugador
var _ceniza: Node3D
var _ciclo: CicloDiaNoche
var _env: Environment
var _terreno: Node3D
var _pulperia: Node3D
var _esqueleto: Skeleton3D
var _hueso_mano := -1

var _camara: Camera3D
var _lente: CameraAttributesPractical
var _velo: ColorRect
var _renglones: ColorRect
var _telon: ColorRect
var _aviso: Label
var _musica: AudioStreamPlayer
var _voz: AudioStreamPlayer

var _utileria: Node3D
var _libro: Node3D
var _tapa: Node3D
var _candil: Node3D
var _luz_candil: OmniLight3D
var _llama: MeshInstance3D
var _frasco: Node3D
var _papel: Node3D
var _piedras: Node3D
var _reposo := PackedFloat32Array()
var _corral: Node3D
var _bultos: Node3D
var _copos: GPUParticles3D
var _lumbres: Node3D

# Cómo estaba cada cosa, para dejarla igual.
var _zenon_de := Vector3.ZERO
var _ceniza_de := Transform3D()
var _pitch_de := 0.0
var _saturacion := 1.0
var _exposicion := 1.0
var _nieve_de := [92.0, 175.0]
var _matas_de := {}
var _nevado := false
var _escondidos: Array = []
var _carteles: Array = []
var _luces: Array = []
var _luz_fogon: OmniLight3D
var _fuerza_fogon := 2.4
var _alto_fogon := 0.9
var _humo: GPUParticles3D
var _humo_de := 1.0
var _cielo_modo := Sky.PROCESS_MODE_AUTOMATIC
## El material del agua (es uno solo para el río, el lago y la aguada) y cuánto brillaba antes de
## que un plano se lo cambiara (-1: nadie lo cambió).
var _agua: ShaderMaterial
var _agua_brillo := -1.0
var _sombras: Array[MeshInstance3D] = []
## El fogón de Zenón, en brasas: sin la llama y con poca luz (el recuerdo del frasco).
var _fogon: MeshInstance3D
var _sin_llama: StandardMaterial3D
var _en_brasas := false


func _ready() -> void:
	# La intro corre antes que todo lo demás en cada cuadro. Si corriera después (es la última hija del
	# mundo), al cortar a un plano Zenón, la cámara del juego y las estrellas se acomodarían recién un
	# cuadro más tarde, y en cada corte seco se vería un cuadro con la pose del plano anterior.
	process_priority = -100
	_mundo = get_parent()
	_jugador = _mundo.get_node("Player")
	_armar_capas()
	ManejadorMusica.detener_musica()
	var sonidos := _mundo.get_node_or_null("Sonidos")
	if sonidos != null:
		sonidos.process_mode = Node.PROCESS_MODE_DISABLED
	# El ciclo de día y noche pone su hora y crea la luna un cuadro después de arrancar, y a Ceniza
	# el jugador la busca recién entonces: la pantalla ya está tapada, se espera a que estén.
	for i in 3:
		await get_tree().process_frame
	_preparar()


func _preparar() -> void:
	_ceniza = _mundo.get_node("Ceniza")
	_ciclo = _mundo.get_node("SistemaDiaNoche")
	_env = (_mundo.get_node("Ambiente_Patagonia") as WorldEnvironment).environment
	_terreno = _mundo.get_node("HTerrain")
	_pulperia = _mundo.get_node("Lugares/PulperiaDonCeferino/Cuerpo")
	_esqueleto = _jugador.cuerpo.find_child("Skeleton3D", true, false)
	_hueso_mano = _esqueleto.find_bone("mixamorig_RightHand")
	_zenon_de = _jugador.global_position
	_ceniza_de = _ceniza.global_transform
	_pitch_de = _jugador.pitch
	_saturacion = _env.adjustment_saturation
	_exposicion = _env.tonemap_exposure
	_nieve_de = [_terreno.get_shader_param("u_nieve_desde"), _terreno.get_shader_param("u_nieve_llena")]
	_ciclo.pausar_ciclo()
	# El reflejo del cielo (en el agua y en la luz de ambiente) se rehace de a poco, en unos ocho
	# cuadros. Jugando no se nota, porque el cielo cambia despacio; al cortar del día a la noche, el
	# río quedaba blanco ese rato. Mientras dura la intro se rehace entero en cada cuadro.
	_cielo_modo = _env.sky.process_mode
	_env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	# El humo del fogón de Zenón, más ralo: tal como es en el juego, de noche parece una cortina
	# anaranjada y al alba una columna negra que tapa el fortín.
	_humo = _mundo.get_node("FogonDeZenon/HumoFogon")
	_humo_de = _humo.amount_ratio
	_humo.amount_ratio = 0.45
	_agua = (_mundo.get_node("Agua/RioLimay") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	# Los carteles con el nombre de cada lugar no salen en la intro.
	for cartel: Label3D in _mundo.find_children("*", "Label3D", true, false):
		if cartel.visible:
			cartel.visible = false
			_carteles.append(cartel)
	# Las luces de los fogones tiemblan con el reloj de la compu (scripts/luz_fogon.gd), que al grabar
	# con el Movie Maker corre a otro ritmo que la imagen: acá quedan quietas, y la del fogón de Zenón
	# tiembla con el reloj de la intro.
	for luz: OmniLight3D in _mundo.find_children("LuzFogon*", "OmniLight3D", true, false):
		luz.set_process(false)
		_luces.append(luz)
	_luz_fogon = _mundo.get_node("FogonDeZenon/LuzFogon")
	_fuerza_fogon = float(_luz_fogon.get("_fuerza"))
	# La luz del fogón está a 90 cm del suelo, y el humo que la atraviesa se enciende ahí: de cerca se
	# ve un punto blanco flotando arriba de la llama. En la intro baja hasta la llama.
	_alto_fogon = _luz_fogon.position.y
	_luz_fogon.position.y = 0.4
	# La llama es la tercera parte del modelo del fogón (assets/props/fogon.glb): piedras, brasa y llama.
	_fogon = _mundo.get_node("FogonDeZenon/Fogon/Fogon")
	_sin_llama = StandardMaterial3D.new()
	_sin_llama.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sin_llama.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_camara = Camera3D.new()
	_camara.far = 8000.0
	_lente = CameraAttributesPractical.new()
	_camara.attributes = _lente
	add_child(_camara)
	_armar_utileria()
	for argumento in OS.get_cmdline_user_args():
		if argumento.begins_with("--intro-fotos") and OS.has_feature("editor"):
			var pedidas := argumento.trim_prefix("--intro-fotos").trim_prefix("=")
			for i in PLANOS.size():
				var hasta: float = PLANOS[i + 1][0] if i + 1 < PLANOS.size() else DURA
				if pedidas == "" and i > 0:
					_fotos.append(lerpf(PLANOS[i][0], hasta, 0.5))
			for pedida in pedidas.split(",", false):
				_fotos.append(float(pedida))
	_lista = true
	if not _fotos.is_empty():
		_sacar_fotos()
		return
	_musica = _parlante("res://audio/intro/intro_musica.ogg", &"Musica")
	_voz = _parlante("res://audio/intro/intro_voz.ogg", &"Voz")


## Los dos parlantes cuelgan del manejador de la música y no de la intro: la mezcla dura tres
## segundos más que la imagen, y esa cola tiene que seguir sonando cuando la intro ya se fue.
func _parlante(ruta: String, canal: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(ruta)
	p.bus = canal
	ManejadorMusica.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


func _input(event: InputEvent) -> void:
	if not (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept") or event.is_action_pressed("jump")):
		return
	# Ni la pausa (scripts/Ajustes.gd) ni Zenón reciben estas teclas mientras dura la intro.
	get_viewport().set_input_as_handled()
	if not _lista or _saltea >= 0.0:
		return
	if _aviso.visible:
		_saltea = 0.0
	else:
		_aviso.visible = true
		_aviso_falta = 4.0


func _process(delta: float) -> void:
	if not _lista:
		return
	if _fotos.is_empty():
		_t += delta
		# El reloj de la intro es el del juego, pero un tirón largo (al cargar el mundo, al compilar un
		# shader) le come tiempo, y la imagen quedaría atrasada respecto de la voz: si se aparta, se lo
		# vuelve a poner con lo que lleva sonado. Grabando con el Movie Maker no pasa, y ahí esa cuenta
		# no sirve (el sonido se mezcla cuadro por cuadro, no en tiempo real). Tampoco sirve sin salida
		# de sonido (el driver "Dummy"): ahí el reloj del sonido anda a los saltos.
		if _voz.playing and not OS.has_feature("movie") and AudioServer.get_driver_name() != "Dummy":
			var sonado := _voz.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
			if absf(sonado - _t) > 0.08:
				_t = sonado
	if _aviso.visible:
		_aviso_falta -= delta
		_aviso.visible = _aviso_falta > 0.0
	if _saltea >= 0.0:
		# Al saltearla, la imagen y el sonido se van en medio segundo, no de golpe.
		_saltea += delta
		if _musica != null:
			_musica.volume_db = -50.0 * _saltea / 0.5
			_voz.volume_db = _musica.volume_db
	if _t >= DURA or _saltea >= 0.5:
		_terminar()
		return
	_poner(_t)
	_telon.color.a = maxf(_negro(_t), _saltea / 0.5)


## Pone el mundo como va en ese segundo de la intro.
func _poner(t: float) -> void:
	var i := PLANOS.size() - 1
	while i > 0 and t < float(PLANOS[i][0]):
		i -= 1
	var arma := i != _plano
	if arma:
		_plano = i
		_base()
		_velo.visible = float(PLANOS[i][2]) >= 0.0
		(_velo.material as ShaderMaterial).set_shader_parameter("color", PLANOS[i][2])
	var desde: float = PLANOS[i][0]
	var hasta: float = PLANOS[i + 1][0] if i + 1 < PLANOS.size() else DURA
	call("_plano_" + str(PLANOS[i][1]), t - desde, (t - desde) / (hasta - desde), arma)
	# La luna y su disco se acomodan a la cámara de este cuadro (con el ciclo en pausa no lo hace solo).
	_ciclo.actualizar_luna()
	# El grano de la copia cambia unas catorce veces por segundo, como una película vieja.
	(_velo.material as ShaderMaterial).set_shader_parameter("reloj", floorf(t * 14.0))
	_luz_candil.light_energy = 0.75 * (1.0 + 0.16 * _temblor(t, 0.0))
	_llama.scale = Vector3(1.0, 1.0 + 0.2 * _temblor(t, 1.3), 1.0)
	_luz_fogon.light_energy = _fuerza_fogon * (0.3 if _en_brasas else 1.0 + 0.25 * _temblor(t, 3.0))
	for n in _lumbres.get_child_count():
		(_lumbres.get_child(n) as Node3D).scale = Vector3.ONE * (1.0 + 0.14 * _temblor(t, 2.1 * n))


## Cuánto tapa el telón negro en ese segundo: entero al empezar y al terminar, y una bajada corta
## al entrar y al salir de cada recuerdo. Entre dos planos del presente el corte es seco.
func _negro(t: float) -> float:
	var abre := float(PLANOS[1][0])
	var a := maxf(1.0 - smoothstep(abre, abre + 1.6, t), smoothstep(DURA - 2.4, DURA - 1.0, t))
	for i in range(2, PLANOS.size()):
		if float(PLANOS[i][2]) >= 0.0 or float(PLANOS[i - 1][2]) >= 0.0:
			a = maxf(a, 1.0 - absf(t - float(PLANOS[i][0])) / BAJADA)
	return clampf(a, 0.0, 1.0)


## El temblor de una llama: el mismo de scripts/luz_fogon.gd, pero con el reloj de la intro.
func _temblor(t: float, fase: float) -> float:
	return sin(t * 7.3 + fase) * 0.5 + sin(t * 13.1 + fase * 1.7) * 0.3 + sin(t * 23.7 + fase * 0.6) * 0.2


## Deja todo como antes de cualquier plano: cada plano parte de acá y cambia solo lo suyo.
func _base() -> void:
	for par: Array in _escondidos:
		(par[0] as Node3D).visible = par[1]
	_escondidos.clear()
	for cosa: Node3D in _utileria.get_children():
		cosa.visible = false
	_renglones.visible = false
	_velo.visible = false
	_camara.make_current()
	_foco(0.0)
	_env.adjustment_saturation = _saturacion
	_env.tonemap_exposure = _exposicion
	_en_brasas = false
	_fogon.set_surface_override_material(2, null)
	if _agua_brillo >= 0.0:
		_agua.set_shader_parameter("especular", _agua_brillo)
		_agua_brillo = -1.0
	if _nevado:
		_nevado = false
		_terreno.set_shader_param("u_nieve_desde", _nieve_de[0])
		_terreno.set_shader_param("u_nieve_llena", _nieve_de[1])
		_matas(false)
	for campo: Node3D in _mundo.get_node("Estrellas").find_children("*", "MultiMeshInstance3D", false, false):
		campo.basis = Basis.IDENTITY
	# Zenón, a pie y en su lugar, sin verse; Ceniza, donde la dejó la escena.
	_jugador.titere_poner(_zenon_de, 0.0, false)
	_jugador.cuerpo.visible = false
	_ceniza.global_transform = _ceniza_de


func _terminar() -> void:
	_lista = false
	_base()
	for cartel: Label3D in _carteles:
		if is_instance_valid(cartel):
			cartel.visible = true
	for luz: OmniLight3D in _luces:
		luz.set_process(true)
	_luz_fogon.position.y = _alto_fogon
	_humo.amount_ratio = _humo_de
	_env.sky.process_mode = _cielo_modo
	_jugador.titere = false
	_jugador.cuerpo.visible = true
	_jugador.pitch = _pitch_de
	_jugador.camera.make_current()
	_ciclo.establecer_hora(_ciclo.hora_inicial)
	_ciclo.reanudar_ciclo()
	var sonidos := _mundo.get_node_or_null("Sonidos")
	if sonidos != null:
		sonidos.process_mode = Node.PROCESS_MODE_INHERIT
	if _musica != null and _saltea < 0.0 and _musica.playing and _musica.stream.get_length() - _musica.get_playback_position() < 4.0:
		# Llegó al final: la cola de la mezcla (el viento y la música que se van apagando, tres segundos)
		# sigue sonando debajo del cartel, y el tema del juego entra cuando termina.
		_musica.finished.connect(ManejadorMusica.reproducir_siguiente_cancion)
	else:
		# La saltearon (el sonido ya bajó) o no hay sonido: el tema del juego entra ahora.
		_callar()
		ManejadorMusica.reproducir_siguiente_cancion()
	# El telón de la intro sigue puesto hasta el final de este cuadro: el cartel de la historia sale
	# ya tapado, sin que se vea el mundo en el medio.
	terminada.emit()
	queue_free()


## Si la intro se va sin terminar (se cierra el juego, cambia la escena), su sonido se va con ella.
func _exit_tree() -> void:
	if _lista:
		_callar()


func _callar() -> void:
	for p: AudioStreamPlayer in [_musica, _voz]:
		if p != null and is_instance_valid(p):
			p.queue_free()


## Para revisar los planos sin ver la intro entera: una foto de cada segundo pedido.
func _sacar_fotos() -> void:
	var carpeta := ProjectSettings.globalize_path("res://.revision/intro/fotos")
	DirAccess.make_dir_recursive_absolute(carpeta)
	# El humo de los fogones tarda unos nueve segundos en estar como va a estar en la intro.
	await get_tree().create_timer(10.0).timeout
	for t in _fotos:
		_t = t
		for i in 40:
			await get_tree().process_frame
		var foto := get_viewport().get_texture().get_image()
		foto.resize(1280, int(1280.0 * foto.get_height() / foto.get_width()))
		foto.save_png("%s/%05.1f_%s.png" % [carpeta, t, PLANOS[_plano][1]])
	get_tree().quit()


# ------------------------------------------------------------------ los planos

func _plano_negro(_t_plano: float, _u: float, _arma: bool) -> void:
	pass


## La pulpería de noche, desde el lado de los parroquianos: el libro cerrado y el candil sobre el
## mostrador, y Don Ceferino detrás, en penumbra.
func _plano_mostrador(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_en_la_pulperia()
		_foco(1.2, 0.14)
	_camara_en(_pulp(Vector3(0.72, 1.28, 1.75).lerp(Vector3(0.58, 1.26, 1.42), u)), _pulp(Vector3(0.08, 1.24, 0.1)), 40.0)


## El libro de cerca. La tapa se abre sola.
func _plano_libro(t: float, u: float, arma: bool) -> void:
	if arma:
		_en_la_pulperia(true)
		_foco(0.62)
	_tapa.rotation.z = deg_to_rad(TAPA_ABIERTA) * smoothstep(1.8, 3.0, t)
	var m := _libro.global_transform
	_camara_en(m * Vector3(0.1, 0.5, 0.46).lerp(Vector3(0.06, 0.44, 0.4), u), m * Vector3(-0.03, 0.03, 0.0), 34.0)


## Recuerdo: el frasco de los remedios de la Dolores junto a las brasas, sin pava ni mate.
func _plano_frasco(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_hora(17.7)
		_cielo_de_recuerdo(false)
		_esconder("FogonDeZenon/Pava")
		_esconder("FogonDeZenon/Mate")
		_en_brasas = true
		_fogon.set_surface_override_material(2, _sin_llama)
		_frasco.visible = true
		_foco(0.9)
	var f := _frasco.global_position
	_camara_en(f + Vector3(0.85, 0.2, 0.45).lerp(Vector3(0.7, 0.17, 0.36), u), f + Vector3(-0.05, 0.09, -0.05), 32.0)


## Recuerdo: la cruz del camino entre los coirones, con el cielo cerrado y sin nadie.
func _plano_cruz(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_hora(15.5)
		_cielo_de_recuerdo(true)
	var c := Vector3(-221.3, 0.39, 92.5)
	_camara_en(c + Vector3(4.6, 0.45, 4.2).lerp(Vector3(5.2, 0.5, 3.2), u), c + Vector3(0.0, 1.0, 0.0), 30.0)


## El libro abierto: la cámara baja por la hoja, renglón por renglón.
func _plano_renglones(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_en_la_pulperia(true)
		_tapa.rotation.z = deg_to_rad(TAPA_ABIERTA)
		_foco(0.19, 0.1)
	var m := _libro.global_transform
	var z := lerpf(-0.09, 0.07, u)
	_camara_en(m * Vector3(0.012, 0.21, z + 0.045), m * Vector3(0.012, 0.04, z), 30.0, m.basis * Vector3.FORWARD)


## Recuerdo: el invierno que le mató los animales. La estepa nevada, el corral vacío y unos bultos lejos.
func _plano_nevada(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_hora(13.0)
		_cielo_de_recuerdo(true)
		_nevar()
	_camara_en(_suelo(Vector3(56.0, 1.7, 31.5).lerp(Vector3(58.5, 1.6, 29.5), u)), _suelo(Vector3(73.0, 0.9, 17.0)), 38.0)


## Recuerdo: lo único que le quedó. Ceniza sola en la nieve.
func _plano_ceniza(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_hora(13.0)
		_cielo_de_recuerdo(true)
		_nevar()
		_ceniza.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(110.0)), _suelo(Vector3(61.0, 0.0, 27.0)))
		_foco(8.0, 0.08)
	_camara_en(_suelo(Vector3(55.5, 1.35, 32.5).lerp(Vector3(56.2, 1.35, 31.9), u)), _suelo(Vector3(61.0, 1.15, 27.0)), 28.0)


## El presente, junto al fogón: Zenón saca la cuenta con piedritas, una por cada raya del suelo.
func _plano_piedritas(t: float, u: float, arma: bool) -> void:
	if arma:
		_junto_al_fogon()
		_foco(0.8)
	for i in PIEDRAS:
		_caer(i, t - (0.45 + 0.72 * i))
	var p := _piedras.global_position
	_camara_en(p + Vector3(0.72, 0.36, 0.0).lerp(Vector3(0.66, 0.4, 0.26), u), p + Vector3(0.0, 0.02, 0.14).lerp(Vector3(0.0, 0.02, 0.3), u), 30.0)


## La cámara sube y se abre: las piedritas no alcanzan ni a la mitad de las rayas.
func _plano_hilera(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_junto_al_fogon()
		for i in PIEDRAS:
			_caer(i, 9.0)
	# Sigue el movimiento del plano anterior sin que se note el corte: arranca donde aquel terminó.
	var p := _piedras.global_position
	var s := smoothstep(0.0, 1.0, u)
	var desde := p + Vector3(0.66, 0.4, 0.26).lerp(Vector3(1.1, 3.6, 0.9), s)
	var hacia := p + Vector3(0.0, 0.02, 0.3).lerp(Vector3(-0.4, 0.0, 0.55), s)
	_foco(desde.distance_to(hacia), 0.12 * (1.0 - s))
	_camara_en(desde, hacia, lerpf(30.0, 46.0, s))


## Recuerdo: Zenón vadea el Limay, solo.
func _plano_vado(_t_plano: float, _u: float, arma: bool) -> void:
	if arma:
		_hora(11.0)
		_cielo_de_recuerdo(false)
		_zenon_en(Vector3(-515.0, 0.0, -46.0), PI, true)
		_jugador.titere_anda = true
		# Con el cielo casi blanco y el agua espejándolo, el río quedaba como una sábana clara y no se
		# entendía que Ceniza iba por el agua: en este plano el agua brilla menos y muestra su color.
		_agua_brillo = float(_agua.get_shader_parameter("especular"))
		_agua.set_shader_parameter("especular", 0.22)
	var ojo := Vector3(-487.0, maxf(Historia.altura_suelo(-487.0, -28.0), -3.17) + 1.2, -28.0)
	_camara_en(ojo, _jugador.global_position + Vector3(0.0, 0.2, 2.0), 20.0)


## Recuerdo: el recado en la mano, un papel doblado con su lacre, y la posta borrosa detrás.
func _plano_papel(_t_plano: float, u: float, arma: bool) -> void:
	var frente := Vector3(7.5, 0.0, 14.0).normalized()
	if arma:
		_hora(10.5)
		_cielo_de_recuerdo(false)
		_zenon_en(Vector3(7.5, 0.0, -206.0), atan2(-frente.x, -frente.z))
		_papel.visible = true
		_foco(0.5, 0.14)
	# El papel cuelga del puño: sigue a la mano en cada cuadro (el brazo se mece) y le da la cara a la cámara.
	var muneca := (_esqueleto.global_transform * _esqueleto.get_bone_global_pose(_hueso_mano)).origin
	var derecha := frente.cross(Vector3.UP)
	var cara := (frente * 0.92 + derecha * 0.4).normalized()
	# (El modelo está acostado: su largo es X y su cara de arriba, la del lacre, es Y.)
	_papel.global_transform = Transform3D(Basis(Vector3.UP, cara, Vector3.UP.cross(cara)) * Basis(Vector3.UP, 0.25),
			muneca + Vector3(0.0, -0.215, 0.0) + cara * 0.02)
	# Casi de frente: de costado quedaba en el medio del cuadro una marca oscura que la textura tiene en el dorso de la mano.
	_camara_en(muneca + frente * lerpf(0.62, 0.54, u) + derecha * 0.1 + Vector3(0.0, -0.11, 0.0), muneca + Vector3(0.0, -0.17, 0.0), 34.0)


## La llanura de noche, desde lo alto: la lumbre del fortín, la de los toldos y la de la estancia,
## cada una en su lado, y el fogón de Zenón aparte de las tres.
func _plano_llanura(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_hora(23.5)
		_lumbres.visible = true
		# La posta y el hito no son de ningún bando: sus luces confunden.
		_esconder("Lugares/PostaDelCoiron/LuzFogon")
		_esconder("Lugares/HitoDelHumo/LuzBrasa")
		_esconder("Lugares/HitoDelHumo/Humo")
		# Con la luna sola la llanura casi no se distingue: se abre un poco el diafragma.
		_env.tonemap_exposure = _exposicion * 1.5
	_camara_en(Vector3(290.0, 124.0, -366.0).lerp(Vector3(280.0, 116.0, -350.0), u), Vector3(-28.0, 80.0, 6.0), 52.0)


## Zenón de pie, de espaldas a su fuego: la cara le queda en sombra.
func _plano_de_pie(_t_plano: float, u: float, arma: bool) -> void:
	var fuego := Vector3(-6.5, 0.0, -1.0)
	var hacia := Vector3(0.78, 0.0, 0.62)
	var costado := hacia.cross(Vector3.UP)
	if arma:
		_hora(23.5)
		_zenon_en(fuego + hacia * 1.4 + costado * 0.75, atan2(-hacia.x, -hacia.z))
		_foco(3.2, 0.06)
	_camara_en(_suelo(fuego + hacia * lerpf(4.9, 4.3, u) + costado * 0.5 + Vector3(0.0, 1.3, 0.0)),
			_suelo(fuego + hacia * 1.4 + costado * 0.55 + Vector3(0.0, 1.28, 0.0)), 35.0)


## El cielo estrellado sobre la cordillera: la cámara sube del horizonte a las estrellas.
func _plano_cielo(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_hora(23.5)
	_mirar_al_oeste(lerpf(3.0, 24.0, smoothstep(0.0, 1.0, u)))


## La noche entera en unos segundos: giran las estrellas, baja la luna y aclara. Encima, los
## renglones de la cuenta.
func _plano_noche_larga(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		_renglones.visible = true
	_hora(fposmod(23.5 + 6.1 * u, 24.0))
	_mirar_al_oeste(lerpf(24.0, 27.0, u))
	var material := _renglones.material as ShaderMaterial
	material.set_shader_parameter("corrido", 0.1 + u * 0.12)
	material.set_shader_parameter("fuerza", 0.35 * smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.82, 1.0, u)))
	# Las estrellas giran alrededor del polo sur del cielo, que acá queda al sur y a media altura, en
	# el mismo sentido que el sol y la luna: las del oeste bajan hacia la cordillera.
	var giro := Basis(Vector3(0.0, 0.643, 0.766), deg_to_rad(20.0) * u)
	for campo: Node3D in _mundo.get_node("Estrellas").find_children("*", "MultiMeshInstance3D", false, false):
		campo.basis = giro


## El alba. De lejos y con lente largo: Zenón monta a Ceniza, y al fondo el fortín y la pulpería.
func _plano_alba(t: float, u: float, arma: bool) -> void:
	if arma:
		_hora(5.6)
		# Con el lente largo, las últimas estrellas se ven como manchas grandes.
		_esconder("Estrellas/CampoEstrellas")
		_esconder("Estrellas/ViaLactea")
		# Y un guanaco que pase cerca de la cámara tapa media pantalla: los que andan por acá no salen.
		for bicho in _mundo.get_node("GrassMMI").get_children():
			if bicho is Node3D and not bicho is MultiMeshInstance3D and (bicho as Node3D).global_position.distance_to(Vector3(-40.0, 0.0, -28.0)) < 75.0:
				_escondidos.append([bicho, (bicho as Node3D).visible])
				(bicho as Node3D).visible = false
		_ceniza.global_transform = _ceniza_al_alba()
		var izquierda := _ceniza.global_transform.basis.x
		_zenon_en(_ceniza.global_position + izquierda * 1.05, atan2(izquierda.x, izquierda.z))
	if t >= 1.1 and not _jugador.montado:
		_jugador.montar()
	_camara_en(Vector3(-40.0, 2.2, -28.0).lerp(Vector3(-38.5, 2.2, -27.0), u), Vector3(215.0, 3.0, 157.0), 14.0)


## Ya montado, al paso hacia la pulpería, con la cámara del juego detrás. Sale el sol.
func _plano_andando(_t_plano: float, u: float, arma: bool) -> void:
	if arma:
		var ceniza := _ceniza_al_alba()
		_zenon_en(ceniza.origin, ceniza.basis.get_euler().y + PI, true)
		_jugador.titere_anda = true
		_jugador.pitch = deg_to_rad(-9.0)
		_jugador.camera.make_current()
	_hora(lerpf(5.6, 6.0, u))


# ------------------------------------------------------------------ lo que usan los planos

func _hora(hora: float) -> void:
	_ciclo.establecer_hora(hora)


func _camara_en(desde: Vector3, hacia: Vector3, fov: float, arriba := Vector3.UP) -> void:
	_camara.fov = fov
	_camara.look_at_from_position(desde, hacia, arriba)


## El foco corto: nítido a esos metros, y borroso lo que queda bastante más cerca o más lejos.
## Con 0 se ve todo nítido.
func _foco(metros: float, cuanto := 0.12) -> void:
	_lente.dof_blur_near_enabled = metros > 0.0
	_lente.dof_blur_far_enabled = metros > 0.0
	_lente.dof_blur_near_distance = metros * 0.7
	_lente.dof_blur_near_transition = metros * 0.4
	_lente.dof_blur_far_distance = metros * 1.3
	_lente.dof_blur_far_transition = metros * 1.5
	_lente.dof_blur_amount = cuanto


## Un punto dicho como lo ve la pulpería (su mostrador corre a lo largo de X; los parroquianos
## quedan del lado +Z) pasado al mundo.
func _pulp(local: Vector3) -> Vector3:
	return _pulperia.global_transform * local


## Ese punto, apoyado en el suelo: su Y pasa a ser la altura sobre el piso.
func _suelo(p: Vector3) -> Vector3:
	return Vector3(p.x, Historia.altura_suelo(p.x, p.z) + p.y, p.z)


func _esconder(ruta: String) -> void:
	var nodo := _mundo.get_node_or_null(ruta) as Node3D
	if nodo != null:
		_escondidos.append([nodo, nodo.visible])
		nodo.visible = false


func _zenon_en(lugar: Vector3, rumbo: float, a_caballo := false) -> void:
	_jugador.titere_poner(lugar, rumbo, a_caballo)
	_jugador.cuerpo.visible = true


## Los planos del libro: de noche, con el candil por toda luz y los colores apagados.
## En los planos `de_cerca` el candil no entra en cuadro y su luz se sube, como si alguien lo levantara:
## desde la llama, al ras del mostrador, el canto de las hojas le hace sombra a la tapa abierta.
func _en_la_pulperia(de_cerca := false) -> void:
	_luz_candil.position = Vector3(-0.15, 0.36, 0.0) if de_cerca else Vector3(0.0, 0.11, 0.0)
	_hora(23.5)
	_env.adjustment_saturation = 0.7
	_env.ambient_light_energy = 0.22
	# El recado que hay de adorno en el mostrador le deja su lugar al libro.
	_esconder("Lugares/PulperiaDonCeferino/Cuerpo/Recado")
	_libro.visible = true
	_candil.visible = true
	_tapa.rotation.z = 0.0


func _junto_al_fogon() -> void:
	_hora(23.5)
	_piedras.visible = true
	_zenon_en(_piedras.global_position + Vector3(0.0, 0.0, -0.65), PI)


## Una piedrita cae en su raya: `desde` son los segundos desde que la soltaron (negativo: todavía no).
func _caer(i: int, desde: float) -> void:
	var piedra := _piedras.get_child(RAYAS + i) as Node3D
	piedra.visible = desde >= 0.0
	var alto := 0.0
	if desde < 0.26:
		alto = 0.45 * (1.0 - pow(desde / 0.26, 2.0))
	elif desde < 0.42:
		var s := (desde - 0.26) / 0.16
		alto = 0.2 * s * (1.0 - s)
	piedra.position.y = _reposo[i] + alto
	# Su sombra en el suelo aparece cuando la piedra ya está por tocarlo.
	_sombras[i].visible = desde >= 0.0 and alto < 0.06


## El cielo de los recuerdos, casi blanco, como salía en las copias de entonces. Con `cerrado`,
## además, nublado entero y el sol apenas. La hora siguiente que se ponga lo deja como siempre.
func _cielo_de_recuerdo(cerrado: bool) -> void:
	var blanco := Color(0.9, 0.9, 0.86)
	var cielo := _ciclo.cielo
	if cielo != null:
		for nombre: String in ["color_cenit", "color_horizonte", "color_nube", "color_nube_sombra"]:
			cielo.set_shader_parameter(nombre, (cielo.get_shader_parameter(nombre) as Color).lerp(blanco, 0.75))
		if cerrado:
			cielo.set_shader_parameter("cobertura", 1.0)
			cielo.set_shader_parameter("brillo_sol", 0.0)
	_env.fog_light_color = _env.fog_light_color.lerp(blanco, 0.75)
	_ciclo._pasar_bruma("u_bruma_color", _env.fog_light_color)
	if cerrado and _ciclo.sol != null:
		_ciclo.sol.light_energy *= 0.35
		_env.ambient_light_energy *= 1.5


func _nevar() -> void:
	_nevado = true
	_terreno.set_shader_param("u_nieve_desde", -60.0)
	_terreno.set_shader_param("u_nieve_llena", 10.0)
	_matas(true)
	_corral.visible = true
	_bultos.visible = true
	_copos.visible = true
	_copos.restart()


## Las matas, cargadas de nieve o como son.
func _matas(nevadas: bool) -> void:
	for grilla in _mundo.get_node("GrassMMI").get_children():
		var material: ShaderMaterial = null
		if grilla is MultiMeshInstance3D:
			material = (grilla as MultiMeshInstance3D).material_override as ShaderMaterial
		if material == null:
			continue
		if not _matas_de.has(material):
			_matas_de[material] = [material.get_shader_parameter("color_a"), material.get_shader_parameter("color_b")]
		material.set_shader_parameter("color_a", Color(0.8, 0.8, 0.76) if nevadas else _matas_de[material][0])
		material.set_shader_parameter("color_b", Color(0.66, 0.66, 0.6) if nevadas else _matas_de[material][1])


func _mirar_al_oeste(grados: float) -> void:
	var ojo := _suelo(Vector3(-4.0, 1.6, 2.5))
	var alza := deg_to_rad(grados)
	_camara_en(ojo, ojo + Vector3(-cos(alza), sin(alza), 0.12 * cos(alza)), 50.0)


## Dónde espera Ceniza al alba: en su lugar de siempre, pero mirando hacia la pulpería.
func _ceniza_al_alba() -> Transform3D:
	var hacia := Vector3(202.0, 0.0, 156.0) - _ceniza_de.origin
	return Transform3D(Basis(Vector3.UP, atan2(hacia.x, hacia.z)), _ceniza_de.origin)


# ------------------------------------------------------------------ capas y utilería

func _armar_capas() -> void:
	_velo = _capa(40)
	var filtro := ShaderMaterial.new()
	filtro.shader = _shader(FILTRO)
	_velo.material = filtro
	_velo.hide()
	_renglones = _capa(41)
	var sueltos := ShaderMaterial.new()
	sueltos.shader = _shader(RENGLONES)
	_renglones.material = sueltos
	_renglones.hide()
	# El telón queda por debajo del de los carteles (scripts/Dialogo.gd, capa 50), que sale encima al terminar.
	_telon = _capa(45)
	_telon.color = Color.BLACK
	_aviso = Label.new()
	_aviso.text = "Espacio, Enter o Esc otra vez: saltear"
	_aviso.add_theme_font_size_override("font_size", 18)
	_aviso.add_theme_color_override("font_color", Color(0.78, 0.7, 0.55, 0.85))
	_aviso.hide()
	_telon.get_parent().add_child(_aviso)
	_aviso.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 28)


func _capa(numero: int) -> ColorRect:
	var capa := CanvasLayer.new()
	capa.layer = numero
	add_child(capa)
	var cuadro := ColorRect.new()
	cuadro.set_anchors_preset(Control.PRESET_FULL_RECT)
	cuadro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(cuadro)
	return cuadro


func _shader(codigo: String) -> Shader:
	var shader := Shader.new()
	shader.code = codigo
	return shader


func _armar_utileria() -> void:
	_utileria = Node3D.new()
	add_child(_utileria)
	var tinta := ImageTexture.create_from_image(_dibujar_tinta())
	(_renglones.material as ShaderMaterial).set_shader_parameter("tinta", tinta)
	_armar_libro(tinta)
	_armar_candil()
	_armar_frasco()
	_armar_piedras()
	_armar_nevada()
	_armar_lumbres()
	# El recado es el mismo papel doblado con lacre que hay sobre el mostrador y en la posta.
	_papel = (load("res://assets/props/recado.glb") as PackedScene).instantiate() as Node3D
	_utileria.add_child(_papel)


## Una pieza de utilería: una forma simple de un color liso y mate.
func _pieza(padre: Node3D, malla: PrimitiveMesh, color: Color, lugar := Vector3.ZERO, material: Material = null) -> MeshInstance3D:
	if material == null:
		var liso := StandardMaterial3D.new()
		liso.albedo_color = color
		liso.roughness = 1.0
		liso.metallic_specular = 0.0
		material = liso
	malla.material = material
	var nodo := MeshInstance3D.new()
	nodo.mesh = malla
	nodo.position = lugar
	padre.add_child(nodo)
	return nodo


func _caja(x: float, y: float, z: float) -> BoxMesh:
	var malla := BoxMesh.new()
	malla.size = Vector3(x, y, z)
	return malla


func _cilindro(radio: float, alto: float) -> CylinderMesh:
	var malla := CylinderMesh.new()
	malla.top_radius = radio
	malla.bottom_radius = radio
	malla.height = alto
	malla.radial_segments = 14
	malla.rings = 1
	return malla


func _bola(radio: float, alto: float) -> SphereMesh:
	var malla := SphereMesh.new()
	malla.radius = radio
	malla.height = alto
	malla.radial_segments = 12
	malla.rings = 6
	return malla


## La tinta de una hoja del libro: renglones de garabatos que nunca se llegan a leer, cada uno con
## su fecha, su concepto y su importe, y alguno tachado. Blanco donde hay tinta. La misma imagen
## sirve para la hoja y para los renglones sueltos sobre el cielo.
func _dibujar_tinta() -> Image:
	var azar := RandomNumberGenerator.new()
	azar.seed = 1881
	var imagen := Image.create(1536, 2176, false, Image.FORMAT_L8)
	for fila in range(2, 35):
		if azar.randf() < 0.07:
			continue
		var y := fila * 60
		_garabato(imagen, azar, 88.0, y, azar.randf_range(96.0, 140.0))
		var x := 300.0
		var fin := azar.randf_range(720.0, 1140.0)
		while x < fin:
			var largo := azar.randf_range(52.0, 176.0)
			_garabato(imagen, azar, x, y, largo)
			x += largo + azar.randf_range(24.0, 44.0)
		_garabato(imagen, azar, azar.randf_range(1268.0, 1320.0), y, azar.randf_range(68.0, 124.0))
		if azar.randf() < 0.1:
			imagen.fill_rect(Rect2i(292, y - 14, int(fin) - 260, 5), Color.WHITE)
	# Corrida, como tinta vieja: se achica y se vuelve a agrandar.
	imagen.resize(768, 1088, Image.INTERPOLATE_LANCZOS)
	imagen.resize(1536, 2176, Image.INTERPOLATE_CUBIC)
	imagen.generate_mipmaps()
	return imagen


## Una palabra en cursiva: un trazo seguido que sube y baja, con algún palo alto o bajo.
func _garabato(imagen: Image, azar: RandomNumberGenerator, x: float, y: int, largo: float) -> void:
	var fase := azar.randf() * TAU
	var onda := azar.randf_range(0.16, 0.26)
	var alto := azar.randf_range(5.0, 9.0)
	for i in int(largo):
		var de := int(y - 14.0 + sin(fase + i * onda) * alto + sin(i * onda * 2.7) * 2.0)
		imagen.fill_rect(Rect2i(int(x) + i, de, 2, 5), Color.WHITE)
		if azar.randf() < 0.026:
			# El palo va inclinado, como la letra: seis tramos, cada uno un poco más a la derecha.
			var sube := azar.randf() < 0.65
			for tramo in azar.randi_range(4, 7):
				imagen.fill_rect(Rect2i(int(x) + i + (tramo if sube else -tramo), de + (-5 * tramo if sube else 5 * tramo), 3, 6), Color.WHITE)


## El libro de cuentas de Don Ceferino. La tapa gira sobre el lomo (el nodo _tapa es la bisagra).
func _armar_libro(tinta: Texture2D) -> void:
	var cuero := Color(0.2, 0.11, 0.08)
	var papel := Color(0.74, 0.67, 0.52)
	_libro = Node3D.new()
	_utileria.add_child(_libro)
	_libro.global_transform = Transform3D(_pulperia.global_transform.basis.orthonormalized() * Basis(Vector3.UP, deg_to_rad(9.0)),
			_pulp(Vector3(0.02, 1.095, 0.5)))
	_pieza(_libro, _caja(0.23, 0.006, 0.32), cuero, Vector3(0.0, 0.003, 0.0))
	_pieza(_libro, _caja(0.012, 0.04, 0.32), cuero, Vector3(-0.115, 0.02, 0.0))
	_pieza(_libro, _caja(0.215, 0.03, 0.308), papel, Vector3(0.002, 0.021, 0.0))
	var hoja := PlaneMesh.new()
	hoja.size = Vector2(0.213, 0.306)
	var escrita := ShaderMaterial.new()
	escrita.shader = _shader(HOJA)
	escrita.set_shader_parameter("tinta", tinta)
	_pieza(_libro, hoja, papel, Vector3(0.002, 0.0365, 0.0), escrita)
	_tapa = Node3D.new()
	_tapa.position = Vector3(-0.115, 0.039, 0.0)
	_libro.add_child(_tapa)
	_pieza(_tapa, _caja(0.232, 0.006, 0.322), cuero, Vector3(0.116, 0.003, 0.0))
	# Por dentro, la guarda de papel; por fuera, el lomo de cuero más oscuro y el rótulo con dos renglones.
	_pieza(_tapa, _caja(0.214, 0.001, 0.304), papel.darkened(0.12), Vector3(0.118, -0.0005, 0.0))
	_pieza(_tapa, _caja(0.045, 0.0064, 0.3224), cuero.darkened(0.45), Vector3(0.0225, 0.003, 0.0))
	var rotulo := PlaneMesh.new()
	rotulo.size = Vector2(0.11, 0.05)
	var titulo := ShaderMaterial.new()
	titulo.shader = escrita.shader
	titulo.set_shader_parameter("tinta", tinta)
	titulo.set_shader_parameter("zona", Vector4(0.2, 0.112, 0.2, 0.064))
	titulo.set_shader_parameter("rayado", 0.0)
	_pieza(_tapa, rotulo, papel, Vector3(0.13, 0.0064, -0.06), titulo)


## El candil del mostrador: un plato, el depósito del sebo y la llama, con su luz.
func _armar_candil() -> void:
	var hierro := Color(0.1, 0.085, 0.07)
	_candil = Node3D.new()
	_utileria.add_child(_candil)
	_candil.global_position = _pulp(Vector3(0.34, 1.095, 0.38))
	_pieza(_candil, _cilindro(0.05, 0.012), hierro, Vector3(0.0, 0.006, 0.0))
	_pieza(_candil, _bola(0.036, 0.05), hierro.lightened(0.06), Vector3(0.0, 0.035, 0.0))
	_pieza(_candil, _cilindro(0.006, 0.02), hierro, Vector3(0.0, 0.066, 0.0))
	_pieza(_candil, _caja(0.05, 0.008, 0.008), hierro, Vector3(-0.058, 0.04, 0.0))
	var fuego := StandardMaterial3D.new()
	fuego.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fuego.albedo_color = Color(2.6, 1.7, 0.7)
	_llama = _pieza(_candil, _bola(0.009, 0.042), Color.WHITE, Vector3(0.0, 0.094, 0.0), fuego)
	_llama.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_luz_candil = OmniLight3D.new()
	_luz_candil.light_color = Color(1.0, 0.62, 0.3)
	# Alcanza al libro y poco más: a Don Ceferino le llega apenas.
	_luz_candil.omni_range = 1.6
	_luz_candil.omni_attenuation = 1.5
	_luz_candil.shadow_enabled = true
	_candil.add_child(_luz_candil)


## El frasco de los remedios: vidrio verde, con su corcho y un resto adentro.
func _armar_frasco() -> void:
	var vidrio := StandardMaterial3D.new()
	vidrio.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vidrio.albedo_color = Color(0.08, 0.4, 0.2, 0.78)
	vidrio.roughness = 0.25
	_frasco = Node3D.new()
	_utileria.add_child(_frasco)
	_frasco.global_position = _suelo(Vector3(-5.92, 0.0, -0.55))
	_pieza(_frasco, _cilindro(0.027, 0.04), Color(0.07, 0.16, 0.1), Vector3(0.0, 0.022, 0.0))
	_pieza(_frasco, _cilindro(0.034, 0.105), Color.WHITE, Vector3(0.0, 0.0525, 0.0), vidrio)
	_pieza(_frasco, _bola(0.034, 0.04), Color.WHITE, Vector3(0.0, 0.105, 0.0), vidrio)
	_pieza(_frasco, _cilindro(0.013, 0.04), Color.WHITE, Vector3(0.0, 0.135, 0.0), vidrio)
	_pieza(_frasco, _cilindro(0.012, 0.018), Color(0.5, 0.38, 0.24), Vector3(0.0, 0.16, 0.0))


## La cuenta en el suelo: una hilera de rayas hechas con el facón, y las piedritas que caen en las
## primeras. Los hijos del nodo son primero las rayas y después las piedras.
func _armar_piedras() -> void:
	var azar := RandomNumberGenerator.new()
	azar.seed = 180
	# Una raya es un surco hecho con la punta del facón: angosto, oscuro y que se pierde en las puntas.
	var puntas := Gradient.new()
	puntas.offsets = PackedFloat32Array([0.0, 0.22, 0.8, 1.0])
	puntas.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var a_lo_largo := GradientTexture1D.new()
	a_lo_largo.gradient = puntas
	var tierra := StandardMaterial3D.new()
	tierra.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tierra.albedo_color = Color(0.05, 0.035, 0.025, 0.9)
	tierra.albedo_texture = a_lo_largo
	tierra.roughness = 1.0
	# Y debajo de cada piedra, una mancha oscura: el fogón no hace sombras, y sin ella flotan.
	var apoyo := StandardMaterial3D.new()
	apoyo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	apoyo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	apoyo.albedo_color = Color(0.0, 0.0, 0.0, 0.55)
	apoyo.albedo_texture = _punto()
	_piedras = Node3D.new()
	_utileria.add_child(_piedras)
	_piedras.global_position = _suelo(Vector3(-5.25, 0.0, -1.62))
	var base := _piedras.global_position
	var corridas := PackedFloat32Array()
	for i in RAYAS + PIEDRAS:
		var z := 0.07 * (i if i < RAYAS else i - RAYAS)
		var piso := Historia.altura_suelo(base.x, base.z + z) - base.y
		if i < RAYAS:
			var surco := PlaneMesh.new()
			surco.size = Vector2(azar.randf_range(0.075, 0.105), azar.randf_range(0.006, 0.009))
			corridas.append(azar.randf_range(-0.008, 0.008))
			var raya := _pieza(_piedras, surco, Color.WHITE, Vector3(corridas[i], piso + 0.004, z), tierra)
			raya.rotation.y = azar.randf_range(-0.22, 0.22)
		else:
			# Un canto rodado chato, del gris de los que hay en el suelo. Las piedras hacen su propia hilera
			# al pie de las rayas, sin tocarlas: encima de la raya, o en su punta, parecían fósforos.
			var radio := azar.randf_range(0.015, 0.021)
			var gris := azar.randf_range(0.5, 0.64)
			var piedra := _pieza(_piedras, _bola(radio, radio * 0.9), Color(gris, gris * 0.95, gris * 0.88),
					Vector3(corridas[i - RAYAS] + 0.105 + azar.randf_range(-0.006, 0.006), piso + radio * 0.4, z))
			piedra.rotation = Vector3(azar.randf_range(-0.15, 0.15), azar.randf() * TAU, azar.randf_range(-0.15, 0.15))
			_reposo.append(piedra.position.y)
	for i in PIEDRAS:
		var piedra := _piedras.get_child(RAYAS + i) as MeshInstance3D
		var mancha := PlaneMesh.new()
		mancha.size = Vector2.ONE * (piedra.mesh as SphereMesh).radius * 3.2
		_sombras.append(_pieza(_piedras, mancha, Color.WHITE, Vector3(piedra.position.x, _reposo[i] - (piedra.mesh as SphereMesh).radius * 0.4 + 0.006, piedra.position.z), apoyo))


## Lo que hace falta para el recuerdo del invierno: un corral vacío, unos bultos tapados de nieve
## a lo lejos (la hacienda muerta) y los copos.
func _armar_nevada() -> void:
	var centro := _suelo(Vector3(72.0, 0.0, 18.0))
	_corral = (load("res://assets/cercos/corral.glb") as PackedScene).instantiate() as Node3D
	_utileria.add_child(_corral)
	_corral.global_position = centro
	_bultos = Node3D.new()
	_utileria.add_child(_bultos)
	var azar := RandomNumberGenerator.new()
	azar.seed = 7
	for lugar: Vector2 in [Vector2(69.5, 5), Vector2(86.5, 20.5), Vector2(82.5, 2.5), Vector2(97.5, 18.5), Vector2(86, -13), Vector2(101, 0.5), Vector2(105, -12.5)]:
		# Un animal echado de costado: el lomo y la cabeza oscuros, la nieve que le cayó encima y una
		# pata tiesa que asoma. De lejos tiene que leerse como un animal, no como un bulto cualquiera.
		var cuero := Color(0.22, 0.17, 0.13)
		var bulto := _pieza(_bultos, _bola(1.0, 2.0), cuero, _suelo(Vector3(lugar.x, 0.12, lugar.y)))
		bulto.scale = Vector3(azar.randf_range(1.2, 1.5), azar.randf_range(0.42, 0.5), azar.randf_range(0.55, 0.7))
		bulto.rotation.y = azar.randf() * TAU
		_pieza(bulto, _bola(0.34, 0.6), cuero, Vector3(1.12, 0.1, 0.12))
		_pieza(bulto, _bola(1.05, 1.8), Color(0.82, 0.84, 0.86), Vector3(-0.04, 0.12, -0.04))
		var pata := _pieza(bulto, _caja(0.07, 1.5, 0.12), cuero, Vector3(azar.randf_range(-0.5, 0.4), 0.6, 0.55))
		pata.rotation = Vector3(azar.randf_range(0.5, 0.9), 0.0, azar.randf_range(-0.3, 0.3))
	var caida := ParticleProcessMaterial.new()
	caida.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	caida.emission_box_extents = Vector3(24.0, 0.5, 24.0)
	caida.direction = Vector3(0.35, -1.0, 0.1)
	caida.spread = 12.0
	caida.initial_velocity_min = 1.0
	caida.initial_velocity_max = 1.8
	caida.gravity = Vector3(0.3, -0.15, 0.0)
	caida.scale_min = 0.6
	caida.scale_max = 1.4
	var blanco := StandardMaterial3D.new()
	blanco.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blanco.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	blanco.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blanco.albedo_color = Color(0.95, 0.95, 0.93)
	blanco.albedo_texture = _punto()
	var copo := QuadMesh.new()
	copo.size = Vector2(0.05, 0.05)
	copo.material = blanco
	_copos = GPUParticles3D.new()
	_copos.amount = 1400
	_copos.lifetime = 7.0
	_copos.preprocess = 7.0
	_copos.process_material = caida
	_copos.draw_pass_1 = copo
	_copos.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_copos.visibility_aabb = AABB(Vector3(-40.0, -14.0, -40.0), Vector3(80.0, 16.0, 80.0))
	_utileria.add_child(_copos)
	_copos.global_position = centro + Vector3(-8.0, 9.0, 8.0)


## Un punto blanco que se apaga hacia el borde: un copo de nieve, un resplandor.
func _punto() -> GradientTexture2D:
	# Un centro chico y fuerte y un halo ancho y flojo.
	var degrade := Gradient.new()
	degrade.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	degrade.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.3), Color(1.0, 1.0, 1.0, 0.0)])
	var punto := GradientTexture2D.new()
	punto.gradient = degrade
	punto.fill = GradientTexture2D.FILL_RADIAL
	punto.fill_from = Vector2(0.5, 0.5)
	punto.fill_to = Vector2(1.0, 0.5)
	return punto


## Las lumbres que se ven de lejos en la llanura: un resplandor en cada fuego, que no alumbra y al
## que la niebla no tapa (las luces de verdad, a esa distancia, no se ven).
func _armar_lumbres() -> void:
	var resplandor := StandardMaterial3D.new()
	resplandor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	resplandor.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	resplandor.billboard_keep_scale = true
	resplandor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	resplandor.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	resplandor.albedo_texture = _punto()
	# Color de brasa y sin pasarse de 1: más fuerte, el brillo del ambiente las inflaba y parecían soles.
	resplandor.albedo_color = Color(1.0, 0.5, 0.18)
	resplandor.disable_fog = true
	resplandor.no_depth_test = true
	_lumbres = Node3D.new()
	_utileria.add_child(_lumbres)
	# [el nodo donde está el fuego, cuántos metros mide el resplandor, cuánto más arriba va]
	for dato: Array in [["FogonDeZenon/LuzFogon", 7.0, 0.0], ["Lugares/FortinDelSalitral/Cuerpo/Fortin/LuzFogon", 9.0, 0.0],
			["Lugares/FortinDelSalitral/Cuerpo/Fortin/Mangrullo", 5.0, 10.5], ["Lugares/TolderiaPainefil/LuzFogonCentral", 13.0, 0.0],
			["Lugares/TolderiaPainefil/LuzFogon1", 9.0, 0.0], ["Lugares/TolderiaPainefil/LuzFogon4", 9.0, 0.0],
			["Lugares/EstanciaDonRufino/Cuerpo", 10.0, 2.0]]:
		var fuego := _mundo.get_node_or_null(str(dato[0])) as Node3D
		if fuego == null:
			continue
		var cuadro := QuadMesh.new()
		cuadro.size = Vector2.ONE * float(dato[1])
		var lumbre := _pieza(_lumbres, cuadro, Color.WHITE, fuego.global_position + Vector3(0.0, float(dato[2]), 0.0), resplandor)
		# El cuadro gira hacia la cámara recién al dibujarse: sin este margen, en el borde de la imagen se descarta.
		lumbre.extra_cull_margin = float(dato[1])

extends Node

## Todo lo que suena en la estepa además de la música (tanda 8): el viento, los pasos de Zenón, los
## cascos de Ceniza, el fuego de los fogones y la hacienda. Va en el nodo "Sonidos" de World.tscn.
## No toca nada del juego: mira lo que pasa (cuándo apoya cada pie en la animación, qué fogón se ve,
## qué animales hay cerca y si andan) y hace sonar lo que corresponde. Si se borra el nodo, el juego
## queda mudo como antes y nada se rompe.
##
## Los sonidos están en audio/ambiente/ y los hace tools/sonido/generar.py (ninguno es una grabación).
## Cada familia tiene su volumen acá abajo, en decibeles: 0 es como viene el archivo, -6 es más o
## menos la mitad y -60 la apaga. Todo sale por el canal "Sonidos" (default_bus_layout.tres).

@export_group("Volumen de cada familia")
## El viento de fondo, parado y al reparo. Andando ligero y en lo alto sube solo.
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var viento_db := -15.0
## Los pasos de Zenón.
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var pasos_db := -11.0
## Los cascos de Ceniza.
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var cascos_db := -9.0
## El crepitar de los fogones.
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var fuego_db := -5.0
## Las voces de la hacienda (mugidos, balidos, resoplidos, cloqueos) y el tropel de los que andan.
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var hacienda_db := -7.0
@export_group("Volumen de lo que sumó el pase libre")
## Los grillos de las noches de verano (en abril ya no cantan).
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var grillos_db := -21.0
## El chingolo de día y el gallo de la estancia al amanecer.
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var pajaros_db := -15.0
## El Limay de cerca y el chapoteo de Ceniza al vadear (el de Zenón va con pasos_db). En -60 no hay
## agua que suene: los dos pisan como en tierra.
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var agua_db := -9.0
## El silbido con que Zenón llama a Ceniza.
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var silbido_db := -13.0
@export_group("Cada cuánto")
## Entre una voz de la hacienda y la siguiente pasan, al azar, entre estos segundos.
@export var voz_cada := Vector2(5.0, 13.0)
## Entre un canto de pájaro y el siguiente, a la mañana (de día se espacian y de noche callan).
@export var pajaro_cada := Vector2(5.0, 12.0)

const CARPETA := "res://audio/ambiente/"
const CANAL := &"Sonidos"
## Cuántas tomas hay de cada sonido corto (paso_1.wav, paso_2.wav...). Se alternan al azar.
const TOMAS := {"paso": 5, "paso_ripio": 4, "paso_agua": 4, "casco": 6, "mugido": 3, "balido": 3,
	"resoplido": 2, "cloqueo": 3, "chingolo": 3, "hacha": 2}
## La voz de cada animal, según cómo empieza el nombre de su nodo. Los que no figuran no tienen voz.
const VOCES := {"Vaca": "mugido", "Carnero": "balido", "Oveja": "balido", "Gallina": "cloqueo",
	"Caballo": "resoplido", "Ceniza": "resoplido"}
## Los que suenan a tropel cuando andan: los de vaso o pezuña.
const DE_PEZUNA: Array[String] = ["Vaca", "Caballo", "Carnero", "Oveja", "Guanaco", "Chulengo", "Huemul"]
## A qué altura del suelo (metros) está el tobillo de Zenón cuando el pie ya apoyó, y a cuál ya está
## en el aire. Medido en sus clips: apoyado queda a 0,14; caminando sube a 0,28 y corriendo a 0,50.
const PIE_APOYA := 0.19
const PIE_VUELA := 0.23
## Lo mismo para los vasos de Ceniza: apoyado a 0,13; en el aire entre 0,24 (paso) y 0,54 (galope).
const VASO_APOYA := 0.155
const VASO_VUELA := 0.2

var _jugador: CharacterBody3D
var _ciclo: Node
var _terreno: Node3D
var _viento: AudioStreamPlayer
# Pasos de Zenón.
var _pasos := {}
var _esqueleto: Skeleton3D
var _pies := PackedInt32Array()
var _pie_arriba: Array[bool] = [false, false]
var _en_el_aire := 0.0
# Cascos de Ceniza.
var _ceniza: Node3D
var _esq_ceniza: Skeleton3D
var _vasos := PackedInt32Array()
var _vaso_arriba: Array[bool] = [false, false, false, false]
var _cascos: AudioStreamPlayer3D
var _chapoteo: AudioStreamPlayer3D
var _ceniza_antes := Vector3.ZERO
var _ceniza_rapidez := 0.0
var _venia_ligero := 0.0
# Fogones: cada uno es [la luz, su parlante].
var _fuegos: Array = []
# Hacienda.
var _voces := {}
var _parlantes: Array[AudioStreamPlayer3D] = []
var _tropel: AudioStreamPlayer3D
var _antes := {}
var _falta := 0.0
var _falta_voz := 4.0
# Pase libre: grillos, pájaros, agua, suelos y silbido.
var _grillos: AudioStreamPlayer
var _falta_pajaro := 3.0
var _falta_gallo := 2.0
var _rio: AudioStreamPlayer3D
var _puntos_del_rio := PackedVector3Array()
var _aguas_quietas: Array[AABB] = []
var _orilla := Vector3.ZERO
var _orilla_lejos := INF
var _suelos: Image
var _silbido: AudioStreamPlayer
var _jornada: AudioStreamPlayer


func _ready() -> void:
	# Un cuadro después: para entonces ya están en el mundo el jugador, Ceniza y los fogones.
	await get_tree().process_frame
	var mundo := get_parent()
	_jugador = mundo.get_node_or_null("Player") as CharacterBody3D
	if _jugador == null:
		return
	_ciclo = mundo.get_node_or_null("SistemaDiaNoche")
	_terreno = mundo.get_node_or_null("HTerrain") as Node3D
	_viento = _parlante(_largo("viento"))
	_viento.volume_db = -60.0
	_viento.play(randf() * 30.0)
	_armar_pasos()
	_armar_cascos(mundo)
	_armar_fuegos(mundo)
	_armar_hacienda(mundo)
	_armar_pase_libre(mundo)


func _process(delta: float) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return
	_soplar(delta)
	_pisar(delta)
	_andar_de_ceniza(delta)
	_falta -= delta
	if _falta > 0.0:
		return
	# Lo que no hace falta mirar en cada cuadro: cuatro veces por segundo.
	var paso := 0.25 - _falta
	_falta = 0.25
	_atender_fuegos()
	_atender_tropel(paso)
	_atender_pase_libre(paso)
	_falta_voz -= paso
	if _falta_voz <= 0.0:
		_falta_voz = randf_range(voz_cada.x, voz_cada.y)
		_dar_voz()


# ------------------------------------------------------------------ piezas

## Un sonido corto con varias tomas: cada vez suena una distinta, un poco más grave o más aguda.
func _tomas(nombre: String, tono := 1.1, volumen := 1.5) -> AudioStreamRandomizer:
	var azar := AudioStreamRandomizer.new()
	azar.random_pitch = tono
	azar.random_volume_offset_db = volumen
	for i in int(TOMAS.get(nombre, 0)):
		var ruta := "%s%s_%d.wav" % [CARPETA, nombre, i + 1]
		if ResourceLoader.exists(ruta):
			azar.add_stream(-1, load(ruta) as AudioStream)
	return azar


## Un sonido largo que se repite sin corte (los hace "en redondo" tools/sonido/generar.py).
func _largo(nombre: String) -> AudioStream:
	var ruta := CARPETA + nombre + ".ogg"
	var sonido := load(ruta) as AudioStreamOggVorbis if ResourceLoader.exists(ruta) else null
	if sonido != null:
		sonido.loop = true
	return sonido


func _suelto(nombre: String) -> AudioStream:
	var ruta := CARPETA + nombre + ".wav"
	return load(ruta) as AudioStream if ResourceLoader.exists(ruta) else null


## Un parlante que se oye igual en todos lados (lo que suena donde está Zenón).
func _parlante(sonido: AudioStream, voces := 1) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = sonido
	p.bus = CANAL
	p.max_polyphony = voces
	add_child(p)
	return p


## Un parlante puesto en un lugar del mundo: de cerca se oye entero, se va apagando con la
## distancia y a `hasta` metros ya no se oye.
func _parlante_en(padre: Node, sonido: AudioStream, de_cerca: float, hasta: float, voces := 1) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = sonido
	p.bus = CANAL
	p.unit_size = de_cerca
	p.max_distance = hasta
	# El juego no tiene zonas que cambien el sonido: que no las busque en cada cuadro.
	p.area_mask = 0
	p.max_polyphony = voces
	padre.add_child(p)
	return p


## Cuánto de noche es (0 de día, 1 de noche cerrada) y qué hora.
func _noche() -> float:
	return float(_ciclo.get("brillo_estrellas")) if _ciclo != null else 0.0


func _hora() -> float:
	return float(_ciclo.get("hora_del_dia")) if _ciclo != null else 12.0


# ------------------------------------------------------------------ viento

## El viento no se corta nunca. Parado casi no se nota; andando ligero se oye el aire, y en lo alto
## del paso a Chile sopla más. Las rachas ya vienen en el sonido.
func _soplar(delta: float) -> void:
	if _viento == null:
		return
	var ligero := clampf(Vector2(_jugador.velocity.x, _jugador.velocity.z).length() / 12.5, 0.0, 1.0)
	var alto := clampf((_jugador.global_position.y - 40.0) / 80.0, 0.0, 1.0)
	var peso := clampf(2.0 * delta, 0.0, 1.0)
	_viento.volume_db = lerpf(_viento.volume_db, viento_db + 7.0 * ligero + 4.0 * alto, peso)
	_viento.pitch_scale = lerpf(_viento.pitch_scale, 1.0 + 0.18 * ligero + 0.08 * alto, peso)


# ------------------------------------------------------------------ pasos de Zenón

func _armar_pasos() -> void:
	for suelo: String in ["paso", "paso_ripio", "paso_agua"]:
		_pasos[suelo] = _parlante(_tomas(suelo), 3)
	var cuerpo := _jugador.get_node_or_null("Cuerpo")
	_esqueleto = cuerpo.find_child("Skeleton3D", true, false) as Skeleton3D if cuerpo != null else null
	if _esqueleto != null:
		_pies = PackedInt32Array([_esqueleto.find_bone("mixamorig_LeftFoot"), _esqueleto.find_bone("mixamorig_RightFoot")])
		if _pies[0] < 0 or _pies[1] < 0:
			_esqueleto = null


## Suena un paso cada vez que un pie baja y apoya: se mira la altura de cada tobillo en el esqueleto.
## Así el sonido cae con el pie en cualquier clip (caminar, correr, de costado), sin tablas ni reloj.
func _pisar(delta: float) -> void:
	if _esqueleto == null or _jugador.get("montado") == true:
		return
	var en_piso := _jugador.is_on_floor()
	if not en_piso:
		_en_el_aire += delta
		return
	var rapidez := Vector2(_jugador.velocity.x, _jugador.velocity.z).length()
	if _en_el_aire > 0.25:
		# Cayó de un salto: un paso más pesado, y los pies quedan como apoyados.
		# Con un cartel en pantalla, no: al empezar, Zenón aparece un metro arriba del piso.
		if not Historia.ocupado:
			_un_paso(3.0, 0.85)
		_pie_arriba = [false, false]
	_en_el_aire = 0.0
	var suelo := _jugador.global_position.y - 0.9
	for i in 2:
		var alto := (_esqueleto.global_transform * _esqueleto.get_bone_global_pose(_pies[i]).origin).y - suelo
		if _pie_arriba[i] and alto < PIE_APOYA:
			_pie_arriba[i] = false
			# Caminando, más suave; corriendo, entero.
			_un_paso(lerpf(-5.0, 0.0, clampf((rapidez - 1.0) / 3.5, 0.0, 1.0)), 1.0)
		elif alto > PIE_VUELA:
			_pie_arriba[i] = true


func _un_paso(mas_db: float, tono: float) -> void:
	var p := _pasos.get(_que_suelo(_jugador.global_position, _jugador.global_position.y - 0.9), _pasos["paso"]) as AudioStreamPlayer
	p.volume_db = pasos_db + mas_db
	p.pitch_scale = tono
	p.play()


# ------------------------------------------------------------------ cascos de Ceniza

func _armar_cascos(mundo: Node) -> void:
	_ceniza = mundo.get_node_or_null("Ceniza") as Node3D
	if _ceniza == null:
		return
	_esq_ceniza = _ceniza.find_child("Skeleton3D", true, false) as Skeleton3D
	if _esq_ceniza == null:
		return
	for hueso: String in ["del_pie_L", "del_pie_R", "tras_pie_L", "tras_pie_R"]:
		_vasos.append(_esq_ceniza.find_bone(hueso))
	if _vasos.has(-1):
		_esq_ceniza = null
		return
	_cascos = _parlante_en(_ceniza, _tomas("casco", 1.12, 2.0), 8.0, 110.0, 6)
	_chapoteo = _parlante_en(_ceniza, _tomas("paso_agua", 1.1, 2.0), 8.0, 110.0, 4)
	_ceniza_antes = _ceniza.global_position


## Cada vaso suena cuando baja y apoya, igual que los pies de Zenón: al paso salen cuatro tiempos,
## al trote dos (van de a dos patas) y al galope los golpes seguidos y el silencio del aire.
func _andar_de_ceniza(delta: float) -> void:
	if _esq_ceniza == null or not is_instance_valid(_ceniza):
		return
	var donde := _ceniza.global_position
	var corrido := Vector2(donde.x - _ceniza_antes.x, donde.z - _ceniza_antes.z).length()
	_ceniza_antes = donde
	# Un salto de lugar (aparece silbada, se carga una partida) no es andar. Se lo reconoce por los
	# metros y no por la velocidad del cuadro: montada, Ceniza se mueve con la física (60 veces por
	# segundo), y en una pantalla de 144 o más cada uno de esos pasos parecería un salto.
	_ceniza_rapidez = lerpf(_ceniza_rapidez, corrido / maxf(delta, 0.001) if corrido < 3.0 else 0.0, clampf(6.0 * delta, 0.0, 1.0))
	_resoplar_al_parar(delta)
	if _ceniza_rapidez < 0.2:
		return
	var a_ceniza := _ceniza.global_transform.affine_inverse() * _esq_ceniza.global_transform
	for i in 4:
		var alto := (a_ceniza * _esq_ceniza.get_bone_global_pose(_vasos[i]).origin).y
		if _vaso_arriba[i] and alto < VASO_APOYA:
			_vaso_arriba[i] = false
			var en_agua := donde.y < _nivel_del_agua(donde) - 0.05
			var p := _chapoteo if en_agua else _cascos
			# Al paso, apenas; al galope, enteros y un poco más graves.
			var ligero := clampf(_ceniza_rapidez / 12.5, 0.0, 1.0)
			p.volume_db = (agua_db if en_agua else cascos_db) + lerpf(-7.0, 0.0, ligero)
			p.pitch_scale = (0.8 if en_agua else 1.0) * lerpf(1.05, 0.94, ligero)
			p.play()
		elif alto > VASO_VUELA:
			_vaso_arriba[i] = true


## Después de un rato de andar ligero, al parar, Ceniza resopla.
func _resoplar_al_parar(delta: float) -> void:
	if _ceniza_rapidez > 7.0:
		_venia_ligero = minf(_venia_ligero + delta, 6.0)
	elif _ceniza_rapidez < 0.4 and _venia_ligero > 2.5:
		_venia_ligero = 0.0
		_voz_en(_ceniza, "resoplido", 0.9)
	elif _ceniza_rapidez < 3.0:
		_venia_ligero = maxf(_venia_ligero - delta * 0.5, 0.0)


# ------------------------------------------------------------------ fuego

## Cada fogón de la escena tiene una luz que tiembla (los nodos "LuzFogon…", scripts/luz_fogon.gd):
## a cada una se le cuelga su crepitar.
func _armar_fuegos(mundo: Node) -> void:
	var crepitar := _largo("fuego")
	if crepitar == null:
		return
	for luz in mundo.find_children("LuzFogon*", "OmniLight3D", true, false):
		_fuegos.append([luz, _parlante_en(luz, crepitar, 3.5, 34.0)])


## Un fogón suena solo si se ve (la historia esconde algunos) y Zenón está cerca.
func _atender_fuegos() -> void:
	var aqui := _jugador.global_position
	for par: Array in _fuegos:
		var luz := par[0] as Node3D
		var p := par[1] as AudioStreamPlayer3D
		if not is_instance_valid(luz):
			continue
		var suena := luz.is_visible_in_tree() and luz.global_position.distance_squared_to(aqui) < 36.0 * 36.0
		p.volume_db = fuego_db
		if suena and not p.playing:
			# Cada uno arranca en un punto distinto, para que dos fogones vecinos no crepiten a la par.
			p.play(randf() * 13.0)
		elif not suena and p.playing:
			p.stop()


# ------------------------------------------------------------------ hacienda

func _armar_hacienda(mundo: Node) -> void:
	for voz: String in ["mugido", "balido", "resoplido", "cloqueo", "chingolo"]:
		_voces[voz] = _tomas(voz, 1.08, 2.0)
	for i in 3:
		_parlantes.append(_parlante_en(self, null, 9.0, 130.0))
	_tropel = _parlante_en(self, _largo("tropel"), 10.0, 120.0)
	# Los caballos de la escena y Ceniza. Los animales que andan sueltos (multi_mesh_instance_3d.gd)
	# y los de los rebaños (arreo.gd) se anotan solos en el grupo "hacienda" al crearse.
	for caballo in mundo.find_children("Caballo*", "Node3D", true, true):
		caballo.add_to_group("hacienda")
	if _ceniza != null:
		_ceniza.add_to_group("hacienda")


func _empieza_con(nombre: String, lista: Array) -> String:
	for comienzo: String in lista:
		if nombre.begins_with(comienzo):
			return comienzo
	return ""


## Cada tanto, un animal de los que hay cerca dice lo suyo, desde donde está. De noche, casi nada:
## las gallinas y las ovejas callan y las vacas mugen poco.
func _dar_voz() -> void:
	var aqui := _jugador.global_position
	var noche := _noche() > 0.5
	var cerca: Array[Node3D] = []
	for bicho in get_tree().get_nodes_in_group("hacienda"):
		var nodo := bicho as Node3D
		if nodo == null or not nodo.is_visible_in_tree() or nodo.global_position.distance_squared_to(aqui) > 85.0 * 85.0:
			continue
		var voz: String = VOCES.get(_empieza_con(nodo.name, VOCES.keys()), "")
		if voz == "" or (noche and (voz == "cloqueo" or voz == "balido")):
			continue
		cerca.append(nodo)
	if cerca.is_empty() or (noche and randf() < 0.6):
		return
	var quien: Node3D = cerca.pick_random()
	_voz_en(quien, VOCES[_empieza_con(quien.name, VOCES.keys())], 1.0)


## Hace sonar una voz en el lugar de ese animal (con el primer parlante libre).
func _voz_en(quien: Node3D, voz: String, tono: float, mas_db := 0.0) -> void:
	if not _voces.has(voz):
		return
	for p in _parlantes:
		if not p.playing:
			p.stream = _voces[voz]
			p.global_position = quien.global_position + Vector3(0.0, 1.0, 0.0)
			p.volume_db = hacienda_db + mas_db
			p.pitch_scale = tono
			p.play()
			return


## El tropel: cuántos animales de pezuña andan cerca y cuán ligero. Sirve para la punta del arreo,
## la caballada, la fila del cruce a Chile y hasta los guanacos que disparan; no hace falta que
## nadie avise, se mira cuánto se movió cada uno desde la última vez.
func _atender_tropel(paso: float) -> void:
	if _tropel == null:
		return
	var aqui := _jugador.global_position
	var empuje := 0.0
	var centro := Vector3.ZERO
	var ahora := {}
	for bicho in get_tree().get_nodes_in_group("hacienda"):
		var nodo := bicho as Node3D
		if nodo == null or nodo == _ceniza or not nodo.is_visible_in_tree() or _empieza_con(nodo.name, DE_PEZUNA) == "":
			continue
		var donde := nodo.global_position
		if donde.distance_squared_to(aqui) > 90.0 * 90.0:
			continue
		var id := nodo.get_instance_id()
		ahora[id] = donde
		if _antes.has(id):
			var rapidez: float = (donde - (_antes[id] as Vector3)).length() / maxf(paso, 0.01)
			if rapidez > 0.35 and rapidez < 20.0:
				empuje += rapidez
				centro += donde * rapidez
	_antes = ahora
	if empuje < 0.8:
		if _tropel.playing:
			_tropel.stop()
		return
	_tropel.global_position = centro / empuje
	# Siete vacas al trote (unos 14 metros por segundo entre todas) es el tropel entero.
	_tropel.volume_db = hacienda_db + linear_to_db(clampf(empuje / 14.0, 0.05, 1.0))
	_tropel.pitch_scale = clampf(0.9 + empuje / 60.0, 0.9, 1.2)
	if not _tropel.playing:
		_tropel.play(randf() * 7.0)


# ------------------------------------------------------------------ pase libre de la tanda 8
# Cada cosa de acá abajo se apaga sola poniendo su volumen en -60, y se saca borrando su parte:
# los grillos, los pájaros (chingolo y gallo), el agua (río y vado), los suelos (canto rodado) y
# el silbido. Lo que queda arriba no depende de nada de esto, salvo _que_suelo y _nivel_del_agua,
# que si se sacan tienen que seguir devolviendo "paso" y -INF.

func _armar_pase_libre(mundo: Node) -> void:
	_grillos = _parlante(_largo("grillos"))
	_rio = _parlante_en(self, _largo("rio"), 14.0, 95.0)
	_silbido = _parlante(_suelto("silbido"))
	if _jugador.has_signal("silbo"):
		_jugador.connect("silbo", _al_silbar)
	_jornada = _parlante(null, 2)
	Historia.sonar.connect(_al_trabajar)
	# El agua: el lago y la aguada son espejos (una altura sola); el río baja, y su altura en cada
	# lugar sale de los puntos de su propia malla, salteados.
	var aguas := mundo.get_node_or_null("Agua")
	for agua in (aguas.get_children() if aguas != null else []):
		var malla := agua as MeshInstance3D
		if malla == null or malla.mesh == null:
			continue
		var caja: AABB = malla.global_transform * malla.mesh.get_aabb()
		if caja.size.y < 0.05:
			_aguas_quietas.append(caja)
			continue
		var puntos: PackedVector3Array = malla.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var salto := maxi(puntos.size() / 1800, 1)
		for i in range(0, puntos.size(), salto):
			_puntos_del_rio.append(malla.global_transform * puntos[i])
	# Los suelos del terreno (el cuarto canal es el canto rodado), para que la playa suene a piedra.
	if _terreno != null and _terreno.has_method("get_data") and _terreno.get_data() != null:
		var textura := _terreno.get_data().get_texture(2) as Texture2D
		_suelos = textura.get_image() if textura != null else null
		if _suelos != null and _suelos.is_compressed() and _suelos.decompress() != OK:
			_suelos = null


func _atender_pase_libre(paso: float) -> void:
	var aqui := _jugador.global_position
	# El punto del río más cercano: de ahí viene su sonido, y da la altura del agua en este lugar.
	_orilla_lejos = INF
	for punto in _puntos_del_rio:
		var lejos := Vector2(punto.x - aqui.x, punto.z - aqui.z).length_squared()
		if lejos < _orilla_lejos:
			_orilla_lejos = lejos
			_orilla = punto
	_orilla_lejos = sqrt(_orilla_lejos)
	if _rio != null and _rio.stream != null:
		_rio.volume_db = agua_db
		if _orilla_lejos < 95.0:
			_rio.global_position = _orilla
			if not _rio.playing:
				_rio.play(randf() * 11.0)
		elif _rio.playing:
			_rio.stop()
	# Grillos: de noche, en el verano. En abril (cuando llega la línea) ya hace frío.
	if _grillos != null and _grillos.stream != null:
		var cuanto := _noche() if Historia.momento <= 2 else 0.0
		_grillos.volume_db = grillos_db + linear_to_db(maxf(cuanto, 0.001))
		if cuanto > 0.05 and not _grillos.playing:
			_grillos.play(randf() * 11.0)
		elif cuanto <= 0.05 and _grillos.playing:
			_grillos.stop()
	# Pájaros: el chingolo canta desde algún lugar cercano. Mucho al amanecer, menos de día, nada de noche.
	var hora := _hora()
	_falta_pajaro -= paso
	if _falta_pajaro <= 0.0:
		var espera := 1.0 if hora < 9.0 else (1.8 if hora > 16.5 else 3.2)
		_falta_pajaro = randf_range(pajaro_cada.x, pajaro_cada.y) * espera * (1.6 if Historia.momento >= 3 else 1.0)
		if hora > 5.2 and hora < 19.3 and _voces.has("chingolo"):
			for p in _parlantes:
				if not p.playing:
					var rumbo := randf() * TAU
					p.stream = _voces["chingolo"]
					p.global_position = aqui + Vector3(cos(rumbo), 0.0, sin(rumbo)) * randf_range(14.0, 34.0) + Vector3(0.0, 2.0, 0.0)
					p.volume_db = pajaros_db
					p.pitch_scale = 1.0
					p.play()
					break
	# El gallo de la estancia, al amanecer, si se está cerca como para oírlo.
	_falta_gallo -= paso
	if _falta_gallo <= 0.0:
		_falta_gallo = randf_range(14.0, 30.0)
		if hora > 5.2 and hora < 7.7:
			for bicho in get_tree().get_nodes_in_group("hacienda"):
				var gallo := bicho as Node3D
				if gallo != null and String(gallo.name).begins_with("Gallo") and gallo.global_position.distance_squared_to(aqui) < 170.0 * 170.0:
					_cantar_en(gallo)
					break


func _cantar_en(gallo: Node3D) -> void:
	var canto := _suelto("gallo")
	for p in _parlantes:
		if not p.playing and canto != null:
			p.stream = canto
			p.global_position = gallo.global_position + Vector3(0.0, 0.5, 0.0)
			p.volume_db = pajaros_db + 6.0
			p.pitch_scale = randf_range(0.96, 1.04)
			p.play()
			return


## Zenón silba (señal "silbo" de player.gd): suena el silbido y, si Ceniza lo oye, contesta resoplando.
func _al_silbar() -> void:
	if _silbido != null and _silbido.stream != null:
		_silbido.volume_db = silbido_db
		_silbido.play()
	if _ceniza != null and is_instance_valid(_ceniza):
		# (El "false": el reloj se detiene con la pausa.)
		get_tree().create_timer(1.1, false).timeout.connect(func() -> void:
			if is_instance_valid(_ceniza):
				_voz_en(_ceniza, "resoplido", 1.05))


## Una jornada de trabajo de la historia pide su sonido mientras la pantalla está oscura ("suena" en
## el efecto "jornada" de datos/historia.json): unos hachazos para la leña, unos mugidos para la yerra.
func _al_trabajar(que: String) -> void:
	if _jornada == null or not TOMAS.has(que):
		return
	_jornada.stream = _tomas(que, 1.06, 2.5)
	_jornada.volume_db = pasos_db + 3.0 if que == "hacha" else hacienda_db - 4.0
	var cuando := 0.9
	for i in (5 if que == "hacha" else 3):
		get_tree().create_timer(cuando, false).timeout.connect(_jornada.play)
		cuando += randf_range(0.55, 0.8) if que == "hacha" else randf_range(1.6, 2.4)


## A qué altura está el agua en ese lugar, o -INF si ahí no hay agua. Quien tenga los pies por debajo
## está vadeando.
func _nivel_del_agua(p: Vector3) -> float:
	if agua_db <= -59.5:
		return -INF  # Con la perilla apagada no hay agua que suene: se pisa como en tierra.
	for caja in _aguas_quietas:
		if p.x > caja.position.x and p.x < caja.end.x and p.z > caja.position.z and p.z < caja.end.z:
			return caja.position.y
	# La orilla se busca alrededor de Zenón (_atender_pase_libre): quien ande lejos de ese punto,
	# como Ceniza cuando viene sola por la costa, no está en el agua.
	return _orilla.y if _orilla_lejos < 22.0 and Vector2(p.x - _orilla.x, p.z - _orilla.z).length() < 22.0 else -INF


## Sobre qué pisa quien está en ese punto con los pies a esa altura: "paso" (tierra y pasto),
## "paso_ripio" (canto rodado) o "paso_agua" (vadeando).
func _que_suelo(p: Vector3, pies: float) -> String:
	if pies < _nivel_del_agua(p) - 0.03:
		return "paso_agua"
	if _suelos != null and _terreno != null:
		var mapa: Vector3 = _terreno.world_to_map(p)
		var x := clampi(int(mapa.x), 0, _suelos.get_width() - 1)
		var z := clampi(int(mapa.z), 0, _suelos.get_height() - 1)
		if _suelos.get_pixel(x, z).a > 0.45:
			return "paso_ripio"
	return "paso"

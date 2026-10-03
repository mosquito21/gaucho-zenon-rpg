extends MultiMeshInstance3D

## Coirón sembrado una sola vez alrededor del arranque.
## Unos pajaritos, un choique, guanacos, un zorro, cóndores, los animales de la estancia
## y la pulpería y el perro de la estancia se mueven como hijos de este nodo.
## Las matas salen de assets/flora/coiron.glb (tres formas); cada forma va en su propio MultiMesh.

const COIRON_GLB := "res://assets/flora/coiron.glb"
const CHOIQUE_GLB := "res://assets/animales/choique.glb"
const GUANACO_GLB := "res://assets/animales/guanaco.glb"
const ZORRO_GLB := "res://assets/animales/zorro.glb"
const CONDOR_GLB := "res://assets/animales/condor.glb"
const VACA_GLB := "res://assets/animales/vaca.glb"
const OVEJA_GLB := "res://assets/animales/oveja.glb"
const OVEJA_HEMBRA_GLB := "res://assets/animales/oveja_hembra.glb"
const GALLINA_GLB := "res://assets/animales/gallina.glb"
const GALLINA_COLORADA_GLB := "res://assets/animales/gallina_colorada.glb"
const GALLINA_BATARAZA_GLB := "res://assets/animales/gallina_bataraza.glb"
const GALLO_GLB := "res://assets/animales/gallo.glb"
const POLLITO_GLB := "res://assets/animales/pollito.glb"
const POLLITO_PARDO_GLB := "res://assets/animales/pollito_pardo.glb"
const PERRO_GLB := "res://assets/animales/perro.glb"

@export var terrain_path: NodePath = ^"../HTerrain"
@export var count := 520
@export var radio := 250.0
@export var min_scale := 1.05
@export var max_scale := 1.7
@export var max_slope_degrees := 32.0

var _pajaros: Array[Node3D] = []
var _nandu: Node3D
var _bichos: Array[Node3D] = []
var _reloj := 0.0
# Este nodo lleva la primera forma de mata; las otras van en hijos creados al arrancar.
var _matas: Array[MultiMeshInstance3D] = []

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await get_tree().process_frame
	_armar_multimesh()
	_sembrar()
	_armar_pajaros()
	_armar_nandu()
	_armar_bichos()

func _process(delta: float) -> void:
	_reloj += delta
	_mover_pajaros(delta)
	_mover_nandu(delta)
	_mover_bichos(delta)

func _terreno() -> Node:
	return get_node_or_null(terrain_path)

func _altura_mundo(x: float, z: float) -> Vector3:
	var terreno := _terreno()
	if terreno == null or not terreno.has_method("world_to_map"):
		return Vector3(x, 0.0, z)
	var datos = terreno.get_data()
	if datos == null:
		return Vector3(x, 0.0, z)
	var mapa: Vector3 = terreno.world_to_map(Vector3(x, 0.0, z))
	var h: float = datos.get_interpolated_height_at(Vector3(mapa.x, 0.0, mapa.z))
	return terreno.get_internal_transform() * Vector3(mapa.x, h, mapa.z)

func _pendiente_ok(x: float, z: float) -> bool:
	var terreno := _terreno()
	if terreno == null:
		return true
	var datos = terreno.get_data()
	if datos == null or not terreno.has_method("world_to_map"):
		return true
	var mapa: Vector3 = terreno.world_to_map(Vector3(x, 0.0, z))
	var res: int = datos.get_resolution()
	if mapa.x < 2.0 or mapa.z < 2.0 or mapa.x > res - 3 or mapa.z > res - 3:
		return false
	var h: float = datos.get_interpolated_height_at(Vector3(mapa.x, 0.0, mapa.z))
	var hx: float = datos.get_interpolated_height_at(Vector3(mapa.x + 1.0, 0.0, mapa.z))
	var hz: float = datos.get_interpolated_height_at(Vector3(mapa.x, 0.0, mapa.z + 1.0))
	var escala: Vector3 = terreno.map_scale
	var normal := Vector3((h - hx) * escala.y, escala.x, (h - hz) * escala.y).normalized()
	var grados := rad_to_deg(acos(clampf(normal.dot(Vector3.UP), -1.0, 1.0)))
	return grados <= max_slope_degrees

func _sembrar() -> void:
	if multimesh == null or _matas.is_empty():
		return
	var origen := Vector3.ZERO
	var jugador := get_parent().get_node_or_null("Player") as Node3D
	if jugador != null:
		origen = jugador.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = 1848
	var puestos := 0
	var intentos := 0
	while puestos < count and intentos < count * 10:
		intentos += 1
		var ang := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * 55.0
		if puestos > 180:
			dist = rng.randf_range(30.0, radio)
		var x := origen.x + cos(ang) * dist
		var z := origen.z + sin(ang) * dist
		if not _pendiente_ok(x, z):
			continue
		var pos := _altura_mundo(x, z)
		pos.y -= 0.03
		var base := Basis(Vector3.UP, rng.randf() * TAU)
		var s := rng.randf_range(min_scale, max_scale)
		base = base.scaled(Vector3(s, rng.randf_range(0.7, 1.2) * s, s))
		var tono := rng.randf()
		var color := Color(0.72, 0.62, 0.32).lerp(Color(0.48, 0.52, 0.34), tono)
		color = color.lerp(Color(0.55, 0.42, 0.24), rng.randf() * 0.4)
		# Las matas se reparten por turno entre las formas.
		var mata := _matas[puestos % _matas.size()]
		var indice := floori(float(puestos) / _matas.size())
		mata.multimesh.set_instance_transform(indice, Transform3D(base, pos))
		mata.multimesh.set_instance_color(indice, color)
		puestos += 1
	for i in _matas.size():
		_matas[i].multimesh.visible_instance_count = ceili(float(puestos - i) / _matas.size())

func _armar_multimesh() -> void:
	var mallas := _mallas_coiron()
	_matas.clear()
	if mallas.is_empty():
		push_warning("Falta %s: no se siembra coirón." % COIRON_GLB)
		return
	var material := _material_coiron()
	var por_forma := ceili(float(count) / mallas.size())
	for i in mallas.size():
		var mata: MultiMeshInstance3D = self
		if i > 0:
			mata = MultiMeshInstance3D.new()
			mata.name = "CoironForma%d" % i
			mata.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mata)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mallas[i]
		mm.instance_count = por_forma
		mata.multimesh = mm
		mata.material_override = material
		_matas.append(mata)

## Las formas de mata del GLB, ordenadas por nombre.
func _mallas_coiron() -> Array[Mesh]:
	var mallas: Array[Mesh] = []
	var escena := load(COIRON_GLB) as PackedScene
	if escena != null:
		var raiz := escena.instantiate()
		var nodos := raiz.find_children("*", "MeshInstance3D", true, false)
		nodos.sort_custom(func(a, b): return String(a.name) < String(b.name))
		for nodo in nodos:
			mallas.append((nodo as MeshInstance3D).mesh)
		raiz.free()
	return mallas

## Material mate que recibe la luz del sol y de la luna. Antes era UNSHADED y brillaba de noche.
## La malla trae un degradé de luz (oscura abajo, clara en las puntas) y el tono lo pone cada mata.
func _material_coiron() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.1
	return mat

func _material_opaco(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat

func _malla_color(mesh: Mesh, color: Color) -> MeshInstance3D:
	var nodo := MeshInstance3D.new()
	nodo.mesh = mesh
	nodo.material_override = _material_opaco(color)
	nodo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return nodo

func _armar_pajaros() -> void:
	var colores: Array[Color] = [
		Color(0.45, 0.38, 0.28),
		Color(0.55, 0.32, 0.22),
		Color(0.72, 0.74, 0.76),
		Color(0.38, 0.34, 0.26),
		Color(0.62, 0.4, 0.28),
		Color(0.5, 0.52, 0.5),
	]
	var cuerpo_malla := SphereMesh.new()
	cuerpo_malla.radius = 0.16
	cuerpo_malla.height = 0.46
	var ala_malla := BoxMesh.new()
	ala_malla.size = Vector3(0.7, 0.02, 0.18)
	for i in colores.size():
		var ave := Node3D.new()
		ave.name = "Pajaro%d" % i
		add_child(ave)
		var cuerpo := _malla_color(cuerpo_malla, colores[i])
		cuerpo.rotation.z = PI * 0.5
		ave.add_child(cuerpo)
		var alas := _malla_color(ala_malla, colores[i].darkened(0.15))
		alas.name = "Alas"
		ave.add_child(alas)
		ave.set_meta("casa_x", cos(float(i) * 1.1) * 18.0)
		ave.set_meta("casa_z", sin(float(i) * 1.7) * 18.0)
		ave.set_meta("fase", float(i) * 1.3)
		ave.set_meta("vuela", i % 2 == 0)
		_pajaros.append(ave)

func _mover_pajaros(_delta: float) -> void:
	for ave in _pajaros:
		var fase: float = ave.get_meta("fase")
		var t := _reloj + fase
		var x: float = ave.get_meta("casa_x") + cos(t * 0.7) * 6.0
		var z: float = ave.get_meta("casa_z") + sin(t * 0.55) * 6.0
		var suelo := _altura_mundo(x, z)
		var vuela: bool = ave.get_meta("vuela")
		var alto := 1.6 + sin(t * 1.4) * 0.8
		if not vuela:
			alto = 0.15 + maxf(sin(t * 3.0), 0.0) * 0.35
		ave.global_position = Vector3(x, suelo.y + alto, z)
		ave.rotation.y = t * 0.7
		var alas := ave.get_node_or_null("Alas") as MeshInstance3D
		if alas != null:
			alas.rotation.z = sin(t * (8.0 if vuela else 3.0)) * 0.5

## Carga un animal de assets/animales/. Devuelve null si el archivo no está.
func _modelo_bicho(ruta: String, nombre: String, escala: float) -> Node3D:
	if not ResourceLoader.exists(ruta):
		return null
	var escena := load(ruta) as PackedScene
	if escena == null:
		return null
	var bicho := escena.instantiate() as Node3D
	bicho.name = nombre
	bicho.scale = Vector3.ONE * escala
	add_child(bicho)
	return bicho

## Guanacos, zorro, cóndores y los animales de la estancia y la pulpería:
## cada uno da vueltas a su propio círculo, igual que el choique.
func _armar_bichos() -> void:
	# [archivo, nombre, escala, centro x, centro z, radio, vueltas por segundo, fase, altura de vuelo]
	# La altura de vuelo es opcional: si está, el bicho planea a esa altura sobre el suelo.
	var lista := [
		[GUANACO_GLB, "Guanaco1", 1.0, -70.0, -30.0, 46.0, 0.05, 0.0],
		[GUANACO_GLB, "Guanaco2", 0.95, -70.0, -30.0, 49.0, 0.05, 0.16],
		[GUANACO_GLB, "Guanaco3", 1.05, -70.0, -30.0, 43.0, 0.05, 0.3],
		[GUANACO_GLB, "Chulengo", 0.6, -70.0, -30.0, 47.0, 0.05, 0.08],
		[ZORRO_GLB, "Zorro", 1.0, 30.0, 60.0, 18.0, 0.09, 0.0],
		# Cóndores planeando alto: dos sobre el arranque y uno sobre la toldería.
		[CONDOR_GLB, "Condor1", 1.0, -40.0, 60.0, 95.0, 0.12, 0.0, 55.0],
		[CONDOR_GLB, "Condor2", 0.95, -40.0, 60.0, 80.0, 0.14, 2.6, 70.0],
		[CONDOR_GLB, "Condor3", 1.0, -430.0, 60.0, 70.0, 0.13, 1.0, 60.0],
		# Vacas y ovejas de la estancia de Don Rufino, pastando despacio.
		[VACA_GLB, "Vaca1", 1.0, -136.0, -254.0, 10.0, 0.025, 0.0],
		[VACA_GLB, "Vaca2", 0.95, -136.0, -254.0, 12.0, 0.025, 1.3],
		[VACA_GLB, "Vaca3", 1.05, -136.0, -254.0, 8.0, 0.025, 2.4],
		[VACA_GLB, "Vaca4", 0.9, -136.0, -254.0, 11.0, 0.025, 3.6],
		[VACA_GLB, "Vaca5", 1.0, -136.0, -254.0, 9.5, 0.025, 5.0],
		[OVEJA_GLB, "Carnero", 1.0, -162.7, -221.2, 6.0, 0.04, 0.0],
		[OVEJA_HEMBRA_GLB, "Oveja1", 0.95, -162.7, -221.2, 5.5, 0.04, 0.5],
		[OVEJA_HEMBRA_GLB, "Oveja2", 1.0, -162.7, -221.2, 6.5, 0.04, 0.9],
		[OVEJA_HEMBRA_GLB, "Oveja3", 0.9, -162.7, -221.2, 5.0, 0.04, 1.4],
		[OVEJA_HEMBRA_GLB, "Oveja4", 1.0, -162.7, -221.2, 7.0, 0.04, 1.9],
		[OVEJA_HEMBRA_GLB, "Oveja5", 0.95, -162.7, -221.2, 6.0, 0.04, 2.5],
		[OVEJA_HEMBRA_GLB, "Oveja6", 0.85, -162.7, -221.2, 5.8, 0.04, 3.1],
		# Gallinas, gallo y pollitos frente a la estancia y al costado de la pulpería.
		[GALLO_GLB, "GalloEstancia", 1.0, -157.5, -252.5, 3.0, 0.22, 0.0],
		[GALLINA_GLB, "GallinaEstancia1", 1.0, -157.5, -252.5, 2.4, 0.25, 1.2],
		[GALLINA_COLORADA_GLB, "GallinaEstancia2", 0.95, -157.5, -252.5, 3.4, 0.2, 2.5],
		[GALLINA_BATARAZA_GLB, "GallinaEstancia3", 1.05, -157.5, -252.5, 1.8, 0.3, 4.0],
		[POLLITO_GLB, "Pollito1", 1.0, -157.5, -252.5, 2.2, 0.25, 1.35],
		[POLLITO_PARDO_GLB, "Pollito2", 1.0, -157.5, -252.5, 2.1, 0.25, 1.5],
		[POLLITO_GLB, "Pollito3", 0.9, -157.5, -252.5, 2.3, 0.25, 1.62],
		[GALLINA_GLB, "GallinaPulperia1", 1.0, 195.0, 165.0, 2.5, 0.22, 0.4],
		[GALLINA_COLORADA_GLB, "GallinaPulperia2", 0.9, 195.0, 165.0, 3.2, 0.18, 3.0],
		[POLLITO_PARDO_GLB, "Pollito4", 1.0, 195.0, 165.0, 2.4, 0.22, 0.55],
		# El perro de la estancia da su vuelta por el patio, al paso.
		[PERRO_GLB, "PerroEstancia", 1.0, -152.0, -240.0, 6.0, 0.14, 0.0],
	]
	for d in lista:
		var bicho := _modelo_bicho(d[0], d[1], d[2])
		if bicho == null:
			continue
		bicho.set_meta("centro", Vector2(d[3], d[4]))
		bicho.set_meta("radio", d[5])
		bicho.set_meta("vel", d[6])
		bicho.set_meta("fase", d[7])
		bicho.set_meta("alto", d[8] if d.size() > 8 else 0.0)
		_bichos.append(bicho)

func _mover_bichos(_delta: float) -> void:
	for bicho in _bichos:
		var centro: Vector2 = bicho.get_meta("centro")
		var radio_loop: float = bicho.get_meta("radio")
		var ang: float = _reloj * float(bicho.get_meta("vel")) + float(bicho.get_meta("fase"))
		var x := centro.x + cos(ang) * radio_loop
		var z := centro.y + sin(ang) * radio_loop
		var suelo := _altura_mundo(x, z)
		var alto: float = bicho.get_meta("alto")
		if alto > 0.0:
			# Planea: sube y baja despacio y se inclina hacia adentro de la vuelta.
			var ola := sin(_reloj * 0.25 + float(bicho.get_meta("fase")) * 3.0) * 4.0
			bicho.global_position = Vector3(x, suelo.y + alto + ola, z)
			bicho.rotation = Vector3(0.0, -ang, -0.22)
			continue
		var paso := absf(sin(_reloj * 4.0 + float(bicho.get_meta("fase")) * 9.0)) * 0.03
		bicho.global_position = Vector3(x, suelo.y + paso, z)
		# La cabeza apunta a +Z, igual que el choique.
		bicho.rotation.y = -ang

func _armar_nandu() -> void:
	# El choique da la vuelta que antes daba el ñandú de cápsulas.
	_nandu = _modelo_bicho(CHOIQUE_GLB, "Nandu", 1.0)

func _mover_nandu(_delta: float) -> void:
	if _nandu == null:
		return
	var ang := _reloj * 0.18
	var x := cos(ang) * 32.0
	var z := sin(ang) * 32.0
	var suelo := _altura_mundo(x, z)
	# Apoya las patas en el suelo: el vaivén va solo para arriba.
	var paso := absf(sin(_reloj * 3.2)) * 0.03
	_nandu.global_position = Vector3(x, suelo.y + paso, z)
	# El cuello apunta a +Z. Con giro en Y, +Z queda en (sin(yaw), 0, cos(yaw)).
	_nandu.rotation.y = -ang

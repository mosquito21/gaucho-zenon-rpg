extends MultiMeshInstance3D

## Coirón sembrado una sola vez alrededor del arranque.
## Unos pajaritos y un ñandú se mueven como hijos de este nodo.

@export var terrain_path: NodePath = ^"../HTerrain"
@export var count := 520
@export var radio := 250.0
@export var min_scale := 1.05
@export var max_scale := 1.7
@export var max_slope_degrees := 32.0

var _pajaros: Array[Node3D] = []
var _nandu: Node3D
var _reloj := 0.0

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await get_tree().process_frame
	_armar_multimesh()
	_sembrar()
	_armar_pajaros()
	_armar_nandu()

func _process(delta: float) -> void:
	_reloj += delta
	_mover_pajaros(delta)
	_mover_nandu(delta)

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
	if multimesh == null:
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
		multimesh.set_instance_transform(puestos, Transform3D(base, pos))
		var tono := rng.randf()
		var color := Color(0.72, 0.62, 0.32).lerp(Color(0.48, 0.52, 0.34), tono)
		color = color.lerp(Color(0.55, 0.42, 0.24), rng.randf() * 0.4)
		multimesh.set_instance_color(puestos, color)
		puestos += 1
	multimesh.visible_instance_count = puestos

func _armar_multimesh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _malla_coiron()
	mm.instance_count = count
	multimesh = mm

func _malla_coiron() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normales := PackedVector3Array()
	var colores := PackedColorArray()
	var indices := PackedInt32Array()
	var abajo := Color(0.42, 0.34, 0.18)
	var arriba := Color(0.78, 0.68, 0.38)
	for i in 6:
		var ang := float(i) * TAU / 6.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var lado := Vector3(-dir.z, 0.0, dir.x)
		var base_i := vertices.size()
		var punta := dir * 0.34 + Vector3(0.0, 0.42, 0.0)
		var p0 := dir * 0.05 - lado * 0.07
		var p1 := dir * 0.05 + lado * 0.07
		var normal := (punta - p0).cross(p1 - p0).normalized()
		vertices.append_array([p0, p1, punta])
		normales.append_array([normal, normal, normal])
		colores.append_array([abajo, abajo, arriba])
		indices.append_array([base_i, base_i + 1, base_i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normales
	arrays[Mesh.ARRAY_COLOR] = colores
	arrays[Mesh.ARRAY_INDEX] = indices
	var malla := ArrayMesh.new()
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	malla.surface_set_material(0, mat)
	return malla

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

func _armar_nandu() -> void:
	_nandu = Node3D.new()
	_nandu.name = "Nandu"
	add_child(_nandu)
	var cuerpo_malla := CapsuleMesh.new()
	cuerpo_malla.radius = 0.28
	cuerpo_malla.height = 1.15
	var cuerpo := _malla_color(cuerpo_malla, Color(0.42, 0.34, 0.24))
	cuerpo.rotation.z = PI * 0.5
	cuerpo.position = Vector3(0.0, 0.85, 0.0)
	_nandu.add_child(cuerpo)
	var cuello_malla := CapsuleMesh.new()
	cuello_malla.radius = 0.07
	cuello_malla.height = 0.7
	var cuello := _malla_color(cuello_malla, Color(0.38, 0.3, 0.22))
	cuello.position = Vector3(0.0, 1.35, 0.42)
	cuello.rotation.x = -0.4
	_nandu.add_child(cuello)
	var cabeza_malla := SphereMesh.new()
	cabeza_malla.radius = 0.1
	cabeza_malla.height = 0.22
	var cabeza := _malla_color(cabeza_malla, Color(0.36, 0.28, 0.2))
	cabeza.position = Vector3(0.0, 1.72, 0.62)
	_nandu.add_child(cabeza)
	_nandu.scale = Vector3(1.8, 1.8, 1.8)

func _mover_nandu(_delta: float) -> void:
	if _nandu == null:
		return
	var ang := _reloj * 0.18
	var x := cos(ang) * 32.0
	var z := sin(ang) * 32.0
	var suelo := _altura_mundo(x, z)
	var paso := sin(_reloj * 3.2) * 0.06
	_nandu.global_position = Vector3(x, suelo.y + paso, z)
	# El cuello apunta a +Z. Con giro en Y, +Z queda en (sin(yaw), 0, cos(yaw)).
	_nandu.rotation.y = -ang

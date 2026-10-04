extends MultiMeshInstance3D

## Las matas de la estepa (coirón, pasto de orilla, neneo y piedras sueltas) y los bichos.
## Las matas ya no se siembran una por una alrededor del arranque: cada tipo es una grilla de
## copias que viaja con la cámara, así hay matas en todo el mapa (ver _armar_estepa).
## Unos pajaritos, un choique, guanacos, un zorro, cóndores, los animales de la estancia
## y la pulpería y el perro de la estancia se mueven como hijos de este nodo.
## Las matas de cerca salen de assets/flora/coiron.glb (tres formas).

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
const HUEMUL_GLB := "res://assets/animales/huemul.glb"

const MATAS_SHADER := "res://assets/materiales/matas.gdshader"

@export var terrain_path: NodePath = ^"../HTerrain"
## Fuerza del viento sobre las matas (0 las deja quietas).
@export var viento := 0.16

# Velocidad natural de cada animal (metros por segundo a tamaño 1): a esa velocidad los pies no patinan.
# Las de los animales con esqueleto salen de sus clips (tools/animales); la gallina se mueve por código.
const PASO_NATURAL := {
	"caballo": {"walk": 0.94, "trot": 2.11},
	"vaca": {"walk": 0.63},
	"oveja": {"walk": 0.48},
	"guanaco": {"walk": 0.84, "trot": 2.01},
	"zorro": {"walk": 0.5, "trot": 1.23},
	"perro": {"walk": 0.73, "trot": 1.86},
	"choique": {"walk": 0.82, "trot": 3.75},
	"gallina": {"walk": 0.42},
	"huemul": {"walk": 0.75, "trot": 1.84},
}
# Los que viven en el cerro: su cuerpo acompaña la pendiente de la ladera que pisan.
const DE_CERRO := ["huemul"]
# Qué hace cada bicho, en orden; al terminar la lista vuelve a empezar.
# "walk" y "trot" avanzan por su vuelta durante esos segundos. "graze" (pastar, olfatear, picotear)
# e "idle" se quedan en el lugar esa cantidad de veces (cada vez dura lo que dura el clip).
const PLANES := {
	"tropilla": [["walk", 18.0], ["graze", 1.0], ["walk", 10.0], ["idle", 1.0], ["trot", 8.0], ["idle", 1.0]],
	"zorro": [["trot", 9.0], ["graze", 1.0], ["walk", 8.0], ["idle", 1.0]],
	"vaca": [["graze", 2.0], ["walk", 7.0], ["idle", 1.0], ["graze", 1.0], ["walk", 5.0]],
	"oveja": [["graze", 1.0], ["walk", 5.0], ["graze", 2.0], ["idle", 1.0], ["walk", 4.0]],
	"perro": [["walk", 9.0], ["graze", 1.0], ["trot", 5.0], ["idle", 1.0]],
	"choique": [["walk", 12.0], ["graze", 1.0], ["walk", 8.0], ["idle", 1.0], ["trot", 6.0]],
	"gallina": [["walk", 3.0], ["graze", 1.0], ["walk", 2.0], ["idle", 1.0], ["graze", 1.0]],
	"huemul": [["graze", 2.0], ["walk", 8.0], ["idle", 1.0], ["walk", 6.0], ["graze", 1.0], ["idle", 2.0]],
}

var _pajaros: Array[Node3D] = []
# Una ficha por bicho: su nodo, su vuelta (centro, radio, ángulo) y en qué paso de su plan está.
var _bichos: Array[Dictionary] = []
var _reloj := 0.0
var _materiales_matas: Array[ShaderMaterial] = []

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await get_tree().process_frame
	_armar_estepa()
	_armar_pajaros()
	_armar_bichos()

func _process(delta: float) -> void:
	_reloj += delta
	# Las matas necesitan saber dónde pisa Zenón para apartarse.
	var jugador := get_node_or_null("../Player") as Node3D
	if jugador != null:
		for material in _materiales_matas:
			material.set_shader_parameter("u_zenon", jugador.global_position)
	_mover_pajaros(delta)
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
	# La altura exacta del piso que se ve y se pisa: cada cuadrado del terreno son dos triángulos
	# partidos por la diagonal 10-01 (no alcanza con promediar las cuatro esquinas).
	var tope: int = datos.get_resolution() - 2
	var cx := clampi(floori(mapa.x), 0, tope)
	var cz := clampi(floori(mapa.z), 0, tope)
	var fx := mapa.x - cx
	var fz := mapa.z - cz
	var h00: float = datos.get_height_at(cx, cz)
	var h10: float = datos.get_height_at(cx + 1, cz)
	var h01: float = datos.get_height_at(cx, cz + 1)
	var h: float
	if fx + fz <= 1.0:
		h = h00 + (h10 - h00) * fx + (h01 - h00) * fz
	else:
		var h11: float = datos.get_height_at(cx + 1, cz + 1)
		h = h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)
	return terreno.get_internal_transform() * Vector3(mapa.x, h, mapa.z)

## Arma las grillas de matas. Cada una es un MultiMesh de lado x lado copias, separadas "paso" metros.
## El lugar de cada mata, su tamaño, su color, si crece o no en ese suelo y el viento los resuelve
## la placa de video en assets/materiales/matas.gdshader, leyendo las alturas y los suelos del terreno.
func _armar_estepa() -> void:
	var terreno := _terreno()
	var shader := load(MATAS_SHADER) as Shader
	if terreno == null or shader == null or not terreno.has_method("get_data") or terreno.get_data() == null:
		push_warning("Falta el terreno o %s: no se siembran matas." % MATAS_SHADER)
		return
	var datos = terreno.get_data()
	var comunes := {
		"u_alturas": datos.get_texture(0),  # alturas del terreno
		"u_suelos": datos.get_texture(2),  # qué suelo hay en cada lugar (estepa, tierra, vega, canto)
		"u_pisado": _mapa_pisado(terreno),  # el camino de huellas: ahí no crece nada
		"u_mundo_a_mapa": terreno.get_internal_transform().affine_inverse(),
		"u_escala_altura": terreno.map_scale.y,
		"viento": viento,
	}
	var mata := _malla_mata()
	# [nombre, malla, metros entre matas, copias por lado, ajustes]
	var grillas := [
		["Coiron", mata, 1.8, 112, {"densidad": 0.8, "manchones": 0.55, "distancia_fin": 97.0, "altura_max": 135.0,
			"tamano": Vector2(0.8, 1.6), "color_a": Color(0.66, 0.58, 0.33), "color_b": Color(0.47, 0.49, 0.32)}],
		["PastoDeOrilla", mata, 1.6, 80, {"densidad": 0.9, "manchones": 0.3, "distancia_fin": 60.0, "esfumado": 18.0,
			"gusto_suelo": Vector4(0.0, 0.0, 1.0, 0.12), "tamano": Vector2(1.1, 2.1),
			"color_a": Color(0.55, 0.55, 0.28), "color_b": Color(0.62, 0.58, 0.3), "color_vega": Color(0.46, 0.52, 0.27)}],
		["Neneo", _malla_neneo(), 8.0, 30, {"densidad": 0.45, "manchones": 0.9, "distancia_fin": 115.0,
			"gusto_suelo": Vector4(1.0, 0.0, 0.0, 0.0), "tamano": Vector2(0.55, 1.2), "viento": 0.0, "relieve": 1.0, "apartar": 0.0,
			"acostar": 1.0, "altura_max": 150.0,
			"color_a": Color(0.52, 0.5, 0.3), "color_b": Color(0.45, 0.44, 0.28), "hundir": 0.08}],
		["Piedras", _malla_piedra(), 5.0, 48, {"densidad": 0.4, "manchones": 0.7, "distancia_fin": 115.0,
			"gusto_suelo": Vector4(0.8, 0.35, 0.25, 1.0), "tamano": Vector2(0.5, 1.6), "viento": 0.0, "relieve": 1.6, "acostar": 1.0, "apartar": 0.0,
			"color_a": Color(0.52, 0.48, 0.42), "color_b": Color(0.62, 0.57, 0.5), "color_vega": Color(0.5, 0.48, 0.43), "hundir": 0.3}],
	]
	# De cerca, las matas detalladas del GLB (pocas: cada una tiene unos 470 triángulos).
	var formas := _mallas_coiron()
	if formas.is_empty():
		push_warning("Falta %s: no hay matas detalladas de cerca." % COIRON_GLB)
	for i in formas.size():
		grillas.append(["CoironDeCerca%d" % i, formas[i], 6.5, 13, {"densidad": 0.85, "manchones": 0.4,
			"distancia_fin": 40.0, "esfumado": 12.0, "tamano": Vector2(1.05, 1.7),
			"color_a": Color(0.66, 0.58, 0.33), "color_b": Color(0.47, 0.49, 0.32)}])
	for n in grillas.size():
		var g: Array = grillas[n]
		var malla: Mesh = g[1]
		var material := ShaderMaterial.new()
		material.shader = shader
		for nombre in comunes:
			material.set_shader_parameter(nombre, comunes[nombre])
		material.set_shader_parameter("paso", g[2])
		material.set_shader_parameter("lado", float(g[3]))
		material.set_shader_parameter("semilla", float(n + 1))
		material.set_shader_parameter("alto_malla", maxf(malla.get_aabb().end.y, 0.05))
		var ajustes: Dictionary = g[4]
		for nombre in ajustes:
			material.set_shader_parameter(nombre, ajustes[nombre])
		_materiales_matas.append(material)
		add_child(_grilla(g[0], malla, g[2], g[3], material))

## Una imagen del mapa entero (2 m por punto) con el camino de huellas marcado, para que no crezcan
## matas encima. El camino son calcos (Decal) y el terreno no sabe por dónde pasa.
func _mapa_pisado(terreno: Node) -> ImageTexture:
	var lado := 2048
	var imagen := Image.create(lado, lado, false, Image.FORMAT_R8)
	var a_mapa: Transform3D = terreno.get_internal_transform().affine_inverse()
	var celdas := float(terreno.get_data().get_resolution())
	var camino := get_node_or_null("../Caminos/CaminoFortinTolderia")
	if camino != null:
		for tramo in camino.get_children():
			var calco := tramo as Decal
			if calco == null:
				continue
			var pasos := int(calco.size.z) + 1
			for i in pasos + 1:
				var punto: Vector3 = a_mapa * (calco.global_transform * Vector3(0.0, 0.0, (float(i) / pasos - 0.5) * calco.size.z))
				var px := int((punto.x + 0.5) / celdas * lado)
				var pz := int((punto.z + 0.5) / celdas * lado)
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						imagen.set_pixel(clampi(px + dx, 0, lado - 1), clampi(pz + dz, 0, lado - 1), Color.WHITE)
	return ImageTexture.create_from_image(imagen)

## Un MultiMesh con lado x lado copias en cuadrícula. El shader las acomoda alrededor de la cámara.
func _grilla(nombre: String, malla: Mesh, paso: float, lado: int, material: ShaderMaterial) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malla
	mm.instance_count = lado * lado
	var datos := PackedFloat32Array()
	datos.resize(lado * lado * 12)
	var k := 0
	for j in lado:
		for i in lado:
			datos[k] = 1.0
			datos[k + 3] = i * paso
			datos[k + 5] = 1.0
			datos[k + 10] = 1.0
			datos[k + 11] = j * paso
			k += 12
	mm.buffer = datos
	var nodo := MultiMeshInstance3D.new()
	nodo.name = nombre
	nodo.multimesh = mm
	nodo.material_override = material
	nodo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Las matas no están donde dice la cuadrícula (las mueve el shader): que no se descarten por eso.
	nodo.custom_aabb = AABB(Vector3(-6000, -500, -6000), Vector3(12000, 2000, 12000))
	return nodo

## Mata liviana: catorce hojas finas que se abren en fuente (42 triángulos).
## Va por miles; de cerca la acompañan las matas detalladas del GLB.
func _malla_mata() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1881
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var abajo := Color(0.62, 0.58, 0.5)
	var arriba := Color(0.97, 0.95, 0.88)
	for i in 14:
		var ang := TAU * (float(i) + rng.randf() * 0.7) / 14.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var ancho := Vector3(-dir.z, 0.0, dir.x) * 0.013
		var largo := rng.randf_range(0.36, 0.62)
		var abre := rng.randf_range(0.15, 0.7)
		var p0 := dir * 0.03
		var p1 := dir * (0.03 + largo * abre * 0.4) + Vector3.UP * largo * 0.58
		var p2 := dir * (0.03 + largo * abre) + Vector3.UP * largo * (1.0 - abre * 0.35)
		var normal := (Vector3.UP + dir * 0.5).normalized()
		var medio := abajo.lerp(arriba, 0.6)
		for punto in [[p0 - ancho, abajo], [p0 + ancho, abajo], [p1 + ancho * 0.7, medio],
				[p0 - ancho, abajo], [p1 + ancho * 0.7, medio], [p1 - ancho * 0.7, medio],
				[p1 - ancho * 0.7, medio], [p1 + ancho * 0.7, medio], [p2, arriba]]:
			st.set_normal(normal)
			st.set_color(punto[1])
			st.add_vertex(punto[0])
	return st.commit()

## Cojín de neneo: una media bola baja y despareja.
func _malla_neneo() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var anillos := [[0.5, 0.0], [0.47, 0.16], [0.33, 0.3], [0.14, 0.37]]
	var gajos := 8
	var puntos: Array = []
	for a in anillos:
		var fila: Array = []
		for g in gajos:
			var ang := TAU * float(g) / gajos
			var r: float = a[0] * rng.randf_range(0.85, 1.12)
			fila.append(Vector3(cos(ang) * r, a[1] * rng.randf_range(0.9, 1.1), sin(ang) * r))
		puntos.append(fila)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cima := Vector3(0.0, 0.4, 0.0)
	for f in anillos.size():
		for g in gajos:
			var a: Vector3 = puntos[f][g]
			var b: Vector3 = puntos[f][(g + 1) % gajos]
			var caras: Array = [[a, b, cima]]
			if f < anillos.size() - 1:
				var c: Vector3 = puntos[f + 1][g]
				var d: Vector3 = puntos[f + 1][(g + 1) % gajos]
				caras = [[a, b, d], [a, d, c]]
			for cara in caras:
				for v: Vector3 in cara:
					st.set_color(Color(0.5, 0.5, 0.5).lerp(Color(0.95, 0.95, 0.9), clampf(v.y / 0.4, 0.0, 1.0)))
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()

## Piedra suelta: un cascote chato de caras planas.
func _malla_piedra() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var borde: Array[Vector3] = []
	var techo: Array[Vector3] = []
	for g in 6:
		var ang := TAU * (float(g) + rng.randf_range(-0.25, 0.25)) / 6.0
		var r := rng.randf_range(0.22, 0.34)
		borde.append(Vector3(cos(ang) * r, 0.0, sin(ang) * r))
		techo.append(Vector3(cos(ang) * r * 0.62, rng.randf_range(0.14, 0.22), sin(ang) * r * 0.62))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cima := Vector3(0.03, 0.24, -0.02)
	for g in 6:
		var h := (g + 1) % 6
		for cara in [[borde[g], borde[h], techo[h]], [borde[g], techo[h], techo[g]], [techo[g], techo[h], cima]]:
			var gris := rng.randf_range(0.72, 0.95)
			for v: Vector3 in cara:
				st.set_color(Color(gris, gris, gris))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()

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
	# Chingolos, loicas y una gaviota chica: pajaritos del tamaño de una mano (antes eran bolas de 30 cm).
	var colores: Array[Color] = [
		Color(0.45, 0.38, 0.28),
		Color(0.55, 0.32, 0.22),
		Color(0.72, 0.74, 0.76),
		Color(0.38, 0.34, 0.26),
		Color(0.62, 0.4, 0.28),
		Color(0.5, 0.52, 0.5),
	]
	for i in colores.size():
		var ave := _pajarito(colores[i], 1.0 + 0.35 * (i % 3))
		ave.name = "Pajaro%d" % i
		add_child(ave)
		ave.set_meta("casa_x", cos(float(i) * 1.1) * 18.0)
		ave.set_meta("casa_z", sin(float(i) * 1.7) * 18.0)
		ave.set_meta("fase", float(i) * 1.3)
		ave.set_meta("vuela", i % 2 == 0)
		_pajaros.append(ave)

## Un pajarito armado con formas simples: cuerpo, cabeza, pico, cola y dos alas que baten.
## Mira hacia +Z, igual que los demás bichos.
func _pajarito(color: Color, tamano: float) -> Node3D:
	var ave := Node3D.new()
	var cuerpo_malla := SphereMesh.new()
	cuerpo_malla.radius = 0.035
	cuerpo_malla.height = 0.07
	cuerpo_malla.radial_segments = 8
	cuerpo_malla.rings = 4
	var cuerpo := _malla_color(cuerpo_malla, color)
	cuerpo.scale = Vector3(1.0, 1.0, 2.1)
	ave.add_child(cuerpo)
	var cabeza := _malla_color(cuerpo_malla, color.darkened(0.12))
	cabeza.scale = Vector3.ONE * 0.75
	cabeza.position = Vector3(0.0, 0.03, 0.065)
	ave.add_child(cabeza)
	var pico_malla := CylinderMesh.new()
	pico_malla.top_radius = 0.0
	pico_malla.bottom_radius = 0.008
	pico_malla.height = 0.03
	pico_malla.radial_segments = 5
	var pico := _malla_color(pico_malla, Color(0.25, 0.2, 0.15))
	pico.rotation.x = PI * 0.5
	pico.position = Vector3(0.0, 0.028, 0.102)
	ave.add_child(pico)
	var cola_malla := BoxMesh.new()
	cola_malla.size = Vector3(0.03, 0.005, 0.075)
	var cola := _malla_color(cola_malla, color.darkened(0.25))
	cola.position = Vector3(0.0, 0.008, -0.1)
	cola.rotation.x = -0.25
	ave.add_child(cola)
	var ala_malla := BoxMesh.new()
	ala_malla.size = Vector3(0.11, 0.004, 0.065)
	for lado: float in [-1.0, 1.0]:
		var hombro := Node3D.new()
		hombro.name = "AlaIzq" if lado < 0.0 else "AlaDer"
		hombro.position = Vector3(0.028 * lado, 0.018, 0.0)
		var ala := _malla_color(ala_malla, color.darkened(0.2))
		ala.position = Vector3(0.055 * lado, 0.0, -0.005)
		hombro.add_child(ala)
		ave.add_child(hombro)
	ave.scale = Vector3.ONE * tamano
	return ave

func _mover_pajaros(_delta: float) -> void:
	for ave in _pajaros:
		var fase: float = ave.get_meta("fase")
		var t := _reloj + fase
		var x: float = ave.get_meta("casa_x") + cos(t * 0.7) * 6.0
		var z: float = ave.get_meta("casa_z") + sin(t * 0.55) * 6.0
		var suelo := _altura_mundo(x, z)
		var vuela: bool = ave.get_meta("vuela")
		# Mira hacia donde va (antes giraba sobre sí mismo sin parar).
		ave.rotation.y = atan2(-sin(t * 0.7) * 0.7, cos(t * 0.55) * 0.55)
		var batir := 0.0
		if vuela:
			ave.global_position = Vector3(x, suelo.y + 1.6 + sin(t * 1.4) * 0.8, z)
			# Aletea y cada tanto planea un momento con las alas abiertas.
			batir = sin(t * 22.0) * 0.9 if sin(t * 0.9) > -0.5 else 0.15
			ave.rotation.x = -0.12
		else:
			# Camina a saltitos, y entre salto y salto picotea el suelo con las alas plegadas.
			var salto := maxf(sin(t * 3.0), 0.0)
			ave.global_position = Vector3(x, suelo.y + 0.03 + salto * 0.12, z)
			batir = 1.35 - salto * 0.9
			ave.rotation.x = 0.0 if salto > 0.0 else maxf(sin(t * 9.0), 0.0) * 0.9
		(ave.get_node("AlaIzq") as Node3D).rotation.z = batir
		(ave.get_node("AlaDer") as Node3D).rotation.z = -batir

## Carga un animal de assets/animales/. Si existe su versión con esqueleto (<nombre>_animado.glb),
## usa esa; si no, el modelo quieto de siempre. Devuelve null si el archivo no está.
func _modelo_bicho(ruta: String, nombre: String, escala: float) -> Node3D:
	var animado := ruta.replace(".glb", "_animado.glb")
	if ResourceLoader.exists(animado):
		ruta = animado
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

## Choique, guanacos, zorro, cóndores y los animales de la estancia y la pulpería.
## Cada uno tiene su vuelta (un círculo), pero ya no desliza sin parar: sigue un plan
## (caminar, pastar, quedarse quieto, trotar) y los pies pisan a la velocidad a la que avanza.
func _armar_bichos() -> void:
	# [archivo, nombre, escala, centro x, centro z, radio, ángulo de arranque, especie, plan]
	# Los que planean (cóndores) llevan en cambio: vueltas por segundo y altura de vuelo.
	var lista := [
		[CHOIQUE_GLB, "Nandu", 1.0, 0.0, 0.0, 32.0, 0.0, "choique", "choique"],
		[GUANACO_GLB, "Guanaco1", 1.0, -70.0, -30.0, 46.0, 0.0, "guanaco", "tropilla"],
		[GUANACO_GLB, "Guanaco2", 0.95, -70.0, -30.0, 49.0, 0.16, "guanaco", "tropilla"],
		[GUANACO_GLB, "Guanaco3", 1.05, -70.0, -30.0, 43.0, 0.3, "guanaco", "tropilla"],
		[GUANACO_GLB, "Chulengo", 0.6, -70.0, -30.0, 47.0, 0.08, "guanaco", "tropilla"],
		[ZORRO_GLB, "Zorro", 1.0, 30.0, 60.0, 18.0, 0.0, "zorro", "zorro"],
		# Cóndores planeando alto: dos sobre el arranque y uno sobre la toldería.
		[CONDOR_GLB, "Condor1", 1.0, -40.0, 60.0, 95.0, 0.0, 0.12, 55.0],
		[CONDOR_GLB, "Condor2", 0.95, -40.0, 60.0, 80.0, 2.6, 0.14, 70.0],
		[CONDOR_GLB, "Condor3", 1.0, -430.0, 60.0, 70.0, 1.0, 0.13, 60.0],
		# Vacas y ovejas de la estancia de Don Rufino: pastan, dan unos pasos y vuelven a pastar.
		[VACA_GLB, "Vaca1", 1.0, -136.0, -254.0, 10.0, 0.0, "vaca", "vaca"],
		[VACA_GLB, "Vaca2", 0.95, -136.0, -254.0, 12.0, 1.3, "vaca", "vaca"],
		[VACA_GLB, "Vaca3", 1.05, -136.0, -254.0, 8.0, 2.4, "vaca", "vaca"],
		[VACA_GLB, "Vaca4", 0.9, -136.0, -254.0, 11.0, 3.6, "vaca", "vaca"],
		[VACA_GLB, "Vaca5", 1.0, -136.0, -254.0, 9.5, 5.0, "vaca", "vaca"],
		[OVEJA_GLB, "Carnero", 1.0, -162.7, -221.2, 6.0, 0.0, "oveja", "oveja"],
		[OVEJA_HEMBRA_GLB, "Oveja1", 0.95, -162.7, -221.2, 5.5, 0.5, "oveja", "oveja"],
		[OVEJA_HEMBRA_GLB, "Oveja2", 1.0, -162.7, -221.2, 6.5, 0.9, "oveja", "oveja"],
		[OVEJA_HEMBRA_GLB, "Oveja3", 0.9, -162.7, -221.2, 5.0, 1.4, "oveja", "oveja"],
		[OVEJA_HEMBRA_GLB, "Oveja4", 1.0, -162.7, -221.2, 7.0, 1.9, "oveja", "oveja"],
		[OVEJA_HEMBRA_GLB, "Oveja5", 0.95, -162.7, -221.2, 6.0, 2.5, "oveja", "oveja"],
		[OVEJA_HEMBRA_GLB, "Oveja6", 0.85, -162.7, -221.2, 5.8, 3.1, "oveja", "oveja"],
		# Gallinas, gallo y pollitos frente a la estancia y al costado de la pulpería.
		[GALLO_GLB, "GalloEstancia", 1.0, -157.5, -252.5, 3.0, 0.0, "gallina", "gallina"],
		[GALLINA_GLB, "GallinaEstancia1", 1.0, -157.5, -252.5, 2.4, 1.2, "gallina", "gallina"],
		[GALLINA_COLORADA_GLB, "GallinaEstancia2", 0.95, -157.5, -252.5, 3.4, 2.5, "gallina", "gallina"],
		[GALLINA_BATARAZA_GLB, "GallinaEstancia3", 1.05, -157.5, -252.5, 1.8, 4.0, "gallina", "gallina"],
		[POLLITO_GLB, "Pollito1", 1.0, -157.5, -252.5, 2.2, 1.35, "gallina", "gallina"],
		[POLLITO_PARDO_GLB, "Pollito2", 1.0, -157.5, -252.5, 2.1, 1.5, "gallina", "gallina"],
		[POLLITO_GLB, "Pollito3", 0.9, -157.5, -252.5, 2.3, 1.62, "gallina", "gallina"],
		[GALLINA_GLB, "GallinaPulperia1", 1.0, 195.0, 165.0, 2.5, 0.4, "gallina", "gallina"],
		[GALLINA_COLORADA_GLB, "GallinaPulperia2", 0.9, 195.0, 165.0, 3.2, 3.0, "gallina", "gallina"],
		[POLLITO_PARDO_GLB, "Pollito4", 1.0, 195.0, 165.0, 2.4, 0.55, "gallina", "gallina"],
		# El perro de la estancia da su vuelta por el patio.
		[PERRO_GLB, "PerroEstancia", 1.0, -152.0, -240.0, 6.0, 0.0, "perro", "perro"],
		# Huemules en el paso a Chile: uno en el borde del bosque, a la entrada, y otro ladera arriba.
		[HUEMUL_GLB, "Huemul1", 1.0, -1100.0, 620.0, 12.0, 0.0, "huemul", "huemul"],
		[HUEMUL_GLB, "Huemul2", 0.92, -1120.0, 780.0, 14.0, 2.0, "huemul", "huemul"],
	]
	for d in lista:
		var nodo := _modelo_bicho(d[0], d[1], d[2])
		if nodo == null:
			continue
		var ficha := {"nodo": nodo, "centro": Vector2(d[3], d[4]), "radio": float(d[5]), "ang": float(d[6]),
			"escala": float(d[2]), "alto": 0.0, "plan": [], "paso": -1, "t": 0.0, "dura": 0.0, "vel": 0.0, "clip": "",
			"radio_ref": float(d[5])}
		if d[7] is String:
			ficha["especie"] = d[7]
			ficha["plan"] = PLANES[d[8]]
			ficha["anim"] = nodo.find_child("AnimationPlayer", true, false) as AnimationPlayer
			# Cada uno arranca en un paso distinto de su plan, para que no hagan todos lo mismo a la vez.
			# La tropilla de guanacos va junta: mismo plan y la misma vuelta de referencia (46 m), así
			# los de adentro y los de afuera giran a la par, con uno o dos segundos de diferencia.
			if d[8] == "tropilla":
				ficha["radio_ref"] = 46.0
			else:
				ficha["paso"] = (int(float(d[6]) * 7.0) % PLANES[d[8]].size()) - 1
			_siguiente_paso(ficha)
			ficha["t"] = fmod(float(d[6]) * 3.7, 1.5)
		else:
			ficha["vel"] = float(d[7])
			ficha["alto"] = float(d[8])
		_bichos.append(ficha)

## Pasa al paso siguiente del plan: pone el clip y calcula a qué velocidad avanza.
func _siguiente_paso(b: Dictionary) -> void:
	var plan: Array = b.plan
	b.paso = (int(b.paso) + 1) % plan.size()
	b.t = 0.0
	var clip: String = plan[b.paso][0]
	var cuanto: float = plan[b.paso][1]
	var natural: float = PASO_NATURAL[b.especie].get(clip, 0.0)
	if natural <= 0.0 and (clip == "walk" or clip == "trot"):
		clip = "walk"
		natural = PASO_NATURAL[b.especie].get("walk", 0.5)
	b.clip = clip
	# Avanza a la velocidad natural de su especie (ajustada a su vuelta), y el clip va al ritmo
	# que corresponde a su tamaño: un animal chico da pasos más rápidos para cubrir lo mismo.
	b.vel = natural * float(b.radio) / float(b.radio_ref)
	var ritmo := 1.0
	if natural > 0.0:
		ritmo = clampf(float(b.vel) / (natural * float(b.escala)), 0.6, 1.6)
	var anim := b.get("anim") as AnimationPlayer
	var largo := 6.0
	if anim != null and anim.has_animation(clip):
		anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		anim.play(clip, 0.5, ritmo)
		largo = anim.get_animation(clip).length
	elif b.especie == "gallina":
		largo = 2.0
	b.dura = cuanto if b.vel > 0.0 else cuanto * largo

func _mover_bichos(delta: float) -> void:
	var camara := get_viewport().get_camera_3d()
	for b in _bichos:
		var nodo: Node3D = b.nodo
		var centro: Vector2 = b.centro
		var radio: float = b.radio
		if float(b.alto) > 0.0:
			# Planea: sube y baja despacio y se inclina hacia adentro de la vuelta.
			var giro: float = _reloj * float(b.vel) + float(b.ang)
			var ola := sin(_reloj * 0.25 + float(b.ang) * 3.0) * 4.0
			var bajo := _altura_mundo(centro.x + cos(giro) * radio, centro.y + sin(giro) * radio)
			nodo.global_position = Vector3(bajo.x, bajo.y + float(b.alto) + ola, bajo.z)
			nodo.rotation = Vector3(0.0, -giro, -0.22 + sin(_reloj * 0.4 + float(b.ang)) * 0.05)
			continue
		b.t = float(b.t) + delta
		if float(b.t) >= float(b.dura):
			_siguiente_paso(b)
		# Lejos de la cámara no se anima el esqueleto (sigue su vuelta igual): no se ve y ahorra trabajo.
		var anim_b := b.get("anim") as AnimationPlayer
		if anim_b != null and camara != null:
			anim_b.active = camara.global_position.distance_squared_to(nodo.global_position) < 150.0 * 150.0
		var vel: float = b.vel
		b.ang = float(b.ang) + vel * delta / radio
		var ang: float = b.ang
		var suelo := _altura_mundo(centro.x + cos(ang) * radio, centro.y + sin(ang) * radio)
		var t: float = b.t
		var cabeceo := 0.0
		var vaiven := 0.0
		if b.get("anim") == null:
			# Sin esqueleto (gallinas, pollitos, o si falta el modelo animado): pasitos y picoteo por código.
			if vel > 0.0:
				suelo.y += absf(sin(t * 9.0)) * 0.02
			elif b.especie == "gallina" and b.clip == "graze":
				cabeceo = maxf(sin(t * 7.0), 0.0) * 0.75
			elif b.especie == "gallina":
				vaiven = sin(t * 5.0) * 0.5 * maxf(1.0 - t, 0.0)
		# En la ladera, el cuerpo acompaña la pendiente: se mira cuánto sube el piso de la cola a la
		# cabeza (medio metro para cada lado) y se inclina eso. Subiendo, la cabeza va arriba.
		if b.especie in DE_CERRO:
			var adelante := Vector2(-sin(ang), cos(ang)) * 0.5
			var sube := _altura_mundo(suelo.x + adelante.x, suelo.z + adelante.y).y - _altura_mundo(suelo.x - adelante.x, suelo.z - adelante.y).y
			cabeceo -= atan2(sube, 1.0)
		nodo.global_position = suelo
		# La cabeza apunta a +Z. Con giro en Y, +Z queda en (sin(yaw), 0, cos(yaw)).
		nodo.rotation = Vector3(cabeceo, -ang + vaiven, 0.0)

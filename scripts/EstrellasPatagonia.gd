extends Node3D

## Cielo estrellado de la Patagonia, con la Vía Láctea como una banda densa.
## Sigue a la cámara para que no se quede atrás cuando Zenón camina.

class_name EstrellasPatagonia

var sistema_dia_noche: CicloDiaNoche
var campo_estrellas: MultiMeshInstance3D
var via_lactea: MultiMeshInstance3D
var materiales_cielo: Array[StandardMaterial3D] = []

@export var cantidad_estrellas: int = 1400
@export var cantidad_via_lactea: int = 2200
# Más lejos que la cordillera (llega hasta 3850 m), así las montañas tapan las estrellas bajas.
@export var distancia_estrellas: float = 3900.0
@export var intensidad_estrellas: float = 1.0

func _ready():
	print("🌟 Iniciando cielo estrellado patagónico...")
	await get_tree().process_frame
	await get_tree().process_frame
	configurar_estrellas()
	conectar_con_sistema_dia_noche()

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position
	# El brillo sigue a la hora de forma continua (antes saltaba al cambiar de período).
	if sistema_dia_noche:
		cambiar_opacidad_estrellas(sistema_dia_noche.brillo_estrellas * intensidad_estrellas)

func configurar_estrellas():
	print("✨ Armando campo de estrellas y Vía Láctea...")
	campo_estrellas = _crear_campo(cantidad_estrellas, false)
	via_lactea = _crear_campo(cantidad_via_lactea, true)
	add_child(campo_estrellas)
	add_child(via_lactea)
	print("🌌 Cielo estrellado listo")

func _crear_campo(cantidad: int, es_via_lactea: bool) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1, 1, 1, 0)
	material.no_depth_test = false
	# Sin niebla (si no, toman el color de la niebla y de noche desaparecen), redondas y de borde
	# suave en vez de cuadraditos, y cada una con su tamaño.
	material.disable_fog = true
	material.billboard_keep_scale = true
	material.albedo_texture = _punto_suave()
	materiales_cielo.append(material)
	
	# Cada estrella es un punto de 1,2 m visto a 420 m; si están más lejos, crece en la misma
	# proporción para que se vean del mismo tamaño. El "tamano" de cada una lo multiplica.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.2 * (distancia_estrellas / 420.0)
	
	var malla := MultiMesh.new()
	malla.transform_format = MultiMesh.TRANSFORM_3D
	malla.use_colors = true
	malla.mesh = quad
	malla.instance_count = cantidad
	
	var inclinacion_galactica := deg_to_rad(58.0)
	for i in cantidad:
		var punto: Vector3
		var tamano: float
		var color: Color
		if es_via_lactea:
			var a_lo_largo := randf() * TAU
			var ancho := randfn(0.0, 0.11)
			punto = Vector3(cos(a_lo_largo), ancho, sin(a_lo_largo))
			punto = punto.rotated(Vector3(1, 0, 0), inclinacion_galactica).normalized()
			if punto.y < 0.0:
				punto.y = absf(punto.y)
			tamano = randf_range(0.5, 1.3)
			color = Color(randf_range(0.75, 0.95), randf_range(0.8, 0.95), 1.0, randf_range(0.15, 0.55))
		else:
			var altura := randf()
			var anillo := sqrt(maxf(1.0 - altura * altura, 0.0))
			var angulo := randf() * TAU
			punto = Vector3(cos(angulo) * anillo, altura, sin(angulo) * anillo)
			tamano = randf_range(0.5, 1.4)
			if randf() < 0.08:
				tamano *= 2.0
			color = Color(randf_range(0.85, 1.0), randf_range(0.88, 1.0), randf_range(0.95, 1.0), randf_range(0.45, 1.0))
		
		var base := Basis.from_scale(Vector3.ONE * tamano)
		malla.set_instance_transform(i, Transform3D(base, punto * distancia_estrellas))
		malla.set_instance_color(i, color)
	
	var nodo := MultiMeshInstance3D.new()
	nodo.name = "ViaLactea" if es_via_lactea else "CampoEstrellas"
	nodo.multimesh = malla
	nodo.material_override = material
	nodo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return nodo

func conectar_con_sistema_dia_noche():
	sistema_dia_noche = encontrar_sistema_dia_noche()
	if sistema_dia_noche:
		print("🔗 Estrellas conectadas al ciclo día/noche")
	else:
		print("⚠️ No se encontró el sistema día/noche")

## Un punto blanco que se apaga hacia el borde, para que cada estrella sea redonda.
func _punto_suave() -> GradientTexture2D:
	var degrade := Gradient.new()
	degrade.set_color(0, Color(1, 1, 1, 1))
	degrade.set_color(1, Color(1, 1, 1, 0))
	var punto := GradientTexture2D.new()
	punto.gradient = degrade
	punto.fill = GradientTexture2D.FILL_RADIAL
	punto.fill_from = Vector2(0.5, 0.5)
	punto.fill_to = Vector2(1.0, 0.5)
	punto.width = 32
	punto.height = 32
	return punto

func encontrar_sistema_dia_noche() -> CicloDiaNoche:
	var nodos_encontrados: Array = []
	buscar_nodos_recursivo(get_tree().current_scene, CicloDiaNoche, nodos_encontrados)
	if nodos_encontrados.size() > 0:
		return nodos_encontrados[0]
	return null

func buscar_nodos_recursivo(nodo: Node, tipo: Variant, resultado: Array):
	if is_instance_of(nodo, tipo):
		resultado.append(nodo)
	for child in nodo.get_children():
		buscar_nodos_recursivo(child, tipo, resultado)

func cambiar_opacidad_estrellas(opacidad: float):
	for material in materiales_cielo:
		if is_instance_valid(material):
			var color := material.albedo_color
			material.albedo_color = Color(color.r, color.g, color.b, opacidad)

func cambiar_cantidad_estrellas(nueva_cantidad: int):
	cantidad_estrellas = nueva_cantidad
	for material in materiales_cielo:
		if is_instance_valid(material):
			material.queue_free()
	materiales_cielo.clear()
	if campo_estrellas and is_instance_valid(campo_estrellas):
		campo_estrellas.queue_free()
	if via_lactea and is_instance_valid(via_lactea):
		via_lactea.queue_free()
	await get_tree().process_frame
	configurar_estrellas()

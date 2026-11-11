extends CanvasLayer

## Lo que Zenón tiene siempre a mano además del cartel de abajo:
##   · La brújula, arriba a la derecha: gira con la mirada. Marca el norte, por dónde anda el sol,
##     dónde quedó Ceniza, dónde está el fogón y, con una rayita roja, adónde hay algo que hacer.
##   · El mapa (tecla M): el pago dibujado como un croquis, con el agua y los cerros tal como están
##     en el terreno, los lugares, Zenón, Ceniza y las mismas señas rojas.
##   · El morral (tecla I): lo que Zenón lleva encima y lo que va cargado en Ceniza, y la cuenta.
## Lo crea scenes/player/player.gd al arrancar el mundo; no está en ninguna escena. Todo se dibuja
## por programa, como el cuadro de diálogo (scripts/Dialogo.gd). Los lugares del mapa, las señas y
## las cosas del morral son datos: "mapa" y "cosas" en datos/historia.json.
## Con el mapa o el morral abiertos Zenón no camina ni gira la cámara; el tiempo sigue corriendo.

const TIERRA := Color(0.07, 0.055, 0.04, 0.94)
const CLARO := Color(0.96, 0.91, 0.78)
const APAGADO := Color(0.78, 0.7, 0.55)
## El único acento del juego, el rojo apagado: Zenón en el mapa y las señas.
const ROJO := Color(0.74, 0.25, 0.17)
const BRASA := Color(0.93, 0.58, 0.26)
const PAPEL := Color(0.8, 0.72, 0.56)
const TINTA := Color(0.2, 0.14, 0.09)
const AGUA := Color(0.43, 0.53, 0.56)
## Qué parte del mundo muestra el mapa, en metros: de oeste a este y de norte a sur. Si se suma un
## lugar fuera de este recuadro, hay que agrandarlo.
const MAPA_X := Vector2(-1750.0, 750.0)
const MAPA_Z := Vector2(-960.0, 1080.0)
## Cada cuántos metros se mira la altura del terreno para pintar el agua y los cerros del mapa.
const GRANO := 12.5

## Zenón. Lo pone player.gd antes de sumar este nodo.
var jugador: Node3D
## Qué hay abierto: "" (nada), "mapa" o "morral".
var abierto := ""

var _fuente: Font
var _brujula: Control
var _velo: ColorRect
var _mapa: Control
var _mapa_agua: Control
var _mapa_tinta: Control
var _mapa_vivo: Control
var _marco := Rect2()
var _fondo: ImageTexture
var _morral: PanelContainer
var _lista: VBoxContainer


func _ready() -> void:
	layer = 2
	_fuente = ThemeDB.fallback_font
	_brujula = Control.new()
	_brujula.name = "Brujula"
	_brujula.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brujula.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_brujula.offset_left = -150.0
	_brujula.offset_right = -22.0
	_brujula.offset_top = 22.0
	_brujula.offset_bottom = 168.0
	_brujula.draw.connect(_dibujar_brujula)
	add_child(_brujula)
	_velo = ColorRect.new()
	_velo.name = "Velo"
	_velo.color = Color(0.0, 0.0, 0.0, 0.55)
	_velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_velo.hide()
	add_child(_velo)
	_mapa = Control.new()
	_mapa.name = "Mapa"
	_mapa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mapa.draw.connect(_dibujar_papel)
	_mapa.hide()
	add_child(_mapa)
	# Encima del papel van, en este orden, el agua (recortada al recuadro), la tinta y lo que se mueve.
	_mapa_agua = Control.new()
	_mapa_agua.name = "Agua"
	_mapa_agua.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mapa_agua.clip_contents = true
	_mapa_agua.draw.connect(_dibujar_agua)
	_mapa.add_child(_mapa_agua)
	_mapa_tinta = Control.new()
	_mapa_tinta.name = "Tinta"
	_mapa_tinta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mapa_tinta.draw.connect(_dibujar_mapa)
	_mapa.add_child(_mapa_tinta)
	_mapa_vivo = Control.new()
	_mapa_vivo.name = "LoQueSeMueve"
	_mapa_vivo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mapa_vivo.draw.connect(_dibujar_lo_que_se_mueve)
	_mapa.add_child(_mapa_vivo)
	_armar_morral()


func _process(_delta: float) -> void:
	if jugador == null or not is_instance_valid(jugador):
		return
	# Con un diálogo, un cartel o la intro en pantalla no hay brújula, y lo que estuviera abierto se cierra.
	if Historia.ocupado and abierto != "":
		cerrar()
	_brujula.visible = not Historia.ocupado and abierto == ""
	if _brujula.visible:
		_brujula.queue_redraw()
	if abierto == "mapa":
		_mapa_vivo.queue_redraw()


func _input(event: InputEvent) -> void:
	if jugador == null or not is_instance_valid(jugador) or get_tree().paused:
		return
	if abierto != "" and event.is_action_pressed("ui_cancel"):
		# Esc cierra lo que esté abierto, en vez de abrir la pausa (scripts/Ajustes.gd lo recibe después).
		get_viewport().set_input_as_handled()
		cerrar()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_M or event.keycode == KEY_I:
		get_viewport().set_input_as_handled()
		var que := "mapa" if event.keycode == KEY_M else "morral"
		if abierto == que:
			cerrar()
		elif not Historia.ocupado and jugador.get("titere") != true:
			abrir(que)


func abrir(que: String) -> void:
	abierto = que
	_velo.show()
	_mapa.visible = que == "mapa"
	_morral.visible = que == "morral"
	if que == "mapa":
		_acomodar_mapa()
		_mapa.queue_redraw()
		_mapa_agua.queue_redraw()
		_mapa_tinta.queue_redraw()
	else:
		_llenar_morral()


func cerrar() -> void:
	abierto = ""
	_velo.hide()
	_mapa.hide()
	_morral.hide()


# ------------------------------------------------------------------ la brújula

## Hacia dónde mira la cámara, en radianes desde el norte y girando hacia el este. En este mundo el
## norte es -Z y el este es +X.
func _rumbo() -> float:
	return -float(jugador.get("yaw"))


## Dónde cae en el borde de la brújula algo que está en ese rumbo (radianes desde el norte).
func _en_la_esfera(rumbo: float) -> Vector2:
	var a := rumbo - _rumbo()
	return Vector2(sin(a), -cos(a))


## El rumbo desde Zenón hasta ese punto del mundo (x, z).
func _rumbo_a(punto: Vector2) -> float:
	return atan2(punto.x - jugador.global_position.x, -(punto.y - jugador.global_position.z))


func _lejos(punto: Vector2) -> float:
	return Vector2(punto.x - jugador.global_position.x, punto.y - jugador.global_position.z).length()


func _dibujar_brujula() -> void:
	var b := _brujula
	var c := Vector2(b.size.x * 0.5, 62.0)
	var r := 46.0
	b.draw_circle(c, r + 7.0, Color(TIERRA, 0.5))
	b.draw_arc(c, r + 7.0, 0.0, TAU, 56, Color(CLARO, 0.45), 1.5, true)
	# Las ocho rayas y las cuatro letras, que giran con la mirada.
	for i in 8:
		var hacia := _en_la_esfera(i * PI / 4.0)
		b.draw_line(c + hacia * (r - (7.0 if i % 2 == 0 else 4.0)), c + hacia * r, Color(CLARO, 0.75), 1.5, true)
	for par: Array in [["N", 0.0], ["E", PI / 2.0], ["S", PI], ["O", -PI / 2.0]]:
		var donde: Vector2 = c + _en_la_esfera(par[1]) * (r - 19.0)
		var es_norte: bool = par[0] == "N"
		_letra(b, par[0], donde, 17 if es_norte else 14, Color(0.95, 0.5, 0.36) if es_norte else CLARO)
	# El sol, mientras está arriba del horizonte: un punto claro en el borde, por donde anda.
	var mundo := jugador.get_parent()
	var sol := mundo.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sol != null and sol.visible and sol.light_energy > 0.02:
		var al_sol := sol.global_transform.basis.z
		if al_sol.y > 0.03:
			b.draw_circle(c + _en_la_esfera(atan2(al_sol.x, -al_sol.z)) * (r + 7.0), 4.0, Color(1.0, 0.9, 0.62, 0.95))
	# El fogón (un punto color brasa) y Ceniza (una herradura), si no los tiene al lado.
	var fogon := mundo.get_node_or_null("FogonDeZenon") as Node3D
	if fogon != null and _lejos(Vector2(fogon.global_position.x, fogon.global_position.z)) > 25.0:
		b.draw_circle(c + _en_la_esfera(_rumbo_a(Vector2(fogon.global_position.x, fogon.global_position.z))) * (r - 5.0), 3.2, BRASA)
	var ceniza := mundo.get_node_or_null("Ceniza") as Node3D
	if ceniza != null and jugador.get("montado") != true and _lejos(Vector2(ceniza.global_position.x, ceniza.global_position.z)) > 8.0:
		_herradura(b, c + _en_la_esfera(_rumbo_a(Vector2(ceniza.global_position.x, ceniza.global_position.z))) * (r - 5.0), 4.5, CLARO)
	# Las señas: adónde hay algo que hacer (Historia.senias). Una rayita roja que cruza el borde.
	for punto in Historia.senias():
		if _lejos(punto) > 12.0:
			var hacia := _en_la_esfera(_rumbo_a(punto))
			b.draw_line(c + hacia * (r - 6.0), c + hacia * (r + 9.0), ROJO.lightened(0.15), 3.5, true)
	# La marca fija de arriba: hacia ahí mira Zenón.
	b.draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -r - 1.0), c + Vector2(-5.0, -r - 10.0), c + Vector2(5.0, -r - 10.0)]), CLARO)
	_letra(b, "M mapa · I morral", Vector2(c.x, c.y + r + 24.0), 12, Color(CLARO, 0.6))


func _letra(donde: Control, texto: String, centro: Vector2, cuerpo: int, color: Color) -> void:
	var ancho := _fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1.0, cuerpo).x
	donde.draw_string(_fuente, centro + Vector2(-ancho * 0.5, cuerpo * 0.36), texto, HORIZONTAL_ALIGNMENT_LEFT, -1.0, cuerpo, color)


func _herradura(donde: Control, centro: Vector2, radio: float, color: Color) -> void:
	donde.draw_arc(centro, radio, deg_to_rad(125.0), deg_to_rad(415.0), 14, color, 2.0, true)


# ------------------------------------------------------------------ el mapa

## De un punto del mundo (x, z) a su lugar en el papel.
func _al_papel(punto: Vector2) -> Vector2:
	return _marco.position + Vector2((punto.x - MAPA_X.x) / (MAPA_X.y - MAPA_X.x), (punto.y - MAPA_Z.x) / (MAPA_Z.y - MAPA_Z.x)) * _marco.size


## El papel ocupa casi toda la pantalla, con la proporción del recuadro del mundo que muestra.
func _acomodar_mapa() -> void:
	var pantalla := get_viewport().get_visible_rect().size
	var proporcion := (MAPA_X.y - MAPA_X.x) / (MAPA_Z.y - MAPA_Z.x)
	var ancho := minf(pantalla.x * 0.92 - 70.0, (pantalla.y * 0.92 - 118.0) * proporcion)
	var alto := ancho / proporcion
	_mapa.size = Vector2(ancho + 70.0, alto + 118.0)
	_mapa.position = ((pantalla - _mapa.size) * 0.5).round()
	_mapa_vivo.size = _mapa.size
	_mapa_tinta.size = _mapa.size
	_marco = Rect2(Vector2(35.0, 66.0), Vector2(ancho, alto))
	_mapa_agua.position = _marco.position
	_mapa_agua.size = _marco.size
	if _fondo == null:
		_pintar_fondo()


## El papel con los cerros: se mira la altura del terreno cada GRANO metros, una sola vez, y se
## pinta una imagen chica que después se estira (queda aguada, como una acuarela). Arriba de los
## cien metros, la nieve del paso.
func _pintar_fondo() -> void:
	var columnas := int((MAPA_X.y - MAPA_X.x) / GRANO)
	var filas := int((MAPA_Z.y - MAPA_Z.x) / GRANO)
	var imagen := Image.create(columnas, filas, false, Image.FORMAT_RGB8)
	var cerro := Color(0.56, 0.45, 0.31)
	var nieve := Color(0.9, 0.88, 0.8)
	for fila in filas:
		for columna in columnas:
			var x := MAPA_X.x + (columna + 0.5) * GRANO
			var z := MAPA_Z.x + (fila + 0.5) * GRANO
			var alto := Historia.altura_suelo(x, z)
			# Un grano de papel, siempre el mismo en cada lugar.
			var grano := fposmod(sin(columna * 12.9898 + fila * 78.233) * 43758.5453, 1.0) * 0.03 - 0.015
			var color := PAPEL.lerp(cerro, smoothstep(3.0, 110.0, alto) * 0.8).lerp(nieve, smoothstep(95.0, 150.0, alto))
			imagen.set_pixel(columna, fila, Color(color.r + grano, color.g + grano, color.b + grano))
	_fondo = ImageTexture.create_from_image(imagen)


## El papel, con su borde y los cerros.
func _dibujar_papel() -> void:
	_mapa.draw_rect(Rect2(Vector2.ZERO, _mapa.size), PAPEL.darkened(0.08))
	_mapa.draw_rect(Rect2(Vector2.ZERO, _mapa.size), TINTA, false, 3.0)
	if _fondo != null:
		_mapa.draw_texture_rect(_fondo, _marco, false)


## El agua: el Limay, el lago y la aguada, tal como son en el mundo (las mismas mallas de "Agua" en
## World.tscn, vistas desde arriba). Este dibujo está recortado al recuadro: el lago sigue más allá.
func _dibujar_agua() -> void:
	var aguas := jugador.get_parent().get_node_or_null("Agua")
	for agua in (aguas.get_children() if aguas != null else []):
		var malla := agua as MeshInstance3D
		if malla == null or malla.mesh == null or not malla.is_visible_in_tree() or malla.mesh.get_surface_count() == 0:
			continue
		var partes: Array = malla.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = partes[Mesh.ARRAY_VERTEX]
		var puntos := PackedVector2Array()
		for vertice in vertices:
			var en_el_mundo := malla.global_transform * vertice
			puntos.append(_al_papel(Vector2(en_el_mundo.x, en_el_mundo.z)) - _marco.position)
		var indices := PackedInt32Array()
		if partes[Mesh.ARRAY_INDEX] != null:
			indices = partes[Mesh.ARRAY_INDEX]
		else:
			indices = PackedInt32Array(range(puntos.size()))
		if puntos.size() >= 3 and indices.size() >= 3:
			RenderingServer.canvas_item_add_triangle_array(_mapa_agua.get_canvas_item(), indices, puntos, PackedColorArray([AGUA]))


func _dibujar_mapa() -> void:
	var m := _mapa_tinta
	m.draw_rect(_marco, Color(TINTA, 0.7), false, 1.5)
	m.draw_string(_fuente, Vector2(35.0, 44.0), "El pago", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, TINTA)
	var dicho := "Zenón no sabe leer: este mapa lo lleva en la cabeza."
	m.draw_string(_fuente, Vector2(m.size.x - 35.0 - _fuente.get_string_size(dicho, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x, 42.0), dicho,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(TINTA, 0.8))
	var mundo := jugador.get_parent()
	# El camino de huellas: un punto de tinta por cada tramo.
	for camino in ["Caminos/CaminoFortinTolderia", "Caminos/HuellasDeLaAguada"]:
		var huellas := mundo.get_node_or_null(camino)
		for tramo in (huellas.get_children() if huellas != null else []):
			if tramo is Node3D:
				m.draw_circle(_al_papel(Vector2(tramo.global_position.x, tramo.global_position.z)), 1.3, Color(TINTA, 0.55))
	# El agua y la cordillera, con su nombre.
	_rotulo(m, "Lago Nahuel Huapi", _al_papel(Vector2(-1420.0, 120.0)), 15, Color(TINTA, 0.75))
	_rotulo(m, "Río Limay", _al_papel(Vector2(-760.0, _cauce(-760.0) - 60.0)), 14, Color(TINTA, 0.75))
	# Los lugares ("mapa" > "lugares" en datos/historia.json). Los que están ocultos no salen.
	for lugar: Dictionary in Historia.datos.get("mapa", {}).get("lugares", []):
		var punto := Historia.lugar_del_mapa(lugar.get("en", lugar.get("nodo", "")))
		if not punto.is_finite():
			continue
		var p := _al_papel(punto)
		_dibujo(m, str(lugar.get("dibujo", "")), p)
		var nombre := str(lugar.get("nombre", ""))
		var ancho := _fuente.get_string_size(nombre, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14).x
		var corrido := Vector2(16.0, 5.0)
		match str(lugar.get("rotulo", "derecha")):
			"izquierda":
				corrido = Vector2(-16.0 - ancho, 5.0)
			"arriba":
				corrido = Vector2(-ancho * 0.5, -13.0)
			"abajo":
				corrido = Vector2(-ancho * 0.5, 24.0)
		m.draw_string(_fuente, p + corrido, nombre, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, TINTA)
	# El norte y la escala (mil varas son 866 metros).
	var norte := _marco.position + Vector2(_marco.size.x - 34.0, 52.0)
	m.draw_line(norte + Vector2(0.0, 22.0), norte + Vector2(0.0, -20.0), TINTA, 2.0, true)
	m.draw_colored_polygon(PackedVector2Array([norte + Vector2(0.0, -28.0), norte + Vector2(-6.0, -14.0), norte + Vector2(6.0, -14.0)]), TINTA)
	_letra(m, "N", norte + Vector2(0.0, 34.0), 15, TINTA)
	var vara := 866.0 / (MAPA_X.y - MAPA_X.x) * _marco.size.x
	var escala := _marco.position + Vector2(_marco.size.x - 30.0 - vara, _marco.size.y - 24.0)
	m.draw_line(escala, escala + Vector2(vara, 0.0), TINTA, 2.0)
	m.draw_line(escala + Vector2(0.0, -5.0), escala + Vector2(0.0, 5.0), TINTA, 2.0)
	m.draw_line(escala + Vector2(vara, -5.0), escala + Vector2(vara, 5.0), TINTA, 2.0)
	_letra(m, "mil varas", escala + Vector2(vara * 0.5, -12.0), 13, TINTA)
	# Al pie, qué es cada marca.
	var pie := Vector2(35.0, m.size.y - 22.0)
	_flecha(m, pie + Vector2(8.0, -5.0), 0.0, ROJO)
	m.draw_string(_fuente, pie + Vector2(24.0, 0.0), "Zenón", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, TINTA)
	_herradura(m, pie + Vector2(102.0, -5.0), 5.5, TINTA)
	m.draw_string(_fuente, pie + Vector2(116.0, 0.0), "Ceniza", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, TINTA)
	m.draw_arc(pie + Vector2(200.0, -5.0), 7.0, 0.0, TAU, 20, ROJO, 2.5, true)
	m.draw_string(_fuente, pie + Vector2(216.0, 0.0), "donde hay algo que hacer", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, TINTA)
	var cierre := "M o Esc: cerrar"
	m.draw_string(_fuente, Vector2(m.size.x - 35.0 - _fuente.get_string_size(cierre, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x, pie.y), cierre,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(TINTA, 0.8))


## Lo que cambia mientras se mira el mapa: las señas, Ceniza y Zenón (una flecha hacia donde mira).
func _dibujar_lo_que_se_mueve() -> void:
	if jugador == null or not is_instance_valid(jugador):
		return
	var v := _mapa_vivo
	for punto in Historia.senias():
		var p := _al_papel(punto)
		v.draw_arc(p, 15.0, 0.0, TAU, 28, ROJO, 3.0, true)
	var ceniza := jugador.get_parent().get_node_or_null("Ceniza") as Node3D
	if ceniza != null and jugador.get("montado") != true:
		_herradura(v, _al_papel(Vector2(ceniza.global_position.x, ceniza.global_position.z)), 6.0, TINTA)
	_flecha(v, _al_papel(Vector2(jugador.global_position.x, jugador.global_position.z)), _rumbo(), ROJO)


## Una punta de flecha que mira hacia ese rumbo (0 es el norte, arriba en el papel).
func _flecha(donde: Control, centro: Vector2, rumbo: float, color: Color) -> void:
	var adelante := Vector2(sin(rumbo), -cos(rumbo))
	var costado := Vector2(adelante.y, -adelante.x)
	var puntos := PackedVector2Array([centro + adelante * 11.0, centro - adelante * 7.0 + costado * 7.0, centro - adelante * 3.0, centro - adelante * 7.0 - costado * 7.0])
	donde.draw_colored_polygon(puntos, color)
	puntos.append(puntos[0])
	donde.draw_polyline(puntos, TINTA, 1.5, true)


func _rotulo(donde: Control, texto: String, centro: Vector2, cuerpo: int, color: Color) -> void:
	_letra(donde, texto, centro, cuerpo, color)


## Por dónde pasa el río en esa línea norte-sur: el punto más bajo del terreno al norte del llano.
func _cauce(x: float) -> float:
	var z_bajo := -300.0
	var bajo := 1e9
	var z := MAPA_Z.x
	while z < 150.0:
		var alto := Historia.altura_suelo(x, z)
		if alto < bajo:
			bajo = alto
			z_bajo = z
		z += 10.0
	return z_bajo


## El dibujito de cada lugar, a pluma. Los nombres van en "dibujo" de cada lugar del mapa.
func _dibujo(m: Control, cual: String, p: Vector2) -> void:
	match cual:
		"rancho":
			m.draw_rect(Rect2(p + Vector2(-6.0, -3.0), Vector2(12.0, 8.0)), TINTA, false, 1.8)
			m.draw_polyline(PackedVector2Array([p + Vector2(-8.0, -3.0), p + Vector2(0.0, -10.0), p + Vector2(8.0, -3.0)]), TINTA, 1.8, true)
		"fortin":
			m.draw_rect(Rect2(p + Vector2(-7.0, -6.0), Vector2(14.0, 12.0)), TINTA, false, 1.8)
			for esquina in [Vector2(-7.0, -6.0), Vector2(7.0, -6.0), Vector2(-7.0, 6.0), Vector2(7.0, 6.0)]:
				m.draw_circle(p + esquina, 2.0, TINTA)
			m.draw_line(p + Vector2(0.0, 2.0), p + Vector2(0.0, -15.0), TINTA, 1.5, true)
			m.draw_colored_polygon(PackedVector2Array([p + Vector2(0.0, -15.0), p + Vector2(7.0, -12.5), p + Vector2(0.0, -10.0)]), TINTA)
		"toldos", "carpas":
			var lugares := [Vector2(-7.0, 2.0), Vector2(1.0, -3.0), Vector2(8.0, 3.0)] if cual == "toldos" else [Vector2(-8.0, -3.0), Vector2(0.0, -3.0), Vector2(8.0, -3.0), Vector2(-4.0, 5.0), Vector2(4.0, 5.0)]
			for l: Vector2 in lugares:
				m.draw_polyline(PackedVector2Array([p + l + Vector2(-4.0, 3.0), p + l + Vector2(0.0, -4.0), p + l + Vector2(4.0, 3.0), p + l + Vector2(-4.0, 3.0)]), TINTA, 1.6, true)
		"palo":
			m.draw_line(p + Vector2(0.0, 5.0), p + Vector2(0.0, -11.0), TINTA, 1.8, true)
			m.draw_polyline(PackedVector2Array([p + Vector2(0.0, -11.0), p + Vector2(3.0, -15.0), p + Vector2(1.0, -19.0), p + Vector2(5.0, -23.0)]), Color(TINTA, 0.6), 1.5, true)
		"piedras":
			for l in [Vector2(-4.0, 3.0), Vector2(4.0, 3.0), Vector2(0.0, -3.0)]:
				m.draw_circle(p + l, 3.4, TINTA)
		"agua":
			for alto in [-3.0, 3.0]:
				m.draw_polyline(PackedVector2Array([p + Vector2(-8.0, alto), p + Vector2(-4.0, alto - 2.5), p + Vector2(0.0, alto), p + Vector2(4.0, alto + 2.5), p + Vector2(8.0, alto)]), TINTA, 1.6, true)
		"fogon":
			m.draw_circle(p, 5.0, BRASA.darkened(0.15))
			m.draw_arc(p, 5.0, 0.0, TAU, 16, TINTA, 1.6, true)
		"monte":
			for l in [Vector2(-5.0, 2.0), Vector2(4.0, 3.0), Vector2(0.0, -4.0)]:
				m.draw_arc(p + l, 3.6, 0.0, TAU, 12, TINTA, 1.5, true)
		"paso":
			m.draw_polyline(PackedVector2Array([p + Vector2(-13.0, 6.0), p + Vector2(-6.0, -7.0), p + Vector2(0.0, 3.0), p + Vector2(7.0, -9.0), p + Vector2(14.0, 6.0)]), TINTA, 1.8, true)
		_:
			m.draw_circle(p, 3.0, TINTA)


# ------------------------------------------------------------------ el morral

func _armar_morral() -> void:
	_morral = PanelContainer.new()
	_morral.name = "LoQueLleva"
	_morral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caja := StyleBoxFlat.new()
	caja.bg_color = TIERRA
	caja.border_color = Color(APAGADO, 0.5)
	caja.set_border_width_all(2)
	caja.set_content_margin_all(28.0)
	_morral.add_theme_stylebox_override("panel", caja)
	_morral.set_anchors_preset(Control.PRESET_CENTER)
	_morral.custom_minimum_size = Vector2(640.0, 0.0)
	_morral.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_morral.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 5)
	_morral.add_child(_lista)
	_morral.hide()
	add_child(_morral)


func _renglon(texto: String, cuerpo: int, color: Color, espacio_arriba := 0.0) -> void:
	if espacio_arriba > 0.0:
		var hueco := Control.new()
		hueco.custom_minimum_size = Vector2(0.0, espacio_arriba)
		_lista.add_child(hueco)
	var renglon := Label.new()
	renglon.text = texto
	renglon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	renglon.custom_minimum_size = Vector2(584.0, 0.0)
	renglon.add_theme_font_size_override("font_size", cuerpo)
	renglon.add_theme_color_override("font_color", color)
	_lista.add_child(renglon)


## Vuelve a escribir la lista con lo que Zenón lleva en este momento (Historia.lo_que_lleva).
func _llenar_morral() -> void:
	for viejo in _lista.get_children():
		_lista.remove_child(viejo)
		viejo.queue_free()
	_renglon("El morral", 30, CLARO)
	var cosas: Array = Historia.lo_que_lleva()
	for parte: Array in [["encima", "Encima"], ["recado", "Cargado en Ceniza"]]:
		var de_esta: Array = cosas.filter(func(cosa: Dictionary) -> bool: return cosa.donde == parte[0])
		if de_esta.is_empty():
			continue
		_renglon(parte[1], 15, Color(APAGADO, 0.8), 12.0)
		for cosa: Dictionary in de_esta:
			_renglon(str(cosa.nombre) + ("  × %d" % int(cosa.cuantas) if int(cosa.cuantas) > 1 else ""), 21, CLARO, 4.0)
			if str(cosa.texto) != "":
				_renglon(str(cosa.texto), 16, APAGADO)
	var cuenta := "La cuenta en lo de Don Ceferino: %d patacones." % Historia.deuda if Historia.deuda > 0 else "La cuenta en lo de Don Ceferino está saldada."
	_renglon(cuenta, 19, CLARO, 18.0)
	_renglon("Plata encima, ninguna.", 16, APAGADO)
	_renglon("I o Esc: cerrar", 14, Color(APAGADO, 0.75), 14.0)

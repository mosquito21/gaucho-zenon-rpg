extends CanvasLayer

## El cuadro de diálogo, los carteles a pantalla oscura ("Pasaron las semanas…") y el epílogo.
## Lo crea scripts/Historia.gd y solo dibuja: qué se dice y qué cambia lo decide Historia
## con los textos de datos/historia.json.
##
## Teclas: E, Enter o clic para seguir; los números, las flechas y Enter, o clic para elegir.

const TIERRA := Color(0.07, 0.055, 0.04, 0.9)
const CLARO := Color(0.96, 0.91, 0.78)
const APAGADO := Color(0.78, 0.7, 0.55)
const ROJO := Color(0.62, 0.25, 0.2)

var _panel: PanelContainer
var _quien: Label
var _texto: Label
var _opciones: VBoxContainer
var _seguir: Label
var _telon: ColorRect
var _telon_titulo: Label
var _telon_texto: Label
var _telon_seguir: Label

var _paginas: Array = []
var _pagina := 0
var _textos_opciones: Array = []
# Qué se está mostrando: "" nada, "dialogo", "telon" (cartel o epílogo).
var _modo := ""
var _al_terminar := Callable()
var _telon_listo := false
var _mouse_antes := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_armar_cuadro()
	_armar_telon()
	_panel.hide()
	_telon.hide()


func _armar_cuadro() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -560.0
	_panel.offset_right = 560.0
	_panel.offset_bottom = -48.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = TIERRA
	fondo.border_color = Color(0.35, 0.28, 0.2)
	fondo.set_border_width_all(1)
	fondo.set_corner_radius_all(4)
	fondo.set_content_margin_all(26.0)
	_panel.add_theme_stylebox_override("panel", fondo)
	add_child(_panel)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 12)
	_panel.add_child(caja)

	_quien = Label.new()
	_quien.add_theme_font_size_override("font_size", 22)
	_quien.add_theme_color_override("font_color", ROJO.lightened(0.25))
	caja.add_child(_quien)

	_texto = Label.new()
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto.custom_minimum_size = Vector2(1060.0, 0.0)
	_texto.add_theme_font_size_override("font_size", 26)
	_texto.add_theme_color_override("font_color", CLARO)
	caja.add_child(_texto)

	_opciones = VBoxContainer.new()
	_opciones.add_theme_constant_override("separation", 4)
	caja.add_child(_opciones)

	_seguir = Label.new()
	_seguir.text = "E para seguir"
	_seguir.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_seguir.add_theme_font_size_override("font_size", 16)
	_seguir.add_theme_color_override("font_color", APAGADO)
	caja.add_child(_seguir)


func _armar_telon() -> void:
	_telon = ColorRect.new()
	_telon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_telon.color = Color(0.04, 0.035, 0.03)
	add_child(_telon)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_telon.add_child(centro)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 28)
	centro.add_child(caja)
	_telon_titulo = Label.new()
	_telon_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_telon_titulo.add_theme_font_size_override("font_size", 40)
	_telon_titulo.add_theme_color_override("font_color", CLARO)
	caja.add_child(_telon_titulo)
	_telon_texto = Label.new()
	_telon_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_telon_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_telon_texto.custom_minimum_size = Vector2(980.0, 0.0)
	_telon_texto.add_theme_font_size_override("font_size", 28)
	_telon_texto.add_theme_color_override("font_color", CLARO)
	caja.add_child(_telon_texto)
	_telon_seguir = Label.new()
	_telon_seguir.text = "E para seguir"
	_telon_seguir.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_telon_seguir.add_theme_font_size_override("font_size", 16)
	_telon_seguir.add_theme_color_override("font_color", APAGADO)
	caja.add_child(_telon_seguir)


## El cuadro está pegado abajo y crece hacia arriba. Un control suelto no se achica solo
## cuando su contenido se achica (ni cuando un texto termina de partirse en renglones),
## así que mientras está a la vista se le pone el alto justo.
func _process(_delta: float) -> void:
	if _panel.visible:
		_panel.offset_top = _panel.offset_bottom - _panel.get_combined_minimum_size().y


# ------------------------------------------------------------------ diálogo

## vista: {"quien": String, "paginas": [String], "opciones": [String]} (la arma Historia.vista()).
func mostrar(vista: Dictionary) -> void:
	if _modo == "":
		_mouse_antes = Input.get_mouse_mode()
	_modo = "dialogo"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_quien.text = str(vista.get("quien", ""))
	_quien.visible = _quien.text != ""
	_paginas = vista.get("paginas", [])
	_textos_opciones = vista.get("opciones", [])
	_pagina = 0
	_panel.show()
	_pintar_pagina()


func _pintar_pagina() -> void:
	_texto.text = str(_paginas[_pagina]) if _pagina < _paginas.size() else ""
	for boton in _opciones.get_children():
		_opciones.remove_child(boton)
		boton.queue_free()
	var ultima := _pagina >= _paginas.size() - 1
	var con_opciones := ultima and not _textos_opciones.is_empty()
	_seguir.text = "E para seguir"
	if not con_opciones:
		return
	var numeros := PackedStringArray()
	for i in _textos_opciones.size():
		numeros.append(str(i + 1))
	_seguir.text = "%s o el mouse para elegir" % ", ".join(numeros)
	for i in _textos_opciones.size():
		var boton := Button.new()
		boton.text = "%d.  %s" % [i + 1, _textos_opciones[i]]
		boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
		boton.flat = true
		# Una opción larga parte el renglón en vez de ensanchar el cuadro. El ancho fijo hace
		# falta para que el botón sepa dónde cortar.
		boton.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		boton.custom_minimum_size = Vector2(1060.0, 0.0)
		boton.add_theme_font_size_override("font_size", 23)
		boton.add_theme_color_override("font_color", APAGADO)
		boton.add_theme_color_override("font_hover_color", CLARO)
		boton.add_theme_color_override("font_focus_color", CLARO)
		boton.pressed.connect(_elegir.bind(i))
		# Ninguna opción arranca enfocada: si no, el Enter de pasar páginas (o el Espacio) elegía la
		# primera sin querer. La primera flecha enfoca (ver _input).
		_opciones.add_child(boton)


func _elegir(indice: int) -> void:
	if _modo == "dialogo":
		Historia.elegir(indice)


func cerrar() -> void:
	if _modo != "dialogo":
		return
	_modo = ""
	_panel.hide()
	Input.set_mouse_mode(_mouse_antes)


# ------------------------------------------------------------------ carteles y epílogo

## Oscurece la pantalla, muestra unas líneas ("Pasaron las semanas…") y vuelve al juego.
## al_medio se llama con la pantalla ya tapada (para mover cosas sin que se vea).
## Con ya_tapada, la pantalla arranca oscura en vez de oscurecerse (el cartel del arranque).
func fundido(lineas: Array, al_terminar: Callable, al_medio := Callable(), ya_tapada := false) -> void:
	_abrir_telon("", lineas, Color(0.04, 0.035, 0.03), al_terminar, al_medio)
	if ya_tapada:
		_telon.modulate.a = 1.0


## El cierre de la historia: título, páginas de texto y vuelta al menú.
func epilogo(titulo: String, paginas: Array, color: Color, al_terminar: Callable) -> void:
	_abrir_telon(titulo, paginas, color, al_terminar)


func _abrir_telon(titulo: String, paginas: Array, color: Color, al_terminar: Callable, al_medio := Callable()) -> void:
	if _modo == "":
		_mouse_antes = Input.get_mouse_mode()
	_modo = "telon"
	_panel.hide()
	_paginas = paginas
	_pagina = 0
	_al_terminar = al_terminar
	_telon.color = color
	# Sobre un telón claro (la niebla del paso) la letra va oscura.
	var letra := CLARO if color.get_luminance() < 0.5 else Color(0.12, 0.1, 0.08)
	_telon_titulo.add_theme_color_override("font_color", letra)
	_telon_texto.add_theme_color_override("font_color", letra)
	_telon_seguir.add_theme_color_override("font_color", Color(letra, 0.6))
	_telon_titulo.text = titulo
	_telon_titulo.visible = titulo != ""
	_telon_texto.text = str(_paginas[0]) if not _paginas.is_empty() else ""
	_telon.modulate.a = 0.0
	_telon.show()
	_telon_listo = false
	var sube := create_tween()
	sube.tween_property(_telon, "modulate:a", 1.0, 0.8)
	# Recién con la pantalla tapada se mueven las cosas y se puede seguir.
	sube.tween_callback(func() -> void:
		if al_medio.is_valid():
			al_medio.call()
		_telon_listo = true)


func _seguir_telon() -> void:
	_pagina += 1
	if _pagina < _paginas.size():
		_telon_titulo.hide()
		_telon_texto.text = str(_paginas[_pagina])
		return
	_modo = ""
	var hecho := _al_terminar
	_al_terminar = Callable()
	var baja := create_tween()
	baja.tween_property(_telon, "modulate:a", 0.0, 0.6)
	baja.tween_callback(_telon.hide)
	Input.set_mouse_mode(_mouse_antes)
	if hecho.is_valid():
		hecho.call()


## Se sale al menú con algo en pantalla (por la pausa): se cierra todo sin avisarle a nadie.
func soltar() -> void:
	_modo = ""
	_al_terminar = Callable()
	_panel.hide()
	_telon.hide()


# ------------------------------------------------------------------ teclas

func _input(event: InputEvent) -> void:
	# Con el juego en pausa las teclas son del menú de pausa (scripts/Ajustes.gd).
	if _modo == "" or get_tree().paused:
		return
	# Espacio no cuenta para seguir: también es la tecla de saltar, y al cerrar el cuadro Zenón saltaba.
	var seguir: bool = event.is_action_pressed("interact") \
			or (event.is_action_pressed("ui_accept") and not event.is_action("jump")) \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if _modo == "telon":
		if seguir and _telon_listo:
			get_viewport().set_input_as_handled()
			_seguir_telon()
		return
	var eligiendo := _opciones.get_child_count() > 0
	if eligiendo:
		# Espacio es la tecla de saltar: con opciones a la vista no elige nada (antes apretaba la
		# opción enfocada, que en lo de Ceferino es saldar e irse).
		if event.is_action("jump"):
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			# Los números de arriba y los del teclado numérico.
			var numero: int = event.keycode - (KEY_KP_1 if event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9 else KEY_1)
			if numero >= 0 and numero < _textos_opciones.size():
				get_viewport().set_input_as_handled()
				_elegir(numero)
			elif get_viewport().gui_get_focus_owner() == null and (event.is_action("ui_down") or event.is_action("ui_up")):
				# La primera flecha enfoca una opción; de ahí en más, flechas y Enter como siempre.
				get_viewport().set_input_as_handled()
				(_opciones.get_child(0 if event.is_action("ui_down") else -1) as Control).grab_focus()
		return
	if seguir:
		get_viewport().set_input_as_handled()
		if _pagina < _paginas.size() - 1:
			_pagina += 1
			_pintar_pagina()
		else:
			Historia.avanzar()

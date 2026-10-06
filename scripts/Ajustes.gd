extends CanvasLayer

## Los ajustes del juego (volumen, mouse, pantalla, calidad de imagen) y el menú de pausa (tanda 9).
## Es un autoload: vive toda la partida, también en el menú principal. Dibuja sus dos menús por
## programa, como scripts/Dialogo.gd dibuja el cuadro de diálogo.
##
## Los ajustes se guardan en user://ajustes.cfg, aparte de la partida (empezar de nuevo no los
## borra). Esc abre y cierra la pausa cuando se está en el mundo; F11 cambia la pantalla completa.

const TIERRA := Color(0.07, 0.055, 0.04, 0.94)
const CLARO := Color(0.96, 0.91, 0.78)
const APAGADO := Color(0.78, 0.7, 0.55)

## Los valores de fábrica. "imagen" es "completa" o "liviana".
const DE_FABRICA := {"general": 1.0, "musica": 1.0, "sonidos": 1.0, "mouse": 1.0,
	"pantalla_completa": false, "imagen": "completa"}
## Qué canal de audio mueve cada volumen (default_bus_layout.tres).
const CANALES := {"general": "Master", "musica": "Musica", "sonidos": "Sonidos"}
## La imagen liviana, para compus modestas: cada número es lo que vale ahí lo que en la completa
## vale lo que diga la escena o el proyecto.
##   escala: la imagen del mundo se dibuja a esa fracción del tamaño y después se agranda;
##   sombras_hasta: hasta cuántos metros llegan las sombras del sol;
##   sombras_mapa: el lado, en puntos, de la imagen donde se dibujan esas sombras;
##   matas: cuánto de lejos y de tupido se dibuja el pasto (1 es todo);
##   piso: el detalle del piso de lejos (el mínimo que acepta el terreno es 2).
## Además apaga el suavizado de bordes, el sombreado de rincones y las sombras de la luna.
const LIVIANA := {"escala": 0.7, "sombras_hasta": 80.0, "sombras_mapa": 2048, "matas": 0.7, "piso": 2.0}

var valores := DE_FABRICA.duplicate()
## Por cuánto se multiplica la sensibilidad del mouse (lo lee scenes/player/player.gd).
var mouse := 1.0

var _ruta := "user://ajustes.cfg"
var _velo: ColorRect
var _pausa: PanelContainer
var _ajustes: PanelContainer
var _nota: Label
var _boton_menu: Button
var _foco_antes: Control
var _controles := {}
var _desde_el_menu := false
var _mouse_antes := Input.MOUSE_MODE_CAPTURED
# Cómo venían el proyecto y la escena, para volver de la imagen liviana a la completa.
var _volumen_base := {}
var _de_fabrica := {}
var _de_escena := {}


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Las pruebas que corren el juego solas usan sus propios ajustes, para no tocar los de quien juega.
	if OS.get_cmdline_user_args().has("--partida-de-prueba"):
		_ruta = "user://ajustes_prueba.cfg"
	for canal: String in CANALES.values():
		var i := AudioServer.get_bus_index(canal)
		if i >= 0:
			_volumen_base[canal] = AudioServer.get_bus_volume_db(i)
	_de_fabrica = {
		"msaa": get_viewport().msaa_3d,
		"sombras_mapa": int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)),
		"sombras_filtro": int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)),
	}
	DisplayServer.window_set_title("El Gaucho Zenón")
	_leer()
	_armar()
	_aplicar()
	get_tree().scene_changed.connect(_al_cambiar_de_escena)
	# Si el mundo se abre derecho desde el editor (sin pasar por el menú) no hay cambio de escena:
	# la segunda pasada de la imagen, que alcanza a la luna, se pide acá.
	get_tree().create_timer(0.5).timeout.connect(_aplicar_imagen)


## Si se cierra la ventana con los ajustes a la vista, se guardan igual.
func _notification(que: int) -> void:
	if que == NOTIFICATION_WM_CLOSE_REQUEST:
		_guardar()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		poner("pantalla_completa", not bool(valores.pantalla_completa))
		_guardar()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _velo.visible:
		get_viewport().set_input_as_handled()
		if _ajustes.visible and not _desde_el_menu:
			_mostrar(_pausa)
		else:
			cerrar()
	elif _en_el_mundo():
		get_viewport().set_input_as_handled()
		abrir_pausa()


func _en_el_mundo() -> bool:
	var escena := get_tree().current_scene
	return escena != null and escena.get_node_or_null("Player") != null


# ------------------------------------------------------------------ pausa

## Detiene el juego y muestra el menú de pausa. La música sigue.
func abrir_pausa() -> void:
	_mouse_antes = Input.get_mouse_mode()
	_desde_el_menu = false
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var guarda := Historia.se_puede_guardar()
	_boton_menu.text = "Guardar y volver al menú" if guarda else "Volver al menú"
	_nota.text = "" if guarda else "Con un diálogo abierto o un final ya elegido no se guarda:\nal volver, seguís desde el último guardado."
	_nota.visible = not guarda
	_mostrar(_pausa)


## Los ajustes, desde el menú principal (sin pausa: ahí no hay nada que detener).
func abrir_ajustes() -> void:
	_desde_el_menu = true
	_foco_antes = get_viewport().gui_get_focus_owner()
	_mostrar(_ajustes)


## Cierra lo que haya abierto y, si había pausa, sigue el juego con el mouse como estaba.
func cerrar() -> void:
	_guardar()
	_velo.hide()
	# En el menú principal, el botón que estaba marcado vuelve a estarlo (para seguir con el teclado).
	if _desde_el_menu and is_instance_valid(_foco_antes):
		_foco_antes.grab_focus()
	_foco_antes = null
	if get_tree().paused:
		get_tree().paused = false
		Input.set_mouse_mode(_mouse_antes)


func _mostrar(panel: PanelContainer) -> void:
	_velo.show()
	_pausa.visible = panel == _pausa
	_ajustes.visible = panel == _ajustes
	_pintar()
	# El primer botón queda marcado, para manejarse también con las flechas y Enter.
	var botones := panel.find_children("*", "Button", true, false)
	if not botones.is_empty():
		(botones[0] as Button).grab_focus()


func _al_menu() -> void:
	Historia.guardar_al_salir()
	_guardar()
	_velo.hide()
	get_tree().paused = false
	Historia.dejar_el_mundo()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _salir() -> void:
	Historia.guardar_al_salir()
	_guardar()
	get_tree().quit()


# ------------------------------------------------------------------ valores

## Cambia un ajuste y lo aplica en el momento.
func poner(clave: String, valor: Variant) -> void:
	valores[clave] = valor
	_aplicar()
	_pintar()


func _leer() -> void:
	var archivo := ConfigFile.new()
	if archivo.load(_ruta) != OK:
		return
	for clave: String in DE_FABRICA:
		var valor = archivo.get_value("ajustes", clave, DE_FABRICA[clave])
		# Un archivo tocado a mano con un valor de otro tipo no rompe nada: queda el de fábrica.
		if typeof(valor) == typeof(DE_FABRICA[clave]) or (valor is int and DE_FABRICA[clave] is float):
			valores[clave] = valor
	# Y un número fuera de lugar (o que no es un número) vuelve al rango de su barra.
	for clave: String in ["general", "musica", "sonidos", "mouse"]:
		var n := float(valores[clave])
		var del_mouse := clave == "mouse"
		valores[clave] = float(DE_FABRICA[clave]) if is_nan(n) else clampf(n, 0.3 if del_mouse else 0.0, 2.5 if del_mouse else 1.0)


func _guardar() -> void:
	var archivo := ConfigFile.new()
	for clave: String in valores:
		archivo.set_value("ajustes", clave, valores[clave])
	archivo.save(_ruta)


func _aplicar() -> void:
	for clave: String in CANALES:
		var i := AudioServer.get_bus_index(CANALES[clave])
		if i < 0:
			continue
		var cuanto := clampf(float(valores[clave]), 0.0, 1.0)
		AudioServer.set_bus_mute(i, cuanto <= 0.001)
		AudioServer.set_bus_volume_db(i, float(_volumen_base.get(CANALES[clave], 0.0)) + linear_to_db(maxf(cuanto, 0.001)))
	mouse = clampf(float(valores.mouse), 0.2, 3.0)
	var modo := DisplayServer.window_get_mode()
	var esta_completa := modo == DisplayServer.WINDOW_MODE_FULLSCREEN or modo == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if bool(valores.pantalla_completa) != esta_completa:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(valores.pantalla_completa) else DisplayServer.WINDOW_MODE_MAXIMIZED)
	_aplicar_imagen()


## La calidad de imagen. Lo que es de la pantalla se aplica siempre; lo que es del mundo (el sol,
## el pasto, el piso), cuando hay un mundo cargado. Se puede cambiar en medio de la partida.
func _aplicar_imagen() -> void:
	var liviana := str(valores.imagen) == "liviana"
	var vista := get_viewport()
	vista.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if liviana else Viewport.SCALING_3D_MODE_BILINEAR
	vista.scaling_3d_scale = float(LIVIANA.escala) if liviana else 1.0
	vista.msaa_3d = Viewport.MSAA_DISABLED if liviana else (_de_fabrica.msaa as Viewport.MSAA)
	RenderingServer.directional_shadow_atlas_set_size(int(LIVIANA.sombras_mapa) if liviana else int(_de_fabrica.sombras_mapa), true)
	RenderingServer.directional_soft_shadow_filter_set_quality((RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if liviana else int(_de_fabrica.sombras_filtro)) as RenderingServer.ShadowQuality)
	if not _en_el_mundo():
		return
	var mundo := get_tree().current_scene
	var sol := mundo.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sol != null:
		if not _de_escena.has("sol"):
			_de_escena["sol"] = [sol.directional_shadow_max_distance, sol.directional_shadow_mode, sol.directional_shadow_blend_splits]
		var antes: Array = _de_escena["sol"]
		sol.directional_shadow_max_distance = float(LIVIANA.sombras_hasta) if liviana else float(antes[0])
		sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if liviana else (antes[1] as DirectionalLight3D.ShadowMode)
		sol.directional_shadow_blend_splits = false if liviana else bool(antes[2])
	# La luna la crea scripts/CicloDiaNoche.gd un instante después de arrancar: por eso esto se
	# aplica dos veces al entrar al mundo (ver _al_cambiar_de_escena).
	var luna := mundo.get_node_or_null("Luna") as DirectionalLight3D
	if luna != null:
		luna.shadow_enabled = not liviana
	var ambiente := mundo.get_node_or_null("Ambiente_Patagonia") as WorldEnvironment
	if ambiente != null and ambiente.environment != null:
		ambiente.environment.ssao_enabled = not liviana
	var terreno := mundo.get_node_or_null("HTerrain")
	if terreno != null and terreno.get("lod_scale") != null:
		if not _de_escena.has("piso"):
			_de_escena["piso"] = float(terreno.get("lod_scale"))
		terreno.set("lod_scale", float(LIVIANA.piso) if liviana else float(_de_escena["piso"]))
	var matas := mundo.get_node_or_null("GrassMMI")
	if matas != null and matas.has_method("poner_matas"):
		matas.call("poner_matas", float(LIVIANA.matas) if liviana else 1.0)


func _al_cambiar_de_escena() -> void:
	_de_escena = {}
	_aplicar_imagen()
	get_tree().create_timer(0.5).timeout.connect(_aplicar_imagen)


# ------------------------------------------------------------------ dibujo

func _armar() -> void:
	_velo = ColorRect.new()
	_velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_velo.color = Color(0.02, 0.015, 0.01, 0.6)
	_velo.hide()
	add_child(_velo)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_velo.add_child(centro)
	var pila := VBoxContainer.new()
	centro.add_child(pila)

	_ajustes = _panel(pila, "Ajustes")
	_deslizador("Volumen general", "general", 0.0, 1.0)
	_deslizador("Música", "musica", 0.0, 1.0)
	_deslizador("Sonidos", "sonidos", 0.0, 1.0)
	_deslizador("Mouse", "mouse", 0.3, 2.5)
	_controles["pantalla_completa"] = _boton(_ajustes, "", func() -> void: poner("pantalla_completa", not bool(valores.pantalla_completa)))
	_controles["imagen"] = _boton(_ajustes, "", func() -> void: poner("imagen", "completa" if str(valores.imagen) == "liviana" else "liviana"))
	# Pase libre de la tanda 9: por si alguien dejó el mouse imposible o el volumen en cero.
	_boton(_ajustes, "Volver a los de fábrica", func() -> void:
		valores = DE_FABRICA.duplicate()
		_aplicar()
		_pintar())
	_boton(_ajustes, "Volver", _volver)

	_pausa = _panel(pila, "Pausa")
	_boton(_pausa, "Seguir", cerrar)
	_boton(_pausa, "Ajustes", _mostrar.bind(_ajustes))
	_boton_menu = _boton(_pausa, "Guardar y volver al menú", _al_menu)
	_boton(_pausa, "Salir del juego", _salir)
	# Pase libre de la tanda 9: la pausa recuerda las teclas (se saca borrando estas líneas).
	var teclas := Label.new()
	teclas.text = "WASD andar · Shift correr · E usar y hablar · Tab acordarte adónde ir\nA caballo: E monta · Shift sube de marcha · S sofrena · Q se baja (a pie, silba)"
	teclas.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	teclas.add_theme_font_size_override("font_size", 16)
	teclas.add_theme_color_override("font_color", Color(APAGADO, 0.8))
	_caja(_pausa).add_child(teclas)
	_nota = Label.new()
	_nota.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nota.add_theme_font_size_override("font_size", 17)
	_nota.add_theme_color_override("font_color", APAGADO)
	_caja(_pausa).add_child(_nota)


func _volver() -> void:
	_guardar()
	if _desde_el_menu:
		cerrar()
	else:
		_mostrar(_pausa)


## Un panel de color tierra con su título; adentro, una columna donde van los botones.
func _panel(padre: Control, titulo: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = TIERRA
	fondo.border_color = Color(0.35, 0.28, 0.2)
	fondo.set_border_width_all(1)
	fondo.set_corner_radius_all(4)
	fondo.set_content_margin_all(30.0)
	panel.add_theme_stylebox_override("panel", fondo)
	panel.hide()
	padre.add_child(panel)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	panel.add_child(caja)
	var rotulo := Label.new()
	rotulo.text = titulo
	rotulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotulo.add_theme_font_size_override("font_size", 34)
	rotulo.add_theme_color_override("font_color", CLARO)
	caja.add_child(rotulo)
	return panel


func _caja(panel: PanelContainer) -> VBoxContainer:
	return panel.get_child(0) as VBoxContainer


func _boton(panel: PanelContainer, texto: String, accion: Callable) -> Button:
	var boton := Button.new()
	boton.text = texto
	boton.flat = true
	boton.custom_minimum_size = Vector2(520.0, 46.0)
	boton.add_theme_font_size_override("font_size", 26)
	boton.add_theme_color_override("font_color", APAGADO)
	boton.add_theme_color_override("font_hover_color", CLARO)
	boton.add_theme_color_override("font_focus_color", CLARO)
	boton.pressed.connect(accion)
	_caja(panel).add_child(boton)
	return boton


## Un renglón con su nombre, una barra para correr y cuánto vale, en porcentaje.
func _deslizador(nombre: String, clave: String, desde: float, hasta: float) -> void:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 16)
	var rotulo := Label.new()
	rotulo.text = nombre
	rotulo.custom_minimum_size = Vector2(200.0, 0.0)
	rotulo.add_theme_font_size_override("font_size", 22)
	rotulo.add_theme_color_override("font_color", CLARO)
	fila.add_child(rotulo)
	var barra := HSlider.new()
	barra.min_value = desde
	barra.max_value = hasta
	barra.step = 0.05
	barra.custom_minimum_size = Vector2(250.0, 30.0)
	barra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	barra.value_changed.connect(func(valor: float) -> void:
		if not is_equal_approx(float(valores[clave]), valor):
			poner(clave, valor))
	fila.add_child(barra)
	var cuanto := Label.new()
	cuanto.custom_minimum_size = Vector2(54.0, 0.0)
	cuanto.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cuanto.add_theme_font_size_override("font_size", 20)
	cuanto.add_theme_color_override("font_color", APAGADO)
	fila.add_child(cuanto)
	_caja(_ajustes).add_child(fila)
	_controles[clave] = [barra, cuanto]


## Pone en los controles lo que valen los ajustes ahora.
func _pintar() -> void:
	for clave: String in _controles:
		var control = _controles[clave]
		if control is Array:
			(control[0] as HSlider).set_value_no_signal(float(valores[clave]))
			(control[1] as Label).text = "%d %%" % roundi(float(valores[clave]) * 100.0)
	(_controles["pantalla_completa"] as Button).text = "Pantalla completa (F11): %s" % ("sí" if bool(valores.pantalla_completa) else "no")
	(_controles["imagen"] as Button).text = "Imagen: %s" % ("liviana (para compus modestas)" if str(valores.imagen) == "liviana" else "completa")

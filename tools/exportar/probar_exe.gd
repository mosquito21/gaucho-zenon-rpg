extends Node

## Prueba la versión exportada sin manos (tanda 9). Los juegos exportados ya no aceptan "--script",
## así que la carga el propio juego, y solo si es una versión de depuración (scripts/Historia.gd,
## _correr_prueba_de_afuera):
##   py tools/exportar/exportar.py --depuracion
##   GauchoZenon.console.exe --audio-driver Dummy -- --partida-de-prueba
##       --probar=<proyecto>/tools/exportar/probar_exe.gd --repo=<proyecto> --salida=<carpeta>
## Mira el menú, empieza una partida nueva de prueba, comprueba que estén la música, la historia, el
## terreno, la gente y los sonidos, juega un tramo con tools/pruebas/recorrida.gd (leída del
## proyecto: no va en el paquete), pausa, vuelve al menú, continúa, y deja en la carpeta de salida
## unas capturas y resultado.txt. Sin "--partida-de-prueba" no hace nada: nunca toca la partida de
## quien juega.

var repo := ""
var salida := ""
var lineas: Array = []
var fallas := 0
var _paso := 0
var _t := 0.0
var _total := 0.0
var _recorrida: Node
var _cuadros := 0
var _lugar := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argumento in OS.get_cmdline_user_args():
		if argumento.begins_with("--repo="):
			repo = argumento.trim_prefix("--repo=")
		elif argumento.begins_with("--salida="):
			salida = argumento.trim_prefix("--salida=")
	if not OS.get_cmdline_user_args().has("--partida-de-prueba") or repo == "" or salida == "":
		printerr("Falta --partida-de-prueba, --repo=<proyecto> o --salida=<carpeta>: no hago nada.")
		set_process(false)
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(salida)
	var h := get_node("/root/Historia")
	if not str(h.get("ruta_partida")).ends_with("partida_prueba.json"):
		_falla("la partida no es la de prueba (%s): no sigo" % str(h.get("ruta_partida")))
		_terminar()
		return
	# Una partida de prueba nueva: se borran solo los archivos de prueba.
	for nombre in ["partida_prueba.json", "abril_prueba.json", "partida_terminada_prueba.json", "ajustes_prueba.cfg"]:
		if FileAccess.file_exists("user://" + nombre):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + nombre))
	_anotar("motor %s | plantilla %s | editor %s | depuración %s" % [Engine.get_version_info().string, str(OS.has_feature("template")), str(OS.has_feature("editor")), str(OS.is_debug_build())])
	_anotar("audio: %s | ventana %s | video: %s" % [AudioServer.get_driver_name(), str(get_viewport().get_visible_rect().size), RenderingServer.get_video_adapter_name()])
	# Los archivos de prueba se borraron con el menú ya armado: se lo vuelve a cargar, de cero.
	get_tree().change_scene_to_file.call_deferred("res://scenes/MainMenu.tscn")

func _anotar(texto: String) -> void:
	lineas.append(texto)
	print("[prueba] " + texto)

func _falla(texto: String) -> void:
	fallas += 1
	_anotar("FALLA: " + texto)

func _espero(condicion: bool, que: String) -> void:
	if condicion:
		_anotar("bien: " + que)
	else:
		_falla(que)

func _foto(nombre: String) -> void:
	get_viewport().get_texture().get_image().save_png(salida.path_join(nombre + ".png"))

func _boton(empieza_con: String) -> Button:
	for b in get_tree().current_scene.find_children("*", "Button", true, false):
		if str(b.text).begins_with(empieza_con):
			return b
	return null

func _tecla_e() -> void:
	var e := InputEventAction.new()
	e.action = "interact"
	e.pressed = true
	Input.parse_input_event(e)

func _siguiente() -> void:
	_paso += 1
	_t = 0.0

func _terminar() -> void:
	_anotar("FALLAS: %d" % fallas)
	var archivo := FileAccess.open(salida.path_join("resultado.txt"), FileAccess.WRITE)
	if archivo != null:
		archivo.store_string("\n".join(lineas) + "\n")
		archivo.close()
	get_tree().quit(1 if fallas > 0 else 0)

func _process(delta: float) -> void:
	_t += delta
	_total += delta
	_cuadros += 1
	if _total > 420.0:
		_falla("pasaron siete minutos y la prueba no terminó (paso %d)" % _paso)
		_terminar()
		return
	var escena := get_tree().current_scene
	if escena == null:
		return
	var h := get_node("/root/Historia")
	var ajustes := get_node("/root/Ajustes")
	var musica := get_node("/root/ManejadorMusica")
	match _paso:
		0:  # El menú principal.
			if _t < 2.0 or escena.scene_file_path != "res://scenes/MainMenu.tscn":
				return
			var textos: Array = []
			for b in escena.find_children("*", "Button", true, false):
				textos.append(b.text)
			_anotar("menú: %s" % str(textos))
			_espero(textos.has("Comenzar") and textos.has("Ajustes") and textos.has("Salir"), "el menú de una partida nueva tiene Comenzar, Ajustes y Salir")
			var rotulos: Array = []
			for r in escena.find_children("*", "Label", true, false):
				rotulos.append(r.text)
			_espero(rotulos.has("v" + str(ProjectSettings.get_setting("application/config/version", "?"))), "el menú dice la versión (%s)" % str(rotulos))
			var canciones: Array = musica.get("lista_canciones")
			_espero(canciones.size() == 8, "la música encontró ocho temas (encontró %d)" % canciones.size())
			_espero((musica.get("reproductor_musica") as AudioStreamPlayer).playing, "la música está sonando")
			_espero(not str(canciones).contains("Nada preso"), "'Nada preso en la mano' sigue afuera")
			_foto("1_menu")
			_boton("Comenzar").pressed.emit()
			_siguiente()
		1:  # El mundo: pasa el cartel de arranque.
			if escena.get_node_or_null("Player") == null or _t < 1.5:
				return
			if h.get("ocupado") == true:
				if fmod(_t, 0.5) < delta:
					_tecla_e()
				return
			_siguiente()
		2:  # Lo que tiene que estar.
			if _t < 2.0:
				return
			_espero((h.get("datos") as Dictionary).size() > 5, "la historia se leyó (datos/historia.json)")
			_espero((h.get("_personas") as Array).size() >= 20, "la gente está en el mundo (%d con quien hablar)" % (h.get("_personas") as Array).size())
			_espero(float(h.call("altura_suelo", -1545.0, 900.0)) > 50.0, "el terreno tiene su relieve (el portezuelo está a %.0f m)" % float(h.call("altura_suelo", -1545.0, 900.0)))
			var s := escena.get_node_or_null("Sonidos")
			_espero(s != null, "está el nodo Sonidos")
			if s != null:
				var viento := s.get("_viento") as AudioStreamPlayer
				_espero(viento != null and viento.stream != null and viento.playing, "el viento suena")
				_espero((s.get("_fuegos") as Array).size() == 10, "los diez fogones tienen su crepitar")
				var tomas := 0
				for voz in (s.get("_voces") as Dictionary).values():
					tomas += (voz as AudioStreamRandomizer).streams_count
				_espero(tomas == 14, "las voces de la hacienda están (14 tomas; hay %d)" % tomas)
				_espero(((s.get("_pasos") as Dictionary)["paso"] as AudioStreamPlayer).stream.streams_count == 5, "los pasos tienen sus cinco tomas")
				_espero(s.get("_suelos") != null, "se leyeron los suelos del terreno")
				_espero((s.get("_puntos_del_rio") as PackedVector3Array).size() > 100, "se midió el río")
			_espero(get_tree().get_nodes_in_group("hacienda").size() > 40, "los animales están (%d)" % get_tree().get_nodes_in_group("hacienda").size())
			_espero(AudioServer.get_bus_index("Musica") > 0 and AudioServer.get_bus_index("Sonidos") > 0, "están los canales Musica y Sonidos")
			_espero(escena.get_node_or_null("Luna") != null, "el día y la noche arrancaron (hay luna)")
			_cuadros = 0
			_siguiente()
		3:  # Cuadros por segundo, parado en el arranque (con el tope de siempre).
			if _t < 4.0:
				return
			_anotar("cuadros por segundo en el arranque, con el tope de la pantalla: %.0f" % (_cuadros / _t))
			_foto("2_arranque")
			# Un tramo jugado con las teclas: montar, galopar hasta la pulpería, bajarse y hablar con Ceferino.
			var fuente := FileAccess.get_file_as_string(repo.path_join("tools/pruebas/recorrida.gd"))
			var guion := GDScript.new()
			guion.source_code = fuente
			if fuente == "" or guion.reload() != OK:
				_falla("no pude cargar tools/pruebas/recorrida.gd desde %s" % repo)
				_paso = 5
				return
			_recorrida = guion.new()
			_recorrida.set("velocidad", 4.0)
			_recorrida.set("plan", [["esperar", 1.0], ["montar"], ["marcha", 3], ["ir", "frente_pulperia", 190.0, 172.0, 5.0],
				["marcha", 1], ["esperar", 2.0], ["desmontar"], ["hablar", "ceferino", ["con qué le he de pagar", "Voy."]],
				["espero", "H.flags.has(\"cuenta_vista\")", "Ceferino mostró la cuenta"]])
			get_tree().root.add_child(_recorrida)
			_siguiente()
		4:  # Espera a que termine el tramo.
			if _recorrida.get("listo") != true:
				return
			var fallas_del_tramo: Array = _recorrida.get("fallas")
			_espero(fallas_del_tramo.is_empty(), "el tramo jugado no tuvo fallas (%s)" % str(fallas_del_tramo))
			_anotar("tramo: %.0f s de juego, %.0f m, peor cuadro %.0f ms" % [float(_recorrida.get("total_s")), float(_recorrida.get("total_m")), float(_recorrida.get("peor_cuadro_ms"))])
			_anotar("saludaron: %s" % str((h.get("_saludo_de") as Dictionary).keys()))
			_recorrida.queue_free()
			_siguiente()
		5:  # La pausa.
			if _t < 1.5:
				return
			_foto("3_pulperia")
			_lugar = (escena.get_node("Player") as Node3D).global_position
			ajustes.call("abrir_pausa")
			_espero(get_tree().paused and (musica.get("reproductor_musica") as AudioStreamPlayer).playing, "con la pausa el juego se detiene y la música sigue")
			_siguiente()
		6:
			if _t < 0.6:
				return
			_foto("4_pausa")
			ajustes.call("_al_menu")
			_siguiente()
		7:  # De vuelta en el menú: continuar.
			if _t < 2.0 or escena.scene_file_path != "res://scenes/MainMenu.tscn":
				return
			var continuar := _boton("Continuar")
			_espero(continuar != null and not get_tree().paused, "al volver al menú hay partida para continuar (%s)" % (continuar.text if continuar != null else "no está"))
			if continuar == null:
				_terminar()
				return
			continuar.pressed.emit()
			_siguiente()
		8:  # Otra vez en el mundo, donde había quedado.
			if escena.get_node_or_null("Player") == null or _t < 3.0:
				return
			var ahora := (escena.get_node("Player") as Node3D).global_position
			_espero(ahora.distance_to(_lugar) < 2.5, "al continuar, Zenón está donde quedó (a %.1f m)" % ahora.distance_to(_lugar))
			_espero((h.get("flags") as Dictionary).has("cuenta_vista") and int(h.get("deuda")) == 180, "la historia se guardó (la cuenta vista, 180 patacones)")
			# La imagen liviana, un momento, para ver que el .exe la aguanta.
			ajustes.call("poner", "imagen", "liviana")
			_siguiente()
		9:
			if _t < 2.5:
				return
			_espero(is_equal_approx(get_viewport().scaling_3d_scale, 0.7), "la imagen liviana se aplicó")
			_foto("5_liviana")
			ajustes.call("poner", "imagen", "completa")
			_terminar()

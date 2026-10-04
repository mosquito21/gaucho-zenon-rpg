extends Node

## El estado de la historia de Zenón: en qué momento va la trama, qué pasó, la confianza
## oculta con cada bando y la cuenta de la pulpería. También abre los diálogos, el fogón
## y los finales, y guarda la partida.
##
## Todos los textos y los números están en datos/historia.json: acá no hay ningún diálogo.
## La lógica no necesita el mundo: tools/pruebas/probar_historia.gd la recorre sin abrirlo.

const RUTA_DATOS := "res://datos/historia.json"
const RUTA_PARTIDA := "user://partida.json"

var datos: Dictionary = {}

# 1 la cuenta, 2 los recados, 3 la línea, 4 el final elegido.
var momento := 1
var vars: Dictionary = {}
var flags: Dictionary = {}
var confianza: Dictionary = {}
var deuda := 0
## Lo que Zenón hizo hoy, para repasarlo en el fogón.
var notas: Array = []
var final_elegido := ""
var terminado := false

## Hay un diálogo, un fundido o un epílogo en pantalla: Zenón no se mueve.
var ocupado := false
## Con la que está hablando (la usa el gesto de hablar).
var hablando_con := ""

var _nodo: Dictionary = {}
var _quien := ""
var _visibles: Array = []
var _paginas: Array = []
var _sucio := false
var _pendiente_mundo := false
var _cuadro: Node
var _jugador: Node3D
var _mundo: Node
var _personas: Array = []
var _partida: Dictionary = {}
var _llegada_revisar := 0.0
var _en_fogon := false
var _ultimo_aviso := ""


func _init() -> void:
	_cargar_datos()
	nueva()


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/Dialogo.gd"):
		_cuadro = (load("res://scripts/Dialogo.gd") as GDScript).new()
		add_child(_cuadro)


# ------------------------------------------------------------------ datos y estado

func _cargar_datos() -> void:
	var texto := FileAccess.get_file_as_string(RUTA_DATOS)
	var json := JSON.new()
	if texto == "" or json.parse(texto) != OK:
		push_error("datos/historia.json no se pudo leer (línea %d): %s" % [json.get_error_line(), json.get_error_message()])
		datos = {}
		return
	datos = json.data


## Deja la historia como al empezar. No borra la partida guardada (eso es borrar_partida).
func nueva() -> void:
	var config: Dictionary = datos.get("config", {})
	momento = 1
	vars = {}
	flags = {}
	confianza = {}
	for bando in config.get("minimos", {}):
		confianza[bando] = 0
	deuda = int(config.get("deuda_inicial", 0))
	notas = []
	final_elegido = ""
	terminado = false
	ocupado = false
	_nodo = {}
	_partida = {}
	_sucio = false


func v(nombre: String) -> int:
	return int(vars.get(nombre, 0))


func poner(nombre: String, valor: int) -> void:
	if v(nombre) == valor:
		return
	vars[nombre] = valor
	_sucio = true
	# Los trabajos viejos (recado y seña) dejan su nota para el fogón desde acá.
	var nota: String = str(datos.get("notas_de_trabajos", {}).get("%s=%d" % [nombre, valor], ""))
	if nota != "":
		notas.append(nota)


## ¿Se cumple la condición? Es un diccionario; tienen que cumplirse todas sus claves.
## momento: 2 o [2, 3] · var: {"sena": 2} o {"sena": [2, 3]} · si / no: ["bandera"]
## min: {"ejercito": 3} (contra los mínimos de config si el valor es "minimo") · o: [cond, cond]
## menos: {"ejercito": "minimo"} (la confianza NO llega a ese valor) · final: "chile" (el final elegido)
func cumple(cond: Dictionary) -> bool:
	for clave in cond:
		var valor = cond[clave]
		match clave:
			"momento":
				if not _esta(momento, valor):
					return false
			"var":
				for nombre in valor:
					if not _esta(v(nombre), valor[nombre]):
						return false
			"si":
				for bandera in valor:
					if not flags.has(bandera):
						return false
			"no":
				for bandera in valor:
					if flags.has(bandera):
						return false
			"min":
				for bando in valor:
					var piso = valor[bando]
					if piso is String:
						piso = datos.get("config", {}).get("minimos", {}).get(bando, 0)
					if int(confianza.get(bando, 0)) < int(piso):
						return false
			"menos":
				for bando in valor:
					var techo = valor[bando]
					if techo is String:
						techo = datos.get("config", {}).get("minimos", {}).get(bando, 0)
					if int(confianza.get(bando, 0)) >= int(techo):
						return false
			"final":
				if final_elegido != str(valor):
					return false
			"o":
				var alguna := false
				for otra in valor:
					if cumple(otra):
						alguna = true
						break
				if not alguna:
					return false
			_:
				push_warning("historia.json: condición desconocida '%s'" % clave)
				return false
	return true


func _esta(numero: int, valor) -> bool:
	if valor is Array:
		for uno in valor:
			if int(uno) == numero:
				return true
		return false
	return int(valor) == numero


## Aplica lo que cambia una opción o un nodo.
## var: {"sena": 1} · flag: ["x"] · confianza: {"ejercito": 1} · deuda: -20 · nota: "..."
## momento: 3 · final: "sargento"
func aplicar(efectos: Dictionary) -> void:
	if efectos.is_empty():
		return
	_sucio = true
	for clave in efectos:
		var valor = efectos[clave]
		match clave:
			"var":
				for nombre in valor:
					poner(nombre, int(valor[nombre]))
			"flag":
				for bandera in valor:
					flags[bandera] = true
			"confianza":
				for bando in valor:
					confianza[bando] = int(confianza.get(bando, 0)) + int(valor[bando])
			"deuda":
				deuda = maxi(0, deuda + int(valor))
			"saldar":
				deuda = 0
			"nota":
				notas.append(str(valor))
			"momento":
				momento = int(valor)
				_pendiente_mundo = true
			"final":
				final_elegido = str(valor)
				momento = 4
				_pendiente_mundo = true
			_:
				push_warning("historia.json: efecto desconocido '%s'" % clave)


func _texto(crudo: String) -> String:
	return crudo.replace("{deuda}", str(deuda))


# ------------------------------------------------------------------ diálogos

## Abre la charla de un personaje. Devuelve falso si no tiene nada que decir.
func hablar(id: String) -> bool:
	var persona: Dictionary = datos.get("personajes", {}).get(id, {})
	if persona.is_empty() or ocupado:
		return false
	hablando_con = id
	if _mundo != null and is_instance_valid(_mundo):
		var cuerpo := _mundo.get_node_or_null(str(persona.get("nodo", "")))
		if cuerpo != null and cuerpo.has_method("gesto_de_hablar"):
			cuerpo.gesto_de_hablar()
	var nombre := str(persona.get("nombre", ""))
	return _entrar(str(persona.get("charla", "")), nombre.left(1).to_upper() + nombre.substr(1))


func _entrar(id_nodo: String, quien := "") -> bool:
	var nodos: Dictionary = datos.get("nodos", {})
	# Un nodo "segun" no se muestra: elige a cuál ir según lo que ya pasó.
	var vueltas := 0
	while nodos.has(id_nodo) and nodos[id_nodo].has("segun") and vueltas < 20:
		var destino := ""
		for rama in nodos[id_nodo]["segun"]:
			if cumple(rama.get("si", {})):
				destino = str(rama.get("ir", ""))
				break
		id_nodo = destino
		vueltas += 1
	if not nodos.has(id_nodo):
		if id_nodo != "":
			push_warning("historia.json: no existe el nodo '%s'" % id_nodo)
		_cerrar()
		return false
	_nodo = nodos[id_nodo]
	if quien != "":
		_quien = quien
	if _nodo.has("quien"):
		_quien = str(_nodo["quien"])
	aplicar(_nodo.get("hace", {}))
	var texto = _nodo.get("texto", "")
	_paginas = []
	for pagina in (texto if texto is Array else [texto]):
		_paginas.append(_texto(str(pagina)))
	_visibles = []
	for opcion in _nodo.get("opciones", []):
		if cumple(opcion.get("si", {})):
			_visibles.append(opcion)
	ocupado = true
	if _cuadro != null:
		_cuadro.mostrar(vista())
	return true


## Lo que hay que mostrar ahora: quién habla, las páginas de texto y las opciones.
func vista() -> Dictionary:
	if _nodo.is_empty():
		return {}
	var textos: Array = []
	for opcion in _visibles:
		textos.append(_texto(str(opcion.get("texto", ""))))
	return {"quien": _quien, "paginas": _paginas, "opciones": textos}


func elegir(indice: int) -> void:
	if indice < 0 or indice >= _visibles.size():
		return
	var opcion: Dictionary = _visibles[indice]
	aplicar(opcion.get("hace", {}))
	if opcion.has("ir") and opcion["ir"] != null:
		_entrar(str(opcion["ir"]))
	else:
		_cerrar()


## Sigue adelante en un nodo sin opciones.
func avanzar() -> void:
	if not _visibles.is_empty():
		return
	if _nodo.has("ir") and _nodo["ir"] != null:
		_entrar(str(_nodo["ir"]))
	else:
		_cerrar()


func _cerrar() -> void:
	var era_fogon := _en_fogon
	_en_fogon = false
	_nodo = {}
	_visibles = []
	ocupado = false
	hablando_con = ""
	if _cuadro != null:
		_cuadro.cerrar()
	if era_fogon:
		_amanecer()
	if _pendiente_mundo:
		_pendiente_mundo = false
		_al_cambiar_de_momento()
	elif _sucio and final_elegido == "":
		var aviso := _aviso_del_momento()
		if aviso != _ultimo_aviso:
			_avisar(aviso)
	if _sucio:
		guardar()


# ------------------------------------------------------------------ fogón

## Zenón se sienta al fogón: repasa el día, piensa en lo que falta y se guarda la partida.
## Si los tres encargos están resueltos, acá se cierra el capítulo.
func sentarse_al_fogon() -> void:
	if ocupado:
		return
	var fogon: Dictionary = datos.get("fogon", {})
	var paginas: Array = []
	if notas.is_empty():
		paginas.append(str(fogon.get("sin_notas", "")))
	else:
		# Si el día fue largo, repasa solo lo último.
		paginas.append_array(notas.slice(-int(fogon.get("notas_maximas", 6))))
	var efectos: Dictionary = {}
	for extra in fogon.get("pensamientos", []):
		if cumple(extra.get("si", {})):
			paginas.append(str(extra.get("texto", "")))
			if extra.has("una_vez"):
				efectos["flag"] = efectos.get("flag", []) + [extra["una_vez"]]
	var cierre: Dictionary = fogon.get("cierre", {})
	var ir = null
	if not cierre.is_empty() and cumple(cierre.get("si", {})):
		ir = cierre.get("ir")
	notas = []
	_sucio = true
	var ciclo := _ciclo()
	if ciclo != null:
		ciclo.establecer_hora(float(fogon.get("hora_noche", 22.0)))
	datos["nodos"]["_fogon"] = {"quien": str(fogon.get("quien", "Zenón")), "texto": paginas, "hace": efectos, "ir": ir}
	_entrar("_fogon")
	_en_fogon = true


func _amanecer() -> void:
	var ciclo := _ciclo()
	if ciclo != null:
		ciclo.establecer_hora(float(datos.get("fogon", {}).get("hora_amanecer", 7.0)))
	# El salto a la noche pudo dejar cargado un aviso ("Se hizo de noche…") que a las 7 ya no vale.
	if _jugador != null and is_instance_valid(_jugador) and _jugador.has_method("mostrar_aviso"):
		_jugador.mostrar_aviso("")


func _ciclo() -> Node:
	if _mundo == null or not is_instance_valid(_mundo):
		return null
	return _mundo.get_node_or_null("SistemaDiaNoche")


# ------------------------------------------------------------------ el mundo

## Lo llama el jugador al aparecer en la estepa.
func entrar_al_mundo(jugador: Node3D) -> void:
	_jugador = jugador
	_mundo = jugador.get_parent()
	_personas = []
	if _partida.is_empty() and momento == 1 and flags.is_empty() and FileAccess.file_exists(RUTA_PARTIDA):
		# World.tscn se abrió sin pasar por el menú: sigue la partida que haya.
		# Si esa partida ya llegó a un final, empieza una nueva.
		cargar()
		if terminado:
			borrar_partida()
	for id in datos.get("personajes", {}):
		var persona: Dictionary = datos["personajes"][id]
		var nodo := _mundo.get_node_or_null(str(persona.get("nodo", "")))
		if nodo == null:
			push_warning("historia.json: el personaje '%s' no encuentra su nodo '%s'" % [id, persona.get("nodo", "")])
			continue
		_personas.append(_sumar_interactuable(nodo, Interactable.Rol.PERSONA, id, str(persona.get("nombre", "")), float(persona.get("alcance", 3.2))))
	var fogon := _mundo.get_node_or_null(str(datos.get("fogon", {}).get("nodo", "")))
	if fogon != null:
		_personas.append(_sumar_interactuable(fogon, Interactable.Rol.FOGON, "", "", 3.0))
	_acomodar_mundo()
	if not _partida.is_empty():
		var pos: Array = _partida.get("pos", [])
		if pos.size() == 3:
			jugador.global_position = Vector3(pos[0], pos[1], pos[2])
		jugador.set("yaw", float(_partida.get("yaw", 0.0)))
		if _partida.has("hora"):
			# El ciclo de día y noche pone su hora inicial un cuadro después de arrancar:
			# la hora guardada se pone recién después.
			var hora := float(_partida["hora"])
			get_tree().create_timer(0.2).timeout.connect(func() -> void:
				var ciclo := _ciclo()
				if ciclo != null:
					ciclo.establecer_hora(hora))
	if datos.is_empty():
		_avisar("datos/historia.json está mal escrito: nadie habla hasta arreglarlo. La consola de Godot dice en qué línea.")
		return
	if final_elegido != "" and not flags.has("_final_listo"):
		# Se cerró el juego entre elegir el final y el cartel: se arma de nuevo.
		_empezar_final()
		return
	if final_elegido != "":
		_mover_gente_del_final()
	recordar()


func _sumar_interactuable(padre: Node, rol: int, id: String, nombre: String, alcance: float) -> Interactable:
	var area := Interactable.new()
	area.name = "Hablar"
	area.rol = rol
	area.personaje = id
	area.nombre = nombre
	area.alcance = alcance
	area.monitoring = false
	area.monitorable = false
	padre.add_child(area)
	return area


## La persona (o el fogón) más cercana que Zenón tiene adelante y a mano, o null.
func persona_cerca(jugador: Node3D) -> Interactable:
	var mejor: Interactable = null
	var mejor_dist := 1e9
	var frente := -jugador.global_transform.basis.z
	for area: Interactable in _personas:
		if not is_instance_valid(area) or not area.is_visible_in_tree():
			continue
		var hacia: Vector3 = area.global_position - jugador.global_position
		hacia.y = 0.0
		var dist := hacia.length()
		if dist > area.alcance or dist >= mejor_dist:
			continue
		if dist > 0.8 and frente.dot(hacia / dist) < 0.3:
			continue
		mejor = area
		mejor_dist = dist
	return mejor


## Prende o apaga los lugares que dependen de la trama (el campamento y el fortín nuevo
## aparecen cuando llega la línea).
func _acomodar_mundo() -> void:
	if _mundo == null or not is_instance_valid(_mundo):
		return
	for ruta in datos.get("config", {}).get("ocultos_hasta_la_linea", []):
		var lugar := _mundo.get_node_or_null(str(ruta)) as Node3D
		if lugar == null:
			continue
		var prendido := momento >= 3
		lugar.visible = prendido
		# Apagado, el nodo deja de procesar y sus cuerpos de choque salen de la física.
		lugar.process_mode = Node.PROCESS_MODE_INHERIT if prendido else Node.PROCESS_MODE_DISABLED


func _al_cambiar_de_momento() -> void:
	_acomodar_mundo()
	if final_elegido != "":
		_empezar_final()
		return
	var paso: Dictionary = datos.get("avisos", {})
	var cartel: Array = paso.get("cartel_momento_%d" % momento, [])
	if not cartel.is_empty() and _cuadro != null:
		ocupado = true
		var al_terminar := func() -> void:
			ocupado = false
			_avisar(_aviso_del_momento())
		_cuadro.fundido(cartel, al_terminar)
	else:
		_avisar(_aviso_del_momento())


## Vuelve a mostrar adónde hay que ir (tecla Tab): sirve al retomar una partida.
func recordar() -> void:
	if terminado or ocupado:
		return
	if final_elegido != "":
		_avisar(str(datos.get("finales", {}).get(final_elegido, {}).get("aviso", "")))
		return
	_avisar(_aviso_del_momento())


## El cartel de adónde ir: el primer caso de avisos.segun que se cumpla o, si ninguno, el del momento.
func _aviso_del_momento() -> String:
	var avisos: Dictionary = datos.get("avisos", {})
	for caso in avisos.get("segun", []):
		if cumple(caso.get("si", {})):
			return str(caso.get("texto", ""))
	return str(avisos.get("momento_%d" % momento, ""))


func _avisar(linea: String) -> void:
	_ultimo_aviso = linea
	if linea != "" and _jugador != null and is_instance_valid(_jugador) and _jugador.has_method("mostrar_aviso"):
		_jugador.mostrar_aviso(_texto(linea))


# ------------------------------------------------------------------ finales

func _empezar_final() -> void:
	var final: Dictionary = datos.get("finales", {}).get(final_elegido, {})
	var preparar := func() -> void:
		flags["_final_listo"] = true
		_mover_gente_del_final()
		if final.has("tp") and _jugador != null:
			var tp: Array = final["tp"]
			_jugador.global_position = Vector3(tp[0], altura_suelo(tp[0], tp[1]) + 1.2, tp[1])
			_jugador.set("velocity", Vector3.ZERO)
		var ciclo := _ciclo()
		if ciclo != null and final.has("hora"):
			ciclo.establecer_hora(float(final["hora"]))
		guardar()
	var cartel: Array = final.get("cartel", [])
	if cartel.is_empty() or _cuadro == null:
		preparar.call()
		_avisar(str(final.get("aviso", "")))
		return
	ocupado = true
	var al_terminar := func() -> void:
		ocupado = false
		_avisar(str(final.get("aviso", "")))
	_cuadro.fundido(cartel, al_terminar, preparar)


## En algunos finales la gente espera a Zenón en otro lugar (nadie camina todavía).
func _mover_gente_del_final() -> void:
	if _mundo == null or not is_instance_valid(_mundo):
		return
	for mov in datos.get("finales", {}).get(final_elegido, {}).get("mover", []):
		var nodo := _mundo.get_node_or_null(str(mov.get("nodo", ""))) as Node3D
		if nodo == null:
			continue
		var a: Array = mov.get("a", [0, 0])
		nodo.global_position = Vector3(a[0], altura_suelo(a[0], a[1]), a[1])
		if mov.has("mira"):
			var m: Array = mov["mira"]
			nodo.look_at(Vector3(m[0], nodo.global_position.y, m[1]), Vector3.UP, true)


func _process(delta: float) -> void:
	if final_elegido == "" or terminado or ocupado or _jugador == null or not is_instance_valid(_jugador):
		return
	_llegada_revisar -= delta
	if _llegada_revisar > 0.0:
		return
	_llegada_revisar = 0.25
	var final: Dictionary = datos.get("finales", {}).get(final_elegido, {})
	var llegada: Array = final.get("llegada", [])
	if llegada.size() != 2:
		return
	var plano := Vector2(_jugador.global_position.x - float(llegada[0]), _jugador.global_position.z - float(llegada[1]))
	if plano.length() <= float(final.get("radio", 8.0)):
		terminar()


## Cierra la historia con el final elegido y muestra el epílogo.
func terminar() -> void:
	if final_elegido == "" or terminado:
		return
	terminado = true
	guardar()
	_mostrar_epilogo()


func _mostrar_epilogo() -> void:
	var final: Dictionary = datos.get("finales", {}).get(final_elegido, {})
	if _cuadro == null:
		return
	ocupado = true
	var paginas: Array = []
	for pagina in final.get("epilogo", []):
		paginas.append(_texto(str(pagina)))
	var al_menu := func() -> void:
		ocupado = false
		_jugador = null
		_mundo = null
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	_cuadro.epilogo(str(final.get("titulo", "")), paginas, Color(str(final.get("color", "#0b0907"))), al_menu)


## Altura del piso en un punto del mapa (para acomodar gente en los finales).
func altura_suelo(x: float, z: float) -> float:
	if _mundo == null or not is_instance_valid(_mundo):
		return 0.0
	var terreno := _mundo.get_node_or_null("HTerrain")
	if terreno == null or not terreno.has_method("world_to_map"):
		return 0.0
	var datos_terreno = terreno.get_data()
	if datos_terreno == null:
		return 0.0
	var mapa: Vector3 = terreno.world_to_map(Vector3(x, 0.0, z))
	var h: float = datos_terreno.get_interpolated_height_at(Vector3(mapa.x, 0.0, mapa.z))
	return (terreno.get_internal_transform() * Vector3(mapa.x, h, mapa.z)).y


# ------------------------------------------------------------------ guardado

func hay_partida() -> bool:
	return FileAccess.file_exists(RUTA_PARTIDA)


## ¿La partida guardada ya llegó a un final? (El menú no ofrece "Continuar".)
func partida_terminada() -> bool:
	var json = JSON.parse_string(FileAccess.get_file_as_string(RUTA_PARTIDA))
	return json is Dictionary and bool(json.get("terminado", false))


func estado() -> Dictionary:
	return {"version": 1, "momento": momento, "vars": vars, "flags": flags.keys(), "confianza": confianza,
		"deuda": deuda, "notas": notas, "final": final_elegido, "terminado": terminado}


func poner_estado(e: Dictionary) -> void:
	nueva()
	momento = int(e.get("momento", 1))
	for nombre in e.get("vars", {}):
		vars[nombre] = int(e["vars"][nombre])
	for bandera in e.get("flags", []):
		flags[bandera] = true
	for bando in e.get("confianza", {}):
		confianza[bando] = int(e["confianza"][bando])
	deuda = int(e.get("deuda", deuda))
	notas = e.get("notas", [])
	final_elegido = str(e.get("final", ""))
	terminado = bool(e.get("terminado", false))


func guardar() -> void:
	_sucio = false
	var e := estado()
	if _jugador != null and is_instance_valid(_jugador):
		var p := _jugador.global_position
		e["pos"] = [p.x, p.y, p.z]
		e["yaw"] = _jugador.get("yaw")
		var ciclo := _ciclo()
		if ciclo != null:
			e["hora"] = ciclo.get("hora_del_dia")
	else:
		return  # Sin mundo (pruebas) no se escribe nada en el disco.
	var archivo := FileAccess.open(RUTA_PARTIDA, FileAccess.WRITE)
	if archivo == null:
		push_warning("No se pudo guardar la partida en %s" % RUTA_PARTIDA)
		return
	archivo.store_string(JSON.stringify(e, "\t"))


func cargar() -> bool:
	var json = JSON.parse_string(FileAccess.get_file_as_string(RUTA_PARTIDA))
	if not (json is Dictionary):
		return false
	poner_estado(json)
	_partida = json
	return true


func borrar_partida() -> void:
	if FileAccess.file_exists(RUTA_PARTIDA):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_PARTIDA))
	nueva()

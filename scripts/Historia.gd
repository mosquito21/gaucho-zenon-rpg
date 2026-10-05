extends Node

## El estado de la historia de Zenón: en qué momento va la trama, qué pasó, la confianza
## oculta con cada bando y la cuenta de la pulpería. También abre los diálogos, el fogón
## y los finales, y guarda la partida.
##
## Todos los textos y los números están en datos/historia.json: acá no hay ningún diálogo.
## La lógica no necesita el mundo: tools/pruebas/probar_historia.gd la recorre sin abrirlo.

const RUTA_DATOS := "res://datos/historia.json"
## Los rebaños que Zenón arrea: la sección de datos/historia.json (su variable se llama igual) y la
## clave con que la partida guarda dónde quedó cada animal. "vacas" es la de la tanda 6 y no cambia,
## para que las partidas viejas carguen.
const REBANOS := {"arreo": "vacas", "caballada": "caballos"}
## Dónde se guarda la partida. Las pruebas que corren el juego solas lo arrancan con
## "-- --partida-de-prueba" y guardan en otros archivos (ver _ruta), para no pisar los de quien juega.
var ruta_partida := "user://partida.json"
var _sufijo := ""
## Las pruebas sin mundo pueden decir qué contesta la condición "cerca" (null: no dicen nada).
var cerca_forzada = null

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
var _terreno: Node3D
var _saliendo := {}
var _fila: Array[Node3D] = []
var _fila_esperando := false
## Los rebaños que hay en el mundo: sección de datos → nodo (scripts/arreo.gd).
var _rebanos := {}
## La jornada de trabajo que empieza al cerrar el diálogo (efecto "jornada").
var _jornada: Dictionary = {}
## Cómo estaba en la escena cada cosa que "mundo" prende, apaga o mueve, para dejarla igual después.
var _de_escena := {}


func _init() -> void:
	if OS.get_cmdline_user_args().has("--partida-de-prueba"):
		_sufijo = "_prueba"
	ruta_partida = _ruta("partida")
	_cargar_datos()
	nueva()


## El archivo de ese nombre en la carpeta de partidas: "partida", "abril" (la copia al llegar la
## línea) o "partida_terminada" (la que se aparta al empezar de nuevo).
func _ruta(nombre: String) -> String:
	return "user://%s%s.json" % [nombre, _sufijo]


## Al cerrar la ventana se guarda dónde quedó todo (antes solo se guardaba al cerrar un diálogo).
## Con un diálogo abierto no: lo que ese diálogo ya cambió todavía no terminó de aplicarse (el cierre
## es el que amanece, pasa de capítulo y guarda la copia de abril), así que se vuelve al último guardado.
## Con un final elegido tampoco: la gente que sigue a Zenón no se guarda, y al volver quedaría atrás.
func _notification(que: int) -> void:
	if que == NOTIFICATION_WM_CLOSE_REQUEST and not terminado and final_elegido == "" and _nodo.is_empty():
		guardar()


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
	_jornada = {}


func v(nombre: String) -> int:
	return int(vars.get(nombre, 0))


func poner(nombre: String, valor: int) -> void:
	if v(nombre) == valor:
		return
	vars[nombre] = valor
	_sucio = true
	# Lo que pone el mundo (el recado, el mojón, un rebaño encerrado) deja su nota para el fogón desde acá.
	var nota: String = str(datos.get("notas_de_trabajos", {}).get("%s=%d" % [nombre, valor], ""))
	if nota != "":
		notas.append(nota)
	# Fuera de un diálogo (el recado, el mojón, un rebaño) no hay un cierre que acomode el mundo y
	# guarde: se hace al terminar el cuadro. Adentro de un diálogo, de eso se ocupa _cerrar().
	if _nodo.is_empty() and not ocupado and _jugador != null:
		_asentar.call_deferred()


## Acomoda el mundo a lo que cambió y lo deja escrito, sin tocar lo que _cerrar() tiene pendiente.
func _asentar() -> void:
	_acomodar_mundo()
	_escribir(ruta_partida)


## ¿Se cumple la condición? Es un diccionario; tienen que cumplirse todas sus claves.
## momento: 2 o [2, 3] · var: {"sena": 2} o {"sena": [2, 3]} · si / no: ["bandera"]
## min: {"ejercito": 3} (contra los mínimos de config si el valor es "minimo") · o: [cond, cond]
## menos: {"ejercito": "minimo"} (la confianza NO llega a ese valor) · final: "chile" (el final elegido)
## deuda_hasta: 40 (la cuenta es de 40 o menos) · cerca: "ceniza" (la tiene a mano; ver config.cerca)
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
			"deuda_hasta":
				if deuda > int(valor):
					return false
			"cerca":
				if not _cerca(str(valor)):
					return false
			"periodo":
				# "Noche" o ["Crepúsculo", "Noche"]: los períodos de scripts/CicloDiaNoche.gd. Sin mundo es de día.
				var ciclo := _ciclo()
				var ahora := str(ciclo.call("obtener_periodo_dia")) if ciclo != null else "Día"
				if not (valor if valor is Array else [valor]).has(ahora):
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


## ¿Zenón tiene eso a mano? En datos/historia.json, config.cerca dice qué nodo es y a cuántos metros
## ("ceniza": montado está encima, así que también vale). Sin mundo (las pruebas) cuenta como cerca.
func _cerca(de_que: String) -> bool:
	if cerca_forzada != null:
		return bool(cerca_forzada)
	if _jugador == null or not is_instance_valid(_jugador) or _mundo == null or not is_instance_valid(_mundo):
		return true
	var c: Dictionary = datos.get("config", {}).get("cerca", {}).get(de_que, {})
	var nodo := _mundo.get_node_or_null(str(c.get("nodo", ""))) as Node3D
	if nodo == null:
		return true
	var lejos := Vector2(nodo.global_position.x - _jugador.global_position.x, nodo.global_position.z - _jugador.global_position.z).length()
	return lejos <= float(c.get("metros", 12.0))


## Aplica lo que cambia una opción o un nodo.
## var: {"sena": 1} · flag: ["x"] · confianza: {"ejercito": 1} · deuda: -20 · nota: "..."
## momento: 3 · final: "sargento" · jornada: {"horas": 4, "texto": ["..."]} (ver _hacer_jornada)
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
			"jornada":
				_jornada = valor
			_:
				push_warning("historia.json: efecto desconocido '%s'" % clave)


func _texto(crudo: String) -> String:
	return crudo.replace("{deuda}", str(deuda))


# ------------------------------------------------------------------ diálogos

## La ficha de una persona ("personajes") o de un lugar de trabajo ("changas").
func _ficha(id: String) -> Dictionary:
	return datos.get("personajes", {}).get(id, datos.get("changas", {}).get(id, {}))


## El cartel de "Presioná E" que la historia le pone a una persona o a un lugar de trabajo, si le
## pone uno ("mira": {"si": {...}, "texto": "..."} o una lista de esos); si no, "".
func mira_de(id: String) -> String:
	var mira = _ficha(id).get("mira", [])
	for caso in (mira if mira is Array else [mira]):
		if cumple(caso.get("si", {})):
			return str(caso.get("texto", ""))
	return ""


## Abre la charla de un personaje o de un lugar de trabajo. Devuelve falso si no tiene nada que decir.
func hablar(id: String) -> bool:
	var persona := _ficha(id)
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
		_acomodar_mundo()
		guardar()
	_hacer_jornada()


## Una jornada de trabajo (efecto "jornada"): la pantalla se oscurece, se lee lo que hizo Zenón y el
## reloj avanza esas horas, sin pasar de la oración (config.jornada_hasta). De noche el reloj no se mueve.
func _hacer_jornada() -> void:
	if _jornada.is_empty():
		return
	var j := _jornada
	_jornada = {}
	var pasar := func() -> void:
		var ciclo := _ciclo()
		if ciclo != null:
			var hora := float(ciclo.get("hora_del_dia"))
			var tope := float(datos.get("config", {}).get("jornada_hasta", 21.0))
			if hora < tope:
				ciclo.establecer_hora(minf(hora + float(j.get("horas", 1.0)), tope))
		guardar()
	var texto = j.get("texto", [])
	if _cuadro == null or ocupado:
		pasar.call()
		return
	ocupado = true
	var al_terminar := func() -> void:
		ocupado = false
		_avisar(_aviso_del_momento())
	_cuadro.fundido(texto if texto is Array else [texto], al_terminar, pasar)


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
	# Al otro día el capataz vuelve a tener una punta que traer.
	if v("arreo") == 2:
		poner("arreo", 0)
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
	_de_escena = {}
	_rebanos = {}
	if _partida.is_empty() and momento == 1 and flags.is_empty() and FileAccess.file_exists(ruta_partida):
		# World.tscn se abrió sin pasar por el menú: sigue la partida que haya.
		# Si esa partida ya llegó a un final, la aparta (no la borra) y empieza una nueva.
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
	# Los lugares de trabajo de los conchabos (el jarillal): se usan como se le habla a una persona.
	for id in datos.get("changas", {}):
		var changa: Dictionary = datos["changas"][id]
		var lugar := _mundo.get_node_or_null(str(changa.get("nodo", "")))
		if lugar == null:
			push_warning("historia.json: el lugar de trabajo '%s' no encuentra su nodo '%s'" % [id, changa.get("nodo", "")])
			continue
		_personas.append(_sumar_interactuable(lugar, Interactable.Rol.CHANGA, id, str(changa.get("nombre", "")), float(changa.get("alcance", 6.0))))
	var fogon := _mundo.get_node_or_null(str(datos.get("fogon", {}).get("nodo", "")))
	if fogon != null:
		_personas.append(_sumar_interactuable(fogon, Interactable.Rol.FOGON, "", "", 3.0))
	# Ceniza se monta arrimándose a ella (el resto lo hace player.gd).
	var caballo := _mundo.get_node_or_null("Ceniza")
	if caballo != null:
		_personas.append(_sumar_interactuable(caballo, Interactable.Rol.CABALLO, "", "Ceniza", 2.8))
	_acomodar_mundo()
	if not _partida.is_empty():
		var pos: Array = _partida.get("pos", [])
		if pos.size() == 3:
			jugador.global_position = Vector3(pos[0], pos[1], pos[2])
		jugador.set("yaw", float(_partida.get("yaw", 0.0)))
		if jugador.has_method("poner_caballo"):
			jugador.call("poner_caballo", _partida)
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
	if momento == 1 and not flags.has("_arranque"):
		# Partida nueva: el cartel de dónde y cuándo, con las teclas (avisos.cartel_momento_1).
		flags["_arranque"] = true
		_al_cambiar_de_momento()
		return
	if _partida.has("hora"):
		# La hora guardada se pone recién a los 0,2 s (arriba): el recordatorio espera a eso, para
		# que la línea del sol salga con la hora de la partida y no con la del arranque.
		get_tree().create_timer(0.3).timeout.connect(recordar)
		return
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
	# "Adelante" es hacia donde mira la cámara. A pie el cuerpo la sigue; montado no (el caballo va
	# por su rumbo), y alcanza con arrimarse y mirar a la persona.
	var giro: float = jugador.rotation.y if jugador.get("yaw") == null else float(jugador.get("yaw"))
	var frente := Vector3(-sin(giro), 0.0, -cos(giro))
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
	_acomodar_segun_la_historia()
	_acomodar_rebanos()
	# El sol anda más al norte (más bajo al mediodía) a medida que avanza el año: config.sol_al_norte
	# trae los grados para cada momento.
	var norte: Array = datos.get("config", {}).get("sol_al_norte", [])
	var ciclo := _ciclo()
	if ciclo != null and not norte.is_empty():
		ciclo.set("sol_al_norte", float(norte[clampi(momento, 1, norte.size()) - 1]))


## La sección "mundo" de datos/historia.json: una lista de {"si", "mostrar", "ocultar", "mover"}.
## Mientras se cumple su "si", cada entrada prende sus "mostrar", apaga sus "ocultar" y lleva a otro
## lugar a los de "mover" ({"nodo", "a": [x, z], "mira": [x, z], "clips": [...]}); cuando deja de
## cumplirse, todo vuelve a estar como en la escena. Así se ven la carga en Ceniza, el rastro de la
## caballada o la yerra.
func _acomodar_segun_la_historia() -> void:
	var visto := {}
	var movido := {}
	var rutas := {}
	for entrada: Dictionary in datos.get("mundo", []):
		var vale := cumple(entrada.get("si", {}))
		for ruta: String in entrada.get("mostrar", []):
			rutas[ruta] = true
			if vale:
				visto[ruta] = true
		for ruta: String in entrada.get("ocultar", []):
			rutas[ruta] = true
			if vale:
				visto[ruta] = false
		for mov: Dictionary in entrada.get("mover", []):
			rutas[str(mov.get("nodo", ""))] = true
			if vale:
				movido[str(mov.get("nodo", ""))] = mov
	for ruta: String in rutas:
		var nodo := _mundo.get_node_or_null(ruta) as Node3D
		if nodo == null:
			continue
		if not _de_escena.has(ruta):
			_de_escena[ruta] = {"visible": nodo.visible, "modo": nodo.process_mode, "lugar": nodo.global_transform,
				"clips": nodo.get("clips"), "movido": false}
		var antes: Dictionary = _de_escena[ruta]
		var ver: bool = visto.get(ruta, antes.visible)
		nodo.visible = ver
		# Apagado, deja de procesar y sus cuerpos de choque salen de la física (visible no alcanza).
		nodo.process_mode = antes.modo if ver else Node.PROCESS_MODE_DISABLED
		if movido.has(ruta) != antes.movido:
			antes.movido = movido.has(ruta)
			var ronda = nodo.get("ronda")
			if antes.movido:
				_llevar(nodo, movido[ruta])
			elif ronda is PackedVector2Array and not ronda.is_empty() and nodo.has_method("quedarse"):
				# El que tenía una ronda la retoma desde donde está: vuelve caminando.
				nodo.call("quedarse")
			else:
				nodo.global_transform = antes.lugar
				if antes.clips != null and nodo.has_method("poner_clips"):
					nodo.call("poner_clips", antes.clips)


## Lleva un nodo a otro punto del mapa, apoyado en el suelo, mirando hacia donde se le diga.
## Con "andando": true, si es alguien que camina y Zenón lo tiene a la vista (a menos de 60 m), va
## caminando en vez de aparecer ahí. El que hacía una ronda la deja y se queda en ese punto.
func _llevar(nodo: Node3D, mov: Dictionary) -> void:
	var a: Array = mov.get("a", [0, 0])
	var meta := Vector3(a[0], altura_suelo(a[0], a[1]), a[1])
	var camina := nodo.has_method("andar_por")
	var a_la_vista := _jugador != null and is_instance_valid(_jugador) and _jugador.global_position.distance_to(nodo.global_position) < 60.0
	if camina and a_la_vista and mov.get("andando", false):
		nodo.call("andar_por", PackedVector3Array([meta]), float(mov.get("velocidad", 1.2)))
		return
	nodo.global_position = meta
	if mov.has("mira"):
		var m: Array = mov["mira"]
		nodo.look_at(Vector3(m[0], nodo.global_position.y, m[1]), Vector3.UP, true)
	if mov.has("clips") and nodo.has_method("poner_clips"):
		nodo.call("poner_clips", mov["clips"])
	if camina:
		nodo.call("andar_por", PackedVector3Array([meta]))


## Los rebaños (la punta de vacas del capataz, la caballada del fortín): cada sección de datos trae
## "suelta" (la condición con la que anda por el campo y hay que arrearla) y "encerrada" (con la que
## se la ve ya en su corral). Los números están en datos/historia.json y los animales los mueve
## scripts/arreo.gd.
func _acomodar_rebanos() -> void:
	if _mundo == null or not is_instance_valid(_mundo) or _jugador == null:
		return
	for seccion: String in REBANOS:
		var d: Dictionary = datos.get(seccion, {})
		if d.is_empty():
			continue
		var suelta: bool = d.has("suelta") and cumple(d["suelta"])
		var nodo: Node = _rebanos.get(seccion)
		var hay := nodo != null and is_instance_valid(nodo)
		if not suelta and not (d.has("encerrada") and cumple(d["encerrada"])):
			if hay:
				nodo.queue_free()
			_rebanos.erase(seccion)
			continue
		if not hay:
			nodo = (load("res://scripts/arreo.gd") as GDScript).new()
			# "Arreo" o "Caballada": por ese nombre lo busca la prueba (tools/pruebas/recorrida.gd).
			nodo.name = seccion.capitalize()
			nodo.set("datos", d)
			nodo.set("jinete", _jugador)
			nodo.connect("cumplido", _rebano_cumplido.bind(seccion))
			nodo.connect("quedo_atras", func() -> void: _avisar(str(d.get("aviso_rezagada", ""))))
			_mundo.add_child(nodo)
			_rebanos[seccion] = nodo
			# Si la partida se guardó a medio arreo, cada animal vuelve adonde había quedado.
			nodo.call("poner", suelta, _partida.get(REBANOS[seccion], []) if suelta else [])
			_partida.erase(REBANOS[seccion])
		elif nodo.get("suelta") != suelta and (suelta or nodo.get("_pagado") != true):
			nodo.call("poner", suelta)


## El último animal pasó la tranquera. Ningún rebaño mueve la confianza de nadie ni toca los finales.
func _rebano_cumplido(seccion: String) -> void:
	var d: Dictionary = datos.get(seccion, {})
	if d.has("al_cumplir"):
		# La caballada: queda hecha y se cobra después, en lo de Ceferino.
		aplicar(d["al_cumplir"])
	else:
		# El arreo del capataz se cobra solo. Hasta el otro día no hay otra punta (2); después de
		# tantas veces, ninguna más (3).
		var hechos := v("arreos") + 1
		aplicar({"deuda": -int(d.get("paga", 0)), "nota": str(d.get("nota", "")),
			"var": {"arreos": hechos, "arreo": 3 if hechos >= int(d.get("veces", 1)) else 2}})
	_avisar(str(d.get("aviso_hecho", "")))
	_acomodar_mundo()
	guardar()


func _al_cambiar_de_momento() -> void:
	_acomodar_mundo()
	if final_elegido != "":
		_empezar_final()
		return
	if momento == 3:
		# Una copia de cómo llegó Zenón a abril, para volver a elegir sin rejugar ("Volver a abril de
		# 1881" en el menú). No toca la partida en curso.
		_escribir(_ruta("abril"))
	var paso: Dictionary = datos.get("avisos", {})
	var cartel: Array = paso.get("cartel_momento_%d" % momento, [])
	if not cartel.is_empty() and _cuadro != null:
		ocupado = true
		var al_terminar := func() -> void:
			ocupado = false
			_avisar(_aviso_del_momento())
		# El cartel del arranque sale con la pantalla ya tapada; los demás la van oscureciendo.
		_cuadro.fundido(cartel, al_terminar, Callable(), momento == 1)
	else:
		_avisar(_aviso_del_momento())


## Vuelve a mostrar adónde hay que ir (tecla Tab): sirve al retomar una partida. Debajo dice por
## dónde anda el sol a esta hora (avisos.sol), que es la brújula de Zenón.
func recordar() -> void:
	if terminado or ocupado:
		return
	var linea := _aviso_del_momento()
	if final_elegido != "":
		linea = str(datos.get("finales", {}).get(final_elegido, {}).get("aviso", ""))
	var ciclo := _ciclo()
	if ciclo != null:
		var hora := float(ciclo.get("hora_del_dia"))
		for caso: Dictionary in datos.get("avisos", {}).get("sol", []):
			if hora >= float(caso.get("desde", 0.0)) and hora < float(caso.get("hasta", 24.0)):
				linea += "\n" + str(caso.get("texto", ""))
				break
	_avisar(linea)
	# El aviso de Tab con el sol no es "el aviso del momento": que al cerrar un diálogo vuelva a compararse bien.
	_ultimo_aviso = _aviso_del_momento()


## El cartel de adónde ir: el primer caso de avisos.segun que se cumpla o, si ninguno, el del momento.
## Debajo, una línea por cada conchabo a medias (avisos.conchabos).
func _aviso_del_momento() -> String:
	var avisos: Dictionary = datos.get("avisos", {})
	var linea := str(avisos.get("momento_%d" % momento, ""))
	for caso in avisos.get("segun", []):
		if cumple(caso.get("si", {})):
			linea = str(caso.get("texto", ""))
			break
	for caso in avisos.get("conchabos", []):
		if cumple(caso.get("si", {})):
			linea += "\n" + str(caso.get("texto", ""))
	return linea


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


## Acomoda a la gente del final elegido. En datos/historia.json, cada final puede traer:
##   "mover": a quién se lleva a otro lugar y hacia dónde mira;
##   "mostrar": qué aparece recién ahora (la carga de un caballo);
##   "fila": quiénes siguen a Zenón, uno detrás de otro, y a quién lleva montado cada caballo;
##   "camina": quién va por su cuenta por unos puntos (el sargento, adelante). Con un solo punto,
##     el suyo, deja la ronda y se queda ahí (el soldado de la carga, para no cruzarse con el sargento).
func _mover_gente_del_final() -> void:
	if _mundo == null or not is_instance_valid(_mundo):
		return
	var final: Dictionary = datos.get("finales", {}).get(final_elegido, {})
	for mov in final.get("mover", []):
		var nodo := _mundo.get_node_or_null(str(mov.get("nodo", ""))) as Node3D
		if nodo != null:
			_llevar(nodo, mov)
	for ruta in final.get("mostrar", []):
		var cosa := _mundo.get_node_or_null(str(ruta)) as Node3D
		if cosa != null:
			cosa.visible = true
	_fila = []
	var fila: Dictionary = final.get("fila", {})
	var guia: Node3D = _jugador
	for puesto: Dictionary in fila.get("orden", []):
		var nodo := _mundo.get_node_or_null(str(puesto.get("nodo", ""))) as Node3D
		if nodo == null or not nodo.has_method("seguir") or guia == null:
			continue
		nodo.call("seguir", guia, float(puesto.get("detras", 2.5)), float(fila.get("espera_desde", 40.0)), float(fila.get("paso", 0.0)))
		if puesto.has("lleva"):
			var jinete := _mundo.get_node_or_null(str(puesto["lleva"]))
			if jinete != null and jinete.has_method("sentarse_en"):
				jinete.call("sentarse_en", nodo)
		_fila.append(nodo)
		guia = nodo
	for andar: Dictionary in final.get("camina", []):
		var nodo := _mundo.get_node_or_null(str(andar.get("nodo", ""))) as Node3D
		if nodo == null or not nodo.has_method("andar_por"):
			continue
		var puntos := PackedVector3Array()
		for p: Array in andar.get("por", []):
			puntos.append(Vector3(p[0], altura_suelo(p[0], p[1]), p[1]))
		nodo.call("andar_por", puntos, float(andar.get("velocidad", 1.3)))


func _process(delta: float) -> void:
	if terminado or ocupado or _jugador == null or not is_instance_valid(_jugador):
		return
	_llegada_revisar -= delta
	if _llegada_revisar > 0.0:
		return
	_llegada_revisar = 0.25
	_salir_al_encuentro()
	_pensar_al_pasar()
	if final_elegido == "":
		return
	var final: Dictionary = datos.get("finales", {}).get(final_elegido, {})
	var aqui := Vector2(_jugador.global_position.x, _jugador.global_position.z)
	# Un final puede terminar al alejarse (montado, hacia un rumbo) en vez de al llegar a un lugar.
	var alejarse: Dictionary = final.get("alejarse", {})
	if not alejarse.is_empty():
		var de: Array = alejarse.get("de", [0, 0])
		var hacia: Array = alejarse.get("hacia", [0, 1])
		var andado := (aqui - Vector2(de[0], de[1])).dot(Vector2(hacia[0], hacia[1]).normalized())
		if andado >= float(alejarse.get("metros", 300.0)) and (not alejarse.get("montado", false) or _jugador.get("montado") == true):
			terminar()
		return
	var llegada: Array = final.get("llegada", [])
	if llegada.size() != 2:
		return
	var meta := Vector2(llegada[0], llegada[1])
	# Si la fila quedó esperando porque Zenón se adelantó, se lo dice (una vez por espera).
	var fila: Dictionary = final.get("fila", {})
	if not _fila.is_empty() and is_instance_valid(_fila[0]):
		var lejos: float = aqui.distance_to(Vector2(_fila[0].global_position.x, _fila[0].global_position.z))
		var esperando := lejos > float(fila.get("espera_desde", 40.0))
		if esperando and not _fila_esperando and fila.has("aviso_espera"):
			_avisar(str(fila["aviso_espera"]))
		_fila_esperando = esperando
	if aqui.distance_to(meta) > float(final.get("radio", 8.0)):
		return
	# Con gente detrás, el final llega cuando llega la gente, no solo Zenón.
	for nodo: Node3D in _fila:
		if is_instance_valid(nodo) and Vector2(nodo.global_position.x, nodo.global_position.z).distance_to(meta) > float(final.get("radio", 8.0)) + float(fila.get("holgura", 16.0)):
			return
	terminar()


## Hay gente que, cuando la trama lo pide, no espera a Zenón parada: le sale al cruce (Nicasio en
## la huella). En datos/historia.json: "encuentro": {"si": {condición}, "desde": metros}.
func _salir_al_encuentro() -> void:
	if _mundo == null or not is_instance_valid(_mundo):
		return
	for id: String in datos.get("personajes", {}):
		var cruce: Dictionary = datos["personajes"][id].get("encuentro", {})
		if cruce.is_empty():
			continue
		var nodo := _mundo.get_node_or_null(str(datos["personajes"][id].get("nodo", ""))) as Node3D
		if nodo == null or not nodo.has_method("venir"):
			continue
		var lejos := Vector2(nodo.global_position.x - _jugador.global_position.x, nodo.global_position.z - _jugador.global_position.z).length()
		if lejos < float(cruce.get("desde", 30.0)) and cumple(cruce.get("si", {})):
			if not _saliendo.has(id):
				_saliendo[id] = true
				nodo.call("venir", _jugador, 3.0)
		elif _saliendo.has(id):
			_saliendo.erase(id)
			nodo.call("quedarse")


## Lo que se le hace notar a Zenón al pasar por un lugar (avisos.al_pasar en datos/historia.json):
## {"si": {...}, "en": [x, z] o "rebano": "caballada" (el animal suelto más cercano), "radio": metros,
## "texto": "...", "una_vez": "bandera"}. Sale como un aviso común, una sola vez.
func _pensar_al_pasar() -> void:
	if not _jugador.has_method("mostrar_aviso"):
		return
	var aqui := Vector2(_jugador.global_position.x, _jugador.global_position.z)
	for caso: Dictionary in datos.get("avisos", {}).get("al_pasar", []):
		var bandera := str(caso.get("una_vez", ""))
		if flags.has(bandera) or not cumple(caso.get("si", {})):
			continue
		var lugares := PackedVector2Array()
		if caso.has("en"):
			lugares.append(Vector2(caso["en"][0], caso["en"][1]))
		var rebano: Node = _rebanos.get(str(caso.get("rebano", "")))
		if rebano != null and is_instance_valid(rebano) and rebano.get("suelta") == true:
			lugares.append_array(rebano.call("faltan"))
		for lugar in lugares:
			if aqui.distance_to(lugar) <= float(caso.get("radio", 20.0)):
				flags[bandera] = true
				_jugador.call("mostrar_aviso", _texto(str(caso.get("texto", ""))))
				return


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


## Altura del piso en un punto del mapa, la misma que se ve y se pisa: cada cuadrado del terreno son
## dos triángulos partidos por la diagonal 10-01 (promediar las cuatro esquinas se equivoca hasta
## 13 cm en las laderas). La usan los finales, la gente que camina y Ceniza.
func altura_suelo(x: float, z: float) -> float:
	if _terreno == null or not is_instance_valid(_terreno):
		if not is_inside_tree() or get_tree().current_scene == null:
			return 0.0
		_terreno = get_tree().current_scene.get_node_or_null("HTerrain") as Node3D
		if _terreno == null or not _terreno.has_method("world_to_map"):
			_terreno = null
			return 0.0
	var datos_terreno = _terreno.get_data()
	if datos_terreno == null:
		return 0.0
	var mapa: Vector3 = _terreno.world_to_map(Vector3(x, 0.0, z))
	var tope: int = datos_terreno.get_resolution() - 2
	var cx := clampi(floori(mapa.x), 0, tope)
	var cz := clampi(floori(mapa.z), 0, tope)
	var fx := clampf(mapa.x - cx, 0.0, 1.0)
	var fz := clampf(mapa.z - cz, 0.0, 1.0)
	var h00: float = datos_terreno.get_height_at(cx, cz)
	var h10: float = datos_terreno.get_height_at(cx + 1, cz)
	var h01: float = datos_terreno.get_height_at(cx, cz + 1)
	var h: float
	if fx + fz <= 1.0:
		h = h00 + (h10 - h00) * fx + (h01 - h00) * fz
	else:
		var h11: float = datos_terreno.get_height_at(cx + 1, cz + 1)
		h = h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)
	return (_terreno.get_internal_transform() * Vector3(mapa.x, h, mapa.z)).y


# ------------------------------------------------------------------ guardado

func hay_partida() -> bool:
	return FileAccess.file_exists(ruta_partida)


## ¿La partida guardada ya llegó a un final? (El menú no ofrece "Continuar".)
func partida_terminada() -> bool:
	var json = JSON.parse_string(FileAccess.get_file_as_string(ruta_partida))
	return json is Dictionary and bool(json.get("terminado", false))


## En qué época quedó la partida guardada ("abril de 1881"), para el botón "Continuar" del menú.
## Los nombres, uno por momento, están en config.epocas.
func epoca_guardada() -> String:
	var json = JSON.parse_string(FileAccess.get_file_as_string(ruta_partida))
	var epocas: Array = datos.get("config", {}).get("epocas", [])
	if not (json is Dictionary) or epocas.is_empty():
		return ""
	return str(epocas[clampi(int(json.get("momento", 1)), 1, epocas.size()) - 1])


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
	_escribir(ruta_partida)


## Escribe en ese archivo la historia y dónde está cada cosa del mundo.
func _escribir(ruta: String) -> void:
	if _jugador == null or not is_instance_valid(_jugador):
		return  # Sin mundo (pruebas) no se escribe nada en el disco.
	if datos.is_empty():
		return  # Con datos/historia.json mal escrito no hay historia que guardar (la cuenta saldría en 0).
	var e := estado()
	var p := _jugador.global_position
	e["pos"] = [p.x, p.y, p.z]
	e["yaw"] = _jugador.get("yaw")
	var ciclo := _ciclo()
	if ciclo != null:
		e["hora"] = ciclo.get("hora_del_dia")
	# Dónde quedó Ceniza y si Zenón va montado.
	if _jugador.has_method("estado_del_caballo"):
		e.merge(_jugador.call("estado_del_caballo"))
	# Un rebaño a medio arrear: dónde quedó cada animal.
	for seccion: String in _rebanos:
		var d: Dictionary = datos.get(seccion, {})
		if is_instance_valid(_rebanos[seccion]) and d.has("suelta") and cumple(d["suelta"]):
			e[REBANOS[seccion]] = _rebanos[seccion].call("guardar")
	var archivo := FileAccess.open(ruta, FileAccess.WRITE)
	if archivo == null:
		push_warning("No se pudo guardar la partida en %s" % ruta)
		return
	archivo.store_string(JSON.stringify(e, "\t"))


func cargar() -> bool:
	var json = JSON.parse_string(FileAccess.get_file_as_string(ruta_partida))
	if not (json is Dictionary):
		return false
	poner_estado(json)
	_partida = json
	return true


## Empieza de cero. La partida que había no se pierde: queda apartada en "partida_terminada" (una
## sola, la última), en la misma carpeta. Devuelve falso si había una partida y no se pudo apartar
## (por ejemplo, porque otro programa tiene abierto el archivo apartado de antes).
func borrar_partida() -> bool:
	var apartada := true
	if FileAccess.file_exists(ruta_partida):
		var carpeta := DirAccess.open("user://")
		apartada = carpeta != null and carpeta.rename(ruta_partida, _ruta("partida_terminada")) == OK
	nueva()
	return apartada


## ¿Hay una copia de cómo llegó Zenón a abril de 1881? (La escribe _al_cambiar_de_momento.)
func hay_abril() -> bool:
	return FileAccess.file_exists(_ruta("abril"))


## Vuelve a esa copia: la partida que había queda apartada, como al empezar de nuevo.
func volver_a_abril() -> bool:
	var carpeta := DirAccess.open("user://")
	if carpeta == null or not hay_abril():
		return false
	if not borrar_partida():
		return false  # No se pudo apartar la partida en curso: no se la pisa.
	carpeta.copy(_ruta("abril"), ruta_partida)
	return cargar()

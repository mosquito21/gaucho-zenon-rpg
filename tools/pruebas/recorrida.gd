extends Node

## Prueba que juega sola dentro del mundo, con las teclas de siempre, como un jugador: lleva a Zenón
## de un punto a otro (a pie o montado), habla con la gente con la E, usa los lugares y el fogón,
## y anota cuánto tarda cada tramo, cuántos metros anduvo, si se trabó, si atravesó el piso y el
## peor cuadro. No es parte del juego: se carga a mano con el juego andando (ver ESTADO.md,
## "Para Willy", Tanda 6).
##
## Pasos del plan (una lista de listas):
##   ["ir", "nombre", x, z, radio]            va hasta ese punto del mapa
##   ["acercar", "ruta del nodo", metros]     va hacia ese nodo (aunque se mueva) hasta quedar a esa distancia
##   ["hablar", "id", ["trozo de opción"]]    se acerca a esa persona (o a ese lugar de trabajo, como
##                                            "jarillal"), aprieta E y elige en orden
##   ["usar", "Lugares/PostaDelCoiron"]       se acerca a un lugar, lo mira y aprieta E
##   ["fogon", ["trozo de opción"]]           se sienta al fogón, pasa las páginas y elige si pregunta
##   ["montar"] / ["desmontar"] / ["silbar"]  las teclas del caballo
##   ["marcha", 3]                            montado: 1 paso, 2 trote, 3 galope
##   ["arrear"] o ["arrear", "caballada"]     montado y con el trabajo tomado: lleva el rebaño de esa
##                                            sección de datos (sin nada, el arreo) hasta su corral
##   ["poner", x, z]                          aparece en ese punto del mapa (montado, con Ceniza y todo)
##   ["empujar", x, z, segundos]              va derecho hacia ese punto ese tiempo, sin rodear nada: para
##                                            comprobar que una pared, un cerco o el agua honda lo frenan
##   ["esperar", segundos]
##   ["correr", false]                        a pie: de ahí en más camina (o vuelve a correr con true)
##   ["espero", "expresión", "qué se esperaba"]   una condición sobre Historia (H), el jugador (P) y el mundo (M)
##   ["hasta", "expresión", segundos, "qué se esperaba"]   espera a que se cumpla, como mucho esos segundos
##   ["estado", {...}]                        pone la historia en un estado (Historia.poner_estado)

## Cuántas veces más rápido corre el juego durante la prueba (los tiempos que anota son de juego).
var velocidad := 4.0
var plan: Array = []
var correr := true

var tramos: Array = []
var fallas: Array = []
var listo := false
var peor_cuadro_ms := 0.0
var total_s := 0.0
var total_m := 0.0

var _i := -1
var _paso: Array = []
var _fase := 0
var _t := 0.0
var _espera := 0.0
var _p: CharacterBody3D
var _mundo: Node
var _ant := Vector3.ZERO
var _metros := 0.0
var _quieto := 0.0
var _esquive := 0.0
var _lado := 1.0
var _seguidas := 0
var _libre := 0.0
var _trabadas := 0
var _soltar_salto := false
var _pend: Array = []
var _usec := 0
var _cuadros_asentar := 0
var _ventana_t := 0.0
var _ventana := Vector3.ZERO


func _ready() -> void:
	process_physics_priority = -10
	Engine.time_scale = velocidad
	Engine.physics_ticks_per_second = int(60.0 * velocidad)
	Engine.max_physics_steps_per_frame = 32


func _exit_tree() -> void:
	_soltar()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8


func _process(_delta: float) -> void:
	# El peor cuadro, en tiempo real. Los primeros cuadros de cada paso no cuentan (carga de lo nuevo).
	var ahora := Time.get_ticks_usec()
	if _usec > 0 and _cuadros_asentar <= 0 and not listo:
		peor_cuadro_ms = maxf(peor_cuadro_ms, float(ahora - _usec) / 1000.0)
	_cuadros_asentar -= 1
	_usec = ahora


func _physics_process(delta: float) -> void:
	if listo:
		return
	_mundo = get_tree().current_scene
	if _mundo == null or _mundo.get_node_or_null("Player") == null:
		return
	_p = _mundo.get_node("Player")
	if _i < 0:
		_revisar_rutas()
	if _soltar_salto:
		Input.action_release("jump")
		_soltar_salto = false
	if Historia.terminado:
		# Llegó a un final: el epílogo queda en pantalla y la prueba termina acá.
		_cerrar_paso()
		_terminar()
		return
	if _i < 0 or _hacer(delta):
		_cerrar_paso()
		_i += 1
		if _i >= plan.size() or Historia.terminado:
			_terminar()
			return
		_paso = plan[_i]
		_fase = 0
		_t = 0.0
		_espera = 0.0
		_metros = 0.0
		_trabadas = 0
		_quieto = 0.0
		_esquive = 0.0
		_seguidas = 0
		_ant = _p.global_position
		_pend = []
	_t += delta
	total_s += delta
	# Nunca tendría que caer por debajo del piso.
	if _p.global_position.y < Historia.altura_suelo(_p.global_position.x, _p.global_position.z) - 3.0:
		_falla("atravesó el piso en %s (paso %d)" % [_p.global_position, _i])
		_terminar()


## Todo nodo que datos/historia.json nombra en "mundo" y en "changas" tiene que estar en la escena:
## si se renombra o se borra, la historia lo saltea sin avisar.
func _revisar_rutas() -> void:
	var rutas: Array = []
	for entrada: Dictionary in Historia.datos.get("mundo", []):
		rutas.append_array(entrada.get("mostrar", []))
		rutas.append_array(entrada.get("ocultar", []))
		for mov: Dictionary in entrada.get("mover", []):
			rutas.append(mov.get("nodo", ""))
	for id: String in Historia.datos.get("changas", {}):
		rutas.append(Historia.datos["changas"][id].get("nodo", ""))
	for ruta: String in rutas:
		if _mundo.get_node_or_null(ruta) == null:
			_falla("datos/historia.json nombra '%s' y no está en la escena" % ruta)
	# Lo que Ceniza lleva en el anca no puede traer cuerpos de choque: montado, este mismo cuerpo
	# chocaría contra su carga y el caballo no avanzaría (le pasó al tercio de yerba en la tanda 7).
	var carga := _mundo.get_node_or_null("Ceniza/Carga")
	if carga != null:
		for cuerpo in carga.find_children("*", "CollisionObject3D", true, false):
			_falla("la carga de Ceniza trae un cuerpo de choque: %s" % carga.get_path_to(cuerpo))


func _terminar() -> void:
	_soltar()
	listo = true
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8


func _cerrar_paso() -> void:
	if _i < 0 or _i >= plan.size():
		return
	_soltar()
	total_m += _metros
	tramos.append({"paso": str(_paso[0]) + " " + str(_paso[1] if _paso.size() > 1 else ""), "s": snappedf(_t, 0.1),
		"m": snappedf(_metros, 1.0), "trabadas": _trabadas,
		"en": [snappedf(_p.global_position.x, 0.1), snappedf(_p.global_position.z, 0.1)] if _p != null else []})


func _falla(texto: String) -> void:
	fallas.append(texto)
	push_warning("recorrida: " + texto)


func _soltar() -> void:
	for accion in ["move_forward", "move_backward", "move_left", "move_right", "run", "jump"]:
		Input.action_release(accion)


## Devuelve verdadero cuando el paso terminó.
func _hacer(delta: float) -> bool:
	match str(_paso[0]):
		"ir":
			if _andar(delta, Vector3(float(_paso[2]), 0.0, float(_paso[3])), float(_paso[4])):
				return true
			return _vencido()
		"hablar":
			return _hablar(delta)
		"usar":
			return _usar(delta)
		"fogon":
			return _fogon(delta)
		"esperar":
			return _t >= float(_paso[1])
		"montar", "desmontar", "silbar":
			return _caballo(delta)
		"acercar":
			var quien := _mundo.get_node_or_null(str(_paso[1])) as Node3D
			if quien == null:
				_falla("no existe %s" % str(_paso[1]))
				return true
			if _andar(delta, quien.global_position, float(_paso[2])):
				return true
			return _vencido()
		"marcha":
			if _p.has_method("poner_marcha"):
				_p.poner_marcha(int(_paso[1]))
			return true
		"arrear":
			return _arrear(delta)
		"poner":
			_p.global_position = Vector3(float(_paso[1]), Historia.altura_suelo(float(_paso[1]), float(_paso[2])) + 1.2, float(_paso[2]))
			_p.velocity = Vector3.ZERO
			_ant = _p.global_position
			return true
		"empujar":
			_metros += Vector2(_p.global_position.x - _ant.x, _p.global_position.z - _ant.z).length()
			_ant = _p.global_position
			if _t >= float(_paso[3]):
				_soltar()
				return true
			_p.yaw = atan2(-(float(_paso[1]) - _p.global_position.x), -(float(_paso[2]) - _p.global_position.z))
			Input.action_press("move_forward")
			return false
		"espero":
			if not _vale(str(_paso[1])):
				_falla("se esperaba que " + str(_paso[2]))
			return true
		"hasta":
			if _vale(str(_paso[1])):
				return true
			if _t > float(_paso[2]):
				_falla("pasaron %s s y no se cumplió: %s" % [str(_paso[2]), str(_paso[3])])
				return true
			return false
		"correr":
			correr = _paso[1] == true
			return true
		"estado":
			Historia.poner_estado(_paso[1])
			Historia._acomodar_mundo()
			return true
	_falla("paso desconocido: %s" % str(_paso))
	return true


## Lleva la punta del arreo al corral, montado y al trote, como lo haría un jinete: si está
## desparramada va a buscar a la vaca que quedó más lejos del resto; si va junta, se le pone
## detrás y la empuja hacia la entrada. Falla si en quince minutos de juego no entró.
## Con ["arrear", "caballada"] hace lo mismo con el rebaño de esa sección de datos.
func _arrear(delta: float) -> bool:
	var seccion := str(_paso[1]) if _paso.size() > 1 else "arreo"
	var arreo := _mundo.get_node_or_null(seccion.capitalize())
	if _fase == 0:
		if arreo == null or Historia.v(seccion) != 1:
			_falla("no hay %s en marcha" % seccion)
			return true
		_fase = 1
	if Historia.v(seccion) != 1:
		return true
	var vacas: PackedVector2Array = arreo.faltan()
	if _t > 900.0:
		_falla("la punta no entró al corral en quince minutos (faltan %d vacas)" % vacas.size())
		return true
	if vacas.is_empty():
		_soltar()  # las últimas ya van entrando solas
		return false
	var centro := Vector2.ZERO
	for vaca in vacas:
		centro += vaca
	centro /= vacas.size()
	var lejana := vacas[0]
	for vaca in vacas:
		if vaca.distance_to(centro) > lejana.distance_to(centro):
			lejana = vaca
	var destino: Vector2
	if lejana.distance_to(centro) > 3.5 * sqrt(float(vacas.size())) + 4.0:
		destino = lejana + (lejana - centro).normalized() * 5.0
	else:
		# Detrás de la última vaca, del lado contrario a la entrada.
		var atras: Vector2 = (centro - arreo.entrada()).normalized()
		var fondo := 0.0
		for vaca in vacas:
			fondo = maxf(fondo, (vaca - centro).dot(atras))
		destino = centro + atras * (fondo + 5.0)
	# Al trote para ponerse en su lugar; ya detrás de la punta, al paso.
	_p.poner_marcha(2 if _distancia(Vector3(destino.x, 0.0, destino.y)) > 2.5 else 1)
	_andar(delta, Vector3(destino.x, 0.0, destino.y), 0.5)
	return false


## Una condición escrita como texto, sobre la historia (H), el jugador (P) y el mundo (M).
func _vale(expresion: String) -> bool:
	var e := Expression.new()
	return e.parse(expresion, ["H", "P", "M"]) == OK and e.execute([Historia, _p, _mundo]) == true


## Un tramo que no llega nunca es una falla, no una prueba colgada.
func _vencido() -> bool:
	if _t > 600.0:
		_falla("no llegó: %s (quedó en %s)" % [str(_paso), _p.global_position])
		return true
	return false


func _distancia(destino: Vector3) -> float:
	return Vector2(destino.x - _p.global_position.x, destino.z - _p.global_position.z).length()


## Camina (o va montado) hacia un punto. Si se traba, prueba rodear por un lado y por el otro.
func _andar(delta: float, destino: Vector3, radio: float) -> bool:
	var paso := Vector2(_p.global_position.x - _ant.x, _p.global_position.z - _ant.z).length()
	_metros += paso
	_ant = _p.global_position
	if _distancia(destino) <= radio:
		_soltar()
		return true
	if Historia.ocupado:
		_soltar()
		return false
	var rumbo := atan2(-(destino.x - _p.global_position.x), -(destino.z - _p.global_position.z))
	if _esquive > 0.0:
		_esquive -= delta
		rumbo += _lado * 1.25
	else:
		if paso < 0.5 * delta:
			_quieto += delta
			_libre = 0.0
		else:
			_quieto = 0.0
			_libre += delta
			if _libre > 4.0:
				_seguidas = 0
		# Empujando contra una pared el cuerpo tiembla y no parece quieto: además se mira cuánto
		# avanzó de verdad en casi un segundo.
		_ventana_t += delta
		if _ventana_t >= 0.9:
			if Vector2(_p.global_position.x - _ventana.x, _p.global_position.z - _ventana.z).length() < 0.4:
				_quieto = 1.0
			_ventana_t = 0.0
			_ventana = _p.global_position
		if _quieto > 0.9:
			_quieto = 0.0
			_trabadas += 1
			_seguidas += 1
			_lado = -_lado
			# Cada intento rodea un poco más lejos, y a pie además salta.
			_esquive = 1.0 + 0.7 * float(_seguidas)
			if not _p.get("montado") == true:
				Input.action_press("jump")
				_soltar_salto = true
	_p.yaw = rumbo
	Input.action_press("move_forward")
	if correr and not _p.get("montado") == true:
		Input.action_press("run")
	return false


func _tecla_e() -> void:
	var e := InputEventAction.new()
	e.action = "interact"
	e.pressed = true
	Input.parse_input_event(e)


func _tecla(codigo: int) -> void:
	for apretada: bool in [true, false]:
		var k := InputEventKey.new()
		k.keycode = codigo as Key
		k.physical_keycode = codigo as Key
		k.pressed = apretada
		Input.parse_input_event(k)


## Pasa las páginas con E y elige las opciones (por un trozo de su texto) con los números.
## Devuelve verdadero cuando ya no hay nada en pantalla.
func _charla(delta: float) -> bool:
	_espera -= delta
	if _espera > 0.0:
		return false
	_espera = 0.35
	if not Historia.ocupado:
		if not _pend.is_empty():
			_falla("%s cerró la charla antes de '%s'" % [str(_paso), _pend[0]])
		return true
	var cuadro = Historia._cuadro
	var eligiendo: bool = cuadro != null and cuadro._modo == "dialogo" and cuadro._opciones.get_child_count() > 0
	if not eligiendo:
		_tecla_e()
		return false
	var opciones: Array = Historia.vista().get("opciones", [])
	if _pend.is_empty():
		_falla("%s ofrece opciones y el plan no eligió: %s" % [str(_paso), opciones])
		Historia._cerrar()
		return true
	var trozo: String = _pend.pop_front()
	for n in opciones.size():
		if str(opciones[n]).contains(trozo):
			_tecla(KEY_1 + n)
			return false
	_falla("%s no ofrece '%s' (ofrece %s)" % [str(_paso), trozo, opciones])
	Historia._cerrar()
	return true


func _hablar(delta: float) -> bool:
	var id := str(_paso[1])
	# Una persona ("personajes") o un lugar de trabajo ("changas"): se usan igual.
	var persona: Dictionary = Historia._ficha(id)
	var nodo := _mundo.get_node_or_null(str(persona.get("nodo", ""))) as Node3D
	if nodo == null:
		_falla("no está en el mundo: " + id)
		return true
	match _fase:
		0:
			var cerca := Historia.persona_cerca(_p)
			# Medio paso más adentro del alcance (o hasta donde deje la pared): justo en el borde, el
			# cartel de la E aparece y desaparece.
			if cerca != null and cerca.personaje == id and (_distancia(cerca.global_position) <= cerca.alcance - 0.4 or _quieto > 0.3):
				_soltar()
				_fase = 1
				_espera = 0.2
				return false
			if _andar(delta, nodo.global_position, 0.9):
				# Llegó encima y la E no lo ofrece: se anota y se sigue por la puerta de atrás.
				_falla("pegado a %s y no aparece 'Presioná E para hablar'" % id)
				Historia.hablar(id)
				_pend = (_paso[2] as Array).duplicate() if _paso.size() > 2 else []
				_fase = 2
			return _vencido()
		1:
			_espera -= delta
			if _espera > 0.0:
				return false
			var mira = _p.get("current_interactable")
			if mira == null or mira.get("personaje") != id:
				_falla("la E no apunta a %s (apunta a %s)" % [id, str(mira)])
				Historia.hablar(id)
			else:
				_tecla_e()
			_pend = (_paso[2] as Array).duplicate() if _paso.size() > 2 else []
			_fase = 2
			_espera = 0.3
			return false
		_:
			return _charla(delta)


## Un lugar que se usa mirándolo (posta, hito, mojón): se acerca, lo mira y aprieta E.
func _usar(delta: float) -> bool:
	var nodo := _mundo.get_node_or_null(str(_paso[1])) as Node3D
	if nodo == null:
		_falla("no está en el mundo: " + str(_paso[1]))
		return true
	match _fase:
		0:
			if _andar(delta, nodo.global_position, 6.0):
				_fase = 1
				_espera = 0.3
				_p.yaw = atan2(-(nodo.global_position.x - _p.global_position.x), -(nodo.global_position.z - _p.global_position.z))
				_p.pitch = deg_to_rad(-12.0)
			return _vencido()
		1:
			_espera -= delta
			if _espera > 0.0:
				return false
			var mira = _p.get("current_interactable")
			if mira != null and mira.get_parent() != null and nodo.is_ancestor_of(mira):
				_tecla_e()
				_fase = 2
				_espera = 0.4
				return false
			# Barre la mirada de arriba abajo hasta encontrarlo.
			_p.pitch -= deg_to_rad(3.0)
			_espera = 0.12
			if _p.pitch < deg_to_rad(-45.0):
				_falla("mirando %s no aparece 'Presioná E'" % str(_paso[1]))
				return true
			return false
		_:
			_espera -= delta
			_p.pitch = deg_to_rad(-12.0)
			return _espera <= 0.0


func _fogon(delta: float) -> bool:
	var nodo := _mundo.get_node_or_null(str(Historia.datos.get("fogon", {}).get("nodo", ""))) as Node3D
	if nodo == null:
		_falla("no hay fogón")
		return true
	match _fase:
		0:
			var cerca := Historia.persona_cerca(_p)
			if cerca != null and cerca.rol == Interactable.Rol.FOGON:
				_soltar()
				_fase = 1
				_espera = 0.2
				return false
			if _andar(delta, nodo.global_position, 0.8):
				_falla("pegado al fogón y no aparece 'Presioná E para sentarte'")
				return true
			return _vencido()
		1:
			_espera -= delta
			if _espera > 0.0:
				return false
			_tecla_e()
			_pend = (_paso[1] as Array).duplicate() if _paso.size() > 1 else []
			_fase = 2
			_espera = 0.4
			return false
		_:
			return _charla(delta)


func _caballo(delta: float) -> bool:
	match _fase:
		0:
			if str(_paso[0]) == "montar":
				var ceniza := _mundo.get_node_or_null("Ceniza") as Node3D
				var cerca := Historia.persona_cerca(_p)
				if cerca != null and ceniza != null and ceniza.is_ancestor_of(cerca):
					_soltar()
					_tecla_e()
					_fase = 1
					_espera = 2.0
					return false
				if ceniza == null or _andar(delta, ceniza.global_position, 0.9):
					_falla("pegado a Ceniza y no aparece 'Presioná E para montar'")
					return true
				return _vencido()
			_tecla(KEY_Q)
			_fase = 1
			_espera = 2.0 if str(_paso[0]) == "desmontar" else 0.2
			return false
		_:
			_espera -= delta
			return _espera <= 0.0

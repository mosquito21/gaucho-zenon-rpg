extends Node3D

## El arreo: la punta de vacas de Don Rufino que Zenón trae, montado, hasta el corral grande.
## Las vacas se apartan del jinete, tienden a quedarse juntas y, si una queda muy atrás, se para
## a pastar hasta que la vayan a buscar. Cerca de la tranquera entran solas, en fila.
## No hay navegación: es campo abierto, y lo que hay que esquivar (la posta, la casa, el corral
## por fuera) son círculos. Lo crea scripts/Historia.gd cuando Zenón toma el trabajo del capataz.
## Los números y los lugares están en datos/historia.json ("arreo") y se explican en
## docs/agente/ESTADO.md, "Para Willy", Tanda 6.
##
## Desde la tanda 7 sirve para cualquier rebaño: la caballada del fortín es otra sección de datos
## ("caballada") con sus "modelos", "marchas", "clips" y "nombre". Lo que no trae la sección sale de
## la vaca, así que el arreo quedó igual.

## La última vaca pasó la tranquera.
signal cumplido
## Una vaca quedó lejos del resto y se puso a pastar.
signal quedo_atras

const VACA_GLB := "res://assets/animales/vaca_animado.glb"
const NPC := preload("res://scripts/npc_animado.gd")
## A qué velocidad pisa cada clip de la vaca sin patinar (salen de tools/animales/recetas.py).
const MARCHAS := {"walk": 0.63, "trot": 2.38}
## El genio de cada vaca: desde cuánto más lejos (o más cerca) que las otras se aparta del jinete.
## Con todas iguales, la punta marcha en una fila pareja, como tropa de línea; así va en montón.
const GENIOS := [1.0, 0.78, 1.22, 0.9, 1.14, 0.72, 1.06]

## Qué está haciendo cada vaca. De ENTRA en adelante ya no hay que arrearla.
enum { PASTA, ANDA, REZAGADA, ENTRA, CORRAL }

## La sección "arreo" de datos/historia.json.
var datos: Dictionary = {}
## Quién arrea: Zenón. (En la prueba puede ser cualquier nodo que se mueva.)
var jinete: Node3D
## La punta está en el campo (verdadero) o ya encerrada (falso).
var suelta := false

var _vacas: Array[Dictionary] = []
var _afuera: Array = []
var _adentro: Array = []
var _camino: Array[Vector2] = []
var _pagado := false
var _aviso_en := 0.0
var _jinete_antes := Vector2.ZERO


## Arma la punta: suelta en el campo (o donde había quedado cada vaca, si se retoma una partida)
## o ya encerrada en el corral.
func poner(en_el_campo: bool, guardadas: Array = []) -> void:
	suelta = en_el_campo
	_pagado = not en_el_campo
	_adentro = datos.get("obstaculos", [])
	_afuera = _adentro + ([datos["corral"]] if datos.has("corral") else [])
	_camino = []
	for punto: Array in datos.get("entrada", {}).get("camino", []):
		_camino.append(_v2(punto))
	while _vacas.size() < int(datos.get("animales", datos.get("vacas", 7))):
		_vacas.append(_nueva_vaca(_vacas.size()))
	var centro := _v2(datos.get("donde", [0, 0]))
	for i in _vacas.size():
		var vaca := _vacas[i]
		var guardada: Array = guardadas[i] if i < guardadas.size() else []
		vaca.vel = 0.0
		vaca.tramo = 0
		vaca.rumbo = i * 1.7
		if not en_el_campo or (guardada.size() == 3 and int(guardada[2]) >= ENTRA):
			vaca.estado = CORRAL
			vaca.pos = vaca.lugar
		elif guardada.size() == 3:
			vaca.estado = int(guardada[2])
			vaca.pos = Vector2(guardada[0], guardada[1])
		else:
			# Desparramadas alrededor del lugar, sin encimarse.
			vaca.estado = PASTA
			vaca.pos = centro + Vector2.from_angle(i * 2.4) * (3.0 + 1.8 * i)
		(vaca.nodo as Node3D).call("pisar", 0.0)
		_ubicar(vaca)
	if jinete != null and is_instance_valid(jinete):
		_jinete_antes = Vector2(jinete.global_position.x, jinete.global_position.z)


## Dónde quedó cada vaca y qué hacía, para guardarlo con la partida: [x, z, estado].
func guardar() -> Array:
	var lista: Array = []
	for vaca in _vacas:
		lista.append([snappedf(vaca.pos.x, 0.1), snappedf(vaca.pos.y, 0.1), int(vaca.estado)])
	return lista


## Las vacas que todavía hay que arrear (dónde está cada una) y adónde hay que llevarlas.
## Lo usa la prueba (tools/pruebas/recorrida.gd).
func faltan() -> PackedVector2Array:
	var lista := PackedVector2Array()
	for vaca in _vacas:
		if int(vaca.estado) < ENTRA:
			lista.append(vaca.pos)
	return lista


func entrada() -> Vector2:
	return _camino[0] if not _camino.is_empty() else Vector2.ZERO


func _nueva_vaca(i: int) -> Dictionary:
	var nodo := Node3D.new()
	nodo.set_script(NPC)
	nodo.name = "%s%d" % [str(datos.get("nombre", "VacaDelArreo")), i + 1]
	# "talla": [la del más chico, cuánto más grande cada uno de los tres que siguen].
	var tallas: Array = datos.get("talla", [0.9, 0.05])
	var talla := float(tallas[0]) + float(tallas[1]) * (i % 4)
	var lista: Array[String] = []
	lista.assign(datos.get("clips", ["graze", "graze", "idle"]))
	nodo.set("clips", lista)
	var marchas := {}
	var de_datos: Dictionary = datos.get("marchas", MARCHAS)
	for clip: String in de_datos:
		marchas[clip] = float(de_datos[clip]) * talla
	nodo.set("marchas", marchas)
	var modelos: Array = datos.get("modelos", [VACA_GLB])
	var modelo := (load(str(modelos[i % modelos.size()])) as PackedScene).instantiate() as Node3D
	modelo.scale = Vector3.ONE * talla
	nodo.add_child(modelo)
	add_child(nodo)
	nodo.call("llevar", true)
	var lugares: Array = datos.get("lugares_en_el_corral", [])
	var lugar: Vector2 = _v2(lugares[i % lugares.size()]) if not lugares.is_empty() else _v2(datos.get("corral", [0, 0]))
	return {"nodo": nodo, "pos": Vector2.ZERO, "rumbo": 0.0, "vel": 0.0, "estado": PASTA, "tramo": 0, "lugar": lugar,
		"genio": GENIOS[i % GENIOS.size()]}


func _process(delta: float) -> void:
	if not suelta or jinete == null or not is_instance_valid(jinete) or Historia.ocupado:
		return
	delta = minf(delta, 0.1)
	var j := Vector2(jinete.global_position.x, jinete.global_position.z)
	var vel_jinete := (j - _jinete_antes) / maxf(delta, 0.001)
	_jinete_antes = j
	var a_caballo: bool = jinete.get("montado") != false
	var alcance := float(datos.get("alcance_montado", 16.0)) if a_caballo else float(datos.get("alcance_a_pie", 5.0))
	# El centro de la punta: las que van juntas (ni las rezagadas ni las que ya entran).
	var centro := Vector2.ZERO
	var juntas := 0
	for vaca in _vacas:
		if int(vaca.estado) <= ANDA:
			centro += vaca.pos
			juntas += 1
	if juntas > 0:
		centro /= juntas
	_aviso_en -= delta
	var sin_entrar := 0
	var andando := 0
	for vaca in _vacas:
		match int(vaca.estado):
			CORRAL:
				continue
			ENTRA:
				_entrar(vaca, delta)
			_:
				_arrear(vaca, j, vel_jinete, alcance, a_caballo, centro, juntas, delta)
		andando += 1
		# La tranquera es el segundo punto del camino de entrada: de ahí para adentro, ya entró.
		if int(vaca.estado) < ENTRA or (int(vaca.estado) == ENTRA and int(vaca.tramo) < 2):
			sin_entrar += 1
	if sin_entrar == 0 and not _pagado:
		_pagado = true
		cumplido.emit()
	if andando == 0:
		suelta = false


## Una vaca en el campo: se aparta del jinete, busca a las otras y no se les encima.
func _arrear(vaca: Dictionary, j: Vector2, vel_jinete: Vector2, alcance: float, a_caballo: bool, centro: Vector2, juntas: int, delta: float) -> void:
	var pos: Vector2 = vaca.pos
	if not _camino.is_empty() and pos.distance_to(_camino[0]) < float(datos.get("entrada", {}).get("cerca", 14.0)):
		vaca.estado = ENTRA
		vaca.tramo = 0
		return
	var paso := float(datos.get("paso", 0.9))
	alcance *= float(vaca.genio)
	var del_jinete := pos - j
	var lejos := del_jinete.length()
	var al_centro := centro - pos
	var quiere := Vector2.ZERO
	var velocidad := 0.0
	if lejos < alcance:
		# Cuanto más cerca el jinete, más ligero: del paso al trote.
		var apuro := clampf((1.0 - lejos / alcance) * 1.8, 0.0, 1.0)
		quiere = del_jinete / maxf(lejos, 0.01)
		# La punta se mueve como una sola cosa: además de apartarse del jinete, cada vaca va hacia
		# donde va el resto (del jinete al centro de la punta). Sin esto, empujadas desde atrás se
		# abren en abanico.
		var del_jinete_al_centro := centro - j
		if juntas > 1 and del_jinete_al_centro.length() > 3.0:
			quiere = (quiere + del_jinete_al_centro.normalized()).normalized()
		# Si el caballo se le viene encima, se abre hacia el costado en vez de correr adelante.
		if vel_jinete.length() > 3.0 and lejos < 9.0:
			var rumbo_jinete := vel_jinete.normalized()
			if rumbo_jinete.dot(quiere) > 0.6:
				var costado := rumbo_jinete.orthogonal()
				quiere += costado * (0.9 if costado.dot(del_jinete) >= 0.0 else -0.9)
		# Y cuanto más lejos del resto, más tira a juntarse.
		if juntas > 1 and al_centro.length() > 3.0:
			quiere += al_centro.normalized() * clampf((al_centro.length() - 3.0) / 8.0, 0.0, 1.0) * 0.9
		velocidad = lerpf(paso, float(datos.get("trote", 3.0)) if a_caballo else paso * 1.3, apuro)
		vaca.estado = ANDA
	elif int(vaca.estado) != REZAGADA and juntas > 1:
		if al_centro.length() > float(datos.get("rezago", 30.0)):
			# Quedó muy atrás: se pone a pastar hasta que la vayan a buscar.
			vaca.estado = REZAGADA
			if _aviso_en <= 0.0:
				_aviso_en = 20.0
				quedo_atras.emit()
		elif al_centro.length() > float(datos.get("junta", 7.0)):
			quiere = al_centro.normalized()
			velocidad = paso
			vaca.estado = ANDA
		else:
			vaca.estado = PASTA
	quiere += _apartarse(vaca, false)
	if velocidad == 0.0 and quiere.length() > 0.3:
		velocidad = paso * 0.6
	_mover(vaca, quiere, velocidad, delta, _afuera)


## Cerca de la tranquera ya no hace falta el jinete: va al paso por el camino de entrada y se
## queda en su lugar del corral.
func _entrar(vaca: Dictionary, delta: float) -> void:
	var tramo := int(vaca.tramo)
	var meta: Vector2 = _camino[tramo] if tramo < _camino.size() else vaca.lugar
	var falta: Vector2 = meta - vaca.pos
	# Por los puntos del camino pasa de largo a metro y medio; a su lugar se arrima lo que diga
	# "llegar" (en un corral chico, como el del fortín, tiene que quedar bien adentro).
	if falta.length() < (1.5 if tramo < _camino.size() else float(datos.get("entrada", {}).get("llegar", 1.5))):
		vaca.tramo = tramo + 1
		if tramo >= _camino.size():
			vaca.estado = CORRAL
			vaca.vel = 0.0
			(vaca.nodo as Node3D).call("pisar", 0.0)
		return
	_mover(vaca, falta.normalized() + _apartarse(vaca, true) * 0.5, float(datos.get("paso", 0.9)) * 1.2, delta, _adentro)


## Hacia dónde correrse para no encimarse con las otras (las del campo entre sí, las que entran entre sí).
func _apartarse(vaca: Dictionary, entrando: bool) -> Vector2:
	var suma := Vector2.ZERO
	for otra in _vacas:
		if is_same(otra, vaca) or (int(otra.estado) == ENTRA) != entrando or int(otra.estado) == CORRAL:
			continue
		var entre: Vector2 = vaca.pos - otra.pos
		var d := entre.length()
		if d < 2.6 and d > 0.01:
			suma += entre / d * (1.0 - d / 2.6) * 1.2
	return suma


func _mover(vaca: Dictionary, quiere: Vector2, velocidad: float, delta: float, obstaculos: Array) -> void:
	var nodo := vaca.nodo as Node3D
	var rumbo: float = vaca.rumbo
	if quiere.length() < 0.01:
		velocidad = 0.0
	var vel := move_toward(float(vaca.vel), velocidad, 2.5 * delta)
	vaca.vel = vel
	if vel < 0.05:
		nodo.call("pisar", 0.0)
		return
	var de_frente := 1.0
	if quiere.length() >= 0.01:
		var hacia := atan2(quiere.x, quiere.y)
		rumbo = rotate_toward(rumbo, hacia, 2.4 * delta)
		# Avanza hacia donde mira: mientras se da vuelta casi no avanza, y no camina de costado.
		de_frente = maxf(cos(angle_difference(rumbo, hacia)), 0.15)
	var pos: Vector2 = vaca.pos + Vector2(sin(rumbo), cos(rumbo)) * vel * de_frente * delta
	for o: Array in obstaculos:
		var desde := pos - Vector2(o[0], o[1])
		var radio := float(o[2]) + 0.8
		if desde.length() < radio and desde.length() > 0.001:
			pos = Vector2(o[0], o[1]) + desde.normalized() * radio
	vaca.pos = pos
	vaca.rumbo = rumbo
	nodo.call("pisar", vel * de_frente)
	_ubicar(vaca)


func _ubicar(vaca: Dictionary) -> void:
	var nodo := vaca.nodo as Node3D
	var pos: Vector2 = vaca.pos
	nodo.global_position = Vector3(pos.x, Historia.altura_suelo(pos.x, pos.y), pos.y)
	nodo.rotation.y = vaca.rumbo


func _v2(par: Array) -> Vector2:
	return Vector2(float(par[0]), float(par[1]))

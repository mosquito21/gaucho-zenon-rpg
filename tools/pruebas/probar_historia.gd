extends SceneTree

## Prueba de la historia sin abrir el mundo. Recorre datos/historia.json por los cuatro finales,
## revisa que ningún diálogo quede sin salida, que no haya claves mal escritas ni banderas que
## nadie pone, que cada oferta aparezca justo con su mínimo de confianza y que la partida
## vuelva igual después de guardarla. Si algo falla, termina con error y dice qué.
##   godot --headless --path <carpeta del proyecto> --script res://tools/pruebas/probar_historia.gd
## Tiene que terminar en "FALLAS: 0".

const CONDICIONES := ["momento", "var", "si", "no", "min", "menos", "final", "o"]
const EFECTOS := ["var", "flag", "confianza", "deuda", "saldar", "nota", "momento", "final"]

var H: Node
var fallas := 0
# Qué valores se ponen (y quién), cuáles se miran, y lo mismo con las banderas.
# El recado y el mojón los pone el mundo (player.gd), sin pasar por un diálogo.
var _puesto := {"recado=1": "el mundo", "recado=2": "el mundo", "sena=2": "el mundo"}
var _leido := {}
var _banderas_puestas := {}
var _banderas_leidas := {}


# En _initialize y no en _init: recién acá el proyecto ya registró sus autoloads.
func _initialize() -> void:
	var guion := load("res://scripts/Historia.gd") as GDScript
	if guion == null or not guion.can_instantiate():
		printerr("FALLA: scripts/Historia.gd no compila")
		quit(1)
		return
	H = guion.new()
	_revisar_datos()
	_final_sargento()
	_final_encargado()
	_final_chile()
	_final_solitario_sin_hacer_nada()
	_borde_del_minimo()
	_arreo()
	_guardado()
	print("FALLAS: %d" % fallas)
	H.free()
	quit(1 if fallas > 0 else 0)


func _mal(mensaje: String) -> void:
	fallas += 1
	printerr("FALLA: " + mensaje)


## Todo "ir" apunta a un nodo que existe, y todo nodo con opciones tiene una que siempre está.
func _revisar_datos() -> void:
	var nodos: Dictionary = H.datos.get("nodos", {})
	if nodos.is_empty():
		_mal("no hay nodos: ¿se leyó datos/historia.json?")
	for id in nodos:
		var nodo: Dictionary = nodos[id]
		var destinos: Array = [nodo.get("ir")]
		for rama in nodo.get("segun", []):
			destinos.append(rama.get("ir"))
		var siempre := false
		for opcion in nodo.get("opciones", []):
			destinos.append(opcion.get("ir"))
			if not opcion.has("si"):
				siempre = true
		if nodo.has("opciones") and not siempre:
			_mal("el nodo '%s' puede quedar sin ninguna opción" % id)
		if nodo.has("segun") and nodo["segun"][-1].has("si"):
			_mal("el nodo '%s' (segun) no tiene una rama final sin condición" % id)
		if not nodo.has("segun") and str(nodo.get("texto", "")) == "":
			_mal("el nodo '%s' no tiene texto" % id)
		for destino in destinos:
			if destino != null and not nodos.has(str(destino)):
				_mal("el nodo '%s' manda a '%s', que no existe" % [id, destino])
		_efecto(nodo.get("hace", {}), id)
		for rama in nodo.get("segun", []):
			_condicion(rama.get("si", {}), id)
		for opcion in nodo.get("opciones", []):
			_condicion(opcion.get("si", {}), id)
			_efecto(opcion.get("hace", {}), id)
	var fogon: Dictionary = H.datos.get("fogon", {})
	for caso in H.datos.get("avisos", {}).get("segun", []):
		_condicion(caso.get("si", {}), "un aviso")
		if str(caso.get("texto", "")) == "":
			_mal("hay un aviso sin texto")
	_condicion(fogon.get("cierre", {}).get("si", {}), "el cierre del fogón")
	for extra in fogon.get("pensamientos", []):
		_condicion(extra.get("si", {}), "un pensamiento del fogón")
		if extra.has("una_vez"):
			_banderas_puestas[extra["una_vez"]] = true
	for par in _puesto:
		if not _leido.has(par):
			_mal("%s pone %s y ninguna condición mira ese valor" % [_puesto[par], par])
	for bandera in _banderas_leidas:
		if not _banderas_puestas.has(bandera):
			_mal("%s mira la bandera '%s', que nada pone" % [_banderas_leidas[bandera], bandera])
	for id in H.datos.get("personajes", {}):
		if not nodos.has(str(H.datos["personajes"][id].get("charla", ""))):
			_mal("el personaje '%s' no tiene charla" % id)
		_condicion(H.datos["personajes"][id].get("encuentro", {}).get("si", {}), "el encuentro de '%s'" % id)
	for id in H.datos.get("finales", {}):
		var final: Dictionary = H.datos["finales"][id]
		if final.get("epilogo", []).is_empty() or (final.get("llegada", []).size() != 2 and final.get("alejarse", {}).is_empty()):
			_mal("al final '%s' le falta el epílogo o cómo se llega (llegada o alejarse)" % id)


## Una clave mal escrita en "si" o en "hace" solo da un aviso en la consola: acá es una falla.
## De paso anota qué valores y banderas se ponen y cuáles se miran.
func _condicion(cond: Dictionary, donde: String) -> void:
	for clave in cond:
		if not CONDICIONES.has(clave):
			_mal("%s: condición desconocida '%s'" % [donde, clave])
		elif clave == "o":
			for otra in cond[clave]:
				_condicion(otra, donde)
		elif clave == "var":
			for nombre in cond[clave]:
				var valores = cond[clave][nombre]
				for valor in (valores if valores is Array else [valores]):
					_leido["%s=%d" % [nombre, int(valor)]] = true
		elif clave == "si" or clave == "no":
			for bandera in cond[clave]:
				_banderas_leidas[bandera] = donde


func _efecto(efectos: Dictionary, donde: String) -> void:
	for clave in efectos:
		if not EFECTOS.has(clave):
			_mal("%s: efecto desconocido '%s'" % [donde, clave])
		elif clave == "var":
			for nombre in efectos[clave]:
				_puesto["%s=%d" % [nombre, int(efectos[clave][nombre])]] = donde
		elif clave == "flag":
			for bandera in efectos[clave]:
				_banderas_puestas[bandera] = true


## Habla con alguien y va eligiendo la opción que contiene cada trozo de texto, en orden.
## Las páginas sin opciones se pasan solas.
func _hablar(id: String, elecciones: Array = []) -> void:
	if not H.hablar(id):
		_mal("%s no tiene nada que decir (momento %d)" % [id, H.momento])
		return
	_seguir(elecciones, id)


func _seguir(elecciones: Array, de_quien: String) -> void:
	var pendientes := elecciones.duplicate()
	var vueltas := 0
	while H.ocupado and vueltas < 50:
		vueltas += 1
		var opciones: Array = H.vista().get("opciones", [])
		if opciones.is_empty():
			H.avanzar()
			continue
		if pendientes.is_empty():
			_mal("%s ofrece opciones y la prueba no eligió: %s" % [de_quien, opciones])
			return
		var trozo: String = pendientes.pop_front()
		var indice := -1
		for i in opciones.size():
			if str(opciones[i]).contains(trozo):
				indice = i
		if indice < 0:
			_mal("%s no ofrece '%s' (ofrece %s)" % [de_quien, trozo, opciones])
			return
		H.elegir(indice)
	if not pendientes.is_empty():
		_mal("%s cerró la charla antes de '%s'" % [de_quien, pendientes[0]])


func _momento_1() -> void:
	H.nueva()
	_hablar("ceferino", ["con qué le he de pagar", "Voy."])
	H.poner("recado", 1)
	H.poner("recado", 2)
	_hablar("ceferino")
	_espero(H.momento == 2, "después del primer recado empieza el momento 2")
	var esperada := int(H.datos["config"]["deuda_inicial"]) - 20
	_espero(H.deuda == esperada, "la cuenta baje a %d (está en %d)" % [esperada, H.deuda])


func _fogon_cierra() -> void:
	H.sentarse_al_fogon()
	_seguir([], "el fogón")
	_espero(H.momento == 3, "el fogón cierra el capítulo y llega la línea (momento %d)" % H.momento)


func _espero(condicion: bool, que: String) -> void:
	if not condicion:
		_mal("se esperaba que " + que)


func _final_sargento() -> void:
	_momento_1()
	_hablar("rufino", ["Lo llevo."])
	_hablar("lucero", ["Un papel de Don Rufino"])
	_hablar("lucero", ["Voy, sargento."])
	H.poner("sena", 2)
	_hablar("lucero", ["Toldos cerca"])
	_hablar("nicasio")
	_hablar("painefil", ["no llevo cuentos"])
	_espero(H._aviso_del_momento().contains("fogón"), "con los tres encargos resueltos el aviso mande al fogón")
	H.sentarse_al_fogon()
	_seguir([], "el fogón")
	_espero(H.momento == 3, "el fogón cierre el capítulo (sargento)")
	_hablar("millaray")
	_hablar("lucero", ["Voy con usted"])
	_espero(H.final_elegido == "sargento" and H.deuda == 0, "el final sea sargento con la cuenta en cero (es '%s', %d)" % [H.final_elegido, H.deuda])


func _final_encargado() -> void:
	_momento_1()
	_hablar("rufino", ["Qué dice el papel", "Lo llevo."])
	_hablar("rosario", ["No."])
	_hablar("lucero", ["Un papel de Don Rufino"])
	_hablar("lucero", ["Gracias, pero me voy"])
	_hablar("painefil", ["Todavía no"])
	_hablar("painefil", ["no llevo cuentos"])
	_fogon_cierra()
	_hablar("lucero")
	_hablar("rufino", ["Acepto"])
	_espero(H.final_elegido == "encargado" and H.deuda == 0, "el final sea encargado con la cuenta en cero (es '%s', %d)" % [H.final_elegido, H.deuda])


func _final_chile() -> void:
	_momento_1()
	_hablar("rufino", ["Lo llevo."])
	_hablar("rosario", ["Léamelo."])
	_hablar("rufino", ["Ya sé lo que dice"])
	_hablar("lucero", ["Voy, sargento."])
	H.poner("sena", 2)
	_hablar("lucero", ["Gente no vi"])
	_hablar("rosario")
	_hablar("painefil", ["Y el sargento manda contar"])
	_hablar("millaray", ["Hay uno."])
	_fogon_cierra()
	_hablar("rufino")
	_hablar("painefil")
	_hablar("millaray", ["Voy adelante."])
	_espero(H.final_elegido == "chile", "el final sea chile (es '%s')" % H.final_elegido)
	# En la boca de la quebrada, Millaray ya no despide a Zenón: lo sigue.
	H.hablar("millaray")
	_espero(H.vista().get("paginas", [""])[0] == H.datos["nodos"]["millaray_paso"]["texto"], "Millaray hable del paso una vez elegido ese final")
	_seguir([], "millaray")


## Rechazando todo, la única puerta abierta es la de siempre: saldar e irse.
func _final_solitario_sin_hacer_nada() -> void:
	_momento_1()
	_hablar("rufino", ["Gracias, pero me voy"])
	_hablar("lucero", ["Gracias, pero me voy"])
	_hablar("painefil", ["no llevo cuentos"])
	_fogon_cierra()
	_hablar("lucero")
	_hablar("rufino")
	_hablar("painefil")
	_hablar("millaray")
	_espero(H.final_elegido == "", "sin confianza nadie ofrezca nada")
	_hablar("ceferino", ["Me voy para el sur"])
	_espero(H.final_elegido == "solitario" and H.deuda == 0, "el final sea solitario con la cuenta en cero")
	for id in H.datos["personajes"]:
		_hablar(id)


## Cada oferta aparece justo con el mínimo de confianza, y con uno menos no.
func _borde_del_minimo() -> void:
	var minimos: Dictionary = H.datos["config"]["minimos"]
	for par in [["ejercito", "lucero"], ["estancieros", "rufino"], ["tolderia", "millaray"]]:
		for falta in [0, 1]:
			H.poner_estado({"momento": 3, "confianza": {par[0]: int(minimos[par[0]]) - falta}})
			H.hablar(par[1])
			var ofrece: bool = not H.vista().get("opciones", []).is_empty()
			_espero(ofrece == (falta == 0), "%s ofrezca con el mínimo y no con uno menos (falta %d)" % [par[1], falta])


## La changa del capataz baja la cuenta y nada más: no mueve la confianza ni la trama. Se repite
## al otro día y se acaba después de las veces que dice datos/historia.json.
func _arreo() -> void:
	_momento_1()
	var d: Dictionary = H.datos.get("arreo", {})
	var veces := int(d.get("veces", 0))
	_espero(veces > 0 and int(d.get("paga", 0)) > 0, "datos/historia.json traiga los números del arreo")
	for vuelta in veces:
		var confianza_antes: Dictionary = H.confianza.duplicate()
		var deuda_antes: int = H.deuda
		_hablar("gaucho3", ["La traigo."])
		_espero(H.v("arreo") == 1 and H._aviso_del_momento().contains("arreo"), "al tomar el arreo el aviso diga adónde ir (vuelta %d)" % vuelta)
		_hablar("gaucho3")
		H._arreo_cumplido()
		_espero(H.deuda == deuda_antes - int(d.get("paga", 0)), "el arreo baje la cuenta %d pesos" % int(d.get("paga", 0)))
		_espero(H.confianza == confianza_antes and H.final_elegido == "" and H.momento == 2, "el arreo no mueva la confianza ni la trama")
		H.hablar("gaucho3")
		_espero(H.vista().get("opciones", []).is_empty(), "el mismo día el capataz no ofrezca otra punta")
		_seguir([], "gaucho3")
		H.sentarse_al_fogon()
		_seguir([], "el fogón")
	H.hablar("gaucho3")
	_espero(H.vista().get("opciones", []).is_empty(), "después de %d arreos el capataz no ofrezca más" % veces)
	_seguir([], "gaucho3")


func _guardado() -> void:
	# A mitad del momento 2 el fogón no cierra el capítulo y dice qué falta.
	_momento_1()
	_hablar("rufino", ["Lo llevo."])
	H.sentarse_al_fogon()
	_seguir([], "el fogón")
	_espero(H.momento == 2, "el fogón no cierre el capítulo con encargos pendientes")
	H.sentarse_al_fogon()  # Ya sin notas del día: lo que diga de más son los pensamientos.
	_espero(H.vista().get("paginas", []).size() > 1, "el fogón diga qué falta")
	_seguir([], "el fogón")
	# Ida y vuelta de la partida entera, con confianza, banderas y un final elegido.
	_final_chile()
	var antes := [H.momento, H.vars.duplicate(), H.flags.duplicate(), H.confianza.duplicate(), H.deuda, H.final_elegido]
	var copia: Dictionary = JSON.parse_string(JSON.stringify(H.estado()))
	H.nueva()
	H.poner_estado(copia)
	_espero([H.momento, H.vars, H.flags, H.confianza, H.deuda, H.final_elegido] == antes, "el estado vuelva igual después de guardar y cargar")

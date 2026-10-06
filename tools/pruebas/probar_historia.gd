extends SceneTree

## Prueba de la historia sin abrir el mundo. Recorre datos/historia.json por los cuatro finales,
## revisa que ningún diálogo quede sin salida, que no haya claves mal escritas ni banderas que
## nadie pone, que cada oferta aparezca justo con su mínimo de confianza y que la partida
## vuelva igual después de guardarla. Desde la tanda 7 recorre además los cinco conchabos hasta
## el cobro y saca las cuentas de cuánto baja la deuda. Si algo falla, termina con error y dice qué.
##   godot --headless --path <carpeta del proyecto> --script res://tools/pruebas/probar_historia.gd
## Tiene que terminar en "FALLAS: 0".

const CONDICIONES := ["momento", "var", "si", "no", "min", "menos", "final", "o", "deuda_hasta", "cerca", "periodo", "montado", "ligero"]
const EFECTOS := ["var", "flag", "confianza", "deuda", "saldar", "nota", "momento", "final", "jornada"]
## Los cinco conchabos de la tanda 7: el valor "hecho" (el que Ceferino cobra), el "cobrado" y cuánto paga.
const CONCHABOS := {"caballada": [2, 3, 12], "lenia": [3, 4, 5], "ponchos": [3, 4, 6], "chasque": [3, 4, 5], "yerra": [1, 2, 12]}

var H: Node
var fallas := 0
# Qué valores se ponen (y quién), cuáles se miran, y lo mismo con las banderas.
# El recado y el mojón los pone el mundo (player.gd), sin pasar por un diálogo; la caballada
# encerrada la ponen los datos del rebaño ("al_cumplir"), que se anota más abajo.
var _puesto := {"recado=1": "el mundo", "recado=2": "el mundo", "sena=2": "el mundo"}
var _leido := {}
var _banderas_puestas := {}
var _banderas_leidas := {}
# Todo lo que se leyó en la última charla (las páginas de cada pantalla, en orden).
var _visto: Array = []


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
	_changa_caballada()
	_changa_lenia()
	_changa_ponchos()
	_changa_chasque_y_yerra()
	_sin_ceniza()
	_cobros_y_salto()
	_calibracion_y_umbral()
	_fogon_con_arreo_a_medias()
	_saludos()
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
		if not (nodos[id] is Dictionary):
			continue  # Una nota para quien edita el archivo ("_cobros": "…").
		var nodo: Dictionary = nodos[id]
		var destinos: Array = [nodo.get("ir")]
		for rama in nodo.get("segun", []):
			destinos.append(rama.get("ir"))
		var siempre := false
		var ofrece_final := false
		var sin_efecto := false
		var con_condicion := ""
		for opcion in nodo.get("opciones", []):
			destinos.append(opcion.get("ir"))
			if not opcion.has("si"):
				siempre = true
			else:
				con_condicion = str(opcion.get("texto", ""))
			if opcion.get("hace", {}).has("final"):
				ofrece_final = true
			if not opcion.has("hace") and not opcion.has("ir") and not opcion.has("si"):
				sin_efecto = true
		if nodo.has("opciones") and not siempre:
			_mal("el nodo '%s' puede quedar sin ninguna opción" % id)
		# Una oferta de final siempre deja salir sin decidir ("Déjeme pensarlo.").
		if ofrece_final and not sin_efecto:
			_mal("el nodo '%s' ofrece un final y no tiene una opción que no cambie nada" % id)
		# En una oferta de final ninguna opción aparece y desaparece: se correrían los números, y el 2
		# de ayer ("¿Precisa algo más?") pasaría a ser hoy "Gracias, pero me voy.", que cierra ese final.
		if ofrece_final and con_condicion != "":
			_mal("el nodo '%s' ofrece un final y la opción '%s' tiene condición: los números se correrían" % [id, con_condicion])
		# La pregunta por un conchabo nunca es la primera opción (la que se aprieta sin mirar).
		if nodo.has("opciones") and str(nodo["opciones"][0].get("ir", "")).ends_with("_conchabo"):
			_mal("en el nodo '%s' la primera opción es la del conchabo" % id)
		if nodo.has("segun") and nodo["segun"][-1].has("si"):
			_mal("el nodo '%s' (segun) no tiene una rama final sin condición" % id)
		if not nodo.has("segun") and str(nodo.get("texto", "")) == "":
			_mal("el nodo '%s' no tiene texto" % id)
		for destino in destinos:
			if destino != null and not (nodos.get(str(destino)) is Dictionary):
				_mal("el nodo '%s' manda a '%s', que no existe" % [id, destino])
		_efecto(nodo.get("hace", {}), id)
		for rama in nodo.get("segun", []):
			_condicion(rama.get("si", {}), id)
		for opcion in nodo.get("opciones", []):
			_condicion(opcion.get("si", {}), id)
			_efecto(opcion.get("hace", {}), id)
	var fogon: Dictionary = H.datos.get("fogon", {})
	for lista in ["segun", "conchabos", "al_pasar"]:
		for caso in H.datos.get("avisos", {}).get(lista, []):
			_condicion(caso.get("si", {}), "un aviso")
			if str(caso.get("texto", "")) == "":
				_mal("hay un aviso sin texto")
			# Los avisos "al pasar" ponen su bandera cuando saltan (Historia._pensar_al_pasar).
			if caso.has("una_vez"):
				_banderas_puestas[caso["una_vez"]] = true
	_condicion(fogon.get("cierre", {}).get("si", {}), "el cierre del fogón")
	for extra in fogon.get("pensamientos", []):
		_condicion(extra.get("si", {}), "un pensamiento del fogón")
		if extra.has("una_vez"):
			_banderas_puestas[extra["una_vez"]] = true
	# Los rebaños, lo que cambia en el mundo y los carteles de "Presioná E" también miran y ponen cosas.
	for seccion in H.REBANOS:
		var rebano: Dictionary = H.datos.get(seccion, {})
		_condicion(rebano.get("suelta", {}), "el rebaño '%s'" % seccion)
		_condicion(rebano.get("encerrada", {}), "el rebaño '%s'" % seccion)
		_efecto(rebano.get("al_cumplir", {}), "el rebaño '%s'" % seccion)
	for entrada in H.datos.get("mundo", []):
		_condicion(entrada.get("si", {}), "una entrada de 'mundo'")
	for grupo in ["personajes", "changas"]:
		for id in H.datos.get(grupo, {}):
			if not (H.datos[grupo][id] is Dictionary):
				# El juego recorre estas listas esperando fichas: una nota suelta lo corta al entrar al mundo.
				_mal("en '%s' hay algo que no es una ficha ('%s'): las notas van afuera" % [grupo, id])
				continue
			var ficha: Dictionary = H.datos[grupo][id]
			if not (nodos.get(str(ficha.get("charla", ""))) is Dictionary):
				_mal("'%s' (%s) no tiene charla" % [id, grupo])
			_condicion(ficha.get("encuentro", {}).get("si", {}), "el encuentro de '%s'" % id)
			var mira = ficha.get("mira", [])
			for caso in (mira if mira is Array else [mira]):
				_condicion(caso.get("si", {}), "el cartel de '%s'" % id)
			# Los saludos (tanda 8): cortos, con texto, y sin llaves que nadie reemplace.
			for caso in ficha.get("saluda", []):
				_condicion(caso.get("si", {}), "el saludo de '%s'" % id)
				var textos = caso.get("texto", "")
				for texto in (textos if textos is Array else [textos]):
					if str(texto) == "" or str(texto).length() > 80:
						_mal("un saludo de '%s' está vacío o es largo para un cartelito: '%s'" % [id, texto])
					for llave in ["{buenas}", "{guenas}", "{deuda}"]:
						texto = str(texto).replace(llave, "")
					if str(texto).contains("{"):
						_mal("un saludo de '%s' trae una llave que nadie reemplaza: '%s'" % [id, texto])
	for par in _puesto:
		if not _leido.has(par):
			_mal("%s pone %s y ninguna condición mira ese valor" % [_puesto[par], par])
	for bandera in _banderas_leidas:
		if not _banderas_puestas.has(bandera):
			_mal("%s mira la bandera '%s', que nada pone" % [_banderas_leidas[bandera], bandera])
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
		elif clave == "cerca" and not H.datos.get("config", {}).get("cerca", {}).has(str(cond[clave])):
			_mal("%s: 'cerca' de '%s', que config.cerca no nombra" % [donde, cond[clave]])


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


## Los saludos de la tanda 8 no cambian nada: pedirlos todos, en cada momento, deja la historia igual.
## Y Don Ceferino dice lo de la cuenta flaca justo cuando la cuenta bajó a cuarenta.
func _saludos() -> void:
	H.nueva()
	for momento in [1, 2, 3]:
		H.momento = momento
		var antes := JSON.stringify(H.estado())
		for id in H.datos.get("personajes", {}):
			var linea: String = H.saludo_de(id)
			if linea.contains("{"):
				_mal("el saludo de '%s' en el momento %d quedó con una llave sin reemplazar: '%s'" % [id, momento, linea])
		if JSON.stringify(H.estado()) != antes:
			_mal("pedir los saludos cambió la historia en el momento %d" % momento)
	if H.saludo_de("anciana") != "":
		_mal("la anciana saluda, y no quiere tratos")
	H.momento = 2
	H.deuda = 41
	if H.saludo_de("ceferino").contains("flaca"):
		_mal("Ceferino dice que la cuenta va flaca con 41")
	H.deuda = 40
	if not H.saludo_de("ceferino").contains("flaca"):
		_mal("Ceferino no dice que la cuenta va flaca con 40")
	H.nueva()


## Habla con alguien y va eligiendo la opción que contiene cada trozo de texto, en orden.
## Las páginas sin opciones se pasan solas.
func _hablar(id: String, elecciones: Array = []) -> void:
	_visto = []
	if not H.hablar(id):
		_mal("%s no tiene nada que decir (momento %d)" % [id, H.momento])
		return
	_seguir(elecciones, id)


func _seguir(elecciones: Array, de_quien: String) -> void:
	var pendientes := elecciones.duplicate()
	var vueltas := 0
	while H.ocupado and vueltas < 50:
		vueltas += 1
		_visto.append_array(H.vista().get("paginas", []))
		var opciones: Array = H.vista().get("opciones", [])
		if opciones.size() > 4:
			_mal("%s muestra más de cuatro opciones: %s" % [de_quien, opciones])
		if opciones.is_empty():
			H.avanzar()
			continue
		if pendientes.is_empty():
			_mal("%s ofrece opciones y la prueba no eligió: %s" % [de_quien, opciones])
			H._cerrar()
			return
		var trozo: String = pendientes.pop_front()
		var indice := -1
		for i in opciones.size():
			if str(opciones[i]).contains(trozo):
				indice = i
		if indice < 0:
			_mal("%s no ofrece '%s' (ofrece %s)" % [de_quien, trozo, opciones])
			H._cerrar()
			return
		H.elegir(indice)
	if not pendientes.is_empty():
		_mal("%s cerró la charla antes de '%s'" % [de_quien, pendientes[0]])


## ¿En la última charla se leyó ese trozo de texto?
func _vio(trozo: String) -> bool:
	for pagina in _visto:
		if str(pagina).contains(trozo):
			return true
	return false


func _momento_1() -> void:
	H.nueva()
	H.cerca_forzada = null
	_hablar("ceferino", ["con qué le he de pagar", "Voy."])
	H.poner("recado", 1)
	H.poner("recado", 2)
	_hablar("ceferino")
	_espero(H.momento == 2, "después del primer recado empieza el momento 2")
	var esperada := int(H.datos["config"]["deuda_inicial"]) - 20
	_espero(H.deuda == esperada, "la cuenta baje a %d (está en %d)" % [esperada, H.deuda])


## El fogón pregunta antes del salto; la prueba elige dejar que pasen las semanas.
func _fogon_cierra() -> void:
	H.sentarse_al_fogon()
	_seguir(["Dejar que pasen las semanas."], "el fogón")
	_espero(H.momento == 3, "el fogón cierra el capítulo y llega la línea (momento %d)" % H.momento)


## Rechaza los tres encargos y deja pasar las semanas: abril, sin confianza con nadie.
func _abril_sin_nada() -> void:
	_momento_1()
	_hablar("rufino", ["Gracias, pero me voy"])
	_hablar("lucero", ["Gracias, pero me voy"])
	_hablar("painefil", ["no llevo cuentos"])
	_fogon_cierra()


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
	# "Todavía no." no salta: la noche pasa y Zenón sigue en el momento 2.
	H.sentarse_al_fogon()
	_seguir(["Todavía no."], "el fogón")
	_espero(H.momento == 2, "con 'Todavía no.' el fogón no cierre el capítulo")
	_fogon_cierra()
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
	_hablar("lucero", ["Nada más."])
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
	_abril_sin_nada()
	_hablar("lucero", ["Nada más."])
	_hablar("rufino")
	_hablar("painefil")
	_hablar("millaray")
	_espero(H.final_elegido == "", "sin confianza nadie ofrezca nada")
	_hablar("ceferino", ["Me voy para el sur"])
	_espero(H.final_elegido == "solitario" and H.deuda == 0, "el final sea solitario con la cuenta en cero")
	_espero(not H.flags.has("boleadoras_quedan"), "con la cuenta alta Ceferino se quede con las boleadoras")
	for id in H.datos["personajes"]:
		_hablar(id)


## ¿Alguna de las opciones a la vista elige un final?
func _ofrece_final() -> bool:
	for opcion in H._visibles:
		if opcion.get("hace", {}).has("final"):
			return true
	return false


## Cada oferta aparece justo con el mínimo de confianza, y con uno menos no.
func _borde_del_minimo() -> void:
	var minimos: Dictionary = H.datos["config"]["minimos"]
	for par in [["ejercito", "lucero"], ["estancieros", "rufino"], ["tolderia", "millaray"]]:
		for falta in [0, 1]:
			H.poner_estado({"momento": 3, "confianza": {par[0]: int(minimos[par[0]]) - falta}})
			H.hablar(par[1])
			_espero(_ofrece_final() == (falta == 0), "%s ofrezca con el mínimo y no con uno menos (falta %d)" % [par[1], falta])
			H._cerrar()


## La changa del capataz baja la cuenta y nada más: no mueve la confianza ni la trama. Se repite
## al otro día y se acaba después de las veces que dice datos/historia.json.
func _arreo() -> void:
	_momento_1()
	var d: Dictionary = H.datos.get("arreo", {})
	var veces := int(d.get("veces", 0))
	_espero(veces > 0 and int(d.get("paga", 0)) > 0, "datos/historia.json traiga los números del arreo")
	_hablar("ceferino", ["algún conchabo"])
	_espero(_vio("capataz"), "Ceferino nombre el arreo del capataz antes de que lo ofrezca")
	for vuelta in veces:
		var confianza_antes: Dictionary = H.confianza.duplicate()
		var deuda_antes: int = H.deuda
		_hablar("gaucho3", ["La traigo."])
		_espero(H.v("arreo") == 1 and H._aviso_del_momento().contains("arreo"), "al tomar el arreo el aviso diga adónde ir (vuelta %d)" % vuelta)
		_hablar("gaucho3")
		H._rebano_cumplido("arreo")
		_espero(H.deuda == deuda_antes - int(d.get("paga", 0)), "el arreo baje la cuenta %d patacones" % int(d.get("paga", 0)))
		_espero(H.confianza == confianza_antes and H.final_elegido == "" and H.momento == 2, "el arreo no mueva la confianza ni la trama")
		H.hablar("gaucho3")
		_espero(H.vista().get("opciones", []).is_empty(), "el mismo día el capataz no ofrezca otra punta")
		_seguir([], "gaucho3")
		H.sentarse_al_fogon()
		_seguir([], "el fogón")
	H.hablar("gaucho3")
	_espero(H.vista().get("opciones", []).is_empty(), "después de %d arreos el capataz no ofrezca más" % veces)
	_seguir([], "gaucho3")


## Lo que tiene que quedar igual después de un conchabo: la confianza, el final y el momento.
func _foto() -> Array:
	return [H.confianza.duplicate(), H.final_elegido, H.momento]


## Cobra en lo de Ceferino y comprueba que ese conchabo bajó la cuenta lo que dice la tabla y nada más.
func _cobrar(conchabo: String, antes: Array, deuda_antes: int, salida: String) -> void:
	var datos: Array = CONCHABOS[conchabo]
	_espero(H.v(conchabo) == datos[0], "el conchabo '%s' quede hecho antes del cobro (vale %d)" % [conchabo, H.v(conchabo)])
	_espero(H._aviso_del_momento().contains("sin cobrar"), "con '%s' hecho, Tab mande a cobrar a lo de Ceferino" % conchabo)
	_hablar("ceferino", [salida])
	_espero(H.v(conchabo) == datos[1], "Ceferino cobre '%s' (vale %d)" % [conchabo, H.v(conchabo)])
	_espero(H.deuda == deuda_antes - int(datos[2]), "'%s' baje la cuenta %d patacones (de %d a %d)" % [conchabo, datos[2], deuda_antes, H.deuda])
	_espero(_foto() == antes, "'%s' no mueva la confianza, el final ni el momento" % conchabo)
	_espero(not H._aviso_del_momento().contains("sin cobrar"), "cobrado '%s', Tab ya no mande a cobrar" % conchabo)


## Campear la caballada (Lucero). En el momento 2 se ofrece recién con la seña resuelta.
func _changa_caballada() -> void:
	_momento_1()
	_hablar("ceferino", ["algún conchabo"])
	_espero(not _vio("caballada"), "Ceferino no nombre la caballada mientras Lucero todavía pide la seña")
	_hablar("lucero", ["Gracias, pero me voy"])
	var antes := _foto()
	var deuda_antes: int = H.deuda
	_hablar("ceferino", ["algún conchabo"])
	_espero(_vio("caballada"), "Ceferino nombre la caballada antes de que Lucero la ofrezca")
	_hablar("lucero", ["Otro día."])
	_espero(H.v("caballada") == 0, "con 'Otro día.' la caballada no quede tomada")
	_hablar("lucero", ["Se la campeo"])
	_espero(H.v("caballada") == 1 and H._aviso_del_momento().contains("caballada"), "al tomar la caballada Tab diga adónde ir")
	_hablar("lucero")
	_espero(_vio("campo afuera"), "con la caballada suelta Lucero recuerde dónde anda")
	H._rebano_cumplido("caballada")
	_espero(H.deuda == deuda_antes, "encerrar la caballada no baje la cuenta sola: se cobra en lo de Ceferino")
	_cobrar("caballada", antes, deuda_antes, "Nada más.")
	_hablar("lucero")
	_espero(_vio("tropilla"), "Lucero diga algo de la caballada ya cobrada")


## Leña para el Salitral (el veterano). El jarillal es un lugar de trabajo, no una persona.
func _changa_lenia() -> void:
	_momento_1()
	var antes := _foto()
	var deuda_antes: int = H.deuda
	_hablar("ceferino", ["algún conchabo"])
	_espero(_vio("leña"), "Ceferino nombre la leña antes de que el veterano la ofrezca")
	# El parte y la yerra son de abril: antes ni Ceferino los nombra ni sus dueños los ofrecen.
	_espero(not _vio("parte") and not _vio("yerra"), "en el momento 2 Ceferino no nombre el parte ni la yerra")
	_hablar("gaucho2")
	_hablar("centinela")
	_hablar("jarillal")
	_espero(H.v("lenia") == 0, "el jarillal, sin el trabajo tomado, solo se mire")
	_hablar("soldado3", ["Se lo traigo."])
	_espero(H.v("lenia") == 1 and H._aviso_del_momento().contains("Jarillal"), "al tomar la leña Tab diga adónde ir")
	_espero(H.mira_de("jarillal").contains("cortar leña"), "con la leña tomada el jarillal diga 'cortar leña'")
	_hablar("jarillal", ["Después."])
	_espero(H.v("lenia") == 1, "con 'Después.' no se corte nada")
	_hablar("jarillal", ["Cortar un atado."])
	_espero(H.v("lenia") == 2 and H._jornada.is_empty(), "cortar deje la leña cargada (y la jornada, hecha)")
	_hablar("soldado3")
	_espero(H.v("lenia") == 3 and _vio("vale"), "el veterano reciba la leña y dé el vale")
	_cobrar("lenia", antes, deuda_antes, "Nada más.")
	_hablar("soldado3")
	_espero(_vio("leña"), "el veterano diga algo de la leña ya entregada")


## Los ponchos de la tejedora. La pista hacia Chile sale solo en el momento 2 y si falta confianza.
func _changa_ponchos() -> void:
	_momento_1()
	var antes := _foto()
	var deuda_antes: int = H.deuda
	_hablar("ceferino", ["algún conchabo"])
	_espero(_vio("ponchos"), "Ceferino nombre los ponchos antes de que la tejedora los ofrezca")
	_hablar("tejedora", ["Los llevo."])
	_espero(H.v("ponchos") == 1 and H._aviso_del_momento().contains("ponchos"), "al tomar los ponchos Tab diga adónde ir")
	_hablar("ceferino", ["Nada más."])
	_espero(H.v("ponchos") == 2 and _vio("sabe lo que vale"), "Ceferino pague los ponchos al precio de ella")
	_espero(H.deuda == deuda_antes, "vender los ponchos no baje la cuenta: son de ella")
	_hablar("tejedora")
	_espero(H.v("ponchos") == 3 and _vio("A Painefil"), "la tejedora reciba lo suyo y, sin confianza, diga qué llevarle a Painefil")
	_cobrar("ponchos", antes, deuda_antes, "Nada más.")
	_hablar("tejedora")
	_espero(_vio("ya traté"), "la tejedora diga algo de los ponchos ya cobrados")
	# Con la confianza de la toldería en el mínimo, la pista no hace falta y no sale.
	_momento_1()
	H.confianza["tolderia"] = int(H.datos["config"]["minimos"]["tolderia"])
	H.poner("ponchos", 2)
	_hablar("tejedora")
	_espero(H.v("ponchos") == 3 and not _vio("A Painefil"), "con confianza la tejedora no dé la pista")


## El chasque al campamento y la yerra, que son de abril (momento 3), y la caballada tomada en abril.
func _changa_chasque_y_yerra() -> void:
	_abril_sin_nada()
	var antes := _foto()
	var deuda_antes: int = H.deuda
	_hablar("ceferino", ["algún conchabo"])
	_espero(_vio("parte") and _vio("yerra") and _vio("caballada"), "en abril Ceferino nombre el parte, la yerra y la caballada")
	_espero(not _vio("capataz"), "en abril Ceferino no nombre el arreo, que ya no se ofrece")
	_hablar("centinela")
	_espero(H.v("chasque") == 0, "sin el parte, el centinela salude como siempre")
	_hablar("lucero", ["Precisa algo más", "El parte.", "Lo llevo"])
	_espero(H.v("chasque") == 1 and H._aviso_del_momento().contains("parte"), "al tomar el parte Tab diga adónde ir")
	_hablar("centinela")
	_espero(H.v("chasque") == 2 and _vio("en mano"), "el centinela reciba el parte y dé la respuesta")
	_hablar("lucero", ["Yo no leo", "Nada más."])
	_espero(H.v("chasque") == 3, "Lucero reciba la respuesta")
	_cobrar("chasque", antes, deuda_antes, "Todavía no.")
	_hablar("centinela")
	_espero(_vio("conocen"), "el centinela ya conozca al baqueano")
	# La yerra: una jornada con el peón, sin lugar aparte.
	deuda_antes = H.deuda
	_hablar("gaucho2", ["Doy una mano."])
	_espero(H.v("yerra") == 1 and H._jornada.is_empty(), "la yerra quede hecha (y la jornada, pasada)")
	_cobrar("yerra", antes, deuda_antes, "Todavía no.")
	_hablar("gaucho2")
	_espero(_vio("lazo"), "el peón diga algo de la yerra ya hecha")
	# La caballada en abril: Lucero ya no tiene otra cosa que ofrecer, así que va derecho a ella.
	deuda_antes = H.deuda
	_hablar("lucero", ["Precisa algo más", "Se la campeo"])
	_espero(H.v("caballada") == 1, "en abril la caballada se tome por '¿Precisa algo más, sargento?'")
	H.hablar("lucero")
	_espero(H.vista().get("opciones", []).size() == 1, "sin nada que ofrecer, Lucero no muestre la opción de trabajo")
	_seguir(["Nada más."], "lucero")
	H._rebano_cumplido("caballada")
	_cobrar("caballada", antes, deuda_antes, "Todavía no.")


## Lo que pide a Ceniza no existe sin ella: la charla sigue como siempre y nada cambia.
func _sin_ceniza() -> void:
	_abril_sin_nada()
	H.cerca_forzada = false
	H.poner("ponchos", 1)
	H.hablar("ceferino")
	_espero(H.v("ponchos") == 1, "sin Ceniza cerca Ceferino no reciba los ponchos")
	var opciones: Array = H.vista().get("opciones", [])
	_espero(opciones.size() == 3 and str(opciones[0]).contains("Me voy para el sur"), "a pie, con los ponchos tomados, la cuenta y la oferta de final sigan ahí (%s)" % [opciones])
	_seguir(["Todavía no."], "ceferino")
	_espero(H._aviso_del_momento().contains("traela hasta la pulpería"), "Tab diga que los ponchos van en Ceniza")
	H.poner("ponchos", 2)
	_hablar("tejedora")
	_espero(H.v("ponchos") == 2 and _vio("Traelo"), "sin Ceniza la tejedora pida el caballo y no cambie nada")
	H.poner("lenia", 1)
	_espero(not H.mira_de("jarillal").contains("Presioná E para cortar"), "sin Ceniza el jarillal no ofrezca cortar")
	_hablar("jarillal")
	_espero(H.v("lenia") == 1 and _vio("Sin Ceniza"), "sin Ceniza no se corte leña")
	H.poner("lenia", 2)
	_hablar("soldado3")
	_espero(H.v("lenia") == 2 and _vio("montado"), "sin Ceniza el veterano pida el montado y no cambie nada")
	H.cerca_forzada = null


## Varios cobros se encadenan en una sola charla; uno pendiente pasa el salto de las semanas; y
## con un final ya elegido no se cobra nada.
func _cobros_y_salto() -> void:
	# Pendiente al llegar al salto.
	_momento_1()
	_hablar("rufino", ["Gracias, pero me voy"])
	_hablar("lucero", ["Gracias, pero me voy"])
	_hablar("painefil", ["no llevo cuentos"])
	H.poner("lenia", 3)
	_fogon_cierra()
	var deuda_antes: int = H.deuda
	_hablar("ceferino", ["Todavía no."])
	_espero(H.v("lenia") == 4 and H.deuda == deuda_antes - 5, "un cobro pendiente se cobre también después del salto")
	# Los cinco juntos.
	var total := 0
	for conchabo in CONCHABOS:
		H.poner(conchabo, CONCHABOS[conchabo][0])
		total += int(CONCHABOS[conchabo][2])
	deuda_antes = H.deuda
	_hablar("ceferino", ["Todavía no."])
	_espero(H.deuda == deuda_antes - total, "los cinco cobros se encadenen en una charla (bajó %d, tenía que bajar %d)" % [deuda_antes - H.deuda, total])
	for conchabo in CONCHABOS:
		_espero(H.v(conchabo) == CONCHABOS[conchabo][1], "'%s' quede cobrado" % conchabo)
	# Con un final ya elegido se cortan todos.
	_abril_sin_nada()
	_hablar("ceferino", ["Me voy para el sur"])
	H.poner("yerra", 1)
	H.poner("ponchos", 1)
	_hablar("ceferino")
	_espero(H.v("yerra") == 1 and H.v("ponchos") == 1 and H.deuda == 0, "con un final elegido Ceferino ya no cobre ni reciba nada")
	for id in H.datos["personajes"]:
		_hablar(id)
	_espero(H.v("yerra") == 1 and H.v("ponchos") == 1 and H.v("lenia") == 0 and H.v("caballada") == 0, "con un final elegido nadie ofrezca ni mueva un conchabo")


## Las cuentas de la tanda 7: toda la trama deja 90 en abril; con tres arreos, 45; con los cinco
## conchabos, 5. Y el umbral del final solitario: con 40 o menos, las boleadoras se quedan.
func _calibracion_y_umbral() -> void:
	var total := 0
	for conchabo in CONCHABOS:
		total += int(CONCHABOS[conchabo][2])
	var arreo: Dictionary = H.datos.get("arreo", {})
	var arreos := int(arreo.get("paga", 0)) * int(arreo.get("veces", 0))
	_espero(total == 40 and arreos == 45, "los cinco conchabos sumen 40 y los tres arreos, 45 (suman %d y %d)" % [total, arreos])
	# Toda la trama, contándole todo a todos.
	_momento_1()
	_hablar("rufino", ["Lo llevo."])
	_hablar("rosario", ["Léamelo."])
	_hablar("lucero", ["Un papel de Don Rufino"])
	_hablar("lucero", ["Voy, sargento."])
	H.poner("sena", 2)
	_hablar("lucero", ["Toldos cerca"])
	_hablar("painefil", ["Y el sargento manda contar"])
	_fogon_cierra()
	_espero(H.deuda == 90, "toda la trama deje la cuenta en 90 al llegar abril (quedó en %d)" % H.deuda)
	_espero(H.deuda - arreos == 45 and H.deuda - arreos - total == 5, "con tres arreos queden 45 y con los cinco conchabos, 5")
	# El umbral: 40 se queda con las boleadoras, 41 no, y con cero no debe nada.
	for caso in [[41, false, "Raspando"], [40, true, "quedátelas"], [5, true, "quedátelas"], [0, true, "No me debés nada. Andá."]]:
		H.poner_estado({"momento": 3, "deuda": caso[0]})
		_hablar("ceferino", ["Me voy para el sur"])
		_espero(H.final_elegido == "solitario" and H.deuda == 0, "el final solitario se elija con cualquier monto (deuda %d)" % caso[0])
		_espero(H.flags.has("boleadoras_quedan") == caso[1], "con la cuenta en %d las boleadoras %s" % [caso[0], "se queden" if caso[1] else "las cobre Ceferino"])
		_espero(_vio(caso[2]), "con la cuenta en %d Ceferino diga '%s'" % [caso[0], caso[2]])
	# El pensamiento de la cuenta liviana sale una sola vez, al bajar de cien.
	_momento_1()
	H.deuda = 99
	_visto = []
	H.sentarse_al_fogon()
	_seguir([], "el fogón")
	_espero(_vio("ya no me pesa"), "con la cuenta en 99 Zenón lo piense en el fogón")
	_visto = []
	H.sentarse_al_fogon()
	_seguir([], "el fogón")
	_espero(not _vio("ya no me pesa") and not _vio("la sombra me apunta"), "los pensamientos de una vez no se repitan")


## El salto de las semanas con la punta de Don Rufino a medias: el fogón lo dice y el arreo se cierra.
func _fogon_con_arreo_a_medias() -> void:
	_momento_1()
	_hablar("rufino", ["Gracias, pero me voy"])
	_hablar("lucero", ["Gracias, pero me voy"])
	_hablar("painefil", ["no llevo cuentos"])
	_hablar("gaucho3", ["La traigo."])
	_visto = []
	H.sentarse_al_fogon()
	_seguir(["Todavía no."], "el fogón")
	_espero(_vio("sigue campo afuera") and H.momento == 2 and H.v("arreo") == 1, "con el arreo a medias el fogón lo diga, y 'Todavía no.' no cambie nada")
	_fogon_cierra()
	_espero(H.v("arreo") == 3, "el salto cierre el arreo que quedó a medias (vale %d)" % H.v("arreo"))
	_hablar("gaucho3")
	_espero(_vio("la trajo otro"), "en abril el capataz diga que la punta la trajo otro")
	_hablar("gaucho3")
	_espero(not _vio("la trajo otro"), "y lo diga una sola vez")


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
	H.poner("lenia", 2)
	var antes := [H.momento, H.vars.duplicate(), H.flags.duplicate(), H.confianza.duplicate(), H.deuda, H.final_elegido]
	var copia: Dictionary = JSON.parse_string(JSON.stringify(H.estado()))
	H.nueva()
	H.poner_estado(copia)
	_espero([H.momento, H.vars, H.flags, H.confianza, H.deuda, H.final_elegido] == antes, "el estado vuelva igual después de guardar y cargar")

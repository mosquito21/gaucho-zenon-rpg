extends Control

## Menú principal. Si hay una partida guardada sin terminar aparece "Continuar", y el botón
## de siempre pasa a decir "Empezar de nuevo" y pide confirmación antes de apartarla.
## Si alguna partida llegó a abril de 1881, aparece además "Volver a abril de 1881".

@onready var _empezar: Button = $MenuContainer/MenuVBox/PlayButton


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if Historia.hay_abril():
		_sumar_boton("Volver a abril de 1881", _on_abril_pressed, _empezar.get_index() + 1)
	if not Historia.hay_partida():
		return
	_empezar.text = "Empezar de nuevo"
	if not Historia.partida_terminada():
		var continuar := _sumar_boton("Continuar", _continuar, 0)
		# Dice en qué época quedó la partida, para saber cuál es sin abrirla.
		var epoca := Historia.epoca_guardada()
		if epoca != "":
			continuar.text = "Continuar · %s" % epoca
		continuar.grab_focus()


## Un botón igual al de empezar, con otro texto y otra acción, en ese lugar de la lista.
func _sumar_boton(texto: String, accion: Callable, lugar: int) -> Button:
	var boton := _empezar.duplicate() as Button
	boton.name = texto.to_pascal_case()
	boton.text = texto
	# El duplicado trae la conexión del botón de empezar: se cambia por la suya.
	if boton.pressed.is_connected(_on_play_button_pressed):
		boton.pressed.disconnect(_on_play_button_pressed)
	boton.pressed.connect(accion)
	_empezar.add_sibling(boton)
	_empezar.get_parent().move_child(boton, lugar)
	return boton


func _confirmar(titulo: String, texto: String, accion: Callable) -> void:
	var aviso := ConfirmationDialog.new()
	aviso.title = titulo
	aviso.dialog_text = texto
	aviso.ok_button_text = titulo
	aviso.cancel_button_text = "Volver"
	aviso.confirmed.connect(accion)
	add_child(aviso)
	aviso.popup_centered()


func _continuar() -> void:
	Historia.cargar()
	get_tree().change_scene_to_file("res://scenes/World.tscn")


func _on_play_button_pressed() -> void:
	# También con una partida terminada: la partida no se borra, pero deja de ser la que se continúa.
	if Historia.hay_partida():
		_confirmar("Empezar de nuevo", "La historia empieza otra vez.\nLa partida guardada no se borra: queda apartada, con el nombre \"partida_terminada\".", _empezar_de_nuevo)
		return
	_empezar_de_nuevo()


func _empezar_de_nuevo() -> void:
	if not Historia.borrar_partida():
		_no_se_pudo_apartar()
		return
	get_tree().change_scene_to_file("res://scenes/World.tscn")


func _on_abril_pressed() -> void:
	var texto := "Volvés a la copia que se guardó cuando llegó la línea, en abril de 1881, para elegir otra vez."
	if Historia.hay_partida():
		texto += "\nLa partida guardada no se borra: queda apartada, con el nombre \"partida_terminada\"."
	_confirmar("Volver a abril de 1881", texto, _volver_a_abril)


func _volver_a_abril() -> void:
	if Historia.volver_a_abril():
		get_tree().change_scene_to_file("res://scenes/World.tscn")
	else:
		_no_se_pudo_apartar()


## La partida en curso no se pudo apartar: no se toca nada y se avisa.
func _no_se_pudo_apartar() -> void:
	OS.alert("No se pudo apartar la partida guardada (¿está abierto \"partida_terminada\" en otro programa?).\nNo se cambió nada.", "El Gaucho Zenón")


func _on_quit_button_pressed() -> void:
	get_tree().quit()

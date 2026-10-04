extends Control

## Menú principal. Si hay una partida guardada sin terminar aparece "Continuar", y el botón
## de siempre pasa a decir "Empezar de nuevo" y pide confirmación antes de borrarla.

@onready var _empezar: Button = $MenuContainer/MenuVBox/PlayButton


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not Historia.hay_partida():
		return
	_empezar.text = "Empezar de nuevo"
	if Historia.partida_terminada():
		return
	var continuar := _empezar.duplicate() as Button
	continuar.name = "ContinueButton"
	continuar.text = "Continuar"
	# El duplicado trae la conexión del botón de empezar: se cambia por la suya.
	if continuar.pressed.is_connected(_on_play_button_pressed):
		continuar.pressed.disconnect(_on_play_button_pressed)
	continuar.pressed.connect(_continuar)
	_empezar.add_sibling(continuar)
	_empezar.get_parent().move_child(continuar, 0)
	continuar.grab_focus()


func _continuar() -> void:
	Historia.cargar()
	get_tree().change_scene_to_file("res://scenes/World.tscn")


func _on_play_button_pressed() -> void:
	if Historia.hay_partida() and not Historia.partida_terminada():
		var aviso := ConfirmationDialog.new()
		aviso.title = "Empezar de nuevo"
		aviso.dialog_text = "Se borra la partida guardada y la historia empieza otra vez."
		aviso.ok_button_text = "Empezar de nuevo"
		aviso.cancel_button_text = "Volver"
		aviso.confirmed.connect(_empezar_de_nuevo)
		add_child(aviso)
		aviso.popup_centered()
		return
	_empezar_de_nuevo()


func _empezar_de_nuevo() -> void:
	Historia.borrar_partida()
	get_tree().change_scene_to_file("res://scenes/World.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()

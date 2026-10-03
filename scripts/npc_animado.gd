extends Node3D

## Pone en movimiento a un personaje armado con Mixamo (los "<nombre>_animado.glb").
## Va en el nodo del personaje, el que tiene adentro a "Modelo". Reproduce los clips de la
## lista en orden y vuelve a empezar; si un nombre aparece varias veces, ese clip se repite.
## Solo mueve el modelo: no toca los trabajos, la interacción ni el choque.

## Clips a reproducir, en orden. Los nombres son los que trae el GLB (idle, talking, etc.).
@export var clips: Array[String] = ["idle"]
## Segundos que tarda en pasar suave de un clip al siguiente.
@export var mezcla: float = 0.4
## Arranca en un clip y en un momento al azar, para que no se muevan todos a la vez.
@export var arranque_al_azar: bool = true

var _anim: AnimationPlayer
var _turno: int = 0

func _ready() -> void:
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		push_warning("%s: no hay AnimationPlayer debajo de este nodo (¿el Modelo es un _animado.glb?)" % name)
		return
	var validos: Array[String] = []
	for clip in clips:
		if _anim.has_animation(clip):
			validos.append(clip)
		else:
			push_warning("%s: el modelo no tiene el clip '%s'" % [name, clip])
	clips = validos
	if clips.is_empty():
		return
	_anim.playback_default_blend_time = mezcla
	_anim.animation_finished.connect(_al_terminar)
	if arranque_al_azar:
		_turno = randi() % clips.size()
	_anim.play(clips[_turno])
	if arranque_al_azar:
		_anim.seek(randf() * _anim.current_animation_length, true)

func _al_terminar(_clip: StringName) -> void:
	_turno = (_turno + 1) % clips.size()
	_anim.play(clips[_turno])

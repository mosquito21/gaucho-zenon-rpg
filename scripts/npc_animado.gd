extends Node3D

## Pone en movimiento a un personaje armado con Mixamo (los "<nombre>_animado.glb").
## Va en el nodo del personaje, el que tiene adentro a "Modelo". Reproduce los clips de la
## lista en orden y vuelve a empezar; si un nombre aparece varias veces, ese clip se repite.
## Solo mueve el modelo: no toca los trabajos, la interacción ni el choque.
## También lo usan los caballos y los perros (clips "idle" y "graze").

## Clips a reproducir, en orden. Los nombres son los que trae el GLB (idle, talking, etc.).
@export var clips: Array[String] = ["idle"]
## Segundos que tarda en pasar suave de un clip al siguiente.
@export var mezcla: float = 0.4
## Arranca en un clip y en un momento al azar, para que no se muevan todos a la vez.
@export var arranque_al_azar: bool = true
## A más de esta distancia de la cámara (en metros) la animación se detiene, para no gastar
## en mover a quien no se ve. Al acercarse sigue donde estaba.
@export var distancia_animado: float = 130.0

@export_group("Porte")
## Ritmo: 1 es el del clip. Menos es más lento y pesado; más es más rápido y nervioso.
@export_range(0.5, 1.5, 0.01) var ritmo: float = 1.0
## Espalda, en grados: positivo encorva, negativo yergue (pecho afuera).
@export_range(-15.0, 30.0, 0.5) var encorvar: float = 0.0
## Cabeza, en grados: positivo la baja, negativo levanta el mentón.
@export_range(-15.0, 20.0, 0.5) var cabeza: float = 0.0
## Hombros, en grados: positivo los deja caer hacia adelante, negativo los echa atrás.
@export_range(-10.0, 15.0, 0.5) var hombros: float = 0.0
## Cuántos grados gira la cabeza cuando mira alrededor (0: no mira).
@export_range(0.0, 45.0, 1.0) var mirar: float = 0.0
## Cada cuántos segundos, más o menos, mira hacia un lado.
@export_range(2.0, 20.0, 0.5) var mirar_cada: float = 7.0
## Grados de vaivén lento del tronco, como quien cambia el peso de pierna.
@export_range(0.0, 5.0, 0.1) var mecer: float = 0.0
## Grados que se abren los brazos hacia afuera, para que las manos no se metan en el cuerpo o en la ropa.
@export_range(0.0, 20.0, 0.5) var abrir_brazos: float = 0.0
## Largo de los dedos: 1 los deja como vienen en el modelo; menos los acorta (solo en personajes con dedos).
@export_range(0.4, 1.0, 0.01) var dedos: float = 1.0

var _anim: AnimationPlayer
var _porte: Porte
var _turno: int = 0
var _falta_revisar: float = 0.0

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
	_armar_porte()
	_anim.playback_default_blend_time = mezcla
	_anim.animation_finished.connect(_al_terminar)
	if arranque_al_azar:
		_turno = randi() % clips.size()
	_tocar()
	if arranque_al_azar:
		_anim.seek(randf() * _anim.current_animation_length, true)

func _process(delta: float) -> void:
	# Dos o tres veces por segundo mira si la cámara está cerca; si no, deja la animación en pausa.
	_falta_revisar -= delta
	if _falta_revisar > 0.0 or _anim == null:
		return
	_falta_revisar = 0.4
	var camara := get_viewport().get_camera_3d()
	if camara == null:
		return
	var cerca := camara.global_position.distance_squared_to(global_position) < distancia_animado * distancia_animado
	_anim.active = cerca
	if _porte != null:
		_porte.active = cerca

func _al_terminar(_clip: StringName) -> void:
	_turno = (_turno + 1) % clips.size()
	_tocar()

## Cada vez que empieza un clip va un poquito más rápido o más lento, para que no se repita igual.
func _tocar() -> void:
	_anim.play(clips[_turno], -1.0, ritmo * randf_range(0.93, 1.07))

## El porte se suma por encima de los clips (ver scripts/porte.gd). Si todo está en cero, no se crea.
func _armar_porte() -> void:
	if is_zero_approx(absf(encorvar) + absf(cabeza) + absf(hombros) + mirar + mecer + abrir_brazos + absf(1.0 - dedos)):
		return
	var esqueleto := find_child("Skeleton3D", true, false) as Skeleton3D
	if esqueleto == null:
		return
	_porte = Porte.new()
	_porte.name = "Porte"
	_porte.encorvar = encorvar
	_porte.cabeza = cabeza
	_porte.hombros = hombros
	_porte.mirar = mirar
	_porte.mirar_cada = mirar_cada
	_porte.mecer = mecer
	_porte.abrir_brazos = abrir_brazos
	_porte.dedos = dedos
	esqueleto.add_child(_porte)

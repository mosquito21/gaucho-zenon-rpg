extends OmniLight3D

## Hace temblar la luz de un fogón, como la de un fuego de verdad.
## Va en la luz (el nodo "LuzFogon" de cada fogón). Solo cambia su fuerza: no toca nada más.

## Cuánto tiembla: 0 es quieta, 0.25 es un fuego tranquilo.
@export var temblor: float = 0.25

var _fuerza: float
var _fase: float

func _ready() -> void:
	_fuerza = light_energy
	# Cada fogón arranca en un momento distinto, para que no tiemblen todos a la vez.
	_fase = randf() * 100.0

func _process(_delta: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001 + _fase
	light_energy = _fuerza * (1.0 + temblor * (sin(t * 7.3) * 0.5 + sin(t * 13.1) * 0.3 + sin(t * 23.7) * 0.2))

extends Node

# Singleton para manejar la música del juego
# Este script se ejecuta automáticamente al iniciar el juego

# Nodo AudioStreamPlayer para reproducir la música
var reproductor_musica: AudioStreamPlayer

# Lista de canciones disponibles
var lista_canciones: Array[String] = []

# Carpeta donde están las canciones
@export var carpeta_musica: String = "res://audio/musica/"

# Volumen de la música (0.0 a 1.0)
@export var volumen_musica: float = 0.5

# Índice de la canción actual
var cancion_actual_index: int = -1

# Extensiones de archivo soportadas
var extensiones_soportadas: Array[String] = [".mp3", ".ogg", ".wav"]

func _ready():
	"""
	Se ejecuta automáticamente cuando el juego inicia
	"""
	print("ManejadorMusica: Inicializando sistema de música...")
	# La música sigue sonando con el juego en pausa (scripts/Ajustes.gd).
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Crear el nodo AudioStreamPlayer
	reproductor_musica = AudioStreamPlayer.new()
	# La música sale por su propio canal, para poder darle su volumen aparte del de los sonidos.
	reproductor_musica.bus = &"Musica"

	# Añadir el reproductor como hijo de este nodo
	add_child(reproductor_musica)
	
	# Configurar el reproductor para cambiar de canción cuando termine
	reproductor_musica.finished.connect(_on_musica_finished)
	
	# Buscar todas las canciones en la carpeta
	buscar_canciones()
	
	# Reproducir la primera canción aleatoria
	reproducir_siguiente_cancion()

func buscar_canciones():
	"""
	Busca todos los archivos de música en la carpeta especificada
	"""
	lista_canciones.clear()
	
	# ResourceLoader.list_directory lista lo que el juego puede cargar, también dentro del paquete
	# exportado: ahí los .mp3 no existen como archivos (existe lo importado) y DirAccess no veía
	# ninguno, así que el juego exportado quedaba mudo. Las subcarpetas vienen terminadas en "/" y
	# quedan afuera (así "afuera_por_ahora/" sigue sin sonar).
	for nombre_archivo in ResourceLoader.list_directory(carpeta_musica):
		for extension in extensiones_soportadas:
			if nombre_archivo.to_lower().ends_with(extension):
				lista_canciones.append(carpeta_musica + nombre_archivo)
				print("ManejadorMusica: Canción encontrada - " + nombre_archivo)
				break
	
	print("ManejadorMusica: Se encontraron " + str(lista_canciones.size()) + " canciones")

func reproducir_siguiente_cancion():
	"""
	Reproduce una canción aleatoria de la lista
	"""
	if lista_canciones.is_empty():
		print("ManejadorMusica: No hay canciones para reproducir")
		print("ManejadorMusica: Coloca archivos .mp3, .ogg o .wav en " + carpeta_musica)
		return
	
	# Seleccionar una canción aleatoria diferente a la actual
	var nuevo_index = randi() % lista_canciones.size()
	
	# Si hay más de una canción, evitar repetir la misma
	if lista_canciones.size() > 1:
		while nuevo_index == cancion_actual_index:
			nuevo_index = randi() % lista_canciones.size()
	
	cancion_actual_index = nuevo_index
	var ruta_cancion = lista_canciones[cancion_actual_index]
	
	# Cargar y reproducir la canción
	var stream = load(ruta_cancion)
	
	if stream != null:
		reproductor_musica.stream = stream
		reproductor_musica.volume_db = linear_to_db(volumen_musica)
		reproductor_musica.play()
		
		var nombre_cancion = ruta_cancion.get_file()
		print("ManejadorMusica: Reproduciendo - " + nombre_cancion)
	else:
		print("ManejadorMusica: Error al cargar - " + ruta_cancion)

func _on_musica_finished():
	"""
	Se ejecuta cuando la música termina para reproducir la siguiente canción aleatoria
	"""
	print("ManejadorMusica: Canción terminada, cambiando a otra...")
	reproducir_siguiente_cancion()

func cambiar_volumen(nuevo_volumen: float):
	"""
	Cambia el volumen de la música
	Args:
		nuevo_volumen: Valor entre 0.0 y 1.0
	"""
	volumen_musica = clamp(nuevo_volumen, 0.0, 1.0)
	if reproductor_musica:
		reproductor_musica.volume_db = linear_to_db(volumen_musica)

func pausar_musica():
	"""
	Pausa la música
	"""
	if reproductor_musica and reproductor_musica.playing:
		reproductor_musica.stream_paused = true

func reanudar_musica():
	"""
	Reanuda la música si estaba pausada
	"""
	if reproductor_musica:
		reproductor_musica.stream_paused = false

func detener_musica():
	"""
	Detiene la música completamente
	"""
	if reproductor_musica:
		reproductor_musica.stop()

func cambiar_musica_ahora():
	"""
	Fuerza el cambio a la siguiente canción aleatoria inmediatamente
	"""
	print("ManejadorMusica: Cambiando canción manualmente...")
	detener_musica()
	reproducir_siguiente_cancion()

func agregar_cancion(ruta_cancion: String):
	"""
	Agrega una canción específica a la lista (si existe)
	Args:
		ruta_cancion: Ruta al archivo de música
	"""
	if FileAccess.file_exists(ruta_cancion) and not lista_canciones.has(ruta_cancion):
		lista_canciones.append(ruta_cancion)
		print("ManejadorMusica: Canción agregada - " + ruta_cancion.get_file())

func actualizar_lista_canciones():
	"""
	Vuelve a buscar canciones en la carpeta (útil si se añaden nuevas canciones)
	"""
	print("ManejadorMusica: Actualizando lista de canciones...")
	buscar_canciones()
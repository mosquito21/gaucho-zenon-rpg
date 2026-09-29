extends Node

## Controles temporales para probar el sistema día/noche y estrellas
## ¡Solo para testing!

var sistema_dia_noche: CicloDiaNoche

func _ready():
	print("🎮 Controles de debug cargados:")
	print("F1 = Amanecer | F2 = Mediodía | F3 = Atardecer | F4 = Medianoche")
	print("F5 = Ver estado del sistema | F6 = Arreglar referencias")
	print("F7 = Diagnosticar cielo/ambiente | F9 = Ver parámetros del sol")
	
	# Buscar el sistema día/noche
	await get_tree().process_frame
	sistema_dia_noche = encontrar_sistema_dia_noche()
	
	if sistema_dia_noche:
		print("✅ Sistema día/noche encontrado!")
		# Mostrar estado inicial
		sistema_dia_noche.debug_estado()
	else:
		print("❌ No se encontró el sistema día/noche")

func _input(event):
	if not sistema_dia_noche:
		return
		
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:  # Amanecer
				sistema_dia_noche.establecer_hora(6.0)
				print("🌅 Amanecer (6:00) - Las estrellas se ocultan")
				
			KEY_F2:  # Mediodía
				sistema_dia_noche.establecer_hora(12.0)
				print("☀️ Mediodía (12:00) - Sol al máximo")
				
			KEY_F3:  # Atardecer
				sistema_dia_noche.establecer_hora(18.0)
				print("🌇 Atardecer (18:00) - Empiezan a verse estrellas")
				
			KEY_F4:  # Medianoche
				sistema_dia_noche.establecer_hora(0.0)
				print("🌌 Medianoche (00:00) - ¡CIELO LLENO DE ESTRELLAS!")
				
			KEY_F5:  # Debug del estado
				print("=== ESTADO DEL SISTEMA ===")
				sistema_dia_noche.debug_estado()
				print("============================")
				
			KEY_F6:  # Arreglar referencias
				print("🔧 Arreglando referencias...")
				arreglar_referencias()
				
			KEY_F7:  # Diagnosticar cielo
				print("🔍 Diagnosticando cielo y ambiente...")
				diagnosticar_cielo()
				
			KEY_F9:  # Ver parámetros del sol
				print("☀️ Mostrando parámetros del DirectionalLight3D...")
				mostrar_parametros_sol()

func encontrar_sistema_dia_noche() -> CicloDiaNoche:
	var nodos = []
	buscar_recursivo(get_tree().current_scene, CicloDiaNoche, nodos)
	return nodos[0] if nodos.size() > 0 else null

func buscar_recursivo(nodo: Node, tipo: Variant, resultado: Array):
	if is_instance_of(nodo, tipo):
		resultado.append(nodo)
	for child in nodo.get_children():
		buscar_recursivo(child, tipo, resultado)

func arreglar_referencias():
	"""Busca y asigna manualmente las referencias al CicloDiaNoche"""
	
	if not sistema_dia_noche:
		print("❌ No hay sistema día/noche")
		return
	
	# Buscar DirectionalLight3D en toda la escena
	var luces = []
	buscar_recursivo(get_tree().current_scene, DirectionalLight3D, luces)
	
	if luces.size() > 0:
		sistema_dia_noche.sol = luces[0]
		print("✅ Sol asignado manualmente: ", luces[0].name)
	else:
		# Crear sol si no existe
		var sol = DirectionalLight3D.new()
		sol.name = "Sol_Debug"
		sol.light_energy = 1.0
		sol.light_color = Color.WHITE
		get_tree().current_scene.add_child(sol)
		sistema_dia_noche.sol = sol
		print("✅ Sol creado y asignado: ", sol.name)
	
	# Buscar WorldEnvironment
	var ambientes = []
	buscar_recursivo(get_tree().current_scene, WorldEnvironment, ambientes)
	
	if ambientes.size() > 0:
		sistema_dia_noche.ambiente_mundo = ambientes[0]
		print("✅ Ambiente asignado manualmente: ", ambientes[0].name)
	else:
		print("⚠️ No se encontró WorldEnvironment (opcional)")
	
	# Verificar resultado
	print("🔍 Referencias después del arreglo:")
	sistema_dia_noche.debug_estado()

func diagnosticar_cielo():
	"""Diagnostica problemas con el cielo y ambiente"""
	
	print("=== DIAGNÓSTICO DE CIELO Y AMBIENTE ===")
	
	# Buscar WorldEnvironment en la escena
	var ambientes = []
	buscar_recursivo(get_tree().current_scene, WorldEnvironment, ambientes)
	
	if ambientes.size() == 0:
		print("❌ NO HAY WorldEnvironment - ¡Aquí está el problema!")
		print("💡 Solución: Crear WorldEnvironment...")
		crear_ambiente_basico()
	else:
		var ambiente = ambientes[0] as WorldEnvironment
		print("✅ WorldEnvironment encontrado: ", ambiente.name)
		
		if not ambiente.environment:
			print("❌ WorldEnvironment SIN Environment asignado")
			print("💡 Creando Environment...")
			ambiente.environment = Environment.new()
		
		var env = ambiente.environment
		print("✅ Environment asignado")
		
		if not env.sky:
			print("❌ Environment SIN Sky asignado")  
			print("💡 Creando Sky...")
			env.sky = Sky.new()
			env.background_mode = Environment.BG_SKY
		
		print("✅ Sky asignado")
		
		if not env.sky.sky_material:
			print("❌ Sky SIN material asignado")
			print("💡 Creando ProceduralSkyMaterial...")
			env.sky.sky_material = ProceduralSkyMaterial.new()
		
		var sky_mat = env.sky.sky_material
		print("✅ Sky material: ", sky_mat.get_class())
		
		if sky_mat is ProceduralSkyMaterial:
			print("✅ ProceduralSkyMaterial - ¡PERFECTO!")
			print("🔧 Forzando colores nocturnos...")
			var mat = sky_mat as ProceduralSkyMaterial
			mat.sky_top_color = Color(0.02, 0.05, 0.1)
			mat.sky_horizon_color = Color(0.05, 0.08, 0.15)
			print("🌌 Colores nocturnos aplicados directamente")
		else:
			print("⚠️ NO es ProceduralSkyMaterial")
	
	print("======================================")

func crear_ambiente_basico():
	"""Crea un WorldEnvironment básico si no existe"""
	
	var ambiente = WorldEnvironment.new()
	ambiente.name = "Ambiente_Debug"
	
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	
	# Configurar colores nocturnos
	var sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	sky_mat.sky_top_color = Color(0.02, 0.05, 0.1)
	sky_mat.sky_horizon_color = Color(0.05, 0.08, 0.15)
	
	ambiente.environment = env
	get_tree().current_scene.add_child(ambiente)
	
	print("✅ WorldEnvironment creado: ", ambiente.name)
	
	# Reasignar al sistema día/noche
	if sistema_dia_noche:
		sistema_dia_noche.ambiente_mundo = ambiente
		print("🔗 Ambiente reasignado al sistema día/noche")
		
		# Forzar actualización inmediata
		sistema_dia_noche.actualizar_ciclo()
	else:
		print("❌ No se encontró sistema día/noche para reasignar")

func mostrar_parametros_sol():
	"""Muestra parámetros básicos del DirectionalLight3D (versión ligera)"""
	
	# Buscar DirectionalLight3D rápido
	var luces = []
	buscar_recursivo(get_tree().current_scene, DirectionalLight3D, luces)
	
	if luces.size() == 0:
		print("❌ NO HAY DirectionalLight3D")
		return
	
	var sol = luces[0] as DirectionalLight3D
	print("☀️ SOL: ", sol.name, " | Energía: ", sol.light_energy, " | Color: ", sol.light_color)
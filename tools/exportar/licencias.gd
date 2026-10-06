extends SceneTree

## Escribe las licencias que tienen que acompañar a un juego hecho con Godot: la del motor y las de
## las piezas de terceros que el motor trae adentro, más la del plugin del terreno.
##   godot --headless --path <proyecto> --script res://tools/exportar/licencias.gd -- --salida=<archivo>
## Lo corre tools/exportar/exportar.py.

func _initialize() -> void:
	var salida := ""
	for argumento in OS.get_cmdline_user_args():
		if argumento.begins_with("--salida="):
			salida = argumento.trim_prefix("--salida=")
	if salida == "":
		printerr("Falta --salida=<archivo>")
		quit(1)
		return
	var t := "LICENCIAS\n=========\n\nEl Gaucho Zenón está hecho con Godot Engine %s.\n\n" % Engine.get_version_info().string
	t += "---------------------------------------------------------------- Godot Engine\n\n"
	t += Engine.get_license_text() + "\n\n"
	t += "---------------------------------------------------------------- Plugin HTerrain (terreno)\n\n"
	t += FileAccess.get_file_as_string("res://addons/zylann.hterrain/LICENSE.md") + "\n\n"
	t += "---------------------------------------------------------------- Piezas de terceros dentro de Godot\n\n"
	for pieza: Dictionary in Engine.get_copyright_info():
		t += "%s\n" % pieza.get("name", "")
		for parte: Dictionary in pieza.get("parts", []):
			for linea in parte.get("copyright", []):
				t += "    (c) %s\n" % linea
			t += "    Licencia: %s\n" % parte.get("license", "")
		t += "\n"
	t += "---------------------------------------------------------------- Texto de cada licencia\n\n"
	var licencias := Engine.get_license_info()
	for nombre: String in licencias:
		t += "== %s ==\n\n%s\n\n" % [nombre, licencias[nombre]]
	var archivo := FileAccess.open(salida, FileAccess.WRITE)
	if archivo == null:
		printerr("No se pudo escribir %s" % salida)
		quit(1)
		return
	archivo.store_string(t)
	archivo.close()
	print("Licencias escritas en %s (%d letras)" % [salida, t.length()])
	quit(0)

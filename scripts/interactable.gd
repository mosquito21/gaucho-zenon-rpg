extends Area3D
class_name Interactable

## Cosa de la estepa con la que Zenón puede hablar o dejar un recado.
## El estado del trabajo vive en el jugador, así no se pierde al caminar.

enum Rol { PIEDRA, POSTA, HITO, FORTIN, MOJON }

@export var rol: Rol = Rol.PIEDRA
@export var interact_text := "Presioná E para inspeccionar la piedra"
## Lo que se lee al apretar E en un lugar que solo informa (por ejemplo la pulpería).
## Si queda vacío, sigue la frase de la piedra.
@export_multiline var texto_al_usar := ""


func texto_mira(jugador: Node) -> String:
	var periodo := _periodo_de(jugador)
	var recado: int = int(jugador.get("estado_recado"))
	var exploracion: int = int(jugador.get("estado_exploracion"))
	match rol:
		Rol.POSTA:
			if recado == 0:
				if periodo == "Noche" or periodo == "Crepúsculo":
					return "Presioná E para tomar el recado. De noche, seguí el humo del palo."
				if periodo == "Atardecer":
					return "Presioná E para llevar el recado. Con el sol bajo se ve el palo."
				return "Presioná E para llevar el recado al hito del humo"
			if recado == 1:
				return "Llevás el recado. El hito queda al noreste, donde sale el humo."
			return "El recado ya se entregó. El puestero te saluda."
		Rol.HITO:
			if recado == 1:
				if periodo == "Atardecer":
					return "Presioná E para dejar el recado. Llegás con luz de atardecer."
				return "Presioná E para dejar el recado en el palo"
			if recado == 2:
				return "El recado ya está en el palo."
			return "Es el palo del hito. Todavía no traés recado."
		Rol.FORTIN:
			if exploracion == 0:
				if periodo == "Noche" or periodo == "Crepúsculo":
					return "Presioná E para hablar con el centinela. De noche la seña cuesta verla."
				return "Presioná E para pedir la seña del cerro"
			if exploracion == 1:
				return "Andá al mojón del cerro, al sudoeste, y volvé."
			if exploracion == 2:
				return "Presioná E para contarle al centinela que viste el mojón"
			return "La seña del cerro ya quedó anotada en el fortín."
		Rol.MOJON:
			if exploracion == 1:
				return "Presioná E para marcar el mojón del cerro"
			if exploracion >= 2:
				return "El mojón ya está marcado. Volvé al fortín si falta."
			return "Es un mojón del cerro. El fortín todavía no te mandó."
		_:
			return interact_text


func al_interactuar(jugador: Node) -> String:
	match rol:
		Rol.POSTA:
			return str(jugador.call("tomar_recado"))
		Rol.HITO:
			return str(jugador.call("entregar_recado"))
		Rol.FORTIN:
			return str(jugador.call("hablar_en_el_fortin"))
		Rol.MOJON:
			return str(jugador.call("marcar_mojon"))
		_:
			if texto_al_usar != "":
				return texto_al_usar
			return "Es una piedra de la estepa. No guarda ningún recado."


func _periodo_de(jugador: Node) -> String:
	if jugador.has_method("periodo_del_dia"):
		return str(jugador.call("periodo_del_dia"))
	return "Día"

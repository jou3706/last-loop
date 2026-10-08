extends Node

signal objective_changed(text: String)

var current_objective := ""

func set_objective(text: String) -> void:
	if text == current_objective:
		return
	current_objective = text
	objective_changed.emit(text)
	print("[objective] changed: ", text)

func get_objective() -> String:
	return current_objective
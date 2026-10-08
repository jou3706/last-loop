extends Node3D

const INITIAL_OBJECTIVE := "Secure the inner courtyard and clear remaining guards"

func _ready() -> void:
	ObjectiveManager.set_objective(INITIAL_OBJECTIVE)
	call_deferred("_setup_victory")

func _setup_victory() -> void:
	var tz := get_node_or_null("TriggerVictory")
	if tz != null and tz.has_signal("triggered"):
		tz.triggered.connect(_on_victory)

func _on_victory(_body: Node3D) -> void:
	var overlay := get_node_or_null("VictoryOverlay")
	if overlay != null and overlay.has_method("show_victory"):
		overlay.show_victory()
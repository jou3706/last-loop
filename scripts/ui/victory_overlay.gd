extends CanvasLayer

@onready var panel: ColorRect = $Panel

func _ready() -> void:
	visible = false

func show_victory() -> void:
	visible = true
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.5)
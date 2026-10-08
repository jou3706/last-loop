extends CanvasLayer

@onready var panel: ColorRect = $Panel
@onready var replay_button: Button = $Panel/ButtonRow/ReplayButton
@onready var menu_button: Button = $Panel/ButtonRow/MenuButton

func _ready() -> void:
	visible = false
	replay_button.pressed.connect(_on_replay)
	menu_button.pressed.connect(_on_menu)

func show_victory() -> void:
	visible = true
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.5)
	AudioManager.play_victory()

func _on_replay() -> void:
	AudioManager.play_ui_click()
	get_tree().reload_current_scene()

func _on_menu() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
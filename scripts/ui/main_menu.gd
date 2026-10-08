extends Control

@onready var main_box: VBoxContainer = $CenterContainer/MainBox
@onready var level_select: Control = $LevelSelect

func _ready() -> void:
	level_select.visible = false
	$CenterContainer/MainBox/StartButton.pressed.connect(_start_campaign)
	$CenterContainer/MainBox/SelectLevelButton.pressed.connect(_show_level_select)
	$CenterContainer/MainBox/QuitButton.pressed.connect(_quit)
	$LevelSelect/Level1Button.pressed.connect(_go_level1)
	$LevelSelect/Level2Button.pressed.connect(_go_level2)
	$LevelSelect/BackButton.pressed.connect(_hide_level_select)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _start_campaign() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/level_01.tscn")

func _show_level_select() -> void:
	AudioManager.play_ui_click()
	main_box.visible = false
	level_select.visible = true

func _hide_level_select() -> void:
	AudioManager.play_ui_click()
	level_select.visible = false
	main_box.visible = true

func _go_level1() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/level_01.tscn")

func _go_level2() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/level_02.tscn")

func _quit() -> void:
	AudioManager.play_ui_click()
	get_tree().quit()
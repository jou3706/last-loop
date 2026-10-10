extends CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Panel/CenterContainer/VBox/ResumeButton.pressed.connect(_on_resume)
	$Panel/CenterContainer/VBox/RestartButton.pressed.connect(_on_restart)
	$Panel/CenterContainer/VBox/MenuButton.pressed.connect(_on_main_menu)
	$Panel/CenterContainer/VBox/QuitButton.pressed.connect(_on_quit)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()

func toggle() -> void:
	if get_tree().paused:
		resume()
	else:
		pause()

func pause() -> void:
	get_tree().paused = true
	visible = true
	$Panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func resume() -> void:
	get_tree().paused = false
	visible = false
	$Panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume() -> void:
	AudioManager.play_ui_click()
	resume()

func _on_restart() -> void:
	AudioManager.play_ui_click()
	resume()
	get_tree().reload_current_scene()

func _on_main_menu() -> void:
	AudioManager.play_ui_click()
	resume()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_quit() -> void:
	AudioManager.play_ui_click()
	get_tree().quit()
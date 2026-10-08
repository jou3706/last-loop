extends CanvasLayer

@onready var ammo_label: Label = $Control/Ammo
@onready var health_label: Label = $Control/Health
@onready var wave_label: Label = $Control/Wave
@onready var score_label: Label = $Control/Score
@onready var kills_label: Label = $Control/Kills
@onready var status_label: Label = $Control/Status
@onready var info_label: Label = $Control/Info
@onready var objective_label: Label = $Control/Objective

var _player: Node = null
var _gm: Node = null
var _info_tween: Tween

func _ready() -> void:
	call_deferred("_bind")

func _bind() -> void:
	var root = get_tree().current_scene
	_player = root.get_node_or_null("Player")
	_gm = root.get_node_or_null("GameManager")
	if _gm != null:
		if _gm.has_signal("wave_started"):
			_gm.wave_started.connect(_on_wave_started)
			_gm.wave_cleared.connect(_on_wave_cleared)
		wave_label.visible = true
		score_label.visible = true
		kills_label.visible = true
	else:
		wave_label.visible = false
		score_label.visible = false
		kills_label.visible = false

func _on_wave_started(wave: int) -> void:
	_show_info("Wave %d" % wave)

func _on_wave_cleared(wave: int) -> void:
	_show_info("Wave %d cleared!" % wave)

func _show_info(text: String) -> void:
	info_label.text = text
	info_label.visible = true
	if _info_tween and _info_tween.is_valid():
		_info_tween.kill()
	_info_tween = create_tween()
	_info_tween.tween_interval(1.5)
	_info_tween.tween_callback(func() -> void: info_label.visible = false)

func _process(_delta: float) -> void:
	var objective := ObjectiveManager.get_objective()
	if objective_label.text != "Objective: " + objective:
		objective_label.text = "Objective: " + objective
	if _player != null:
		if _player.has_method("get_ammo"):
			var a = _player.get_ammo()
			ammo_label.text = "Ammo: %d / %d" % [a.mag, a.reserve]
		if _player.has_method("get_health"):
			health_label.text = "HP: %d" % _player.get_health()
	if _gm != null:
		if _gm.has_method("get_wave"):
			wave_label.text = "Wave: %d" % _gm.get_wave()
		if _gm.has_method("get_score"):
			score_label.text = "Score: %d" % _gm.get_score()
		if _gm.has_method("get_kills"):
			kills_label.text = "Kills: %d" % _gm.get_kills()
	if _player != null and _player.has_method("is_dead") and _player.is_dead():
		status_label.visible = true
	else:
		status_label.visible = false
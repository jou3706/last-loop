extends CanvasLayer

@onready var ammo_label: Label = $Control/Ammo
@onready var health_label: Label = $Control/Health
@onready var wave_label: Label = $Control/Wave
@onready var status_label: Label = $Control/Status

var _player: Node = null
var _gm: Node = null

func _ready() -> void:
	call_deferred("_bind")

func _bind() -> void:
	var root = get_tree().current_scene
	_player = root.get_node_or_null("Player")
	_gm = root.get_node_or_null("GameManager")

func _process(_delta: float) -> void:
	if _player != null:
		if _player.has_method("get_ammo"):
			var a = _player.get_ammo()
			ammo_label.text = "Ammo: %d / %d" % [a.mag, a.reserve]
		if _player.has_method("get_health"):
			health_label.text = "HP: %d" % _player.get_health()
	if _gm != null and _gm.has_method("get_wave"):
		wave_label.text = "Wave: %d" % _gm.get_wave()
	if _player != null and _player.has_method("is_dead") and _player.is_dead():
		status_label.visible = true
	else:
		status_label.visible = false
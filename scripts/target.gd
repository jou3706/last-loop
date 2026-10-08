extends StaticBody3D

@export_category("Health")
@export var max_health := 60
@export var respawn_time := 2.5

@export_category("Movement")
## 0 = stationary target, >0 = slides that many meters to each side.
@export var move_range := 0.0
@export var move_duration := 1.6

var health: int
var _dead := false
var _start_transform: Transform3D
var _move_tween: Tween

@onready var board: MeshInstance3D = $Board

func _ready() -> void:
	health = max_health
	_start_transform = transform
	if board.material_override:
		board.material_override = board.material_override.duplicate()
	if move_range > 0.0:
		_start_move_tween()

func _start_move_tween() -> void:
	_move_tween = create_tween().set_loops()
	_move_tween.tween_property(self, "position:x", position.x + move_range, move_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(self, "position:x", position.x, move_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func take_damage(amount: int) -> void:
	if _dead:
		return
	health -= amount
	_flash()
	if health <= 0:
		_die()

func _flash() -> void:
	var mat := board.material_override as StandardMaterial3D
	if not mat:
		return
	var original := Color(0.85, 0.2, 0.15)
	mat.albedo_color = Color(6, 6, 6)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", original, 0.25)

func _die() -> void:
	_dead = true
	if _move_tween and _move_tween.is_running():
		_move_tween.pause()
	var tw := create_tween()
	tw.tween_property(self, "rotation", Vector3(-1.45, 0.0, 0.0), 0.4) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(respawn_time)
	tw.tween_callback(_reset)

func _reset() -> void:
	health = max_health
	_dead = false
	transform = _start_transform
	if _move_tween:
		_move_tween.play()
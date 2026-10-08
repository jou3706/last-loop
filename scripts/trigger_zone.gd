extends Area3D

signal triggered(body: Node3D)

@export var objective_text := ""
@export var enemy_group: PackedScene
@export var spawn_offset := Vector3.ZERO
@export var complete_level := false
@export_file("*.tscn") var next_scene := "res://scenes/level_02.tscn"
@export var one_shot := true

var _used := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if _used or body == null:
		return
	if not _is_player(body):
		return
	if objective_text != "":
		ObjectiveManager.set_objective(objective_text)
	if enemy_group:
		_spawn_group()
	if one_shot:
		_used = true
	if complete_level:
		_complete_level()
	triggered.emit(body)

func _spawn_group() -> void:
	var group := enemy_group.instantiate()
	var parent: Node = get_tree().current_scene
	parent.add_child(group)
	if group is Node3D:
		group.global_position = global_position + spawn_offset

func _complete_level() -> void:
	print("[trigger] level complete -> ", next_scene)
	get_tree().call_deferred("change_scene_to_file", next_scene)

func _is_player(body: Node3D) -> bool:
	return body is CharacterBody3D and body.has_method("take_damage")
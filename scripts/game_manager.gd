extends Node

@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@export var spawn_points: Array[NodePath] = []

var _spawn_timer: Timer
var _wave := 1
var _enemies_left := 0
var _spawn_nodes: Array[Marker3D] = []

func _ready() -> void:
	_collect_spawn_nodes()
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = 3.0
	_spawn_timer.one_shot = false
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn)
	_spawn_timer.start()
	_spawn_wave()

func _collect_spawn_nodes() -> void:
	_spawn_nodes.clear()
	var scene: Node = get_tree().current_scene
	if scene == null:
		for ch in get_tree().root.get_children():
			if ch.name == "Main":
				scene = ch
				break
	if scene != null:
		for n in scene.get_children():
			if n is Marker3D and n.name.begins_with("Spawn"):
				_spawn_nodes.append(n)
	if _spawn_nodes.is_empty():
		for p in spawn_points:
			var sp = get_node_or_null(p)
			if sp is Marker3D:
				_spawn_nodes.append(sp)

func _spawn_wave() -> void:
	_enemies_left = _wave * 3
	_spawn_timer.wait_time = max(1.5, 4.0 - _wave * 0.3)

func _on_spawn() -> void:
	if _enemies_left <= 0: return
	if _spawn_nodes.is_empty(): _collect_spawn_nodes()
	if _spawn_nodes.is_empty(): return
	var sp: Marker3D = _spawn_nodes.pick_random()
	var e = enemy_scene.instantiate()
	get_tree().current_scene.add_child(e)
	e.global_position = sp.global_position
	e.died.connect(_on_enemy_died)
	_enemies_left -= 1
	if _enemies_left <= 0:
		_wave += 1
		_spawn_wave()

func _on_enemy_died() -> void:
	pass


func get_wave() -> int:
	return _wave
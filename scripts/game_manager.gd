extends Node

@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@export var spawn_points: Array[NodePath] = []
@export var interwave_time := 2.0

var _spawn_timer: Timer
var _wave := 1
var score := 0
var kills := 0
var _remaining_to_spawn := 0
var _alive := 0
var _spawn_nodes: Array[Marker3D] = []
var _advancing := false

signal wave_started(wave: int)
signal wave_cleared(wave: int)

func _ready() -> void:
	_collect_spawn_nodes()
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = 3.0
	_spawn_timer.one_shot = false
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn)
	_spawn_timer.start()
	call_deferred("_start_wave", 1)

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

func _start_wave(w: int) -> void:
	_wave = w
	_remaining_to_spawn = _wave * 3
	_alive = 0
	_advancing = false
	_spawn_timer.wait_time = max(0.8, 3.0 - _wave * 0.2)
	wave_started.emit(_wave)

func _on_spawn() -> void:
	if _remaining_to_spawn <= 0: return
	if _spawn_nodes.is_empty(): _collect_spawn_nodes()
	if _spawn_nodes.is_empty(): return
	var sp: Marker3D = _spawn_nodes.pick_random()
	var e = enemy_scene.instantiate()
	get_tree().current_scene.add_child(e)
	e.global_position = sp.global_position
	e.setup_wave(_wave)
	e.died.connect(_on_enemy_died)
	_alive += 1
	_remaining_to_spawn -= 1

func _on_enemy_died(points: int) -> void:
	_alive = maxi(_alive - 1, 0)
	kills += 1
	score += points
	if _alive != 0 or _remaining_to_spawn != 0 or _advancing:
		return
	_advancing = true
	wave_cleared.emit(_wave)
	await get_tree().create_timer(interwave_time, false).timeout
	if is_inside_tree():
		_start_wave(_wave + 1)

func get_wave() -> int:
	return _wave

func get_score() -> int:
	return score

func get_kills() -> int:
	return kills

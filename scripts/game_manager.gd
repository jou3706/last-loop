extends Node

@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@export var spawn_points: Array[Node3D] = []

var _spawn_timer: Timer
var _wave := 1
var _enemies_left := 0

func _ready() -> void:
  _spawn_timer = Timer.new()
  _spawn_timer.wait_time = 3.0
  _spawn_timer.one_shot = false
  add_child(_spawn_timer)
  _spawn_timer.timeout.connect(_on_spawn)
  _spawn_timer.start()
  _spawn_wave()

func _spawn_wave() -> void:
  _enemies_left = _wave * 3
  _spawn_timer.wait_time = max(1.5, 4.0 - _wave * 0.3)

func _on_spawn() -> void:
  if _enemies_left <= 0: return
  if spawn_points.is_empty(): return
  var sp = spawn_points.pick_random()
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

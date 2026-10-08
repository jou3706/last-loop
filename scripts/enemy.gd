extends CharacterBody3D

@export var speed := 2.8
@export var health := 100
@export var score_value := 10
@export var detection_range := 40.0
@export var stop_range := 10.0
@export var min_range := 6.0
@export var fire_rate := 2.0
@export var shot_damage := 10
@export var gravity := 9.8

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var eyes: RayCast3D = $Eyes
@onready var muzzle: Marker3D = $Muzzle

var _target: Node3D = null
var _player_ref: Node3D = null
var _shot_cooldown := 0.0

signal died(score_value: int)

func _ready() -> void:
	nav.path_desired_distance = 0.5
	nav.target_desired_distance = 0.5
	eyes.collision_mask = 1 | 2
	call_deferred("_find_player")

func _find_player() -> void:
	var root = get_tree().current_scene
	_player_ref = root.get_node_or_null("Player")

func set_target(t: Node3D) -> void:
	_target = t

func setup_wave(wave: int) -> void:
	if wave > 1:
		health = int(health * (1.0 + 0.1 * float(wave - 1)))
		speed = speed * (1.0 + 0.05 * float(wave - 1))

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	if _player_ref == null:
		_find_player()
		return
	if health <= 0:
		return
	_shot_cooldown -= delta

	var to_player := _player_ref.global_position - global_position
	var flat_dir := Vector3(to_player.x, 0.0, to_player.z)
	var dist := flat_dir.length()
	var has_los := _has_line_of_sight()

	match _decide_motion(dist, has_los):
		&"advance":
			nav.target_position = _player_ref.global_position
			_move_to_path()
		&"retreat":
			nav.target_position = global_position - flat_dir.normalized() * 8.0
			_move_to_path()
		_:
			velocity.x = 0.0
			velocity.z = 0.0

	if dist <= detection_range and has_los and _shot_cooldown <= 0.0:
		_fire()

	_face_towards(flat_dir, dist <= detection_range)
	move_and_slide()

func _decide_motion(dist: float, has_los: bool) -> String:
	if dist > stop_range:
		return "advance"
	if dist < min_range:
		return "retreat"
	return "" if has_los else "advance"

func _move_to_path() -> void:
	if nav.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dir := (nav.get_next_path_position() - global_position)
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

func _has_line_of_sight() -> bool:
	if _player_ref == null:
		return false
	var aim := _player_ref.global_position + Vector3.UP * 1.0
	eyes.target_position = eyes.to_local(aim)
	eyes.force_raycast_update()
	return eyes.is_colliding() and eyes.get_collider() == _player_ref

func _fire() -> void:
	_shot_cooldown = 1.0 / max(fire_rate, 0.01)
	var origin := muzzle.global_position
	eyes.force_raycast_update()
	var end := origin + (muzzle.global_transform.basis * Vector3.BACK * 200.0)
	if eyes.is_colliding():
		end = eyes.get_collision_point()
		if eyes.get_collider() == _player_ref and _player_ref.has_method("take_damage"):
			_player_ref.take_damage(shot_damage)
	_spawn_tracer(origin, end)

func _face_towards(flat_dir: Vector3, active: bool) -> void:
	if not active or flat_dir.length_squared() < 0.0001:
		return
	global_rotation.y = atan2(flat_dir.x, flat_dir.z)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.6, 0.2, 1.0)
	box.material = mat
	beam.mesh = box
	get_tree().current_scene.add_child(beam)
	beam.global_position = (from + to) * 0.5
	var dir := (to - beam.global_position).normalized()
	if absf(dir.dot(Vector3.UP)) > 0.99:
		beam.look_at(to, Vector3.RIGHT)
	else:
		beam.look_at(to)
	var tw := beam.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.1)
	tw.tween_callback(beam.queue_free)

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		died.emit(score_value)
		queue_free()
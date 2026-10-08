extends CharacterBody3D

@export_category("Movement")
@export var walk_speed := 3.5
@export var sprint_speed := 5.5
@export var ads_walk_speed := 2.2
@export var jump_velocity := 4.5
@export var gravity := 9.8

@export_category("Look")
@export var mouse_sensitivity := 0.0022
@export var ads_mouse_sensitivity := 0.0014
@export var min_pitch := -1.4
@export var max_pitch := 1.4

@export_category("Camera Bob")
@export var bob_enabled := true
@export var bob_amplitude := 0.04
@export var bob_frequency := 1.8

@export_category("ADS")
@export var ads_fov := 50.0
@export var hip_fov := 90.0
@export var ads_transition_speed := 14.0

@export_category("Weapon")
@export var fire_rate := 8.0  # RPS
@export var damage := 24
@export var range := 200.0
@export var mag_size := 30
@export var reserve_ammo := 90
@export var reload_time := 1.6
@export var recoil_pitch := 0.18
@export var recoil_yaw := 0.03
@export var recoil_recovery := 8.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var muzzle_flash: GPUParticles3D = $Head/Camera3D/WeaponHolder/MuzzleFlash
@onready var muzzle_light: OmniLight3D = $Head/Camera3D/WeaponHolder/MuzzleLight

const ImpactScene := preload("res://scenes/fx/impact.tscn")

var _bob_time := 0.0
var _base_cam_pos := Vector3.ZERO
var _ads_active := false

var _current_mag := 0
var _current_reserve := 0
var _can_fire := true
var _reloading := false
var _recoil := Vector2.ZERO

func _ready() -> void:
	_base_cam_pos = camera.position
	camera.fov = hip_fov
	_current_mag = mag_size
	_current_reserve = reserve_ammo
	raycast.target_position = Vector3(0, 0, -range)
	raycast.collision_mask = 1 | 4
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := ads_mouse_sensitivity if _ads_active else mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sens, min_pitch, max_pitch)
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("aim"):
		_ads_active = true
	if event.is_action_released("aim"):
		_ads_active = false
	if event.is_action_pressed("reload") and not _reloading and _current_mag < mag_size and _current_reserve > 0:
		_start_reload()

func _physics_process(delta: float) -> void:
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= gravity * delta

	var base_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var speed := ads_walk_speed if _ads_active else base_speed
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

	var target_fov := ads_fov if _ads_active else hip_fov
	camera.fov = lerpf(camera.fov, target_fov, ads_transition_speed * delta)

	_update_bob(delta, input_dir, speed)
	_update_recoil(delta)

	if Input.is_action_pressed("fire"):
		_try_fire()

func _try_fire() -> void:
	if not _can_fire or _reloading:
		return
	if _current_mag <= 0:
		return
	_fire()

func _fire() -> void:
	_current_mag -= 1
	var start := muzzle_flash.global_position
	var end := raycast.to_global(raycast.target_position)
	if raycast and raycast.is_colliding():
		end = raycast.get_collision_point()
		var col := raycast.get_collider()
		if col and col.has_method("take_damage"):
			col.take_damage(damage)
		_spawn_impact(end, raycast.get_collision_normal())
	_spawn_trail(start, end)
	_flash_muzzle()

	_recoil.y += recoil_pitch
	_recoil.x += randf_range(-recoil_yaw, recoil_yaw)
	head.rotation.x -= recoil_pitch * 0.01
	head.rotation.y += randf_range(-recoil_yaw, recoil_yaw) * 0.01

	_can_fire = false
	get_tree().create_timer(1.0 / max(fire_rate, 0.01), false).timeout.connect(_reset_fire, CONNECT_ONE_SHOT)

func _reset_fire() -> void:
	_can_fire = true

func _flash_muzzle() -> void:
	muzzle_flash.restart()
	muzzle_light.light_energy = 6.0
	var tw := create_tween()
	tw.tween_property(muzzle_light, "light_energy", 0.0, 0.06)

func _spawn_trail(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.55, 1.0)
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
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(beam.queue_free)

func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var fx := ImpactScene.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.global_position = pos
	fx.setup(normal)

func _start_reload() -> void:
	if _reloading:
		return
	_reloading = true
	get_tree().create_timer(reload_time, false).timeout.connect(_finish_reload, CONNECT_ONE_SHOT)

func _finish_reload() -> void:
	var needed: int = mag_size - _current_mag
	var take: int = min(needed, _current_reserve)
	if take > 0:
		_current_reserve -= take
		_current_mag += take
	_reloading = false

func _update_recoil(delta: float) -> void:
	_recoil = _recoil.lerp(Vector2.ZERO, recoil_recovery * delta)
	if abs(_recoil.y) > 0.0001 or abs(_recoil.x) > 0.0001:
		head.rotation.x = clampf(head.rotation.x - _recoil.y * delta, min_pitch, max_pitch)
		head.rotation.y += _recoil.x * delta
		_recoil.y *= 0.9
		_recoil.x *= 0.9

func _update_bob(delta: float, input_dir: Vector2, speed: float) -> void:
	if not bob_enabled or _ads_active:
		_bob_time = 0.0
		camera.position = camera.position.lerp(_base_cam_pos, 12.0 * delta)
		return
	var moving := is_on_floor() and input_dir != Vector2.ZERO
	if moving:
		_bob_time += delta * (speed / walk_speed)
		var phase := _bob_time * TAU * bob_frequency
		camera.position.y = lerpf(camera.position.y, _base_cam_pos.y + sin(phase) * bob_amplitude, 10.0 * delta)
		camera.position.x = lerpf(camera.position.x, _base_cam_pos.x + cos(phase * 0.5) * bob_amplitude * 0.6, 10.0 * delta)
	else:
		_bob_time = 0.0
		camera.position = camera.position.lerp(_base_cam_pos, 10.0 * delta)


var health := 100

func take_damage(amount: int) -> void:
	health = max(0, health - amount)

func get_health() -> int:
	return health

func get_ammo() -> Dictionary:
	return {"mag": _current_mag, "reserve": _current_reserve}

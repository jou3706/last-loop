extends CharacterBody3D

@export_category("Movement")
@export var walk_speed := 3.5
@export var sprint_speed := 8.0
@export var ads_walk_speed := 2.2
@export var jump_velocity := 4.5
@export var gravity := 9.8

@export_category("Health")
@export var max_health := 100
@export var respawn_delay := 2.0
@export var respawn_iframes := 1.5

@export_category("Look")
@export var mouse_sensitivity := 0.0022
@export var ads_mouse_sensitivity := 0.0014
@export var min_pitch := -1.4
@export var max_pitch := 1.4

@export_category("Camera Bob")
@export var bob_enabled := true
@export var bob_amplitude := 0.04
@export var bob_frequency := 1.8
@export var sprint_bob_multiplier := 1.6

@export_category("FOV")
@export var hip_fov := 75.0
@export var ads_fov := 50.0
@export var sprint_fov := 90.0
@export var fov_transition_time := 0.25

@export_category("Crouch")
@export var crouch_speed := 2.0
@export var crouch_height := 0.9
@export var crouch_camera_height := 0.8
@export var crouch_transition_time := 0.18

@export_category("Weapon")
@export var fire_rate := 8.0  # RPS
@export var damage := 24
@export var range := 200.0
@export var ray_zero_parallax := 20.0
@export var mag_size := 30
@export var reserve_ammo := 90
@export var reload_time := 1.6
@export var recoil_pitch := 0.18
@export var recoil_yaw := 0.03
@export var recoil_recovery := 8.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var muzzle: Marker3D = $Head/Camera3D/WeaponHolder/Muzzle
@onready var raycast: RayCast3D = $Head/Camera3D/WeaponHolder/Muzzle/RayCast3D
@onready var muzzle_flash: GPUParticles3D = $Head/Camera3D/WeaponHolder/Muzzle/MuzzleFlash
@onready var muzzle_light: OmniLight3D = $Head/Camera3D/WeaponHolder/Muzzle/MuzzleLight
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

const ImpactScene := preload("res://scenes/fx/impact.tscn")

var _bob_time := 0.0
var _base_cam_pos := Vector3.ZERO
var _base_head_pos := Vector3.ZERO
var _ads_active := false
var _crouching := false
var _was_sprinting := false
var _was_crouching := false
var _sprint_held := false
var _crouch_held := false
var _fov_target := 0.0
var _fov_tween: Tween
var _crouch_tween: Tween

var _current_mag := 0
var _current_reserve := 0
var _can_fire := true
var _reloading := false
var _recoil := Vector2.ZERO
var _dead := false
var _iframes_left := 0.0
var _start_global := Vector3.ZERO
var _respawn_timer: Timer
var _last_bob_sin := 0.0
var health := 0

func _ready() -> void:
	floor_snap_length = 0.2
	up_direction = Vector3.UP
	_base_cam_pos = camera.position
	_base_head_pos = head.position
	camera.fov = hip_fov
	_fov_target = hip_fov
	_current_mag = mag_size
	_current_reserve = reserve_ammo
	_start_global = global_position
	health = max_health
	_respawn_timer = Timer.new()
	_respawn_timer.one_shot = true
	add_child(_respawn_timer)
	_respawn_timer.timeout.connect(_respawn)
	_align_muzzle_ray()
	raycast.collision_mask = 1 | 4
	_ensure_input_actions()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_window().grab_focus()
	print("[player] ready - script loaded, mouse captured")

func _ensure_input_actions() -> void:
	var sprint_key := InputEventKey.new()
	sprint_key.physical_keycode = Key.KEY_SHIFT
	if not InputMap.has_action("sprint"):
		InputMap.add_action("sprint")
	if not InputMap.action_has_event("sprint", sprint_key):
		InputMap.action_add_event("sprint", sprint_key)
	var crouch_key := InputEventKey.new()
	crouch_key.physical_keycode = Key.KEY_CTRL
	if not InputMap.has_action("crouch"):
		InputMap.add_action("crouch")
	if not InputMap.action_has_event("crouch", crouch_key):
		InputMap.action_add_event("crouch", crouch_key)

func _align_muzzle_ray() -> void:
	var aim_point := camera.global_position - camera.global_transform.basis.z * ray_zero_parallax
	raycast.target_position = raycast.to_local(aim_point).normalized() * range

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.physical_keycode == Key.KEY_SHIFT:
			_sprint_held = event.pressed
		elif event.physical_keycode == Key.KEY_CTRL:
			_crouch_held = event.pressed
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := ads_mouse_sensitivity if _ads_active else mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sens, min_pitch, max_pitch)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("aim"):
		_ads_active = true
	if event.is_action_released("aim"):
		_ads_active = false
	if event.is_action_pressed("reload") and not _reloading and _current_mag < mag_size and _current_reserve > 0:
		_start_reload()

func _physics_process(delta: float) -> void:
	_iframes_left = maxf(_iframes_left - delta, 0.0)
	if _dead:
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			velocity.y = 0.0
		move_and_slide()
		return
	_update_crouch()
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= gravity * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := not _crouching and (_sprint_held or Input.is_physical_key_pressed(Key.KEY_SHIFT) or Input.is_action_pressed("sprint")) and input_dir != Vector2.ZERO
	var base_speed := sprint_speed if sprinting else walk_speed
	var speed := crouch_speed if _crouching else (ads_walk_speed if _ads_active else base_speed)
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

	_set_fov_target(ads_fov if _ads_active else (sprint_fov if sprinting else hip_fov))

	_update_bob(delta, input_dir, speed, sprinting)
	_update_recoil(delta)

	if sprinting != _was_sprinting:
		print("Sprinting: ", sprinting)
		_was_sprinting = sprinting
	if _crouching != _was_crouching:
		print("Crouching: ", _crouching)
		_was_crouching = _crouching

	if Input.is_action_pressed("fire"):
		_try_fire()

func _try_fire() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if _current_mag <= 0:
		if _current_reserve > 0 and not _reloading:
			_start_reload()
		return
	if not _can_fire or _reloading:
		return
	_fire()

func _fire() -> void:
	_current_mag -= 1
	var start := muzzle.global_position
	var end := raycast.to_global(raycast.target_position)
	if raycast and raycast.is_colliding():
		end = raycast.get_collision_point()
		var col := raycast.get_collider()
		if col and col.has_method("take_damage"):
			col.take_damage(damage)
		_spawn_impact(col, end, raycast.get_collision_normal())
	_spawn_trail(start, end)
	_flash_muzzle()

	_recoil.y += recoil_pitch
	_recoil.x += randf_range(-recoil_yaw, recoil_yaw)
	head.rotation.x -= recoil_pitch * 0.01
	head.rotation.y += randf_range(-recoil_yaw, recoil_yaw) * 0.01

	_can_fire = false
	get_tree().create_timer(1.0 / max(fire_rate, 0.01), false).timeout.connect(_reset_fire, CONNECT_ONE_SHOT)
	AudioManager.play_gunshot()

func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(head.global_position, head.global_position + Vector3.UP * 1.2, 1)
	return space.intersect_ray(q).is_empty()

func _set_fov_target(target: float) -> void:
	if target == _fov_target:
		return
	_fov_target = target
	if _fov_tween and _fov_tween.is_valid():
		_fov_tween.kill()
	_fov_tween = create_tween()
	_fov_tween.set_trans(Tween.TRANS_QUART)
	_fov_tween.set_ease(Tween.EASE_OUT)
	_fov_tween.tween_property(camera, "fov", target, fov_transition_time)

func _update_crouch() -> void:
	var want_crouch := _crouch_held or Input.is_physical_key_pressed(Key.KEY_CTRL) or Input.is_action_pressed("crouch")
	if not want_crouch and not _can_stand():
		want_crouch = true
	var new_crouch := want_crouch and is_on_floor()
	if new_crouch != _crouching:
		_crouching = new_crouch
		_animate_crouch()

func _animate_crouch() -> void:
	if _crouch_tween and _crouch_tween.is_valid():
		_crouch_tween.kill()
	_crouch_tween = create_tween()
	_crouch_tween.set_trans(Tween.TRANS_QUART)
	_crouch_tween.set_ease(Tween.EASE_OUT)
	var shape := collision_shape.shape as CapsuleShape3D
	if _crouching:
		_crouch_tween.tween_property(head, "position:y", crouch_camera_height, crouch_transition_time)
		if shape:
			_crouch_tween.parallel().tween_property(shape, "height", crouch_height, crouch_transition_time)
			_crouch_tween.parallel().tween_property(collision_shape, "position:y", crouch_height * 0.5, crouch_transition_time)
	else:
		_crouch_tween.tween_property(head, "position:y", _base_head_pos.y, crouch_transition_time)
		if shape:
			_crouch_tween.parallel().tween_property(shape, "height", 1.8, crouch_transition_time)
			_crouch_tween.parallel().tween_property(collision_shape, "position:y", 0.9, crouch_transition_time)

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

func _spawn_impact(parent_node: Node, hit_pos: Vector3, normal: Vector3) -> void:
	var fx := ImpactScene.instantiate()
	var parent: Node = get_tree().current_scene
	if parent_node is Node3D and (parent_node as Node).is_inside_tree():
		parent = parent_node
	parent.add_child(fx)
	fx.global_position = hit_pos
	fx.setup(normal)

func _start_reload() -> void:
	if _reloading:
		return
	_reloading = true
	AudioManager.play_reload()
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

func _update_bob(delta: float, input_dir: Vector2, speed: float, sprinting: bool) -> void:
	if not bob_enabled or _ads_active or _crouching:
		_bob_time = 0.0
		camera.position = camera.position.lerp(_base_cam_pos, 12.0 * delta)
		return
	var moving := is_on_floor() and input_dir != Vector2.ZERO
	if moving:
		var freq := bob_frequency * (sprint_bob_multiplier if sprinting else 1.0)
		_bob_time += delta * (speed / walk_speed)
		var phase := _bob_time * TAU * freq
		camera.position.y = lerpf(camera.position.y, _base_cam_pos.y + sin(phase) * bob_amplitude, 10.0 * delta)
		camera.position.x = lerpf(camera.position.x, _base_cam_pos.x + cos(phase * 0.5) * bob_amplitude * 0.6, 10.0 * delta)
		var bob_sin := sin(phase)
		if _last_bob_sin >= 0.0 and bob_sin < 0.0:
			AudioManager.play_footstep()
		_last_bob_sin = bob_sin
	else:
		_bob_time = 0.0
		_last_bob_sin = 0.0
		camera.position = camera.position.lerp(_base_cam_pos, 10.0 * delta)

func take_damage(amount: int) -> void:
	if _dead or _iframes_left > 0.0:
		return
	health = max(0, health - amount)
	if health <= 0:
		_die()

func is_dead() -> bool:
	return _dead

func _die() -> void:
	if _dead:
		return
	_dead = true
	print("[player] died")
	_respawn_timer.start(respawn_delay)

func _respawn() -> void:
	global_position = _start_global
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	head.rotation.x = 0.0
	health = max_health
	_dead = false
	_iframes_left = respawn_iframes
	print("[player] respawned")

func get_health() -> int:
	return health

func get_ammo() -> Dictionary:
	return {"mag": _current_mag, "reserve": _current_reserve}

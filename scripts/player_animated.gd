extends CharacterBody3D

## Player animated rig controller.
## Third-person character with a procedural skeleton (Mixamo clips):
## - WASD camera-relative locomotion, Shift sprint, Space jump.
## - RMB/aim action enters the Aiming blend space (slower walk).
## - Ctrl/crouch action enters the Crouching blend space (crouched speed).
## - M1/fire plays the Firing_Rifle one-shot on top of the current state.
## - R/reload plays the Reloading one-shot and blocks firing while active.
## Firing and reloading are AnimationNodeOneShot states; the script hands the
## state machine back to the locomotion state when the clip finishes.

@export var walk_speed := 3.2
@export var run_speed := 6.5
@export var crouch_speed := 1.8
@export var aim_speed_factor := 0.65
@export var accel := 12.0
@export var decel := 16.0
@export var jump_velocity := 8.0
@export var gravity := 20.0
@export var turn_speed := 8.0

@onready var _tree: AnimationTree = $AnimationTree
@onready var _ap: AnimationPlayer = $AnimationPlayer

var _current_speed := 0.0
var _aiming := false
var _crouching := false
var _reloading := false
var _exit_at_ms := 0
var _prev_state: StringName = &"Locomotion"

func _ready() -> void:
	_tree.process_callback = AnimationTree.ANIMATION_PROCESS_PHYSICS
	set_locomotion(0.0, 0.0)

func _physics_process(delta: float) -> void:
	_handle_actions()
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		do_jump()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := Input.is_action_pressed("sprint") and input_dir != Vector2.ZERO and not _crouching

	var cam := _camera()
	var fwd := _forwards(cam)
	var right := _rights(cam)
	var desired := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		desired = (fwd * -input_dir.y + right * input_dir.x).normalized()

	var top_speed := walk_speed
	if _crouching:
		top_speed = crouch_speed
	elif sprinting:
		top_speed = run_speed
	elif _aiming:
		top_speed = walk_speed * aim_speed_factor

	var target_vel := desired * top_speed
	var rate := accel if desired != Vector3.ZERO else decel
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)

	move_and_slide()

	_face_camera(fwd, delta)

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var horiz_speed := horiz.length()
	var dir_deg := 0.0
	if horiz_speed > 0.05:
		dir_deg = rad_to_deg(atan2(horiz.dot(right), horiz.dot(fwd)))
	set_locomotion(dir_deg, horiz_speed)
	_current_speed = horiz_speed

	_update_action_exit()

## Reads and applies the toggle/hold actions each physics tick.
func _handle_actions() -> void:
	var crouch_now := Input.is_action_pressed("crouch")
	if crouch_now != _crouching:
		set_crouching(crouch_now)
	var aim_now := Input.is_action_pressed("aim")
	if aim_now != _aiming:
		set_aiming(aim_now)
	if Input.is_action_just_pressed("fire"):
		try_fire()
	if Input.is_action_just_pressed("reload"):
		try_reload()
	_travel_pose()

## Steers the state machine back to the locomotion family once the
## Firing/Reloading one-shot clip has run for long enough (guaranteed exit even
## if the one-shot does not auto-advance inside a BlendTree state).
func _update_action_exit() -> void:
	var cur := _current_state()
	if cur == &"Fire" or cur == &"Reload":
		if Time.get_ticks_msec() >= _exit_at_ms:
			_pb().travel("Locomotion")
	if _reloading and _prev_state == &"Reload" and cur != &"Reload":
		_reloading = false
	_prev_state = cur

func _camera() -> Camera3D:
	return get_viewport().get_camera_3d()

func _forwards(cam: Camera3D) -> Vector3:
	if cam == null:
		return -global_transform.basis.z
	return -cam.global_transform.basis.z

func _rights(cam: Camera3D) -> Vector3:
	if cam == null:
		return global_transform.basis.x
	return cam.global_transform.basis.x

func _face_camera(fwd: Vector3, delta: float) -> void:
	if Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back") \
		or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"):
		var yaw := atan2(-fwd.x, -fwd.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * turn_speed, 0.0, 1.0))

func _pb() -> AnimationNodeStateMachinePlayback:
	return _tree.get("parameters/playback")

## Makes sure the state machine is playing (starts at Locomotion if not initialised yet).
func _ensure_initialized() -> void:
	var pb := _pb()
	if pb != null and pb.get_current_node() == "Start":
		pb.start("Locomotion")

func _current_state() -> StringName:
	var pb := _pb()
	if pb == null:
		return &"Locomotion"
	var s: StringName = pb.get_current_node()
	if s == &"" or s == &"Start":
		return &"Locomotion"
	return s

## dir_deg: movement direction in degrees (-180..180, 0 = forward).
## speed: current horizontal speed in m/s; mapped to the active blend space.
func set_locomotion(dir_deg: float, speed: float) -> void:
	_ensure_initialized()
	var cur := _current_state()
	if cur == &"Crouching":
		var fy := clampf(speed / maxf(crouch_speed, 0.01), 0.0, 1.5)
		_tree.set("parameters/Crouching/blend_position", Vector2(dir_deg, fy * 400.0))
	elif cur == &"Aiming":
		var ay := clampf(speed / maxf(walk_speed * aim_speed_factor, 0.01), 0.0, 1.5)
		_tree.set("parameters/Aiming/blend_position", Vector2(dir_deg, ay * 400.0))
	else:
		var ly := clampf(speed / run_speed, 0.0, 1.0) * 600.0
		_tree.set("parameters/Locomotion/blend_position", Vector2(dir_deg, ly))

func _travel_pose() -> void:
	var cur := _current_state()
	if cur == &"Fire" or cur == &"Reload" or cur == &"Rifle_Jump":
		return
	var target: StringName = &"Locomotion"
	if _crouching:
		target = &"Crouching"
	elif _aiming:
		target = &"Aiming"
	if cur != target:
		_pb().travel(String(target))

func set_aiming(on: bool) -> void:
	_ensure_initialized()
	_aiming = on
	_travel_pose()

func set_crouching(on: bool) -> void:
	_ensure_initialized()
	_crouching = on
	_travel_pose()

func is_aiming() -> bool:
	return _aiming

func is_crouching() -> bool:
	return _crouching

## Plays the Firing_Rifle one-shot on top of the current locomotion state.
## Returns false if a reload or another firing anim is running.
func try_fire() -> bool:
	_ensure_initialized()
	if _reloading or _current_state() == &"Fire":
		return false
	_pb().travel("Fire")
	_tree.set("parameters/Fire/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
	_tree.set("parameters/Fire/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_exit_at_ms = Time.get_ticks_msec() + _clip_ms("Firing_Rifle") + 200
	_sfx("play_gunshot")
	return true

## Plays the Reloading one-shot and blocks firing while it runs.
func try_reload() -> bool:
	_ensure_initialized()
	if _reloading or _current_state() == &"Reload":
		return false
	_reloading = true
	_pb().travel("Reload")
	_tree.set("parameters/Reload/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE)
	_tree.set("parameters/Reload/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_exit_at_ms = Time.get_ticks_msec() + _clip_ms("Reloading") + 250
	_sfx("play_reload")
	return true

func is_reloading() -> bool:
	return _reloading

func do_jump() -> void:
	_ensure_initialized()
	var pb := _pb()
	if pb.get_current_node() != "Rifle_Jump":
		pb.travel("Rifle_Jump")

func is_jumping() -> bool:
	_ensure_initialized()
	var pb := _pb()
	return pb.get_current_node() == "Rifle_Jump"

func _clip_ms(name: String) -> int:
	var a: Animation = _ap.get_animation(name)
	if a == null:
		return 800
	return int(a.length * 1000.0)

func _sfx(method: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method(method):
		am.call(method)
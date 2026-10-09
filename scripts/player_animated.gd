extends CharacterBody3D

## Player animated rig controller (AnimationPlayer-driven).
## Third-person character with a procedural skeleton (Mixamo clips):
## - WASD camera-relative locomotion; the body rotates to face the movement
##   direction (smoothly) and plays the matching clip (Rifle_Walk / Rifle_Run,
##   directional walk variants, crouch/aim clips).
## - Shift sprint, Space jump (Rifle_Jump).
## - RMB/aim action prefers aim-walk clips; Ctrl/crouch prefers crouch clips.
## - M1/fire plays the Firing_Rifle one-shot on top of the current clip.
## - R/reload plays the Reloading one-shot and blocks firing while active.
## Reuses the 41 prepared animation clips stored on the AnimationPlayer's default
## library.
##
## Animation is played through the AnimationPlayer directly instead of an
## AnimationTree: this engine build (Godot 4.7.2) does not evaluate AnimationTree
## graphs at runtime, so a lightweight script picks the best base clip each frame
## and layers Firing/Reloading one-shots over it with short crossfades, resuming
## the base clip seamlessly on completion.

@export var walk_speed := 3.2
@export var run_speed := 6.5
@export var crouch_speed := 1.8
@export var aim_speed_factor := 0.65
@export var accel := 12.0
@export var decel := 16.0
@export var jump_velocity := 8.0
@export var gravity := 20.0
@export var turn_speed := 8.0

const C_FIRE := &"Firing_Rifle"
const C_RELOAD := &"Reloading"
const C_JUMP := &"Rifle_Jump"
const C_IDLE := &"Rifle_Idle"
const C_IDLE_AIM := &"Rifle_Aiming_Idle"
const C_IDLE_CROUCH := &"Idle_Crouching"
const C_WALK_F := &"Rifle_Walk"
const C_RUN_F := &"Rifle_Run"
const C_WALK_B := &"Backwards_Rifle_Walk"
const C_RUN_B := &"Run_Backwards"
const C_STRAFE := &"Strafing"
const C_WALK_FL := &"Walk_Forward_Left"
const C_WALK_FR := &"Walk_Forward_Right"
const C_CROUCH_F := &"Rifle_Crouch_Idle_To_Walk"
const C_CROUCH_L := &"Walk_Crouching_Left"
const C_CROUCH_R := &"Walk_Crouching_Right"

const BASE_CLIPS: Array = [
	C_IDLE, C_IDLE_AIM, C_IDLE_CROUCH, C_WALK_F, C_RUN_F, C_WALK_B, C_RUN_B,
	C_STRAFE, C_WALK_FL, C_WALK_FR, C_CROUCH_F, C_CROUCH_L, C_CROUCH_R, C_JUMP,
]

@onready var _ap: AnimationPlayer = $AnimationPlayer

var _current_speed := 0.0
var _aiming := false
var _crouching := false
var _reloading := false

var _base_clip := C_IDLE
var _oneshot_active := false
var _oneshot_name := &""
var _resume_clip := C_IDLE
var _resume_pos := 0.0
var _exit_at_ms := 0

func _ready() -> void:
	for c in BASE_CLIPS:
		var a: Animation = _ap.get_animation(c)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
	_ap.animation_finished.connect(_on_animation_finished)
	_apply_base_clip(C_IDLE, 0.0, -1.0)

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

	var top_speed := 0.0
	if not input_dir.is_zero_approx():
		if sprinting: top_speed = run_speed
		else: top_speed = walk_speed
	else:
		top_speed = 0.0
	if _crouching and top_speed > 0.0: top_speed = crouch_speed
	elif _aiming and top_speed > 0.0: top_speed = walk_speed * aim_speed_factor
	var target_vel := desired * top_speed
	var rate := accel if desired != Vector3.ZERO else decel
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)

	# Face the actual movement direction so the character turns towards where it
	# is being driven by WASD (smoothly, via turn_speed).
	_face_motion(desired, delta)

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var horiz_speed := horiz.length()
	var dir_deg := 0.0
	if horiz_speed > 0.05:
		# Direction of travel expressed in the character's own facing space, so
		# the clip selection matches what the (rotating) body is actually doing.
		var local := global_transform.basis.inverse() * horiz
		dir_deg = rad_to_deg(atan2(local.x, -local.z))
	set_locomotion(dir_deg, horiz_speed)
	_current_speed = horiz_speed

	_check_oneshot_exit()

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

## Picks the base clip from the current state (fell/moving direction/speed) and
## switches to it with a short crossfade when it differs from what is playing.
## While a one-shot is running only the *next* base clip is remembered so that it
## resumes cleanly when the one-shot ends.
func _update_base_pose(dir_deg: float, speed: float) -> void:
	if _oneshot_active:
		_base_clip = _target_clip(dir_deg, speed)
		return
	var target := _target_clip(dir_deg, speed)
	if target == _base_clip and _ap.is_playing():
		return
	_apply_base_clip(target, 0.15, -1.0)

func _target_clip(dir_deg: float, speed: float) -> StringName:
	if not is_on_floor():
		return C_JUMP
	if _crouching:
		if speed < 0.35:
			return C_IDLE_CROUCH
		if absf(dir_deg) <= 45.0 or absf(dir_deg) > 135.0:
			return C_CROUCH_F
		return C_CROUCH_R if dir_deg > 0.0 else C_CROUCH_L

	if _aiming and speed < 0.35:
		return C_IDLE_AIM
	elif input_dir.is_zero_approx() or speed < 0.25:
		return C_IDLE
	var running := sprinting
	if dir_deg <= 45.0:
		return C_RUN_F if running else C_WALK_F
	if dir_deg <= 90.0:
		return C_RUN_F if running else C_WALK_FR
	return C_RUN_B if running else C_WALK_B

## Plays the base clip, optionally seeking to a position while crossfading.
func _apply_base_clip(clip: StringName, blend: float, seek_pos: float) -> void:
	_base_clip = clip
	_ap.play(clip, blend)
	if seek_pos >= 0.0:
		var a: Animation = _ap.get_animation(clip)
		var end := a.length if a != null else 0.0
		_ap.seek(minf(seek_pos, maxf(0.0, end)), true)

## Starts a one-shot over the current base clip. Cancels any running one-shot
## (matching the original state machine, where a new action travels away from the
## previous Fire/Reload state). Returns false when blocked.
func _begin_oneshot(name: StringName) -> bool:
	if _oneshot_active and _oneshot_name == name:
		return false
	if _oneshot_active:
		_on_animation_finished(_oneshot_name)
	_resume_clip = _base_clip
	_resume_pos = _ap.current_animation_position
	_oneshot_active = true
	_oneshot_name = name
	_exit_at_ms = Time.get_ticks_msec() + _clip_ms(String(name)) + 150
	_ap.play(name)
	return true

func _check_oneshot_exit() -> void:
	if _oneshot_active and Time.get_ticks_msec() >= _exit_at_ms:
		_on_animation_finished(_oneshot_name)

func _on_animation_finished(anim_name: StringName) -> void:
	if not _oneshot_active or anim_name != _oneshot_name:
		return
	_oneshot_active = false
	if _reloading and anim_name == C_RELOAD:
		_reloading = false
	_apply_base_clip(_base_clip, 0.12, _resume_pos)

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

func _face_motion(desired: Vector3, delta: float) -> void:
	if desired != Vector3.ZERO:
		var yaw := atan2(-desired.x, -desired.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * turn_speed, 0.0, 1.0))

## dir_deg: movement direction in degrees (-180..180, 0 = forward).
## speed: current horizontal speed in m/s.
func set_locomotion(dir_deg: float, speed: float) -> void:
	_update_base_pose(dir_deg, speed)

func set_aiming(on: bool) -> void:
	_aiming = on
	if not _oneshot_active:
		_update_base_pose(0.0, _current_speed)

func set_crouching(on: bool) -> void:
	_crouching = on
	if not _oneshot_active:
		_update_base_pose(0.0, _current_speed)

func is_aiming() -> bool:
	return _aiming

func is_crouching() -> bool:
	return _crouching

## Plays the Firing_Rifle one-shot on top of the current base clip.
## Returns false if a reload or another firing anim is running.
func try_fire() -> bool:
	if _reloading:
		return false
	if not _begin_oneshot(C_FIRE):
		return false
	_sfx("play_gunshot")
	return true

## Plays the Reloading one-shot and blocks firing while it runs.
func try_reload() -> bool:
	if _reloading:
		return false
	_reloading = true
	if not _begin_oneshot(C_RELOAD):
		_reloading = false
		return false
	_sfx("play_reload")
	return true

func is_reloading() -> bool:
	return _reloading

func do_jump() -> void:
	if _oneshot_active:
		_on_animation_finished(_oneshot_name)
	_apply_base_clip(C_JUMP, 0.15, -1.0)

func is_jumping() -> bool:
	return not is_on_floor()

func _clip_ms(name: String) -> int:
	var a: Animation = _ap.get_animation(name)
	if a == null:
		return 800
	return int(a.length * 1000.0)

func _sfx(method: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method(method):
		am.call(method)
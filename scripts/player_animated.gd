extends CharacterBody3D

## Third-person shooter controller (CoD-style).
## Body faces the camera yaw. WASD is camera-relative (forward / strafe).
## Mixamo clips drive the skeleton in-place; hip XZ root motion is stripped
## every frame so the rifle stays in the hands instead of sliding behind.

@export var walk_speed := 3.6
@export var run_speed := 6.8
@export var crouch_speed := 1.8
@export var aim_speed_factor := 0.55
@export var accel := 14.0
@export var decel := 18.0
@export var jump_velocity := 6.2
@export var gravity := 22.0
@export var turn_speed := 12.0
@export var mouse_sensitivity := 0.0024
@export var ads_mouse_sensitivity := 0.0015
@export var min_pitch := -0.7
@export var max_pitch := 0.5
@export var fire_rate := 8.0
@export var damage := 24
@export var mag_size := 30
@export var reserve_ammo := 90
@export var hip_fov := 70.0
@export var ads_fov := 50.0
@export var ads_spring_length := 1.6
@export var hip_spring_length := 2.7

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

const BASE_CLIPS: Array[StringName] = [
	C_IDLE, C_IDLE_AIM, C_IDLE_CROUCH, C_WALK_F, C_RUN_F, C_WALK_B, C_RUN_B,
	C_STRAFE, C_WALK_FL, C_WALK_FR, C_CROUCH_F, C_CROUCH_L, C_CROUCH_R,
]

const ImpactScene := preload("res://scenes/fx/impact.tscn")

@onready var _ap: AnimationPlayer = $AnimationPlayer
@onready var _spring: SpringArm3D = $SpringArm3D
@onready var _cam: Camera3D = $SpringArm3D/Camera3D
@onready var _skel: Skeleton3D = $Skeleton3D
@onready var _rifle: MeshInstance3D = $Skeleton3D/RifleAttach/RifleMesh

var _hip_idx := -1
var _hip_rest_pos := Vector3.ZERO
var _current_speed := 0.0
var _aiming := false
var _crouching := false
var _sprinting := false
var _reloading := false
var _jumping := false
var _base_clip := C_IDLE
var _oneshot_active := false
var _oneshot_name := &""
var _resume_clip := C_IDLE
var _resume_pos := 0.0
var _exit_at_ms := 0
var _cam_yaw := 0.0
var _cam_pitch := -0.12
var _can_fire := true
var _current_mag := 30
var _current_reserve := 90
var _muzzle: Marker3D
var _muzzle_light: OmniLight3D
var health := 100

func _ready() -> void:
	floor_snap_length = 0.2
	up_direction = Vector3.UP
	collision_layer = 2
	collision_mask = 1
	_current_mag = mag_size
	_current_reserve = reserve_ammo
	if has_node("AnimationTree"):
		$AnimationTree.active = false
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_hip_idx = _skel.find_bone("mixamorig_Hips")
	if _hip_idx >= 0:
		_hip_rest_pos = _skel.get_bone_rest(_hip_idx).origin
	_setup_rifle_grip()
	for c in BASE_CLIPS:
		var a: Animation = _ap.get_animation(c)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
	for oneshot in [C_JUMP, C_FIRE, C_RELOAD]:
		var oa: Animation = _ap.get_animation(oneshot)
		if oa != null:
			oa.loop_mode = Animation.LOOP_NONE
	_ap.animation_finished.connect(_on_animation_finished)
	_apply_base_clip(C_IDLE, 0.0, -1.0)
	_cam_yaw = rotation.y
	_cam.current = true
	_cam.fov = hip_fov
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_rifle_grip() -> void:
	# Mixamo RightHand: +Y along the bone. Rifle mesh barrel is -Z.
	_rifle.position = Vector3(0.03, 0.13, 0.02)
	_rifle.rotation_degrees = Vector3(0.0, 90.0, -90.0)
	_muzzle = _rifle.get_node_or_null("Muzzle") as Marker3D
	if _muzzle == null:
		_muzzle = Marker3D.new()
		_muzzle.name = "Muzzle"
		_rifle.add_child(_muzzle)
	_muzzle.position = Vector3(0.0, 0.0, -0.6)
	_muzzle_light = _muzzle.get_node_or_null("MuzzleLight") as OmniLight3D
	if _muzzle_light == null:
		_muzzle_light = OmniLight3D.new()
		_muzzle_light.name = "MuzzleLight"
		_muzzle.add_child(_muzzle_light)
	_muzzle_light.light_color = Color(1.0, 0.72, 0.32)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 4.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := ads_mouse_sensitivity if _aiming else mouse_sensitivity
		_cam_yaw -= event.relative.x * sens
		_cam_pitch = clampf(_cam_pitch - event.relative.y * sens, min_pitch, max_pitch)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	_handle_actions()
	_sync_camera_rig(delta)

	if is_on_floor():
		if _jumping and velocity.y <= 0.0:
			_jumping = false
		if Input.is_action_just_pressed("jump") and not _crouching:
			velocity.y = jump_velocity
			_jumping = true
			do_jump()
	else:
		velocity.y -= gravity * delta
		_jumping = true
	floor_snap_length = 0.0 if velocity.y > 0.4 else 0.2

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_sprinting = Input.is_action_pressed("sprint") and not input_dir.is_zero_approx() and not _crouching and not _aiming

	var fwd := Vector3.FORWARD.rotated(Vector3.UP, _cam_yaw)
	var right := Vector3.RIGHT.rotated(Vector3.UP, _cam_yaw)
	var desired := Vector3.ZERO
	if not input_dir.is_zero_approx():
		desired = (fwd * -input_dir.y + right * input_dir.x)
		desired.y = 0.0
		if desired.length_squared() > 0.0001:
			desired = desired.normalized()

	var top_speed := 0.0
	if not input_dir.is_zero_approx():
		top_speed = run_speed if _sprinting else walk_speed
	if _crouching and top_speed > 0.0:
		top_speed = crouch_speed
	elif _aiming and top_speed > 0.0:
		top_speed = walk_speed * aim_speed_factor
	var target_vel := desired * top_speed
	var rate := accel if desired != Vector3.ZERO else decel
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)

	move_and_slide()

	if Input.is_action_pressed("fire"):
		_try_fire()

	var dir_deg := 0.0
	if not input_dir.is_zero_approx():
		dir_deg = rad_to_deg(atan2(input_dir.x, -input_dir.y))
	var horiz_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	set_locomotion(dir_deg, horiz_speed)
	_current_speed = horiz_speed
	_check_oneshot_exit()

	_ap.advance(delta)
	_lock_root_motion()

func _handle_actions() -> void:
	var crouch_now := Input.is_action_pressed("crouch")
	if crouch_now != _crouching:
		set_crouching(crouch_now)
	var aim_now := Input.is_action_pressed("aim")
	if aim_now != _aiming:
		set_aiming(aim_now)
	if Input.is_action_just_pressed("reload"):
		try_reload()

func _sync_camera_rig(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _cam_yaw, clampf(delta * turn_speed, 0.0, 1.0))
	_spring.rotation.y = 0.0
	_spring.rotation.x = _cam_pitch
	var target_len := ads_spring_length if _aiming else hip_spring_length
	_spring.spring_length = lerpf(_spring.spring_length, target_len, clampf(delta * 8.0, 0.0, 1.0))
	var target_fov := ads_fov if _aiming else hip_fov
	_cam.fov = lerpf(_cam.fov, target_fov, clampf(delta * 8.0, 0.0, 1.0))

func _lock_root_motion() -> void:
	if _hip_idx < 0:
		return
	var p := _skel.get_bone_pose_position(_hip_idx)
	p.x = _hip_rest_pos.x
	p.z = _hip_rest_pos.z
	p.y = clampf(p.y, _hip_rest_pos.y - 0.12, _hip_rest_pos.y + 0.28)
	_skel.set_bone_pose_position(_hip_idx, p)
	_skel.force_update_all_bone_transforms()

func _update_base_pose(dir_deg: float, speed: float) -> void:
	var target := _target_clip(dir_deg, speed)
	if _oneshot_active:
		_base_clip = target
		return
	if target == _base_clip and (_ap.is_playing() or target == C_JUMP):
		return
	_apply_base_clip(target, 0.12, -1.0)

func _target_clip(dir_deg: float, speed: float) -> StringName:
	if _jumping or not is_on_floor():
		return C_JUMP
	if _crouching:
		if speed < 0.35:
			return C_IDLE_CROUCH
		if absf(dir_deg) <= 45.0 or absf(dir_deg) > 135.0:
			return C_CROUCH_F
		return C_CROUCH_R if dir_deg > 0.0 else C_CROUCH_L
	if speed < 0.35:
		return C_IDLE_AIM if _aiming else C_IDLE
	var running := _sprinting
	var abs_dir := absf(dir_deg)
	if abs_dir <= 35.0:
		return C_RUN_F if running else C_WALK_F
	if abs_dir <= 80.0:
		if running:
			return C_RUN_F
		return C_WALK_FR if dir_deg > 0.0 else C_WALK_FL
	if abs_dir <= 135.0:
		return C_STRAFE
	return C_RUN_B if running else C_WALK_B

func _begin_oneshot(clip_name: StringName) -> bool:
	if not _ap.has_animation(clip_name):
		return false
	if _oneshot_active and _oneshot_name == clip_name:
		return false
	if _oneshot_active:
		_on_animation_finished(_oneshot_name)
	_resume_clip = _base_clip
	_resume_pos = _ap.current_animation_position
	_oneshot_active = true
	_oneshot_name = clip_name
	_exit_at_ms = Time.get_ticks_msec() + _clip_ms(clip_name) + 80
	_ap.play(clip_name, 0.08)
	return true

func _check_oneshot_exit() -> void:
	if _oneshot_active and Time.get_ticks_msec() >= _exit_at_ms:
		_on_animation_finished(_oneshot_name)

func _on_animation_finished(anim_name: StringName) -> void:
	if not _oneshot_active or anim_name != _oneshot_name:
		return
	_oneshot_active = false
	if _reloading and anim_name == C_RELOAD:
		_finish_reload()
	var resume := _base_clip
	if resume == C_JUMP and is_on_floor() and not _jumping:
		resume = C_IDLE
	_apply_base_clip(resume, 0.1, _resume_pos)

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

func _try_fire() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if _reloading:
		return
	if _current_mag <= 0:
		try_reload()
		return
	if not _can_fire:
		return
	_fire()

func _fire() -> void:
	_current_mag -= 1
	_can_fire = false
	_begin_oneshot(C_FIRE)
	get_tree().create_timer(1.0 / maxf(fire_rate, 0.01), false).timeout.connect(func() -> void: _can_fire = true, CONNECT_ONE_SHOT)
	_sfx("play_gunshot")
	if _muzzle_light:
		_muzzle_light.light_energy = 6.0
		var tw := create_tween()
		tw.tween_property(_muzzle_light, "light_energy", 0.0, 0.06)
	var origin := _cam.global_position
	var aim_dir := -_cam.global_transform.basis.z
	var to := origin + aim_dir * 200.0
	var q := PhysicsRayQueryParameters3D.create(origin, to, 1 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit.position
		var col = hit.collider
		if col != null and col.has_method("take_damage"):
			col.take_damage(damage)
		_spawn_impact(col, end, hit.normal)
	var muzzle_pos := _muzzle.global_position if _muzzle else origin
	_spawn_trail(muzzle_pos, end)

func try_reload() -> bool:
	if _reloading or _current_reserve <= 0 or _current_mag >= mag_size:
		return false
	_reloading = true
	_sfx("play_reload")
	if not _begin_oneshot(C_RELOAD):
		get_tree().create_timer(1.6, false).timeout.connect(_finish_reload, CONNECT_ONE_SHOT)
	return true

func _finish_reload() -> void:
	var needed := mag_size - _current_mag
	var take := mini(needed, _current_reserve)
	if take > 0:
		_current_reserve -= take
		_current_mag += take
	_reloading = false

func is_reloading() -> bool:
	return _reloading

func do_jump() -> void:
	if _oneshot_active and _oneshot_name == C_RELOAD:
		return
	if _oneshot_active:
		_on_animation_finished(_oneshot_name)
	_apply_base_clip(C_JUMP, 0.08, -1.0)

func is_jumping() -> bool:
	return _jumping or not is_on_floor()

func take_damage(amount: int) -> void:
	health = maxi(health - amount, 0)

func get_health() -> int:
	return health

func get_ammo() -> Dictionary:
	return {"mag": _current_mag, "reserve": _current_reserve}

func _clip_ms(clip_name: StringName) -> int:
	var a: Animation = _ap.get_animation(clip_name)
	if a == null:
		return 800
	return int(a.length * 1000.0)

func _sfx(method: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method(method):
		am.call(method)

func _apply_base_clip(clip: StringName, blend: float, seek_pos: float) -> void:
	if not _ap.has_animation(clip):
		return
	_base_clip = clip
	_ap.play(clip, blend)
	if seek_pos >= 0.0:
		_ap.seek(seek_pos, true)

func _spawn_trail(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.015, 0.015, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.5, 1.0)
	box.material = mat
	beam.mesh = box
	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(beam)
	beam.global_position = (from + to) * 0.5
	var dir := (to - from).normalized()
	if absf(dir.dot(Vector3.UP)) > 0.99:
		beam.look_at(to, Vector3.RIGHT)
	else:
		beam.look_at(to)
	var tw := beam.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.07)
	tw.tween_callback(beam.queue_free)

func _spawn_impact(parent_node: Variant, hit_pos: Vector3, normal: Vector3) -> void:
	var fx := ImpactScene.instantiate()
	var parent: Node = get_tree().current_scene
	if parent_node is Node3D and (parent_node as Node).is_inside_tree():
		parent = parent_node
	if parent == null:
		return
	parent.add_child(fx)
	fx.global_position = hit_pos
	fx.setup(normal)

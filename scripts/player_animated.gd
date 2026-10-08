extends CharacterBody3D

## Player animated rig controller.
## Full third-person locomotion: WASD movement (camera-relative), Shift to run,
## Space to jump. Drives the AnimationTree Locomotion blend space + jump state.

@export var walk_speed := 3.2
@export var run_speed := 6.5
@export var accel := 12.0
@export var decel := 16.0
@export var jump_velocity := 8.0
@export var gravity := 20.0
@export var turn_speed := 8.0

@onready var _tree: AnimationTree = $AnimationTree
var _current_speed := 0.0

func _ready() -> void:
	_tree.process_callback = AnimationTree.ANIMATION_PROCESS_PHYSICS
	set_locomotion(0.0, 0.0)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		do_jump()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := Input.is_action_pressed("sprint") and input_dir != Vector2.ZERO

	var cam := _camera()
	var fwd := _forwards(cam)
	var right := _rights(cam)
	var desired := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		desired = (fwd * -input_dir.y + right * input_dir.x).normalized()

	var target_vel := desired * (run_speed if sprinting else walk_speed)
	var rate := accel if desired != Vector3.ZERO else decel
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)

	move_and_slide()

	_face_camera(fwd, delta)

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var horiz_speed := horiz.length()
	var blend_y := clampf(horiz_speed / run_speed, 0.0, 1.0) * 600.0
	var dir_deg := 0.0
	if horiz_speed > 0.05:
		dir_deg = rad_to_deg(atan2(horiz.dot(right), horiz.dot(fwd)))
	set_locomotion(dir_deg, blend_y)
	_current_speed = horiz_speed

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

## dir_deg: movement direction in degrees (-180..180, 0 = forward).
## speed: locomotion speed 0..600.
func set_locomotion(dir_deg: float, speed: float) -> void:
	_ensure_initialized()
	_tree.set("parameters/Locomotion/blend_position", Vector2(dir_deg, clampf(speed, 0.0, 600.0)))

func do_jump() -> void:
	_ensure_initialized()
	var pb := _pb()
	if pb.get_current_node() != "Rifle_Jump":
		pb.travel("Rifle_Jump")

func is_jumping() -> bool:
	_ensure_initialized()
	var pb := _pb()
	return pb.get_current_node() == "Rifle_Jump"
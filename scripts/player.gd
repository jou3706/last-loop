extends CharacterBody3D

@export_category("Movement")
@export var walk_speed := 3.5
@export var sprint_speed := 5.5
@export var jump_velocity := 4.5
@export var gravity := 9.8

@export_category("Look")
@export var mouse_sensitivity := 0.0022
@export var min_pitch := -1.4
@export var max_pitch := 1.4

@export_category("Camera Bob")
@export var bob_enabled := true
@export var bob_amplitude := 0.04
@export var bob_frequency := 1.8

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _bob_time := 0.0
var _base_cam_pos := Vector3.ZERO

func _ready() -> void:
	_base_cam_pos = camera.position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x - event.relative.y * mouse_sensitivity,
			min_pitch,
			max_pitch
		)
	if event.is_action_pressed("pause"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= gravity * delta

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	_update_bob(delta, input_dir, speed)

func _update_bob(delta: float, input_dir: Vector2, speed: float) -> void:
	if not bob_enabled:
		return
	var moving := is_on_floor() and input_dir != Vector2.ZERO
	if moving:
		_bob_time += delta * (speed / walk_speed)
		var phase := _bob_time * TAU * bob_frequency
		camera.position.y = lerpf(
			camera.position.y,
			_base_cam_pos.y + sin(phase) * bob_amplitude,
			10.0 * delta
		)
		camera.position.x = lerpf(
			camera.position.x,
			_base_cam_pos.x + cos(phase * 0.5) * bob_amplitude * 0.6,
			10.0 * delta
		)
	else:
		_bob_time = 0.0
		camera.position = camera.position.lerp(_base_cam_pos, 10.0 * delta)

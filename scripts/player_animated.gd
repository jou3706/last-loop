extends CharacterBody3D

## Player animated rig controller.
## Drives the AnimationTree Locomotion blend space + jump state.

@export var turn_speed := 8.0

@onready var _tree: AnimationTree = $AnimationTree

func _ready() -> void:
	_tree.process_callback = AnimationTree.ANIMATION_PROCESS_PHYSICS
	set_locomotion(0.0, 0.0)

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
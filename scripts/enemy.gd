extends CharacterBody3D

@export var speed := 2.8
@export var health := 100
@export var score_value := 10
@export var attack_range := 1.6
@export var attack_damage := 15
@export var attack_cooldown := 1.0
@export var gravity := 9.8

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var eyes: RayCast3D = $Eyes

var _target: Node3D = null
var _can_attack := true
var _player_ref: Node3D = null

signal died(score_value: int)

func _ready() -> void:
	nav.path_desired_distance = 0.5
	nav.target_desired_distance = 0.5
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
	nav.target_position = _player_ref.global_position
	if nav.is_navigation_finished():
		velocity.x = 0; velocity.z = 0
	else:
		var dir = (nav.get_next_path_position() - global_position).normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	move_and_slide()
	_try_attack()

func _try_attack() -> void:
	if not _can_attack: return
	if _player_ref == null: return
	if global_position.distance_to(_player_ref.global_position) <= attack_range:
		_can_attack = false
		get_tree().create_timer(attack_cooldown, false).timeout.connect(func(): _can_attack=true, CONNECT_ONE_SHOT)
		# simple damage hook if player has health later
		if _player_ref.has_method("take_damage"):
			_player_ref.take_damage(attack_damage)

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		died.emit(score_value)
		queue_free()
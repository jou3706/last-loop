extends Node3D

@export var lifetime := 8.0

func _ready() -> void:
    var tw := create_tween()
    tw.tween_interval(lifetime)
    tw.tween_callback(queue_free)

## Orients the effect so +Z points along the surface normal.
func setup(normal: Vector3) -> void:
    if normal.length_squared() < 0.0001:
        return
    var n := normal.normalized()
    var up := Vector3.UP
    if absf(n.dot(Vector3.UP)) > 0.99:
        up = Vector3.RIGHT
    look_at(global_position - n, up)

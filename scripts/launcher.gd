extends Node2D

signal ball_launched(ball: RigidBody2D)
signal aim_changed(direction: Vector2, charge_ratio: float, impulse: float)
signal charge_started
signal charge_stopped

## Lowest impulse produced by a quick click.
@export_range(0.0, 5000.0, 10.0) var minimum_launch_impulse: float = 800.0
## Highest impulse produced by a full charge.
@export_range(0.0, 5000.0, 10.0) var launch_impulse: float = 3000.0
## Seconds required to reach full launch power.
@export_range(0.1, 5.0, 0.05) var full_charge_seconds: float = 1.2
## Maximum angle to either side of straight up.
@export_range(0.0, 85.0, 1.0) var launch_angle_limit_deg: float = 60.0
## Assign the hidden, frozen RigidBody2D used as the ball template.
@export_node_path("RigidBody2D") var ball_template: NodePath

var _firing_enabled := false
var _charging := false
var _was_pressed := false
var _charge_seconds := 0.0
var _aim_direction := Vector2.UP

@onready var _aim_guide: Line2D = get_node_or_null("AimGuide") as Line2D


func _ready() -> void:
	_update_aim()
	_update_aim_guide(0.0)


func _process(delta: float) -> void:
	_update_aim()

	var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not _firing_enabled:
		if _charging:
			charge_stopped.emit()
		_charging = false
		_charge_seconds = 0.0
		_was_pressed = pressed
		_update_feedback()
		return

	if pressed and not _was_pressed:
		_charging = true
		_charge_seconds = 0.0
		charge_started.emit()

	if pressed and _charging:
		_charge_seconds = minf(_charge_seconds + delta, full_charge_seconds)

	if not pressed and _was_pressed and _charging:
		# Capture the charged value before clearing the charging state. Otherwise
		# _charge_ratio() falls back to zero and every shot uses minimum power.
		var charged_impulse := _current_impulse()
		_charging = false
		charge_stopped.emit()
		_spawn_ball(charged_impulse)
		_charge_seconds = 0.0

	_was_pressed = pressed
	_update_feedback()


func set_firing_enabled(enabled: bool) -> void:
	if _charging:
		charge_stopped.emit()
	_firing_enabled = enabled
	_charging = false
	_charge_seconds = 0.0
	# Ignore a click that was already held while a menu closed.
	_was_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_update_feedback()


func _update_aim() -> void:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() < 1.0:
		return

	var desired_angle := atan2(to_mouse.x, -to_mouse.y)
	var angle_limit := deg_to_rad(launch_angle_limit_deg)
	desired_angle = clampf(desired_angle, -angle_limit, angle_limit)
	_aim_direction = Vector2.UP.rotated(desired_angle)


func _charge_ratio() -> float:
	if not _charging or full_charge_seconds <= 0.0:
		return 0.0
	return clampf(_charge_seconds / full_charge_seconds, 0.0, 1.0)


func _current_impulse() -> float:
	return lerpf(minimum_launch_impulse, launch_impulse, _charge_ratio())


func _update_feedback() -> void:
	var ratio := _charge_ratio()
	_update_aim_guide(ratio)
	aim_changed.emit(_aim_direction, ratio, _current_impulse())


func _update_aim_guide(charge_ratio: float) -> void:
	if _aim_guide == null:
		return
	var guide_length := lerpf(150.0, 250.0, charge_ratio)
	_aim_guide.points = PackedVector2Array([Vector2.ZERO, _aim_direction * guide_length])
	_aim_guide.default_color = Color(0.35, 0.85, 1.0).lerp(Color(1.0, 0.75, 0.2), charge_ratio)
	_aim_guide.visible = _firing_enabled


func _spawn_ball(impulse: float) -> void:
	var template := get_node_or_null(ball_template) as RigidBody2D
	if template == null:
		push_warning("Launcher: assign Ball Template in the Inspector.")
		return

	var new_ball := template.duplicate() as RigidBody2D
	if new_ball == null:
		push_warning("Launcher: BallTemplate could not be duplicated.")
		return

	new_ball.name = "Ball"
	new_ball.visible = true
	new_ball.freeze = false
	new_ball.sleeping = false
	new_ball.linear_velocity = Vector2.ZERO
	new_ball.angular_velocity = 0.0
	new_ball.add_to_group("launched_balls")
	get_parent().add_child(new_ball)

	# The authored template uses child offsets. Align the actual collision shape
	# with the launcher's global position without changing the template itself.
	var spawn_offset := Vector2.ZERO
	var collision_shape := new_ball.get_node_or_null("CollisionShape2D") as Node2D
	if collision_shape != null:
		spawn_offset = collision_shape.position
	new_ball.global_position = global_position - spawn_offset

	# Wait until the duplicated body is registered in the physics world before
	# applying the impulse; otherwise the frozen-to-active transition may eat it.
	new_ball.call_deferred("apply_central_impulse", _aim_direction * impulse)
	ball_launched.emit(new_ball)
	set_firing_enabled(false)

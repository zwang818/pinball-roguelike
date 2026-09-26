extends Area2D

signal ball_entered(
	zone: Area2D,
	ball: RigidBody2D,
	base_score: int,
	ball_bonus: int,
	zone_label: String
)

## Score produced when a ball enters this lane.
@export var score_value: int = 50
## Balls returned to the player. Keep at zero for normal score zones.
@export_range(0, 9, 1) var ball_bonus: int = 0
## Player-facing name used by score feedback.
@export var zone_label: String = "普通奖励"


func _ready() -> void:
	add_to_group("score_zones")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var ball := body as RigidBody2D
	if ball == null or not ball.is_in_group("launched_balls"):
		return
	ball_entered.emit(self, ball, score_value, ball_bonus, zone_label)

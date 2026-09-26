extends Node2D

## Shared whitebox peg appearance and collision tuning.
@export_range(1.0, 64.0, 1.0) var peg_radius: float = 12.0
@export_range(0.0, 1.0, 0.05) var peg_bounce: float = 0.9
@export var peg_texture: Texture2D = preload("res://assets/peg.svg")

@export_group("Level 1 Layout")
@export_range(1, 12, 1) var level_1_rows: int = 5
@export_range(1, 16, 1) var level_1_even_columns: int = 11
@export_range(1, 16, 1) var level_1_odd_columns: int = 10
@export var level_1_start: Vector2 = Vector2(210.0, 280.0)
@export_range(40.0, 240.0, 1.0) var level_1_column_spacing: float = 145.0
@export_range(40.0, 180.0, 1.0) var level_1_row_spacing: float = 95.0

@export_group("Level 2 Layout")
@export_range(1, 12, 1) var level_2_rows: int = 6
@export_range(1, 16, 1) var level_2_even_columns: int = 12
@export_range(1, 16, 1) var level_2_odd_columns: int = 11
@export var level_2_start: Vector2 = Vector2(180.0, 230.0)
@export_range(40.0, 240.0, 1.0) var level_2_column_spacing: float = 135.0
@export_range(40.0, 180.0, 1.0) var level_2_row_spacing: float = 90.0


func _ready() -> void:
	build_for_level(1)


func build_for_level(level_number: int) -> void:
	_clear_generated_pegs()
	if level_number == 2:
		_build_staggered_layout(
			level_2_rows,
			level_2_even_columns,
			level_2_odd_columns,
			level_2_start,
			level_2_column_spacing,
			level_2_row_spacing,
			"L2"
		)
		# The lower cluster adds a final deflection before the four scoring lanes.
		for index in range(4):
			_create_peg("L2_Lower_%02d" % (index + 1), Vector2(725.0 + index * 135.0, 770.0))
	else:
		_build_staggered_layout(
			level_1_rows,
			level_1_even_columns,
			level_1_odd_columns,
			level_1_start,
			level_1_column_spacing,
			level_1_row_spacing,
			"L1"
		)


func _build_staggered_layout(
	rows: int,
	even_columns: int,
	odd_columns: int,
	start: Vector2,
	column_spacing: float,
	row_spacing: float,
	prefix: String
) -> void:
	for row in range(rows):
		var column_count := even_columns if row % 2 == 0 else odd_columns
		var row_offset := 0.0 if row % 2 == 0 else column_spacing * 0.5
		for column in range(column_count):
			var peg_position := start + Vector2(
				column * column_spacing + row_offset,
				row * row_spacing
			)
			_create_peg("%s_Peg_%02d_%02d" % [prefix, row + 1, column + 1], peg_position)


func _create_peg(peg_name: String, peg_position: Vector2) -> void:
	var peg := Area2D.new()
	peg.name = peg_name
	peg.position = peg_position
	peg.collision_layer = 2
	peg.collision_mask = 1
	peg.set_meta("generated_peg", true)
	add_child(peg)

	var peg_shape := CircleShape2D.new()
	peg_shape.radius = peg_radius

	var area_collision := CollisionShape2D.new()
	area_collision.name = "CollisionShape2D"
	area_collision.shape = peg_shape
	peg.add_child(area_collision)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = peg_texture
	sprite.self_modulate = Color(1.0, 1.0, 1.0, 0.94)
	peg.add_child(sprite)

	# The Area2D keeps future interaction hooks available. Its StaticBody2D
	# child supplies the actual rebound surface and never awards score.
	var solid_body := StaticBody2D.new()
	solid_body.name = "SolidBody2D"
	solid_body.collision_layer = 1
	solid_body.collision_mask = 1
	var material := PhysicsMaterial.new()
	material.friction = 0.05
	material.bounce = peg_bounce
	solid_body.physics_material_override = material
	peg.add_child(solid_body)

	var solid_collision := CollisionShape2D.new()
	solid_collision.name = "CollisionShape2D"
	solid_collision.shape = peg_shape
	solid_body.add_child(solid_collision)


func _clear_generated_pegs() -> void:
	for child in get_children():
		if child.has_meta("generated_peg"):
			child.free()

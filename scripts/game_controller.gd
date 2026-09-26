extends Node2D

enum RunState {
	PLAYING,
	WAITING_FOR_FINAL_BALL,
	BUFF_SELECTION,
	VICTORY,
	FAILURE,
}

@export_group("Scene Bindings")
@export_node_path("Node2D") var launcher_path: NodePath
@export_node_path("Node2D") var peg_board_path: NodePath
@export_node_path("Node2D") var audio_manager_path: NodePath
@export_node_path("CanvasLayer") var hud_path: NodePath

@export_group("Level 1")
@export_range(1, 99, 1) var level_1_balls: int = 15
@export_range(1, 9999, 1) var level_1_target_score: int = 300
@export_range(1.0, 600.0, 1.0) var level_1_time_seconds: float = 120.0

@export_group("Level 2")
@export_range(1, 99, 1) var level_2_balls: int = 15
@export_range(1, 9999, 1) var level_2_target_score: int = 400
@export_range(1.0, 600.0, 1.0) var level_2_time_seconds: float = 120.0

@export_group("Ball Resolution")
@export_range(1.0, 60.0, 1.0) var maximum_ball_lifetime: float = 20.0
@export var cleanup_bounds: Rect2 = Rect2(-80.0, -120.0, 2080.0, 1260.0)

var current_level := 1
var current_score := 0
var level_1_final_score := 0
var balls_remaining := 0
var target_score := 0
var time_remaining := 0.0
var total_play_time := 0.0
var selected_buff := "无"
var state := RunState.PLAYING
var active_ball: RigidBody2D
var active_ball_time := 0.0
var _message_time := 0.0
var _last_timer_second := -1

var _launcher: Node2D
var _peg_board: Node2D
var _audio_manager: Node2D
var _hud: CanvasLayer

var _level_label: Label
var _score_label: Label
var _balls_label: Label
var _time_label: Label
var _buff_label: Label
var _center_message: Label
var _power_bar: ProgressBar
var _power_label: Label
var _buff_panel: Control
var _result_panel: Control
var _result_title: Label
var _result_stats: Label


func _ready() -> void:
	_launcher = get_node(launcher_path) as Node2D
	_peg_board = get_node(peg_board_path) as Node2D
	_audio_manager = get_node(audio_manager_path) as Node2D
	_hud = get_node(hud_path) as CanvasLayer
	_cache_hud_nodes()
	_connect_scene_signals()
	_start_new_run()


func _process(delta: float) -> void:
	if state == RunState.PLAYING:
		time_remaining = maxf(time_remaining - delta, 0.0)
		total_play_time += delta
		var timer_second := ceili(time_remaining)
		if timer_second != _last_timer_second:
			_last_timer_second = timer_second
			if timer_second > 0 and timer_second <= 10:
				_audio_manager.call("play_tick")
		if time_remaining <= 0.0:
			state = RunState.WAITING_FOR_FINAL_BALL
			_set_launcher_enabled(false)
			_show_center_message("时间耗尽 · 等待最后一球结算", Color(1.0, 0.35, 0.3), -1.0)
			if active_ball == null:
				_finish_level_after_resources_end()

	if active_ball != null and is_instance_valid(active_ball):
		active_ball_time += delta
		var ball_position := _get_ball_center(active_ball)
		if not cleanup_bounds.has_point(ball_position):
			_audio_manager.call("play_miss")
			_resolve_active_ball("越界：0 分")
		elif active_ball_time >= maximum_ball_lifetime:
			_audio_manager.call("play_miss")
			_resolve_active_ball("本球超时：0 分")
		elif active_ball.sleeping and active_ball_time > 1.0:
			_audio_manager.call("play_miss")
			_resolve_active_ball("未进入区域：0 分")

	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_center_message.text = ""

	_update_hud()


func _cache_hud_nodes() -> void:
	_level_label = _hud.get_node("HUDRoot/StatusPanel/LevelLabel") as Label
	_score_label = _hud.get_node("HUDRoot/StatusPanel/ScoreLabel") as Label
	_balls_label = _hud.get_node("HUDRoot/StatusPanel/BallsLabel") as Label
	_time_label = _hud.get_node("HUDRoot/StatusPanel/TimeLabel") as Label
	_buff_label = _hud.get_node("HUDRoot/StatusPanel/BuffLabel") as Label
	_center_message = _hud.get_node("HUDRoot/CenterMessage") as Label
	_power_bar = _hud.get_node("HUDRoot/PowerPanel/PowerBar") as ProgressBar
	_power_label = _hud.get_node("HUDRoot/PowerPanel/PowerLabel") as Label
	_buff_panel = _hud.get_node("HUDRoot/BuffPanel") as Control
	_result_panel = _hud.get_node("HUDRoot/ResultPanel") as Control
	_result_title = _hud.get_node("HUDRoot/ResultPanel/Card/ResultTitle") as Label
	_result_stats = _hud.get_node("HUDRoot/ResultPanel/Card/ResultStats") as Label


func _connect_scene_signals() -> void:
	_launcher.connect("ball_launched", Callable(self, "_on_ball_launched"))
	_launcher.connect("aim_changed", Callable(self, "_on_aim_changed"))
	_launcher.connect("charge_started", Callable(self, "_on_charge_started"))
	_launcher.connect("charge_stopped", Callable(self, "_on_charge_stopped"))
	for zone in get_tree().get_nodes_in_group("score_zones"):
		zone.connect("ball_entered", Callable(self, "_on_score_zone_entered"))

	(_hud.get_node("HUDRoot/BuffPanel/Card/BuffBallsButton") as Button).pressed.connect(
		_choose_buff.bind("备用弹匣")
	)
	(_hud.get_node("HUDRoot/BuffPanel/Card/BuffScoreButton") as Button).pressed.connect(
		_choose_buff.bind("得分增幅")
	)
	(_hud.get_node("HUDRoot/BuffPanel/Card/BuffSafeButton") as Button).pressed.connect(
		_choose_buff.bind("安全落袋")
	)
	(_hud.get_node("HUDRoot/ResultPanel/Card/RetryButton") as Button).pressed.connect(_start_new_run)


func _start_new_run() -> void:
	_clear_launched_balls()
	current_level = 1
	level_1_final_score = 0
	total_play_time = 0.0
	selected_buff = "无"
	_start_level(1)


func _start_level(level_number: int) -> void:
	_clear_launched_balls()
	current_level = level_number
	current_score = 0
	active_ball_time = 0.0
	state = RunState.PLAYING
	_message_time = 0.0
	_center_message.text = ""
	_buff_panel.visible = false
	_result_panel.visible = false

	if current_level == 1:
		balls_remaining = level_1_balls
		target_score = level_1_target_score
		time_remaining = level_1_time_seconds
	else:
		balls_remaining = level_2_balls + (3 if selected_buff == "备用弹匣" else 0)
		target_score = level_2_target_score
		time_remaining = level_2_time_seconds
	_last_timer_second = ceili(time_remaining)

	_peg_board.call("build_for_level", current_level)
	_set_launcher_enabled(true)
	_update_hud()


func _on_ball_launched(ball: RigidBody2D) -> void:
	if state != RunState.PLAYING or balls_remaining <= 0:
		ball.queue_free()
		return
	balls_remaining -= 1
	active_ball = ball
	active_ball_time = 0.0
	_audio_manager.call("register_ball", ball)
	_audio_manager.call("play_launch")
	_set_launcher_enabled(false)
	_update_hud()


func _on_aim_changed(_direction: Vector2, charge_ratio: float, impulse: float) -> void:
	_power_bar.value = charge_ratio * 100.0
	_power_label.text = "力度 %d  （按住蓄力，松开发射）" % roundi(impulse)
	_audio_manager.call("update_charge", charge_ratio)


func _on_charge_started() -> void:
	_audio_manager.call("start_charge")


func _on_charge_stopped() -> void:
	_audio_manager.call("stop_charge")


func _on_score_zone_entered(
	_zone: Area2D,
	ball: RigidBody2D,
	base_score: int,
	ball_bonus: int,
	zone_label: String
) -> void:
	if ball != active_ball:
		return
	_audio_manager.call("play_score", base_score, ball_bonus)
	if ball_bonus > 0:
		balls_remaining += ball_bonus
		_resolve_active_ball(
			"%s：+%d 个球" % [zone_label, ball_bonus],
			Color(1.0, 0.82, 0.3)
		)
		return
	var awarded_score := _apply_buff_to_score(base_score)
	current_score = maxi(0, current_score + awarded_score)
	var prefix := "+" if awarded_score > 0 else ""
	var feedback_color := Color(0.45, 1.0, 0.55) if awarded_score >= 0 else Color(1.0, 0.4, 0.35)
	_resolve_active_ball("%s：%s%d 分" % [zone_label, prefix, awarded_score], feedback_color)


func _apply_buff_to_score(base_score: int) -> int:
	if current_level != 2:
		return base_score
	if selected_buff == "安全落袋" and base_score < 0:
		return 0
	if selected_buff == "得分增幅" and base_score > 0:
		return roundi(float(base_score) * 1.25)
	return base_score


func _resolve_active_ball(feedback: String, feedback_color: Color = Color.WHITE) -> void:
	if active_ball == null:
		return
	var finished_ball := active_ball
	active_ball = null
	active_ball_time = 0.0
	if is_instance_valid(finished_ball):
		finished_ball.queue_free()
	_show_center_message(feedback, feedback_color, 1.2)

	if current_score >= target_score:
		_complete_level()
	elif state == RunState.WAITING_FOR_FINAL_BALL or balls_remaining <= 0:
		_finish_level_after_resources_end()
	else:
		_set_launcher_enabled(true)


func _complete_level() -> void:
	_set_launcher_enabled(false)
	if current_level == 1:
		level_1_final_score = current_score
		state = RunState.BUFF_SELECTION
		_audio_manager.call("play_level_clear")
		_message_time = 0.0
		_center_message.text = "第一关通过！选择一个 Buff"
		_buff_panel.visible = true
	else:
		state = RunState.VICTORY
		_show_result(true)


func _finish_level_after_resources_end() -> void:
	if current_score >= target_score:
		_complete_level()
	else:
		state = RunState.FAILURE
		_set_launcher_enabled(false)
		_show_result(false)


func _choose_buff(buff_name: String) -> void:
	if state != RunState.BUFF_SELECTION:
		return
	_audio_manager.call("play_buff_confirm")
	selected_buff = buff_name
	_start_level(2)


func _show_result(victory: bool) -> void:
	_buff_panel.visible = false
	_result_panel.visible = true
	_center_message.text = ""
	var total_score := level_1_final_score + current_score
	if victory:
		_audio_manager.call("play_victory")
		_result_title.text = "🎉 通关成功！"
		_result_title.modulate = Color(1.0, 0.9, 0.35)
		_result_stats.text = "总用时：%.1f 秒\n两关总分：%d\n剩余球数：%d\n本局 Buff：%s" % [
			total_play_time,
			total_score,
			balls_remaining,
			selected_buff,
		]
	else:
		_audio_manager.call("play_failure")
		_result_title.text = "挑战失败"
		_result_title.modulate = Color(1.0, 0.45, 0.4)
		_result_stats.text = "第 %d 关得分：%d / %d\n距离目标还差：%d\n重新挑战将从第一关开始" % [
			current_level,
			current_score,
			target_score,
			maxi(target_score - current_score, 0),
		]

	# Short MVP celebration: fade the page in and briefly pulse the title.
	_result_panel.modulate.a = 0.0
	_result_title.scale = Vector2(0.85, 0.85)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_result_panel, "modulate:a", 1.0, 0.3)
	tween.tween_property(_result_title, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK)


func _show_center_message(text: String, color: Color, duration: float) -> void:
	_center_message.text = text
	_center_message.modulate = color
	_message_time = duration


func _set_launcher_enabled(enabled: bool) -> void:
	_launcher.call("set_firing_enabled", enabled and state == RunState.PLAYING and balls_remaining > 0)


func _update_hud() -> void:
	if _level_label == null:
		return
	_level_label.text = "关卡 %d / 2" % current_level
	_score_label.text = "分数 %d / %d" % [current_score, target_score]
	_balls_label.text = "剩余球数 %d" % balls_remaining
	_time_label.text = "时间 %02d" % ceili(time_remaining)
	_time_label.modulate = Color(1.0, 0.25, 0.2) if time_remaining <= 10.0 else Color.WHITE
	_buff_label.text = "Buff：%s" % selected_buff


func _get_ball_center(ball: RigidBody2D) -> Vector2:
	var collision_shape := ball.get_node_or_null("CollisionShape2D") as Node2D
	return collision_shape.global_position if collision_shape != null else ball.global_position


func _clear_launched_balls() -> void:
	active_ball = null
	for candidate in get_tree().get_nodes_in_group("launched_balls"):
		if is_instance_valid(candidate):
			candidate.queue_free()

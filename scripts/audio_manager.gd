extends Node2D

## Centralized music and sound effects for the playable prototype.

@export_group("Volume")
@export_range(-40.0, 6.0, 0.5) var music_volume_db: float = -18.0
@export_range(-40.0, 6.0, 0.5) var sound_volume_db: float = -6.0
@export_range(-40.0, 6.0, 0.5) var ui_volume_db: float = -5.0
@export_range(0.0, 0.25, 0.01) var collision_cooldown_seconds: float = 0.06

@export_group("Audio Streams")
@export var background_music: AudioStream = preload("res://assets/audio/bgm_adventure.wav")
@export var charge_sound: AudioStream = preload("res://assets/audio/charge_loop.wav")
@export var launch_sound: AudioStream = preload("res://assets/audio/launch.wav")
@export var collision_sound: AudioStream = preload("res://assets/audio/collision.wav")
@export var score_100_sound: AudioStream = preload("res://assets/audio/score_100.wav")
@export var score_50_sound: AudioStream = preload("res://assets/audio/score_50.wav")
@export var extra_ball_sound: AudioStream = preload("res://assets/audio/extra_ball.wav")
@export var negative_sound: AudioStream = preload("res://assets/audio/negative.wav")
@export var tick_sound: AudioStream = preload("res://assets/audio/tick.wav")
@export var buff_confirm_sound: AudioStream = preload("res://assets/audio/buff_confirm.wav")
@export var level_clear_sound: AudioStream = preload("res://assets/audio/level_clear.wav")
@export var victory_sound: AudioStream = preload("res://assets/audio/victory.wav")
@export var failure_sound: AudioStream = preload("res://assets/audio/failure.wav")

@onready var _music_player: AudioStreamPlayer = $Music
@onready var _charge_player: AudioStreamPlayer = $Charge
@onready var _sfx_player: AudioStreamPlayer = $SFX
@onready var _ui_player: AudioStreamPlayer = $UI
@onready var _collision_player: AudioStreamPlayer2D = $Collision

var _last_collision_msec := -1000
var _charge_active := false


func _ready() -> void:
	_ensure_audio_bus("Music")
	_ensure_audio_bus("SFX")
	_ensure_audio_bus("UI")

	_music_player.bus = &"Music"
	_charge_player.bus = &"SFX"
	_sfx_player.bus = &"SFX"
	_collision_player.bus = &"SFX"
	_ui_player.bus = &"UI"
	_music_player.volume_db = music_volume_db
	_charge_player.volume_db = sound_volume_db - 4.0
	_sfx_player.volume_db = sound_volume_db
	_collision_player.volume_db = sound_volume_db - 2.0
	_ui_player.volume_db = ui_volume_db

	_music_player.stream = background_music
	_charge_player.stream = charge_sound
	_collision_player.stream = collision_sound
	_music_player.finished.connect(_restart_music)
	_charge_player.finished.connect(_restart_charge)
	if _music_player.stream != null:
		_music_player.play()


func _exit_tree() -> void:
	# Explicitly stop long-running loops so editor stop/reload releases playback cleanly.
	for player in [_music_player, _charge_player, _sfx_player, _ui_player, _collision_player]:
		player.stop()
		player.stream = null


func start_charge() -> void:
	if _charge_player.stream == null:
		return
	_charge_active = true
	_charge_player.pitch_scale = 0.85
	if not _charge_player.playing:
		_charge_player.play()


func update_charge(charge_ratio: float) -> void:
	if _charge_player.playing:
		_charge_player.pitch_scale = lerpf(0.85, 1.45, clampf(charge_ratio, 0.0, 1.0))


func stop_charge() -> void:
	_charge_active = false
	_charge_player.stop()


func play_launch() -> void:
	_play_sfx(launch_sound, 1.0)


func register_ball(ball: RigidBody2D) -> void:
	ball.contact_monitor = true
	ball.max_contacts_reported = 8
	ball.body_entered.connect(_on_ball_body_entered.bind(ball))


func play_score(base_score: int, ball_bonus: int) -> void:
	if ball_bonus > 0:
		_play_sfx(extra_ball_sound, 1.0)
	elif base_score >= 100:
		_play_sfx(score_100_sound, 1.0)
	elif base_score > 0:
		_play_sfx(score_50_sound, 1.0)
	else:
		play_miss()


func play_miss() -> void:
	_play_sfx(negative_sound, 0.94)


func play_tick() -> void:
	_play_ui(tick_sound, 1.0)


func play_buff_confirm() -> void:
	_play_ui(buff_confirm_sound, 1.0)


func play_level_clear() -> void:
	_play_ui(level_clear_sound, 1.0)


func play_victory() -> void:
	_play_ui(victory_sound, 1.0)


func play_failure() -> void:
	_play_ui(failure_sound, 1.0)


func _on_ball_body_entered(_body: Node, ball: RigidBody2D) -> void:
	if not is_instance_valid(ball):
		return
	var now := Time.get_ticks_msec()
	if now - _last_collision_msec < int(collision_cooldown_seconds * 1000.0):
		return
	_last_collision_msec = now
	var shape := ball.get_node_or_null("CollisionShape2D") as Node2D
	_collision_player.global_position = shape.global_position if shape != null else ball.global_position
	_collision_player.pitch_scale = randf_range(0.94, 1.08)
	_collision_player.play()


func _play_sfx(stream: AudioStream, pitch: float) -> void:
	if stream == null:
		return
	_sfx_player.stream = stream
	_sfx_player.pitch_scale = pitch
	_sfx_player.play()


func _play_ui(stream: AudioStream, pitch: float) -> void:
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.pitch_scale = pitch
	_ui_player.play()


func _restart_music() -> void:
	if is_inside_tree() and _music_player.stream != null:
		_music_player.play()


func _restart_charge() -> void:
	if _charge_active and is_inside_tree() and _charge_player.stream != null:
		_charge_player.play()


func _ensure_audio_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)

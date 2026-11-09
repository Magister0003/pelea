extends Node3D

const Fighter := preload("res://duel_fighter.gd")
const Stage := preload("res://duel_stage.gd")
const Hud := preload("res://duel_hud.gd")
const Impact := preload("res://duel_impact.gd")
const EDGE := 5.4
const MIN_GAP := 0.78
const ROUND_SECONDS := 60
const WINS_REQUIRED := 2

@export var player_one_model: PackedScene
@export var player_two_model: PackedScene
@export_range(0.0, 1.0) var player_one_punch_contact := 0.30
@export_range(0.0, 1.0) var player_one_kick_contact := 0.40
@export_range(0.0, 1.0) var player_two_punch_contact := 0.30
@export_range(0.0, 1.0) var player_two_kick_contact := 0.40

var left := Fighter.new()
var right := Fighter.new()
var hud := Hud.new()
var stage := Stage.new()
var effects := Impact.new()
var hitstop_frames := 0
var left_wins := 0
var right_wins := 0
var time_left := float(ROUND_SECONDS)
var next_round_in := 0.0
var round_finished := false


func _ready() -> void:
	add_child(stage)
	add_child(effects)
	add_child(left)
	add_child(right)
	left.setup(player_one_model, Color("#32d3c5"))
	right.setup(player_two_model, Color("#e66d52"))
	left.punch_contact = player_one_punch_contact
	left.kick_contact = player_one_kick_contact
	right.punch_contact = player_two_punch_contact
	right.kick_contact = player_two_kick_contact
	if player_one_model:
		left.punch_reach = 1.31
		left.kick_reach = 1.70
	if player_two_model:
		right.punch_reach = 1.17
		right.kick_reach = 1.65
	add_child(hud)
	start_round()


func _physics_process(delta: float) -> void:
	stage.update_camera(left.position.x, right.position.x, delta)
	if Input.is_action_just_pressed("restart_match"):
		left_wins = 0
		right_wins = 0
		start_round()
		return
	if round_finished:
		left.update_visual(delta)
		right.update_visual(delta)
		left.advance_frame()
		right.advance_frame()
		if next_round_in > 0.0:
			next_round_in -= delta
			if next_round_in <= 0.0:
				start_round()
		return

	queue_input_attack("p1_", left)
	queue_input_attack("p2_", right)
	if hitstop_frames > 0:
		hitstop_frames -= 1
		return

	var left_velocity := left.prepare_move(
		Input.get_axis("p1_left", "p1_right"),
		Input.is_action_pressed("p1_guard"),
		false
	)
	var right_velocity := right.prepare_move(
		Input.get_axis("p2_left", "p2_right"),
		Input.is_action_pressed("p2_guard"),
		false
	)
	move_fighters(left_velocity * delta, right_velocity * delta)
	resolve_attacks()
	left.update_visual(delta)
	right.update_visual(delta)
	left.advance_frame()
	right.advance_frame()

	time_left = maxf(0.0, time_left - delta)
	hud.set_time(ceili(time_left))
	if left.health == 0 or right.health == 0 or time_left == 0:
		finish_round()


func queue_input_attack(prefix: String, fighter: Fighter) -> void:
	if Input.is_action_just_pressed(prefix + "jump_kick"):
		fighter.queue_attack("jump_kick")
	elif Input.is_action_just_pressed(prefix + "heavy"):
		fighter.queue_attack("heavy")
	elif Input.is_action_just_pressed(prefix + "attack"):
		fighter.queue_attack("punch")
	elif Input.is_action_just_pressed(prefix + "kick"):
		var direction := Input.get_axis(prefix + "left", prefix + "right") * fighter.facing
		if direction > 0.0:
			fighter.queue_attack("front_kick")
		elif direction < 0.0:
			fighter.queue_attack("roundhouse")
		else:
			fighter.queue_attack("kick")


func move_fighters(left_step: float, right_step: float) -> void:
	var left_x := clampf(left.position.x + left_step, -EDGE, EDGE - MIN_GAP)
	var right_x := clampf(right.position.x + right_step, -EDGE + MIN_GAP, EDGE)
	if right_x - left_x < MIN_GAP:
		if left_step > 0.0 and right_step < 0.0:
			var center := (left_x + right_x) * 0.5
			left_x = center - MIN_GAP * 0.5
			right_x = center + MIN_GAP * 0.5
		elif left_step > 0.0:
			left_x = right_x - MIN_GAP
		else:
			right_x = left_x + MIN_GAP

	left.walking = not is_equal_approx(left.position.x, left_x)
	right.walking = not is_equal_approx(right.position.x, right_x)
	left.position.x = left_x
	right.position.x = right_x


func resolve_attacks() -> void:
	# Snapshot both contacts before applying stun so simultaneous hits can trade.
	var left_hits := left.can_hit(right)
	var right_hits := right.can_hit(left)
	var left_damage := left.attack_damage()
	var right_damage := right.attack_damage()
	if left_hits:
		left.attack_connected = true
		show_impact(left, right)
	if right_hits:
		right.attack_connected = true
		show_impact(right, left)
	if left_hits:
		right.take_hit(left_damage)
	if right_hits:
		left.take_hit(right_damage)
	if left_hits or right_hits:
		hud.update_health(left.health, right.health)


func show_impact(attacker: Fighter, defender: Fighter) -> void:
	var direction := attacker.facing
	var height := 1.39 if attacker == left else 1.25
	if attacker.kicking:
		height = 1.7 if attacker == left else 1.82
	if attacker.attack_variant == "front_kick":
		height = 1.2
	var contact := defender.position + Vector3(-direction * 0.22, height, 0.22)
	effects.play_hit(contact, direction, defender.guarding)
	var strength := 0.18 if attacker.attack_damage() > Fighter.DAMAGE else 0.13
	stage.shake(0.045 if defender.guarding else strength)
	hitstop_frames = maxi(hitstop_frames, 2 if defender.guarding else 4)


func start_round() -> void:
	hitstop_frames = 0
	effects.clear()
	round_finished = false
	next_round_in = 0.0
	time_left = ROUND_SECONDS
	left.reset(-2.6, 1.0)
	right.reset(2.6, -1.0)
	stage.update_camera(left.position.x, right.position.x, 0.0)
	hud.clear_result()
	hud.update_health(left.health, right.health)
	hud.update_round(left_wins, right_wins)
	hud.set_time(ROUND_SECONDS)


func finish_round() -> void:
	round_finished = true
	left.walking = false
	right.walking = false
	var result := "Empate"
	if left.health > right.health:
		left_wins += 1
		result = "Kai gana la ronda"
	elif right.health > left.health:
		right_wins += 1
		result = "Akari gana la ronda"
	hud.update_round(left_wins, right_wins)

	if left_wins == WINS_REQUIRED or right_wins == WINS_REQUIRED:
		var winner := "Kai" if left_wins == WINS_REQUIRED else "Akari"
		hud.show_result("%s gana el combate\nR · Volver a jugar" % winner)
	else:
		hud.show_result(result)
		next_round_in = 2.0

extends Node3D

const MAX_HEALTH := 100
const DAMAGE := 20
const SPEED := 2.15
const SOURCE_WALK_SPEED := 0.79
const REACH := 1.5
const ATTACK_FRAMES := 24
const FIRST_ACTIVE_FRAME := 7
const LAST_ACTIVE_FRAME := 9
const HIT_STUN_FRAMES := 15
const KICK_DAMAGE := 27
const KICK_REACH := 1.82
const KICK_FRAMES := 41
const KICK_FIRST_ACTIVE_FRAME := 15
const KICK_LAST_ACTIVE_FRAME := 18
const INPUT_BUFFER_FRAMES := 8
const POSE_BLEND_SECONDS := 0.075
const EXTRA_ATTACKS := {
	"heavy": {"start": 13, "end": 15, "frames": 37, "reach": 1.28, "damage": 32},
	"front_kick": {"start": 10, "end": 12, "frames": 30, "reach": 1.50, "damage": 22},
	"roundhouse": {"start": 17, "end": 20, "frames": 42, "reach": 1.72, "damage": 32},
	"jump_kick": {"start": 18, "end": 21, "frames": 43, "reach": 1.72, "damage": 33},
}

var health := MAX_HEALTH
var facing := 1.0
var guarding := false
var attack_frame := -1
var kicking := false
var attack_connected := false
var stun_frames := 0
var walking := false
var walk_direction := 1.0
var walk_rate := 1.0
var attack_variant := ""
var pending_attack := ""
var buffer_frames := 0
var extra_contacts: Dictionary = {}
var extra_reaches: Dictionary = {}

var visual := Node3D.new()
var front_arm: Node3D
var rear_arm: Node3D
var front_leg: Node3D
var rear_leg: Node3D
var front_elbow: Node3D
var rear_elbow: Node3D
var head: Node3D
var cloth_tail: Node3D
var materials: Dictionary = {}
var is_akari := false
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var previous_pose: Array[Transform3D] = []
var blend_time := 0.0
var animation_names: Dictionary[String, StringName]
var visual_state := ""
var clip_time := 0.0
var walk_phase := 0.0
var punch_contact := 0.30
var kick_contact := 0.40
var punch_reach := REACH
var kick_reach := KICK_REACH


func setup(model: PackedScene, color: Color) -> void:
	add_child(visual)
	if model:
		var model_instance := model.instantiate()
		visual.add_child(model_instance)
		animation_player = find_animation_player(model_instance)
		var skeletons := model_instance.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			skeleton = skeletons[0] as Skeleton3D
		if animation_player:
			animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			for clip in animation_player.get_animation_list():
				animation_names[clip.get_file().to_lower()] = clip
	else:
		build_placeholder(color)


func reset(x: float, direction: float) -> void:
	position.x = x
	facing = direction
	health = MAX_HEALTH
	guarding = false
	attack_frame = -1
	kicking = false
	attack_connected = false
	stun_frames = 0
	walking = false
	visual_state = ""
	attack_variant = ""
	pending_attack = ""
	buffer_frames = 0
	previous_pose.clear()
	update_visual(0)


func queue_attack(requested: String) -> void:
	if requested.is_empty():
		return
	if requested == "jump_kick" and not animation_names.has(requested):
		return
	if requested in EXTRA_ATTACKS and not animation_names.has(requested):
		requested = "punch" if requested == "heavy" else "kick"
	pending_attack = requested
	buffer_frames = INPUT_BUFFER_FRAMES


func prepare_move(direction: float, wants_guard: bool, wants_attack: bool, wants_kick := false) -> float:
	walking = false
	guarding = false
	if wants_attack or wants_kick:
		queue_attack("punch" if wants_attack else "kick")
	if stun_frames > 0 or attack_frame >= 0:
		return 0.0
	if wants_guard:
		guarding = true
		return 0.0
	if buffer_frames > 0:
		attack_variant = pending_attack
		attack_frame = 0
		kicking = attack_variant in ["kick", "front_kick", "roundhouse", "jump_kick"]
		attack_connected = false
		buffer_frames = 0
		return 0.0
	if not is_zero_approx(direction):
		walk_direction = direction * facing
	var speed := direction * SPEED * (0.83 if direction * facing < 0.0 else 1.0)
	walk_rate = absf(speed) / SOURCE_WALK_SPEED
	return speed


func attack_clip() -> String:
	if attack_variant.is_empty():
		return "kick" if kicking else "punch"
	return attack_variant


func first_attack_frame() -> int:
	if attack_variant in EXTRA_ATTACKS:
		return EXTRA_ATTACKS[attack_variant].start
	return KICK_FIRST_ACTIVE_FRAME if kicking else FIRST_ACTIVE_FRAME


func attack_duration() -> int:
	if attack_variant in EXTRA_ATTACKS:
		return EXTRA_ATTACKS[attack_variant].frames
	return KICK_FRAMES if kicking else ATTACK_FRAMES


func can_hit(rival: Node3D) -> bool:
	if attack_frame < 0 or attack_connected:
		return false
	var distance := (rival.position.x - position.x) * facing
	var last := KICK_LAST_ACTIVE_FRAME if kicking else LAST_ACTIVE_FRAME
	var reach := kick_reach if kicking else punch_reach
	if attack_variant in EXTRA_ATTACKS:
		last = EXTRA_ATTACKS[attack_variant].end
		reach = extra_reaches.get(attack_variant, EXTRA_ATTACKS[attack_variant].reach)
	return attack_frame >= first_attack_frame() and attack_frame <= last 		and distance >= 0.0 and distance <= reach


func attack_damage() -> int:
	if attack_variant in EXTRA_ATTACKS:
		return EXTRA_ATTACKS[attack_variant].damage
	return KICK_DAMAGE if kicking else DAMAGE

func take_hit(damage := DAMAGE) -> void:
	if guarding:
		return
	health = maxi(0, health - damage)
	stun_frames = HIT_STUN_FRAMES
	attack_variant = ""
	attack_frame = -1
	kicking = false
	walking = false


func advance_frame() -> void:
	buffer_frames = maxi(0, buffer_frames - 1)
	if attack_frame >= 0:
		attack_frame += 1
		if attack_frame >= attack_duration():
			attack_variant = ""
			attack_frame = -1
			kicking = false
	if stun_frames > 0:
		stun_frames -= 1


func update_visual(delta: float) -> void:
	visual.rotation.y = facing * PI / 2
	var state := "idle"
	if health == 0:
		state = "ko"
	elif stun_frames > 0:
		state = "hit"
	elif attack_frame >= 0:
		state = attack_clip()
	elif guarding:
		state = "guard"
	elif walking:
		state = "walk_forward" if walk_direction > 0.0 else "walk_backward"

	if animation_player:
		update_clip(state, delta)
		return
	if not front_arm:
		return

	# Show the face and chest at three quarters while keeping the punch aimed at the rival.
	visual.rotation.y = facing * 1.24
	walk_phase += delta
	var breath := sin(walk_phase * 5.0)
	var stride := sin(walk_phase * 16.0) * 0.30 if walking else 0.0
	var punch := 0.0
	var windup := 0.0
	if state == "punch":
		if attack_frame < FIRST_ACTIVE_FRAME:
			var buildup := float(attack_frame) / FIRST_ACTIVE_FRAME
			windup = sin(buildup * PI) * 0.55
			punch = pow(buildup, 3.0)
		else:
			punch = 1.0 - float(maxi(0, attack_frame - LAST_ACTIVE_FRAME)) / (ATTACK_FRAMES - LAST_ACTIVE_FRAME)
		visual.rotation.y = facing * lerpf(1.24, 1.55, punch)

	front_leg.rotation.x = -0.22 + stride
	rear_leg.rotation.x = 0.24 - stride
	front_arm.rotation.x = -0.66 - punch * 0.88 + windup - stride * 0.35
	rear_arm.rotation.x = -0.35 + punch * 0.32 + stride * 0.23
	front_elbow.rotation.x = lerpf(-1.48, -0.04, punch) + breath * 0.045
	rear_elbow.rotation.x = -1.76 + breath * 0.055
	head.rotation.x = 0.06 - punch * 0.08
	cloth_tail.rotation.x = 0.11 + breath * 0.15 - punch * 0.54
	visual.rotation.x = punch * 0.12 - windup * 0.12
	visual.position.y = breath * 0.012 + absf(stride) * 0.045 - 0.015
	visual.position.x = punch * facing * 0.22
	if state == "guard":
		front_arm.rotation.x = -1.20
		rear_arm.rotation.x = -0.92
		front_elbow.rotation.x = -1.05
		rear_elbow.rotation.x = -1.45
		head.rotation.x = 0.18
		visual.position.y -= 0.045
	elif state == "kick":
		var windup_frames := float(KICK_FIRST_ACTIVE_FRAME)
		var extension := smoothstep(0.0, windup_frames, attack_frame)
		extension *= 1.0 - smoothstep(KICK_LAST_ACTIVE_FRAME, KICK_FRAMES, attack_frame)
		front_leg.rotation.x -= extension * 1.35
		rear_leg.rotation.x -= extension * 0.16
		visual.rotation.x -= extension * 0.16
		visual.position.x = facing * extension * 0.23
		front_arm.rotation.x -= extension * 0.28
	elif state == "hit":
		var recoil := float(stun_frames) / HIT_STUN_FRAMES
		visual.rotation.x = -0.34 * recoil
		front_arm.rotation.x += recoil * 0.38
		rear_elbow.rotation.x += recoil * 0.44
	elif state == "ko":
		visual.rotation.x = -PI / 2
		visual.position.y = 0.33
		front_arm.rotation.x = -0.18
		rear_arm.rotation.x = 0.06
		front_elbow.rotation.x = -0.55
		rear_elbow.rotation.x = -0.18


func update_clip(state: String, delta: float) -> void:
	var clip: StringName = animation_names.get(state, &"")
	visual.position.y = 0.0
	visual.rotation.x = 0.0
	if clip.is_empty():
		if state.begins_with("walk"):
			walk_phase += delta * 14.0
			visual.position.y = absf(sin(walk_phase)) * 0.035
			visual.rotation.x = 0.04
		clip = animation_names.get("idle", &"")
		state = "idle"
	if clip.is_empty():
		return
	var length := animation_player.get_animation(clip).length
	if visual_state != state:
		begin_pose_blend()
		visual_state = state
		clip_time = 0.0
		animation_player.play(clip)
		animation_player.advance(0.0)
	else:
		clip_time += delta * (walk_rate if state.begins_with("walk") else 1.0)

	if attack_frame >= 0 and state == attack_clip():
		# The animation reaches the contact pose on the first damage frame.
		var first := first_attack_frame()
		var duration := attack_duration()
		var ratio: float = extra_contacts.get(state, kick_contact if kicking else punch_contact)
		var contact_time := ratio * length
		if attack_frame < first:
			clip_time = lerpf(0.0, contact_time, float(attack_frame) / first)
		else:
			clip_time = lerpf(contact_time, length, float(attack_frame - first) / (duration - first - 1))
	elif state == "idle" or state.begins_with("walk"):
		clip_time = fposmod(clip_time, length)
	else:
		clip_time = minf(clip_time, length)
	animation_player.seek(clip_time, true)
	blend_pose(delta)


func begin_pose_blend() -> void:
	previous_pose.clear()
	if not skeleton or visual_state.is_empty():
		return
	for index in skeleton.get_bone_count():
		previous_pose.append(skeleton.get_bone_pose(index))
	blend_time = 0.0


func blend_pose(delta: float) -> void:
	if previous_pose.is_empty():
		return
	blend_time += delta
	var weight := smoothstep(0.0, POSE_BLEND_SECONDS, blend_time)
	if weight >= 1.0:
		previous_pose.clear()
		return
	for index in skeleton.get_bone_count():
		var pose := previous_pose[index].interpolate_with(skeleton.get_bone_pose(index), weight)
		skeleton.set_bone_pose(index, pose)


func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var player := find_animation_player(child)
		if player:
			return player
	return null



func build_placeholder(accent: Color) -> void:
	is_akari = accent.r > accent.b
	var skin := Color("#f0b48c") if is_akari else Color("#cd8864")
	var suit := Color("#e7e0ce") if is_akari else Color("#21394c")
	var pants := Color("#381f34") if is_akari else Color("#142533")
	var trim := Color("#e5ad56") if is_akari else Color("#7cf8df")
	var armor := Color("#951b38") if is_akari else Color("#132531")
	var width := 0.24 if is_akari else 0.30

	# Lofted shapes leave room for joints without the mannequin-like box silhouette.
	var body := joint(visual, Vector3(0, 0.96, 0))
	var torso_rings := [
		Vector3(0.00, width * 0.68, 0.129),
		Vector3(0.14, width * 0.62, 0.135),
		Vector3(0.29, width * 0.87, 0.169),
		Vector3(0.45, width, 0.157),
		Vector3(0.52, width * 0.52, 0.104),
	]
	loft(body, torso_rings, suit)
	loft(body, [Vector3(-0.03, width * 0.72, 0.146), Vector3(0.05, width * 0.72, 0.148)], armor)
	loft(body, [Vector3(0.051, width * 0.723, 0.149), Vector3(0.082, width * 0.721, 0.151)], accent)
	sphere(body, Vector3(0, -0.035, 0), Vector3(width * 1.60, 0.22, 0.30), pants)
	sphere(body, Vector3(0, 0.52, 0), Vector3(0.15, 0.22, 0.15), skin)
	segment(body, Vector3(-width * 0.57, 0.46, 0.132), Vector3(0.058, 0.21, 0.176), 0.039, 0.031, armor, 5)
	segment(body, Vector3(width * 0.57, 0.45, 0.130), Vector3(-0.13, 0.075, 0.127), 0.036, 0.024, accent, 5)
	sphere(body, Vector3(0.067, 0.014, 0.149), Vector3(0.105, 0.087, 0.052), trim)
	cloth_tail = joint(body, Vector3(0.14, 0.01, 0.067))
	segment(cloth_tail, Vector3.ZERO, Vector3(0.035, -0.28, -0.04), 0.050, 0.027, accent, 4).scale.z = 0.34
	segment(cloth_tail, Vector3(-0.014, -0.10, -0.01), Vector3(-0.062, -0.29, 0.01), 0.043, 0.026, armor, 4).scale.z = 0.34

	head = joint(visual, Vector3(0, 1.52, 0.024))
	build_head(head, skin, accent, trim)

	var near_side := 1.0 if is_akari else -1.0
	front_arm = joint(visual, Vector3(near_side * width * 0.86, 1.41, 0.028))
	rear_arm = joint(visual, Vector3(-near_side * width * 0.86, 1.41, -0.028))
	front_arm.rotation.z = near_side * 0.13
	rear_arm.rotation.z = -near_side * 0.11
	front_elbow = build_arm(front_arm, skin, suit, armor, accent, trim)
	rear_elbow = build_arm(rear_arm, skin, suit, armor, accent, trim)

	front_leg = joint(visual, Vector3(near_side * width * 0.41, 0.94, 0.12))
	rear_leg = joint(visual, Vector3(-near_side * width * 0.41, 0.94, -0.12))
	front_leg.rotation.z = near_side * 0.055
	rear_leg.rotation.z = -near_side * 0.085
	for leg in [front_leg, rear_leg]:
		build_leg(leg, pants, armor, accent, trim)


func build_head(parent: Node3D, skin: Color, accent: Color, trim: Color) -> void:
	loft(parent, [
		Vector3(0.015, 0.063, 0.075), Vector3(0.058, 0.115, 0.107),
		Vector3(0.13, 0.145, 0.133), Vector3(0.24, 0.148, 0.136),
		Vector3(0.31, 0.106, 0.096), Vector3(0.34, 0.035, 0.033)
	], skin, 14)
	var hair := Color("#641c37") if is_akari else Color("#101b32")
	var hair_light := Color("#a6334b") if is_akari else Color("#223c63")
	var ink := Color("#22131e")
	sphere(parent, Vector3(0, 0.267, -0.034), Vector3(0.319, 0.213, 0.275), hair)
	sphere(parent, Vector3(0, 0.124, 0.126), Vector3(0.047, 0.046, 0.070), skin.lightened(0.08))
	sphere(parent, Vector3(0, 0.072, 0.109), Vector3(0.065, 0.012, 0.032), skin.darkened(0.36))
	for side in [-1.0, 1.0]:
		sphere(parent, Vector3(side * 0.139, 0.138, -0.016), Vector3(0.051, 0.075, 0.055), skin)
		var eye := sphere(parent, Vector3(side * 0.071, 0.166, 0.119), Vector3(0.086, 0.032, 0.024), Color("#fcf3e9"))
		eye.rotation.y = side * 0.38
		eye.rotation.z = side * 0.13
		sphere(parent, Vector3(side * 0.065, 0.165, 0.133), Vector3(0.026, 0.025, 0.012), accent.darkened(0.22))
		sphere(parent, Vector3(side * 0.066, 0.166, 0.138), Vector3(0.014, 0.019, 0.006), ink)
		segment(parent, Vector3(side * 0.035, 0.194, 0.131), Vector3(side * 0.109, 0.204, 0.103), 0.014, 0.009, hair, 5)
		if is_akari:
			sphere(parent, Vector3(side * 0.155, 0.108, -0.010), Vector3(0.020, 0.038, 0.022), trim)

	if is_akari:
		segment(parent, Vector3(-0.09, 0.32, 0.065), Vector3(0.13, 0.19, 0.115), 0.088, 0.008, hair_light, 6)
		segment(parent, Vector3(-0.13, 0.265, 0.024), Vector3(-0.151, 0.115, 0.059), 0.067, 0.009, hair, 6)
		sphere(parent, Vector3(0.027, 0.278, -0.173), Vector3(0.105, 0.094, 0.104), trim)
		segment(parent, Vector3(0.025, 0.28, -0.161), Vector3(0.093, 0.22, -0.283), 0.079, 0.066, hair_light, 8)
		segment(parent, Vector3(0.093, 0.22, -0.283), Vector3(0.10, 0.03, -0.306), 0.068, 0.007, hair, 8)
	else:
		segment(parent, Vector3(0, 0.26, 0.079), Vector3(-0.073, 0.20, 0.149), 0.074, 0.005, hair, 5)
		segment(parent, Vector3(0.021, 0.283, 0.045), Vector3(0.086, 0.47, -0.015), 0.108, 0.003, hair_light, 5)
		segment(parent, Vector3(-0.072, 0.274, 0.004), Vector3(-0.131, 0.418, -0.069), 0.097, 0.003, hair, 5)
		segment(parent, Vector3(0.074, 0.261, -0.061), Vector3(0.174, 0.375, -0.177), 0.093, 0.004, hair, 5)
		segment(parent, Vector3(-0.024, 0.289, -0.086), Vector3(-0.030, 0.407, -0.220), 0.097, 0.004, hair_light, 5)
		segment(parent, Vector3(-0.108, 0.230, -0.046), Vector3(-0.172, 0.285, -0.191), 0.074, 0.004, hair, 5)


func build_arm(upper: Node3D, skin: Color, suit: Color, armor: Color, accent: Color, trim: Color) -> Node3D:
	var shoulder := 0.116 if is_akari else 0.127
	sphere(upper, Vector3(0, -0.035, 0), Vector3(shoulder * 2.0, 0.230, shoulder * 1.90), armor if is_akari else suit)
	segment(upper, Vector3(0, -0.075, 0), Vector3(0, -0.295, 0), shoulder * 0.83, 0.067, skin)
	segment(upper, Vector3(0, -0.056, 0), Vector3(0, -0.090, 0), shoulder * 1.02, shoulder * 0.90, accent)
	if is_akari:
		sphere(upper, Vector3(0, -0.015, 0.088), Vector3(0.143, 0.133, 0.079), suit)
		sphere(upper, Vector3(0, -0.008, 0.124), Vector3(0.072, 0.064, 0.023), trim)
	var elbow := joint(upper, Vector3(0, -0.288, 0))
	sphere(elbow, Vector3.ZERO, Vector3(0.132, 0.131, 0.128), skin)
	segment(elbow, Vector3.ZERO, Vector3(0, -0.218, 0), 0.071, 0.051, skin)
	segment(elbow, Vector3(0, -0.085, 0), Vector3(0, -0.224, 0), 0.083, 0.067, armor)
	segment(elbow, Vector3(0, -0.099, 0), Vector3(0, -0.142, 0), 0.085, 0.078, trim if is_akari else accent)
	sphere(elbow, Vector3(0, -0.258, 0.016), Vector3(0.16, 0.154, 0.164), accent)
	sphere(elbow, Vector3(0.040, -0.248, 0.064), Vector3(0.069, 0.095, 0.076), accent.darkened(0.22))
	return elbow


func build_leg(leg: Node3D, pants: Color, armor: Color, accent: Color, trim: Color) -> void:
	segment(leg, Vector3.ZERO, Vector3(0, -0.396, 0.018), 0.134, 0.090, pants)
	sphere(leg, Vector3(0, -0.376, 0.029), Vector3(0.185, 0.194, 0.182), pants)
	segment(leg, Vector3(0, -0.400, 0.015), Vector3(0, -0.793, 0), 0.096, 0.063, pants)
	segment(leg, Vector3(0, -0.587, 0.002), Vector3(0, -0.837, 0.002), 0.096, 0.071, armor)
	sphere(leg, Vector3(0, -0.867, 0.064), Vector3(0.176, 0.106, 0.302), armor)
	sphere(leg, Vector3(0, -0.913, 0.064), Vector3(0.184, 0.049, 0.306), pants.darkened(0.40))
	segment(leg, Vector3(0, -0.595, 0), Vector3(0, -0.621, 0), 0.098, 0.095, accent)
	if is_akari:
		sphere(leg, Vector3(0, -0.389, 0.094), Vector3(0.169, 0.173, 0.081), accent)
		sphere(leg, Vector3(0, -0.384, 0.128), Vector3(0.106, 0.098, 0.030), armor)
		segment(leg, Vector3(0, -0.475, 0.084), Vector3(0, -0.734, 0.075), 0.063, 0.038, trim, 6)
	else:
		segment(leg, Vector3(0, -0.633, 0), Vector3(0, -0.650, 0), 0.093, 0.090, accent.darkened(0.3))


func joint(parent: Node3D, location: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = location
	parent.add_child(node)
	return node


func sphere(parent: Node3D, location: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 12
	mesh.rings = 8
	var part := mount_mesh(parent, mesh, color)
	part.position = location
	part.scale = dimensions
	return part


func segment(parent: Node3D, from: Vector3, to: Vector3, base: float, tip: float, color: Color, sides := 10) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = from.distance_to(to)
	mesh.bottom_radius = base
	mesh.top_radius = tip
	mesh.radial_segments = sides
	mesh.rings = 0
	var part := mount_mesh(parent, mesh, color)
	part.position = (from + to) * 0.5
	part.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	return part


func loft(parent: Node3D, rings: Array, color: Color, sides := 12) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring: Vector3 in rings:
		for side in range(sides):
			var angle := TAU * float(side) / sides
			var radial := Vector3(cos(angle), 0, sin(angle))
			vertices.append(Vector3(radial.x * ring.y, ring.x, radial.z * ring.z))
			normals.append(Vector3(radial.x / ring.y, 0, radial.z / ring.z).normalized())
	for row in range(rings.size() - 1):
		for side in range(sides):
			var first := row * sides + side
			var next := row * sides + (side + 1) % sides
			indices.append_array(PackedInt32Array([first, next, first + sides, next, next + sides, first + sides]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mount_mesh(parent, mesh, color)


func mount_mesh(parent: Node3D, mesh: Mesh, color: Color) -> MeshInstance3D:
	if not materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.73
		materials[color] = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = materials[color]
	parent.add_child(part)
	return part


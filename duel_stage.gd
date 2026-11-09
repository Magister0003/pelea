extends Node3D

const CAMERA_HEIGHT := 4.0
const CAMERA_PITCH := 0.12

var camera := Camera3D.new()
var camera_center := 0.0
var camera_width := 8.4
var shake_amount := 0.0
var shake_phase := 0.0
var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.seed = 38195
	_setup_lighting()
	_build_horizon()
	_build_courtyard()
	_build_shrine()

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.rotation.x = -CAMERA_PITCH
	add_child(camera)
	camera.current = true
	update_camera(-2.6, 2.6, 0.0)


func update_camera(left_x: float, right_x: float, delta: float) -> void:
	var viewport := get_viewport().get_visible_rect().size
	var aspect := viewport.x / maxf(viewport.y, 1.0)
	var center := (left_x + right_x) * 0.5
	var width := maxf(CAMERA_HEIGHT * aspect, absf(right_x - left_x) + 3.15)
	var weight := 1.0 - exp(-6.0 * delta) if delta > 0.0 else 1.0
	camera_center = lerpf(camera_center, center, weight)
	camera_width = lerpf(camera_width, width, weight)
	var safe_width := 2.0 * maxf(absf(left_x - camera_center), absf(right_x - camera_center)) + 2.2
	camera.size = maxf(camera_width, safe_width)
	shake_phase += delta * 76.0
	shake_amount = move_toward(shake_amount, 0.0, delta * 0.85) if delta > 0.0 else 0.0
	camera.position = Vector3(
		camera_center + sin(shake_phase) * shake_amount,
		2.95 + cos(shake_phase * 1.63) * shake_amount * 0.6,
		12.0
	)


func shake(strength: float) -> void:
	shake_amount = maxf(shake_amount, strength)


func _setup_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#10142b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#afbef9")
	environment.ambient_light_energy = 0.70
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -27, 0)
	key.light_color = Color("#ffe0ca")
	key.light_energy = 0.95
	key.shadow_enabled = true
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-9, 12, 0)
	fill.light_color = Color("#fff2e9")
	fill.light_energy = 0.4
	add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-22, 151, 0)
	rim.light_color = Color("#86c9ff")
	rim.light_energy = 0.75
	add_child(rim)
	_light(Vector3(-3.8, 1.5, -2.1), Color("#35c6db"), 2.0, 6.5)
	_light(Vector3(3.8, 1.5, -2.1), Color("#f86849"), 2.0, 6.5)


func _build_horizon() -> void:
	var sky := QuadMesh.new()
	sky.size = Vector2(54.0, 18.0)
	var shader := Shader.new()
	shader.code = """shader_type spatial;
	render_mode unshaded, cull_disabled, fog_disabled;

	void fragment() {
		vec3 night = vec3(0.04, 0.055, 0.13);
		vec3 dusk = vec3(0.26, 0.24, 0.41);
		float gradient = smoothstep(0.18, 0.59, UV.y);
		ALBEDO = mix(night, dusk, gradient);
	}"""
	var sky_material := ShaderMaterial.new()
	sky_material.shader = shader
	_place(sky, Vector3(0, 1.0, -22.0), sky_material)

	var moon := _unlit(Color("#ffc4a2"))
	var halo := _unlit(Color(0.95, 0.42, 0.35, 0.08))
	_disk(Vector3(-3.15, 1.90, -12.0), 0.69, moon)
	_disk(Vector3(-3.15, 1.90, -12.03), 0.84, halo)
	_disk(Vector3(-3.15, 1.90, -12.06), 1.00, halo)

	var stars := _unlit(Color("#cbd3fb"))
	for i in range(38):
		var size := random.randf_range(0.012, 0.035)
		_box(Vector3(random.randf_range(-19, 19), random.randf_range(0.15, 6), -19.0),
			Vector3(size, size, size), stars)

	_mountains(-16.0, -0.55, 1.85, Color("#333b61"))
	_mountains(-12.5, -0.60, 1.5, Color("#242d47"))
	_mountains(-8.8, -0.48, 1.25, Color("#172132"))
	_build_trees()


func _mountains(depth: float, baseline: float, height: float, color: Color) -> void:
	var silhouette := SurfaceTool.new()
	silhouette.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := -20.0
	var ridge := baseline + 0.35
	for i in range(28):
		var next_x := x + random.randf_range(1.1, 2.4)
		var next_ridge := baseline + random.randf_range(0.25, height)
		var lower_left := Vector3(x, baseline - 4.0, depth)
		var lower_right := Vector3(next_x, baseline - 4.0, depth)
		var upper_left := Vector3(x, ridge, depth)
		var upper_right := Vector3(next_x, next_ridge, depth)
		for vertex in [lower_left, upper_left, upper_right, lower_left, upper_right, lower_right]:
			silhouette.add_vertex(vertex)
		x = next_x
		ridge = next_ridge
	_place(silhouette.commit(), Vector3.ZERO, _unlit(color))


func _build_trees() -> void:
	var bark := _unlit(Color("#171827"))
	var canopy := _unlit(Color("#272138"))
	var leaf := SphereMesh.new()
	leaf.radius = 0.5
	leaf.height = 1.0
	leaf.radial_segments = 7
	leaf.rings = 3

	for side in [-1.0, 1.0]:
		var base := Vector3(side * 4.3, -0.1, -6.7)
		var knee := base + Vector3(-side * 0.29, 0.94, 0)
		var fork := knee + Vector3(side * 0.36, 0.67, 0)
		var inner_tip := knee + Vector3(-side * 0.9, 0.66, 0)
		var outer_tip := fork + Vector3(side * 0.95, 0.27, 0)
		_branch(base, knee, 0.13, bark)
		_branch(knee, fork, 0.095, bark)
		_branch(knee, inner_tip, 0.055, bark)
		_branch(fork, outer_tip, 0.06, bark)
		for point in [inner_tip, fork, outer_tip]:
			var cloud := _place(leaf, point + Vector3(0, 0.15, 0), canopy)
			cloud.scale = Vector3(random.randf_range(1.4, 1.95), 0.50, 0.53)


func _branch(start: Vector3, end: Vector3, radius: float, material: Material) -> void:
	var segment := CylinderMesh.new()
	segment.height = start.distance_to(end)
	segment.top_radius = radius * 0.56
	segment.bottom_radius = radius
	segment.radial_segments = 6
	var branch := _place(segment, (start + end) * 0.5, material)
	var axis := (end - start).normalized()
	branch.quaternion = Quaternion(Vector3.UP, axis)


func _build_courtyard() -> void:
	var stone := _material(Color("#262737"), 0.83)
	var stone_trim := _material(Color("#181a28"), 0.87)
	var gold := _material(Color("#ab6651"), 0.42, 0.23)
	var tiles: Array[StandardMaterial3D] = [
		_material(Color("#3c3b4c"), 0.72),
		_material(Color("#404154"), 0.72),
		_material(Color("#353747"), 0.72),
		_material(Color("#36394b"), 0.72),
	]

	_box(Vector3(0, -0.25, -0.3), Vector3(18.0, 0.43, 5.3), stone)
	_box(Vector3(0, -0.54, -0.3), Vector3(17.4, 0.16, 5.0), stone_trim)
	for row in range(4):
		var offset := 0.55 if row % 2 else 0.0
		for col in range(-8, 9):
			var tile := tiles[random.randi_range(0, tiles.size() - 1)]
			_box(Vector3(col * 1.1 + offset, -0.018, row * 1.12 - 2.0),
				Vector3(1.076, 0.036, 1.092), tile)
	for depth in [-2.54, 2.03]:
		_box(Vector3(0, -0.019, depth), Vector3(18.0, 0.039, 0.07), gold)
	_box(Vector3(0, -0.30, 2.36), Vector3(17.8, 0.045, 0.07), gold)

	var ring := TorusMesh.new()
	ring.inner_radius = 1.07
	ring.outer_radius = 1.096
	ring.rings = 48
	ring.ring_segments = 6
	var engraving := _place(ring, Vector3(0, 0.006, -0.25), gold)
	engraving.scale.y = 0.19
	for index in range(8):
		var angle := TAU * index / 8
		var marker := _box(Vector3(cos(angle) * 1.19, 0.005, sin(angle) * 1.19 - 0.25),
			Vector3(0.13, 0.012, 0.044), gold)
		marker.rotation.y = -angle


func _build_shrine() -> void:
	var lacquer := _material(Color("#6c3040"), 0.57)
	var dark_wood := _material(Color("#391f2d"), 0.7)
	var roof := _material(Color("#242337"), 0.65)
	var copper := _material(Color("#b1755b"), 0.38, 0.3)
	var cloth := _material(Color("#593044"), 0.92)
	var lantern := _material(Color("#ffc17a"), 0.5, 1.28)
	var teal_lantern := _material(Color("#6bdddf"), 0.5, 0.65)
	var stone := _material(Color("#303144"), 0.85)

	var depth := -3.6
	for x in [-2.23, 2.23]:
		_box(Vector3(x, 0.10, depth), Vector3(0.59, 0.29, 0.66), stone)
		_box(Vector3(x, 1.35, depth), Vector3(0.36, 2.65, 0.41), lacquer)
		_box(Vector3(x, 0.44, depth), Vector3(0.45, 0.34, 0.52), dark_wood)
		_box(Vector3(x, 1.98, depth + 0.22), Vector3(0.42, 0.07, 0.05), copper)
	_box(Vector3(0, 2.31, depth), Vector3(5.28, 0.19, 0.49), lacquer)
	_box(Vector3(0, 2.48, depth), Vector3(5.0, 0.09, 0.52), dark_wood)
	_box(Vector3(0, 2.58, depth + 0.12), Vector3(0.44, 0.48, 0.41), lacquer)
	_gate_roof(depth, roof, copper)

	for side in [-1.0, 1.0]:
		var beam_x: float = side * 5.5
		for x in [beam_x - 1.6, beam_x + 1.6]:
			_box(Vector3(x, 0.49, -2.95), Vector3(0.18, 0.98, 0.18), lacquer)
			_box(Vector3(x, 1.01, -2.95), Vector3(0.29, 0.08, 0.29), roof)
		_box(Vector3(beam_x, 0.66, -2.95), Vector3(3.2, 0.11, 0.11), dark_wood)

		var pole_x: float = side * 3.77
		_box(Vector3(pole_x, 0.89, -3.1), Vector3(0.11, 1.8, 0.12), dark_wood)
		_box(Vector3(pole_x + side * 0.34, 1.77, -3.1), Vector3(0.77, 0.06, 0.12), copper)
		var banner := _box(Vector3(pole_x + side * 0.43, 1.28, -3.1),
			Vector3(0.59, 0.88, 0.037), cloth)
		banner.rotation.z = side * 0.046
		_box(Vector3(pole_x + side * 0.43, 1.45, -3.07), Vector3(0.31, 0.05, 0.036), copper)
		_box(Vector3(pole_x + side * 0.43, 1.36, -3.07), Vector3(0.22, 0.03, 0.036), copper)

		var glow := teal_lantern if side < 0 else lantern
		_build_lantern(Vector3(side * 1.54, 1.89, depth + 0.09), glow, roof)
		_build_lantern(Vector3(side * 4.95, 0.93, -2.65), glow, roof)
		_build_lantern(Vector3(side * 7.58, 0.93, -2.65), glow, roof)
		_light(Vector3(side * 1.55, 1.8, depth + 0.55), glow.albedo_color, 0.65, 3.0)

	var embers := CPUParticles3D.new()
	embers.position = Vector3(0, 0.45, -1.15)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(6.5, 0.5, 1.8)
	embers.direction = Vector3(0.2, 1.0, 0)
	embers.gravity = Vector3.ZERO
	embers.initial_velocity_min = 0.1
	embers.initial_velocity_max = 0.28
	embers.lifetime = 5.0
	embers.amount = 24
	embers.preprocess = 5.0
	var ember := BoxMesh.new()
	ember.size = Vector3(0.021, 0.021, 0.021)
	ember.material = _unlit(Color("#e39b63"))
	embers.mesh = ember
	add_child(embers)


func _gate_roof(depth: float, roof: Material, copper: Material) -> void:
	var profile: Array[Vector2] = [
		Vector2(-2.95, 3.22), Vector2(-2.47, 2.96), Vector2(-1.72, 2.82),
		Vector2(-0.82, 2.78), Vector2(0, 2.77), Vector2(0.82, 2.78),
		Vector2(1.72, 2.82), Vector2(2.47, 2.96), Vector2(2.95, 3.22),
	]
	for i in range(profile.size() - 1):
		var start := profile[i]
		var end := profile[i + 1]
		var center := (start + end) * 0.5
		var direction := end - start
		var length := direction.length() + 0.018
		var segment := _box(Vector3(center.x, center.y, depth), Vector3(length, 0.18, 0.88), roof)
		segment.rotation.z = direction.angle()
		var trim := _box(Vector3(center.x, center.y + 0.082, depth + 0.45),
			Vector3(length, 0.044, 0.055), copper)
		trim.rotation.z = direction.angle()


func _build_lantern(center: Vector3, glass: Material, frame: Material) -> void:
	_box(center, Vector3(0.24, 0.32, 0.24), glass)
	for y in [-0.18, 0.18]:
		_box(center + Vector3(0, y, 0), Vector3(0.31, 0.07, 0.31), frame)
	for x in [-0.124, 0.124]:
		for z in [-0.124, 0.124]:
			_box(center + Vector3(x, 0, z), Vector3(0.024, 0.36, 0.024), frame)


func _light(center: Vector3, color: Color, energy: float, distance: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = center
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = distance
	add_child(lamp)


func _material(color: Color, roughness: float, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _unlit(color: Color) -> StandardMaterial3D:
	var material := _material(color, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _disk(center: Vector3, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.008
	mesh.radial_segments = 48
	var disk := _place(mesh, center, material)
	disk.rotation.x = PI / 2
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _box(center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _place(mesh, center, material)


func _place(mesh: Mesh, center: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	add_child(instance)
	return instance

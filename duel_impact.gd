extends Node3D

var punch_sound: AudioStreamWAV
var guard_sound: AudioStreamWAV


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	punch_sound = synthesize_hit(false)
	guard_sound = synthesize_hit(true)


func play_hit(point: Vector3, direction: float, blocked: bool) -> void:
	var impact := Node3D.new()
	add_child(impact)
	impact.position = point

	var bright := Color("#aaf5ff") if blocked else Color("#fff0a8")
	var outer := Color("#43b6ff") if blocked else Color("#ff6241")
	var bright_material := spark_material(bright)
	var outer_material := spark_material(outer)
	var flash := OmniLight3D.new()
	flash.light_color = outer
	flash.light_energy = 2.5
	flash.omni_range = 2.0
	impact.add_child(flash)

	var burst := impact.create_tween().set_parallel()
	burst.tween_property(flash, "light_energy", 0.0, 0.14)
	for index in range(12):
		var angle := TAU * index / 12.0
		var travel := Vector3(cos(angle), sin(angle), 0.0)
		var line := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12 + 0.12 * absf(cos(angle * 5.0)), 0.022, 0.022)
		line.mesh = mesh
		line.material_override = bright_material if index % 3 == 0 else outer_material
		line.rotation.z = angle
		line.position = travel * 0.09
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		impact.add_child(line)
		var destination := travel * (0.36 + 0.5 * absf(cos(angle * 3.0))) + Vector3(direction * 0.25, -0.11, 0)
		burst.tween_property(line, "position", destination, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		burst.tween_property(line, "scale", Vector3.ONE * 0.04, 0.22).set_delay(0.04)

	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.16
	core_mesh.height = 0.32
	core.mesh = core_mesh
	core.material_override = bright_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	impact.add_child(core)
	burst.tween_property(core, "scale", Vector3.ZERO, 0.1)
	burst.chain().tween_callback(impact.queue_free)

	if not punch_sound:
		return
	var player := AudioStreamPlayer.new()
	player.stream = guard_sound if blocked else punch_sound
	player.volume_db = -9.0
	impact.add_child(player)
	player.play()


func clear() -> void:
	for impact in get_children():
		impact.queue_free()


func spark_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func synthesize_hit(blocked: bool) -> AudioStreamWAV:
	const RATE := 22050
	var random := RandomNumberGenerator.new()
	random.seed = 543
	var samples := PackedByteArray()
	samples.resize(int(0.18 * RATE) * 2)
	var phase := 0.0
	for index in range(samples.size() / 2):
		var time := float(index) / RATE
		var frequency := 540.0 * exp(-time * 9.0) if blocked else 140.0 * exp(-time * 16.0)
		phase += TAU * frequency / RATE
		var tone := sin(phase) * exp(-time * 24.0)
		var noise := random.randf_range(-1.0, 1.0) * exp(-time * 54.0)
		var signal_value := (tone * 0.53 + noise * 0.45) * minf(time * 800.0, 1.0)
		samples.encode_s16(index * 2, int(signal_value * 24000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream

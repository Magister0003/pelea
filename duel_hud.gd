extends CanvasLayer

const LEFT_ACCENT := Color("#64eddd")
const RIGHT_ACCENT := Color("#ff846f")
const TEXT := Color("#fff6df")
const MUTED := Color("#b9c7d3")
const PANEL := Color("#101724e9")
const GOLD := Color("#edbd75")


class HudShade extends Control:
	func _draw() -> void:
		var fade := Color(0.018, 0.025, 0.05, 0.88)
		var clear := Color(fade, 0.0)
		var top := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, 142), Vector2(0, 142)])
		var bottom := PackedVector2Array([
			Vector2(0, size.y - 76), Vector2(size.x, size.y - 76), size, Vector2(0, size.y)
		])
		draw_polygon(top, PackedColorArray([fade, fade, clear, clear]))
		draw_polygon(bottom, PackedColorArray([clear, clear, fade, fade]))


class HealthBar extends ProgressBar:
	var accent := Color.WHITE
	var mirrored := false
	var trailing_value := 100.0
	var impact_delay := 0.0

	func _ready() -> void:
		value_changed.connect(health_changed)
		resized.connect(queue_redraw)
		set_process(false)

	func health_changed(new_value: float) -> void:
		if new_value >= trailing_value:
			trailing_value = new_value
			set_process(false)
		else:
			impact_delay = 0.14
			set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		impact_delay -= delta
		if impact_delay <= 0.0:
			trailing_value = move_toward(trailing_value, value, delta * 85.0)
			queue_redraw()
			if is_equal_approx(trailing_value, value):
				set_process(false)

	func _draw() -> void:
		var shell := bar_shape(1.0, 0.0)
		draw_colored_polygon(shell, Color("#0a101c"))
		draw_polyline(PackedVector2Array([shell[0], shell[1], shell[2], shell[3], shell[0]]), accent.darkened(0.48), 1.5, true)
		if trailing_value > 0.0:
			draw_colored_polygon(bar_shape(trailing_value / max_value, 3.0), Color("#f4cc8b"))
		if value > 0.0:
			var fill := bar_shape(value / max_value, 3.0)
			draw_polygon(fill, PackedColorArray([accent.lightened(0.27), accent.lightened(0.27), accent.darkened(0.3), accent.darkened(0.3)]))
			draw_line(fill[0], fill[1], Color(1, 1, 1, 0.55), 1.0, true)
		for mark in [0.25, 0.5, 0.75]:
			var segment := bar_shape(mark, 3.0)
			draw_line(segment[1], segment[2], Color(0.04, 0.08, 0.12, 0.32), 1.0, true)

	func bar_shape(ratio: float, inset: float) -> PackedVector2Array:
		var slant := 8.0
		var left := inset + slant
		var right := left + maxf(1.0, size.x - slant - inset * 2.0) * ratio
		var points := PackedVector2Array([
			Vector2(left, inset), Vector2(right, inset),
			Vector2(right - slant, size.y - inset), Vector2(left - slant, size.y - inset)
		])
		if mirrored:
			for index in range(points.size()):
				points[index].x = size.x - points[index].x
		return points


var left_health: HealthBar
var right_health: HealthBar
var score: Label
var timer: Label
var result_panel: CenterContainer
var result_text: Label
var left_rounds: Label
var right_rounds: Label
var display_font := FontVariation.new()
var result_animation: Tween


func _ready() -> void:
	display_font.base_font = ThemeDB.fallback_font
	display_font.variation_embolden = 1.15
	display_font.variation_transform = Transform2D(Vector2.RIGHT, Vector2(-0.15, 1.0), Vector2.ZERO)
	var overlay := HudShade.new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.resized.connect(overlay.queue_redraw)

	var top := HBoxContainer.new()
	overlay.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 30
	top.offset_top = 15
	top.offset_right = -30
	top.add_theme_constant_override("separation", 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE

	left_health = add_health(top, "KAI", LEFT_ACCENT, false)

	var round_info := VBoxContainer.new()
	round_info.custom_minimum_size.x = 138
	round_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_info.add_theme_constant_override("separation", 1)
	top.add_child(round_info)
	var game_label := make_label("D U E L O   L O C A L", 11, GOLD)
	game_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_info.add_child(game_label)
	timer = make_label("60", 47, TEXT, true)
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_info.add_child(timer)
	score = make_label("0   /   0", 13, MUTED)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_info.add_child(score)

	right_health = add_health(top, "AKARI", RIGHT_ACCENT, true)
	add_controls(overlay)
	add_result_panel(overlay)


func update_health(left: int, right: int) -> void:
	left_health.value = left
	right_health.value = right


func update_round(left_wins: int, right_wins: int) -> void:
	score.text = "%d   /   %d" % [left_wins, right_wins]
	left_rounds.text = round_marks(left_wins)
	right_rounds.text = round_marks(right_wins)


func set_time(seconds: int) -> void:
	timer.text = "%02d" % seconds
	timer.modulate = RIGHT_ACCENT if seconds <= 10 else Color.WHITE


func show_result(message: String) -> void:
	if result_animation:
		result_animation.kill()
	result_text.text = message
	result_panel.modulate.a = 0.0
	result_panel.show()
	result_animation = create_tween()
	result_animation.tween_property(result_panel, "modulate:a", 1.0, 0.18)


func clear_result() -> void:
	if result_animation:
		result_animation.kill()
	result_panel.hide()


func add_health(parent: HBoxContainer, fighter_name: String, accent: Color, mirrored: bool) -> HealthBar:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)
	parent.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	title_row.add_theme_constant_override("separation", 10)
	column.add_child(title_row)
	var player_tag := make_label("P2" if mirrored else "P1", 12, accent, true)
	player_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var caption := make_label(fighter_name, 35, TEXT, true)
	if mirrored:
		title_row.add_child(caption)
		title_row.add_child(player_tag)
	else:
		title_row.add_child(player_tag)
		title_row.add_child(caption)

	var bar := HealthBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size.y = 23
	bar.show_percentage = false
	bar.accent = accent
	bar.mirrored = mirrored
	bar.value = 100
	bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	bar.add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	column.add_child(bar)

	var marks := make_label(round_marks(0), 17, accent)
	if mirrored:
		marks.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right_rounds = marks
	else:
		left_rounds = marks
	column.add_child(marks)
	return bar


func round_marks(wins: int) -> String:
	return ("◆" if wins >= 1 else "◇") + "  " + ("◆" if wins >= 2 else "◇")


func add_controls(overlay: Control) -> void:
	var bottom := HBoxContainer.new()
	overlay.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 30
	bottom.offset_top = -48
	bottom.offset_right = -30
	bottom.offset_bottom = -19
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left_controls := make_label("P1   A/D mover   ·   F golpe · H fuerte · E patada · G guardia", 13, LEFT_ACCENT)
	left_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(left_controls)
	var restart_control := make_label("R REINICIAR\nPATADA + DIRECCIÓN PARA VARIAR", 10, MUTED, true)
	restart_control.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(restart_control)
	var right_controls := make_label("P2   ←/→ mover   ·   K golpe · O fuerte · I patada · L guardia", 13, RIGHT_ACCENT)
	right_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(right_controls)


func add_result_panel(overlay: Control) -> void:
	result_panel = CenterContainer.new()
	overlay.add_child(result_panel)
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = GOLD
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 12
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 17
	style.content_margin_bottom = 19
	card.add_theme_stylebox_override("panel", style)
	result_panel.add_child(card)
	result_text = make_label("", 29, TEXT, true)
	result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(result_text)
	clear_result()


func make_label(content: String, font_size: int, color: Color, display := false) -> Label:
	var label := Label.new()
	label.text = content
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#090b15"))
	label.add_theme_constant_override("outline_size", 5)
	if display:
		label.add_theme_font_override("font", display_font)
	return label

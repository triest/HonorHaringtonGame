extends CanvasLayer
## MissionEditorPanel
##
## 2026-09-28 (user: "редактор миссий, чтобы можно было соотношение и
## типы кораблей сторон выбирать"): a pre-battle setup screen. Two
## columns (own force / enemy force), one row per ShipClasses.ORDER class
## with a -/+ stepper, a live summary (ships / missile tubes / point
## defense mounts) per side, a "Случайный состав" convenience randomizer,
## and "В бою" -- confirming calls `on_confirm` with a setup Dictionary in
## exactly the shape DemoScenario.build() expects.
##
## Shown ON TOP of an already-built default mission (main.gd always builds
## ShipClasses.default_setup() first, so every existing headless caller --
## probes, screenshots, tests -- sees ships immediately and is unaffected
## by this panel's mere existence); confirming REBUILDS the world with the
## chosen composition via main.gd's own rebuild path. Pure UI -- invents no
## new simulation mechanics, only assembles the setup Dictionary that
## DemoScenario/ShipClasses already define.
class_name MissionEditorPanel

const UiTheme = preload("res://scripts/ui_theme.gd")

var on_confirm: Callable = Callable()

## 2026-09-29: the chosen scenario (Scenarios.ORDER id). Picking one also
## loads that scenario's default force composition into the steppers below
## (still fully editable afterwards).
var scenario_id: String = "intercept"
var _scenario_buttons: Dictionary = {}  # scenario id -> Button
var _tagline_label: Label

var counts: Dictionary = {"red": {}, "blue": {}}  # side -> class_id -> int
var _count_labels: Dictionary = {"red": {}, "blue": {}}  # side -> class_id -> Label
var _summary_labels: Dictionary = {}  # side -> Label
var _panel: PanelContainer

func _ready() -> void:
	layer = 30
	for side in ["red", "blue"]:
		for cid in ShipClasses.ORDER:
			counts[side][cid] = 0
	var default_setup: Dictionary = ShipClasses.default_setup()
	for side in ["red", "blue"]:
		for entry in default_setup.get(side, []):
			counts[side][String(entry["class_id"])] = int(entry["count"])

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	var sb := UiTheme.panel_stylebox()
	sb.set_content_margin_all(18)
	sb.bg_color = Color(0.02, 0.05, 0.07, 0.97)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_panel.add_child(root)

	var title := Label.new()
	title.text = "РЕДАКТОР МИССИИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Выберите состав эскадр перед боем -- количество и класс кораблей каждой стороны."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR_DIM)
	root.add_child(sub)

	var scen_row := HFlowContainer.new()
	scen_row.add_theme_constant_override("h_separation", 6)
	scen_row.add_theme_constant_override("v_separation", 6)
	scen_row.alignment = FlowContainer.ALIGNMENT_CENTER
	root.add_child(scen_row)
	var scen_lbl := Label.new()
	scen_lbl.text = "Сценарий:"
	scen_lbl.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR_DIM)
	scen_row.add_child(scen_lbl)
	var scen_group := ButtonGroup.new()
	for scen_id in Scenarios.ORDER:
		var sid_cap: String = scen_id
		var b: Button = _btn(scen_row, Scenarios.short_of(sid_cap), func(): _select_scenario(sid_cap), Scenarios.tagline_of(sid_cap))
		b.toggle_mode = true
		b.button_group = scen_group
		var pressed_sb := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR)
		pressed_sb.set_content_margin_all(5)
		pressed_sb.bg_color = Color(0.15, 0.35, 0.4, 0.95)
		b.add_theme_stylebox_override("pressed", pressed_sb)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		_scenario_buttons[sid_cap] = b
	_tagline_label = Label.new()
	_tagline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tagline_label.custom_minimum_size = Vector2(700, 0)
	_tagline_label.add_theme_font_size_override("font_size", 13)
	_tagline_label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	root.add_child(_tagline_label)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	root.add_child(columns)
	_build_column(columns, "red", "Мантикора (вы)", UiTheme.ACCENT_COLOR)
	_build_column(columns, "blue", "Хевен (противник)", Color(1.0, 0.45, 0.4))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(buttons)
	_btn(buttons, "Случайный сценарий", _randomize_scenario, "Случайный сценарий с его составом сил")
	_btn(buttons, "Случайный состав", _randomize, "Случайно подобрать оба состава")
	_btn(buttons, "По умолчанию", _reset_default, "Состав по умолчанию выбранного сценария")
	var start := _btn(buttons, "В бой", _confirm)
	start.add_theme_font_size_override("font_size", 18)
	start.custom_minimum_size = Vector2(160, 44)

	_refresh()
	# Centre the panel on screen (2026-09-29: it used to sit in the
	# top-left corner); sizes are only known after the first layout pass.
	call_deferred("_center")
	get_viewport().size_changed.connect(_center)

func _center() -> void:
	if _panel == null or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_panel.position = ((vp - _panel.size) * 0.5).max(Vector2.ZERO)

func _build_column(parent: Node, side: String, title_text: String, color: Color) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(340, 0)
	parent.add_child(col)

	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", color)
	col.add_child(t)

	for cid in ShipClasses.ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)

		var lbl := Label.new()
		lbl.text = ShipClasses.label(cid).capitalize()
		lbl.custom_minimum_size = Vector2(150, 0)
		lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(lbl)

		_step_btn(row, "-", side, cid, -1)
		var cnt := Label.new()
		cnt.custom_minimum_size = Vector2(28, 0)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cnt.add_theme_font_size_override("font_size", 15)
		cnt.add_theme_color_override("font_color", color)
		row.add_child(cnt)
		_count_labels[side][cid] = cnt
		_step_btn(row, "+", side, cid, 1)

	var summary := Label.new()
	summary.add_theme_font_size_override("font_size", 12)
	summary.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR_DIM)
	col.add_child(summary)
	_summary_labels[side] = summary

func _step_btn(parent: Node, text: String, side: String, cid: String, delta: int) -> void:
	var b: Button = _btn(parent, text, func(): _step(side, cid, delta))
	b.custom_minimum_size = Vector2(30, 30)

func _btn(parent: Node, text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	var normal := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR_DIM)
	normal.set_content_margin_all(5)
	var hover := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR)
	hover.set_content_margin_all(5)
	hover.bg_color = Color(0.08, 0.2, 0.25, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _step(side: String, cid: String, delta: int) -> void:
	var cur: int = int(counts[side][cid])
	var total: int = ShipClasses.side_total(_setup_side(side))
	if delta > 0 and total >= ShipClasses.MAX_PER_SIDE_COUNT:
		return
	counts[side][cid] = maxi(0, cur + delta)
	_refresh()

func _setup_side(side: String) -> Array:
	var out: Array = []
	for cid in ShipClasses.ORDER:
		var n: int = int(counts[side][cid])
		if n > 0:
			out.append({"class_id": cid, "count": n})
	return out

func _refresh() -> void:
	for side in ["red", "blue"]:
		for cid in ShipClasses.ORDER:
			_count_labels[side][cid].text = str(counts[side][cid])
		var s: Array = _setup_side(side)
		var ships: int = ShipClasses.side_total(s)
		var tubes: int = ShipClasses.side_stat_sum(s, "tubes")
		var pd: int = ShipClasses.side_stat_sum(s, "pd_mounts")
		var cm_mult: float = float(Scenarios.get_data(scenario_id)["%s_cm_mult" % side])
		var cm: int = int(round(float(ShipClasses.side_cm_stock(s)) * cm_mult))
		_summary_labels[side].text = "кораблей: %d  ·  труб: %d  ·  ПРО: %d  ·  контрракет: %d" % [ships, tubes, pd, cm]
	for scen_key in _scenario_buttons.keys():
		_scenario_buttons[scen_key].set_pressed_no_signal(scen_key == scenario_id)
	if _tagline_label != null:
		_tagline_label.text = "%s — %s" % [Scenarios.title_of(scenario_id), Scenarios.tagline_of(scenario_id)]

func _select_scenario(id: String) -> void:
	scenario_id = id
	_apply_setup(Scenarios.default_setup_for(id))
	_refresh()

func _randomize_scenario() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_select_scenario(Scenarios.ORDER[rng.randi() % Scenarios.ORDER.size()])

func _apply_setup(d: Dictionary) -> void:
	for side in ["red", "blue"]:
		for cid in ShipClasses.ORDER:
			counts[side][cid] = 0
		for entry in d.get(side, []):
			counts[side][String(entry["class_id"])] = int(entry["count"])

func _reset_default() -> void:
	_apply_setup(Scenarios.default_setup_for(scenario_id))
	_refresh()

func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for side in ["red", "blue"]:
		for cid in ShipClasses.ORDER:
			counts[side][cid] = 0
		var remaining: int = rng.randi_range(3, ShipClasses.MAX_PER_SIDE_COUNT)
		while remaining > 0:
			var cid: String = ShipClasses.ORDER[rng.randi() % ShipClasses.ORDER.size()]
			counts[side][cid] += 1
			remaining -= 1
	_refresh()

func _confirm() -> void:
	var setup: Dictionary = {"scenario": scenario_id, "red": _setup_side("red"), "blue": _setup_side("blue")}
	# Guard against an empty side (a degenerate, ship-less mission) --
	# fall back to the default composition for that side rather than
	# handing DemoScenario an empty force.
	if ShipClasses.side_total(setup["red"]) <= 0:
		setup["red"] = Scenarios.default_setup_for(scenario_id)["red"]
	if ShipClasses.side_total(setup["blue"]) <= 0:
		setup["blue"] = Scenarios.default_setup_for(scenario_id)["blue"]
	visible = false
	if on_confirm.is_valid():
		on_confirm.call(setup)

extends CanvasLayer
## CommandBar
##
## 2026-09-27 live user report: "no ship control, no course plotting, no
## order panel", "add interface buttons", "make the radar enlargeable".
## A bottom command bar of real clickable buttons (styled with UiTheme)
## so every order in the demo is reachable with the mouse, not only via
## hidden hotkeys. Four groups:
##
##   ВРЕМЯ      pause / 1x / 5x / 25x / 100x + clock readout
##   ВЫБОР      whole squadron / flagship / next enemy target / group (G)
##   МАНЕВР     course 15 deg left/right, speed +/-, full thrust, drift,
##              withdraw, hold formation
##   ОГОНЬ      attack designated target, weapons free, hold fire,
##              PD auto/hold
##   РАДАР      enlarge/shrink the tactical plot, zoom its range
##
## Order routing (same §56.3 item I rule as MoveOrderController): a
## selection that is a formation's ENTIRE membership gets one formation
## order via the guide (the whole line turns together, stations kept);
## any other own ship gets its own IndividualOrder via the comm-delayed
## transmit_individual_order_now. Nothing here invents new simulation
## mechanics -- every button maps onto an existing world API.
##
## 2026-09-28 (user: "наведи порядок с панелью приказов, упорядочи,
## сделай переключателями"): the bar was one long wrapping row of ~35
## individual buttons with a group label wedged inline before each
## cluster -- hard to scan, and several genuinely ON/OFF settings (PD
## hold, weapons free, hold-the-line, ship attitude, time scale, radar
## enlarge) were pairs/sets of one-shot buttons with no visible "which
## one is active now" state (time scale faked it with a manual .modulate
## tint). Reorganized into one row PER GROUP (a small dim title above its
## own HFlowContainer, so groups are visually separated instead of
## running together) and every mutually-exclusive/ON-OFF control is now a
## real Godot toggle button (toggle_mode = true, using the SAME
## normal/hover/pressed styleboxes _btn() already had -- the "pressed"
## stylebox was defined from the start but never visible before because
## nothing had toggle_mode on). sync() now drives every toggle's visual
## state from the actual world/selection state each frame, via
## set_pressed_no_signal() so refreshing the display never re-fires the
## order it displays. Every callback, hotkey and order-routing function
## below is UNCHANGED -- this is a UI/structure pass, not a logic change.
class_name CommandBar

const UiTheme = preload("res://scripts/ui_theme.gd")

const TIME_SCALES: Array = [1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2000.0, 5000.0, 20000.0, 100000.0]
## Auto-slowdown: while any missile is within this distance of its target,
## time is capped to SLOWDOWN_CAP so the terminal phase (PD, hits) can be
## watched and the simulation keeps its fine tick there. Toggleable.
const SLOWDOWN_RANGE_M: float = 1.5e9
const SLOWDOWN_CAP: float = 10.0
## Перемотка до сближения (TODO): адаптивный множитель, пока расстояние до
## противника больше WARP_STOP_RANGE_M; затем возврат к WARP_RESUME_SCALE.
const WARP_STOP_RANGE_M: float = 6.0e8        # 1.5 x ENERGY_RANGE_M (4e8)
const WARP_TARGET_REAL_S: float = 5.0
const WARP_MAX_DT_MULT: int = 600             # тик до 10 с симуляции при перемотке
const WARP_RESUME_SCALE: float = 10.0
const TURN_STEP_RAD: float = deg_to_rad(15.0)
const SPEED_STEP_MPS: float = 50_000.0      # 50 km/s per click
const FULL_THRUST_FRACTION: float = 0.8     # same 80% margin DemoScenario uses
const WITHDRAW_SPEED_MPS: float = 400_000.0 # 400 km/s away from the enemy

var world: SimulationWorld
var selection: SelectionState
var player_team: String = ""
var command_group_controller: CommandGroupController
var tactical_plot: TacticalPlot
var camera_focus_controller: CameraFocusController
## Order acknowledgements are also written to the battle log (set by main).
var battle_log = null

var auto_slowdown: bool = true
var warp_active: bool = false
var _warp_btn: Button
var _warp_prev_d: float = -1.0
var _warp_prev_t: float = 0.0
var _warp_saved_dt_mult: int = 1
var _slow_btn: Button
var _slowdown_active: bool = false
var _clock_label: Label
var _sel_label: Label
var _fire_label: Label
var _time_buttons: Dictionary = {}  # scale -> Button
var _attitude_buttons: Dictionary = {}  # mode -> Button
var _pd_btn: Button
var _fire_btn: Button
var _hold_btn: Button
var _cm_btn: Button
var _radar_btn: Button
var _panel: PanelContainer
var _status_text: String = ""
var _status_until_ms: int = 0

func _ready() -> void:
	layer = 5
	_panel = PanelContainer.new()
	_panel.name = "CommandBarPanel"
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_stylebox())
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 8
	_panel.offset_right = -8
	_panel.offset_bottom = -8
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	_panel.add_child(root)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 24)
	root.add_child(status_row)
	_clock_label = _mk_label(status_row)
	_sel_label = _mk_label(status_row)
	_fire_label = _mk_label(status_row)

	var groups := VBoxContainer.new()
	groups.add_theme_constant_override("separation", 3)
	root.add_child(groups)

	var time_row := _group_row(groups, "ВРЕМЯ")
	var time_group := ButtonGroup.new()
	_time_buttons[0.0] = _toggle_btn(time_row, "Пауза", Callable(self, "_on_time_toggled").bind(0.0), "Space", time_group)
	for s in TIME_SCALES:
		var sc: float = s
		_time_buttons[sc] = _toggle_btn(time_row, "x%d" % int(sc), Callable(self, "_on_time_toggled").bind(sc), "", time_group)
	_slow_btn = _toggle_btn(time_row, "Авто-замедл.: ВКЛ", _on_slowdown_toggled, "Замедлять до x10, пока ракеты подлетают к целям")
	_slow_btn.set_pressed_no_signal(auto_slowdown)
	_warp_btn = _toggle_btn(time_row, "Перемотка до сближения", _on_warp_toggled, "Сильно ускоряет время, пока противник дальше дальности энергооружия, затем возвращает x10")

	var select_row := _group_row(groups, "ВЫБОР")
	_btn(select_row, "Эскадра", _select_squadron, "Выделить все свои корабли")
	_btn(select_row, "Флагман", _select_flagship)
	_btn(select_row, "Цель >", _cycle_target, "Следующая вражеская цель")
	_btn(select_row, "Группа (G)", _make_group, "Сделать отряд из выделения")

	var camera_row := _group_row(groups, "КАМЕРА")
	_btn(camera_row, "Крупно (F)", func(): _cam("close"), "Камера к выделенному кораблю вплотную (или двойной клик по кораблю)")
	_btn(camera_row, "Эскадра (F2)", func(): _cam("squadron"), "Вся своя эскадра")
	_btn(camera_row, "Весь бой (F1)", func(): _cam("all"), "Обе стороны целиком")
	_btn(camera_row, "← Назад (Esc)", func(): _cam("back"), "Вернуться к предыдущему виду")

	var maneuver_row := _group_row(groups, "МАНЕВР")
	_btn(maneuver_row, "< Курс 15°", func(): _turn(1.0))
	_btn(maneuver_row, "Курс 15° >", func(): _turn(-1.0))
	_btn(maneuver_row, "Скорость +", func(): _change_speed(SPEED_STEP_MPS), "+50 км/с")
	_btn(maneuver_row, "Скорость -", func(): _change_speed(-SPEED_STEP_MPS), "-50 км/с")
	_btn(maneuver_row, "Полный ход", _full_thrust, "Разгон 80% по текущему курсу")
	_btn(maneuver_row, "Дрейф", _drift, "Двигатели на ноль, держать строй")
	_btn(maneuver_row, "Отход", _withdraw, "Развернуть от противника")

	var attitude_row := _group_row(groups, "ПОЛОЖЕНИЕ")
	var attitude_group := ButtonGroup.new()
	_attitude_buttons["auto"] = _toggle_btn(attitude_row, "Авто-крен", Callable(self, "_on_attitude_toggled").bind("auto"), "Бортом к врагу для стрельбы; при подлёте ракет — крен клином к залпу (успевает не всегда)", attitude_group)
	_attitude_buttons["broadside"] = _toggle_btn(attitude_row, "Бортом", Callable(self, "_on_attitude_toggled").bind("broadside"), "Всегда бортом: максимум огня, но борт (боковая стена) под ударом", attitude_group)
	_attitude_buttons["wedge"] = _toggle_btn(attitude_row, "Клином", Callable(self, "_on_attitude_toggled").bind("wedge"), "Клин к противнику: ракеты и лучи блокируются, но свои трубы и борт закрыты — огня нет", attitude_group)
	_attitude_buttons["course"] = _toggle_btn(attitude_row, "Нос по курсу", Callable(self, "_on_attitude_toggled").bind("course"), "Походное положение", attitude_group)

	var fire_row := _group_row(groups, "ОГОНЬ")
	_btn(fire_row, "Атаковать цель", _attack, "Огонь по назначенной цели")
	_btn(fire_row, "Добить слабейшего", _attack_weakest, "Все выделенные корабли переключаются на самый повреждённый обнаруженный корабль противника -- концентрация огня реально ускоряет уничтожение эскадры противника")
	_fire_btn = _toggle_btn(fire_row, "Огонь: свободный", _on_fire_toggled, "Переключатель: свободный огонь / прекратить огонь")
	_pd_btn = _toggle_btn(fire_row, "ПРО: авто", _on_pd_toggled, "Переключатель: ПРО автоматически / ПРО стоп")
	_cm_btn = _btn(fire_row, "ПРТР: авто", _cycle_cm_policy, "Контрракеты выделенных кораблей (запас конечный!): АВТО — по любой ракете, ТОЛЬКО ФЛАГМАН — по ракетам на флагман, ТОЛЬКО ЗАЛПЫ — по залпам от 10 ракет, СТОП — беречь. Нажатие переключает по кругу.")
	_hold_btn = _toggle_btn(fire_row, "Драться до конца: выкл", _on_hold_toggled, "Приказ игнорировать критические повреждения корпуса: корабль продолжает стрелять и НЕ уходит на автоматический отход, пока экипаж может держать боевой пост")

	var radar_row := _group_row(groups, "РАДАР")
	_radar_btn = _toggle_btn(radar_row, "Радар ⤢", func(_p): _toggle_radar(), "Увеличить/уменьшить радар (M)")
	_btn(radar_row, "Радар +", func(): _radar_zoom(1.6), "Приблизить (колесо над радаром)")
	_btn(radar_row, "Радар -", func(): _radar_zoom(1.0 / 1.6))
	_btn(radar_row, "Радар авто", func(): _radar_zoom(0.0), "Автомасштаб")

func _mk_label(parent: Node) -> Label:
	var l := Label.new()
	# Long status text must never widen the bar past the screen (it did,
	# pushing the right-hand buttons off-screen).
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(80, 0)
	l.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR)
	l.add_theme_font_size_override("font_size", 15)
	parent.add_child(l)
	return l

## One row PER GROUP: a small dim title above its own HFlowContainer, so
## the bar reads as clearly separated clusters (Наведи порядок) instead
## of one long inline-labelled row. Still an HFlowContainer per row, so a
## group with many buttons (ВРЕМЯ) still wraps gracefully on a narrow
## window instead of being clipped.
func _group_row(parent: Node, title: String) -> HFlowContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 1)
	parent.add_child(wrap)
	var l := Label.new()
	l.text = title
	l.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR_DIM)
	l.add_theme_font_size_override("font_size", 11)
	wrap.add_child(l)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	wrap.add_child(row)
	return row

func _btn(parent: Node, text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE  # never steal keyboard hotkeys
	b.add_theme_font_size_override("font_size", 14)
	var normal := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR_DIM)
	normal.set_content_margin_all(5)
	var hover := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR)
	hover.set_content_margin_all(5)
	hover.bg_color = Color(0.08, 0.2, 0.25, 0.95)
	var pressed := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR)
	pressed.set_content_margin_all(5)
	pressed.bg_color = Color(0.15, 0.35, 0.4, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

## Same look as _btn(), but a real toggle: `cb` receives the button's new
## pressed state on every click (toggle_mode buttons still fire once per
## click). Active state reads from the SAME "pressed" stylebox _btn()
## already defined -- toggle_mode is what makes Godot actually show it
## while button_pressed is true, instead of only flashing on mouse-down.
## `group`, when given, makes Godot itself keep exactly one button in the
## group pressed (used for ВРЕМЯ/ПОЛОЖЕНИЕ, which are mutually exclusive
## by nature) instead of relying on the next sync() tick to correct it.
func _toggle_btn(parent: Node, text: String, cb: Callable, tip: String = "", group: ButtonGroup = null) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	if group != null:
		b.button_group = group
	b.add_theme_font_size_override("font_size", 14)
	var normal := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR_DIM)
	normal.set_content_margin_all(5)
	var hover := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR)
	hover.set_content_margin_all(5)
	hover.bg_color = Color(0.08, 0.2, 0.25, 0.95)
	var pressed := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR)
	pressed.set_content_margin_all(5)
	pressed.bg_color = Color(0.15, 0.35, 0.4, 0.95)
	var hover_pressed := UiTheme.panel_stylebox(UiTheme.ACCENT_COLOR)
	hover_pressed.set_content_margin_all(5)
	hover_pressed.bg_color = Color(0.2, 0.42, 0.48, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", hover_pressed)
	b.add_theme_color_override("font_color", UiTheme.ACCENT_COLOR)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.toggled.connect(cb)
	parent.add_child(b)
	return b

## Height of the bar in pixels, so other panels (WeaponPanel, radar) can
## stay above it.
func get_height() -> float:
	return _panel.size.y + 8.0 if _panel != null else 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				_set_time(1.0 if world.clock.paused else 0.0)
				get_viewport().set_input_as_handled()
			KEY_M:
				_toggle_radar()
				get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT, KEY_PERIOD:
				_step_time(1)
			KEY_BRACKETLEFT, KEY_COMMA:
				_step_time(-1)


# ---------------------------------------------------------------- status

func _process(_delta: float) -> void:
	sync()

func sync() -> void:
	if world == null:
		return
	var clk: SimClock = world.clock
	var t: int = int(world.world_sim_time)
	_update_warp()
	_slowdown_active = auto_slowdown and _missiles_closing()
	clk.scale_cap = SLOWDOWN_CAP if _slowdown_active else 0.0
	var speed_txt: String = "ПАУЗА" if clk.paused else "x%d (факт x%.0f)" % [int(clk.time_scale), clk.effective_time_scale]
	if _slowdown_active and not clk.paused and clk.time_scale > SLOWDOWN_CAP:
		speed_txt += " [замедление: ракеты у целей]"
	var sep_txt: String = ""
	var d: float = _enemy_distance_m()
	if d > 0.0:
		sep_txt = "   до противника: %s" % _fmt_km(d)
	_clock_label.text = "T+%02d:%02d:%02d   %s%s" % [t / 3600, (t / 60) % 60, t % 60, speed_txt, sep_txt]
	for k in _time_buttons.keys():
		var active: bool = (k == 0.0 and clk.paused) or (not clk.paused and is_equal_approx(k, clk.time_scale))
		_time_buttons[k].set_pressed_no_signal(active)

	var own: Array = _own_selected()
	if own.is_empty():
		_sel_label.text = "Выделено: ничего (кликните свой корабль/эскадру или 'Эскадра')"
	else:
		var sp: float = 0.0
		for sid in own:
			sp += world.ships[sid].velocity.length()
		sp /= float(own.size())
		var nm: Array = []
		for sid in own:
			nm.append(ShipNames.of(sid))
		_sel_label.text = "Выделено: %s   скорость %.0f км/с" % [", ".join(nm), sp / 1000.0]
	var tgt: String = selection.designated_target_id if selection != null else ""
	var msl: int = 0
	for mid in world.missiles.keys():
		if world.missiles[mid].is_active() and not world.counter_missile_ids.has(mid) and String(world.teams.get(world.missile_owners.get(mid, ""), "")) != player_team:
			msl += 1
	var ammo_own: int = 0
	var ammo_en: int = 0
	for sid in world.missile_tubes.keys():
		if world.ships.has(sid) and world.ships[sid].is_wreck:
			continue
		for tube in world.missile_tubes[sid]:
			if String(world.teams.get(sid, "")) == player_team:
				ammo_own += tube.ammo_count
			else:
				ammo_en += tube.ammo_count
	var cm_own: int = 0
	for csid in world.cm_tubes.keys():
		if String(world.teams.get(csid, "")) == player_team and world.ships.has(csid) and not world.ships[csid].is_wreck:
			cm_own += world.cm_ammo_remaining(csid)
	_fire_label.text = "Цель: %s   входящих ракет: %d   боезапас: %d (у врага ~%d)   контрракет: %d%s" % [ShipNames.of(tgt) if tgt != "" else "—", msl, ammo_own, ammo_en, cm_own, ("   " + _status_text) if Time.get_ticks_msec() < _status_until_ms else ""]

	# ОГОНЬ / ПОЛОЖЕНИЕ toggles mirror the first own selected ship's
	# CURRENT order state (a group order still applies to the whole
	# selection when clicked -- these three just show what's in effect
	# for it right now). With nothing selected there is no state to show,
	# so they're left as-is rather than guessed.
	if not own.is_empty():
		var rep: String = own[0]
		var directive = world.ship_combat_directives.get(rep)
		var rep_free: bool = directive == null or directive.weapons_free
		_fire_btn.set_pressed_no_signal(rep_free)
		_fire_btn.text = "Огонь: свободный" if rep_free else "Огонь: СТОП"
		var rep_pd: bool = world.ship_pd_hold.get(rep, false)
		_pd_btn.set_pressed_no_signal(rep_pd)
		_pd_btn.text = "ПРО: СТОП" if rep_pd else "ПРО: авто"
		var cm_stock: int = 0
		for csid in own:
			cm_stock += world.cm_ammo_remaining(csid)
		_cm_btn.text = "ПРТР: %s (%d)" % [CM_POLICY_RU.get(world.cm_policy_of(rep), "авто"), cm_stock]
		_cm_btn.modulate = Color(1.0, 0.55, 0.5) if (cm_stock <= 0 and world.cm_tubes.has(rep)) else Color.WHITE
		var rep_hold: bool = world.ship_hold_the_line.get(rep, false)
		_hold_btn.set_pressed_no_signal(rep_hold)
		_hold_btn.text = "Драться до конца: ВКЛ" if rep_hold else "Драться до конца: выкл"
		var rep_att: String = String(world.ship_attitude.get(rep, "auto"))
		if rep_att == "":
			rep_att = "auto"
		for k in _attitude_buttons.keys():
			_attitude_buttons[k].set_pressed_no_signal(k == rep_att)
	if tactical_plot != null:
		_radar_btn.set_pressed_no_signal(tactical_plot.enlarged)

func _say(text: String) -> void:
	if battle_log != null:
		var who: Array = _own_selected()
		var wn: Array = []
		for w in who:
			wn.append(ShipNames.of(w))
		battle_log.add_local("%s%s" % [text, (" (" + ", ".join(wn) + ")") if not wn.is_empty() else ""])
	_status_text = text
	_status_until_ms = Time.get_ticks_msec() + 4000

func _fmt_km(m: float) -> String:
	if m >= 1.0e9:
		return "%.2f млн км" % (m / 1.0e9)
	return "%.0f тыс. км" % (m / 1.0e6)

func _enemy_distance_m() -> float:
	var own_c = _centroid(_alive_ids(true))
	var en_c = _centroid(_alive_ids(false))
	if own_c == null or en_c == null:
		return -1.0
	return (own_c as Vector3).distance_to(en_c as Vector3)

func _alive_ids(own: bool) -> Array:
	var out: Array = []
	for sid in world.ships.keys():
		var is_own: bool = String(world.teams.get(sid, "")) == player_team
		if is_own == own and not world.ships[sid].is_wreck:
			out.append(sid)
	return out

func _centroid(ids: Array):
	if ids.is_empty():
		return null
	var c := Vector3.ZERO
	for sid in ids:
		c += world.ships[sid].position
	return c / float(ids.size())

func _own_selected() -> Array:
	var out: Array = []
	if selection == null:
		return out
	for sid in selection.selected_ids:
		if world.ships.has(sid) and String(world.teams.get(sid, "")) == player_team and not world.ships[sid].is_wreck:
			out.append(sid)
	return out

# ---------------------------------------------------------------- time

func _step_time(dir: int) -> void:
	var cur: int = TIME_SCALES.find(world.clock.time_scale)
	if cur < 0:
		cur = 0
	_set_time(TIME_SCALES[clampi(cur + dir, 0, TIME_SCALES.size() - 1)])

func _on_warp_toggled(pressed: bool) -> void:
	if pressed:
		if world == null or _enemy_distance_m() <= WARP_STOP_RANGE_M:
			_warp_btn.set_pressed_no_signal(false)
			return
		warp_active = true
		_warp_saved_dt_mult = world.clock.max_dt_multiplier
		world.clock.max_dt_multiplier = maxi(_warp_saved_dt_mult, WARP_MAX_DT_MULT)
		world.clock.paused = false
		_warp_prev_d = -1.0
		_say("Перемотка до сближения: ВКЛ")
	else:
		_end_warp(false)

func _end_warp(resume: bool) -> void:
	if not warp_active:
		return
	warp_active = false
	world.clock.max_dt_multiplier = _warp_saved_dt_mult
	if _warp_btn != null:
		_warp_btn.set_pressed_no_signal(false)
	if resume:
		_set_time(WARP_RESUME_SCALE)
		_say("Сближение достигнуто: время x%d" % int(WARP_RESUME_SCALE))

## Подбирает множитель так, чтобы остаток пути уложился в ~WARP_TARGET_REAL_S.
func _update_warp() -> void:
	if not warp_active:
		return
	var clk: SimClock = world.clock
	var d: float = _enemy_distance_m()
	if d < 0.0 or d <= WARP_STOP_RANGE_M:
		_end_warp(true)
		return
	if clk.paused:
		_end_warp(false)
		return
	var t: float = clk.sim_time
	var closing: float = 0.0
	if _warp_prev_d >= 0.0 and t > _warp_prev_t:
		closing = (_warp_prev_d - d) / (t - _warp_prev_t)
	_warp_prev_d = d
	_warp_prev_t = t
	if closing < 1.0e4:
		closing = 1.0e5  # 100 км/с: оценка, пока скорость сближения не измерена
	var want: float = (d - WARP_STOP_RANGE_M) / closing / WARP_TARGET_REAL_S
	var pick: float = TIME_SCALES[0]
	for s in TIME_SCALES:
		if float(s) <= want:
			pick = float(s)
	clk.set_time_scale(pick)

func _on_slowdown_toggled(pressed: bool) -> void:
	auto_slowdown = pressed
	_slow_btn.text = "Авто-замедл.: %s" % ("ВКЛ" if auto_slowdown else "ВЫКЛ")

## True if any active missile is within SLOWDOWN_RANGE_M of its target.
func _missiles_closing() -> bool:
	for mid in world.missiles.keys():
		var m = world.missiles[mid]
		if m.is_active() and m.target != null and not world.counter_missile_ids.has(mid) and m.position.distance_to(m.target.position) < SLOWDOWN_RANGE_M:
			return true
	return false

func _set_time(scale: float) -> void:
	if scale <= 0.0:
		world.clock.paused = true
		return
	world.clock.paused = false
	world.clock.set_time_scale(scale)

## Bound to each ВРЕМЯ toggle button via Callable.bind(scale) -- only
## acts on the press that turns a button ON (the click that turns one
## off is the OTHER button's own press, handled by ITS bound call).
func _on_time_toggled(pressed: bool, scale: float) -> void:
	if pressed:
		_end_warp(false)
		_set_time(scale)

# ---------------------------------------------------------------- selection

func _select_squadron() -> void:
	selection.select_only(_alive_ids(true))

func _select_flagship() -> void:
	for fid in world.formations.keys():
		var f: FormationState = world.formations[fid]
		if String(world.teams.get(f.guide_ship_id, "")) == player_team:
			selection.select_only([f.guide_ship_id])
			return
	var own := _alive_ids(true)
	if not own.is_empty():
		selection.select_only([own[0]])

func _cycle_target() -> void:
	var enemies: Array = []
	var pov: String = _alive_ids(true)[0] if not _alive_ids(true).is_empty() else ""
	var contacts: Dictionary = world.sensor_contacts.get(pov, {})
	for sid in _alive_ids(false):
		if contacts.has(sid) and contacts[sid].state != ContactStateRef.Type.UNKNOWN:
			enemies.append(sid)
	if enemies.is_empty():
		_say("противник не обнаружен")
		return
	var i: int = enemies.find(selection.designated_target_id)
	selection.designate_target(enemies[(i + 1) % enemies.size()])

const ContactStateRef = preload("res://simulation/contact_state.gd")
const SubsystemTypeRef = preload("res://simulation/subsystem_type.gd")

func _make_group() -> void:
	if command_group_controller == null:
		return
	var id: String = command_group_controller.make_group_from_selection()
	_say("отряд создан" if id != "" else "нужно выделить 2+ своих корабля вне строя")

func _cam(kind: String) -> void:
	if camera_focus_controller == null:
		return
	match kind:
		"close":
			if not camera_focus_controller.view_selection(true):
				_say("выделите корабль")
		"squadron":
			camera_focus_controller.view_own_squadron()
		"all":
			camera_focus_controller.view_all()
		"back":
			camera_focus_controller.back()

func _overview() -> void:
	if camera_focus_controller == null:
		return
	camera_focus_controller.stop_follow()
	var cam = camera_focus_controller.camera
	if cam == null:
		return
	var ids: Array = _alive_ids(true) + _alive_ids(false)
	var c = _centroid(ids)
	if c == null:
		return
	var spread: float = 1.0
	for sid in ids:
		spread = maxf(spread, (c as Vector3).distance_to(world.ships[sid].position))
	cam.focus_on(c, spread)

func _focus() -> void:
	if camera_focus_controller != null:
		camera_focus_controller.try_focus()

# ---------------------------------------------------------------- order routing

## Splits the own selection into {"formations": [formation_id...],
## "individuals": [ship_id...]} per the §56.3 item I rule.
func _route() -> Dictionary:
	var own: Array = _own_selected()
	var by_f: Dictionary = {}
	var lone: Array = []
	for sid in own:
		var fid: String = _formation_of(sid)
		if fid == "":
			lone.append(sid)
		else:
			if not by_f.has(fid):
				by_f[fid] = []
			by_f[fid].append(sid)
	var forms: Array = []
	for fid in by_f.keys():
		var f: FormationState = world.formations[fid]
		var members: Array = [f.guide_ship_id]
		members.append_array(f.member_ids())
		var alive_members: Array = []
		for m in members:
			if world.ships.has(m) and not world.ships[m].is_wreck:
				alive_members.append(m)
		var full: bool = true
		for m in alive_members:
			if not by_f[fid].has(m):
				full = false
		if full:
			forms.append(fid)
		else:
			lone.append_array(by_f[fid])
	return {"formations": forms, "individuals": lone}

func _formation_of(sid: String) -> String:
	for fid in world.formations.keys():
		var f: FormationState = world.formations[fid]
		if f.guide_ship_id == sid or f.member_offsets.has(sid):
			return fid
	return ""

func _need_selection() -> bool:
	if _own_selected().is_empty():
		_say("сначала выделите свои корабли")
		return false
	return true

func _heading_of(ship: ShipPhysicsState) -> Vector3:
	if ship.velocity.length_squared() > 1.0:
		return ship.velocity.normalized()
	return ship.orientation * Vector3(0, 0, -1)

func _turn(sign: float) -> void:
	if not _need_selection():
		return
	var r := _route()
	for fid in r["formations"]:
		var g: ShipPhysicsState = world.ships[world.formations[fid].guide_ship_id]
		var h: Vector3 = _heading_of(g).rotated(Vector3.UP, sign * TURN_STEP_RAD)
		world.issue_formation_order_now(fid, FormationOrder.change_course(g, h))
	for sid in r["individuals"]:
		var s: ShipPhysicsState = world.ships[sid]
		world.transmit_individual_order_now(sid, IndividualOrder.change_course(s, _heading_of(s).rotated(Vector3.UP, sign * TURN_STEP_RAD)))
	_say("курс %s15°" % ("+" if sign < 0 else "-"))

func _change_speed(delta: float) -> void:
	if not _need_selection():
		return
	var r := _route()
	for fid in r["formations"]:
		var g: ShipPhysicsState = world.ships[world.formations[fid].guide_ship_id]
		world.issue_formation_order_now(fid, FormationOrder.change_speed(g, maxf(0.0, g.velocity.length() + delta), _heading_of(g)))
	for sid in r["individuals"]:
		var s: ShipPhysicsState = world.ships[sid]
		world.transmit_individual_order_now(sid, IndividualOrder.change_speed(s, maxf(0.0, s.velocity.length() + delta), _heading_of(s)))
	_say("скорость %+d км/с" % int(delta / 1000.0))

## Full thrust along the current heading: a CHANGE_SPEED order to a speed
## far above anything reachable in this battle, so the helm keeps
## accelerating until the player gives another order (Дрейф / Скорость).
func _full_thrust() -> void:
	if not _need_selection():
		return
	var r := _route()
	for fid in r["formations"]:
		var g: ShipPhysicsState = world.ships[world.formations[fid].guide_ship_id]
		world.issue_formation_order_now(fid, FormationOrder.change_speed(g, 5.0e7, _heading_of(g)))
	for sid in r["individuals"]:
		var s: ShipPhysicsState = world.ships[sid]
		world.transmit_individual_order_now(sid, IndividualOrder.change_speed(s, 5.0e7, _heading_of(s)))
	_say("полный ход")

func _drift() -> void:
	if not _need_selection():
		return
	var r := _route()
	for fid in r["formations"]:
		world.issue_formation_order_now(fid, FormationOrder.hold_formation())
	for sid in r["individuals"]:
		var s: ShipPhysicsState = world.ships[sid]
		world.transmit_individual_order_now(sid, IndividualOrder.change_speed(s, s.velocity.length(), _heading_of(s)))
	_say("дрейф")

func _withdraw() -> void:
	if not _need_selection():
		return
	var en = _centroid(_alive_ids(false))
	if en == null:
		return
	var r := _route()
	for fid in r["formations"]:
		var g: ShipPhysicsState = world.ships[world.formations[fid].guide_ship_id]
		var away: Vector3 = (g.position - (en as Vector3))
		away.y = 0.0
		# One CHANGE_SPEED with an explicit heading = turn away AND run at
		# withdrawal speed in a single velocity-vector order.
		world.issue_formation_order_now(fid, FormationOrder.change_speed(g, WITHDRAW_SPEED_MPS, away.normalized()))
	for sid in r["individuals"]:
		var s: ShipPhysicsState = world.ships[sid]
		var away2: Vector3 = (s.position - (en as Vector3))
		away2.y = 0.0
		world.transmit_individual_order_now(sid, IndividualOrder.change_speed(s, WITHDRAW_SPEED_MPS, away2.normalized()))
	_say("отход")

# ---------------------------------------------------------------- fire

const ATT_RU: Dictionary = {"auto": "авто-крен", "broadside": "бортом к врагу", "wedge": "клином к врагу", "course": "нос по курсу"}

func _attitude(mode: String) -> void:
	if not _need_selection():
		return
	for sid in _own_selected():
		world.set_ship_attitude(sid, mode)
	_say("положение: " + ATT_RU.get(mode, mode))

## Bound to each ПОЛОЖЕНИЕ toggle button via Callable.bind(mode) -- same
## "only act on the press that turns ON" rule as _on_time_toggled.
func _on_attitude_toggled(pressed: bool, mode: String) -> void:
	if pressed:
		_attitude(mode)

func _attack() -> void:
	if not _need_selection():
		return
	var tgt: String = selection.designated_target_id
	if tgt == "" or not world.ships.has(tgt):
		_say("нет цели: кликните врага или 'Цель >'")
		return
	for sid in _own_selected():
		world.transmit_ship_target(sid, tgt)
		world.transmit_ship_weapons_free(sid, true)
	_say("атаковать %s" % ShipNames.of(tgt))

## 2026-09-28 (user: "от игрока мало что зависит"): a one-click version
## of the tactic that headless A/B testing (simulation/tests/
## probe_player_impact.gd, averaged over several seeds) actually confirmed
## works -- concentrating the whole selection's fire on the single most-
## damaged DETECTED enemy ship kills the enemy squadron faster than
## leaving every ship to its own AI-default nearest-target pick.
## Sensor-honest: only looks at contacts this selection's ships can
## currently see (own sensor_contacts, TRACKED/DETECTED/ESTIMATED), never
## true enemy state -- same rule _attack()/the plot/the cards already
## follow.
func _attack_weakest() -> void:
	if not _need_selection():
		return
	var weakest_id: String = ""
	var weakest_cond: float = INF
	for sid in _own_selected():
		var contacts: Dictionary = world.sensor_contacts.get(sid, {})
		for cid in contacts.keys():
			if not world.ships.has(cid) or world.ships[cid].is_wreck:
				continue
			if String(world.teams.get(cid, "")) == player_team:
				continue
			var c = contacts[cid]
			if c.state == ContactStateRef.Type.UNKNOWN:
				continue
			var cond: float = world.ships[cid].subsystems.get_condition(SubsystemTypeRef.Type.STRUCTURAL_INTEGRITY)
			if cond < weakest_cond:
				weakest_cond = cond
				weakest_id = cid
	if weakest_id == "":
		_say("противник не обнаружен")
		return
	selection.designate_target(weakest_id)
	for sid in _own_selected():
		world.transmit_ship_target(sid, weakest_id)
		world.transmit_ship_weapons_free(sid, true)
	_say("добить %s (самый повреждённый из обнаруженных)" % ShipNames.of(weakest_id))

func _weapons_free(free: bool) -> void:
	if not _need_selection():
		return
	for sid in _own_selected():
		world.transmit_ship_weapons_free(sid, free)
	_say("огонь свободный" if free else "огонь прекращён")

func _pd_hold(hold: bool) -> void:
	if not _need_selection():
		return
	for sid in _own_selected():
		world.transmit_ship_pd_hold(sid, hold)
	_say("ПРО: стоп" if hold else "ПРО: авто")

func _hold_the_line(hold: bool) -> void:
	if not _need_selection():
		return
	for sid in _own_selected():
		world.set_ship_hold_the_line(sid, hold)
	_say("драться до конца, невзирая на повреждения" if hold else "разрешён отход при критических повреждениях")

## Toggle handlers for the merged ОГОНЬ switches: if nothing's selected,
## the underlying order call bails out via _need_selection() (with its
## own status message) and never applies -- revert the button's visual
## state right back so it doesn't silently claim an order that never
## went out. sync() takes over the visual state again the moment there
## IS a selection.
## 2026-09-29: counter-missile policy cycle for the selection, driven by the
## first selected ship's current policy: авто -> только флагман -> только
## залпы -> стоп -> авто. Comm-delayed like every other order.
const CM_POLICY_ORDER: Array = ["auto", "flagship", "salvo", "hold"]
const CM_POLICY_RU: Dictionary = {"auto": "авто", "flagship": "только флагман", "salvo": "только залпы", "hold": "СТОП"}

func _cycle_cm_policy() -> void:
	if not _need_selection():
		return
	var own: Array = _own_selected()
	var cur: int = CM_POLICY_ORDER.find(world.cm_policy_of(own[0]))
	var nxt: String = CM_POLICY_ORDER[(cur + 1) % CM_POLICY_ORDER.size()]
	var n: int = 0
	for sid in own:
		if world.cm_tubes.has(sid) and not world.cm_tubes[sid].is_empty():
			world.transmit_ship_cm_policy(sid, nxt)
			n += 1
	if n == 0:
		_say("у выделенных кораблей нет контрракет")
		return
	_say("контрракеты: " + String(CM_POLICY_RU.get(nxt, nxt)))

func _on_fire_toggled(pressed: bool) -> void:
	if not _need_selection():
		_fire_btn.set_pressed_no_signal(not pressed)
		return
	_weapons_free(pressed)

func _on_pd_toggled(pressed: bool) -> void:
	if not _need_selection():
		_pd_btn.set_pressed_no_signal(not pressed)
		return
	_pd_hold(pressed)

func _on_hold_toggled(pressed: bool) -> void:
	if not _need_selection():
		_hold_btn.set_pressed_no_signal(not pressed)
		return
	_hold_the_line(pressed)

# ---------------------------------------------------------------- radar

func _toggle_radar() -> void:
	if tactical_plot != null:
		tactical_plot.set_enlarged(not tactical_plot.enlarged)

func _radar_zoom(factor: float) -> void:
	if tactical_plot == null:
		return
	if factor <= 0.0:
		tactical_plot.range_zoom = 1.0
	else:
		tactical_plot.range_zoom = clampf(tactical_plot.range_zoom * factor, 1.0, 10000.0)

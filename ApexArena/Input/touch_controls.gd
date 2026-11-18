extends Control
## Multi-touch HUD controls: floating joystick, action buttons, drag-to-look.
## Every finger is tracked by its index, so thumbs never interfere with each other.

signal settings_requested
signal gyro_calibrated
signal edit_changed

const CFG_PATH := "user://hud.cfg"
# Bump this number whenever the default button layout changes.
# Old saved layouts with a different version are ignored automatically.
const LAYOUT_VERSION := 2
const STICK_R := 85.0
const STICK_DEADZONE := 0.1
const GYRO_DEADZONE := 0.006   # rad/s, after bias removal
const CALIB_TIME := 1.2

var active := false
var edit_mode := false
var hud_scale := 1.0
var sens := 1.0

# Gyro aiming. Rates come from Input.get_gyroscope() in rad/s and are integrated
# with the real frame delta, so the result does not depend on the frame rate.
var gyro_on := true
var gyro_sens := 1.0
var gyro_flip_x := false   # invert left/right
var gyro_flip_y := false   # invert up/down
var gyro_swap := false     # use the other pair of sensor axes
var gyro_bias := Vector3.ZERO
var gyro_look := Vector2.ZERO   # accumulated radians (yaw, pitch)
var dbg_label: Label
var _calib_t := -1.0
var _calib_sum := Vector3.ZERO
var _calib_n := 0
var calibrating: bool:
	get:
		return _calib_t >= 0.0

var move_vec := Vector2.ZERO
var sprint := false
var look_delta := Vector2.ZERO

var buttons := {
	"fire": {"pos": Vector2(0.84, 0.60), "r": 66.0, "label": "FIRE", "look": true, "col": Color(1.0, 0.45, 0.1)},
	"fire_l": {"pos": Vector2(0.08, 0.42), "r": 44.0, "label": "FIRE", "look": false, "col": Color(1.0, 0.45, 0.1)},
	"aim": {"pos": Vector2(0.72, 0.38), "r": 40.0, "label": "AIM", "look": true, "col": Color(0.4, 0.8, 1.0)},
	"jump": {"pos": Vector2(0.92, 0.82), "r": 46.0, "label": "JUMP", "look": false, "col": Color(1, 1, 1)},
	"slide": {"pos": Vector2(0.94, 0.36), "r": 40.0, "label": "SLIDE", "look": false, "col": Color(0.5, 1.0, 0.6)},
	"reload": {"pos": Vector2(0.70, 0.78), "r": 34.0, "label": "RELOAD", "look": false, "col": Color(1, 1, 1)},
	"switch": {"pos": Vector2(0.60, 0.68), "r": 30.0, "label": "SWAP", "look": false, "col": Color(1, 1, 1)},
	"gear": {"pos": Vector2(0.955, 0.09), "r": 24.0, "label": "II", "look": false, "col": Color(1, 1, 1)},
}
var _defaults := {}
var _fingers := {}      # finger index -> role ("stick", "look", button name, "edit:<name>")
var _btn_finger := {}   # button name -> finger index
var _stick_finger := -1
var _stick_center := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_home := Vector2(0.13, 0.74)
const STICK_HOME_DEFAULT := Vector2(0.13, 0.74)
var stick_scale := 1.0
var selected := ""   # element picked in edit mode ("stick" or a button name)
var _jump_edge := false
var _reload_edge := false
var _switch_edge := false

var fire_held: bool:
	get:
		return _btn_finger.has("fire") or _btn_finger.has("fire_l")
var aim_held: bool:
	get:
		return _btn_finger.has("aim")
var slide_held: bool:
	get:
		return _btn_finger.has("slide")

func _ready() -> void:
	# Fill the whole screen. Without the explicit size the control stays tiny
	# and everything piles up in the top-left corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit_to_screen()
	get_viewport().size_changed.connect(_fit_to_screen)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in buttons.keys():
		if not buttons[k].has("s"):
			buttons[k]["s"] = 1.0   # per-button size multiplier
	_defaults = buttons.duplicate(true)

func _fit_to_screen() -> void:
	var vs := get_viewport_rect().size
	if vs.x > 1.0 and vs.y > 1.0:
		size = vs

func adjust_selected(d: float) -> void:
	if selected == "":
		return
	if selected == "stick":
		stick_scale = clampf(snappedf(stick_scale + d, 0.05), 0.5, 2.0)
	elif buttons.has(selected):
		buttons[selected]["s"] = clampf(snappedf(float(buttons[selected]["s"]) + d, 0.05), 0.5, 2.0)
	edit_changed.emit()

func selected_text() -> String:
	if selected == "":
		return "TAP A BUTTON TO SELECT IT"
	var s: float = stick_scale if selected == "stick" else float(buttons[selected]["s"])
	return "%s   x%.2f" % [selected.to_upper(), s]

func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d

func consume_gyro() -> Vector2:
	var d := gyro_look
	gyro_look = Vector2.ZERO
	return d

func start_calibration() -> void:
	_calib_t = 0.0
	_calib_sum = Vector3.ZERO
	_calib_n = 0

func consume_jump() -> bool:
	var v := _jump_edge
	_jump_edge = false
	return v

func consume_reload() -> bool:
	var v := _reload_edge
	_reload_edge = false
	return v

func consume_switch() -> bool:
	var v := _switch_edge
	_switch_edge = false
	return v

func reset_state() -> void:
	_fingers.clear()
	_btn_finger.clear()
	_stick_finger = -1
	move_vec = Vector2.ZERO
	sprint = false
	look_delta = Vector2.ZERO
	gyro_look = Vector2.ZERO
	_jump_edge = false
	_reload_edge = false
	_switch_edge = false

func _center(b: Dictionary) -> Vector2:
	var p: Vector2 = b["pos"]
	return Vector2(p.x * size.x, p.y * size.y)

func _hit_button(p: Vector2) -> String:
	var best := ""
	var best_d := 1e9
	for k in buttons.keys():
		var b: Dictionary = buttons[k]
		var d: float = p.distance_to(_center(b))
		var r: float = float(b["r"]) * hud_scale * float(b["s"]) + 10.0
		if d <= r and d < best_d:
			best = k
			best_d = d
	if edit_mode:
		var sc := Vector2(size.x * _stick_home.x, size.y * _stick_home.y)
		var sd: float = p.distance_to(sc)
		if sd <= STICK_R * hud_scale * stick_scale and sd < best_d:
			best = "stick"
	return best

func _input(event: InputEvent) -> void:
	if not (active or edit_mode):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position, event.relative)

func _press(idx: int, pos: Vector2) -> void:
	var bn := _hit_button(pos)
	if edit_mode:
		if bn != "":
			_fingers[idx] = "edit:" + bn
			selected = bn
			edit_changed.emit()
		return
	if bn != "":
		_btn_finger[bn] = idx
		_fingers[idx] = bn
		match bn:
			"jump":
				_jump_edge = true
			"reload":
				_reload_edge = true
			"switch":
				_switch_edge = true
			"gear":
				_btn_finger.erase(bn)
				_fingers.erase(idx)
				settings_requested.emit()
		return
	# Fixed joystick: it only grabs a finger that lands on/near it, and its center never moves.
	var home := Vector2(size.x * _stick_home.x, size.y * _stick_home.y)
	var grab_r := STICK_R * hud_scale * stick_scale * 1.8
	if _stick_finger < 0 and pos.distance_to(home) <= grab_r:
		_stick_finger = idx
		_stick_center = home
		_stick_pos = pos
		_fingers[idx] = "stick"
		_update_stick()
	else:
		_fingers[idx] = "look"

func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if not _fingers.has(idx):
		return
	var role: String = _fingers[idx]
	if edit_mode:
		if role.begins_with("edit:"):
			var bn := role.substr(5)
			var np := Vector2(clampf(pos.x / size.x, 0.04, 0.96), clampf(pos.y / size.y, 0.06, 0.94))
			if bn == "stick":
				_stick_home = np
			else:
				buttons[bn]["pos"] = np
		return
	if role == "stick":
		_stick_pos = pos
		_update_stick()
	elif role == "look":
		look_delta += rel
	elif buttons.has(role) and buttons[role]["look"]:
		look_delta += rel

func _release(idx: int) -> void:
	if not _fingers.has(idx):
		return
	var role: String = _fingers[idx]
	_fingers.erase(idx)
	if role == "stick":
		_stick_finger = -1
		move_vec = Vector2.ZERO
		sprint = false
	elif _btn_finger.has(role):
		_btn_finger.erase(role)

func _update_stick() -> void:
	var r := STICK_R * hud_scale * stick_scale
	_stick_center = Vector2(size.x * _stick_home.x, size.y * _stick_home.y)   # never moves
	var d := (_stick_pos - _stick_center).limit_length(r)
	var v := Vector2(d.x, -d.y) / r
	var l := v.length()
	if l < STICK_DEADZONE:
		v = Vector2.ZERO
	else:
		# Remove the dead zone and rescale so movement starts smoothly from zero.
		v = v / l * ((l - STICK_DEADZONE) / (1.0 - STICK_DEADZONE))
	move_vec = v.limit_length(1.0)
	var m := move_vec.length()
	if m > 0.9:
		sprint = true
	elif m < 0.4:
		sprint = false

func _update_gyro(delta: float) -> void:
	var raw := Input.get_gyroscope()
	if dbg_label != null and dbg_label.is_visible_in_tree():
		dbg_label.text = "GYRO  x %.2f   y %.2f   z %.2f  (rad/s)" % [raw.x, raw.y, raw.z]
	if _calib_t >= 0.0:
		# Average the resting sensor to find its drift (bias), then subtract it forever.
		_calib_t += delta
		_calib_sum += raw
		_calib_n += 1
		if _calib_t >= CALIB_TIME:
			if _calib_n > 0:
				gyro_bias = _calib_sum / float(_calib_n)
			_calib_t = -1.0
			save_layout()
			gyro_calibrated.emit()
		return
	if not gyro_on or not active:
		return
	var g := raw - gyro_bias
	var yaw: float = g.y     # turn left/right
	var pitch: float = g.x   # look up/down
	if gyro_swap:
		yaw = g.x
		pitch = g.y
	if gyro_flip_x:
		yaw = -yaw
	if gyro_flip_y:
		pitch = -pitch
	if absf(yaw) < GYRO_DEADZONE:
		yaw = 0.0
	if absf(pitch) < GYRO_DEADZONE:
		pitch = 0.0
	gyro_look += Vector2(yaw, pitch) * minf(delta, 0.05) * gyro_sens

func _process(delta: float) -> void:
	if size != get_viewport_rect().size:
		_fit_to_screen()
	_update_gyro(delta)
	if active or edit_mode:
		queue_redraw()

func _draw() -> void:
	if not (active or edit_mode):
		return
	var font := ThemeDB.fallback_font
	var r := STICK_R * hud_scale * stick_scale
	var c0 := Vector2(size.x * _stick_home.x, size.y * _stick_home.y)
	var off := Vector2.ZERO
	if _stick_finger >= 0:
		c0 = _stick_center
		off = (_stick_pos - _stick_center).limit_length(r)
	draw_circle(c0, r, Color(1, 1, 1, 0.07))
	var ring_col := Color(1.0, 0.6, 0.15, 0.7) if sprint else Color(1, 1, 1, 0.35)
	draw_arc(c0, r, 0.0, TAU, 48, ring_col, 2.5, true)
	draw_circle(c0 + off, r * 0.38, Color(1, 1, 1, 0.45 if _stick_finger >= 0 else 0.22))
	if edit_mode and selected == "stick":
		draw_arc(c0, r + 6.0, 0.0, TAU, 48, Color(1, 0.85, 0.2), 4.0, true)
	var fs := int(15.0 * hud_scale)
	for k in buttons.keys():
		var b: Dictionary = buttons[k]
		var c := _center(b)
		var br: float = float(b["r"]) * hud_scale * float(b["s"])
		var col: Color = b["col"]
		var down: bool = _btn_finger.has(k)
		draw_circle(c, br, Color(col.r, col.g, col.b, 0.38 if down else 0.14))
		draw_arc(c, br, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.9 if down else 0.55), 2.5, true)
		if edit_mode and selected == k:
			draw_arc(c, br + 6.0, 0.0, TAU, 40, Color(1, 0.85, 0.2), 4.0, true)
		draw_string(font, c + Vector2(-br, fs * 0.35), String(b["label"]), HORIZONTAL_ALIGNMENT_CENTER, br * 2.0, fs, Color(1, 1, 1, 0.95))
	if edit_mode:
		draw_string(font, Vector2(0, size.y * 0.2), "DRAG TO MOVE  -  TAP TO SELECT  -  USE  -  /  +  TO RESIZE", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1, 0.8, 0.3))

func save_layout() -> void:
	var cf := ConfigFile.new()
	cf.set_value("meta", "layout_version", LAYOUT_VERSION)
	for k in buttons.keys():
		var p: Vector2 = buttons[k]["pos"]
		cf.set_value("buttons", String(k), p)
		cf.set_value("scales", String(k), float(buttons[k]["s"]))
	cf.set_value("stick", "home", _stick_home)
	cf.set_value("stick", "scale", stick_scale)
	cf.set_value("settings", "hud_scale", hud_scale)
	cf.set_value("settings", "sens", sens)
	cf.set_value("gyro", "on", gyro_on)
	cf.set_value("gyro", "sens", gyro_sens)
	cf.set_value("gyro", "flip_x", gyro_flip_x)
	cf.set_value("gyro", "flip_y", gyro_flip_y)
	cf.set_value("gyro", "swap", gyro_swap)
	cf.set_value("gyro", "bias", gyro_bias)
	cf.save(CFG_PATH)

func load_layout() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return
	# Always keep user settings (scale + sensitivity).
	hud_scale = clampf(float(cf.get_value("settings", "hud_scale", 1.0)), 0.6, 1.6)
	sens = clampf(float(cf.get_value("settings", "sens", 1.0)), 0.3, 2.5)
	gyro_on = bool(cf.get_value("gyro", "on", true))
	gyro_sens = clampf(float(cf.get_value("gyro", "sens", 1.0)), 0.2, 5.0)
	gyro_flip_x = bool(cf.get_value("gyro", "flip_x", false))
	gyro_flip_y = bool(cf.get_value("gyro", "flip_y", false))
	gyro_swap = bool(cf.get_value("gyro", "swap", false))
	var gb = cf.get_value("gyro", "bias", Vector3.ZERO)
	if gb is Vector3:
		gyro_bias = gb
	# Only restore saved button positions if they match the current layout version.
	# Otherwise the new default layout is used.
	if int(cf.get_value("meta", "layout_version", 0)) != LAYOUT_VERSION:
		return
	for k in buttons.keys():
		var p = cf.get_value("buttons", String(k), buttons[k]["pos"])
		if p is Vector2:
			buttons[k]["pos"] = p
		buttons[k]["s"] = clampf(float(cf.get_value("scales", String(k), 1.0)), 0.5, 2.0)
	var sh = cf.get_value("stick", "home", STICK_HOME_DEFAULT)
	if sh is Vector2:
		_stick_home = sh
	stick_scale = clampf(float(cf.get_value("stick", "scale", 1.0)), 0.5, 2.0)

func reset_layout() -> void:
	for k in buttons.keys():
		buttons[k]["pos"] = _defaults[k]["pos"]
		buttons[k]["s"] = 1.0
	_stick_home = STICK_HOME_DEFAULT
	stick_scale = 1.0
	selected = ""
	hud_scale = 1.0
	save_layout()

extends Node3D
## Match flow: menu -> match (1v1 vs bot, training, or online vs friend) -> result.
## Owns world, UI, scoring and respawns.
## Combat uses a simple take_damage(amount, attacker, hit_pos) interface.
## Online: every phone owns its own player; hits are sent to the victim (see net.gd).

const ArenaScript = preload("res://Arena/arena.gd")
const FxScript = preload("res://Effects/effects.gd")
const PlayerScript = preload("res://Player/player.gd")
const RemotePlayerScript = preload("res://Player/remote_player.gd")
const EnemyScript = preload("res://Enemies/enemy.gd")
const TouchScript = preload("res://Input/touch_controls.gd")
const HudScript = preload("res://UI/hud.gd")
const NetScript = preload("res://Systems/net.gd")
const WeaponData = preload("res://Weapons/weapon_data.gd")

const MATCH_TIME := 240.0
const RESPAWN_DELAY := 2.0
const LOBBY_HELP := "HOST: turn ON your phone hotspot, then tap HOST GAME.\nFRIEND: connect to that hotspot Wi-Fi, then tap JOIN GAME.\n(Same home Wi-Fi works too.)"

enum State { MENU, PLAYING, ENDED }

var state: int = State.MENU
var training := false
var online := false
var time_left := MATCH_TIME
var player_score := 0
var enemy_score := 0
var player_respawn := -1.0
var enemy_respawn := -1.0
var shadows_on := true

var arena
var fx
var player
var enemy
var remote
var net
var touch
var hud
var ui: CanvasLayer
var menu_panel: Control
var lobby_panel: Control
var pause_panel: Control
var end_panel: Control
var edit_bar: Control
var edit_label: Label
var weapon_panel: Control
var wp_return: Control          # panel to go back to (main menu or pause)
var wp_list: VBoxContainer
var wp_slot_btns: Array[Button] = []
var wp_cat_btns: Array[Button] = []
var wp_cat := 0
var wp_slot := 0
var end_label: Label
var lobby_status: Label
var ip_edit: LineEdit
var again_btn: Button
var scale_label: Label
var sens_label: Label
var gsens_label: Label
var gyro_dbg: Label
var shadow_btn: Button
var gyro_btn: Button
var swap_btn: Button
var flipx_btn: Button
var flipy_btn: Button
var calib_btn: Button

func _ready() -> void:
	randomize()
	arena = ArenaScript.new()
	add_child(arena)
	fx = FxScript.new()
	add_child(fx)
	player = PlayerScript.new()
	add_child(player)
	enemy = EnemyScript.new()
	add_child(enemy)
	remote = RemotePlayerScript.new()
	remote.name = "RemotePlayer"
	add_child(remote)
	net = NetScript.new()
	net.name = "Net"   # same node path on both phones (required for RPC)
	add_child(net)
	net.game = self
	remote.net = net
	_build_ui()
	player.touch = touch
	player.setup_fx(fx)
	enemy.target = player
	enemy.fx = fx
	enemy.waypoints = arena.waypoints
	player.died.connect(_on_player_died)
	enemy.died.connect(_on_enemy_died)
	player.damaged.connect(hud.on_player_damaged)
	player.hit_marker.connect(hud.on_hit_marker)
	player.weapon.traced.connect(_on_player_traced)
	hud.game = self
	hud.player = player
	hud.enemy = enemy
	hud.arena = arena
	touch.load_layout()
	touch.dbg_label = gyro_dbg
	touch.settings_requested.connect(_open_pause)
	touch.edit_changed.connect(_update_edit_label)
	touch.gyro_calibrated.connect(_update_labels)
	net.status.connect(func(t: String): lobby_status.text = t)
	net.peer_lost.connect(_on_net_peer_lost)
	remote.deactivate()
	player.global_position = Vector3(0, 1, 15)
	enemy.global_position = Vector3(0, 1, -15)
	_update_labels()
	_show_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_open_pause()

func _foe_pos() -> Vector3:
	return remote.global_position if online else enemy.global_position

func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	if not training:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			if not online:
				_end_match()
				return
			elif net.is_host:
				# Host is the clock: it tells the friend the final score.
				net.send_end(player_score, enemy_score)
				_end_match()
				return
	if player_respawn > 0.0:
		player_respawn -= delta
		if player_respawn <= 0.0:
			var ps: Vector3 = _pick_spawn(_foe_pos())
			player.respawn(ps, _yaw_to_center(ps))
	if enemy_respawn > 0.0:
		enemy_respawn -= delta
		if enemy_respawn <= 0.0:
			var es: Vector3 = _pick_spawn(player.global_position)
			enemy.respawn(es, _yaw_to_center(es))

# ------------------------------------------------------------------ match
func _pick_spawn(from: Vector3) -> Vector3:
	var best: Vector3 = arena.spawn_points[0]
	var best_d := -1.0
	for sp in arena.spawn_points:
		var d: float = from.distance_to(sp) + randf() * 8.0
		if d > best_d:
			best_d = d
			best = sp
	return best

func _yaw_to_center(p: Vector3) -> float:
	var d := Vector3.ZERO - p
	return atan2(-d.x, -d.z)

func _begin_play() -> void:
	state = State.PLAYING
	menu_panel.hide()
	lobby_panel.hide()
	end_panel.hide()
	pause_panel.hide()
	weapon_panel.hide()
	hud.visible = true
	touch.visible = true
	touch.active = true
	get_tree().paused = false
	hud.show_banner("FIGHT!", Color(1, 0.7, 0.2))

func _start_match(train: bool) -> void:
	online = false
	training = train
	remote.deactivate()
	hud.enemy = enemy
	enemy.visible = true
	enemy.set_physics_process(true)
	player_score = 0
	enemy_score = 0
	time_left = MATCH_TIME
	player_respawn = -1.0
	enemy_respawn = -1.0
	enemy.can_shoot = not train
	player.weapon.infinite_ammo = train
	var ps: Vector3 = arena.spawn_points[randi() % arena.spawn_points.size()]
	player.respawn(ps, _yaw_to_center(ps))
	var es: Vector3 = _pick_spawn(ps)
	enemy.respawn(es, _yaw_to_center(es))
	_begin_play()

## Starts (or restarts) an online match. `pair` picks opposite spawn corners:
## host uses spawn pair*2, the friend uses pair*2+1.
func online_start(host: bool, pair: int) -> void:
	online = true
	training = false
	player_score = 0
	enemy_score = 0
	time_left = MATCH_TIME
	player_respawn = -1.0
	enemy_respawn = -1.0
	# Switch the AI bot off completely.
	enemy.frozen = true
	enemy.dead = true
	enemy.visible = false
	enemy.col.set_deferred("disabled", true)
	enemy.set_physics_process(false)
	player.weapon.infinite_ammo = false
	var mine: Vector3 = arena.spawn_points[pair * 2 + (0 if host else 1)]
	var theirs: Vector3 = arena.spawn_points[pair * 2 + (1 if host else 0)]
	player.respawn(mine, _yaw_to_center(mine))
	remote.activate(theirs, _yaw_to_center(theirs))
	hud.enemy = remote
	_begin_play()

func _on_player_died(_killer) -> void:
	enemy_score += 1
	player_respawn = RESPAWN_DELAY
	hud.show_banner("ELIMINATED", Color(1, 0.3, 0.25))
	if online:
		net.send_scored()   # tells the friend he got the kill

func _on_enemy_died(_killer) -> void:
	player_score += 1
	enemy_respawn = RESPAWN_DELAY
	player.weapon.add_reserve(28)
	hud.show_banner("ENEMY DOWN  +1", Color(1, 0.8, 0.2))

func _end_match() -> void:
	state = State.ENDED
	touch.active = false
	touch.reset_state()
	player.frozen = true
	enemy.frozen = true
	var res := "DRAW"
	if player_score > enemy_score:
		res = "VICTORY"
	elif player_score < enemy_score:
		res = "DEFEAT"
	end_label.text = "%s\n%d  -  %d" % [res, player_score, enemy_score]
	again_btn.visible = (not online) or net.is_host
	end_panel.show()

func _play_again() -> void:
	if online:
		if net.is_host:
			var pair := randi() % 3
			net.send_start(pair)
			online_start(true, pair)
	else:
		_start_match(training)

# ------------------------------------------------------------------ online callbacks
func net_host_ready() -> void:
	# Friend just connected (host side). Small delay so both phones are ready.
	await get_tree().create_timer(0.6).timeout
	if net.session and net.peer_ready and state != State.PLAYING:
		var pair := randi() % 3
		net.send_start(pair)
		online_start(true, pair)

func on_net_start(pair: int) -> void:
	online_start(false, pair)

func on_net_end(h_you: int, h_foe: int) -> void:
	if state != State.PLAYING:
		return
	player_score = h_foe
	enemy_score = h_you
	_end_match()

func on_net_hit(amount: float, y_off: float) -> void:
	if state != State.PLAYING or player.dead:
		return
	var hp: Vector3 = player.global_position + Vector3(0.0, y_off, 0.0)
	player.take_damage(amount, remote, hp)

func on_net_scored() -> void:
	if state != State.PLAYING:
		return
	player_score += 1
	player.weapon.add_reserve(28)
	hud.show_banner("ENEMY DOWN  +1", Color(1, 0.8, 0.2))

func _on_player_traced(from: Vector3, to: Vector3) -> void:
	if online:
		net.send_tracer(from, to)

func _on_net_peer_lost() -> void:
	net.close()
	if not online:
		lobby_status.text = "Connection lost. Tap HOST or JOIN to try again."
		return
	online = false
	get_tree().paused = false
	state = State.MENU
	player.frozen = true
	remote.deactivate()
	hud.enemy = enemy
	pause_panel.hide()
	end_panel.hide()
	weapon_panel.hide()
	edit_bar.hide()
	touch.edit_mode = false
	hud.visible = false
	touch.active = false
	touch.reset_state()
	touch.visible = false
	lobby_status.text = "Friend left the game.\nTap HOST or JOIN to play again."
	lobby_panel.show()

# ------------------------------------------------------------------ lobby
func _open_lobby() -> void:
	menu_panel.hide()
	lobby_status.text = LOBBY_HELP
	ip_edit.text = net.last_ip
	lobby_panel.show()

func _lobby_back() -> void:
	net.close()
	lobby_panel.hide()
	menu_panel.show()

func _lobby_host() -> void:
	net.host()

func _lobby_join() -> void:
	net.join_auto()

func _lobby_connect() -> void:
	net.close()
	net.join(ip_edit.text)

# ------------------------------------------------------------------ pause / settings
func _open_pause() -> void:
	if state != State.PLAYING or pause_panel.visible or touch.edit_mode:
		return
	# Online matches keep running (the friend is still playing), so no tree pause there.
	if not online:
		get_tree().paused = true
	touch.active = false
	touch.reset_state()
	_update_labels()
	pause_panel.show()

func _close_pause() -> void:
	get_tree().paused = false
	pause_panel.hide()
	touch.active = true

func _adj_scale(d: float) -> void:
	touch.hud_scale = clampf(touch.hud_scale + d, 0.6, 1.6)
	touch.save_layout()
	_update_labels()

func _adj_sens(d: float) -> void:
	touch.sens = clampf(touch.sens + d, 0.3, 2.5)
	touch.save_layout()
	_update_labels()

func _adj_gyro(d: float) -> void:
	touch.gyro_sens = clampf(snappedf(touch.gyro_sens + d, 0.1), 0.2, 5.0)
	touch.save_layout()
	_update_labels()

func _toggle_gyro() -> void:
	touch.gyro_on = not touch.gyro_on
	touch.save_layout()
	_update_labels()

func _toggle_swap() -> void:
	touch.gyro_swap = not touch.gyro_swap
	touch.save_layout()
	_update_labels()

func _toggle_flipx() -> void:
	touch.gyro_flip_x = not touch.gyro_flip_x
	touch.save_layout()
	_update_labels()

func _toggle_flipy() -> void:
	touch.gyro_flip_y = not touch.gyro_flip_y
	touch.save_layout()
	_update_labels()

func _calibrate() -> void:
	touch.start_calibration()
	_update_labels()

func _toggle_shadows() -> void:
	shadows_on = not shadows_on
	arena.sun.shadow_enabled = shadows_on
	_update_labels()

func _reset_layout() -> void:
	touch.reset_layout()
	_update_labels()

func _enter_edit() -> void:
	pause_panel.hide()
	edit_bar.show()
	touch.edit_mode = true
	touch.selected = ""
	_update_edit_label()

func _update_edit_label() -> void:
	edit_label.text = touch.selected_text()

func _exit_edit() -> void:
	touch.edit_mode = false
	touch.selected = ""
	touch.save_layout()
	edit_bar.hide()
	pause_panel.show()

# ------------------------------------------------------------------ weapon loadout
func _open_weapons(from: Control) -> void:
	wp_return = from
	from.hide()
	weapon_panel.show()
	_refresh_weapons()

func _close_weapons() -> void:
	weapon_panel.hide()
	if wp_return != null:
		wp_return.show()

func _set_wp_slot(i: int) -> void:
	wp_slot = i
	_refresh_weapons()

func _set_wp_cat(i: int) -> void:
	wp_cat = i
	_refresh_weapons()

func _equip_weapon(idx: int) -> void:
	player.weapon.equip(wp_slot, idx)
	player.weapon.save_loadout()
	_refresh_weapons()

func _refresh_weapons() -> void:
	var wpn = player.weapon
	for i in 2:
		var nm: String = String(WeaponData.WEAPONS[wpn.slots[i]]["name"])
		wp_slot_btns[i].text = ("> " if i == wp_slot else "") + "SLOT %d: %s" % [i + 1, nm]
	for i in wp_cat_btns.size():
		var cn: String = String(WeaponData.CATEGORIES[i])
		wp_cat_btns[i].text = ("[ %s ]" % cn) if i == wp_cat else cn
	for c in wp_list.get_children():
		wp_list.remove_child(c)
		c.queue_free()
	for idx in WeaponData.indices_for(String(WeaponData.CATEGORIES[wp_cat])):
		var w: Dictionary = WeaponData.WEAPONS[idx]
		var tag := ""
		if wpn.slots[0] == idx:
			tag = "   [SLOT 1]"
		elif wpn.slots[1] == idx:
			tag = "   [SLOT 2]"
		var mode := "AUTO" if bool(w["auto"]) else "SEMI"
		var txt := "%s%s\nDMG %d    RPM %d    MAG %d    %s" % [String(w["name"]), tag, int(w["damage"]), int(w["rpm"]), int(w["mag"]), mode]
		_btn(wp_list, txt, _equip_weapon.bind(idx), 640, 78, 22)

func _quit_to_menu() -> void:
	get_tree().paused = false
	if online:
		net.close()
		online = false
	state = State.MENU
	player.frozen = true
	enemy.frozen = true
	remote.deactivate()
	hud.enemy = enemy
	pause_panel.hide()
	end_panel.hide()
	weapon_panel.hide()
	_show_menu()

func _update_labels() -> void:
	scale_label.text = "%.1f" % touch.hud_scale
	sens_label.text = "%.1f" % touch.sens
	gsens_label.text = "%.1f" % touch.gyro_sens
	shadow_btn.text = "SHADOWS: " + ("ON" if shadows_on else "OFF")
	gyro_btn.text = "GYRO: " + ("ON" if touch.gyro_on else "OFF")
	swap_btn.text = "AXES: " + ("SWAP" if touch.gyro_swap else "NORMAL")
	flipx_btn.text = "FLIP H: " + ("ON" if touch.gyro_flip_x else "OFF")
	flipy_btn.text = "FLIP V: " + ("ON" if touch.gyro_flip_y else "OFF")
	calib_btn.text = "KEEP PHONE STILL..." if touch.calibrating else "CALIBRATE GYRO (PHONE STILL)"

func _show_menu() -> void:
	touch.active = false
	touch.reset_state()
	hud.visible = false
	touch.visible = false
	lobby_panel.hide()
	menu_panel.show()

# ------------------------------------------------------------------ UI construction
func _btn(parent: Node, text: String, cb: Callable, w := 380, h := 70, fs := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _label(parent: Node, text: String, fs: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _panel(title: String) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)
	_label(vb, title, 46, Color(1, 0.6, 0.15))
	ui.add_child(root)
	root.hide()
	return [root, vb]

## Two-column panel (used by the pause menu, which has many settings).
func _panel2(title: String) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	center.add_child(outer)
	_label(outer, title, 40, Color(1, 0.6, 0.15))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 40)
	outer.add_child(hb)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	ui.add_child(root)
	root.hide()
	return [root, left, right]

func _pair(vb: Node) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	return hb

func _row(vb: Node, title: String, minus: Callable, plus: Callable) -> Label:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	var t := Label.new()
	t.text = title
	t.custom_minimum_size = Vector2(240, 0)
	t.add_theme_font_size_override("font_size", 24)
	hb.add_child(t)
	_btn(hb, "-", minus, 70, 52, 30)
	var v := Label.new()
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 26)
	hb.add_child(v)
	_btn(hb, "+", plus, 70, 52, 30)
	return v

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	hud = HudScript.new()
	ui.add_child(hud)
	touch = TouchScript.new()
	ui.add_child(touch)

	# ---- main menu
	var m := _panel("APEX ARENA")
	menu_panel = m[0]
	_label(m[1], "Slide  -  Slide Jump  -  Bunny Hop  -  Strafe", 20, Color(1, 1, 1, 0.7))
	_btn(m[1], "1v1 MATCH  (4:00)", func(): _start_match(false))
	_btn(m[1], "TRAINING", func(): _start_match(true))
	_btn(m[1], "LOADOUT  (WEAPONS)", func(): _open_weapons(menu_panel), 380, 70, 26)
	_btn(m[1], "PLAY WITH FRIEND  (HOTSPOT)", _open_lobby, 380, 70, 24)
	_btn(m[1], "QUIT", func(): get_tree().quit(), 380, 56, 24)

	# ---- online lobby
	var l := _panel("PLAY WITH FRIEND")
	lobby_panel = l[0]
	lobby_status = _label(l[1], LOBBY_HELP, 20, Color(1, 1, 1, 0.85))
	lobby_status.custom_minimum_size = Vector2(760, 96)
	lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_btn(l[1], "HOST GAME  (hotspot ON)", _lobby_host, 460, 62, 26)
	_btn(l[1], "JOIN GAME  (auto)", _lobby_join, 460, 62, 26)
	var ipr := HBoxContainer.new()
	ipr.alignment = BoxContainer.ALIGNMENT_CENTER
	ipr.add_theme_constant_override("separation", 10)
	l[1].add_child(ipr)
	ip_edit = LineEdit.new()
	ip_edit.custom_minimum_size = Vector2(290, 56)
	ip_edit.add_theme_font_size_override("font_size", 24)
	ip_edit.placeholder_text = "Host IP"
	ip_edit.text = net.last_ip
	ipr.add_child(ip_edit)
	_btn(ipr, "CONNECT", _lobby_connect, 160, 56, 22)
	_btn(l[1], "BACK", _lobby_back, 460, 56, 24)

	# ---- pause / settings (two columns)
	var p := _panel2("PAUSED")
	pause_panel = p[0]
	var lc: Node = p[1]
	var rc: Node = p[2]
	_btn(lc, "RESUME", _close_pause, 478, 56, 28)
	scale_label = _row(lc, "HUD SCALE", _adj_scale.bind(-0.1), _adj_scale.bind(0.1))
	sens_label = _row(lc, "LOOK SENSITIVITY", _adj_sens.bind(-0.1), _adj_sens.bind(0.1))
	gsens_label = _row(lc, "GYRO SENSITIVITY", _adj_gyro.bind(-0.1), _adj_gyro.bind(0.1))
	var g1 := _pair(lc)
	gyro_btn = _btn(g1, "GYRO", _toggle_gyro, 235, 52, 20)
	swap_btn = _btn(g1, "AXES", _toggle_swap, 235, 52, 20)
	var g2 := _pair(lc)
	flipx_btn = _btn(g2, "FLIP H", _toggle_flipx, 235, 52, 20)
	flipy_btn = _btn(g2, "FLIP V", _toggle_flipy, 235, 52, 20)
	gyro_dbg = _label(lc, "", 16, Color(0.6, 0.9, 1.0))
	_btn(rc, "WEAPONS / LOADOUT", func(): _open_weapons(pause_panel), 380, 52, 22)
	calib_btn = _btn(rc, "CALIBRATE", _calibrate, 380, 52, 20)
	shadow_btn = _btn(rc, "SHADOWS", _toggle_shadows, 380, 52, 22)
	_btn(rc, "EDIT HUD LAYOUT", _enter_edit, 380, 52, 22)
	_btn(rc, "RESET HUD LAYOUT", _reset_layout, 380, 52, 22)
	_btn(rc, "QUIT TO MENU", _quit_to_menu, 380, 52, 22)

	# ---- weapon loadout: 2 slots, tabs per weapon type, list of weapons
	var wpn := _panel("LOADOUT")
	weapon_panel = wpn[0]
	var wv: Node = wpn[1]
	var slot_row := _pair(wv)
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 2:
		wp_slot_btns.append(_btn(slot_row, "", _set_wp_slot.bind(i), 310, 56, 20))
	var cat_row := _pair(wv)
	cat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in WeaponData.CATEGORIES.size():
		wp_cat_btns.append(_btn(cat_row, "", _set_wp_cat.bind(i), 150, 52, 20))
	wp_list = VBoxContainer.new()
	wp_list.add_theme_constant_override("separation", 8)
	wv.add_child(wp_list)
	_btn(wv, "BACK", _close_weapons, 640, 56, 24)

	# ---- end of match
	var e := _panel("")
	end_panel = e[0]
	end_label = _label(e[1], "", 54, Color.WHITE)
	again_btn = _btn(e[1], "PLAY AGAIN", _play_again)
	_btn(e[1], "MENU", _quit_to_menu, 380, 56, 24)

	edit_bar = Control.new()
	edit_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edit_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Top-center bar:  [-]  NAME xSIZE  [+]  [DONE]
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	edit_bar.add_child(bar)
	_btn(bar, "-", func(): touch.adjust_selected(-0.1), 80, 64, 34)
	edit_label = _label(bar, "", 22, Color(1, 0.85, 0.4))
	edit_label.custom_minimum_size = Vector2(340, 64)
	edit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_btn(bar, "+", func(): touch.adjust_selected(0.1), 80, 64, 34)
	_btn(bar, "DONE", _exit_edit, 200, 64, 28)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.offset_top += 20.0
	bar.offset_bottom += 20.0
	ui.add_child(edit_bar)
	edit_bar.hide()

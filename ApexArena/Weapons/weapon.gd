extends Node3D
## Modular weapon controller: 3D viewmodels, hitscan, recoil, reload, switching, tilt.
## Stats live in weapon_data.gd. Owner (player) sets the input fields each frame, then calls tick().
## The player carries TWO weapons (slots). SWAP toggles between them; the loadout menu changes them.

signal fired
signal hit_enemy(killed: bool, head: bool)
signal traced(from: Vector3, to: Vector3)   # used to show our tracers on the friend's phone

const Data = preload("res://Weapons/weapon_data.gd")
const SWITCH_TIME := 0.38
const LOADOUT_PATH := "user://loadout.cfg"

var player
var cam: Camera3D
var fx
var target_mask := 5          # world (1) + enemy layer (4)
var infinite_ammo := false

var current := 0              # index into Data.WEAPONS of the weapon in hand
var slots: Array[int] = [0, 1]   # the two carried weapons (indexes into Data.WEAPONS)
var slot := 0                 # which slot is active
var ammo: Array[int] = []     # indexed by weapon index (not slot)
var reserve: Array[int] = []
var reloading := false
var reload_t := 0.0
var switch_t := SWITCH_TIME
var pending := -1
var cooldown := 0.0
var bloom := 0.0
var was_firing := false
var spread_now := 0.0

# Inputs written by the owner every frame
var firing := false
var aiming := false
var sliding := false
var on_floor := true
var move_speed := 0.0
var look_delta := Vector2.ZERO
var tilt_target := 0.0       # radians; + = tilt left, - = tilt right

var models: Array[Node3D] = []   # indexed by weapon index
var base_pos := Vector3(0.23, -0.23, -0.48)
var ads_t := 0.0
var roll := 0.0
var kick := 0.0
var sway := Vector2.ZERO
var bob_t := 0.0
var slide_pose := 0.0
var flash_t := 0.0
var _mats := {}

func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	m.metallic = 0.25
	_mats[key] = m
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _flash_node(parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.35)
	mi.material_override = m
	mi.position = pos
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Every model must set these meta values: mag (Node3D that dips on reload), mag_y,
## muzzle (Node3D, tracer start), flash (MeshInstance3D), ads_y (how far it drops to line up the sights).
func _finish_model(m: Node3D, mag: Node3D, muzzle_pos: Vector3, flash_pos: Vector3, ads_y: float) -> Node3D:
	var muzzle := Node3D.new()
	muzzle.position = muzzle_pos
	m.add_child(muzzle)
	var fl := _flash_node(m, flash_pos)
	m.set_meta("mag", mag)
	m.set_meta("mag_y", mag.position.y)
	m.set_meta("muzzle", muzzle)
	m.set_meta("flash", fl)
	m.set_meta("ads_y", ads_y)
	return m

func _build_rifle(accent: Color) -> Node3D:
	var m := Node3D.new()
	var dark := Color(0.14, 0.15, 0.17)
	var mid := Color(0.26, 0.28, 0.31)
	var glove := Color(0.12, 0.12, 0.13)
	_box(m, Vector3(0.07, 0.1, 0.5), Vector3(0, 0, 0), mid)
	_box(m, Vector3(0.075, 0.075, 0.28), Vector3(0, -0.005, -0.36), dark)
	_box(m, Vector3(0.025, 0.025, 0.28), Vector3(0, 0.02, -0.6), dark)
	_box(m, Vector3(0.06, 0.12, 0.22), Vector3(0, -0.02, 0.33), dark)
	_box(m, Vector3(0.05, 0.12, 0.06), Vector3(0, -0.1, 0.1), dark, Vector3(15, 0, 0))
	_box(m, Vector3(0.04, 0.05, 0.14), Vector3(0, 0.075, -0.04), dark)
	_box(m, Vector3(0.02, 0.02, 0.02), Vector3(0, 0.1, -0.1), accent)
	_box(m, Vector3(0.072, 0.02, 0.22), Vector3(0, 0.055, -0.2), accent)
	_box(m, Vector3(0.09, 0.09, 0.09), Vector3(0, -0.07, -0.34), glove)
	_box(m, Vector3(0.07, 0.1, 0.1), Vector3(0, -0.12, 0.1), glove)
	var mag := _box(m, Vector3(0.05, 0.17, 0.08), Vector3(0, -0.13, -0.06), dark)
	return _finish_model(m, mag, Vector3(0, 0.02, -0.76), Vector3(0, 0.02, -0.8), 0.1)

func _build_pistol(accent: Color) -> Node3D:
	var m := Node3D.new()
	var dark := Color(0.14, 0.15, 0.17)
	var mid := Color(0.3, 0.32, 0.36)
	var glove := Color(0.12, 0.12, 0.13)
	_box(m, Vector3(0.05, 0.06, 0.24), Vector3(0, 0.0, -0.05), mid)
	_box(m, Vector3(0.045, 0.04, 0.2), Vector3(0, -0.05, -0.04), dark)
	_box(m, Vector3(0.045, 0.11, 0.06), Vector3(0, -0.1, 0.07), dark, Vector3(15, 0, 0))
	_box(m, Vector3(0.052, 0.015, 0.1), Vector3(0, 0.035, -0.05), accent)
	_box(m, Vector3(0.07, 0.1, 0.09), Vector3(0, -0.1, 0.07), glove)
	var mag := _box(m, Vector3(0.04, 0.09, 0.05), Vector3(0, -0.12, 0.06), dark)
	return _finish_model(m, mag, Vector3(0, 0.0, -0.18), Vector3(0, 0.0, -0.22), 0.045)

func _build_revolver(accent: Color) -> Node3D:
	var m := Node3D.new()
	var dark := Color(0.14, 0.15, 0.17)
	var mid := Color(0.36, 0.37, 0.4)
	var glove := Color(0.12, 0.12, 0.13)
	_box(m, Vector3(0.05, 0.07, 0.18), Vector3(0, 0.0, -0.03), mid)             # frame
	_box(m, Vector3(0.062, 0.07, 0.09), Vector3(0, 0.0, -0.13), dark)           # cylinder
	_box(m, Vector3(0.03, 0.035, 0.3), Vector3(0, 0.02, -0.32), mid)            # long barrel
	_box(m, Vector3(0.014, 0.014, 0.3), Vector3(0, 0.047, -0.32), accent)       # top rib
	_box(m, Vector3(0.012, 0.03, 0.012), Vector3(0, 0.06, -0.01), dark)         # rear sight
	_box(m, Vector3(0.045, 0.11, 0.06), Vector3(0, -0.1, 0.07), dark, Vector3(20, 0, 0))   # grip
	_box(m, Vector3(0.07, 0.1, 0.09), Vector3(0, -0.1, 0.07), glove)
	var mag := _box(m, Vector3(0.012, 0.012, 0.012), Vector3(0, -0.04, -0.02), dark)       # dummy (reload dip)
	return _finish_model(m, mag, Vector3(0, 0.02, -0.48), Vector3(0, 0.02, -0.52), 0.06)

func _build_smg(accent: Color) -> Node3D:
	var m := Node3D.new()
	var dark := Color(0.14, 0.15, 0.17)
	var mid := Color(0.26, 0.28, 0.31)
	var glove := Color(0.12, 0.12, 0.13)
	_box(m, Vector3(0.065, 0.09, 0.34), Vector3(0, 0, 0), mid)                  # receiver
	_box(m, Vector3(0.06, 0.06, 0.18), Vector3(0, 0.0, -0.26), dark)            # shroud
	_box(m, Vector3(0.022, 0.022, 0.1), Vector3(0, 0.01, -0.4), dark)           # barrel tip
	_box(m, Vector3(0.05, 0.08, 0.12), Vector3(0, -0.01, 0.23), dark)           # stock
	_box(m, Vector3(0.045, 0.11, 0.06), Vector3(0, -0.09, 0.08), dark, Vector3(15, 0, 0))  # grip
	_box(m, Vector3(0.035, 0.04, 0.1), Vector3(0, 0.065, -0.02), dark)          # sight base
	_box(m, Vector3(0.018, 0.018, 0.018), Vector3(0, 0.092, -0.06), accent)     # sight dot
	_box(m, Vector3(0.067, 0.018, 0.16), Vector3(0, 0.05, -0.12), accent)       # accent strip
	_box(m, Vector3(0.08, 0.08, 0.08), Vector3(0, -0.06, -0.26), glove)         # off hand
	_box(m, Vector3(0.07, 0.09, 0.09), Vector3(0, -0.11, 0.08), glove)          # trigger hand
	var mag := _box(m, Vector3(0.04, 0.2, 0.06), Vector3(0, -0.14, -0.04), dark)
	return _finish_model(m, mag, Vector3(0, 0.01, -0.46), Vector3(0, 0.01, -0.5), 0.085)

func _build_sniper(accent: Color) -> Node3D:
	var m := Node3D.new()
	var dark := Color(0.14, 0.15, 0.17)
	var mid := Color(0.26, 0.28, 0.31)
	var glove := Color(0.12, 0.12, 0.13)
	_box(m, Vector3(0.07, 0.1, 0.5), Vector3(0, 0, 0), mid)                     # receiver
	_box(m, Vector3(0.03, 0.03, 0.6), Vector3(0, 0.015, -0.55), dark)           # long barrel
	_box(m, Vector3(0.045, 0.045, 0.12), Vector3(0, 0.015, -0.88), dark)        # muzzle brake
	_box(m, Vector3(0.06, 0.14, 0.3), Vector3(0, -0.02, 0.4), dark)             # stock
	_box(m, Vector3(0.045, 0.11, 0.06), Vector3(0, -0.1, 0.12), dark, Vector3(15, 0, 0))   # grip
	_box(m, Vector3(0.05, 0.05, 0.26), Vector3(0, 0.12, -0.05), dark)           # scope tube
	_box(m, Vector3(0.07, 0.07, 0.05), Vector3(0, 0.12, -0.2), accent)          # objective lens ring
	_box(m, Vector3(0.06, 0.06, 0.04), Vector3(0, 0.12, 0.1), accent)           # eyepiece
	_box(m, Vector3(0.02, 0.05, 0.02), Vector3(0, 0.08, -0.1), dark)            # scope mount
	_box(m, Vector3(0.02, 0.05, 0.02), Vector3(0, 0.08, 0.0), dark)             # scope mount
	_box(m, Vector3(0.02, 0.02, 0.07), Vector3(0.06, 0.02, 0.06), mid)          # bolt handle
	_box(m, Vector3(0.08, 0.09, 0.1), Vector3(0, -0.07, -0.25), glove)          # off hand
	_box(m, Vector3(0.07, 0.1, 0.1), Vector3(0, -0.12, 0.12), glove)            # trigger hand
	var mag := _box(m, Vector3(0.045, 0.07, 0.1), Vector3(0, -0.075, -0.02), dark)
	return _finish_model(m, mag, Vector3(0, 0.015, -0.95), Vector3(0, 0.015, -1.0), 0.15)

func _build_model(w: Dictionary) -> Node3D:
	var accent: Color = w.get("accent", Color(0.95, 0.45, 0.1))
	match String(w.get("model", "rifle")):
		"pistol":
			return _build_pistol(accent)
		"revolver":
			return _build_revolver(accent)
		"smg":
			return _build_smg(accent)
		"sniper":
			return _build_sniper(accent)
	return _build_rifle(accent)

func setup(p, c: Camera3D) -> void:
	player = p
	cam = c
	for w in Data.WEAPONS:
		ammo.append(int(w["mag"]))
		reserve.append(int(w["reserve"]))
		models.append(_build_model(w))
	for m in models:
		add_child(m)
	load_loadout()
	slot = 0
	current = slots[0]
	_show_only(current)
	position = base_pos

func _show_only(i: int) -> void:
	for j in models.size():
		models[j].visible = (j == i)

# ---------------------------------------------------------------- loadout
func save_loadout() -> void:
	var cf := ConfigFile.new()
	cf.set_value("loadout", "slot1", slots[0])
	cf.set_value("loadout", "slot2", slots[1])
	cf.save(LOADOUT_PATH)

func load_loadout() -> void:
	var cf := ConfigFile.new()
	if cf.load(LOADOUT_PATH) != OK:
		return
	var a: int = int(cf.get_value("loadout", "slot1", 0))
	var b: int = int(cf.get_value("loadout", "slot2", 1))
	var n: int = Data.WEAPONS.size()
	if a >= 0 and a < n and b >= 0 and b < n and a != b:
		slots[0] = a
		slots[1] = b

## Put weapon `widx` into slot `slot_i` (0 or 1). If the other slot already has it, the two swap.
func equip(slot_i: int, widx: int) -> void:
	if widx < 0 or widx >= Data.WEAPONS.size() or slots[slot_i] == widx:
		return
	var other: int = 1 - slot_i
	if slots[other] == widx:
		slots[other] = slots[slot_i]
	else:
		ammo[widx] = int(Data.WEAPONS[widx]["mag"])
		reserve[widx] = int(Data.WEAPONS[widx]["reserve"])
	slots[slot_i] = widx
	reloading = false
	if current != slots[slot]:
		pending = slots[slot]
		switch_t = 0.0   # plays the draw animation

func is_scoped() -> bool:
	return bool(Data.WEAPONS[current].get("scoped", false))

func aim_sens() -> float:
	return float(Data.WEAPONS[current].get("aim_sens", 0.55))

func refill() -> void:
	for i in ammo.size():
		ammo[i] = int(Data.WEAPONS[i]["mag"])
		reserve[i] = int(Data.WEAPONS[i]["reserve"])
	reloading = false
	switch_t = SWITCH_TIME
	pending = -1
	bloom = 0.0
	current = slots[slot]
	_show_only(current)

func add_reserve(n: int) -> void:
	reserve[current] = mini(reserve[current] + n, int(Data.WEAPONS[current]["reserve"]) * 2)

func zoom_fov() -> float:
	return float(Data.WEAPONS[current]["zoom_fov"])

func weapon_name() -> String:
	return String(Data.WEAPONS[current]["name"])

func reload_progress() -> float:
	if not reloading:
		return 0.0
	return clampf(reload_t / float(Data.WEAPONS[current]["reload"]), 0.0, 1.0)

func start_reload() -> void:
	var w: Dictionary = Data.WEAPONS[current]
	if reloading or switch_t < SWITCH_TIME:
		return
	if ammo[current] >= int(w["mag"]):
		return
	if reserve[current] <= 0 and not infinite_ammo:
		return
	reloading = true
	reload_t = 0.0

## SWAP button: toggle between the two carried weapons.
func switch_next() -> void:
	if switch_t < SWITCH_TIME:
		return
	reloading = false
	slot = 1 - slot
	pending = slots[slot]
	switch_t = 0.0

func _finish_reload() -> void:
	reloading = false
	var w: Dictionary = Data.WEAPONS[current]
	var need: int = int(w["mag"]) - ammo[current]
	var take: int = need if infinite_ammo else mini(need, reserve[current])
	ammo[current] += take
	if not infinite_ammo:
		reserve[current] -= take

func tick(delta: float) -> void:
	var w: Dictionary = Data.WEAPONS[current]
	cooldown = maxf(0.0, cooldown - delta)
	bloom = maxf(0.0, bloom - float(w["bloom_recover"]) * delta)
	flash_t -= delta
	var model := models[current]
	(model.get_meta("flash") as MeshInstance3D).visible = flash_t > 0.0

	# Switching
	if switch_t < SWITCH_TIME:
		switch_t += delta
		if pending >= 0 and switch_t >= SWITCH_TIME * 0.5:
			current = pending
			pending = -1
			_show_only(current)
			w = Data.WEAPONS[current]
			model = models[current]

	# Reloading
	if reloading:
		reload_t += delta
		if reload_t >= float(w["reload"]):
			_finish_reload()

	# Firing
	var can_act: bool = switch_t >= SWITCH_TIME and not reloading
	if firing and can_act and cooldown <= 0.0:
		if bool(w["auto"]) or not was_firing:
			if ammo[current] > 0:
				_shoot(w)
			elif not was_firing:
				start_reload()
	was_firing = firing

	var spread_deg: float = float(w["spread_ads"]) if aiming else float(w["spread_hip"])
	spread_now = spread_deg + bloom + move_speed * 0.02
	_animate(delta, w, model)

func _shoot(w: Dictionary) -> void:
	ammo[current] -= 1
	cooldown = 60.0 / float(w["rpm"])
	bloom = minf(bloom + float(w["bloom"]), float(w["bloom_max"]))
	var b := cam.global_transform.basis
	var ang := randf() * TAU
	var r: float = sqrt(randf()) * deg_to_rad(spread_now)
	var dir: Vector3 = (-b.z + b.x * cos(ang) * r + b.y * sin(ang) * r).normalized()
	var origin := cam.global_position
	var rng: float = float(w["range"])
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng, target_mask)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var muzzle := models[current].get_meta("muzzle") as Node3D
	var end: Vector3 = origin + dir * 80.0
	if not hit.is_empty():
		end = hit["position"]
		var col = hit["collider"]
		if col != null and col.has_method("take_damage"):
			var head: bool = false
			var cn := col as Node3D
			if cn != null:
				head = end.y - cn.global_position.y > 1.42
			# Damage falloff: SMGs lose power at range, snipers do not.
			var dmg: float = float(w["damage"])
			var dist: float = origin.distance_to(end)
			var fs: float = float(w.get("falloff_start", 9999.0))
			if dist > fs:
				var fe: float = float(w.get("falloff_end", fs + 1.0))
				var t: float = clampf((dist - fs) / maxf(fe - fs, 0.01), 0.0, 1.0)
				dmg *= lerpf(1.0, float(w.get("falloff_min", 1.0)), t)
			var killed: bool = col.take_damage(dmg, player, end)
			hit_enemy.emit(killed, head)
			if fx:
				fx.impact(end, hit["normal"], true)
		elif fx:
			fx.impact(end, hit["normal"], false)
	if fx:
		fx.tracer(muzzle.global_position, end)
	traced.emit(muzzle.global_position, end)
	flash_t = 0.045
	var fl := models[current].get_meta("flash") as MeshInstance3D
	fl.rotation.z = randf() * TAU
	fl.scale = Vector3.ONE * randf_range(0.8, 1.4)
	kick += 0.035
	var pitch: float = deg_to_rad(float(w["recoil_pitch"]))
	var yaw: float = deg_to_rad(float(w["recoil_yaw"])) * randf_range(-1.0, 1.0)
	player.add_recoil(pitch, yaw)
	fired.emit()

func _animate(delta: float, w: Dictionary, model: Node3D) -> void:
	var a: float = 1.0 if (aiming and not reloading) else 0.0
	ads_t = move_toward(ads_t, a, delta * 9.0)
	# Scoped weapons hide the gun model while looking through the scope.
	model.visible = not (is_scoped() and ads_t > 0.85)
	var ads_pos := Vector3(0.0, -float(model.get_meta("ads_y")), -0.42)
	var p := base_pos.lerp(ads_pos, ads_t)
	var sway_goal := Vector2(-look_delta.x, look_delta.y) * 0.0009
	sway_goal = sway_goal.limit_length(0.04)
	sway = sway.lerp(sway_goal, 1.0 - exp(-12.0 * delta))
	p += Vector3(sway.x, sway.y, 0.0)
	if on_floor and move_speed > 1.0 and not sliding:
		bob_t += delta * move_speed * 1.4
		p += Vector3(cos(bob_t * 0.5) * 0.006, sin(bob_t) * 0.006, 0.0) * (1.0 - ads_t * 0.8)
	kick = lerpf(kick, 0.0, 1.0 - exp(-16.0 * delta))
	p.z += kick * (1.0 - ads_t * 0.5)
	slide_pose = move_toward(slide_pose, 1.0 if sliding else 0.0, delta * 6.0)
	p += Vector3(0.04, -0.05, 0.02) * slide_pose * (1.0 - ads_t)
	var rx := kick * 1.2
	# Reload / switch animations
	if reloading:
		var u := clampf(reload_t / float(w["reload"]), 0.0, 1.0)
		var dip := sin(u * PI)
		p.y -= dip * 0.1
		p.x -= dip * 0.05
		rx += dip * 0.55
		var mag := model.get_meta("mag") as Node3D
		var mu := sin(clampf((u - 0.2) / 0.55, 0.0, 1.0) * PI)
		mag.position.y = float(model.get_meta("mag_y")) - 0.22 * mu
	else:
		(model.get_meta("mag") as Node3D).position.y = float(model.get_meta("mag_y"))
	if switch_t < SWITCH_TIME:
		var sd := sin(clampf(switch_t / SWITCH_TIME, 0.0, 1.0) * PI)
		p.y -= sd * 0.3
		rx += sd * 0.6
	# Signature slide tilt: weapon rolls toward strafe direction, returns smoothly
	roll = lerpf(roll, tilt_target, 1.0 - exp(-9.0 * delta))
	position = p
	rotation = Vector3(rx, roll * 0.25 + sway.x * 2.0, roll)

extends RefCounted
## Weapon stat table. To add a weapon: append a Dictionary to WEAPONS (new weapons go at the END,
## so existing indexes and saved loadouts stay valid). "model" picks the viewmodel built in weapon.gd:
## pistol / revolver / smg / rifle / sniper. "accent" is its trim color.
##
## Optional keys:  falloff_start / falloff_end (meters) + falloff_min (damage multiplier at falloff_end),
##                 scoped (true = black scope overlay + hidden gun while aiming),
##                 aim_sens (look-sensitivity multiplier while aiming, default 0.55).
## Headshot = x1.5 damage (handled by the target).

const CATEGORIES := ["PISTOL", "SMG", "RIFLE", "SNIPER"]

const WEAPONS := [
	# ---------------------------------------------------------------- 0  RIFLE (original)
	{
		"name": "R-301 CARBINE", "cat": "RIFLE", "model": "rifle", "accent": Color(0.95, 0.45, 0.1),
		"damage": 14.0, "rpm": 660.0, "auto": true,
		"mag": 28, "reserve": 112, "reload": 1.9,
		"spread_hip": 1.1, "spread_ads": 0.25, "bloom": 0.22, "bloom_max": 2.2, "bloom_recover": 4.0,
		"recoil_pitch": 0.55, "recoil_yaw": 0.28, "range": 120.0, "zoom_fov": 55.0,
	},
	# ---------------------------------------------------------------- 1  PISTOL (original)
	{
		"name": "P2020 PISTOL", "cat": "PISTOL", "model": "pistol", "accent": Color(0.95, 0.45, 0.1),
		"damage": 21.0, "rpm": 420.0, "auto": false,
		"mag": 14, "reserve": 70, "reload": 1.3,
		"spread_hip": 0.9, "spread_ads": 0.2, "bloom": 0.5, "bloom_max": 2.0, "bloom_recover": 4.0,
		"recoil_pitch": 1.1, "recoil_yaw": 0.35, "range": 90.0, "zoom_fov": 65.0,
	},
	# ---------------------------------------------------------------- 2  PISTOL: strong, slow
	{
		"name": "MAGNUM .44", "cat": "PISTOL", "model": "revolver", "accent": Color(0.85, 0.7, 0.25),
		"damage": 52.0, "rpm": 130.0, "auto": false,
		"mag": 6, "reserve": 36, "reload": 2.3,
		"spread_hip": 0.8, "spread_ads": 0.1, "bloom": 1.0, "bloom_max": 2.5, "bloom_recover": 3.0,
		"recoil_pitch": 2.6, "recoil_yaw": 0.5, "range": 100.0, "zoom_fov": 60.0,
	},
	# ---------------------------------------------------------------- 3  SMG: fast, weak, short range
	{
		"name": "VOLT SMG", "cat": "SMG", "model": "smg", "accent": Color(0.2, 0.8, 0.95),
		"damage": 8.5, "rpm": 900.0, "auto": true,
		"mag": 35, "reserve": 140, "reload": 1.7,
		"spread_hip": 1.3, "spread_ads": 0.5, "bloom": 0.15, "bloom_max": 2.6, "bloom_recover": 5.0,
		"recoil_pitch": 0.32, "recoil_yaw": 0.3, "range": 70.0, "zoom_fov": 62.0,
		"falloff_start": 12.0, "falloff_end": 35.0, "falloff_min": 0.5,
	},
	# ---------------------------------------------------------------- 4  SMG: a bit stronger, slower
	{
		"name": "TACT-9 SMG", "cat": "SMG", "model": "smg", "accent": Color(0.6, 0.95, 0.3),
		"damage": 11.0, "rpm": 720.0, "auto": true,
		"mag": 25, "reserve": 100, "reload": 1.6,
		"spread_hip": 1.1, "spread_ads": 0.4, "bloom": 0.2, "bloom_max": 2.4, "bloom_recover": 5.0,
		"recoil_pitch": 0.45, "recoil_yaw": 0.3, "range": 80.0, "zoom_fov": 60.0,
		"falloff_start": 15.0, "falloff_end": 40.0, "falloff_min": 0.6,
	},
	# ---------------------------------------------------------------- 5  RIFLE: hard hitting, heavy recoil
	{
		"name": "KR-47", "cat": "RIFLE", "model": "rifle", "accent": Color(0.3, 0.75, 0.4),
		"damage": 20.0, "rpm": 520.0, "auto": true,
		"mag": 30, "reserve": 90, "reload": 2.3,
		"spread_hip": 1.2, "spread_ads": 0.28, "bloom": 0.3, "bloom_max": 2.6, "bloom_recover": 3.5,
		"recoil_pitch": 0.85, "recoil_yaw": 0.4, "range": 130.0, "zoom_fov": 52.0,
		"falloff_start": 40.0, "falloff_end": 100.0, "falloff_min": 0.8,
	},
	# ---------------------------------------------------------------- 6  SNIPER: semi-auto marksman
	{
		"name": "LONGBOW DMR", "cat": "SNIPER", "model": "sniper", "accent": Color(0.9, 0.35, 0.3),
		"damage": 48.0, "rpm": 240.0, "auto": false,
		"mag": 10, "reserve": 40, "reload": 2.4,
		"spread_hip": 1.8, "spread_ads": 0.05, "bloom": 0.8, "bloom_max": 2.0, "bloom_recover": 3.0,
		"recoil_pitch": 1.3, "recoil_yaw": 0.2, "range": 220.0, "zoom_fov": 38.0,
		"aim_sens": 0.4,
	},
	# ---------------------------------------------------------------- 7  SNIPER: bolt, one-shot headshot
	{
		"name": "KRAKEN SNIPER", "cat": "SNIPER", "model": "sniper", "accent": Color(0.7, 0.4, 0.9),
		"damage": 90.0, "rpm": 55.0, "auto": false,
		"mag": 5, "reserve": 20, "reload": 3.0,
		"spread_hip": 3.0, "spread_ads": 0.0, "bloom": 2.0, "bloom_max": 3.0, "bloom_recover": 2.0,
		"recoil_pitch": 3.0, "recoil_yaw": 0.3, "range": 300.0, "zoom_fov": 18.0,
		"scoped": true, "aim_sens": 0.25,
	},
]

## Indexes of all weapons in a category (keeps the order of WEAPONS).
static func indices_for(cat: String) -> Array[int]:
	var out: Array[int] = []
	for i in WEAPONS.size():
		if String(WEAPONS[i]["cat"]) == cat:
			out.append(i)
	return out

extends Node3D
## Small, bright fighting arena (36 x 36) built entirely from code.
## Public variables/functions are kept compatible with the rest of the game.

const HALF := 18.0
const ARENA_COLOR := Color(0.62, 0.58, 0.50)
const ARENA_DARK := Color(0.52, 0.49, 0.42)
const WALL_COLOR := Color(0.55, 0.52, 0.47)

var half: float = HALF
# Order matters: (0,1) / (2,3) / (4,5) are opposite pairs used by online mode.
# All of them are in open floor, away from any cover.
var spawn_points: Array[Vector3] = [
	Vector3(-15, 1.0, -15),
	Vector3(15, 1.0, 15),
	Vector3(-15, 1.0, 15),
	Vector3(15, 1.0, -15),
	Vector3(0, 1.0, -15),
	Vector3(0, 1.0, 15),
]

# All waypoints are on open floor (not inside any obstacle).
var waypoints: Array[Vector3] = [
	Vector3(-12, 0, -12), Vector3(12, 0, 12),
	Vector3(-12, 0, 12), Vector3(12, 0, -12),
	Vector3(0, 0, -8), Vector3(0, 0, 8),
	Vector3(-9, 0, 0), Vector3(9, 0, 0),
	Vector3(-4, 0, -13), Vector3(4, 0, 13),
	Vector3(-13, 0, 4), Vector3(13, 0, -4),
]

var map_rects: Array[Rect2] = []
var sun: DirectionalLight3D
var _mats: Dictionary = {}


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_walls()
	_build_cover()


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	_mats[key] = material
	return material


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.58, 0.88)
	sky_material.sky_horizon_color = Color(0.80, 0.86, 0.92)
	sky_material.ground_horizon_color = Color(0.72, 0.70, 0.64)
	sky_material.ground_bottom_color = Color(0.45, 0.44, 0.40)
	sky.sky_material = sky_material
	environment.sky = sky

	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.2
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.80, 0.84, 0.88)
	environment.fog_density = 0.002
	environment.glow_enabled = false

	var world_environment := WorldEnvironment.new()
	world_environment.name = "ArenaWorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "ArenaSun"
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)


func _add_static_box(pos: Vector3, size: Vector3, color: Color, yaw: float = 0.0, register_on_map: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape

	body.add_child(mesh_instance)
	body.add_child(collision)
	add_child(body)

	if register_on_map:
		_register_rect(pos, size, yaw)
	return body


func _register_rect(pos: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var half_x := size.x * 0.5
	var half_z := size.z * 0.5
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	var extent_x := c * half_x + s * half_z
	var extent_z := s * half_x + c * half_z
	map_rects.append(Rect2(Vector2(pos.x - extent_x, pos.z - extent_z), Vector2(extent_x * 2.0, extent_z * 2.0)))


func add_box(pos: Vector3, size: Vector3, color: Color, yaw: float = 0.0, on_map: bool = true) -> void:
	_add_static_box(pos, size, color, yaw, on_map)


func _stripe(pos: Vector3, size: Vector3, color: Color, yaw: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(color)
	mesh_instance.position = pos
	mesh_instance.rotation.y = yaw
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


func _build_ground() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8)
	image.set_pixel(0, 0, ARENA_COLOR)
	image.set_pixel(1, 1, ARENA_COLOR)
	image.set_pixel(1, 0, ARENA_DARK)
	image.set_pixel(0, 1, ARENA_DARK)

	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_texture = ImageTexture.create_from_image(image)
	ground_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground_material.uv1_scale = Vector3(12.0, 12.0, 1.0)
	ground_material.roughness = 1.0

	var body := StaticBody3D.new()
	body.name = "ArenaGround"
	body.position = Vector3(0, -0.5, 0)
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(HALF * 2.0, 1.0, HALF * 2.0)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = ground_material

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape

	body.add_child(mesh_instance)
	body.add_child(collision)
	add_child(body)


func _rock(x: float, z: float, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(x, height * 0.5, z)
	body.rotation.y = randf() * TAU
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.6
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(Color(0.48, 0.47, 0.50))

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius * 0.85
	shape.height = height
	collision.shape = shape

	body.add_child(mesh_instance)
	body.add_child(collision)
	add_child(body)

	map_rects.append(Rect2(Vector2(x - radius, z - radius), Vector2(radius * 2.0, radius * 2.0)))


func _barrier(x: float, z: float, yaw: float) -> void:
	add_box(Vector3(x, 0.65, z), Vector3(4.0, 1.3, 0.8), Color(0.66, 0.64, 0.60), yaw)
	_stripe(Vector3(x, 1.31, z), Vector3(4.02, 0.04, 0.82), Color(0.90, 0.68, 0.25), yaw)


func _build_walls() -> void:
	add_box(Vector3(0, 3, -HALF - 0.5), Vector3(HALF * 2.0 + 2.0, 6, 1), WALL_COLOR, 0.0, false)
	add_box(Vector3(0, 3, HALF + 0.5), Vector3(HALF * 2.0 + 2.0, 6, 1), WALL_COLOR, 0.0, false)
	add_box(Vector3(HALF + 0.5, 3, 0), Vector3(1, 6, HALF * 2.0 + 2.0), WALL_COLOR, 0.0, false)
	add_box(Vector3(-HALF - 0.5, 3, 0), Vector3(1, 6, HALF * 2.0 + 2.0), WALL_COLOR, 0.0, false)

	var trim := Color(0.80, 0.52, 0.30)
	_stripe(Vector3(0, 1.5, -HALF + 0.1), Vector3(HALF * 2.0, 0.12, 0.10), trim, 0.0)
	_stripe(Vector3(0, 1.5, HALF - 0.1), Vector3(HALF * 2.0, 0.12, 0.10), trim, 0.0)
	_stripe(Vector3(HALF - 0.1, 1.5, 0), Vector3(0.10, 0.12, HALF * 2.0), trim, 0.0)
	_stripe(Vector3(-HALF + 0.1, 1.5, 0), Vector3(0.10, 0.12, HALF * 2.0), trim, 0.0)


func _build_cover() -> void:
	var concrete := Color(0.68, 0.66, 0.61)

	# Center pillar block with low barriers on both sides.
	add_box(Vector3(0, 1.2, 0), Vector3(3.0, 2.4, 3.0), Color(0.85, 0.60, 0.32))
	_barrier(-6, 0, PI * 0.5)
	_barrier(6, 0, PI * 0.5)

	# Barriers protecting the diagonals.
	_barrier(-6, -9, 0.0)
	_barrier(6, 9, 0.0)
	_barrier(6, -9, 0.0)
	_barrier(-6, 9, 0.0)

	# Shipping containers (long axis along Z).
	add_box(Vector3(-11, 1.3, -4), Vector3(2.4, 2.6, 6), Color(0.45, 0.58, 0.54))
	add_box(Vector3(11, 1.3, 4), Vector3(2.4, 2.6, 6), Color(0.78, 0.45, 0.32))

	# Columns.
	for point in [Vector3(-4, 1.75, -4), Vector3(4, 1.75, 4), Vector3(-4, 1.75, 4), Vector3(4, 1.75, -4)]:
		add_box(point, Vector3(1.2, 3.5, 1.2), Color(0.72, 0.70, 0.64))

	# Low crates to jump on / slide past.
	add_box(Vector3(-13, 0.5, 9), Vector3(2.0, 1.0, 2.0), concrete)
	add_box(Vector3(13, 0.5, -9), Vector3(2.0, 1.0, 2.0), concrete)
	add_box(Vector3(-9, 0.4, 13), Vector3(1.6, 0.8, 1.6), concrete, 0.4)
	add_box(Vector3(9, 0.4, -13), Vector3(1.6, 0.8, 1.6), concrete, -0.4)

	# Decorative torii gate (no collision).
	var torii_red := Color(0.80, 0.25, 0.18)
	_stripe(Vector3(0, 2.9, -11), Vector3(7.0, 0.42, 0.42), torii_red, 0.0)
	_stripe(Vector3(0, 2.5, -11), Vector3(5.8, 0.18, 0.28), Color(0.35, 0.24, 0.18), 0.0)
	_stripe(Vector3(-2.6, 1.45, -11), Vector3(0.38, 2.9, 0.38), torii_red, 0.0)
	_stripe(Vector3(2.6, 1.45, -11), Vector3(0.38, 2.9, 0.38), torii_red, 0.0)

	# A few rocks in the corners.
	var rock_positions: Array[Vector2] = [
		Vector2(-15, -4), Vector2(15, 4), Vector2(-3, 14), Vector2(3, -14),
	]
	for point in rock_positions:
		_rock(point.x, point.y, randf_range(1.0, 1.4), randf_range(1.6, 2.4))

extends CharacterBody3D
## Puppet of the friend's phone: follows the network state smoothly and can be shot.
## Damage is forwarded to the real owner, who applies it to his own health.

const BASE_COLOR := Color(0.2, 0.45, 0.9)

var net
var active := false
var dead := true
var health := 100.0
var sliding := false
var invuln := false

var visual: Node3D
var arms: Node3D
var legs: Array[Node3D] = []
var col: CollisionShape3D
var _body_mat: StandardMaterial3D
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _speed := 0.0
var _anim := 0.0
var _flash := 0.0
var _tw: Tween

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m

func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

func _ready() -> void:
	collision_layer = 4   # same layer as the AI enemy, so weapons hit it
	collision_mask = 0
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col = CollisionShape3D.new()
	col.shape = cap
	col.position.y = 0.9
	col.disabled = true
	add_child(col)
	visual = Node3D.new()
	add_child(visual)
	_body_mat = _mat(BASE_COLOR)
	var dark := _mat(Color(0.15, 0.16, 0.2))
	var skin := _mat(Color(0.9, 0.7, 0.55))
	for sx in [-0.13, 0.13]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx, 0.8, 0.0)
		visual.add_child(pivot)
		_part(pivot, Vector3(0.2, 0.8, 0.24), Vector3(0, -0.4, 0), dark)
		legs.append(pivot)
	_part(visual, Vector3(0.52, 0.6, 0.3), Vector3(0, 1.1, 0), _body_mat)
	_part(visual, Vector3(0.28, 0.28, 0.28), Vector3(0, 1.55, 0), skin)
	_part(visual, Vector3(0.3, 0.08, 0.05), Vector3(0, 1.58, -0.15), dark)
	# Arms + gun pivot at the shoulders so they follow the friend's aim pitch.
	arms = Node3D.new()
	arms.position = Vector3(0, 1.3, 0)
	visual.add_child(arms)
	_part(arms, Vector3(0.13, 0.13, 0.5), Vector3(-0.28, -0.1, -0.25), _body_mat)
	_part(arms, Vector3(0.13, 0.13, 0.5), Vector3(0.2, -0.1, -0.3), _body_mat)
	_part(arms, Vector3(0.08, 0.12, 0.6), Vector3(0.08, -0.08, -0.5), dark)
	visible = false

func deactivate() -> void:
	active = false
	dead = true
	visible = false
	if col:
		col.set_deferred("disabled", true)

func activate(pos: Vector3, yaw: float) -> void:
	active = true
	dead = false
	health = 100.0
	sliding = false
	invuln = false
	visible = true
	global_position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	_target_pos = pos
	_target_yaw = yaw
	_reset_visual()
	col.set_deferred("disabled", false)

func _reset_visual() -> void:
	if _tw:
		_tw.kill()
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO
	visual.scale = Vector3.ONE
	arms.rotation = Vector3.ZERO
	_body_mat.albedo_color = BASE_COLOR

func apply_state(pos: Vector3, yaw: float, pitch: float, spd: float, is_dead: bool,
		is_slide: bool, hp: float, inv: bool) -> void:
	if not active:
		return
	_target_pos = pos
	_target_yaw = yaw
	_speed = spd
	arms.rotation.x = pitch
	sliding = is_slide
	invuln = inv
	health = hp
	if is_dead != dead:
		dead = is_dead
		col.set_deferred("disabled", dead)
		if dead:
			_play_death()
		else:
			_reset_visual()
			global_position = pos
			rotation.y = yaw

func _play_death() -> void:
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(visual, "rotation:x", PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD)
	_tw.parallel().tween_property(visual, "position:y", 0.25, 0.45)

func _physics_process(delta: float) -> void:
	if not active:
		return
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_body_mat.albedo_color = BASE_COLOR
	var k := 1.0 - exp(-20.0 * delta)
	if global_position.distance_to(_target_pos) > 6.0:
		global_position = _target_pos
	else:
		global_position = global_position.lerp(_target_pos, k)
	rotation.y = lerp_angle(rotation.y, _target_yaw, k)
	var crouch: bool = sliding and not dead
	visual.scale.y = lerpf(visual.scale.y, 0.65 if crouch else 1.0, k)
	_anim += delta * _speed * 2.2
	var sw: float = clampf(_speed / 5.0, 0.0, 1.0) * 0.7
	legs[0].rotation.x = sin(_anim) * sw
	legs[1].rotation.x = -sin(_anim) * sw

## Same interface as the AI enemy. The real health lives on the friend's phone;
## here we only predict the result for the hit marker and forward the damage.
func take_damage(amount: float, _attacker: Node, hit_pos: Vector3) -> bool:
	if not active or dead or invuln:
		return false
	var a := amount
	if hit_pos.y > global_position.y + 1.42 and not sliding:
		a *= 1.5
	health -= a
	_flash = 0.1
	_body_mat.albedo_color = Color.WHITE
	if net:
		net.send_hit(amount, hit_pos.y - global_position.y)
	return health <= 0.0

extends CharacterBody3D

## Playable NODEVERSE robot: WASD/arrows (camera-relative), Space jump, Shift sprint,
## E / Q interact, R respawn, V camera mode, right-drag orbit, wheel zoom.

signal interact_pressed
signal secondary_pressed
signal fell_in_water(pos: Vector3)

const WALK_SPEED: float = 4.2
const SPRINT_SPEED: float = 7.0
const ACCEL: float = 30.0
const AIR_ACCEL: float = 12.0
const GRAVITY: float = 24.0
const JUMP_VELOCITY: float = 7.4
const COYOTE_TIME: float = 0.12
const JUMP_BUFFER: float = 0.12
const FALL_Y: float = -1.2
const ROBOT_SCALE: float = 1.3
const CAM_MIN_PITCH: float = 15.0   # camera never looks flatter than 15 degrees
const CAM_MAX_PITCH: float = 80.0
const EDGE_LOOKAHEAD: float = 0.35  # how far ahead to probe for ground
const GROUND_MIN_Y: float = 0.2     # ground below this height counts as sea

var spawn_point: Vector3 = Vector3(0.0, 0.6, 0.0)
var last_safe: Vector3 = Vector3(0.0, 0.6, 0.0)

var cam: Camera3D
var cam_yaw: float = 45.0
var cam_pitch: float = 38.0
var cam_dist: float = 11.0
var cam_focus: Vector3 = Vector3.ZERO
var follow_mode: bool = false
var _orbiting: bool = false

var _pivot: Node3D
var _visual: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _boot_l: Node3D
var _boot_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _head: Node3D
var _base_pos: Dictionary = {}

var _coyote: float = 0.0
var _jump_buf: float = 0.0
var _phase: float = 0.0
var _squash: float = 0.0
var _was_on_floor: bool = false
var _prev_vy: float = 0.0
var _safe_timer: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = 1.1
	cs.shape = cap
	cs.position = Vector3(0.0, 0.56, 0.0)
	add_child(cs)

	_pivot = Node3D.new()
	_pivot.name = "VisualPivot"
	add_child(_pivot)
	var ps: PackedScene = load("res://scenes/assets/01_robot.tscn") as PackedScene
	if ps != null:
		_visual = ps.instantiate() as Node3D
		_pivot.add_child(_visual)
	_pivot.scale = Vector3.ONE * ROBOT_SCALE
	_leg_l = _find_part("Leg_L")
	_leg_r = _find_part("Leg_R")
	_boot_l = _find_part("BootSole_L")
	_boot_r = _find_part("BootSole_R")
	_arm_l = _find_part("ArmPivot_L")
	_arm_r = _find_part("ArmPivot_R")
	_head = _find_part("Head")

	cam = Camera3D.new()
	cam.name = "FollowCamera"
	cam.top_level = true
	cam.fov = 38.0
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	cam_focus = global_position
	_update_camera(1.0)

func _find_part(part_name: String) -> Node3D:
	if _visual == null:
		return null
	var n: Node = _visual.find_child(part_name, true, false)
	var n3: Node3D = n as Node3D
	if n3 != null:
		_base_pos[part_name] = n3.position
	return n3

func teleport_to(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO
	cam_focus = p

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and not ek.echo:
			if ek.keycode == KEY_SPACE:
				_jump_buf = JUMP_BUFFER
			elif ek.keycode == KEY_E:
				interact_pressed.emit()
			elif ek.keycode == KEY_Q:
				secondary_pressed.emit()
			elif ek.keycode == KEY_R:
				teleport_to(spawn_point)
			elif ek.keycode == KEY_V:
				follow_mode = not follow_mode
				if follow_mode:
					cam_pitch = 24.0
					cam_dist = 6.5
				else:
					cam_pitch = 38.0
					cam_dist = 11.0
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_dist = maxf(3.0, cam_dist * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_dist = minf(30.0, cam_dist * 1.1)
	elif event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		cam_yaw -= mm.relative.x * 0.3
		cam_pitch = clampf(cam_pitch + mm.relative.y * 0.25, CAM_MIN_PITCH, CAM_MAX_PITCH)

func _physics_process(delta: float) -> void:
	_time += delta
	var input_vec: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vec.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vec.y -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vec.x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vec.x -= 1.0

	var yaw: float = deg_to_rad(cam_yaw)
	var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish: Vector3 = right * input_vec.x + fwd * input_vec.y
	if wish.length() > 0.01:
		wish = wish.normalized()
	var speed: float = SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	var target: Vector3 = wish * speed
	var on_floor: bool = is_on_floor()
	var acc: float = ACCEL if on_floor else AIR_ACCEL
	velocity.x = move_toward(velocity.x, target.x, acc * delta)
	velocity.z = move_toward(velocity.z, target.z, acc * delta)

	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)
		velocity.y -= GRAVITY * delta
	_jump_buf = maxf(_jump_buf - delta, 0.0)
	if _jump_buf > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buf = 0.0
		_coyote = 0.0
		_squash = -0.12

	_block_water_edges(delta)
	_prev_vy = velocity.y
	move_and_slide()

	if is_on_floor() and not _was_on_floor and _prev_vy < -5.0:
		_squash = 0.18
	_was_on_floor = is_on_floor()

	if is_on_floor() and global_position.y > -0.2:
		_safe_timer += delta
		if _safe_timer > 0.35:
			_safe_timer = 0.0
			last_safe = global_position + Vector3(0.0, 0.1, 0.0)
	if global_position.y < FALL_Y:
		fell_in_water.emit(global_position)
		teleport_to(last_safe)

	_animate(delta)

## True if there is walkable ground (island, bridge, pier, prop) below `p` above the water line
func _has_ground(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 0.8, 0.0), p + Vector3(0.0, -3.0, 0.0))
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and (hit["position"] as Vector3).y > GROUND_MIN_Y

## Stops horizontal movement that would carry the robot past an edge into the sea.
## Each axis is tested separately so the robot can still slide along the shore.
func _block_water_edges(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if hv.length() < 0.01:
		return
	var pos := global_position
	var ahead := pos + hv.normalized() * EDGE_LOOKAHEAD + hv * delta
	if _has_ground(ahead):
		return
	if absf(velocity.x) > 0.001 and not _has_ground(pos + Vector3(signf(velocity.x) * EDGE_LOOKAHEAD + velocity.x * delta, 0.0, 0.0)):
		velocity.x = 0.0
	if absf(velocity.z) > 0.001 and not _has_ground(pos + Vector3(0.0, 0.0, signf(velocity.z) * EDGE_LOOKAHEAD + velocity.z * delta)):
		velocity.z = 0.0
	var hv2 := Vector3(velocity.x, 0.0, velocity.z)
	if hv2.length() > 0.01 and not _has_ground(pos + hv2.normalized() * EDGE_LOOKAHEAD + hv2 * delta):
		velocity.x = 0.0
		velocity.z = 0.0

func _animate(delta: float) -> void:
	var hs: float = Vector2(velocity.x, velocity.z).length()
	if hs > 0.3:
		var target_yaw: float = atan2(velocity.x, velocity.z)
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, target_yaw, 1.0 - exp(-14.0 * delta))
	var amp: float = clampf(hs / 4.2, 0.0, 1.5)
	if not is_on_floor():
		amp = 0.25
	_phase += delta * (4.0 + hs * 1.7)
	var s: float = sin(_phase)
	var swing: float = s * amp
	_set_z(_leg_l, "Leg_L", swing * 0.05)
	_set_z(_boot_l, "BootSole_L", swing * 0.05)
	_set_z(_leg_r, "Leg_R", -swing * 0.05)
	_set_z(_boot_r, "BootSole_R", -swing * 0.05)
	var arm_air: float = -70.0 if not is_on_floor() else 0.0
	if _arm_l != null:
		_arm_l.rotation_degrees.x = lerpf(_arm_l.rotation_degrees.x, -swing * 38.0 + arm_air, 1.0 - exp(-16.0 * delta))
	if _arm_r != null:
		_arm_r.rotation_degrees.x = lerpf(_arm_r.rotation_degrees.x, swing * 38.0 + arm_air, 1.0 - exp(-16.0 * delta))
	if _head != null and _base_pos.has("Head"):
		var hb: Vector3 = _base_pos["Head"]
		_head.position = Vector3(hb.x, hb.y + absf(s) * 0.014 * amp + sin(_time * 2.0) * 0.004, hb.z)
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-9.0 * delta))
	_pivot.scale = Vector3(1.0 + _squash, 1.0 - _squash, 1.0 + _squash) * ROBOT_SCALE

func _set_z(n: Node3D, key: String, dz: float) -> void:
	if n == null or not _base_pos.has(key):
		return
	var b: Vector3 = _base_pos[key]
	n.position = Vector3(b.x, b.y, b.z + dz)

func _process(delta: float) -> void:
	_update_camera(delta)

func _update_camera(delta: float) -> void:
	var goal: Vector3 = global_position + Vector3(0.0, 0.6, 0.0)
	cam_focus = cam_focus.lerp(goal, 1.0 - exp(-8.0 * delta))
	var yr: float = deg_to_rad(cam_yaw)
	cam_pitch = clampf(cam_pitch, CAM_MIN_PITCH, CAM_MAX_PITCH)
	var pr: float = deg_to_rad(cam_pitch)
	var offset: Vector3 = Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr)) * cam_dist
	cam.look_at_from_position(cam_focus + offset, cam_focus, Vector3.UP)

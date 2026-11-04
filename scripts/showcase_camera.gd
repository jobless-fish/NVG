extends Node3D

## Interactive Orbit / Pan / Zoom Camera Controller for AssetShowcase.tscn

var target := Vector3(0.0, 0.6, 0.0)
var yaw_deg := 45.0
var pitch_deg := 34.0
var distance := 31.0

var _orbiting := false
var _panning := false
var _cam: Camera3D

func _ready() -> void:
	_cam = get_node_or_null("Camera3D")
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "Camera3D"
		_cam.fov = 38.0
		_cam.far = 250.0
		add_child(_cam)
	_cam.current = true
	_update_cam()

	# Add lightweight help overlay
	var canvas := CanvasLayer.new()
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	var lbl := Label.new()
	lbl.text = "NODEVERSE 3D 에셋 쇼케이스 (총 70종 3D 모델 / sample-assets 53종 + objects 20종)\n" + \
		"• 우클릭 드래그: 회전 | 휠 클릭 / Shift+드래그: 이동 | 마우스 휠: 줌 | WASD/방향키: 이동\n" + \
		"• 숫자키 [0]: 전체 보기  [1]: 캐릭터·소품  [2]: 지형·자연  [3]: 다리·부두·울타리  [4]: 자료구조 모듈  [5]: 표지판  [6]: 연결섬 오브젝트 OBJ01-20"
	lbl.add_theme_font_size_override("font_size", 14)
	panel.add_child(lbl)
	canvas.add_child(panel)
	add_child(canvas)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT)):
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = maxf(2.5, distance * 0.88)
			_update_cam()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = minf(80.0, distance * 1.14)
			_update_cam()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			yaw_deg -= mm.relative.x * 0.32
			pitch_deg = clampf(pitch_deg + mm.relative.y * 0.28, 8.0, 82.0)
			_update_cam()
		elif _panning:
			var right := _cam.global_transform.basis.x
			var up := Vector3(right.z, 0.0, -right.x).normalized()
			var scale_pan := distance * 0.0016
			target -= right * mm.relative.x * scale_pan
			target += up * mm.relative.y * scale_pan
			_update_cam()
	elif event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_0:
			target = Vector3(0.0, 0.6, 0.0); distance = 31.0; yaw_deg = 45.0; pitch_deg = 35.0; _update_cam()
		elif k == KEY_1:
			target = Vector3(0.0, 0.6, -12.35); distance = 11.0; _update_cam()
		elif k == KEY_2:
			target = Vector3(0.0, 0.6, -7.85); distance = 12.0; _update_cam()
		elif k == KEY_3:
			target = Vector3(0.0, 0.6, -3.35); distance = 12.0; _update_cam()
		elif k == KEY_4:
			target = Vector3(0.0, 0.8, 1.85); distance = 14.0; _update_cam()
		elif k == KEY_5:
			target = Vector3(0.0, 0.6, 7.15); distance = 10.0; _update_cam()
		elif k == KEY_6:
			target = Vector3(0.0, 0.8, 8.4); distance = 14.0; _update_cam()

func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1.0
	if move.length_squared() > 0.0:
		move = move.normalized()
		var rad := deg_to_rad(yaw_deg)
		var fwd := Vector3(-sin(rad), 0.0, -cos(rad))
		var rgt := Vector3(cos(rad), 0.0, -sin(rad))
		var spd := maxf(4.0, distance * 0.45) * delta
		target += (rgt * move.x - fwd * move.y) * spd
		_update_cam()

func _update_cam() -> void:
	var yr := deg_to_rad(yaw_deg)
	var pr := deg_to_rad(pitch_deg)
	var offset := Vector3(
		sin(yr) * cos(pr),
		sin(pr),
		cos(yr) * cos(pr)
	) * distance
	_cam.look_at_from_position(target + offset, target, Vector3.UP)

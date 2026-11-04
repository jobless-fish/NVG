class_name BuilderDataStructs
extends RefCounted

## Builds assets 31-53:
## 31-35: array_tile_0..4
## 36: list_sign_floating
## 37-39: list_node_10, 20, 30
## 40-41: list_link_10_20, 20_30
## 42: stack_tower
## 43-48: conveyor variants
## 49-53: standing signs (ARRAY A/B, LIST, STACK, QUEUE)

static func build_array_tile(index_num: int) -> Node3D:
	var root := Node3D.new()
	root.name = "ArrayTile_%d" % index_num

	var mat_tan := MeshKit.mat_color("arr_tan", Color(0.72, 0.57, 0.35), 0.65, 0.0, "wood_oak")
	var mat_gold := MeshKit.mat_color("arr_gold", Color(0.90, 0.60, 0.14), 0.46, 0.06)
	var mat_digit := MeshKit.mat_color("arr_digit", Color(0.92, 0.86, 0.68), 0.50, 0.02)
	var mat_stone := MeshKit.mat_color("arr_stone", Color(0.66, 0.64, 0.60), 0.70, 0.03)
	var mat_stone_mid := MeshKit.mat_color("arr_stone_m", Color(0.50, 0.49, 0.48), 0.76, 0.04, "stone_ashlar")
	var mat_panel := MeshKit.mat_color("arr_panel", Color(0.32, 0.31, 0.30), 0.80, 0.05)

	var label_txt := str(index_num)

	# 1. Front Golden Index Tile + Tan Pedestal Base (at z = +0.16)
	MeshKit.add_part(root, "TileBase",
		MeshKit.beveled_box(Vector3(0.80, 0.10, 0.72), 0.016, 1, false),
		mat_tan, Vector3(0.0, 0.05, 0.18))
	MeshKit.add_part(root, "GoldBlock",
		MeshKit.beveled_box(Vector3(0.68, 0.20, 0.60), 0.022, 1, false),
		mat_gold, Vector3(0.0, 0.19, 0.18))
	MeshKit.add_part(root, "TileDigit",
		MeshKit.text_mesh_3d(label_txt, 42, 0.0085, 0.045),
		mat_digit, Vector3(0.0, 0.30, 0.18), Vector3(-90.0, 0.0, 0.0))

	# 2. Back Vertical Stone Index Backboard (at z = -0.30, facing +Z!)
	MeshKit.add_part(root, "WallPlinth",
		MeshKit.beveled_box(Vector3(0.86, 0.42, 0.28), 0.015, 1, false),
		mat_stone_mid, Vector3(0.0, 0.21, -0.30))
	MeshKit.add_part(root, "WallBackPanel",
		MeshKit.beveled_box(Vector3(0.74, 0.58, 0.14), 0.01, 1, false),
		mat_panel, Vector3(0.0, 0.68, -0.32))

	# Left & Right Stone Frame Jambs + Sill + 3 Top Coping Stones (matching 31_array_tile_0.png!)
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "WallPillar_%d" % int(sx),
			MeshKit.beveled_box(Vector3(0.11, 0.56, 0.22), 0.012, 1, false),
			mat_stone, Vector3(sx * 0.365, 0.69, -0.30))
	MeshKit.add_part(root, "WallSill",
		MeshKit.beveled_box(Vector3(0.84, 0.06, 0.23), 0.01, 1, false),
		mat_stone, Vector3(0.0, 0.43, -0.30))

	var cap_defs := [[-0.285, 0.26], [0.0, 0.27], [0.285, 0.26]]
	for k in range(3):
		var cd: Array = cap_defs[k]
		MeshKit.add_part(root, "WallTopCap_%d" % k,
			MeshKit.beveled_box(Vector3(cd[1], 0.10, 0.23), 0.012, 1, false),
			mat_stone, Vector3(cd[0], 1.01, -0.30))

	MeshKit.add_part(root, "WallDigit",
		MeshKit.text_mesh_3d(label_txt, 40, 0.0085, 0.055),
		mat_stone, Vector3(0.0, 0.70, -0.235))

	return root

static func _build_signboard_mesh_group(
	parent: Node3D,
	group_name: String,
	text_str: String,
	center_pos: Vector3,
	width: float = 1.28,
	height: float = 0.58,
	light_frame: bool = false
) -> Node3D:
	var grp := Node3D.new()
	grp.name = group_name
	grp.position = center_pos
	parent.add_child(grp)

	var frame_col := Color(1.0, 0.94, 0.84) if light_frame else Color(0.92, 0.82, 0.70)
	var mat_frame := MeshKit.mat_color("sign_frame_" + str(light_frame), frame_col, 0.56, 0.0, "wood_oak" if light_frame else "wood_brown")
	var mat_board := MeshKit.mat_color("sign_slate", Color(0.24, 0.25, 0.24), 0.76, 0.06)
	var mat_text := MeshKit.mat_color("sign_text", Color(0.95, 0.95, 0.92), 0.38, 0.02)

	var border := 0.075
	var depth := 0.11

	# Dark slate recessed center board
	MeshKit.add_part(grp, "SlateBoard",
		MeshKit.beveled_box(Vector3(width - border * 1.2, height - border * 1.2, depth * 0.72), 0.008, 1, false),
		mat_board, Vector3.ZERO)

	# 4 Bevelled Wooden Frame Rails
	MeshKit.add_part(grp, "FrameTop",
		MeshKit.beveled_box(Vector3(width, border, depth), 0.012, 1, false),
		mat_frame, Vector3(0.0, height * 0.5 - border * 0.5, 0.0))
	MeshKit.add_part(grp, "FrameBottom",
		MeshKit.beveled_box(Vector3(width, border, depth), 0.012, 1, false),
		mat_frame, Vector3(0.0, -height * 0.5 + border * 0.5, 0.0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(grp, "FrameSide_%d" % int(sx),
			MeshKit.beveled_box(Vector3(border, height - border * 1.6, depth), 0.012, 1, false),
			mat_frame, Vector3(sx * (width * 0.5 - border * 0.5), 0.0, 0.0))

	# 3D Extruded Lettering on front (+Z)
	var px_size := 0.0086 if text_str.length() >= 5 else 0.0098
	MeshKit.add_part(grp, "SignText",
		MeshKit.text_mesh_3d(text_str, 40, px_size, 0.048),
		mat_text, Vector3(0.0, 0.0, depth * 0.36 + 0.014))

	return grp

static func build_list_sign_floating() -> Node3D:
	var root := Node3D.new()
	root.name = "ListSignFloating"
	_build_signboard_mesh_group(root, "Board", "LIST", Vector3(0.0, 0.32, 0.0), 1.24, 0.58, false)
	return root

static func build_standing_sign(text_str: String, variant_b: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Sign_" + text_str + ("_B" if variant_b else "")

	var mat_post := MeshKit.mat_color("sign_post", Color(0.90, 0.82, 0.72), 0.64, 0.0, "wood_brown")
	var mat_stone := MeshKit.mat_color("sign_stone", Color(0.58, 0.59, 0.62), 0.74, 0.06)

	for sx: float in [-1.0, 1.0]:
		var px: float = sx * 0.39
		MeshKit.add_part(root, "StoneBase_%d" % int(sx),
			MeshKit.beveled_box(Vector3(0.21, 0.10, 0.21), 0.015, 1, false),
			mat_stone, Vector3(px, 0.05, 0.0))
		MeshKit.add_part(root, "WoodPost_%d" % int(sx),
			MeshKit.beveled_box(Vector3(0.11, 0.44, 0.11), 0.012, 1, false),
			mat_post, Vector3(px, 0.30, 0.0))

	_build_signboard_mesh_group(root, "Board", text_str, Vector3(0.0, 0.77, 0.0), 1.30, 0.58, variant_b)
	return root

static func build_list_node(val_num: int) -> Node3D:
	var root := Node3D.new()
	root.name = "ListNode_%d" % val_num

	var mat_body := MeshKit.mat_color("node_body", Color(0.11, 0.13, 0.17), 0.34, 0.55)
	var mat_seam := MeshKit.mat_color("node_seam", Color(0.05, 0.06, 0.08), 0.50, 0.40)
	var mat_lid := MeshKit.mat_color("node_lid", Color(0.19, 0.21, 0.26), 0.28, 0.48)
	var mat_num := MeshKit.mat_color("node_num", Color(0.90, 0.93, 0.96), 0.35, 0.08)
	var mat_cyan := MeshKit.mat_emissive("node_cyan", Color(0.18, 0.88, 1.0), Color(0.10, 0.76, 1.0), 1.65, 0.20)

	# Main dark metallic cube + recessed groove + bevelled top lid
	MeshKit.add_part(root, "CubeLower",
		MeshKit.beveled_box(Vector3(0.78, 0.54, 0.78), 0.022, 1, false),
		mat_body, Vector3(0.0, 0.27, 0.0))
	MeshKit.add_part(root, "SeamGroove",
		MeshKit.beveled_box(Vector3(0.73, 0.04, 0.73), 0.005, 1, false),
		mat_seam, Vector3(0.0, 0.555, 0.0))
	MeshKit.add_part(root, "TopLid",
		MeshKit.beveled_box(Vector3(0.78, 0.12, 0.78), 0.02, 1, false),
		mat_lid, Vector3(0.0, 0.63, 0.0))

	# Bold 3D Number on top ("10", "20", "30")
	MeshKit.add_part(root, "TopDigits",
		MeshKit.text_mesh_3d(str(val_num), 42, 0.0112, 0.045),
		mat_num, Vector3(0.0, 0.70, 0.0), Vector3(-90.0, 0.0, 0.0))

	# Outgoing glowing cyan port on +X (Nodes 10 & 20)
	if val_num == 10 or val_num == 20:
		MeshKit.add_part(root, "PortOutHousing",
			MeshKit.beveled_box(Vector3(0.08, 0.28, 0.30), 0.015, 1, false),
			mat_cyan, Vector3(0.41, 0.27, 0.0))
		MeshKit.add_part(root, "PortOutStub",
			MeshKit.beveled_box(Vector3(0.12, 0.11, 0.12), 0.01, 1, false),
			mat_cyan, Vector3(0.48, 0.27, 0.0))
		MeshKit.add_light(root, "PortGlowR", Color(0.18, 0.85, 1.0), 0.65, 1.8, Vector3(0.50, 0.27, 0.0))

	# Incoming glowing cyan socket flange on -X (Node 20)
	if val_num == 20:
		MeshKit.add_part(root, "PortInSocket",
			MeshKit.beveled_box(Vector3(0.06, 0.26, 0.28), 0.012, 1, false),
			mat_cyan, Vector3(-0.40, 0.27, 0.0))

	return root

static func build_list_link(second_link: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "ListLink_20_30" if second_link else "ListLink_10_20"

	var mat_cyan := MeshKit.mat_emissive("link_cyan", Color(0.20, 0.88, 1.0), Color(0.08, 0.72, 1.0), 1.45, 0.22)
	var mat_cyan_soft := MeshKit.mat_emissive("link_cyan_s", Color(0.35, 0.90, 1.0), Color(0.15, 0.65, 0.95), 1.05, 0.28)

	# Glowing cyan 3D pointer arrow pointing from -X to +X!
	# Left source flange at x = -0.28
	MeshKit.add_part(root, "SourceFlange",
		MeshKit.beveled_box(Vector3(0.075, 0.24, 0.28), 0.014, 1, false),
		mat_cyan, Vector3(-0.27, 0.18, 0.0))

	# 3D Arrow polygon in XZ plane (shaft + bold triangular head)
	var arrow_poly := PackedVector2Array([
		Vector2(-0.25, -0.065),
		Vector2(0.05, -0.065),
		Vector2(0.05, -0.185),
		Vector2(0.29, 0.0),
		Vector2(0.05, 0.185),
		Vector2(0.05, 0.065),
		Vector2(-0.25, 0.065)
	])
	MeshKit.add_part(root, "ArrowBody",
		MeshKit.extrude_polygon_xz(arrow_poly, 0.115),
		mat_cyan, Vector3(0.0, 0.18, 0.0))

	# Receiving port glow prism on back-right (seen in 40 & 41 PNGs)
	var sock_z := -0.12 if second_link else -0.10
	MeshKit.add_part(root, "TargetPortGlow",
		MeshKit.beveled_box(Vector3(0.16, 0.22, 0.18), 0.016, 1, false),
		mat_cyan_soft, Vector3(0.26, 0.22, sock_z))

	MeshKit.add_light(root, "LinkLight", Color(0.20, 0.88, 1.0), 0.7, 2.0, Vector3(0.02, 0.20, 0.0))
	return root

static func _make_chevron_mesh(scale_f: float = 1.0) -> ArrayMesh:
	var w := 0.065 * scale_f
	var arm := 0.20 * scale_f
	# L-shaped 90-degree chevron centered near origin, tip at (+arm*0.45, +arm*0.45)
	var poly := PackedVector2Array([
		Vector2(arm * 0.5, arm * 0.5),
		Vector2(-arm * 0.5, arm * 0.5),
		Vector2(-arm * 0.5, arm * 0.5 - w),
		Vector2(arm * 0.5 - w, arm * 0.5 - w),
		Vector2(arm * 0.5 - w, -arm * 0.5),
		Vector2(arm * 0.5, -arm * 0.5)
	])
	return MeshKit.extrude_polygon_xz(poly, 0.022)

static func build_stack_tower() -> Node3D:
	var root := Node3D.new()
	root.name = "StackTower"

	var mat_sand := MeshKit.mat_color("stk_sand", Color(0.78, 0.68, 0.48), 0.66, 0.02)
	var mat_sand_dark := MeshKit.mat_color("stk_sand_d", Color(0.62, 0.53, 0.36), 0.70, 0.02)
	var mat_brick := MeshKit.mat_color("stk_brick", Color(0.95, 0.93, 0.90), 0.78, 0.04, "brick_dark")
	var mat_coping := MeshKit.mat_color("stk_coping", Color(0.32, 0.31, 0.34), 0.65, 0.12)
	var mat_steel := MeshKit.mat_color("stk_steel", Color(0.50, 0.54, 0.60), 0.34, 0.68)
	var mat_pad := MeshKit.mat_color("stk_pad", Color(0.28, 0.33, 0.44), 0.38, 0.25)
	var mat_border := MeshKit.mat_emissive("stk_border", Color(0.92, 0.97, 1.0), Color(0.72, 0.88, 1.0), 1.4, 0.25)
	var mat_cyan := MeshKit.mat_emissive("stk_cyan", Color(0.28, 0.95, 1.0), Color(0.16, 0.86, 1.0), 2.8, 0.15)

	# 1. Stepped Tan Sandstone Foundation (y = 0 .. 0.22)
	MeshKit.add_part(root, "BaseLower",
		MeshKit.beveled_box(Vector3(1.74, 0.11, 1.74), 0.018, 1, false),
		mat_sand_dark, Vector3(0.0, 0.055, 0.0))
	MeshKit.add_part(root, "BaseUpper",
		MeshKit.beveled_box(Vector3(1.66, 0.11, 1.66), 0.016, 1, false),
		mat_sand, Vector3(0.0, 0.165, 0.0))

	# Front (+Z) sill corner studs (seen in 42_stack_tower.png!)
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "BaseStud_%d" % int(sx),
			MeshKit.beveled_box(Vector3(0.16, 0.06, 0.16), 0.012, 1, false),
			mat_sand, Vector3(sx * 0.58, 0.24, 0.66))

	# 2. U-Shaped Dark Coursed Brick Tower Walls (Open on front so all 3 stacked crates & steel cage are clearly visible!)
	var wall_h := 2.24
	var wall_y := 0.22 + wall_h * 0.5
	# Left wall (x = -0.64, recessed slightly from front so shaft projects forward cleanly)
	MeshKit.add_part(root, "BrickWallLeft",
		MeshKit.beveled_box(Vector3(0.36, wall_h, 1.18), 0.016, 1, false, 1.4),
		mat_brick, Vector3(-0.64, wall_y, -0.23))
	# Right wall (x = +0.64, recessed so isometric view sees 100% of stacked crates!)
	MeshKit.add_part(root, "BrickWallRight",
		MeshKit.beveled_box(Vector3(0.36, wall_h, 1.18), 0.016, 1, false, 1.4),
		mat_brick, Vector3(0.64, wall_y, -0.23))
	# Back wall (z = -0.64)
	MeshKit.add_part(root, "BrickWallBack",
		MeshKit.beveled_box(Vector3(0.96, wall_h, 0.36), 0.016, 1, false, 1.4),
		mat_brick, Vector3(0.0, wall_y, -0.64))

	# Top stone coping slabs on U-parapet
	var cope_y := 0.22 + wall_h + 0.045
	MeshKit.add_part(root, "CopingLeft",
		MeshKit.beveled_box(Vector3(0.38, 0.09, 1.20), 0.014, 1, false),
		mat_coping, Vector3(-0.64, cope_y, -0.23))
	MeshKit.add_part(root, "CopingRight",
		MeshKit.beveled_box(Vector3(0.38, 0.09, 1.20), 0.014, 1, false),
		mat_coping, Vector3(0.64, cope_y, -0.23))
	MeshKit.add_part(root, "CopingBack",
		MeshKit.beveled_box(Vector3(1.00, 0.09, 0.38), 0.014, 1, false),
		mat_coping, Vector3(0.0, cope_y, -0.64))

	# 3. Inner Steel Elevator Cage (Base + 4 Guide Columns + Top Lift Roof)
	var shaft_z := 0.18
	MeshKit.add_part(root, "LiftFloor",
		MeshKit.beveled_box(Vector3(0.84, 0.08, 0.84), 0.012, 1, false),
		mat_steel, Vector3(0.0, 0.25, shaft_z))

	var rail_h := 1.78
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "GuideColumn_%d_%d" % [int(sx), int(sz)],
				MeshKit.beveled_box(Vector3(0.075, rail_h, 0.075), 0.01, 1, false),
				mat_steel, Vector3(sx * 0.37, 0.28 + rail_h * 0.5, shaft_z + sz * 0.37))

	var roof_y := 2.10
	MeshKit.add_part(root, "LiftRoof",
		MeshKit.beveled_box(Vector3(0.90, 0.11, 0.90), 0.014, 1, false),
		mat_steel, Vector3(0.0, roof_y, shaft_z))

	# Glowing UP Arrow Pad on Lift Roof (arrow pointing toward -Z up-right!)
	MeshKit.add_part(root, "ArrowPadFrame",
		MeshKit.beveled_box(Vector3(0.66, 0.045, 0.66), 0.01, 1, false),
		mat_border, Vector3(0.0, roof_y + 0.065, shaft_z))
	MeshKit.add_part(root, "ArrowPadFace",
		MeshKit.beveled_box(Vector3(0.60, 0.052, 0.60), 0.008, 1, false),
		mat_pad, Vector3(0.0, roof_y + 0.068, shaft_z))

	var up_arrow_poly := PackedVector2Array([
		Vector2(-0.06, 0.19),
		Vector2(0.06, 0.19),
		Vector2(0.06, -0.02),
		Vector2(0.18, -0.02),
		Vector2(0.0, -0.21),
		Vector2(-0.18, -0.02),
		Vector2(-0.06, -0.02)
	])
	MeshKit.add_part(root, "UpArrowGlyph",
		MeshKit.extrude_polygon_xz(up_arrow_poly, 0.026),
		mat_cyan, Vector3(0.0, roof_y + 0.095, shaft_z))

	# 4. Three Stacked Crates Inside Elevator Shaft!
	for c_idx in range(3):
		var crate := BuilderCharsProps.build_crate("gold_top" if c_idx == 2 else "brown")
		crate.name = "StackedCrate_%d" % c_idx
		crate.scale = Vector3(0.76, 0.76, 0.76)
		crate.position = Vector3(0.0, 0.29 + float(c_idx) * 0.505, shaft_z)
		root.add_child(crate)

	# 5. STACK Sign Mounted on Top Parapet (facing +Z!)
	_build_signboard_mesh_group(root, "StackSign", "STACK", Vector3(0.0, cope_y + 0.30, -0.52), 1.16, 0.52, false)

	return root

static func _add_conveyor_button_pad(
	parent: Node3D,
	pad_name: String,
	z_pos: float,
	mode: String
) -> void:
	var pad := Node3D.new()
	pad.name = pad_name
	pad.position = Vector3(0.0, 0.25, z_pos)
	parent.add_child(pad)

	var is_gold := (mode == "gold_star")
	var mat_rim := MeshKit.mat_emissive("conv_rim_" + mode,
		Color(1.0, 0.92, 0.55) if is_gold else Color(0.92, 0.97, 1.0),
		Color(0.95, 0.78, 0.25) if is_gold else Color(0.65, 0.85, 1.0), 1.2, 0.25)
	var mat_face := MeshKit.mat_color("conv_face_" + mode,
		Color(0.55, 0.46, 0.26) if is_gold else Color(0.28, 0.33, 0.44), 0.36, 0.22)
	var mat_cyan := MeshKit.mat_emissive("conv_cyan", Color(0.32, 0.96, 1.0), Color(0.18, 0.86, 1.0), 2.8, 0.15)
	var mat_star := MeshKit.mat_emissive("conv_star", Color(1.0, 0.95, 0.38), Color(1.0, 0.86, 0.20), 2.8, 0.15)

	MeshKit.add_part(pad, "PadBase",
		MeshKit.beveled_box(Vector3(0.72, 0.06, 0.72), 0.012, 1, false),
		mat_rim, Vector3.ZERO)
	MeshKit.add_part(pad, "PadScreen",
		MeshKit.beveled_box(Vector3(0.65, 0.066, 0.65), 0.008, 1, false),
		mat_face, Vector3.ZERO)

	if mode == "chevron_up" or mode == "chevron_down":
		# Double nested glowing cyan chevrons aligned with 43 (up-left) and 44/45 (down-right)!
		var rot_y := -135.0 if mode == "chevron_up" else 45.0
		var chev_big := _make_chevron_mesh(1.15)
		var chev_small := _make_chevron_mesh(0.64)
		var shift := Vector3(-0.04, 0.0, 0.0) if mode == "chevron_up" else Vector3(0.04, 0.0, 0.0)
		MeshKit.add_part(pad, "ChevOuter", chev_big, mat_cyan, Vector3(0.0, 0.036, 0.0) + shift, Vector3(0.0, rot_y, 0.0))
		MeshKit.add_part(pad, "ChevInner", chev_small, mat_cyan, Vector3(0.0, 0.036, 0.0) - shift * 1.1, Vector3(0.0, rot_y, 0.0))
	elif mode == "gold_star":
		# 8-ray golden starburst indicator (matching 46_conveyor_two_buttons.png!)
		for i in range(4):
			MeshKit.add_part(pad, "StarRay_%d" % i,
				MeshKit.beveled_box(Vector3(0.32, 0.025, 0.075), 0.008, 1, false),
				mat_star, Vector3(0.0, 0.036, 0.0), Vector3(0.0, float(i) * 45.0, 0.0))

static func build_conveyor(variant: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Conveyor_" + variant

	var mat_chassis := MeshKit.mat_color("conv_chassis", Color(0.15, 0.16, 0.19), 0.52, 0.45)
	var mat_slat := MeshKit.mat_color("conv_slat", Color(0.24, 0.25, 0.26), 0.58, 0.25)
	var mat_rail := MeshKit.mat_color("conv_rail", Color(0.76, 0.78, 0.82), 0.30, 0.72)
	var mat_hole := MeshKit.mat_color("conv_hole", Color(0.14, 0.16, 0.22), 0.65, 0.35)
	var mat_gold_plate := MeshKit.mat_color("conv_gplate", Color(0.94, 0.76, 0.34), 0.32, 0.62)

	var width_x := 0.96
	var length_z := 1.72
	var belt_w := 0.78

	# Core chassis & rounded front/back belt rollers
	MeshKit.add_part(root, "Chassis",
		MeshKit.beveled_box(Vector3(belt_w, 0.20, length_z - 0.16), 0.012, 1, false),
		mat_chassis, Vector3(0.0, 0.11, 0.0))
	for sz: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "EndRoller_%d" % int(sz),
			MeshKit.beveled_cylinder(0.10, 0.10, belt_w, 16, 0.01, true),
			mat_chassis, Vector3(0.0, 0.11, sz * (length_z * 0.5 - 0.09)), Vector3(0.0, 0.0, 90.0))

	# 9 Transverse Dark Belt Slats
	var slat_cnt := 9
	var slat_z := (length_z - 0.22) / float(slat_cnt) - 0.016
	for i in range(slat_cnt):
		var zp := lerpf(-(length_z * 0.5 - 0.18), (length_z * 0.5 - 0.18), float(i) / float(slat_cnt - 1))
		MeshKit.add_part(root, "BeltSlat_%d" % i,
			MeshKit.beveled_box(Vector3(belt_w - 0.02, 0.036, slat_z), 0.006, 1, false),
			mat_slat, Vector3(0.0, 0.215, zp))

	# Brushed Silver Side Rails + Mechanical Roller Port Holes
	for sx: float in [-1.0, 1.0]:
		var sname := "R" if sx > 0.0 else "L"
		MeshKit.add_part(root, "SideRail_" + sname,
			MeshKit.beveled_box(Vector3(0.095, 0.24, length_z), 0.016, 1, false),
			mat_rail, Vector3(sx * (width_x * 0.5 - 0.047), 0.125, 0.0))
		for h_idx in range(8):
			var hz := lerpf(-length_z * 0.40, length_z * 0.40, float(h_idx) / 7.0)
			MeshKit.add_part(root, "RollerHole_%s_%d" % [sname, h_idx],
				MeshKit.beveled_box(Vector3(0.02, 0.11, 0.11), 0.004, 1, false),
				mat_hole, Vector3(sx * (width_x * 0.5 - 0.004), 0.115, hz))

	# Variant-specific top assemblies (43-48)
	if variant == "arrow_up":
		_add_conveyor_button_pad(root, "UpPad", -0.38, "chevron_up")
	elif variant == "arrow_down_a":
		_add_conveyor_button_pad(root, "DownPad", 0.38, "chevron_down")
	elif variant == "arrow_down_b":
		_add_conveyor_button_pad(root, "DownPad", 0.38, "chevron_down")
		# Side coupling bracket on +X rail (seen in 45_conveyor_arrow_down_b.png!)
		MeshKit.add_part(root, "SideCouplerBracket",
			MeshKit.beveled_box(Vector3(0.08, 0.11, 0.54), 0.012, 1, false),
			mat_rail, Vector3(width_x * 0.5 + 0.025, 0.13, -0.30))
	elif variant == "two_buttons":
		_add_conveyor_button_pad(root, "BackUpPad", -0.40, "chevron_up")
		_add_conveyor_button_pad(root, "FrontGoldPad", 0.40, "gold_star")
	elif variant == "gold_plate":
		# Metallic gold ribbed pressure plate at +Z front (47_conveyor_gold_plate.png)
		MeshKit.add_part(root, "GoldPlateBase",
			MeshKit.beveled_box(Vector3(0.72, 0.05, 0.68), 0.012, 1, false),
			mat_gold_plate, Vector3(0.0, 0.245, 0.38))
		for r_i in range(3):
			MeshKit.add_part(root, "GoldRib_%d" % r_i,
				MeshKit.beveled_box(Vector3(0.20, 0.032, 0.62), 0.008, 1, false),
				mat_gold_plate, Vector3((float(r_i) - 1.0) * 0.225, 0.278, 0.38))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				MeshKit.add_part(root, "Rivet_%d_%d" % [int(sx), int(sz)],
					MeshKit.beveled_cylinder(0.025, 0.025, 0.02, 10, 0.004, true),
					mat_chassis, Vector3(sx * 0.28, 0.292, 0.38 + sz * 0.25))
	elif variant == "crates":
		# Two golden framed crates riding along the conveyor (48_conveyor_crates.png)
		for idx in range(2):
			var c := BuilderCharsProps.build_crate("gold_top")
			c.name = "BeltCrate_%d" % idx
			c.scale = Vector3(0.86, 0.86, 0.86)
			c.position = Vector3(0.0, 0.23, 0.38 if idx == 0 else -0.38)
			root.add_child(c)

	return root

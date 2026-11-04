class_name BuilderCharsProps
extends RefCounted

## Builds assets 01-11:
## 01_robot (combining 01_robot_front, 02_robot_side, 03_robot_back, 04_robot_back_side)
## 05_boat, 06_lamp, 07_torch, 08_crane, 09_crate_brown, 10_crate_gold_top, 11_crate_gold_front

static func build_robot() -> Node3D:
	var root := Node3D.new()
	root.name = "Robot"

	var mat_white := MeshKit.mat_color("robot_white", Color(0.92, 0.94, 0.96), 0.28, 0.04)
	var mat_panel := MeshKit.mat_color("robot_panel", Color(0.82, 0.85, 0.89), 0.35, 0.06)
	var mat_joint := MeshKit.mat_color("robot_joint", Color(0.16, 0.19, 0.22), 0.42, 0.45)
	var mat_sole := MeshKit.mat_color("robot_sole", Color(0.36, 0.40, 0.45), 0.50, 0.20)
	var mat_visor := MeshKit.mat_color("robot_visor", Color(0.03, 0.09, 0.04), 0.10, 0.15)
	var mat_eye := MeshKit.mat_emissive("robot_eye", Color(0.45, 1.0, 0.42), Color(0.32, 1.0, 0.30), 2.8, 0.15)

	# --- LEGS & BOOTS (y = 0.0 .. 0.24) ---
	for side: float in [-1.0, 1.0]:
		var sname := "L" if side > 0.0 else "R"
		var lx: float = side * 0.105
		# Boot sole
		MeshKit.add_part(root, "BootSole_" + sname,
			MeshKit.beveled_box(Vector3(0.145, 0.045, 0.185), 0.015, 2, true),
			mat_sole, Vector3(lx, 0.0225, 0.015))
		# Boot upper / shin
		MeshKit.add_part(root, "Leg_" + sname,
			MeshKit.beveled_box(Vector3(0.138, 0.155, 0.155), 0.028, 3, true),
			mat_white, Vector3(lx, 0.115, 0.005))
		# Hip joint ring
		MeshKit.add_part(root, "HipJoint_" + sname,
			MeshKit.beveled_cylinder(0.055, 0.055, 0.05, 16, 0.008, true),
			mat_joint, Vector3(lx, 0.205, 0.0))

	# --- TORSO (y = 0.22 .. 0.54) ---
	MeshKit.add_part(root, "PelvisTrim",
		MeshKit.beveled_box(Vector3(0.33, 0.05, 0.24), 0.018, 2, true),
		mat_joint, Vector3(0.0, 0.235, 0.0))

	MeshKit.add_part(root, "TorsoBody",
		MeshKit.beveled_box(Vector3(0.38, 0.29, 0.28), 0.052, 3, true),
		mat_white, Vector3(0.0, 0.385, 0.0))

	# Front chest plate (+Z)
	MeshKit.add_part(root, "ChestPlate",
		MeshKit.beveled_box(Vector3(0.27, 0.19, 0.03), 0.012, 2, true),
		mat_panel, Vector3(0.0, 0.385, 0.135))

	# Glowing green chest core emblem (rounded triangle / heart gem)
	var gem_poly := PackedVector2Array([
		Vector2(-0.045, -0.028),
		Vector2(0.0, -0.036),
		Vector2(0.045, -0.028),
		Vector2(0.032, 0.005),
		Vector2(0.0, 0.038),
		Vector2(-0.032, 0.005)
	])
	MeshKit.add_part(root, "ChestCore",
		MeshKit.extrude_polygon_xz(gem_poly, 0.022),
		mat_eye, Vector3(0.0, 0.39, 0.148), Vector3(90.0, 0.0, 0.0))

	# Back torso panel (-Z) matching 03_robot_back
	MeshKit.add_part(root, "BackTorsoPanel",
		MeshKit.beveled_box(Vector3(0.25, 0.20, 0.025), 0.01, 2, true),
		mat_panel, Vector3(0.0, 0.385, -0.135))

	# --- ARMS ---
	var sph := SphereMesh.new()
	sph.radius = 0.052; sph.height = 0.104; sph.radial_segments = 16; sph.rings = 8
	var sph_am := MeshKit.prim_to_array_mesh(sph)
	for side: float in [-1.0, 1.0]:
		var sname := "L" if side > 0.0 else "R"
		MeshKit.add_part(root, "Shoulder_" + sname,
			sph_am, mat_joint, Vector3(side * 0.205, 0.455, 0.0))
		var arm_pivot := Node3D.new()
		arm_pivot.name = "ArmPivot_" + sname
		arm_pivot.position = Vector3(side * 0.215, 0.455, 0.0)
		arm_pivot.rotation_degrees = Vector3(4.0, 0.0, side * 16.0)
		root.add_child(arm_pivot)

		MeshKit.add_part(arm_pivot, "ArmUpper_" + sname,
			MeshKit.beveled_box(Vector3(0.105, 0.22, 0.118), 0.035, 3, true),
			mat_white, Vector3(side * 0.015, -0.105, 0.0))
		MeshKit.add_part(arm_pivot, "HandCuff_" + sname,
			MeshKit.beveled_box(Vector3(0.088, 0.052, 0.10), 0.018, 2, true),
			mat_joint, Vector3(side * 0.015, -0.215, 0.0))

	# --- NECK & HEAD (y = 0.52 .. 0.96) ---
	MeshKit.add_part(root, "Neck",
		MeshKit.beveled_cylinder(0.105, 0.105, 0.06, 18, 0.01, true),
		mat_joint, Vector3(0.0, 0.54, 0.0))

	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.74, 0.0)
	root.add_child(head)

	# Main rounded head shell
	MeshKit.add_part(head, "HeadShell",
		MeshKit.beveled_box(Vector3(0.50, 0.37, 0.42), 0.065, 3, true),
		mat_white, Vector3.ZERO)

	# Stepped top crown cap (seen clearly in 03_robot_back & 04_robot_back_side)
	MeshKit.add_part(head, "HeadTopCap",
		MeshKit.beveled_box(Vector3(0.39, 0.042, 0.31), 0.018, 2, true),
		mat_white, Vector3(0.0, 0.19, -0.005))

	# Back head detail panel & ridge grooves
	MeshKit.add_part(head, "HeadBackPanel",
		MeshKit.beveled_box(Vector3(0.31, 0.19, 0.028), 0.014, 2, true),
		mat_panel, Vector3(0.0, -0.02, -0.202))
	MeshKit.add_part(head, "HeadBackRidge",
		MeshKit.beveled_box(Vector3(0.33, 0.025, 0.025), 0.008, 1, false),
		mat_panel, Vector3(0.0, 0.105, -0.20))

	# Ear pads (02_robot_side & 04_robot_back_side)
	for side: float in [-1.0, 1.0]:
		var sname := "L" if side > 0.0 else "R"
		MeshKit.add_part(head, "EarPad_" + sname,
			MeshKit.beveled_box(Vector3(0.048, 0.155, 0.155), 0.02, 2, true),
			mat_white, Vector3(side * 0.252, -0.005, -0.005))

	# Front visor bezel & glossy screen (+Z)
	MeshKit.add_part(head, "VisorScreen",
		MeshKit.beveled_box(Vector3(0.39, 0.245, 0.035), 0.035, 3, true),
		mat_visor, Vector3(0.0, -0.01, 0.198))

	# Two glowing green square LED eyes
	for side: float in [-1.0, 1.0]:
		var sname := "L" if side > 0.0 else "R"
		MeshKit.add_part(head, "Eye_" + sname,
			MeshKit.beveled_box(Vector3(0.078, 0.078, 0.018), 0.015, 2, true),
			mat_eye, Vector3(side * 0.095, -0.01, 0.214))

	return root

static func build_boat() -> Node3D:
	var root := Node3D.new()
	root.name = "Boat"

	var mat_hull := MeshKit.mat_color("boat_hull", Color(0.95, 0.88, 0.82), 0.62, 0.0, "wood_boat")
	var mat_dark := MeshKit.mat_color("boat_dark", Color(0.75, 0.68, 0.62), 0.68, 0.0, "wood_boat")
	var mat_mast := MeshKit.mat_color("boat_mast", Color(0.88, 0.80, 0.72), 0.60, 0.0, "wood_brown")
	var stud_mesh := MeshKit.lego_stud(0.055, 0.035, 14)

	# Stepped Lego/voxel hull bottom keel (along Z from -0.82 stern to +0.86 bow)
	var keel_poly := PackedVector2Array([
		Vector2(0.0, 0.84),
		Vector2(0.20, 0.66),
		Vector2(0.34, 0.35),
		Vector2(0.36, -0.35),
		Vector2(0.24, -0.68),
		Vector2(0.10, -0.82),
		Vector2(-0.10, -0.82),
		Vector2(-0.24, -0.68),
		Vector2(-0.36, -0.35),
		Vector2(-0.34, 0.35),
		Vector2(-0.20, 0.66)
	])
	MeshKit.add_part(root, "HullBottom",
		MeshKit.extrude_polygon_xz(keel_poly, 0.14, 0.9),
		mat_dark, Vector3(0.0, 0.07, 0.0))

	# Cockpit floor
	MeshKit.add_part(root, "DeckFloor",
		MeshKit.beveled_box(Vector3(0.58, 0.05, 1.10), 0.01, 1, false),
		mat_dark, Vector3(0.0, 0.145, 0.0))

	# Stepped hull side walls (left & right gunwales)
	var seg_defs := [
		# [z_center, z_len, x_offset, thickness]
		[0.0, 0.76, 0.35, 0.10],
		[0.48, 0.30, 0.27, 0.10],
		[-0.48, 0.30, 0.28, 0.10]
	]
	for side: float in [-1.0, 1.0]:
		var sname := "L" if side > 0.0 else "R"
		for idx in range(seg_defs.size()):
			var d: Array = seg_defs[idx]
			MeshKit.add_part(root, "Gunwale_%s_%d" % [sname, idx],
				MeshKit.beveled_box(Vector3(d[3], 0.22, d[1]), 0.015, 1, false),
				mat_hull, Vector3(side * d[2], 0.24, d[0]))

	# Stepped Bow (+Z) deck & prow block
	MeshKit.add_part(root, "BowDeck",
		MeshKit.beveled_box(Vector3(0.46, 0.22, 0.26), 0.015, 1, false),
		mat_hull, Vector3(0.0, 0.24, 0.62))
	MeshKit.add_part(root, "BowProw",
		MeshKit.beveled_box(Vector3(0.24, 0.23, 0.22), 0.015, 1, false),
		mat_hull, Vector3(0.0, 0.245, 0.80))

	# Stepped Stern (-Z) deck & transom
	MeshKit.add_part(root, "SternDeck",
		MeshKit.beveled_box(Vector3(0.48, 0.22, 0.26), 0.015, 1, false),
		mat_hull, Vector3(0.0, 0.24, -0.60))
	MeshKit.add_part(root, "SternTip",
		MeshKit.beveled_box(Vector3(0.26, 0.23, 0.20), 0.015, 1, false),
		mat_hull, Vector3(0.0, 0.245, -0.78))

	# Rear cockpit bench with 2 Lego studs (seen in 05_boat.png!)
	MeshKit.add_part(root, "RearBench",
		MeshKit.beveled_box(Vector3(0.46, 0.13, 0.22), 0.015, 1, false),
		mat_hull, Vector3(0.0, 0.21, -0.30))
	MeshKit.add_part(root, "BenchStudL", stud_mesh, mat_hull, Vector3(-0.11, 0.275, -0.30))
	MeshKit.add_part(root, "BenchStudR", stud_mesh, mat_hull, Vector3(0.11, 0.275, -0.30))

	# Bow & Stern deck Lego studs
	MeshKit.add_part(root, "BowStudTip", stud_mesh, mat_hull, Vector3(0.0, 0.36, 0.81))
	MeshKit.add_part(root, "BowStudL", stud_mesh, mat_hull, Vector3(-0.10, 0.35, 0.63))
	MeshKit.add_part(root, "BowStudR", stud_mesh, mat_hull, Vector3(0.10, 0.35, 0.63))
	MeshKit.add_part(root, "SternStud1", stud_mesh, mat_hull, Vector3(0.0, 0.35, -0.61))
	MeshKit.add_part(root, "SternStud2", stud_mesh, mat_hull, Vector3(0.0, 0.36, -0.78))
	MeshKit.add_part(root, "SideStudL", stud_mesh, mat_hull, Vector3(-0.35, 0.35, 0.12))
	MeshKit.add_part(root, "SideStudR", stud_mesh, mat_hull, Vector3(0.35, 0.35, -0.05))

	# Central mast pedestal block + Mast + Cross-yardarm
	MeshKit.add_part(root, "MastPedestal",
		MeshKit.beveled_box(Vector3(0.38, 0.18, 0.32), 0.018, 1, false),
		mat_hull, Vector3(0.0, 0.24, 0.18))
	MeshKit.add_part(root, "MastPole",
		MeshKit.beveled_box(Vector3(0.075, 1.08, 0.075), 0.012, 1, false),
		mat_mast, Vector3(0.0, 0.84, 0.18))
	MeshKit.add_part(root, "Yardarm",
		MeshKit.beveled_box(Vector3(0.58, 0.068, 0.068), 0.012, 1, false),
		mat_mast, Vector3(0.0, 1.12, 0.18))
	MeshKit.add_part(root, "MastLashing",
		MeshKit.beveled_box(Vector3(0.11, 0.095, 0.105), 0.015, 1, false),
		mat_hull, Vector3(0.0, 1.12, 0.18))

	return root

static func build_lamp() -> Node3D:
	var root := Node3D.new()
	root.name = "Lamp"

	var mat_iron := MeshKit.mat_color("lamp_iron", Color(0.20, 0.21, 0.23), 0.42, 0.55)
	var mat_trim := MeshKit.mat_color("lamp_trim", Color(0.28, 0.29, 0.32), 0.38, 0.50)
	var mat_glow := MeshKit.mat_emissive("lamp_glass", Color(1.0, 0.94, 0.68), Color(1.0, 0.86, 0.42), 2.5, 0.18)

	# Stepped base
	MeshKit.add_part(root, "BasePlate",
		MeshKit.beveled_box(Vector3(0.28, 0.055, 0.28), 0.012, 1, false),
		mat_iron, Vector3(0.0, 0.0275, 0.0))
	MeshKit.add_part(root, "BaseStep",
		MeshKit.beveled_box(Vector3(0.21, 0.05, 0.21), 0.01, 1, false),
		mat_trim, Vector3(0.0, 0.08, 0.0))
	MeshKit.add_part(root, "LowerColumn",
		MeshKit.beveled_box(Vector3(0.13, 0.26, 0.13), 0.014, 1, false),
		mat_iron, Vector3(0.0, 0.23, 0.0))
	MeshKit.add_part(root, "MidCollar",
		MeshKit.beveled_box(Vector3(0.155, 0.04, 0.155), 0.008, 1, false),
		mat_trim, Vector3(0.0, 0.37, 0.0))

	# Slender post
	MeshKit.add_part(root, "Post",
		MeshKit.beveled_cylinder(0.048, 0.044, 0.56, 14, 0.005, true),
		mat_iron, Vector3(0.0, 0.66, 0.0))

	# Lantern base & glowing tapered glass housing
	MeshKit.add_part(root, "LanternBase",
		MeshKit.beveled_box(Vector3(0.18, 0.045, 0.18), 0.008, 1, false),
		mat_trim, Vector3(0.0, 0.955, 0.0))
	MeshKit.add_part(root, "LanternGlass",
		MeshKit.beveled_cylinder(0.095, 0.135, 0.22, 4, 0.006, false),
		mat_glow, Vector3(0.0, 1.085, 0.0), Vector3(0.0, 45.0, 0.0))

	# 4 corner iron struts around glass
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "Strut_%d_%d" % [int(sx), int(sz)],
				MeshKit.beveled_box(Vector3(0.024, 0.235, 0.024), 0.004, 1, false),
				mat_iron, Vector3(sx * 0.082, 1.085, sz * 0.082),
				Vector3(-sz * 6.5, 0.0, sx * 6.5))

	# Stepped pyramidal lantern roof cap
	MeshKit.add_part(root, "RoofBrim",
		MeshKit.beveled_box(Vector3(0.28, 0.04, 0.28), 0.01, 1, false),
		mat_iron, Vector3(0.0, 1.21, 0.0))
	MeshKit.add_part(root, "RoofMid",
		MeshKit.beveled_box(Vector3(0.20, 0.045, 0.20), 0.008, 1, false),
		mat_trim, Vector3(0.0, 1.25, 0.0))
	MeshKit.add_part(root, "RoofTop",
		MeshKit.beveled_box(Vector3(0.11, 0.045, 0.11), 0.008, 1, false),
		mat_iron, Vector3(0.0, 1.29, 0.0))

	MeshKit.add_light(root, "LampLight", Color(1.0, 0.88, 0.55), 0.9, 3.0, Vector3(0.0, 1.08, 0.0))
	return root

static func build_torch() -> Node3D:
	var root := Node3D.new()
	root.name = "Torch"

	var mat_stone := MeshKit.mat_color("torch_stone", Color(0.46, 0.45, 0.48), 0.78, 0.05)
	var mat_stone_dark := MeshKit.mat_color("torch_stone_dark", Color(0.30, 0.29, 0.32), 0.82, 0.05)
	var mat_wood := MeshKit.mat_color("torch_wood", Color(0.92, 0.86, 0.78), 0.68, 0.0, "wood_brown")
	var mat_ember := MeshKit.mat_emissive("torch_ember", Color(0.55, 0.15, 0.05), Color(0.85, 0.22, 0.04), 1.5, 0.6)
	var mat_flame_out := MeshKit.mat_emissive("torch_flame_out", Color(1.0, 0.52, 0.12), Color(1.0, 0.45, 0.08), 2.6, 0.2)
	var mat_flame_in := MeshKit.mat_emissive("torch_flame_in", Color(1.0, 0.92, 0.35), Color(1.0, 0.88, 0.28), 3.2, 0.15)

	# Stone base
	MeshKit.add_part(root, "BaseStone",
		MeshKit.beveled_cylinder(0.16, 0.12, 0.09, 8, 0.012, false),
		mat_stone, Vector3(0.0, 0.045, 0.0), Vector3(0.0, 22.5, 0.0))

	# Wooden post
	MeshKit.add_part(root, "WoodPost",
		MeshKit.beveled_cylinder(0.078, 0.078, 0.58, 8, 0.008, false),
		mat_wood, Vector3(0.0, 0.37, 0.0), Vector3(0.0, 22.5, 0.0))

	# Stone brazier bowl
	MeshKit.add_part(root, "BrazierLower",
		MeshKit.beveled_cylinder(0.085, 0.165, 0.12, 8, 0.01, false),
		mat_stone_dark, Vector3(0.0, 0.71, 0.0), Vector3(0.0, 22.5, 0.0))
	MeshKit.add_part(root, "BrazierRim",
		MeshKit.beveled_cylinder(0.165, 0.175, 0.13, 8, 0.012, false),
		mat_stone, Vector3(0.0, 0.83, 0.0), Vector3(0.0, 22.5, 0.0))

	# Vertical stone ribs on brazier
	for i in range(8):
		var ang := TAU * float(i) / 8.0 + PI / 8.0
		MeshKit.add_part(root, "Rib_%d" % i,
			MeshKit.beveled_box(Vector3(0.032, 0.14, 0.035), 0.005, 1, false),
			mat_stone_dark,
			Vector3(cos(ang) * 0.155, 0.82, sin(ang) * 0.155),
			Vector3(0.0, -rad_to_deg(ang), 0.0))

	MeshKit.add_part(root, "EmberBed",
		MeshKit.beveled_cylinder(0.125, 0.125, 0.03, 10, 0.005, true),
		mat_ember, Vector3(0.0, 0.895, 0.0))

	# Stylized 3D flame (layered tapered polyhedra)
	MeshKit.add_part(root, "FlameOuter",
		MeshKit.beveled_cylinder(0.115, 0.025, 0.24, 7, 0.01, true),
		mat_flame_out, Vector3(0.0, 1.01, 0.0))
	MeshKit.add_part(root, "FlameTip",
		MeshKit.beveled_cylinder(0.055, 0.008, 0.14, 6, 0.005, true),
		mat_flame_out, Vector3(-0.01, 1.15, 0.01), Vector3(6.0, 0.0, -8.0))
	MeshKit.add_part(root, "FlameCore",
		MeshKit.beveled_cylinder(0.078, 0.018, 0.17, 7, 0.008, true),
		mat_flame_in, Vector3(0.01, 0.99, 0.015))

	MeshKit.add_light(root, "TorchLight", Color(1.0, 0.65, 0.22), 1.0, 3.2, Vector3(0.0, 1.05, 0.0))
	return root

static func build_crane() -> Node3D:
	var root := Node3D.new()
	root.name = "Crane"

	var mat_stone := MeshKit.mat_color("crane_stone", Color(0.76, 0.75, 0.74), 0.68, 0.05)
	var mat_stone_dark := MeshKit.mat_color("crane_stone_d", Color(0.55, 0.55, 0.58), 0.65, 0.15)
	var mat_post := MeshKit.mat_color("crane_post", Color(0.92, 0.84, 0.76), 0.58, 0.0, "wood_brown")
	var mat_boom := MeshKit.mat_color("crane_boom", Color(0.96, 0.90, 0.80), 0.52, 0.0, "wood_oak")
	var mat_metal := MeshKit.mat_color("crane_metal", Color(0.45, 0.47, 0.52), 0.38, 0.65)
	var stud_mesh := MeshKit.lego_stud(0.068, 0.042, 16)

	# Stepped grey stone foundation
	MeshKit.add_part(root, "BaseSlab",
		MeshKit.beveled_box(Vector3(0.76, 0.11, 0.76), 0.018, 1, false),
		mat_stone, Vector3(0.0, 0.055, 0.0))
	MeshKit.add_part(root, "BaseCollar",
		MeshKit.beveled_cylinder(0.26, 0.25, 0.15, 8, 0.015, false),
		mat_stone, Vector3(0.0, 0.185, 0.0), Vector3(0.0, 22.5, 0.0))

	# Vertical brown timber mast column
	MeshKit.add_part(root, "MastColumn",
		MeshKit.beveled_cylinder(0.135, 0.135, 0.88, 20, 0.01, true),
		mat_post, Vector3(0.0, 0.68, 0.0))

	# Slewing stone/metal turret & side housing (+X side as in 08_crane.png)
	MeshKit.add_part(root, "TurretBase",
		MeshKit.beveled_box(Vector3(0.38, 0.20, 0.42), 0.018, 1, false),
		mat_stone_dark, Vector3(0.0, 1.18, 0.0))
	MeshKit.add_part(root, "SideHousing",
		MeshKit.beveled_box(Vector3(0.24, 0.28, 0.30), 0.018, 1, false),
		mat_stone, Vector3(0.24, 1.25, -0.02))
	MeshKit.add_part(root, "TopCap",
		MeshKit.beveled_box(Vector3(0.34, 0.12, 0.34), 0.016, 1, false),
		mat_stone, Vector3(0.0, 1.49, 0.0))
	MeshKit.add_part(root, "CenterNeck",
		MeshKit.beveled_box(Vector3(0.26, 0.18, 0.28), 0.012, 1, false),
		mat_post, Vector3(0.0, 1.36, 0.0))

	# Horizontal wooden boom along Z (front tip at +Z, rear counter-jib at -Z)
	MeshKit.add_part(root, "BoomBeam",
		MeshKit.beveled_box(Vector3(0.22, 0.15, 1.66), 0.016, 1, false),
		mat_boom, Vector3(0.0, 1.37, 0.28))

	# Diagonal wood knee brace under front boom
	MeshKit.add_part(root, "BoomBrace",
		MeshKit.beveled_box(Vector3(0.13, 0.24, 0.13), 0.012, 1, false),
		mat_post, Vector3(0.0, 1.24, 0.18), Vector3(-35.0, 0.0, 0.0))

	# Rear counterweight stone block under -Z counter-jib
	MeshKit.add_part(root, "CounterWeight",
		MeshKit.beveled_box(Vector3(0.22, 0.18, 0.30), 0.015, 1, false),
		mat_stone_dark, Vector3(0.0, 1.22, -0.39))

	# Lego studs along wooden boom (4 in front + 1 in back, matching 08_crane.png!)
	for z_pos: float in [0.32, 0.54, 0.76, 0.98, -0.40]:
		MeshKit.add_part(root, "BoomStud_%d" % int(z_pos * 100),
			stud_mesh, mat_boom, Vector3(0.0, 1.445, z_pos))

	# Trolley & Hanging Hook assembly at +Z tip (z = 0.96)
	MeshKit.add_part(root, "Trolley",
		MeshKit.beveled_box(Vector3(0.16, 0.09, 0.24), 0.01, 1, false),
		mat_stone_dark, Vector3(0.0, 1.255, 0.88))
	MeshKit.add_part(root, "ChainUpper",
		MeshKit.beveled_cylinder(0.026, 0.026, 0.22, 10, 0.004, true),
		mat_metal, Vector3(0.0, 1.13, 0.98))
	MeshKit.add_part(root, "PulleyBlock",
		MeshKit.beveled_box(Vector3(0.13, 0.24, 0.13), 0.022, 2, false),
		mat_stone_dark, Vector3(0.0, 0.94, 0.98))

	# Sculpted 3D Crane Hook (in YZ/XY plane)
	var hook_poly := PackedVector2Array([
		Vector2(-0.025, 0.08),
		Vector2(0.025, 0.08),
		Vector2(0.032, -0.01),
		Vector2(0.075, -0.06),
		Vector2(0.055, -0.125),
		Vector2(-0.025, -0.135),
		Vector2(-0.078, -0.085),
		Vector2(-0.068, -0.035),
		Vector2(-0.035, -0.045),
		Vector2(-0.038, -0.075),
		Vector2(0.012, -0.085),
		Vector2(0.028, -0.055),
		Vector2(-0.025, 0.00)
	])
	MeshKit.add_part(root, "CraneHook",
		MeshKit.extrude_polygon_xz(hook_poly, 0.045),
		mat_metal, Vector3(0.0, 0.76, 0.98), Vector3(90.0, 45.0, 0.0))

	return root

static func build_crate(variant: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Crate_" + variant

	var tex_key := "wood_brown" if variant == "brown" else "wood_gold"
	var frame_tint := Color(0.95, 0.86, 0.76) if variant == "brown" else Color(1.0, 0.96, 0.86)
	var panel_tint := Color(0.78, 0.69, 0.60) if variant == "brown" else Color(0.88, 0.80, 0.68)

	var mat_frame := MeshKit.mat_color("crate_f_" + variant, frame_tint, 0.58, 0.0, tex_key)
	var mat_panel := MeshKit.mat_color("crate_p_" + variant, panel_tint, 0.66, 0.0, tex_key)

	var s := 0.66
	var hs := s * 0.5
	var rail := 0.075
	var recess := 0.032
	var cy := hs

	# Inner recessed wooden core (deepened slightly so top & side frames cast crisp recessed shadows!)
	var core_h := s - (0.02 if variant == "gold_front" else rail * 1.15)
	MeshKit.add_part(root, "InnerCore",
		MeshKit.beveled_box(Vector3(s - recess * 2.2, core_h, s - recess * 2.2), 0.01, 1, false),
		mat_panel, Vector3(0.0, cy - (0.0 if variant == "gold_front" else 0.012), 0.0))

	# 4 vertical corner posts
	var post_mesh := MeshKit.beveled_box(Vector3(rail, s, rail), 0.012, 1, false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var off := hs - rail * 0.5
			MeshKit.add_part(root, "CornerPost_%d_%d" % [int(sx), int(sz)],
				post_mesh, mat_frame, Vector3(sx * off, cy, sz * off))

	# Bottom & Top horizontal rails along X and Z
	var span := s - rail * 1.6
	var hrail_x := MeshKit.beveled_box(Vector3(span, rail, rail), 0.01, 1, false)
	var hrail_z := MeshKit.beveled_box(Vector3(rail, rail, span), 0.01, 1, false)
	for sy: float in [-1.0, 1.0]:
		var ry := cy + sy * (hs - rail * 0.5)
		for sz: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "RailX_%d_%d" % [int(sy), int(sz)],
				hrail_x, mat_frame, Vector3(0.0, ry, sz * (hs - rail * 0.5)))
		for sx: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "RailZ_%d_%d" % [int(sy), int(sx)],
				hrail_z, mat_frame, Vector3(sx * (hs - rail * 0.5), ry, 0.0))

	# Plank slats inside side panels for crisp 3D wood-slat shadow lines
	var slat_len := s - rail * 2.02
	var slat_h := (s - rail * 2.0) / 3.0 - 0.012
	for i in range(3):
		var py := cy + (float(i) - 1.0) * (slat_h + 0.012)
		for sz: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "SideSlatZ_%d_%d" % [i, int(sz)],
				MeshKit.beveled_box(Vector3(slat_len, slat_h, 0.022), 0.005, 1, false),
				mat_panel, Vector3(0.0, py, sz * (hs - recess)))
		for sx: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "SideSlatX_%d_%d" % [i, int(sx)],
				MeshKit.beveled_box(Vector3(0.022, slat_h, slat_len), 0.005, 1, false),
				mat_panel, Vector3(sx * (hs - recess), py, 0.0))

	# Top face: 11_crate_gold_front has a flush planked top lid; 09 & 10 have recessed slatted tops!
	if variant == "gold_front":
		for i in range(3):
			var px := (float(i) - 1.0) * ((s - rail * 1.4) / 3.0)
			MeshKit.add_part(root, "TopFlushPlank_%d" % i,
				MeshKit.beveled_box(Vector3((s - rail * 1.5) / 3.0 - 0.008, 0.035, s - rail * 1.4), 0.006, 1, false),
				mat_frame, Vector3(px, s - 0.018, 0.0))
	else:
		for i in range(3):
			var px := (float(i) - 1.0) * (slat_h + 0.012)
			MeshKit.add_part(root, "TopRecessedSlat_%d" % i,
				MeshKit.beveled_box(Vector3(slat_h, 0.022, slat_len), 0.005, 1, false),
				mat_panel, Vector3(px, s - rail * 0.68, 0.0))

	return root

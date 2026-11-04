class_name BuilderTerrainNature
extends RefCounted

## Builds assets 12-22:
## 12_ground_grass_studs, 13_ground_grass_flat, 14_ground_stone,
## 15_plaza_half, 16_rocks, 17_waterfall,
## 18_lily_pad_top, 19_lily_pad_pair, 20_lily_flower,
## 21_tree_short, 22_tree_tall

static func build_ground_block(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Ground_" + kind

	var mat_earth := MeshKit.mat_color("earth_base", Color(1.0, 0.96, 0.92), 0.78, 0.0, "earth_strata")
	MeshKit.add_part(root, "DirtBody",
		MeshKit.beveled_box(Vector3(1.0, 0.84, 1.0), 0.022, 1, false, 1.0),
		mat_earth, Vector3(0.0, 0.42, 0.0))

	if kind == "stone":
		var mat_stone_rim := MeshKit.mat_color("ground_stone_rim", Color(0.48, 0.47, 0.46), 0.76, 0.04)
		var mat_paver := MeshKit.mat_color("ground_paver", Color(0.68, 0.65, 0.60), 0.68, 0.03)
		var mat_paver_alt := MeshKit.mat_color("ground_paver_alt", Color(0.60, 0.57, 0.53), 0.72, 0.03)
		MeshKit.add_part(root, "StoneCapBase",
			MeshKit.beveled_box(Vector3(1.01, 0.16, 1.01), 0.018, 1, false),
			mat_stone_rim, Vector3(0.0, 0.91, 0.0))

		# Running-bond 3D stone pavers on top (matching 14_ground_stone.png!)
		var rows := 5
		var row_w := 0.96 / float(rows)
		for r in range(rows):
			var z_c := -0.48 + (float(r) + 0.5) * row_w
			var cols := 3 if (r % 2 == 0) else 4
			for c in range(cols):
				var x0 := -0.48 + float(c) * (0.96 / float(cols))
				var x1 := -0.48 + float(c + 1) * (0.96 / float(cols))
				if r % 2 == 1 and c == 0:
					x1 = -0.48 + 0.18
				elif r % 2 == 1 and c == cols - 1:
					x0 = 0.48 - 0.18
				elif r % 2 == 1:
					x0 = -0.30 + float(c - 1) * 0.30
					x1 = x0 + 0.30
				var bw := (x1 - x0) - 0.016
				var bz := row_w - 0.016
				var m := mat_paver if ((r + c) % 2 == 0) else mat_paver_alt
				MeshKit.add_part(root, "Paver_%d_%d" % [r, c],
					MeshKit.beveled_box(Vector3(bw, 0.032, bz), 0.006, 1, false),
					m, Vector3((x0 + x1) * 0.5, 0.995, z_c))
	else:
		var mat_grass := MeshKit.mat_color("grass_cap", Color(1.0, 1.0, 1.0), 0.62, 0.0, "grass_top")
		var mat_tuft := MeshKit.mat_color("grass_tuft", Color(0.50, 0.84, 0.20), 0.55, 0.0)
		var mat_tuft_dark := MeshKit.mat_color("grass_tuft_d", Color(0.32, 0.66, 0.14), 0.58, 0.0)
		MeshKit.add_part(root, "GrassCap",
			MeshKit.beveled_box(Vector3(1.01, 0.17, 1.01), 0.022, 1, false),
			mat_grass, Vector3(0.0, 0.915, 0.0))

		if kind == "grass_studs":
			# Rich cluster of Lego-like foliage blocks & studs matching 12_ground_grass_studs.png!
			var clumps := [
				# [x, z, sx, sy, sz, rot_y, dark?]
				[-0.32, 0.30, 0.16, 0.09, 0.16, 12.0, true],
				[-0.14, 0.22, 0.18, 0.08, 0.16, -8.0, false],
				[0.02, 0.34, 0.14, 0.08, 0.14, 5.0, false],
				[0.18, 0.18, 0.17, 0.10, 0.17, 18.0, true],
				[0.32, 0.04, 0.22, 0.08, 0.16, -15.0, false],
				[-0.22, -0.04, 0.24, 0.07, 0.22, 0.0, false],
				[0.04, -0.02, 0.14, 0.06, 0.14, 22.0, false],
				[0.24, -0.24, 0.20, 0.10, 0.18, -10.0, true],
				[-0.04, -0.34, 0.17, 0.09, 0.17, 8.0, true],
				[-0.28, -0.28, 0.16, 0.07, 0.16, -5.0, false],
				[0.36, -0.14, 0.13, 0.07, 0.13, 0.0, false],
				[-0.36, 0.08, 0.13, 0.07, 0.14, 15.0, false]
			]
			for idx in range(clumps.size()):
				var c: Array = clumps[idx]
				var cm := mat_tuft_dark if c[6] else mat_tuft
				MeshKit.add_part(root, "StudClump_%d" % idx,
					MeshKit.beveled_box(Vector3(c[2], c[3], c[4]), 0.018, 1, false),
					cm, Vector3(c[0], 1.0 + c[3] * 0.45, c[1]), Vector3(0.0, c[5], 0.0))

	return root

static func build_plaza_half() -> Node3D:
	var root := Node3D.new()
	root.name = "PlazaHalf"

	var mat_sand := MeshKit.mat_color("plaza_sand", Color(0.72, 0.66, 0.56), 0.68, 0.02)
	var mat_cobble_a := MeshKit.mat_color("plaza_cob_a", Color(0.70, 0.64, 0.55), 0.70, 0.02)
	var mat_cobble_b := MeshKit.mat_color("plaza_cob_b", Color(0.61, 0.55, 0.47), 0.74, 0.02)
	var mat_step_dark := MeshKit.mat_color("plaza_step_d", Color(0.38, 0.36, 0.35), 0.80, 0.04)
	var mat_step_mid := MeshKit.mat_color("plaza_step_m", Color(0.55, 0.51, 0.46), 0.74, 0.03)

	var holder := Node3D.new()
	holder.name = "SemicircleBody"
	holder.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	root.add_child(holder)

	# Base semicircular core (x >= 0, angle -PI/2 .. +PI/2)
	var base_poly := PackedVector2Array()
	var segs := 28
	for i in range(segs + 1):
		var a := -PI * 0.5 + PI * float(i) / float(segs)
		base_poly.append(Vector2(cos(a) * 1.88, sin(a) * 1.88))
	MeshKit.add_part(holder, "CoreBase",
		MeshKit.extrude_polygon_xz(base_poly, 0.26),
		mat_step_dark, Vector3(0.0, 0.13, 0.0))

	# Outer Tier 1 & Tier 2 sawtooth/scalloped stone blocks (matching 15_plaza_half.png!)
	var tooth_mesh_low := MeshKit.beveled_box(Vector3(0.28, 0.13, 0.28), 0.015, 1, false)
	var tooth_mesh_high := MeshKit.beveled_box(Vector3(0.28, 0.13, 0.28), 0.015, 1, false)
	for i in range(13):
		var a := -PI * 0.46 + PI * 0.92 * float(i) / 12.0
		MeshKit.add_part(holder, "OuterToothLow_%d" % i,
			tooth_mesh_low, mat_step_dark,
			Vector3(cos(a) * 1.92, 0.075, sin(a) * 1.92),
			Vector3(0.0, -rad_to_deg(a) + 45.0, 0.0))
	for i in range(12):
		var a := -PI * 0.44 + PI * 0.88 * float(i) / 11.0
		MeshKit.add_part(holder, "OuterToothMid_%d" % i,
			tooth_mesh_high, mat_step_mid,
			Vector3(cos(a) * 1.76, 0.195, sin(a) * 1.76),
			Vector3(0.0, -rad_to_deg(a) + 45.0, 0.0))

	# Upper circular cobblestone platform (radius 1.62)
	var upper_poly := PackedVector2Array()
	for i in range(segs + 1):
		var a := -PI * 0.5 + PI * float(i) / float(segs)
		upper_poly.append(Vector2(cos(a) * 1.64, sin(a) * 1.64))
	MeshKit.add_part(holder, "UpperDeck",
		MeshKit.extrude_polygon_xz(upper_poly, 0.12),
		mat_step_dark, Vector3(0.0, 0.28, 0.0))

	# Central semicircular sandstone medallion (radius 0.42)
	var med_poly := PackedVector2Array()
	for i in range(18 + 1):
		var a := -PI * 0.5 + PI * float(i) / 18.0
		med_poly.append(Vector2(cos(a) * 0.41, sin(a) * 0.41))
	MeshKit.add_part(holder, "CenterMedallion",
		MeshKit.extrude_polygon_xz(med_poly, 0.045),
		mat_sand, Vector3(0.005, 0.352, 0.0))

	# 5 Concentric rings of 3D radial cobblestone wedges!
	var radii := [0.43, 0.66, 0.89, 1.12, 1.36, 1.60]
	var counts := [10, 14, 18, 22, 26]
	for ring_idx in range(5):
		var r_in: float = radii[ring_idx] + 0.012
		var r_out: float = radii[ring_idx + 1] - 0.012
		var cnt: int = counts[ring_idx]
		for k in range(cnt):
			var a0 := -PI * 0.5 + PI * (float(k) + 0.06) / float(cnt)
			var a1 := -PI * 0.5 + PI * (float(k + 1) - 0.06) / float(cnt)
			var am := (a0 + a1) * 0.5
			var w_poly := PackedVector2Array([
				Vector2(cos(a0) * r_in, sin(a0) * r_in),
				Vector2(cos(am) * r_in, sin(am) * r_in),
				Vector2(cos(a1) * r_in, sin(a1) * r_in),
				Vector2(cos(a1) * r_out, sin(a1) * r_out),
				Vector2(cos(am) * r_out, sin(am) * r_out),
				Vector2(cos(a0) * r_out, sin(a0) * r_out)
			])
			var cm := mat_cobble_a if ((ring_idx + k) % 2 == 0) else mat_cobble_b
			MeshKit.add_part(holder, "Cobble_%d_%d" % [ring_idx, k],
				MeshKit.extrude_polygon_xz(w_poly, 0.042),
				cm, Vector3(0.0, 0.35, 0.0))

	return root

static func build_rocks() -> Node3D:
	var root := Node3D.new()
	root.name = "Rocks"

	var mat_light := MeshKit.mat_color("rock_light", Color(0.62, 0.59, 0.55), 0.80, 0.03)
	var mat_mid := MeshKit.mat_color("rock_mid", Color(0.50, 0.48, 0.46), 0.82, 0.04)
	var mat_dark := MeshKit.mat_color("rock_dark", Color(0.38, 0.37, 0.38), 0.85, 0.04)

	# Stepped blocky rock formation matching 16_rocks.png!
	var blocks := [
		# [name, size, pos, bevel, mat]
		["MainSpire", Vector3(0.56, 1.02, 0.54), Vector3(-0.06, 0.51, -0.10), 0.045, mat_light],
		["SpireCap", Vector3(0.44, 0.14, 0.42), Vector3(-0.06, 1.04, -0.10), 0.04, mat_light],
		["LeftMid", Vector3(0.48, 0.58, 0.52), Vector3(-0.30, 0.29, 0.18), 0.045, mat_light],
		["LeftFront", Vector3(0.44, 0.38, 0.42), Vector3(-0.24, 0.19, 0.34), 0.035, mat_mid],
		["CenterStep", Vector3(0.34, 0.28, 0.34), Vector3(-0.02, 0.14, 0.28), 0.03, mat_mid],
		["RightTall", Vector3(0.46, 0.62, 0.46), Vector3(0.28, 0.31, 0.04), 0.04, mat_mid],
		["RightLow", Vector3(0.46, 0.38, 0.48), Vector3(0.32, 0.19, 0.20), 0.045, mat_dark],
		["FrontFlat", Vector3(0.34, 0.14, 0.34), Vector3(0.08, 0.07, 0.38), 0.03, mat_light]
	]
	for b: Array in blocks:
		MeshKit.add_part(root, b[0],
			MeshKit.beveled_box(b[1], b[3], 1, false),
			b[4], b[2])

	return root

static func build_waterfall() -> Node3D:
	var root := Node3D.new()
	root.name = "Waterfall"

	var mat_earth := MeshKit.mat_color("wf_earth", Color(1.0, 0.96, 0.92), 0.78, 0.0, "earth_strata")
	var mat_grass := MeshKit.mat_color("wf_grass", Color(0.48, 0.82, 0.20), 0.58, 0.0)
	var mat_grass_d := MeshKit.mat_color("wf_grass_d", Color(0.32, 0.66, 0.14), 0.62, 0.0)
	var mat_rock := MeshKit.mat_color("wf_rock", Color(0.74, 0.71, 0.68), 0.78, 0.04)
	var mat_rock_d := MeshKit.mat_color("wf_rock_d", Color(0.56, 0.54, 0.53), 0.80, 0.04)
	var mat_water := MeshKit.mat_water("wf_water", Color(0.16, 0.68, 0.94, 0.88), true)
	var mat_pool := MeshKit.mat_water("wf_pool", Color(0.12, 0.62, 0.88, 0.85), true)
	var mat_foam := MeshKit.mat_emissive("wf_foam", Color(0.95, 0.99, 1.0), Color(0.75, 0.92, 1.0), 0.55, 0.35)

	# Left taller cliff pillar (-X, back) & Right medium cliff pillar (+X, back)
	MeshKit.add_part(root, "CliffLeft",
		MeshKit.beveled_box(Vector3(0.52, 1.28, 0.62), 0.02, 1, false),
		mat_earth, Vector3(-0.42, 0.64, -0.32))
	MeshKit.add_part(root, "GrassLeft",
		MeshKit.beveled_box(Vector3(0.53, 0.16, 0.63), 0.02, 1, false),
		mat_grass, Vector3(-0.42, 1.35, -0.32))
	MeshKit.add_part(root, "StudL1",
		MeshKit.beveled_box(Vector3(0.22, 0.12, 0.22), 0.018, 1, false),
		mat_grass_d, Vector3(-0.46, 1.48, -0.44))
	MeshKit.add_part(root, "StudL2",
		MeshKit.beveled_box(Vector3(0.18, 0.09, 0.18), 0.016, 1, false),
		mat_grass, Vector3(-0.34, 1.46, -0.18))

	MeshKit.add_part(root, "CliffRight",
		MeshKit.beveled_box(Vector3(0.50, 0.98, 0.62), 0.02, 1, false),
		mat_earth, Vector3(0.43, 0.49, -0.32))
	MeshKit.add_part(root, "GrassRight",
		MeshKit.beveled_box(Vector3(0.51, 0.15, 0.63), 0.02, 1, false),
		mat_grass, Vector3(0.43, 1.05, -0.32))
	MeshKit.add_part(root, "StudR1",
		MeshKit.beveled_box(Vector3(0.20, 0.10, 0.20), 0.016, 1, false),
		mat_grass_d, Vector3(0.45, 1.16, -0.36))

	# Center spillway rock bed
	MeshKit.add_part(root, "ChannelBack",
		MeshKit.beveled_box(Vector3(0.46, 0.96, 0.48), 0.02, 1, false),
		mat_rock_d, Vector3(0.0, 0.48, -0.38))

	# Flanking base rocks (left & right of splash zone)
	MeshKit.add_part(root, "RockLeft1",
		MeshKit.beveled_box(Vector3(0.36, 0.44, 0.42), 0.035, 1, false),
		mat_rock, Vector3(-0.46, 0.22, 0.12), Vector3(14.0, 0.0, 0.0))
	MeshKit.add_part(root, "RockLeft2",
		MeshKit.beveled_box(Vector3(0.26, 0.28, 0.28), 0.025, 1, false),
		mat_rock_d, Vector3(-0.28, 0.14, 0.16))
	MeshKit.add_part(root, "RockRight1",
		MeshKit.beveled_box(Vector3(0.42, 0.42, 0.48), 0.04, 1, false),
		mat_rock, Vector3(0.38, 0.21, 0.20), Vector3(12.0, 0.0, 0.0))
	MeshKit.add_part(root, "RockRight2",
		MeshKit.beveled_box(Vector3(0.34, 0.60, 0.36), 0.035, 1, false),
		mat_rock_d, Vector3(0.36, 0.30, 0.02))

	# Waterfall cascade: top crest + curved lip + vertical ribbed fall
	MeshKit.add_part(root, "WaterTopCrest",
		MeshKit.beveled_box(Vector3(0.40, 0.12, 0.36), 0.025, 2, true),
		mat_water, Vector3(0.0, 0.99, -0.26))
	MeshKit.add_part(root, "WaterCurveLip",
		MeshKit.beveled_cylinder(0.18, 0.18, 0.40, 16, 0.02, true),
		mat_water, Vector3(0.0, 0.87, -0.08), Vector3(0.0, 0.0, 90.0))
	MeshKit.add_part(root, "WaterVerticalSheet",
		MeshKit.beveled_box(Vector3(0.40, 0.78, 0.16), 0.03, 2, true),
		mat_water, Vector3(0.0, 0.50, 0.02))

	# Front turquoise pool
	MeshKit.add_part(root, "WaterPool",
		MeshKit.beveled_box(Vector3(0.76, 0.15, 0.74), 0.028, 2, true),
		mat_pool, Vector3(-0.14, 0.075, 0.46))

	# White bubbly foam line at splash base
	var foam_sph := SphereMesh.new()
	foam_sph.radius = 0.075; foam_sph.height = 0.13; foam_sph.radial_segments = 12; foam_sph.rings = 6
	var foam_am := MeshKit.prim_to_array_mesh(foam_sph)
	for i in range(6):
		var fx := -0.22 + float(i) * 0.09
		var fz := 0.14 + float(i % 2) * 0.04
		var sc := 0.85 + float((i * 3) % 4) * 0.12
		MeshKit.add_part(root, "Foam_%d" % i,
			foam_am, mat_foam, Vector3(fx, 0.17, fz), Vector3.ZERO, Vector3(sc, sc * 0.85, sc))

	# Floating lily flower in front pool (matching 17_waterfall.png!)
	var lily := build_lily_flower()
	lily.name = "PoolLilyFlower"
	lily.position = Vector3(-0.22, 0.145, 0.50)
	lily.scale = Vector3(0.68, 0.68, 0.68)
	root.add_child(lily)

	return root

static func _make_lily_pad_mesh(radius: float = 0.22, thickness: float = 0.045, notch_angle_deg: float = 35.0) -> ArrayMesh:
	var poly := PackedVector2Array()
	poly.append(Vector2(0.02, 0.0)) # Notch inner apex
	var segs := 14
	var half_gap := deg_to_rad(22.0)
	var base_a := deg_to_rad(notch_angle_deg)
	for i in range(segs + 1):
		var a := base_a + half_gap + (TAU - half_gap * 2.0) * float(i) / float(segs)
		poly.append(Vector2(cos(a) * radius, sin(a) * radius))
	return MeshKit.extrude_polygon_xz(poly, thickness, 2.0)

static func build_lily_pad_single() -> Node3D:
	var root := Node3D.new()
	root.name = "LilyPadTop"
	var mat_pad := MeshKit.mat_color("lily_green", Color(0.42, 0.78, 0.22), 0.48, 0.0)
	var mat_rim := MeshKit.mat_color("lily_rim", Color(0.26, 0.58, 0.15), 0.55, 0.0)
	MeshKit.add_part(root, "PadBase",
		_make_lily_pad_mesh(0.22, 0.042, 125.0),
		mat_rim, Vector3(0.0, 0.021, 0.0))
	MeshKit.add_part(root, "PadTop",
		_make_lily_pad_mesh(0.205, 0.022, 125.0),
		mat_pad, Vector3(0.0, 0.038, 0.0))
	return root

static func build_lily_pad_pair() -> Node3D:
	var root := Node3D.new()
	root.name = "LilyPadPair"
	var mat_pad_a := MeshKit.mat_color("lily_green_a", Color(0.40, 0.76, 0.21), 0.48, 0.0)
	var mat_pad_b := MeshKit.mat_color("lily_green_b", Color(0.48, 0.82, 0.24), 0.46, 0.0)
	var mat_rim := MeshKit.mat_color("lily_rim", Color(0.24, 0.54, 0.14), 0.55, 0.0)

	# Pad B (left)
	MeshKit.add_part(root, "PadB_Rim",
		_make_lily_pad_mesh(0.20, 0.042, 195.0),
		mat_rim, Vector3(-0.15, 0.021, 0.06))
	MeshKit.add_part(root, "PadB_Top",
		_make_lily_pad_mesh(0.188, 0.022, 195.0),
		mat_pad_a, Vector3(-0.15, 0.038, 0.06))

	# Pad C (right, slightly larger & overlapping)
	MeshKit.add_part(root, "PadC_Rim",
		_make_lily_pad_mesh(0.22, 0.045, -35.0),
		mat_rim, Vector3(0.15, 0.023, -0.04))
	MeshKit.add_part(root, "PadC_Top",
		_make_lily_pad_mesh(0.206, 0.024, -35.0),
		mat_pad_b, Vector3(0.15, 0.041, -0.04))
	return root

static func build_lily_flower() -> Node3D:
	var root := Node3D.new()
	root.name = "LilyFlower"

	var mat_pad := MeshKit.mat_color("lily_f_pad", Color(0.40, 0.76, 0.20), 0.48, 0.0)
	var mat_rim := MeshKit.mat_color("lily_f_rim", Color(0.24, 0.54, 0.14), 0.55, 0.0)
	var mat_petal := MeshKit.mat_color("lily_petal", Color(0.97, 0.98, 0.95), 0.35, 0.0)
	var mat_stamen := MeshKit.mat_emissive("lily_stamen", Color(1.0, 0.84, 0.22), Color(1.0, 0.78, 0.18), 0.6, 0.4)

	MeshKit.add_part(root, "LeafBase",
		_make_lily_pad_mesh(0.23, 0.045, 160.0),
		mat_rim, Vector3(0.0, 0.0225, 0.0))
	MeshKit.add_part(root, "LeafTop",
		_make_lily_pad_mesh(0.215, 0.024, 160.0),
		mat_pad, Vector3(0.0, 0.041, 0.0))

	# Pointed petal mesh
	var petal_poly := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(0.042, 0.055),
		Vector2(0.032, 0.135),
		Vector2(0.0, 0.175),
		Vector2(-0.032, 0.135),
		Vector2(-0.042, 0.055)
	])
	var petal_mesh := MeshKit.extrude_polygon_xz(petal_poly, 0.022)

	# Outer 8 petals + Inner 6 angled petals
	for i in range(8):
		var ya := 360.0 * float(i) / 8.0
		MeshKit.add_part(root, "PetalOuter_%d" % i,
			petal_mesh, mat_petal, Vector3(0.03, 0.062, 0.02), Vector3(-16.0, ya, 0.0))
	for i in range(6):
		var ya := 360.0 * float(i) / 6.0 + 25.0
		MeshKit.add_part(root, "PetalInner_%d" % i,
			petal_mesh, mat_petal, Vector3(0.03, 0.075, 0.02), Vector3(-34.0, ya, 0.0), Vector3(0.82, 0.82, 0.82))

	# Golden stamen center dome
	MeshKit.add_part(root, "StamenCenter",
		MeshKit.beveled_cylinder(0.058, 0.042, 0.048, 12, 0.012, true),
		mat_stamen, Vector3(0.03, 0.088, 0.02))
	return root

static func build_tree(tall: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "TreeTall" if tall else "TreeShort"

	var mat_base := MeshKit.mat_color("tree_base", Color(0.42, 0.78, 0.18), 0.58, 0.0)
	var mat_trunk := MeshKit.mat_color("tree_trunk", Color(0.92, 0.84, 0.74), 0.68, 0.0, "wood_dark")
	var leaf_main := Color(0.28, 0.68, 0.16) if tall else Color(0.50, 0.82, 0.19)
	var leaf_top := Color(0.34, 0.74, 0.20) if tall else Color(0.60, 0.88, 0.24)
	var mat_leaf := MeshKit.mat_color("tree_leaf_" + root.name, leaf_main, 0.52, 0.0)
	var mat_leaf_top := MeshKit.mat_color("tree_leaf_t_" + root.name, leaf_top, 0.48, 0.0)

	# Stepped green grass base plate
	MeshKit.add_part(root, "BasePlate",
		MeshKit.beveled_box(Vector3(0.58, 0.08, 0.58), 0.015, 1, false),
		mat_base, Vector3(0.0, 0.04, 0.0))
	MeshKit.add_part(root, "BaseStep",
		MeshKit.beveled_box(Vector3(0.42, 0.06, 0.42), 0.012, 1, false),
		mat_leaf_top, Vector3(0.0, 0.10, 0.0))

	# Trunk
	var trunk_h := 0.56 if tall else 0.48
	MeshKit.add_part(root, "Trunk",
		MeshKit.beveled_box(Vector3(0.24, trunk_h, 0.24), 0.016, 1, false),
		mat_trunk, Vector3(0.0, 0.12 + trunk_h * 0.5, 0.0))

	# Interlocking blocky cube crown!
	var crown_y := 0.98 if tall else 0.80
	var side_h := 0.58 if tall else 0.38
	var side_w := 0.38
	var offset := 0.19

	# 4-way cross cubes (matching 21_tree_short & 22_tree_tall!)
	MeshKit.add_part(root, "CrownCore",
		MeshKit.beveled_box(Vector3(0.44, side_h, 0.44), 0.025, 1, false),
		mat_leaf, Vector3(0.0, crown_y, 0.0))
	MeshKit.add_part(root, "CrownPosZ",
		MeshKit.beveled_box(Vector3(side_w, side_h, side_w), 0.028, 1, false),
		mat_leaf, Vector3(0.0, crown_y, offset))
	MeshKit.add_part(root, "CrownNegZ",
		MeshKit.beveled_box(Vector3(side_w, side_h, side_w), 0.028, 1, false),
		mat_leaf, Vector3(0.0, crown_y, -offset))
	MeshKit.add_part(root, "CrownPosX",
		MeshKit.beveled_box(Vector3(side_w, side_h, side_w), 0.028, 1, false),
		mat_leaf, Vector3(offset, crown_y, 0.0))
	MeshKit.add_part(root, "CrownNegX",
		MeshKit.beveled_box(Vector3(side_w, side_h, side_w), 0.028, 1, false),
		mat_leaf, Vector3(-offset, crown_y, 0.0))

	# Top cap block
	var top_y := crown_y + side_h * 0.5 + 0.10
	MeshKit.add_part(root, "CrownTop",
		MeshKit.beveled_box(Vector3(0.42, 0.22, 0.42), 0.026, 1, false),
		mat_leaf_top, Vector3(0.0, top_y, 0.0))

	# Tall tree has 4 distinct Lego studs on top (seen clearly in 22_tree_tall.png!)
	if tall:
		var stud := MeshKit.lego_stud(0.052, 0.032, 14)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				MeshKit.add_part(root, "TopStud_%d_%d" % [int(sx), int(sz)],
					stud, mat_leaf, Vector3(sx * 0.10, top_y + 0.11, sz * 0.10))

	return root

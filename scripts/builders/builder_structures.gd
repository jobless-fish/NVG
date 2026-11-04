class_name BuilderStructures
extends RefCounted

## Builds assets 23-30:
## 23_bridge_arch, 24_bridge_solid, 25_dock_cluster,
## 26_fence_short, 27_fence_long_dark, 28_fence_long_light, 29_fence_long_brown,
## 30_stairs

static func build_bridge(solid_variant: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "BridgeSolid" if solid_variant else "BridgeArch"

	var mat_masonry := MeshKit.mat_color("bridge_masonry", Color(0.76, 0.74, 0.71), 0.75, 0.03, "stone_ashlar")
	var mat_stone := MeshKit.mat_color("bridge_stone", Color(0.68, 0.65, 0.60), 0.68, 0.03)
	var mat_stone_mid := MeshKit.mat_color("bridge_stone_m", Color(0.57, 0.54, 0.50), 0.72, 0.03)
	var mat_dark_slot := MeshKit.mat_color("bridge_slot", Color(0.24, 0.23, 0.25), 0.85, 0.04)

	var length := 1.88
	var width_z := 1.34
	var deck_h := 0.74

	# Arch geometry: 23_bridge_arch has a taller/wider arch; 24_bridge_solid has thicker solid stone above a shallower arch
	var arch_half := 0.50 if solid_variant else 0.58
	var spring_y := 0.06 if solid_variant else 0.14
	var crown_y := 0.42 if solid_variant else 0.58

	MeshKit.add_part(root, "ArchBody",
		MeshKit.arch_span_mesh(length, deck_h, width_z, arch_half, spring_y, crown_y, 28, 1.3),
		mat_masonry, Vector3.ZERO)

	# Pier base plinths at both ends (-X and +X)
	var pier_w := (length * 0.5 - arch_half)
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "PierTrim_%d" % int(sx),
			MeshKit.beveled_box(Vector3(pier_w + 0.02, 0.08, width_z + 0.03), 0.012, 1, false),
			mat_stone_mid, Vector3(sx * (length * 0.5 - pier_w * 0.5), 0.04, 0.0))

	# 3 x 2 bevelled stone deck slabs (center pair slightly warmer/darker as in 23 & 24!)
	var inner_z := width_z - 0.28
	var slab_w := (length - 0.04) / 3.0 - 0.015
	var slab_z := inner_z * 0.5 - 0.015
	for ix in range(3):
		var px := (float(ix) - 1.0) * (slab_w + 0.015)
		var m := mat_stone_mid if ix == 1 else mat_stone
		for iz: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "DeckSlab_%d_%d" % [ix, int(iz)],
				MeshKit.beveled_box(Vector3(slab_w, 0.045, slab_z), 0.008, 1, false),
				m, Vector3(px, deck_h + 0.02, iz * (slab_z * 0.5 + 0.008)))

	# Left & Right Stone Parapets with 4 rectangular balustrade slots!
	var rail_thick := 0.14
	var rail_z_off := width_z * 0.5 - rail_thick * 0.5
	for sz: float in [-1.0, 1.0]:
		var side_tag := "Front" if sz > 0.0 else "Back"
		# Lower sill curb
		MeshKit.add_part(root, "Curb_" + side_tag,
			MeshKit.beveled_box(Vector3(length, 0.055, rail_thick), 0.008, 1, false),
			mat_stone_mid, Vector3(0.0, deck_h + 0.027, sz * rail_z_off))
		# 5 vertical baluster posts -> creates 4 open slots!
		for p in range(5):
			var post_x := lerpf(-length * 0.5 + 0.09, length * 0.5 - 0.09, float(p) / 4.0)
			var post_len := 0.18 if (p == 0 or p == 4) else 0.11
			MeshKit.add_part(root, "Baluster_%s_%d" % [side_tag, p],
				MeshKit.beveled_box(Vector3(post_len, 0.11, rail_thick), 0.008, 1, false),
				mat_stone, Vector3(post_x, deck_h + 0.105, sz * rail_z_off))
			if p < 4:
				var slot_x := lerpf(-length * 0.5 + 0.09, length * 0.5 - 0.09, (float(p) + 0.5) / 4.0)
				MeshKit.add_part(root, "SlotCore_%s_%d" % [side_tag, p],
					MeshKit.beveled_box(Vector3(0.24, 0.075, rail_thick * 0.55), 0.004, 1, false),
					mat_dark_slot, Vector3(slot_x, deck_h + 0.105, sz * rail_z_off))
		# Continuous top coping rail (slightly recessed at the ends like 23_bridge_arch.png!)
		MeshKit.add_part(root, "TopRail_" + side_tag,
			MeshKit.beveled_box(Vector3(length + 0.01, 0.075, rail_thick + 0.015), 0.012, 1, false),
			mat_stone, Vector3(0.0, deck_h + 0.195, sz * rail_z_off))

	return root

static func _add_dock_section(
	parent: Node3D,
	sec_name: String,
	center: Vector3,
	size_xz: Vector2,
	deck_y: float,
	plank_count: int,
	planks_along_z: bool,
	post_corners: Array,
	mat_plank: Material,
	mat_post: Material,
	mat_beam: Material
) -> void:
	var sec := Node3D.new()
	sec.name = sec_name
	sec.position = Vector3(center.x, 0.0, center.z)
	parent.add_child(sec)

	# Grey/timber support frame skirt under planks
	MeshKit.add_part(sec, "SupportFrame",
		MeshKit.beveled_box(Vector3(size_xz.x - 0.06, 0.12, size_xz.y - 0.06), 0.01, 1, false),
		mat_beam, Vector3(0.0, deck_y - 0.09, 0.0))

	# Deck planks
	var gap := 0.016
	if planks_along_z:
		var pw := (size_xz.x - gap * float(plank_count - 1)) / float(plank_count)
		for i in range(plank_count):
			var px := -size_xz.x * 0.5 + pw * 0.5 + float(i) * (pw + gap)
			MeshKit.add_part(sec, "Plank_%d" % i,
				MeshKit.beveled_box(Vector3(pw, 0.065, size_xz.y), 0.01, 1, false),
				mat_plank, Vector3(px, deck_y - 0.02, 0.0))
	else:
		var pz_w := (size_xz.y - gap * float(plank_count - 1)) / float(plank_count)
		for i in range(plank_count):
			var pz := -size_xz.y * 0.5 + pz_w * 0.5 + float(i) * (pz_w + gap)
			MeshKit.add_part(sec, "Plank_%d" % i,
				MeshKit.beveled_box(Vector3(size_xz.x, 0.065, pz_w), 0.01, 1, false),
				mat_plank, Vector3(0.0, deck_y - 0.02, pz))

	# Corner posts with bevelled caps
	for idx in range(post_corners.size()):
		var c: Vector2 = post_corners[idx]
		var post_h := deck_y + 0.16
		var px := c.x * (size_xz.x * 0.5 - 0.06)
		var pz := c.y * (size_xz.y * 0.5 - 0.06)
		MeshKit.add_part(sec, "Post_%d" % idx,
			MeshKit.beveled_box(Vector3(0.16, post_h, 0.16), 0.014, 1, false),
			mat_post, Vector3(px, post_h * 0.5, pz))
		MeshKit.add_part(sec, "PostCap_%d" % idx,
			MeshKit.beveled_box(Vector3(0.175, 0.055, 0.175), 0.014, 1, false),
			mat_plank, Vector3(px, post_h + 0.025, pz))

static func build_dock_cluster() -> Node3D:
	var root := Node3D.new()
	root.name = "DockCluster"

	var mat_plank := MeshKit.mat_color("dock_plank", Color(0.98, 0.92, 0.82), 0.56, 0.0, "wood_oak")
	var mat_post := MeshKit.mat_color("dock_post", Color(0.88, 0.80, 0.72), 0.64, 0.0, "wood_brown")
	var mat_beam := MeshKit.mat_color("dock_beam", Color(0.58, 0.56, 0.54), 0.74, 0.04)

	# 1. Main elevated center dock (6 planks along Z, 4 corner posts)
	_add_dock_section(
		root, "CenterMainDock",
		Vector3(-0.15, 0.0, -0.18), Vector2(1.52, 1.52), 0.50, 6, true,
		[Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
		mat_plank, mat_post, mat_beam
	)

	# 2. Left lower dock (+Z front-left extension, 5 perpendicular planks along X!)
	_add_dock_section(
		root, "LeftLowerDock",
		Vector3(-0.34, 0.0, 1.06), Vector2(1.14, 1.02), 0.36, 5, false,
		[Vector2(-1, 1), Vector2(1, 1)],
		mat_plank, mat_post, mat_beam
	)

	# 3. Right lower dock (+X front-right extension, 4 planks along Z!)
	_add_dock_section(
		root, "RightLowerDock",
		Vector3(1.04, 0.0, 0.02), Vector2(0.92, 1.16), 0.36, 4, true,
		[Vector2(1, -1), Vector2(1, 1)],
		mat_plank, mat_post, mat_beam
	)

	return root

static func build_fence(variant: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Fence_" + variant

	var tex_key := "wood_brown"
	var post_tint := Color(0.92, 0.84, 0.76)
	var rail_tint := Color(0.98, 0.90, 0.80)
	var bays := 2
	var total_len := 1.64

	if variant == "short":
		bays = 1
		total_len = 0.88
		tex_key = "wood_brown"
	elif variant == "long_dark":
		bays = 2
		total_len = 1.64
		tex_key = "wood_dark"
		post_tint = Color(0.88, 0.80, 0.72)
	elif variant == "long_light":
		bays = 3
		total_len = 2.16
		tex_key = "wood_oak"
		post_tint = Color(0.98, 0.93, 0.85)
		rail_tint = Color(1.0, 0.96, 0.88)
	elif variant == "long_brown":
		bays = 2
		total_len = 1.64
		tex_key = "wood_brown"

	var mat_post := MeshKit.mat_color("fence_p_" + variant, post_tint, 0.62, 0.0, tex_key)
	var mat_rail := MeshKit.mat_color("fence_r_" + variant, rail_tint, 0.56, 0.0, "wood_oak")
	var mat_bolt := MeshKit.mat_color("fence_bolt", Color(0.28, 0.27, 0.28), 0.48, 0.55)

	var post_count := bays + 1
	for i in range(post_count):
		var px := lerpf(-total_len * 0.5, total_len * 0.5, float(i) / float(bays))
		var thick_post := (variant == "short") or (variant == "long_light" and i <= 1)
		var pw := 0.17 if thick_post else 0.125
		var pd := 0.17 if thick_post else 0.145
		var ph := 0.56 if thick_post else 0.52
		MeshKit.add_part(root, "Post_%d" % i,
			MeshKit.beveled_box(Vector3(pw, ph, pd), 0.015, 1, false),
			mat_post, Vector3(px, ph * 0.5, 0.0))
		if thick_post:
			MeshKit.add_part(root, "PostCap_%d" % i,
				MeshKit.beveled_box(Vector3(pw + 0.016, 0.055, pd + 0.016), 0.014, 1, false),
				mat_rail, Vector3(px, ph + 0.025, 0.0))

	# Upper & Lower horizontal rails per bay
	var bay_w := total_len / float(bays)
	for b in range(bays):
		var bx := -total_len * 0.5 + (float(b) + 0.5) * bay_w
		MeshKit.add_part(root, "RailUpper_%d" % b,
			MeshKit.beveled_box(Vector3(bay_w, 0.088, 0.068), 0.01, 1, false),
			mat_rail, Vector3(bx, 0.38, 0.0))
		MeshKit.add_part(root, "RailLower_%d" % b,
			MeshKit.beveled_box(Vector3(bay_w, 0.082, 0.068), 0.01, 1, false),
			mat_rail, Vector3(bx, 0.18, 0.0))

		if variant == "short":
			# Subtle bolt studs seen on 26_fence_short.png!
			for s: float in [-1.0, 1.0]:
				MeshKit.add_part(root, "Bolt_%d" % int(s),
					MeshKit.beveled_cylinder(0.024, 0.024, 0.02, 10, 0.004, true),
					mat_bolt, Vector3(bx + s * 0.12, 0.38, 0.038), Vector3(90.0, 0.0, 0.0))

	return root

static func build_stairs() -> Node3D:
	var root := Node3D.new()
	root.name = "Stairs"

	var mat_masonry := MeshKit.mat_color("stairs_masonry", Color(0.72, 0.70, 0.67), 0.75, 0.03, "stone_ashlar")
	var mat_tread := MeshKit.mat_color("stairs_tread", Color(0.68, 0.65, 0.60), 0.68, 0.03)
	var mat_tread_alt := MeshKit.mat_color("stairs_tread_a", Color(0.61, 0.58, 0.54), 0.70, 0.03)

	var steps := 5
	var step_h := 1.0 / float(steps)
	var step_d := 1.0 / float(steps)

	# 5 ascending steps from front (+Z = +0.5) to back (-Z = -0.5)
	for i in range(steps):
		var h := float(i + 1) * step_h
		var z_front := 0.5 - float(i) * step_d
		var z_center := z_front - step_d * 0.5

		# Solid ashlar stone column under this tread
		MeshKit.add_part(root, "StepCore_%d" % i,
			MeshKit.beveled_box(Vector3(0.98, h - 0.035, step_d + 0.005), 0.01, 1, false),
			mat_masonry, Vector3(0.0, (h - 0.035) * 0.5, z_center))

		# 3 stone tread slabs across width (narrow left, wide center, narrow right - matching 30_stairs.png!)
		var x_defs := [
			[-0.365, 0.25, mat_tread_alt],
			[0.0, 0.45, mat_tread],
			[0.365, 0.25, mat_tread_alt]
		]
		for k in range(3):
			var xd: Array = x_defs[k]
			MeshKit.add_part(root, "StepTread_%d_%d" % [i, k],
				MeshKit.beveled_box(Vector3(xd[1], 0.048, step_d - 0.008), 0.008, 1, false),
				xd[2], Vector3(xd[0], h - 0.02, z_center))

	return root

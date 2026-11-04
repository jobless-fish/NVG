extends RefCounted

## Extra 3D assets that appear in map_base.png but were NOT part of the original 53 cropped sprites.
## (No class_name on purpose: load via preload("res://scripts/builders/builder_extra_world_assets.gd"))
##  54 queue gantry gate   55 pier viaduct      56 array slot tray
##  57 lego cargo block    58 open crate bin    59 stone seawall
##  60 reef cluster        61 hedge row

static func _stud_grid(parent: Node3D, nx: int, nz: int, pitch: float, y: float, mat: Material, radius: float = 0.11) -> void:
	var stud: ArrayMesh = MeshKit.lego_stud(radius, 0.06, 14)
	for ix in range(nx):
		for iz in range(nz):
			var px: float = (float(ix) - float(nx - 1) * 0.5) * pitch
			var pz: float = (float(iz) - float(nz - 1) * 0.5) * pitch
			MeshKit.add_part(parent, "Stud_%d_%d" % [ix, iz], stud, mat, Vector3(px, y, pz))

# ---------------------------------------------------------------------------
# 54: QUEUE industrial steel gantry portal (origin = ground center, spans X, opening along Z)
# ---------------------------------------------------------------------------
static func build_gantry_gate() -> Node3D:
	var root := Node3D.new()
	root.name = "QueueGantryGate"
	var mat_steel: StandardMaterial3D = MeshKit.mat_color("gantry_steel", Color(0.74, 0.77, 0.81), 0.32, 0.72)
	var mat_dark: StandardMaterial3D = MeshKit.mat_color("gantry_dark", Color(0.16, 0.18, 0.22), 0.55, 0.4)
	var mat_cyan: StandardMaterial3D = MeshKit.mat_emissive("gantry_cyan", Color(0.3, 0.95, 1.0), Color(0.16, 0.86, 1.0), 2.6, 0.15)

	for sx: float in [-1.0, 1.0]:
		var n: String = "L" if sx < 0.0 else "R"
		MeshKit.add_part(root, "BasePlate_" + n,
			MeshKit.beveled_box(Vector3(0.46, 0.12, 0.5), 0.015, 1, false),
			mat_dark, Vector3(sx * 0.85, 0.06, 0.0))
		MeshKit.add_part(root, "Post_" + n,
			MeshKit.beveled_box(Vector3(0.24, 1.7, 0.3), 0.02, 1, false),
			mat_steel, Vector3(sx * 0.85, 0.97, 0.0))
		for i in range(5):
			MeshKit.add_part(root, "Perf_%s_%d" % [n, i],
				MeshKit.beveled_box(Vector3(0.1, 0.1, 0.02), 0.006, 1, false),
				mat_dark, Vector3(sx * 0.85, 0.35 + float(i) * 0.28, 0.152))
	MeshKit.add_part(root, "CrossBeam",
		MeshKit.beveled_box(Vector3(2.05, 0.26, 0.34), 0.02, 1, false),
		mat_steel, Vector3(0.0, 1.82, 0.0))
	MeshKit.add_part(root, "LightStrip",
		MeshKit.beveled_box(Vector3(1.5, 0.04, 0.04), 0.008, 1, false),
		mat_cyan, Vector3(0.0, 1.66, 0.18))
	for sx: float in [-0.6, 0.6]:
		MeshKit.add_part(root, "SignMount_%d" % int(sx * 10.0),
			MeshKit.beveled_box(Vector3(0.1, 0.3, 0.1), 0.01, 1, false),
			mat_dark, Vector3(sx, 2.1, 0.0))
	return root

# ---------------------------------------------------------------------------
# 55: Industrial stone pier viaduct (origin = deck-top center; extends downward)
# ---------------------------------------------------------------------------
static func build_pier_viaduct(size_x: float, size_z: float, depth: float) -> Node3D:
	var root := Node3D.new()
	root.name = "PierViaduct"
	var mat_stone: StandardMaterial3D = MeshKit.mat_color("viaduct_stone", Color(0.82, 0.82, 0.84), 0.7, 0.05, "stone_ashlar")
	var mat_dark: StandardMaterial3D = MeshKit.mat_color("viaduct_dark", Color(0.34, 0.36, 0.40), 0.75, 0.1)
	var mat_trim: StandardMaterial3D = MeshKit.mat_color("viaduct_trim", Color(0.62, 0.63, 0.66), 0.6, 0.15)

	MeshKit.add_part(root, "Deck",
		MeshKit.beveled_box(Vector3(size_x, 0.34, size_z), 0.02, 1, false, 0.8),
		mat_stone, Vector3(0.0, -0.17, 0.0))
	# Raised metal trim on the outer long edges
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "EdgeTrim_%d" % int(sx),
			MeshKit.beveled_box(Vector3(0.1, 0.06, size_z), 0.01, 1, false),
			mat_trim, Vector3(sx * (size_x * 0.5 - 0.05), 0.0, 0.0))
	var count: int = maxi(int(size_z / 1.8) + 1, 2)
	for iz in range(count):
		var pz: float = lerpf(-size_z * 0.5 + 0.45, size_z * 0.5 - 0.45, float(iz) / float(count - 1))
		for sx: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "Pillar_%d_%d" % [iz, int(sx)],
				MeshKit.beveled_box(Vector3(0.5, depth, 0.5), 0.02, 1, false, 0.8),
				mat_dark, Vector3(sx * (size_x * 0.5 - 0.4), -0.34 - depth * 0.5, pz))
		MeshKit.add_part(root, "CrossBeam_%d" % iz,
			MeshKit.beveled_box(Vector3(size_x - 0.5, 0.2, 0.3), 0.015, 1, false),
			mat_trim, Vector3(0.0, -0.5, pz))
	return root

# ---------------------------------------------------------------------------
# 56: ARRAY slot tray with 5 pressable golden tiles (origin = deck top, runs along Z)
# children Tile_0..Tile_4 (animate .position.y to press them)
# ---------------------------------------------------------------------------
static func build_array_tray() -> Node3D:
	var root := Node3D.new()
	root.name = "ArraySlotTray"
	var mat_frame: StandardMaterial3D = MeshKit.mat_color("tray_frame", Color(0.60, 0.58, 0.55), 0.7, 0.05, "stone_ashlar")
	var mat_pit: StandardMaterial3D = MeshKit.mat_color("tray_pit", Color(0.22, 0.2, 0.19), 0.85, 0.05)
	var mat_gold: StandardMaterial3D = MeshKit.mat_color("tray_gold", Color(0.95, 0.62, 0.14), 0.42, 0.08)
	var mat_digit: StandardMaterial3D = MeshKit.mat_color("tray_digit", Color(0.96, 0.9, 0.7), 0.5, 0.02)

	MeshKit.add_part(root, "Pit",
		MeshKit.beveled_box(Vector3(1.2, 0.04, 6.1), 0.008, 1, false),
		mat_pit, Vector3(0.0, 0.0, 0.0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "Rim_%d" % int(sx),
			MeshKit.beveled_box(Vector3(0.1, 0.07, 6.2), 0.012, 1, false),
			mat_frame, Vector3(sx * 0.6, 0.02, 0.0))
	for sz: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "EndRim_%d" % int(sz),
			MeshKit.beveled_box(Vector3(1.3, 0.07, 0.1), 0.012, 1, false),
			mat_frame, Vector3(0.0, 0.02, sz * 3.05))
	for i in range(5):
		var tile := Node3D.new()
		tile.name = "Tile_%d" % i
		tile.position = Vector3(0.0, 0.0, 2.4 - 1.2 * float(i))
		root.add_child(tile)
		MeshKit.add_part(tile, "GoldBlock",
			MeshKit.beveled_box(Vector3(0.92, 0.14, 0.92), 0.022, 1, false),
			mat_gold, Vector3(0.0, 0.04, 0.0))
		MeshKit.add_part(tile, "Digit",
			MeshKit.text_mesh_3d(str(i), 42, 0.0085, 0.04),
			mat_digit, Vector3(0.0, 0.118, 0.0), Vector3(-90.0, 0.0, 0.0))
	return root

# ---------------------------------------------------------------------------
# 57: 2x4 Lego cargo block (origin = bottom center)
# ---------------------------------------------------------------------------
static func build_lego_block(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "LegoBlock2x4"
	var mat: StandardMaterial3D = MeshKit.mat_color("lego_" + color.to_html(), color, 0.38, 0.02)
	MeshKit.add_part(root, "Body",
		MeshKit.beveled_box(Vector3(0.8, 0.4, 1.6), 0.03, 1, false),
		mat, Vector3(0.0, 0.2, 0.0))
	_stud_grid(root, 2, 4, 0.4, 0.4, mat, 0.12)
	return root

# ---------------------------------------------------------------------------
# 58: Open-top wooden cargo bin (origin = bottom center)
# ---------------------------------------------------------------------------
static func build_open_bin() -> Node3D:
	var root := Node3D.new()
	root.name = "OpenCrateBin"
	var mat: StandardMaterial3D = MeshKit.mat_color("bin_wood", Color(0.95, 0.86, 0.76), 0.6, 0.0, "wood_brown")
	var mat_in: StandardMaterial3D = MeshKit.mat_color("bin_inner", Color(0.55, 0.42, 0.32), 0.8, 0.0, "wood_dark")
	var s: float = 0.66
	MeshKit.add_part(root, "Floor", MeshKit.beveled_box(Vector3(s, 0.06, s), 0.01, 1, false), mat_in, Vector3(0.0, 0.03, 0.0))
	for sz: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "WallZ_%d" % int(sz),
			MeshKit.beveled_box(Vector3(s, 0.5, 0.07), 0.01, 1, false),
			mat, Vector3(0.0, 0.25, sz * (s * 0.5 - 0.035)))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "WallX_%d" % int(sx),
			MeshKit.beveled_box(Vector3(0.07, 0.5, s - 0.14), 0.01, 1, false),
			mat, Vector3(sx * (s * 0.5 - 0.035), 0.25, 0.0))
	return root

# ---------------------------------------------------------------------------
# 59: Grey stone seawall foundation (origin = top center; extends downward)
# ---------------------------------------------------------------------------
static func build_seawall(size_x: float, size_z: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "StoneSeawall"
	var mat: StandardMaterial3D = MeshKit.mat_color("seawall_stone", Color(0.74, 0.73, 0.72), 0.78, 0.04, "stone_ashlar")
	MeshKit.add_part(root, "Wall",
		MeshKit.beveled_box(Vector3(size_x, height, size_z), 0.03, 1, false, 0.9),
		mat, Vector3(0.0, -height * 0.5, 0.0))
	return root

# ---------------------------------------------------------------------------
# 60: Underwater turquoise Lego reef cluster (origin = bottom center)
# ---------------------------------------------------------------------------
static func build_reef_cluster(variant: int) -> Node3D:
	var root := Node3D.new()
	root.name = "ReefCluster_%d" % variant
	var mat_a: StandardMaterial3D = MeshKit.mat_color("reef_a", Color(0.22, 0.74, 0.68), 0.45, 0.02)
	var mat_b: StandardMaterial3D = MeshKit.mat_color("reef_b", Color(0.12, 0.54, 0.58), 0.5, 0.02)
	for i in range(5):
		var h: float = 0.3 + float((i * 7 + variant * 3) % 3) * 0.22
		var w: float = 0.8 + float((i + variant) % 2) * 0.4
		var px: float = float(i) * 0.85 - 1.7
		var pz: float = float((i * 5 + variant) % 3) * 0.5 - 0.5
		var m: StandardMaterial3D = mat_a if (i + variant) % 2 == 0 else mat_b
		MeshKit.add_part(root, "Block_%d" % i,
			MeshKit.beveled_box(Vector3(w, h, 0.8), 0.03, 1, false),
			m, Vector3(px, h * 0.5, pz))
	return root

# ---------------------------------------------------------------------------
# 61: Lego-stud hedge row (origin = bottom center, runs along X)
# ---------------------------------------------------------------------------
static func build_hedge(length: float) -> Node3D:
	var root := Node3D.new()
	root.name = "HedgeRow"
	var mat_a: StandardMaterial3D = MeshKit.mat_color("hedge_a", Color(0.30, 0.68, 0.16), 0.55, 0.0)
	var mat_b: StandardMaterial3D = MeshKit.mat_color("hedge_b", Color(0.46, 0.82, 0.20), 0.5, 0.0)
	var count: int = maxi(int(length / 0.35), 1)
	var stud: ArrayMesh = MeshKit.lego_stud(0.07, 0.04, 12)
	for i in range(count):
		var px: float = (float(i) + 0.5) * (length / float(count)) - length * 0.5
		var h: float = 0.26 + float((i * 5) % 3) * 0.06
		var m: StandardMaterial3D = mat_a if i % 2 == 0 else mat_b
		MeshKit.add_part(root, "Bush_%d" % i,
			MeshKit.beveled_box(Vector3(length / float(count) + 0.02, h, 0.36), 0.03, 1, false),
			m, Vector3(px, h * 0.5, 0.0))
		MeshKit.add_part(root, "BushStud_%d" % i, stud, m, Vector3(px, h, 0.0))
	return root

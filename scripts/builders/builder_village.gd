class_name BuilderVillage
extends RefCounted

## Main-island village objects (source: NODEVERSE objects/OBJ01-OBJ06):
## OBJ01 house_blue, OBJ02 cottage_blue, OBJ03 crystal_beacon,
## OBJ04 quest_board, OBJ05 market_stall, OBJ06 round_plaza

# ----------------------------------------------------------------------------
# OBJ01 - Blue-roof two-story house (main block + front cross-gable wing)
# ----------------------------------------------------------------------------
static func build_house_blue() -> Node3D:
	var root := Node3D.new()
	root.name = "HouseBlue"

	var mat_cream := ObjKit.m_cream()
	var mat_timber := ObjKit.m_timber()
	var mat_stone := ObjKit.m_stone()
	var mat_stone_l := ObjKit.m_stone_light()
	var mat_roof := ObjKit.m_blue_roof()
	var mat_roof_d := ObjKit.m_blue_roof_dark()
	var mat_glow := ObjKit.m_window_glow()
	var mat_brick := ObjKit.m_brick()
	var mat_iron := ObjKit.m_iron()

	var plinth_h := 0.14
	var hx := 0.72
	var hz := 0.55
	var wall_top := 1.30
	var wall_h := wall_top - plinth_h

	# 1. Gray stone plinth (main + wing) built from blocks
	var plinth_items: Array = []
	plinth_items.append([ObjKit.box(Vector3(hx * 2.0 + 0.10, plinth_h, hz * 2.0 + 0.10), 0.02), ObjKit.xf(Vector3(0.0, plinth_h * 0.5, 0.0))])
	plinth_items.append([ObjKit.box(Vector3(0.80, plinth_h, 0.56), 0.02), ObjKit.xf(Vector3(0.32, plinth_h * 0.5, 0.63))])
	ObjKit.add_merged(root, "StonePlinth", plinth_items, mat_stone)
	for i in range(5):
		MeshKit.add_part(root, "PlinthBlock_%d" % i, ObjKit.box(Vector3(0.26, 0.10, 0.06), 0.015), mat_stone_l,
			Vector3(-0.66 + float(i) * 0.30, 0.07, hz + 0.06))

	# 2. Plaster walls
	MeshKit.add_part(root, "MainWalls", ObjKit.box(Vector3(hx * 2.0, wall_h, hz * 2.0), 0.01), mat_cream,
		Vector3(0.0, plinth_h + wall_h * 0.5, 0.0))
	var wing_top := 1.18
	var wing_h := wing_top - plinth_h
	MeshKit.add_part(root, "WingWalls", ObjKit.box(Vector3(0.68, wing_h, 0.50), 0.01), mat_cream,
		Vector3(0.32, plinth_h + wing_h * 0.5, 0.61))

	# 3. Timber frame: corner posts + belt beams
	var post_items: Array = []
	for c: Vector2 in [Vector2(-hx, hz), Vector2(hx, hz), Vector2(-hx, -hz), Vector2(hx, -hz)]:
		post_items.append([ObjKit.box(Vector3(0.10, wall_h + 0.02, 0.10), 0.015), ObjKit.xf(Vector3(c.x, plinth_h + wall_h * 0.5, c.y))])
	for wx: float in [-0.02, 0.66]:
		post_items.append([ObjKit.box(Vector3(0.10, wing_h + 0.02, 0.10), 0.015), ObjKit.xf(Vector3(wx, plinth_h + wing_h * 0.5, 0.86))])
	# belt beams at storey line (y=0.74) and wall top
	for by: float in [0.74, wall_top - 0.04]:
		post_items.append([ObjKit.box(Vector3(hx * 2.0 + 0.06, 0.07, 0.06), 0.012), ObjKit.xf(Vector3(0.0, by, hz + 0.01))])
		post_items.append([ObjKit.box(Vector3(0.06, 0.07, hz * 2.0 + 0.06), 0.012), ObjKit.xf(Vector3(hx + 0.01, by, 0.0))])
		post_items.append([ObjKit.box(Vector3(0.06, 0.07, hz * 2.0 + 0.06), 0.012), ObjKit.xf(Vector3(-hx - 0.01, by, 0.0))])
	post_items.append([ObjKit.box(Vector3(0.74, 0.07, 0.06), 0.012), ObjKit.xf(Vector3(0.32, 0.74, 0.87))])
	post_items.append([ObjKit.box(Vector3(0.74, 0.07, 0.06), 0.012), ObjKit.xf(Vector3(0.32, wing_top - 0.04, 0.87))])
	# right side mid post
	post_items.append([ObjKit.box(Vector3(0.06, wall_h, 0.08), 0.012), ObjKit.xf(Vector3(hx + 0.01, plinth_h + wall_h * 0.5, 0.18))])
	ObjKit.add_merged(root, "TimberFrame", post_items, mat_timber)

	# 4. Main roof (ridge along X, gables at +/-X) and wing roof (ridge along Z, gable facing +Z)
	ObjKit.gable_roof(root, "MainRoof", Vector3(0.0, wall_top, 0.0), 0.0, hx * 2.0, hz, 0.10, 0.85,
		mat_roof_d, mat_roof, 0.15, [-1, 1], mat_cream, mat_timber)
	ObjKit.gable_roof(root, "WingRoof", Vector3(0.32, wing_top, 0.50), -90.0, 0.72, 0.34, 0.08, 1.0,
		mat_roof_d, mat_roof, 0.14, [1], mat_cream, mat_timber)
	# Gable X-braces on the wing front
	for sgn: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "GableBrace_%d" % int(sgn), ObjKit.box(Vector3(0.05, 0.40, 0.04), 0.008), mat_timber,
			Vector3(0.32 + sgn * 0.12, wing_top + 0.12, 0.88), Vector3(0.0, 0.0, sgn * 48.0))

	# 5. Windows & door
	ObjKit.window(root, "WinFrontLow", Vector3(-0.38, 0.46, hz), 0.0, 0.30, 0.30, mat_timber, mat_glow)
	ObjKit.window(root, "WinFrontUp", Vector3(-0.38, 1.02, hz), 0.0, 0.24, 0.22, mat_timber, mat_glow)
	ObjKit.window(root, "WinSideUp", Vector3(hx, 1.02, -0.20), 90.0, 0.30, 0.26, mat_timber, mat_glow)
	ObjKit.window(root, "WinSideLow", Vector3(hx, 0.46, -0.20), 90.0, 0.30, 0.28, mat_timber, mat_glow)
	ObjKit.window(root, "WinGable", Vector3(0.32, 1.30, 0.86), 0.0, 0.12, 0.12, mat_timber, MeshKit.mat_color("obj_dark_glass", Color(0.24, 0.17, 0.12), 0.5), false)
	# Stone arch surround + door
	var arch_items: Array = []
	for sx: float in [-1.0, 1.0]:
		arch_items.append([ObjKit.box(Vector3(0.08, 0.58, 0.07), 0.015), ObjKit.xf(Vector3(0.32 + sx * 0.21, plinth_h + 0.29, 0.88))])
	arch_items.append([ObjKit.box(Vector3(0.50, 0.09, 0.08), 0.02), ObjKit.xf(Vector3(0.32, plinth_h + 0.62, 0.885))])
	ObjKit.add_merged(root, "DoorArch", arch_items, mat_stone_l)
	ObjKit.door(root, "FrontDoor", Vector3(0.32, plinth_h, 0.87), 0.0, 0.30, 0.52, ObjKit.m_timber_dark(), mat_timber, mat_iron, mat_glow)
	MeshKit.add_part(root, "DoorStep", ObjKit.box(Vector3(0.44, 0.05, 0.14), 0.012), mat_stone_l, Vector3(0.32, 0.025, 0.96))

	# 6. Brick chimney on the back-left slope
	MeshKit.add_part(root, "ChimneyStack", ObjKit.box(Vector3(0.24, 0.62, 0.24), 0.02), mat_brick, Vector3(-0.42, 1.80, -0.12))
	for k in range(3):
		MeshKit.add_part(root, "ChimneyCourse_%d" % k, ObjKit.box(Vector3(0.25, 0.025, 0.25), 0.004), ObjKit.m_brick(),
			Vector3(-0.42, 1.62 + float(k) * 0.14, -0.12))
	MeshKit.add_part(root, "ChimneyCap", ObjKit.box(Vector3(0.32, 0.10, 0.32), 0.02), mat_cream, Vector3(-0.42, 2.15, -0.12))
	MeshKit.add_part(root, "ChimneyFlue", ObjKit.box(Vector3(0.14, 0.02, 0.14), 0.004), MeshKit.mat_color("obj_soot", Color(0.12, 0.10, 0.09), 0.9), Vector3(-0.42, 2.20, -0.12))
	return root

# ----------------------------------------------------------------------------
# OBJ02 - Small blue-roof cottage
# ----------------------------------------------------------------------------
static func build_cottage_blue() -> Node3D:
	var root := Node3D.new()
	root.name = "CottageBlue"

	var mat_cream := ObjKit.m_cream()
	var mat_timber := ObjKit.m_timber()
	var mat_stone := ObjKit.m_stone()
	var mat_roof := ObjKit.m_blue_roof()
	var mat_roof_d := ObjKit.m_blue_roof_dark()
	var mat_glow := ObjKit.m_window_glow()

	var plinth_h := 0.12
	var h := 0.46
	var wall_top := 0.98
	var wall_h := wall_top - plinth_h

	# Plinth with chunky corner stones
	MeshKit.add_part(root, "Plinth", ObjKit.box(Vector3(h * 2.0 + 0.08, plinth_h, h * 2.0 + 0.08), 0.02), mat_stone, Vector3(0.0, plinth_h * 0.5, 0.0))
	for c: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		MeshKit.add_part(root, "CornerStone_%d_%d" % [int(c.x), int(c.y)], ObjKit.box(Vector3(0.16, 0.16, 0.16), 0.02), ObjKit.m_stone_light(),
			Vector3(c.x * (h + 0.02), 0.08, c.y * (h + 0.02)))

	MeshKit.add_part(root, "Walls", ObjKit.box(Vector3(h * 2.0, wall_h, h * 2.0), 0.01), mat_cream, Vector3(0.0, plinth_h + wall_h * 0.5, 0.0))

	var frame_items: Array = []
	for c: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		frame_items.append([ObjKit.box(Vector3(0.11, wall_h, 0.11), 0.016), ObjKit.xf(Vector3(c.x * h, plinth_h + wall_h * 0.5 + 0.02, c.y * h))])
	# Front beam frame around the door & belt
	frame_items.append([ObjKit.box(Vector3(h * 2.0 + 0.08, 0.08, 0.07), 0.014), ObjKit.xf(Vector3(0.0, 0.76, h + 0.01))])
	frame_items.append([ObjKit.box(Vector3(h * 2.0 + 0.08, 0.08, 0.07), 0.014), ObjKit.xf(Vector3(0.0, wall_top - 0.03, h + 0.01))])
	frame_items.append([ObjKit.box(Vector3(0.07, 0.08, h * 2.0 + 0.08), 0.014), ObjKit.xf(Vector3(h + 0.01, wall_top - 0.03, 0.0))])
	frame_items.append([ObjKit.box(Vector3(0.07, 0.08, h * 2.0 + 0.08), 0.014), ObjKit.xf(Vector3(h + 0.01, 0.30, 0.0))])
	ObjKit.add_merged(root, "TimberFrame", frame_items, mat_timber)

	# Roof: ridge along Z so the gable faces the front (+Z)
	ObjKit.gable_roof(root, "Roof", Vector3(0.0, wall_top, 0.0), -90.0, h * 2.0, h, 0.10, 0.95,
		mat_roof_d, mat_roof, 0.15, [-1, 1], mat_cream, mat_timber)
	for sgn: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "GableBrace_%d" % int(sgn), ObjKit.box(Vector3(0.05, 0.36, 0.04), 0.008), mat_timber,
			Vector3(sgn * 0.17, wall_top + 0.13, h + 0.03), Vector3(0.0, 0.0, sgn * 50.0))

	ObjKit.window(root, "WinGable", Vector3(0.0, wall_top + 0.14, h + 0.01), 0.0, 0.13, 0.13, mat_timber, mat_glow, false)
	ObjKit.window(root, "WinSide", Vector3(h, 0.56, 0.04), 90.0, 0.30, 0.28, mat_timber, mat_glow)
	ObjKit.door(root, "Door", Vector3(-0.10, plinth_h, h + 0.005), 0.0, 0.28, 0.52, ObjKit.m_timber_dark(), mat_timber, ObjKit.m_gold(), mat_glow)

	# Chimney: stone base + brick + cream cap (back-left)
	MeshKit.add_part(root, "ChimneyBase", ObjKit.box(Vector3(0.26, 0.40, 0.26), 0.02), mat_stone, Vector3(-0.28, 1.22, -0.24))
	MeshKit.add_part(root, "ChimneyBrick", ObjKit.box(Vector3(0.24, 0.26, 0.24), 0.02), ObjKit.m_brick(), Vector3(-0.28, 1.55, -0.24))
	MeshKit.add_part(root, "ChimneyCap", ObjKit.box(Vector3(0.30, 0.10, 0.30), 0.02), mat_cream, Vector3(-0.28, 1.72, -0.24))
	MeshKit.add_part(root, "ChimneyFlue", ObjKit.box(Vector3(0.13, 0.02, 0.13), 0.004), MeshKit.mat_color("obj_soot", Color(0.12, 0.10, 0.09), 0.9), Vector3(-0.28, 1.775, -0.24))
	return root

# ----------------------------------------------------------------------------
# OBJ03 - Central crystal beacon
# ----------------------------------------------------------------------------
static func build_crystal_beacon() -> Node3D:
	var root := Node3D.new()
	root.name = "CrystalBeacon"

	var mat_stone := ObjKit.m_stone()
	var mat_stone_l := ObjKit.m_stone_light()
	var mat_stone_d := ObjKit.m_stone_dark()
	var mat_beige := MeshKit.mat_color("obj_beige_stone", Color(0.66, 0.62, 0.56), 0.74, 0.0)
	var mat_cyan := ObjKit.m_cyan_glow()
	var mat_crystal := ObjKit.m_crystal()

	# Lower octagonal tier
	MeshKit.add_part(root, "LowerTier", MeshKit.beveled_cylinder(0.92, 0.92, 0.26, 8, 0.02, false), mat_stone,
		Vector3(0.0, 0.13, 0.0), Vector3(0.0, 22.5, 0.0))
	var lower_blocks: Array = []
	ObjKit.ring_items(lower_blocks, 16, 0.90, 0.13, 0.10, 0.24, 0.92, 0.0, 0.014)
	ObjKit.add_merged(root, "LowerBlockFaces", lower_blocks, mat_stone_l)

	# Upper ring tier with blocks + glowing inserts
	MeshKit.add_part(root, "UpperTier", MeshKit.beveled_cylinder(0.66, 0.66, 0.26, 16, 0.02, false), mat_stone_l, Vector3(0.0, 0.39, 0.0))
	var upper_blocks: Array = []
	ObjKit.ring_items(upper_blocks, 12, 0.66, 0.39, 0.08, 0.24, 0.90, 0.0, 0.014)
	ObjKit.add_merged(root, "UpperBlockFaces", upper_blocks, mat_beige)
	var glow_items: Array = []
	for i in range(6):
		var th := TAU * (float(i) + 0.5) / 6.0
		glow_items.append([ObjKit.box(Vector3(0.03, 0.08, 0.16), 0.006), ObjKit.xf(Vector3(cos(th) * 0.71, 0.39, sin(th) * 0.71), Vector3(0.0, -rad_to_deg(th), 0.0))])
	ObjKit.add_merged(root, "RingGlowInserts", glow_items, mat_cyan)

	# Inner basin rim + glowing core pool
	MeshKit.add_part(root, "BasinRim", MeshKit.beveled_cylinder(0.46, 0.46, 0.10, 16, 0.015, false), mat_stone_d, Vector3(0.0, 0.56, 0.0))
	var rim_blocks: Array = []
	ObjKit.ring_items(rim_blocks, 12, 0.42, 0.57, 0.10, 0.10, 0.90, 0.0, 0.012)
	ObjKit.add_merged(root, "BasinRimBlocks", rim_blocks, mat_stone)
	MeshKit.add_part(root, "GlowPool", MeshKit.beveled_cylinder(0.36, 0.36, 0.04, 20, 0.0, true), mat_cyan, Vector3(0.0, 0.61, 0.0))

	# Four large beige corner blocks on the lower tier
	for k in range(4):
		var th := TAU * (float(k) + 0.5) / 4.0
		MeshKit.add_part(root, "CornerBlock_%d" % k, ObjKit.box(Vector3(0.30, 0.26, 0.30), 0.03), mat_beige,
			Vector3(cos(th) * 0.80, 0.36, sin(th) * 0.80), Vector3(0.0, -rad_to_deg(th), 0.0))

	# Front staircase (+Z) with two glowing posts
	for s in range(3):
		var sh := 0.09 * float(3 - s)
		MeshKit.add_part(root, "Step_%d" % s, ObjKit.box(Vector3(0.56, sh, 0.16), 0.014), mat_beige,
			Vector3(0.0, sh * 0.5, 0.84 + float(s) * 0.15))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "StairPost_%d" % int(sx), ObjKit.box(Vector3(0.22, 0.34, 0.22), 0.025), mat_beige,
			Vector3(sx * 0.40, 0.17, 0.96))
		MeshKit.add_part(root, "StairPostGlow_%d" % int(sx), ObjKit.box(Vector3(0.09, 0.09, 0.02), 0.004), mat_cyan,
			Vector3(sx * 0.40, 0.19, 1.075))

	# Main crystal (hexagonal, pointed) + 3 companion shards on stone sockets
	MeshKit.add_part(root, "MainCrystal", ObjKit.crystal_mesh(0.30, 1.25, 0.46, 6, 0.0), mat_crystal, Vector3(0.0, 0.58, 0.0), Vector3(0.0, 15.0, 0.0))
	var shard_pos := [Vector3(-0.56, 0.0, -0.18), Vector3(0.56, 0.0, -0.18), Vector3(0.0, 0.0, 0.50)]
	for i in range(3):
		var sp: Vector3 = shard_pos[i]
		MeshKit.add_part(root, "ShardSocket_%d" % i, ObjKit.box(Vector3(0.18, 0.10, 0.18), 0.018), mat_stone_d, Vector3(sp.x, 0.57, sp.z))
		MeshKit.add_part(root, "Shard_%d" % i, ObjKit.crystal_mesh(0.10, 0.28, 0.15, 6, 0.0), mat_crystal, Vector3(sp.x, 0.62, sp.z), Vector3(0.0, 30.0 * float(i), 0.0))

	MeshKit.add_light(root, "BeaconGlow", Color(0.25, 0.70, 1.0), 1.2, 3.0, Vector3(0.0, 1.2, 0.0))
	return root

# ----------------------------------------------------------------------------
# OBJ04 - Wooden quest board with pitched canopy & teal emblem
# ----------------------------------------------------------------------------
static func build_quest_board() -> Node3D:
	var root := Node3D.new()
	root.name = "QuestBoard"

	var mat_post := ObjKit.m_timber_dark()
	var mat_plank := ObjKit.m_wood_light()
	var mat_trim := ObjKit.m_timber()
	var mat_stone := ObjKit.m_stone_light()
	var mat_paper := MeshKit.mat_color("obj_parchment", Color(0.97, 0.88, 0.70), 0.85, 0.0)
	var mat_gold := ObjKit.m_gold()
	var mat_teal := MeshKit.mat_emissive("obj_teal_gem", Color(0.30, 0.90, 0.78), Color(0.10, 0.70, 0.60), 1.3, 0.12)

	var px := 0.56
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "FootLow_%d" % int(sx), ObjKit.box(Vector3(0.30, 0.10, 0.30), 0.018), mat_stone, Vector3(sx * px, 0.05, 0.0))
		MeshKit.add_part(root, "FootUp_%d" % int(sx), ObjKit.box(Vector3(0.22, 0.08, 0.22), 0.016), mat_stone, Vector3(sx * px, 0.14, 0.0))
		MeshKit.add_part(root, "Collar_%d" % int(sx), ObjKit.box(Vector3(0.18, 0.07, 0.18), 0.014), mat_trim, Vector3(sx * px, 0.215, 0.0))
		MeshKit.add_part(root, "Post_%d" % int(sx), ObjKit.box(Vector3(0.14, 1.20, 0.14), 0.02), mat_post, Vector3(sx * px, 0.25 + 0.60, 0.0))

	# Plank board
	var plank_items: Array = []
	for i in range(5):
		plank_items.append([ObjKit.box(Vector3(0.98, 0.135, 0.06), 0.012), ObjKit.xf(Vector3(0.0, 0.62 + float(i) * 0.14, 0.0))])
	ObjKit.add_merged(root, "BoardPlanks", plank_items, mat_plank)
	MeshKit.add_part(root, "BottomRail", ObjKit.box(Vector3(1.10, 0.08, 0.10), 0.016), mat_post, Vector3(0.0, 0.53, 0.01))
	MeshKit.add_part(root, "TopBeam", ObjKit.box(Vector3(1.30, 0.09, 0.14), 0.016), mat_post, Vector3(0.0, 1.36, 0.0))

	# Gable canopy: ridge along Z so the triangular face looks to the front
	ObjKit.gable_roof(root, "Canopy", Vector3(0.0, 1.40, 0.0), -90.0, 0.26, 0.62, 0.10, 0.55,
		mat_post, ObjKit.m_timber(), 0.16, [1, -1], ObjKit.m_wood_dark(), mat_trim)

	# Teal emblem in a gold octagon on the gable
	MeshKit.add_part(root, "EmblemRing", MeshKit.beveled_cylinder(0.085, 0.085, 0.04, 8, 0.008, false), mat_gold,
		Vector3(0.0, 1.55, 0.15), Vector3(90.0, 0.0, 0.0))
	MeshKit.add_part(root, "EmblemGem", MeshKit.beveled_cylinder(0.058, 0.058, 0.05, 6, 0.008, false), mat_teal,
		Vector3(0.0, 1.55, 0.16), Vector3(90.0, 0.0, 0.0))

	# Two unlettered notices with gold pins (slightly curled corner)
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "Notice_%d" % int(sx), ObjKit.box(Vector3(0.28, 0.34, 0.015), 0.004), mat_paper,
			Vector3(sx * 0.22, 0.92, 0.04), Vector3(0.0, 0.0, sx * -2.0))
		MeshKit.add_part(root, "NoticeCurl_%d" % int(sx), ObjKit.box(Vector3(0.07, 0.07, 0.015), 0.004), mat_paper,
			Vector3(sx * 0.22 + 0.10, 0.77, 0.055), Vector3(25.0, 0.0, 45.0))
		MeshKit.add_part(root, "Pin_%d" % int(sx), MeshKit.beveled_cylinder(0.025, 0.025, 0.03, 10, 0.006, true), mat_gold,
			Vector3(sx * 0.22, 1.06, 0.06), Vector3(90.0, 0.0, 0.0))
	return root

# ----------------------------------------------------------------------------
# OBJ05 - Striped awning market stall
# ----------------------------------------------------------------------------
static func build_market_stall() -> Node3D:
	var root := Node3D.new()
	root.name = "MarketStall"

	var mat_wood := ObjKit.m_timber()
	var mat_plank := ObjKit.m_wood_light()
	var mat_stone := ObjKit.m_stone_light()
	var mat_blue := MeshKit.mat_color("obj_awning_blue", Color(0.20, 0.45, 0.85), 0.40, 0.0)
	var mat_white := MeshKit.mat_color("obj_awning_white", Color(0.86, 0.84, 0.78), 0.50, 0.0)
	var mat_cap := MeshKit.mat_color("obj_cap_cream", Color(0.70, 0.68, 0.65), 0.6, 0.0)
	var mat_iron := ObjKit.m_iron()

	var hx := 0.56
	var hz := 0.42
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var tag := "%d_%d" % [int(sx), int(sz)]
			MeshKit.add_part(root, "Foot_" + tag, ObjKit.box(Vector3(0.20, 0.12, 0.20), 0.02), mat_stone, Vector3(sx * hx, 0.06, sz * hz))
			var post_h := 1.70 if sz < 0.0 else 1.58
			MeshKit.add_part(root, "Post_" + tag, ObjKit.box(Vector3(0.12, post_h, 0.12), 0.018), mat_wood, Vector3(sx * hx, 0.12 + post_h * 0.5, sz * hz))
			MeshKit.add_part(root, "Cap_" + tag, ObjKit.box(Vector3(0.20, 0.08, 0.20), 0.02), mat_cap, Vector3(sx * hx, 0.12 + post_h + 0.04, sz * hz))
			MeshKit.add_part(root, "CapStud_" + tag, ObjKit.box(Vector3(0.08, 0.05, 0.08), 0.012), ObjKit.m_gold(), Vector3(sx * hx, 0.12 + post_h + 0.105, sz * hz))
			MeshKit.add_part(root, "Bolt_" + tag, MeshKit.beveled_cylinder(0.025, 0.025, 0.02, 10, 0.005, true), mat_iron,
				Vector3(sx * hx, 0.56, sz * hz + sz * 0.065), Vector3(90.0, 0.0, 0.0))

	# Lower shelf + two small crates
	MeshKit.add_part(root, "Shelf", ObjKit.box(Vector3(hx * 2.0, 0.06, hz * 2.0), 0.012), mat_plank, Vector3(0.0, 0.20, 0.0))
	for i in range(2):
		var c := BuilderCharsProps.build_crate("gold_top")
		c.name = "ShelfCrate_%d" % i
		c.scale = Vector3(0.40, 0.40, 0.40)
		c.position = Vector3(-0.22 + float(i) * 0.46, 0.23, 0.05)
		root.add_child(c)

	# Counter (two big boards + rails)
	for i in range(2):
		MeshKit.add_part(root, "CounterBoard_%d" % i, ObjKit.box(Vector3(hx * 2.0 + 0.10, 0.08, hz + 0.04), 0.014), mat_plank,
			Vector3(0.0, 0.62, (float(i) - 0.5) * (hz + 0.05)))
	MeshKit.add_part(root, "CounterFrontRail", ObjKit.box(Vector3(hx * 2.0 + 0.12, 0.14, 0.07), 0.016), mat_wood, Vector3(0.0, 0.53, hz + 0.02))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "CounterSideRail_%d" % int(sx), ObjKit.box(Vector3(0.07, 0.14, hz * 2.0), 0.016), mat_wood, Vector3(sx * (hx + 0.02), 0.53, 0.0))
	MeshKit.add_part(root, "ShelfRail", ObjKit.box(Vector3(hx * 2.0, 0.08, 0.06), 0.012), mat_wood, Vector3(0.0, 0.16, hz + 0.02))

	# Striped awning sloping toward the front (+Z)
	var aw := root
	var slope := 8.0
	var stripes := 5
	var a_width := hx * 2.0 + 0.30
	var sw := a_width / float(stripes)
	var a_depth := hz * 2.0 + 0.32
	var awn := ObjKit.group(aw, "Awning", Vector3(0.0, 1.70, 0.0), Vector3(slope, 0.0, 0.0))
	var blue_items: Array = []
	var white_items: Array = []
	for i in range(stripes):
		var lx := -a_width * 0.5 + sw * (float(i) + 0.5)
		var target := blue_items if i % 2 == 0 else white_items
		target.append([ObjKit.box(Vector3(sw * 1.0, 0.07, a_depth), 0.025), ObjKit.xf(Vector3(lx, 0.0, 0.0))])
		# scalloped front valance
		target.append([MeshKit.beveled_cylinder(sw * 0.48, sw * 0.48, 0.06, 18, 0.01, true), ObjKit.xf(Vector3(lx, -0.06, a_depth * 0.5), Vector3(90.0, 0.0, 0.0))])
	# scalloped right-side valance (+X)
	var side_n := 4
	var sdw := a_depth / float(side_n)
	for j in range(side_n):
		var lz := -a_depth * 0.5 + sdw * (float(j) + 0.5)
		var target2 := blue_items if j % 2 == 1 else white_items
		target2.append([MeshKit.beveled_cylinder(sdw * 0.48, sdw * 0.48, 0.06, 18, 0.01, true), ObjKit.xf(Vector3(a_width * 0.5, -0.06, lz), Vector3(0.0, 0.0, 90.0))])
	ObjKit.add_merged(awn, "AwningBlue", blue_items, mat_blue)
	ObjKit.add_merged(awn, "AwningWhite", white_items, mat_white)
	return root

# ----------------------------------------------------------------------------
# OBJ06 - Round stone plaza (concentric paving rings + scalloped edge)
# ----------------------------------------------------------------------------
static func build_round_plaza() -> Node3D:
	var root := Node3D.new()
	root.name = "RoundPlaza"

	var mat_core := ObjKit.m_stone_dark()
	var mat_edge := MeshKit.mat_color("plaza_edge", Color(0.50, 0.47, 0.46), 0.80, 0.0)
	var mat_edge_l := MeshKit.mat_color("plaza_edge_l", Color(0.58, 0.55, 0.53), 0.78, 0.0)
	var mat_tan_a := MeshKit.mat_color("plaza_tan_a", Color(0.80, 0.66, 0.50), 0.76, 0.0)
	var mat_tan_b := MeshKit.mat_color("plaza_tan_b", Color(0.70, 0.58, 0.46), 0.78, 0.0)
	var mat_gray_ring := MeshKit.mat_color("plaza_gray_ring", Color(0.60, 0.56, 0.53), 0.78, 0.0)

	var R := 1.40
	var base_h := 0.28
	MeshKit.add_part(root, "Core", MeshKit.beveled_cylinder(R - 0.08, R - 0.08, base_h, 32, 0.0, true), mat_core, Vector3(0.0, base_h * 0.5, 0.0))

	# Two staggered courses of edge blocks
	var edge_a: Array = []
	var edge_b: Array = []
	ObjKit.ring_items(edge_a, 30, R - 0.06, 0.07, 0.16, 0.135, 0.95, 0.0, 0.016)
	ObjKit.ring_items(edge_b, 30, R - 0.07, 0.21, 0.16, 0.135, 0.95, PI / 30.0, 0.016)
	ObjKit.add_merged(root, "EdgeCourseLow", edge_a, mat_edge)
	ObjKit.add_merged(root, "EdgeCourseHigh", edge_b, mat_edge_l)

	# Top paving rings (radius bands)
	var top_y := base_h + 0.03
	var bands := [[0.22, 0.46, mat_tan_b], [0.46, 0.72, mat_tan_a], [0.72, 0.98, mat_gray_ring], [0.98, 1.20, mat_tan_b]]
	MeshKit.add_part(root, "CenterDisc", MeshKit.beveled_cylinder(0.21, 0.21, 0.06, 24, 0.012, true), mat_tan_a, Vector3(0.0, top_y, 0.0))
	for bi in range(bands.size()):
		var b: Array = bands[bi]
		var r0: float = b[0]
		var r1: float = b[1]
		var rm := (r0 + r1) * 0.5
		var n := maxi(int(round(TAU * rm / 0.19)), 8)
		var items: Array = []
		ObjKit.ring_items(items, n, rm, top_y, (r1 - r0) * 0.92, 0.06, 0.92, float(bi) * 0.13, 0.012)
		ObjKit.add_merged(root, "PavingRing_%d" % bi, items, b[2])

	# Rim curb on the top edge
	var rim: Array = []
	ObjKit.ring_items(rim, 36, R - 0.10, top_y + 0.01, 0.18, 0.08, 0.95, 0.0, 0.016)
	ObjKit.add_merged(root, "RimCurb", rim, mat_edge_l)

	# Eight cap pillars around the edge
	for k in range(8):
		var th := TAU * float(k) / 8.0 + PI / 8.0
		var pp := Vector3(cos(th) * (R - 0.08), 0.0, sin(th) * (R - 0.08))
		MeshKit.add_part(root, "CapPillar_%d" % k, ObjKit.box(Vector3(0.26, 0.24, 0.26), 0.03), mat_edge_l,
			pp + Vector3(0.0, top_y + 0.10, 0.0), Vector3(0.0, -rad_to_deg(th), 0.0))
		MeshKit.add_part(root, "CapInset_%d" % k, ObjKit.box(Vector3(0.12, 0.02, 0.12), 0.005), mat_edge,
			pp + Vector3(0.0, top_y + 0.225, 0.0), Vector3(0.0, -rad_to_deg(th), 0.0))
	return root

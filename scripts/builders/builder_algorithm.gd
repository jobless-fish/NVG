class_name BuilderAlgorithm
extends RefCounted

## Algorithm-island objects (source: NODEVERSE objects/OBJ12-OBJ16):
## OBJ12 sort_steps, OBJ13 graph_node, OBJ14 graph_edge,
## OBJ15 maze_garden, OBJ16 branch_path

# ----------------------------------------------------------------------------
# OBJ12 - Sorting staircase: 6 colored prisms of increasing height on a stepped plinth
# ----------------------------------------------------------------------------
static func build_sort_steps() -> Node3D:
	var root := Node3D.new()
	root.name = "SortSteps"

	var mat_stone := ObjKit.m_stone()
	var mat_stone_l := ObjKit.m_stone_light()
	var colors := [
		Color(0.12, 0.42, 0.92), Color(0.22, 0.82, 0.86), Color(0.40, 0.80, 0.18),
		Color(0.98, 0.78, 0.12), Color(0.98, 0.50, 0.10), Color(0.90, 0.18, 0.16)
	]

	# Stepped gray plinth (three courses, rising to a back-right wall block)
	MeshKit.add_part(root, "PlinthCourse_0", ObjKit.box(Vector3(2.36, 0.10, 1.02), 0.02), mat_stone, Vector3(0.0, 0.05, 0.08))
	MeshKit.add_part(root, "PlinthCourse_1", ObjKit.box(Vector3(2.26, 0.10, 0.86), 0.02), mat_stone_l, Vector3(0.0, 0.15, 0.02))
	MeshKit.add_part(root, "PlinthCourse_2", ObjKit.box(Vector3(2.16, 0.10, 0.70), 0.02), mat_stone, Vector3(0.0, 0.25, -0.04))
	var joints: Array = []
	for i in range(6):
		joints.append([ObjKit.box(Vector3(0.012, 0.09, 0.012), 0.002), ObjKit.xf(Vector3(-1.0 + float(i) * 0.40, 0.05, 0.59))])
		joints.append([ObjKit.box(Vector3(0.012, 0.09, 0.012), 0.002), ObjKit.xf(Vector3(-0.9 + float(i) * 0.40, 0.15, 0.45))])
	ObjKit.add_merged(root, "PlinthJoints", joints, ObjKit.m_stone_dark())
	MeshKit.add_part(root, "EndWall", ObjKit.box(Vector3(0.26, 0.58, 0.72), 0.025), mat_stone_l, Vector3(1.20, 0.29, -0.04))
	MeshKit.add_part(root, "EndWallCap", ObjKit.box(Vector3(0.30, 0.06, 0.76), 0.02), mat_stone, Vector3(1.20, 0.61, -0.04))

	# Six glossy columns built from stacked unit cubes (heights 1..6)
	var unit := 0.25
	var col_w := 0.30
	var col_d := 0.40
	for i in range(6):
		var m := MeshKit.mat_color("sort_col_%d" % i, colors[i], 0.22, 0.05)
		var x := -0.88 + float(i) * 0.345
		var stack: Array = []
		for u in range(i + 1):
			stack.append([ObjKit.box(Vector3(col_w, unit - 0.008, col_d), 0.03), ObjKit.xf(Vector3(x, 0.30 + unit * (float(u) + 0.5), -0.04))])
		ObjKit.add_merged(root, "Column_%d" % (i + 1), stack, m)
	return root

# ----------------------------------------------------------------------------
# OBJ13 - Graph node pedestal
# ----------------------------------------------------------------------------
static func build_graph_node() -> Node3D:
	var root := Node3D.new()
	root.name = "GraphNode"

	var mat_stone := ObjKit.m_stone_light()
	var mat_stone_d := ObjKit.m_stone()
	var mat_ivory := MeshKit.mat_color("gn_ivory", Color(0.84, 0.74, 0.56), 0.58, 0.0)
	var mat_ivory_d := MeshKit.mat_color("gn_ivory_d", Color(0.72, 0.64, 0.50), 0.6, 0.0)
	var mat_white := MeshKit.mat_color("gn_white", Color(0.82, 0.82, 0.85), 0.18, 0.0)
	var mat_rim := MeshKit.mat_color("gn_rim", Color(0.70, 0.69, 0.68), 0.32, 0.0)
	var mat_cyan := ObjKit.m_cyan_glow()

	# Chamfered square gray foot
	MeshKit.add_part(root, "Foot", MeshKit.beveled_cylinder(0.70, 0.70, 0.16, 8, 0.02, false), mat_stone, Vector3(0.0, 0.08, 0.0), Vector3(0.0, 22.5, 0.0))
	var foot_blocks: Array = []
	for k in range(8):
		var th := TAU * float(k) / 8.0
		foot_blocks.append([ObjKit.box(Vector3(0.05, 0.14, 0.40), 0.015), ObjKit.xf(Vector3(cos(th) * 0.63, 0.08, sin(th) * 0.63), Vector3(0.0, -rad_to_deg(th), 0.0))])
	ObjKit.add_merged(root, "FootFaces", foot_blocks, mat_stone_d)

	# Ivory pillar with panel seams
	var pr := 0.50
	var ph := 0.46
	MeshKit.add_part(root, "Pillar", MeshKit.beveled_cylinder(pr, pr, ph, 28, 0.0, true), mat_ivory, Vector3(0.0, 0.16 + ph * 0.5, 0.0))
	var seams: Array = []
	for k in range(8):
		var th := TAU * (float(k) + 0.5) / 8.0
		seams.append([ObjKit.box(Vector3(0.014, ph * 0.94, 0.02), 0.002), ObjKit.xf(Vector3(cos(th) * (pr + 0.002), 0.16 + ph * 0.5, sin(th) * (pr + 0.002)), Vector3(0.0, -rad_to_deg(th), 0.0))])
	seams.append([MeshKit.beveled_cylinder(pr + 0.004, pr + 0.004, 0.012, 28, 0.0, true), ObjKit.xf(Vector3(0.0, 0.16 + ph * 0.45, 0.0))])
	ObjKit.add_merged(root, "PillarSeams", seams, mat_ivory_d)

	# Rounded white top: segmented rim + glossy domed disk
	var top_y := 0.16 + ph
	MeshKit.add_part(root, "TopRim", MeshKit.beveled_cylinder(0.58, 0.58, 0.13, 32, 0.04, true), mat_rim, Vector3(0.0, top_y + 0.065, 0.0))
	var rim_seams: Array = []
	for k in range(4):
		var th := TAU * float(k) / 4.0 + PI / 4.0
		rim_seams.append([ObjKit.box(Vector3(0.10, 0.135, 0.012), 0.002), ObjKit.xf(Vector3(cos(th) * 0.53, top_y + 0.065, sin(th) * 0.53), Vector3(0.0, -rad_to_deg(th), 0.0))])
	ObjKit.add_merged(root, "TopRimSeams", rim_seams, mat_ivory_d)
	MeshKit.add_part(root, "TopDisk", MeshKit.beveled_cylinder(0.46, 0.44, 0.06, 32, 0.025, true), mat_white, Vector3(0.0, top_y + 0.14, 0.0))

	# Cyan connection sockets on 4 sides
	for k in range(4):
		var ang := float(k) * 90.0
		var dir := Vector3(sin(deg_to_rad(ang)), 0.0, cos(deg_to_rad(ang)))
		MeshKit.add_part(root, "SocketFrame_%d" % k, ObjKit.box(Vector3(0.17, 0.17, 0.06), 0.02), mat_stone_d, Vector3(0.0, 0.40, 0.0) + dir * (pr + 0.01), Vector3(0.0, ang, 0.0))
		MeshKit.add_part(root, "SocketGlow_%d" % k, ObjKit.box(Vector3(0.10, 0.10, 0.03), 0.008), mat_cyan, Vector3(0.0, 0.40, 0.0) + dir * (pr + 0.035), Vector3(0.0, ang, 0.0))
	return root

# ----------------------------------------------------------------------------
# OBJ14 - Graph edge: glowing cyan bar between two ivory terminal blocks
# ----------------------------------------------------------------------------
static func build_graph_edge() -> Node3D:
	var root := Node3D.new()
	root.name = "GraphEdge"

	var mat_ivory := MeshKit.mat_color("ge_ivory", Color(0.80, 0.73, 0.60), 0.6, 0.0)
	var mat_stone := ObjKit.m_stone()
	var mat_stone_l := ObjKit.m_stone_light()
	var mat_wood := ObjKit.m_timber()
	var mat_iron := ObjKit.m_iron()
	var mat_cyan := ObjKit.m_cyan_glow()
	var mat_bar := MeshKit.mat_emissive("ge_bar", Color(0.30, 0.80, 1.0), Color(0.08, 0.60, 1.0), 1.6, 0.06)
	mat_bar.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_bar.albedo_color = Color(0.30, 0.80, 1.0, 0.82)

	var tx := 0.80
	for sx: float in [-1.0, 1.0]:
		var g := ObjKit.group(root, "Terminal_%s" % ("R" if sx > 0.0 else "L"), Vector3(sx * tx, 0.0, 0.0), Vector3(0.0, 0.0 if sx > 0.0 else 180.0, 0.0))
		MeshKit.add_part(g, "Base", ObjKit.box(Vector3(0.50, 0.12, 0.50), 0.02), mat_stone, Vector3(0.0, 0.06, 0.0))
		MeshKit.add_part(g, "Core", ObjKit.box(Vector3(0.44, 0.36, 0.44), 0.025), mat_ivory, Vector3(0.0, 0.30, 0.0))
		MeshKit.add_part(g, "TopPlate", ObjKit.box(Vector3(0.40, 0.05, 0.40), 0.015), mat_ivory, Vector3(0.0, 0.505, 0.0))
		MeshKit.add_part(g, "TopKnob", ObjKit.box(Vector3(0.16, 0.07, 0.16), 0.015), mat_stone_l, Vector3(0.0, 0.565, 0.0))
		# windows on the outer (+X) face and front (+Z) face, wooden side braces with rivets
		for face in range(2):
			# face 0 = outer end (local +X); face 1 = world front (+Z) for both terminals
			var front_yaw := 0.0 if sx > 0.0 else 180.0
			var fyaw := 90.0 if face == 0 else front_yaw
			var fdir := Vector3(1.0, 0.0, 0.0) if face == 0 else Vector3(0.0, 0.0, sx)
			MeshKit.add_part(g, "Window_%d" % face, ObjKit.box(Vector3(0.12, 0.14, 0.02), 0.004), mat_cyan, Vector3(0.0, 0.31, 0.0) + fdir * 0.225, Vector3(0.0, fyaw, 0.0))
			MeshKit.add_part(g, "WindowFrame_%d" % face, ObjKit.box(Vector3(0.18, 0.20, 0.02), 0.006), mat_stone_l, Vector3(0.0, 0.31, 0.0) + fdir * 0.218, Vector3(0.0, fyaw, 0.0))
			for b in [-1.0, 1.0]:
				var lateral := Vector3(0.0, 0.0, 1.0) if face == 0 else Vector3(1.0, 0.0, 0.0)
				var bp := Vector3(0.0, 0.30, 0.0) + fdir * 0.235 + lateral * (float(b) * 0.165)
				MeshKit.add_part(g, "Brace_%d_%d" % [face, int(b)], ObjKit.box(Vector3(0.06, 0.40, 0.025), 0.008), mat_wood, bp, Vector3(0.0, fyaw, 0.0))
				for ry: float in [0.17, 0.43]:
					MeshKit.add_part(g, "Rivet_%d_%d_%d" % [face, int(b), int(ry * 100.0)], ObjKit.box(Vector3(0.025, 0.025, 0.02), 0.005), mat_iron, Vector3(bp.x, ry, bp.z) + fdir * 0.015, Vector3(0.0, fyaw, 0.0))
		# collar toward the bar (-X in local space)
		MeshKit.add_part(g, "Collar", ObjKit.box(Vector3(0.10, 0.28, 0.30), 0.02), mat_stone, Vector3(-0.27, 0.30, 0.0))

	MeshKit.add_part(root, "GlowBar", ObjKit.box(Vector3(tx * 2.0 - 0.56, 0.20, 0.22), 0.02), mat_bar, Vector3(0.0, 0.30, 0.0))
	MeshKit.add_part(root, "GlowBarCore", ObjKit.box(Vector3(tx * 2.0 - 0.58, 0.08, 0.08), 0.01), mat_cyan, Vector3(0.0, 0.30, 0.0))
	MeshKit.add_light(root, "EdgeGlow", Color(0.2, 0.75, 1.0), 0.7, 2.0, Vector3(0.0, 0.45, 0.3))
	return root

# ----------------------------------------------------------------------------
# OBJ15 - Square hedge maze garden
# ----------------------------------------------------------------------------
const MAZE_LAYOUT := [
	"######.####",
	"#.........#",
	"#.###.###.#",
	"#.#.....#.#",
	"#.#.###.#.#",
	"#...#C..#.#",
	"###.###.#.#",
	"#.......#.#",
	"#.#######.#",
	"#.........#",
	"####.######"
]

static func build_maze_garden() -> Node3D:
	var root := Node3D.new()
	root.name = "MazeGarden"

	var mat_base := MeshKit.mat_color("mz_base", Color(0.38, 0.68, 0.16), 0.7, 0.0)
	var mat_hedge := MeshKit.mat_color("mz_hedge", Color(0.40, 0.68, 0.10), 0.78, 0.0)
	var mat_hedge_l := MeshKit.mat_color("mz_hedge_l", Color(0.52, 0.78, 0.16), 0.72, 0.0)
	var mat_sand := MeshKit.mat_color("mz_sand", Color(0.84, 0.70, 0.52), 0.85, 0.0)
	var mat_sand_d := MeshKit.mat_color("mz_sand_d", Color(0.78, 0.64, 0.47), 0.85, 0.0)

	var n: int = MAZE_LAYOUT.size()
	var cell := 0.21
	var half := float(n) * cell * 0.5
	MeshKit.add_part(root, "BaseSlab", ObjKit.box(Vector3(half * 2.0 + 0.14, 0.08, half * 2.0 + 0.14), 0.02), mat_base, Vector3(0.0, 0.04, 0.0))

	var hedge_low: Array = []
	var hedge_top: Array = []
	var sand_a: Array = []
	var sand_b: Array = []
	var center := Vector3.ZERO
	for r in range(n):
		var row: String = MAZE_LAYOUT[r]
		for c in range(row.length()):
			var ch := row[c]
			var px := -half + (float(c) + 0.5) * cell
			var pz := -half + (float(r) + 0.5) * cell
			if ch == "#":
				var hh := 0.13 + MeshKit._hash_float(r, c, 41) * 0.02
				hedge_low.append([ObjKit.box(Vector3(cell, hh, cell), 0.02), ObjKit.xf(Vector3(px, 0.08 + hh * 0.5, pz))])
				# leafy bumps on top
				for q in range(4):
					var ox := (float(q % 2) - 0.5) * cell * 0.5
					var oz := (float(q / 2) - 0.5) * cell * 0.5
					var bh := 0.03 + MeshKit._hash_float(r * 4 + q, c, 77) * 0.025
					hedge_top.append([ObjKit.box(Vector3(cell * 0.46, bh, cell * 0.46), 0.015), ObjKit.xf(Vector3(px + ox, 0.08 + hh + bh * 0.5 - 0.01, pz + oz))])
			else:
				var target := sand_a if (r + c) % 2 == 0 else sand_b
				target.append([ObjKit.box(Vector3(cell * 0.97, 0.03, cell * 0.97), 0.008), ObjKit.xf(Vector3(px, 0.095, pz))])
				if ch == "C":
					center = Vector3(px, 0.0, pz)
	ObjKit.add_merged(root, "Hedges", hedge_low, mat_hedge)
	ObjKit.add_merged(root, "HedgeLeaves", hedge_top, mat_hedge_l)
	ObjKit.add_merged(root, "SandPathA", sand_a, mat_sand)
	ObjKit.add_merged(root, "SandPathB", sand_b, mat_sand_d)

	# Goal pedestal in the maze center
	MeshKit.add_part(root, "GoalPedestal", ObjKit.box(Vector3(0.14, 0.18, 0.14), 0.015), ObjKit.m_stone_light(), center + Vector3(0.0, 0.20, 0.0))
	MeshKit.add_part(root, "GoalTop", ObjKit.box(Vector3(0.16, 0.04, 0.16), 0.01), MeshKit.mat_color("mz_cream", Color(0.96, 0.93, 0.84), 0.6), center + Vector3(0.0, 0.31, 0.0))
	MeshKit.add_part(root, "GoalGem", ObjKit.box(Vector3(0.06, 0.04, 0.06), 0.01), ObjKit.m_gold(), center + Vector3(0.0, 0.345, 0.0))
	return root

# ----------------------------------------------------------------------------
# OBJ16 - Three-way fork footpath (Y junction)
# ----------------------------------------------------------------------------
static func build_branch_path() -> Node3D:
	var root := Node3D.new()
	root.name = "BranchPath"

	var mat_edge := MeshKit.mat_color("bp_edge", Color(0.46, 0.45, 0.46), 0.80, 0.0)
	var mat_edge_l := MeshKit.mat_color("bp_edge_l", Color(0.56, 0.55, 0.55), 0.78, 0.0)
	var mat_path := MeshKit.mat_color("bp_path", Color(1.0, 0.82, 0.60), 0.82, 0.0, "stone_ashlar")
	var mat_medal := MeshKit.mat_color("bp_medal", Color(0.92, 0.78, 0.60), 0.8, 0.0)

	var dirs: Array = [Vector2(0.0, 1.0), Vector2(-0.866, -0.5), Vector2(0.866, -0.5)]
	var hw := 0.26
	var L := 1.05
	var wt := 0.12
	var inner := ObjKit.arms_polygon(dirs, hw, L, 0.20)

	var base_poly := ObjKit._largest_poly(Geometry2D.offset_polygon(inner, wt, Geometry2D.JOIN_MITER))
	MeshKit.add_part(root, "BaseSlab", MeshKit.extrude_polygon_xz(base_poly, 0.14, 2.0), mat_edge, Vector3(0.0, 0.07, 0.0))
	MeshKit.add_part(root, "PathSurface", MeshKit.extrude_polygon_xz(inner, 0.04, 2.4), mat_path, Vector3(0.0, 0.155, 0.0))

	var wi := 0
	for wp: PackedVector2Array in ObjKit.arm_walls(dirs, hw, L, wt, 0.20):
		MeshKit.add_part(root, "Curb_%d" % wi, MeshKit.extrude_polygon_xz(wp, 0.08, 2.0), mat_edge_l, Vector3(0.0, 0.18, 0.0))
		wi += 1
	# curb block joints & end blocks
	var joints: Array = []
	for ai in range(dirs.size()):
		var d: Vector2 = dirs[ai]
		var p := Vector2(-d.y, d.x)
		var yaw := -rad_to_deg(atan2(d.y, d.x))
		for sgn: float in [-1.0, 1.0]:
			for k in range(4):
				var jp := d * (0.42 + float(k) * 0.18) + p * sgn * (hw + wt * 0.5)
				joints.append([ObjKit.box(Vector3(0.012, 0.085, wt + 0.01), 0.002), ObjKit.xf(Vector3(jp.x, 0.18, jp.y), Vector3(0.0, yaw, 0.0))])
			var e := d * (L - 0.06) + p * sgn * (hw + wt * 0.5)
			MeshKit.add_part(root, "EndBlock_%d_%d" % [ai, int(sgn)], ObjKit.box(Vector3(0.13, 0.12, 0.15), 0.02), mat_edge_l, Vector3(e.x, 0.20, e.y), Vector3(0.0, yaw, 0.0))
	ObjKit.add_merged(root, "CurbJoints", joints, ObjKit.m_stone_dark())

	# Circular medallion at the junction
	MeshKit.add_part(root, "MedallionOuter", MeshKit.beveled_cylinder(0.24, 0.24, 0.02, 28, 0.0, true), mat_medal, Vector3(0.0, 0.18, 0.0))
	MeshKit.add_part(root, "MedallionRing", MeshKit.beveled_cylinder(0.18, 0.18, 0.024, 28, 0.0, true), mat_path, Vector3(0.0, 0.181, 0.0))
	MeshKit.add_part(root, "MedallionInner", MeshKit.beveled_cylinder(0.08, 0.08, 0.03, 20, 0.0, true), mat_medal, Vector3(0.0, 0.183, 0.0))
	var spokes: Array = []
	for k in range(8):
		var th := TAU * float(k) / 8.0
		spokes.append([ObjKit.box(Vector3(0.10, 0.026, 0.01), 0.002), ObjKit.xf(Vector3(cos(th) * 0.13, 0.183, sin(th) * 0.13), Vector3(0.0, -rad_to_deg(th), 0.0))])
	ObjKit.add_merged(root, "MedallionSpokes", spokes, ObjKit.m_stone_dark())
	return root

class_name BuilderSQL
extends RefCounted

## SQL-island objects (source: NODEVERSE objects/OBJ07-OBJ11):
## OBJ07 sql_database, OBJ08 sql_archive, OBJ09 sql_library,
## OBJ10 sql_table, OBJ11 sql_query_y

# ----------------------------------------------------------------------------
# OBJ07 - Cylindrical database tower (4 ivory disks + glowing cyan bands)
# ----------------------------------------------------------------------------
static func build_sql_database() -> Node3D:
	var root := Node3D.new()
	root.name = "SQLDatabase"

	var mat_stone := ObjKit.m_stone()
	var mat_stone_l := ObjKit.m_stone_light()
	var mat_ivory := ObjKit.m_ivory()
	var mat_ivory_d := ObjKit.m_ivory_dark()
	var mat_band := ObjKit.m_blue_glow()
	var mat_cyan := ObjKit.m_cyan_glow()
	var mat_cap := MeshKit.mat_color("db_cap", Color(0.62, 0.62, 0.63), 0.55, 0.05)

	# Octagonal two-step foundation
	MeshKit.add_part(root, "FoundationLow", MeshKit.beveled_cylinder(1.00, 1.00, 0.16, 8, 0.02, false), mat_stone,
		Vector3(0.0, 0.08, 0.0), Vector3(0.0, 22.5, 0.0))
	MeshKit.add_part(root, "FoundationUp", MeshKit.beveled_cylinder(0.86, 0.86, 0.22, 8, 0.02, false), mat_stone_l,
		Vector3(0.0, 0.27, 0.0), Vector3(0.0, 22.5, 0.0))
	# Ivory pilaster blocks at the 8 corners with cyan windows
	for k in range(8):
		var th := TAU * float(k) / 8.0 + PI / 8.0
		var g := ObjKit.group(root, "Pilaster_%d" % k, Vector3(cos(th) * 0.84, 0.0, sin(th) * 0.84), Vector3(0.0, 90.0 - rad_to_deg(th), 0.0))
		MeshKit.add_part(g, "Block", ObjKit.box(Vector3(0.22, 0.34, 0.18), 0.02), mat_ivory, Vector3(0.0, 0.30, 0.0))
		MeshKit.add_part(g, "Window", ObjKit.box(Vector3(0.08, 0.13, 0.02), 0.004), mat_cyan, Vector3(0.0, 0.31, 0.095))
	# Front service port (+Z)
	MeshKit.add_part(root, "PortHousing", ObjKit.box(Vector3(0.32, 0.30, 0.16), 0.025), mat_stone_l, Vector3(0.0, 0.30, 0.86))
	MeshKit.add_part(root, "PortGlow", ObjKit.box(Vector3(0.18, 0.07, 0.02), 0.004), mat_cyan, Vector3(0.0, 0.36, 0.945))
	for i in range(2):
		MeshKit.add_part(root, "PortGrille_%d" % i, ObjKit.box(Vector3(0.16, 0.022, 0.02), 0.004), ObjKit.m_stone_dark(), Vector3(0.0, 0.25 - float(i) * 0.04, 0.945))

	# Tower: dark-blue glowing base band, then 4 ivory disks separated by cyan bands
	var y := 0.38
	var band_h := 0.11
	var disk_h := 0.30
	var R := 0.66
	_add_band(root, "BaseBand", y, 0.22, R - 0.02, mat_band, mat_cyan)
	y += 0.22
	for i in range(4):
		var disk := MeshKit.beveled_cylinder(R, R, disk_h, 24, 0.03, true)
		MeshKit.add_part(root, "Disk_%d" % i, disk, mat_ivory, Vector3(0.0, y + disk_h * 0.5, 0.0))
		# vertical seams dividing each disk into stone segments
		var seams: Array = []
		for s in range(10):
			var th := TAU * (float(s) + 0.25 * float(i % 2)) / 10.0
			seams.append([ObjKit.box(Vector3(0.012, disk_h * 0.86, 0.02), 0.002), ObjKit.xf(Vector3(cos(th) * (R + 0.002), y + disk_h * 0.5, sin(th) * (R + 0.002)), Vector3(0.0, -rad_to_deg(th), 0.0))])
		ObjKit.add_merged(root, "DiskSeams_%d" % i, seams, mat_ivory_d)
		y += disk_h
		if i < 3:
			_add_band(root, "Band_%d" % i, y, band_h, R - 0.05, mat_band, mat_cyan)
			y += band_h
	# Gray cap disk inset on top
	MeshKit.add_part(root, "TopCap", MeshKit.beveled_cylinder(R - 0.10, R - 0.10, 0.04, 24, 0.01, true), mat_cap, Vector3(0.0, y + 0.01, 0.0))
	MeshKit.add_light(root, "TowerGlow", Color(0.20, 0.70, 1.0), 0.8, 2.6, Vector3(0.0, 1.2, 0.9))
	return root

static func _add_band(root: Node3D, bname: String, y0: float, h: float, r: float, band_mat: Material, glow_mat: Material) -> void:
	MeshKit.add_part(root, bname, MeshKit.beveled_cylinder(r, r, h, 24, 0.0, true), band_mat, Vector3(0.0, y0 + h * 0.5, 0.0))
	var items: Array = []
	for k in range(8):
		var th := TAU * float(k) / 8.0 + PI / 8.0
		items.append([ObjKit.box(Vector3(0.03, h * 0.55, 0.20), 0.006), ObjKit.xf(Vector3(cos(th) * (r + 0.005), y0 + h * 0.5, sin(th) * (r + 0.005)), Vector3(0.0, -rad_to_deg(th), 0.0))])
	ObjKit.add_merged(root, bname + "_Lights", items, glow_mat)

# ----------------------------------------------------------------------------
# OBJ08 - Classical ivory archive hall (portico, arched entrance, blue hipped roof)
# ----------------------------------------------------------------------------
static func build_sql_archive() -> Node3D:
	var root := Node3D.new()
	root.name = "SQLArchive"

	var mat_stone := ObjKit.m_stone()
	var mat_ivory := ObjKit.m_ivory()
	var mat_ivory_d := ObjKit.m_ivory_dark()
	var mat_gold := ObjKit.m_gold()
	var mat_roof := ObjKit.m_blue_roof()
	var mat_roof_d := ObjKit.m_blue_roof_dark()
	var mat_glow := ObjKit.m_window_glow()
	var mat_cyan := ObjKit.m_cyan_glow()
	var mat_door := ObjKit.m_timber_dark()

	# Stepped plinth
	MeshKit.add_part(root, "PlinthLow", ObjKit.box(Vector3(2.00, 0.16, 1.56), 0.02), mat_stone, Vector3(0.0, 0.08, 0.0))
	MeshKit.add_part(root, "PlinthUp", ObjKit.box(Vector3(1.86, 0.10, 1.42), 0.02), mat_ivory_d, Vector3(0.0, 0.21, -0.02))

	# Hall body
	var body_y0 := 0.26
	var body_h := 0.82
	MeshKit.add_part(root, "HallBody", ObjKit.box(Vector3(1.64, body_h, 1.16), 0.015), mat_ivory, Vector3(0.0, body_y0 + body_h * 0.5, -0.06))
	# block courses (horizontal joints)
	var joints: Array = []
	for j in range(4):
		var jy := body_y0 + 0.18 + float(j) * 0.18
		joints.append([ObjKit.box(Vector3(1.66, 0.012, 1.18), 0.002), ObjKit.xf(Vector3(0.0, jy, -0.06))])
	ObjKit.add_merged(root, "CourseJoints", joints, mat_ivory_d)

	# Corner pilasters with gold capitals + studs
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * 0.84, 0.0, -0.06 + sz * 0.60)
			MeshKit.add_part(root, "Pilaster_%d_%d" % [int(sx), int(sz)], ObjKit.box(Vector3(0.20, body_h + 0.04, 0.20), 0.02), mat_ivory, p + Vector3(0.0, body_y0 + body_h * 0.5, 0.0))
			MeshKit.add_part(root, "PilasterCap_%d_%d" % [int(sx), int(sz)], ObjKit.box(Vector3(0.24, 0.07, 0.24), 0.015), mat_gold, p + Vector3(0.0, body_y0 + body_h + 0.06, 0.0))
			MeshKit.add_part(root, "PilasterStud_%d_%d" % [int(sx), int(sz)], MeshKit.beveled_cylinder(0.07, 0.07, 0.10, 12, 0.02, true), mat_ivory, p + Vector3(0.0, body_y0 + body_h + 0.42, 0.0))

	# Cornice + gold trim
	var cornice_y := body_y0 + body_h + 0.05
	MeshKit.add_part(root, "GoldTrim", ObjKit.box(Vector3(1.78, 0.035, 1.30), 0.006), mat_gold, Vector3(0.0, cornice_y - 0.04, -0.06))
	MeshKit.add_part(root, "Cornice", ObjKit.box(Vector3(1.80, 0.10, 1.32), 0.02), mat_ivory, Vector3(0.0, cornice_y + 0.03, -0.06))

	# Stepped hipped roof (blue tile courses) + lantern
	var ry := cornice_y + 0.08
	for k in range(5):
		var sx_r := 1.64 - float(k) * 0.26
		var sz_r := 1.16 - float(k) * 0.20
		MeshKit.add_part(root, "RoofCourse_%d" % k, ObjKit.box(Vector3(sx_r, 0.09, sz_r), 0.03), mat_roof if k % 2 == 0 else mat_roof_d,
			Vector3(0.0, ry + float(k) * 0.085 + 0.045, -0.06))
		# tile bumps along the front course edge
		var tiles: Array = []
		var n := int(sx_r / 0.16)
		for t in range(n):
			var tx := -sx_r * 0.5 + (float(t) + 0.5) * (sx_r / float(n))
			tiles.append([ObjKit.box(Vector3(sx_r / float(n) * 0.9, 0.05, 0.08), 0.015), ObjKit.xf(Vector3(tx, ry + float(k) * 0.085 + 0.07, -0.06 + sz_r * 0.5 - 0.03))])
		var nz := int(sz_r / 0.16)
		for t in range(nz):
			var tz := -sz_r * 0.5 + (float(t) + 0.5) * (sz_r / float(nz))
			tiles.append([ObjKit.box(Vector3(0.08, 0.05, sz_r / float(nz) * 0.9), 0.015), ObjKit.xf(Vector3(sx_r * 0.5 - 0.03, ry + float(k) * 0.085 + 0.07, -0.06 + tz))])
		ObjKit.add_merged(root, "RoofTiles_%d" % k, tiles, mat_roof)
	var lan_y := ry + 5.0 * 0.085
	MeshKit.add_part(root, "Lantern", ObjKit.box(Vector3(0.40, 0.20, 0.40), 0.02), mat_ivory, Vector3(0.0, lan_y + 0.10, -0.06))
	for f in range(4):
		var ang := float(f) * 90.0
		var dir := Vector3(sin(deg_to_rad(ang)), 0.0, cos(deg_to_rad(ang)))
		MeshKit.add_part(root, "LanternGlow_%d" % f, ObjKit.box(Vector3(0.20, 0.09, 0.02), 0.004), mat_cyan,
			Vector3(0.0, lan_y + 0.11, -0.06) + dir * 0.205, Vector3(0.0, ang, 0.0))
	MeshKit.add_part(root, "LanternCap", ObjKit.box(Vector3(0.46, 0.06, 0.46), 0.015), mat_ivory_d, Vector3(0.0, lan_y + 0.23, -0.06))
	MeshKit.add_part(root, "LanternTop", ObjKit.box(Vector3(0.18, 0.06, 0.18), 0.012), mat_stone, Vector3(0.0, lan_y + 0.29, -0.06))

	# Front portico: 4 columns + entablature + emblem pediment
	var fz := 0.56
	for cx: float in [-0.64, -0.28, 0.28, 0.64]:
		MeshKit.add_part(root, "ColBase_%.0f" % (cx * 100.0), MeshKit.beveled_cylinder(0.09, 0.09, 0.05, 14, 0.01, true), mat_gold, Vector3(cx, body_y0 + 0.025, fz))
		MeshKit.add_part(root, "Column_%.0f" % (cx * 100.0), MeshKit.beveled_cylinder(0.065, 0.065, 0.66, 14, 0.0, true), mat_ivory, Vector3(cx, body_y0 + 0.38, fz))
		MeshKit.add_part(root, "ColCapital_%.0f" % (cx * 100.0), ObjKit.box(Vector3(0.18, 0.06, 0.18), 0.012), mat_gold, Vector3(cx, body_y0 + 0.74, fz))
	MeshKit.add_part(root, "Entablature", ObjKit.box(Vector3(1.50, 0.10, 0.22), 0.02), mat_ivory, Vector3(0.0, body_y0 + 0.82, fz - 0.02))
	MeshKit.add_part(root, "Pediment", ObjKit.box(Vector3(0.64, 0.26, 0.14), 0.03), mat_ivory, Vector3(0.0, cornice_y + 0.16, fz - 0.02))
	MeshKit.add_part(root, "EmblemPlate", ObjKit.box(Vector3(0.44, 0.18, 0.03), 0.01), mat_gold, Vector3(0.0, cornice_y + 0.16, fz + 0.06))
	MeshKit.add_part(root, "EmblemInner", ObjKit.box(Vector3(0.38, 0.13, 0.03), 0.008), mat_door, Vector3(0.0, cornice_y + 0.16, fz + 0.07))
	for sb: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "BookPage_%d" % int(sb), ObjKit.box(Vector3(0.10, 0.08, 0.02), 0.004), MeshKit.mat_color("obj_page", Color(0.98, 0.94, 0.84), 0.6),
			Vector3(sb * 0.055, cornice_y + 0.16, fz + 0.09), Vector3(0.0, 0.0, sb * -8.0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "PedimentGoldBlock_%d" % int(sx), ObjKit.box(Vector3(0.12, 0.12, 0.12), 0.015), mat_gold,
			Vector3(sx * 0.42, cornice_y + 0.10, fz))

	# Arched double door
	var door_g := ObjKit.group(root, "ArchedDoor", Vector3(0.0, body_y0, 0.52))
	MeshKit.add_part(door_g, "ArchSurround", ObjKit.box(Vector3(0.50, 0.62, 0.06), 0.02), mat_ivory_d, Vector3(0.0, 0.31, 0.0))
	MeshKit.add_part(door_g, "ArchTop", MeshKit.beveled_cylinder(0.25, 0.25, 0.06, 20, 0.01, true), mat_ivory_d, Vector3(0.0, 0.62, 0.0), Vector3(90.0, 0.0, 0.0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(door_g, "DoorLeaf_%d" % int(sx), ObjKit.box(Vector3(0.17, 0.56, 0.05), 0.01), mat_door, Vector3(sx * 0.088, 0.28, 0.025))
		MeshKit.add_part(door_g, "Handle_%d" % int(sx), ObjKit.box(Vector3(0.025, 0.10, 0.03), 0.006), mat_gold, Vector3(sx * 0.03, 0.30, 0.06))
	MeshKit.add_part(door_g, "DoorArchFill", MeshKit.beveled_cylinder(0.175, 0.175, 0.05, 20, 0.0, true), mat_door, Vector3(0.0, 0.56, 0.025), Vector3(90.0, 0.0, 0.0))

	# Windows (gold frames + blue lintels) on front and right side
	for wx: float in [-0.46, 0.46]:
		_classical_window(root, "WinFront_%.0f" % (wx * 100.0), Vector3(wx, body_y0 + 0.40, 0.52), 0.0, mat_gold, mat_glow, mat_roof)
	for wz: float in [-0.36, 0.14]:
		_classical_window(root, "WinSide_%.0f" % (wz * 100.0), Vector3(0.82, body_y0 + 0.40, wz), 90.0, mat_gold, mat_glow, mat_roof)

	# Front stairs with glowing posts
	for s in range(3):
		var sh := 0.087 * float(3 - s)
		MeshKit.add_part(root, "Step_%d" % s, ObjKit.box(Vector3(0.70, sh, 0.14), 0.012), mat_ivory_d, Vector3(0.0, sh * 0.5, 0.80 + float(s) * 0.13))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "StairPost_%d" % int(sx), ObjKit.box(Vector3(0.16, 0.24, 0.16), 0.02), mat_ivory, Vector3(sx * 0.46, 0.12, 0.98))
		MeshKit.add_part(root, "StairPostGlow_%d" % int(sx), ObjKit.box(Vector3(0.08, 0.08, 0.02), 0.004), mat_cyan, Vector3(sx * 0.46, 0.13, 1.065))
	return root

static func _classical_window(root: Node3D, wname: String, pos: Vector3, rot_y: float, gold: Material, glow: Material, lintel: Material) -> void:
	var g := ObjKit.window(root, wname, pos, rot_y, 0.16, 0.24, gold, glow, false, true)
	MeshKit.add_part(g, "BlueLintel", ObjKit.box(Vector3(0.28, 0.07, 0.08), 0.015), lintel, Vector3(0.0, 0.19, 0.02))
	MeshKit.add_part(g, "GoldSill", ObjKit.box(Vector3(0.26, 0.04, 0.08), 0.01), gold, Vector3(0.0, -0.16, 0.02))

# ----------------------------------------------------------------------------
# OBJ09 - Small square archive pavilion (library)
# ----------------------------------------------------------------------------
static func build_sql_library() -> Node3D:
	var root := Node3D.new()
	root.name = "SQLLibrary"

	var mat_stone := ObjKit.m_stone()
	var mat_ivory := ObjKit.m_ivory()
	var mat_ivory_d := ObjKit.m_ivory_dark()
	var mat_gold := ObjKit.m_gold()
	var mat_roof := ObjKit.m_blue_roof()
	var mat_roof_d := ObjKit.m_blue_roof_dark()
	var mat_glow := ObjKit.m_window_glow()
	var mat_cyan := ObjKit.m_cyan_glow()

	var hx := 0.50
	var hz := 0.46
	var plinth_h := 0.16
	var wall_top := 1.02
	var wall_h := wall_top - plinth_h

	MeshKit.add_part(root, "Plinth", ObjKit.box(Vector3(hx * 2.0 + 0.14, plinth_h, hz * 2.0 + 0.14), 0.02), mat_stone, Vector3(0.0, plinth_h * 0.5, 0.0))
	MeshKit.add_part(root, "Body", ObjKit.box(Vector3(hx * 2.0, wall_h, hz * 2.0), 0.015), mat_ivory, Vector3(0.0, plinth_h + wall_h * 0.5, 0.0))
	var joints: Array = []
	for j in range(4):
		joints.append([ObjKit.box(Vector3(hx * 2.0 + 0.01, 0.012, hz * 2.0 + 0.01), 0.002), ObjKit.xf(Vector3(0.0, plinth_h + 0.17 * float(j + 1), 0.0))])
	ObjKit.add_merged(root, "CourseJoints", joints, mat_ivory_d)

	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * hx, 0.0, sz * hz)
			MeshKit.add_part(root, "Pilaster_%d_%d" % [int(sx), int(sz)], ObjKit.box(Vector3(0.15, wall_h, 0.15), 0.02), mat_ivory, p + Vector3(0.0, plinth_h + wall_h * 0.5, 0.0))
			MeshKit.add_part(root, "GoldCap_%d_%d" % [int(sx), int(sz)], ObjKit.box(Vector3(0.19, 0.12, 0.19), 0.02), mat_gold, p + Vector3(0.0, wall_top + 0.04, 0.0))
			MeshKit.add_part(root, "PilasterBand_%d_%d" % [int(sx), int(sz)], ObjKit.box(Vector3(0.17, 0.04, 0.17), 0.008), mat_gold, p + Vector3(0.0, plinth_h + 0.36, 0.0))

	# Blue tiled gable roof (ridge along X) with ivory ribs + roof hatch frame
	ObjKit.gable_roof(root, "Roof", Vector3(0.0, wall_top, 0.0), 0.0, hx * 2.0, hz, 0.08, 0.80,
		mat_roof_d, mat_roof, 0.14, [-1, 1], mat_ivory, null)
	var rise := hz * 0.80
	var s := hz + 0.08
	var ang := rad_to_deg(atan2(s * 0.80, s))
	var slope_len := sqrt(s * s + (s * 0.80) * (s * 0.80))
	for side: float in [1.0, -1.0]:
		for rx: float in [-hx - 0.06, hx + 0.06]:
			MeshKit.add_part(root, "Rib_%d_%d" % [int(side), int(signf(rx))], ObjKit.box(Vector3(0.10, 0.10, slope_len), 0.02), mat_ivory,
				Vector3(rx, wall_top - 0.08 * 0.80 + s * 0.80 * 0.5 + 0.05, side * s * 0.5), Vector3(side * ang, 0.0, 0.0))
	# hatch frame on the front slope
	var hatch := ObjKit.group(root, "RoofHatch", Vector3(0.0, wall_top - 0.064 + rise * 0.55, s * 0.42), Vector3(ang, 0.0, 0.0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(hatch, "HatchSide_%d" % int(sx), ObjKit.box(Vector3(0.07, 0.07, 0.34), 0.015), mat_ivory, Vector3(sx * 0.22, 0.08, 0.0))
	for sz: float in [-1.0, 1.0]:
		MeshKit.add_part(hatch, "HatchEnd_%d" % int(sz), ObjKit.box(Vector3(0.50, 0.07, 0.07), 0.015), mat_ivory, Vector3(0.0, 0.08, sz * 0.17))
	MeshKit.add_part(root, "RidgeFinial", ObjKit.box(Vector3(0.16, 0.10, 0.16), 0.02), mat_ivory, Vector3(-hx - 0.04, wall_top + rise + 0.06, 0.0))

	# Arched entrance on the front (+Z) with gold keystone
	var dg := ObjKit.group(root, "Entrance", Vector3(0.0, plinth_h, hz))
	MeshKit.add_part(dg, "ArchFrame", ObjKit.box(Vector3(0.52, 0.50, 0.08), 0.02), mat_ivory_d, Vector3(0.0, 0.25, 0.01))
	MeshKit.add_part(dg, "ArchRound", MeshKit.beveled_cylinder(0.26, 0.26, 0.08, 22, 0.012, true), mat_ivory_d, Vector3(0.0, 0.50, 0.01), Vector3(90.0, 0.0, 0.0))
	MeshKit.add_part(dg, "Keystone", ObjKit.box(Vector3(0.10, 0.12, 0.06), 0.012), mat_gold, Vector3(0.0, 0.77, 0.05))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(dg, "Leaf_%d" % int(sx), ObjKit.box(Vector3(0.18, 0.48, 0.05), 0.01), ObjKit.m_timber_dark(), Vector3(sx * 0.092, 0.24, 0.04))
		MeshKit.add_part(dg, "Handle_%d" % int(sx), ObjKit.box(Vector3(0.025, 0.12, 0.03), 0.006), mat_gold, Vector3(sx * 0.03, 0.26, 0.075))
	MeshKit.add_part(dg, "LeafTop", MeshKit.beveled_cylinder(0.18, 0.18, 0.05, 20, 0.0, true), ObjKit.m_timber_dark(), Vector3(0.0, 0.48, 0.04), Vector3(90.0, 0.0, 0.0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "WallLight_%d" % int(sx), ObjKit.box(Vector3(0.06, 0.16, 0.02), 0.004), mat_cyan, Vector3(sx * 0.36, plinth_h + 0.30, hz + 0.01))

	# Big gold-framed window on the right side (+X) + gable window
	var wg := ObjKit.window(root, "SideWindow", Vector3(hx, plinth_h + 0.42, 0.02), 90.0, 0.34, 0.40, mat_gold, mat_glow, true, true)
	MeshKit.add_part(wg, "GoldHood", ObjKit.box(Vector3(0.48, 0.07, 0.12), 0.015), mat_gold, Vector3(0.0, 0.25, 0.03))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(wg, "StoneJamb_%d" % int(sx), ObjKit.box(Vector3(0.05, 0.42, 0.06), 0.01), ObjKit.m_stone_light(), Vector3(sx * 0.215, 0.0, 0.01))
	ObjKit.window(root, "GableWindow", Vector3(hx, wall_top + 0.14, 0.0), 90.0, 0.16, 0.12, mat_gold, mat_glow, false, true)

	# Front steps + gold-capped stone posts
	for s2 in range(2):
		var sh := 0.08 * float(2 - s2)
		MeshKit.add_part(root, "Step_%d" % s2, ObjKit.box(Vector3(0.50, sh, 0.15), 0.012), mat_stone, Vector3(0.0, sh * 0.5, hz + 0.14 + float(s2) * 0.14))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "StepPost_%d" % int(sx), ObjKit.box(Vector3(0.16, 0.22, 0.16), 0.02), mat_ivory, Vector3(sx * 0.36, 0.11, hz + 0.22))
		MeshKit.add_part(root, "StepPostGold_%d" % int(sx), ObjKit.box(Vector3(0.08, 0.08, 0.02), 0.006), mat_gold, Vector3(sx * 0.36, 0.12, hz + 0.305))
	return root

# ----------------------------------------------------------------------------
# OBJ10 - Square table platform with 4x4 blue/white tile grid
# ----------------------------------------------------------------------------
static func build_sql_table() -> Node3D:
	var root := Node3D.new()
	root.name = "SQLTable"

	var mat_ivory := ObjKit.m_ivory()
	var mat_ivory_d := ObjKit.m_ivory_dark()
	var mat_stone := ObjKit.m_stone()
	var mat_blue := MeshKit.mat_color("tbl_blue", Color(0.24, 0.50, 0.92), 0.22, 0.05)
	var mat_white := MeshKit.mat_color("tbl_white", Color(0.84, 0.85, 0.88), 0.30, 0.0)
	var mat_cyan := ObjKit.m_cyan_glow()
	var mat_wood := ObjKit.m_timber()

	var half := 0.78
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "Foot_%d_%d" % [int(sx), int(sz)], ObjKit.box(Vector3(0.26, 0.14, 0.26), 0.025), mat_stone, Vector3(sx * 0.58, 0.07, sz * 0.58))
	var body_y0 := 0.14
	var body_h := 0.30
	MeshKit.add_part(root, "Body", ObjKit.box(Vector3(half * 2.0 - 0.06, body_h, half * 2.0 - 0.06), 0.015), mat_ivory_d, Vector3(0.0, body_y0 + body_h * 0.5, 0.0))
	MeshKit.add_part(root, "BaseCourse", ObjKit.box(Vector3(half * 2.0, 0.06, half * 2.0), 0.015), mat_ivory, Vector3(0.0, body_y0 + 0.03, 0.0))

	# Side panels: glowing windows with wooden pilasters (all 4 sides)
	for f in range(4):
		var ang := float(f) * 90.0
		var g := ObjKit.group(root, "Side_%d" % f, Vector3.ZERO, Vector3(0.0, ang, 0.0))
		for i in range(4):
			var lx := -0.54 + float(i) * 0.36
			MeshKit.add_part(g, "Glow_%d" % i, ObjKit.box(Vector3(0.16, 0.13, 0.02), 0.004), mat_cyan, Vector3(lx, body_y0 + 0.16, half - 0.025))
			MeshKit.add_part(g, "GlowFrame_%d" % i, ObjKit.box(Vector3(0.22, 0.19, 0.02), 0.006), mat_ivory, Vector3(lx, body_y0 + 0.16, half - 0.04))
		for i in range(5):
			MeshKit.add_part(g, "WoodPilaster_%d" % i, ObjKit.box(Vector3(0.05, 0.22, 0.03), 0.006), mat_wood, Vector3(-0.72 + float(i) * 0.36, body_y0 + 0.16, half - 0.02))

	# Rim blocks on the top border + corner studs
	var top_y := body_y0 + body_h
	var rim: Array = []
	for f in range(4):
		var b := Basis(Vector3.UP, float(f) * PI * 0.5)
		for i in range(4):
			var lx := -0.585 + float(i) * 0.39
			rim.append([ObjKit.box(Vector3(0.38, 0.11, 0.17), 0.02), Transform3D(b, b * Vector3(lx, top_y + 0.055, half - 0.085))])
	ObjKit.add_merged(root, "RimBlocks", rim, mat_ivory)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "CornerBlock_%d_%d" % [int(sx), int(sz)], ObjKit.box(Vector3(0.19, 0.13, 0.19), 0.02), mat_ivory, Vector3(sx * (half - 0.09), top_y + 0.065, sz * (half - 0.09)))
			MeshKit.add_part(root, "CornerStud_%d_%d" % [int(sx), int(sz)], ObjKit.box(Vector3(0.08, 0.04, 0.08), 0.01), mat_stone, Vector3(sx * (half - 0.09), top_y + 0.15, sz * (half - 0.09)))

	# Inset 4x4 tile grid
	MeshKit.add_part(root, "GridBed", ObjKit.box(Vector3(1.24, 0.05, 1.24), 0.01), MeshKit.mat_color("tbl_bed", Color(0.18, 0.36, 0.78), 0.3), Vector3(0.0, top_y + 0.02, 0.0))
	var blues: Array = []
	var whites: Array = []
	var cell := 0.295
	for r in range(4):
		for c in range(4):
			var tx := (float(c) - 1.5) * cell
			var tz := (float(r) - 1.5) * cell
			var target := blues if (r + c) % 2 == 0 else whites
			target.append([ObjKit.box(Vector3(cell - 0.03, 0.05, cell - 0.03), 0.014), ObjKit.xf(Vector3(tx, top_y + 0.06, tz))])
	ObjKit.add_merged(root, "TilesBlue", blues, mat_blue)
	ObjKit.add_merged(root, "TilesWhite", whites, mat_white)
	return root

# ----------------------------------------------------------------------------
# OBJ11 - Y-shaped SQL query channel junction (2 inputs -> 1 output)
# ----------------------------------------------------------------------------
static func build_sql_query_y() -> Node3D:
	var root := Node3D.new()
	root.name = "SQLQueryY"

	var mat_base := ObjKit.m_stone()
	var mat_wall := ObjKit.m_ivory()
	var mat_wall_d := ObjKit.m_ivory_dark()
	var mat_floor := MeshKit.mat_color("qy_floor", Color(0.10, 0.30, 0.70), 0.3, 0.1)
	var mat_flow := MeshKit.mat_emissive("qy_flow", Color(0.25, 0.70, 1.0), Color(0.05, 0.50, 1.0), 1.4, 0.10)
	var mat_dash := ObjKit.m_cyan_glow()
	var mat_plate := MeshKit.mat_color("qy_plate", Color(0.92, 0.58, 0.22), 0.4, 0.35)
	var mat_iron := ObjKit.m_iron()

	var dirs: Array = [Vector2(0.0, 1.0), Vector2(-0.866, -0.5), Vector2(0.866, -0.5)]
	var hw := 0.20
	var L := 0.98
	var wt := 0.13
	var inner := ObjKit.arms_polygon(dirs, hw, L, 0.04)

	var base_poly := ObjKit._largest_poly(Geometry2D.offset_polygon(inner, wt + 0.03, Geometry2D.JOIN_MITER))
	MeshKit.add_part(root, "BaseSlab", MeshKit.extrude_polygon_xz(base_poly, 0.14, 2.0), mat_base, Vector3(0.0, 0.07, 0.0))
	MeshKit.add_part(root, "ChannelFloor", MeshKit.extrude_polygon_xz(inner, 0.05, 2.0), mat_floor, Vector3(0.0, 0.165, 0.0))
	var flow_poly := ObjKit._largest_poly(Geometry2D.offset_polygon(inner, -0.012, Geometry2D.JOIN_MITER))
	MeshKit.add_part(root, "FlowSurface", MeshKit.extrude_polygon_xz(flow_poly, 0.03, 2.0), mat_flow, Vector3(0.0, 0.205, 0.0))

	var wi := 0
	for wp: PackedVector2Array in ObjKit.arm_walls(dirs, hw, L, wt, 0.04):
		MeshKit.add_part(root, "Wall_%d" % wi, MeshKit.extrude_polygon_xz(wp, 0.26, 2.0), mat_wall, Vector3(0.0, 0.27, 0.0))
		wi += 1

	for ai in range(dirs.size()):
		var d: Vector2 = dirs[ai]
		var p := Vector2(-d.y, d.x)
		var yaw := -rad_to_deg(atan2(d.y, d.x))
		# glowing dashes down the center line
		var dashes: Array = []
		for k in range(3):
			var c := d * (0.38 + float(k) * 0.20)
			dashes.append([ObjKit.box(Vector3(0.11, 0.015, 0.045), 0.004), ObjKit.xf(Vector3(c.x, 0.225, c.y), Vector3(0.0, yaw, 0.0))])
		ObjKit.add_merged(root, "FlowDashes_%d" % ai, dashes, mat_dash)
		# end cap blocks with iron studs
		for sgn: float in [-1.0, 1.0]:
			var e := d * (L - 0.07) + p * sgn * (hw + wt * 0.5)
			MeshKit.add_part(root, "EndCap_%d_%d" % [ai, int(sgn)], ObjKit.box(Vector3(0.17, 0.08, 0.17), 0.02), mat_wall_d, Vector3(e.x, 0.44, e.y), Vector3(0.0, yaw, 0.0))
			MeshKit.add_part(root, "EndStud_%d_%d" % [ai, int(sgn)], ObjKit.box(Vector3(0.07, 0.04, 0.07), 0.01), mat_iron, Vector3(e.x, 0.50, e.y), Vector3(0.0, yaw, 0.0))
		# orange bolted plate on one outer wall
		var side := 1.0 if ai != 0 else -1.0
		var pp := d * (L * 0.55) + p * side * (hw + wt + 0.012)
		var plate_g := ObjKit.group(root, "SidePlate_%d" % ai, Vector3(pp.x, 0.30, pp.y), Vector3(0.0, yaw, 0.0))
		MeshKit.add_part(plate_g, "Plate", ObjKit.box(Vector3(0.24, 0.12, 0.02), 0.008), mat_plate, Vector3.ZERO, Vector3(0.0, 0.0, 0.0), Vector3.ONE)
		for bx: float in [-0.09, 0.09]:
			MeshKit.add_part(plate_g, "Bolt_%d" % int(bx * 100.0), ObjKit.box(Vector3(0.025, 0.025, 0.03), 0.006), mat_iron, Vector3(bx, 0.0, 0.0))
	# output portal lintel over the +Z arm end
	MeshKit.add_part(root, "OutputLintel", ObjKit.box(Vector3(hw * 2.0 + wt * 2.0, 0.10, 0.14), 0.02), mat_wall, Vector3(0.0, 0.45, L - 0.07))
	# glowing corner lamps between the arms
	for bis_deg: float in [30.0, 150.0, 270.0]:
		var bd := Vector2(cos(deg_to_rad(bis_deg)), sin(deg_to_rad(bis_deg)))
		var bp := bd * ((hw + wt * 0.55) / 0.866)
		var yaw2 := 90.0 - bis_deg
		MeshKit.add_part(root, "CornerPillar_%d" % int(bis_deg), ObjKit.box(Vector3(0.18, 0.30, 0.18), 0.02), mat_wall_d, Vector3(bp.x, 0.29, bp.y), Vector3(0.0, yaw2, 0.0))
		var gp := bp + bd * 0.092
		MeshKit.add_part(root, "CornerLamp_%d" % int(bis_deg), ObjKit.box(Vector3(0.09, 0.11, 0.02), 0.004), mat_dash, Vector3(gp.x, 0.30, gp.y), Vector3(0.0, yaw2, 0.0))
	return root

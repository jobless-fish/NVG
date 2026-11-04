class_name WorldTerrain
extends RefCounted

## Block-built island terrain for the NODEVERSE connected-island world map
## (reference: reference/NODEVERSE_연결섬_전체지도.png).
## Islands are grids of 1m cells: grass top + earth body + gray rock skirt at the waterline,
## merged into a handful of meshes so the whole map stays light.

const CELL: float = 1.0
const BOTTOM_Y: float = -1.1

## island: {"center": Vector2, "rx": float, "rz": float, "rects": Array[Rect2], "seed": int}
static func island_cells(island: Dictionary) -> Dictionary:
	var c: Vector2 = island["center"]
	var rx: float = island["rx"]
	var rz: float = island["rz"]
	var seed_v: int = island.get("seed", 1)
	var rects: Array = island.get("rects", [])
	var cells: Dictionary = {}
	var x0 := int(floor(c.x - rx - 1.0))
	var x1 := int(ceil(c.x + rx + 1.0))
	var z0 := int(floor(c.y - rz - 1.0))
	var z1 := int(ceil(c.y + rz + 1.0))
	for r: Rect2 in rects:
		x0 = mini(x0, int(floor(r.position.x)))
		x1 = maxi(x1, int(ceil(r.end.x)))
		z0 = mini(z0, int(floor(r.position.y)))
		z1 = maxi(z1, int(ceil(r.end.y)))
	for ix in range(x0, x1 + 1):
		for iz in range(z0, z1 + 1):
			var p := Vector2(float(ix) + 0.5, float(iz) + 0.5)
			var d := Vector2((p.x - c.x) / rx, (p.y - c.y) / rz)
			var jitter := (MeshKit._hash_float(ix, iz, seed_v) - 0.5) * 0.22
			var inside := d.length_squared() <= 1.0 + jitter
			for r: Rect2 in rects:
				if r.has_point(p):
					inside = true
			if inside:
				cells[Vector2i(ix, iz)] = true
	return cells

static func build_island(parent: Node3D, iname: String, cells: Dictionary, top_y: float, seed_v: int = 1) -> Node3D:
	var root := Node3D.new()
	root.name = iname
	parent.add_child(root)

	var mat_grass_a := MeshKit.mat_color("isl_grass_a", Color(0.80, 0.90, 0.74), 0.85, 0.0, "grass_top")
	var mat_grass_b := MeshKit.mat_color("isl_grass_b", Color(0.70, 0.82, 0.64), 0.85, 0.0, "grass_top")
	var mat_earth := MeshKit.mat_color("isl_earth", Color(1.0, 0.95, 0.90), 0.85, 0.0, "earth_strata")
	var mat_rock := MeshKit.mat_color("isl_rock", Color(0.56, 0.56, 0.58), 0.82, 0.0)
	var mat_rock_d := MeshKit.mat_color("isl_rock_d", Color(0.44, 0.44, 0.47), 0.85, 0.0)
	var mat_stud := MeshKit.mat_color("isl_stud", Color(0.40, 0.66, 0.18), 0.6, 0.0)

	var grass_a: Array = []
	var grass_b: Array = []
	var earth: Array = []
	var rock: Array = []
	var rock_d: Array = []
	var studs: Array = []
	var grass_h := 0.22
	var top_box := ObjKit.box(Vector3(CELL * 0.985, grass_h, CELL * 0.985), 0.03)
	var stud_mesh := MeshKit.lego_stud(0.09, 0.05, 12)
	var earth_h := top_y - grass_h - BOTTOM_Y
	var earth_box := ObjKit.box(Vector3(CELL * 0.97, earth_h, CELL * 0.97), 0.02)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	for key: Vector2i in cells.keys():
		var cx := float(key.x) + 0.5
		var cz := float(key.y) + 0.5
		var h := MeshKit._hash_float(key.x, key.y, seed_v + 11)
		var target := grass_a if h > 0.3 else grass_b
		target.append([top_box, ObjKit.xf(Vector3(cx, top_y - grass_h * 0.5, cz))])
		if MeshKit._hash_float(key.x, key.y, seed_v + 23) > 0.86:
			for q in range(4):
				studs.append([stud_mesh, ObjKit.xf(Vector3(cx + (float(q % 2) - 0.5) * 0.5, top_y, cz + (float(q / 2) - 0.5) * 0.5))])
		var edge := false
		for d: Vector2i in dirs:
			if not cells.has(key + d):
				edge = true
				# rocky skirt block pushed outward
				var out := Vector3(float(d.x), 0.0, float(d.y))
				var rh := 0.45 + MeshKit._hash_float(key.x * 3 + d.x, key.y * 3 + d.y, seed_v + 41) * 0.75
				var rw := 0.55 + MeshKit._hash_float(key.x, key.y * 7 + d.x, seed_v + 5) * 0.35
				var rp := Vector3(cx, BOTTOM_Y + 0.4 + rh * 0.5, cz) + out * 0.42
				var tgt := rock if (key.x + key.y) % 2 == 0 else rock_d
				tgt.append([ObjKit.box(Vector3(rw, rh, rw), 0.05), ObjKit.xf(rp, Vector3(0.0, h * 40.0, 0.0))])
		if edge:
			earth.append([earth_box, ObjKit.xf(Vector3(cx, BOTTOM_Y + earth_h * 0.5, cz))])

	ObjKit.add_merged(root, "GrassA", grass_a, mat_grass_a)
	ObjKit.add_merged(root, "GrassB", grass_b, mat_grass_b)
	ObjKit.add_merged(root, "Earth", earth, mat_earth)
	ObjKit.add_merged(root, "RockSkirt", rock, mat_rock)
	ObjKit.add_merged(root, "RockSkirtDark", rock_d, mat_rock_d)
	ObjKit.add_merged(root, "Studs", studs, mat_stud)

	# Collision: one box per contiguous run of cells in each row
	var body := StaticBody3D.new()
	body.name = "Ground"
	root.add_child(body)
	var rows: Dictionary = {}
	for key: Vector2i in cells.keys():
		if not rows.has(key.y):
			rows[key.y] = []
		(rows[key.y] as Array).append(key.x)
	for zr: int in rows.keys():
		var xs: Array = rows[zr]
		xs.sort()
		var start: int = xs[0]
		var prev: int = xs[0]
		for i in range(1, xs.size() + 1):
			var cur: int = xs[i] if i < xs.size() else 999999
			if cur != prev + 1:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				var w := float(prev - start + 1)
				bs.size = Vector3(w, 1.0, 1.0)
				cs.shape = bs
				cs.position = Vector3(float(start) + w * 0.5, top_y - 0.5, float(zr) + 0.5)
				body.add_child(cs)
				start = cur
			prev = cur
	return root

## Tan paving tiles along a polyline (merged), laid on top of the grass.
static func paving(parent: Node3D, pname: String, points: Array, width: float, top_y: float, mat: Material = null) -> void:
	if mat == null:
		mat = MeshKit.mat_color("path_tan", Color(1.0, 0.86, 0.66), 0.82, 0.0, "stone_ashlar")
	var items: Array = []
	var tile := 0.48
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := b - a
		var L := seg.length()
		if L < 0.01:
			continue
		var d := seg / L
		var p := Vector2(-d.y, d.x)
		var yaw := -rad_to_deg(atan2(d.y, d.x))
		var n_along := int(ceil(L / tile))
		var n_across := maxi(int(round(width / tile)), 1)
		for k in range(n_along + 1):
			for j in range(n_across):
				var off := (float(j) - float(n_across - 1) * 0.5) * tile
				var stagger := tile * 0.5 if j % 2 == 1 else 0.0
				var t := minf(float(k) * tile + stagger, L)
				var c := a + d * t + p * off
				items.append([ObjKit.box(Vector3(tile * 0.94, 0.05, tile * 0.94), 0.012), ObjKit.xf(Vector3(c.x, top_y + 0.02, c.y), Vector3(0.0, yaw, 0.0))])
	ObjKit.add_merged(parent, pname, items, mat)

## Long stone arch bridge between two ground points (deck top at deck_y). Includes collision.
static func arch_bridge(parent: Node3D, bname: String, a: Vector2, b: Vector2, width: float, deck_y: float) -> Node3D:
	var root := Node3D.new()
	root.name = bname
	parent.add_child(root)
	var seg := b - a
	var L := seg.length()
	var mid := (a + b) * 0.5
	root.position = Vector3(mid.x, 0.0, mid.y)
	root.rotation_degrees = Vector3(0.0, -rad_to_deg(atan2(seg.y, seg.x)), 0.0)

	var mat_stone := MeshKit.mat_color("bridge_stone", Color(0.80, 0.78, 0.76), 0.75, 0.0, "stone_ashlar")
	var mat_deck := MeshKit.mat_color("bridge_deck", Color(1.0, 0.88, 0.70), 0.8, 0.0, "stone_ashlar")
	var mat_cap := MeshKit.mat_color("bridge_cap", Color(0.62, 0.60, 0.58), 0.75, 0.0)
	var mat_lamp := MeshKit.mat_emissive("bridge_lamp", Color(0.45, 0.92, 1.0), Color(0.2, 0.8, 1.0), 2.0, 0.2)

	var base_y := BOTTOM_Y
	var h := deck_y - 0.06 - base_y
	var span := MeshKit.arch_span_mesh(L, h, width, L * 0.5 - 0.7, 1.0, h - 0.22, 32, 1.4)
	MeshKit.add_part(root, "Arch", span, mat_stone, Vector3(0.0, base_y, 0.0))
	MeshKit.add_part(root, "Deck", ObjKit.box(Vector3(L, 0.08, width - 0.1), 0.01), mat_deck, Vector3(0.0, deck_y - 0.04, 0.0))
	# parapets made of blocks + caps
	var blocks: Array = []
	var caps: Array = []
	var n := int(L / 0.6)
	for sz: float in [-1.0, 1.0]:
		for i in range(n):
			var x := -L * 0.5 + (float(i) + 0.5) * (L / float(n))
			blocks.append([ObjKit.box(Vector3(L / float(n) * 0.96, 0.26, 0.16), 0.02), ObjKit.xf(Vector3(x, deck_y + 0.13, sz * (width * 0.5 - 0.08)))])
		caps.append([ObjKit.box(Vector3(L, 0.06, 0.2), 0.015), ObjKit.xf(Vector3(0.0, deck_y + 0.29, sz * (width * 0.5 - 0.08)))])
		for ex: float in [-1.0, 1.0]:
			MeshKit.add_part(root, "Pillar_%d_%d" % [int(sz), int(ex)], ObjKit.box(Vector3(0.28, 0.5, 0.28), 0.03), mat_cap, Vector3(ex * (L * 0.5 - 0.14), deck_y + 0.25, sz * (width * 0.5 - 0.08)))
			MeshKit.add_part(root, "PillarLamp_%d_%d" % [int(sz), int(ex)], ObjKit.box(Vector3(0.14, 0.12, 0.14), 0.02), mat_lamp, Vector3(ex * (L * 0.5 - 0.14), deck_y + 0.56, sz * (width * 0.5 - 0.08)))
	ObjKit.add_merged(root, "Parapets", blocks, mat_stone)
	ObjKit.add_merged(root, "ParapetCaps", caps, mat_cap)

	var body := StaticBody3D.new()
	root.add_child(body)
	for spec: Array in [[Vector3(L + 0.6, 0.6, width - 0.3), Vector3(0.0, deck_y - 0.3, 0.0)],
			[Vector3(L, 0.8, 0.16), Vector3(0.0, deck_y + 0.4, width * 0.5 - 0.08)],
			[Vector3(L, 0.8, 0.16), Vector3(0.0, deck_y + 0.4, -(width * 0.5 - 0.08))]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[0]
		cs.shape = bs
		cs.position = spec[1]
		body.add_child(cs)
	return root

## Wooden pier jutting into the sea (deck top at deck_y), with posts and collision.
static func pier(parent: Node3D, pname: String, center: Vector2, size: Vector2, deck_y: float, rot_y: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = pname
	root.position = Vector3(center.x, 0.0, center.y)
	root.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	parent.add_child(root)
	var mat_plank := MeshKit.mat_color("pier_plank", Color(0.98, 0.90, 0.80), 0.6, 0.0, "wood_oak")
	var mat_post := MeshKit.mat_color("pier_post", Color(0.88, 0.80, 0.72), 0.65, 0.0, "wood_brown")
	var planks: Array = []
	var n := int(size.x / 0.22)
	for i in range(n):
		var x := -size.x * 0.5 + (float(i) + 0.5) * (size.x / float(n))
		planks.append([ObjKit.box(Vector3(size.x / float(n) * 0.94, 0.08, size.y), 0.012), ObjKit.xf(Vector3(x, deck_y - 0.04, 0.0))])
	ObjKit.add_merged(root, "Planks", planks, mat_plank)
	var posts: Array = []
	for sx: float in [-1.0, 1.0]:
		for k in range(3):
			var z := lerpf(-size.y * 0.5 + 0.1, size.y * 0.5 - 0.1, float(k) / 2.0)
			posts.append([ObjKit.box(Vector3(0.18, deck_y - BOTTOM_Y + 0.25, 0.18), 0.02), ObjKit.xf(Vector3(sx * (size.x * 0.5 - 0.05), (deck_y + 0.25 + BOTTOM_Y) * 0.5, z))])
	ObjKit.add_merged(root, "Posts", posts, mat_post)
	var body := StaticBody3D.new()
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, 0.5, size.y)
	cs.shape = bs
	cs.position = Vector3(0.0, deck_y - 0.25, 0.0)
	body.add_child(cs)
	return root

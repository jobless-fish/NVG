class_name ObjKit
extends RefCounted

## Shared helpers for the OBJ01-OBJ20 builders (NODEVERSE connected-island objects).
## Extends MeshKit with: merged meshes, XY prisms, gable roofs with block tiles,
## windows/doors, ring placement, Y-junction channels and Korean 3D text.

static var _font_cache: Dictionary = {}

# ============================================================================
# BASIC HELPERS
# ============================================================================

static func group(parent: Node3D, gname: String, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Node3D:
	var g := Node3D.new()
	g.name = gname
	g.position = pos
	g.rotation_degrees = rot_deg
	g.scale = scl
	parent.add_child(g)
	return g

static func box(size: Vector3, bevel: float = 0.012) -> ArrayMesh:
	return MeshKit.beveled_box(size, bevel, 1, false)

static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(scl)
	return Transform3D(b, pos)

## Merges [[mesh, Transform3D], ...] into one ArrayMesh (single surface)
static func combine(items: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for it: Array in items:
		var m: Mesh = it[0]
		var t: Transform3D = it[1]
		for s in range(m.get_surface_count()):
			st.append_from(m, s, t)
	return st.commit()

static func transformed(mesh: Mesh, t: Transform3D) -> ArrayMesh:
	return combine([[mesh, t]])

## Adds a merged mesh part if there is anything to merge
static func add_merged(parent: Node3D, part_name: String, items: Array, mat: Material) -> MeshInstance3D:
	if items.is_empty():
		return null
	return MeshKit.add_part(parent, part_name, combine(items), mat)

## Profile in XY plane (x right, y up), extruded along Z, centered on Z=0
static func prism_xy(profile: PackedVector2Array, depth: float, uv_scale: float = 1.0) -> ArrayMesh:
	var flipped := PackedVector2Array()
	for p in profile:
		flipped.append(Vector2(p.x, -p.y))
	var raw := MeshKit.extrude_polygon_xz(flipped, depth, uv_scale)
	return transformed(raw, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))

## Faceted crystal: n-gon prism with pointed top (and optional short bottom point), base at Y=0
static func crystal_mesh(radius: float, body_h: float, tip_h: float, sides: int = 6, bottom_tip: float = 0.0) -> ArrayMesh:
	var items: Array = []
	var body := MeshKit.beveled_cylinder(radius, radius, body_h, sides, 0.0, false)
	items.append([body, xf(Vector3(0.0, bottom_tip + body_h * 0.5, 0.0))])
	var tip := MeshKit.beveled_cylinder(radius, 0.002, tip_h, sides, 0.0, false)
	items.append([tip, xf(Vector3(0.0, bottom_tip + body_h + tip_h * 0.5, 0.0))])
	if bottom_tip > 0.0:
		var btip := MeshKit.beveled_cylinder(0.002, radius, bottom_tip, sides, 0.0, false)
		items.append([btip, xf(Vector3(0.0, bottom_tip * 0.5, 0.0))])
	return combine(items)

# ============================================================================
# MATERIAL PALETTE (sampled from the OBJ reference PNGs)
# ============================================================================

static func m_cream() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_cream", Color(0.86, 0.76, 0.58), 0.80, 0.0)

static func m_ivory() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_ivory", Color(0.82, 0.76, 0.62), 0.66, 0.0)

static func m_ivory_dark() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_ivory_d", Color(0.70, 0.64, 0.52), 0.72, 0.0)

static func m_timber() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_timber", Color(1.0, 0.80, 0.64), 0.62, 0.0, "wood_oak")

static func m_timber_dark() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_timber_d", Color(0.95, 0.80, 0.70), 0.66, 0.0, "wood_brown")

static func m_wood_light() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_wood_l", Color(1.0, 0.92, 0.80), 0.60, 0.0, "wood_oak")

static func m_wood_dark() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_wood_d", Color(0.92, 0.82, 0.76), 0.70, 0.0, "wood_dark")

static func m_blue_roof() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_blue_roof", Color(0.20, 0.32, 0.80), 0.34, 0.05)

static func m_blue_roof_dark() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_blue_roof_d", Color(0.15, 0.24, 0.62), 0.40, 0.05)

static func m_stone() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_stone", Color(0.46, 0.46, 0.49), 0.80, 0.02)

static func m_stone_light() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_stone_l", Color(0.58, 0.57, 0.57), 0.76, 0.02)

static func m_stone_dark() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_stone_d", Color(0.34, 0.34, 0.37), 0.84, 0.02)

static func m_brick() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_brick", Color(0.80, 0.45, 0.24), 0.70, 0.0)

static func m_gold() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_gold", Color(0.96, 0.74, 0.26), 0.32, 0.55)

static func m_iron() -> StandardMaterial3D:
	return MeshKit.mat_color("obj_iron", Color(0.55, 0.57, 0.60), 0.38, 0.65)

static func m_window_glow() -> StandardMaterial3D:
	return MeshKit.mat_emissive("obj_win_glow", Color(1.0, 0.80, 0.38), Color(1.0, 0.62, 0.16), 1.9, 0.30)

static func m_cyan_glow() -> StandardMaterial3D:
	return MeshKit.mat_emissive("obj_cyan", Color(0.30, 0.90, 1.0), Color(0.10, 0.72, 1.0), 2.3, 0.18)

static func m_blue_glow() -> StandardMaterial3D:
	return MeshKit.mat_emissive("obj_blue_glow", Color(0.16, 0.42, 0.95), Color(0.08, 0.36, 1.0), 1.4, 0.22)

static func m_crystal() -> StandardMaterial3D:
	var key := "obj_crystal"
	var m := MeshKit.mat_emissive(key, Color(0.36, 0.74, 1.0), Color(0.12, 0.52, 1.0), 1.25, 0.08)
	m.metallic = 0.15
	m.metallic_specular = 0.9
	return m

# ============================================================================
# ARCHITECTURE PIECES
# ============================================================================

## Gable roof whose ridge runs along local X.
## `center` = roof center at WALL-TOP height. Walls are 2*half_depth deep (local Z) and length_x long.
## Returns the local ridge height above wall top.
static func gable_roof(
	parent: Node3D,
	rname: String,
	center: Vector3,
	rot_y: float,
	length_x: float,
	half_depth: float,
	overhang: float,
	pitch: float,
	slab_mat: Material,
	tile_mat: Material,
	tile_size: float = 0.15,
	gable_ends: Array = [],
	gable_mat: Material = null,
	end_caps_mat: Material = null
) -> float:
	var g := group(parent, rname, center, Vector3(0.0, rot_y, 0.0))
	var s := half_depth + overhang
	var rise := s * pitch
	var eave := -overhang * pitch
	var slope_len := sqrt(s * s + rise * rise)
	var ang := rad_to_deg(atan2(rise, s))
	var roof_len := length_x + overhang * 2.0
	var slab_t := 0.05

	var slab_items: Array = []
	var tile_items: Array = []
	var rows := maxi(int(round(slope_len / tile_size)), 2)
	var cols := maxi(int(round(roof_len / tile_size)), 2)
	var tw := roof_len / float(cols)
	var tl := slope_len / float(rows)
	for side: float in [1.0, -1.0]:
		var slope_xf := xf(Vector3(0.0, eave + rise * 0.5, side * s * 0.5), Vector3(side * ang, 0.0, 0.0))
		slab_items.append([box(Vector3(roof_len, slab_t, slope_len + 0.02), 0.008), slope_xf])
		for r in range(rows):
			var lz := -slope_len * 0.5 + (float(r) + 0.5) * tl
			var stagger := (tw * 0.5) if (r % 2 == 1) else 0.0
			var c_count := cols if stagger == 0.0 else cols - 1
			for c in range(c_count):
				var lx := -roof_len * 0.5 + (float(c) + 0.5) * tw + stagger
				var tile_xf := slope_xf * xf(Vector3(lx, slab_t * 0.5 + 0.03, lz * side), Vector3(-side * 4.0, 0.0, 0.0))
				tile_items.append([box(Vector3(tw * 0.93, 0.06, tl * 1.04), 0.016), tile_xf])
	add_merged(g, "RoofSlabs", slab_items, slab_mat)
	add_merged(g, "RoofTiles", tile_items, tile_mat)

	# Ridge cap
	MeshKit.add_part(g, "RidgeCap", box(Vector3(roof_len + 0.02, 0.08, 0.12), 0.02), tile_mat,
		Vector3(0.0, eave + rise + 0.05, 0.0))

	# Gable wall triangles (+X / -X ends)
	if gable_mat != null:
		var apex := half_depth * pitch
		var tri := PackedVector2Array([Vector2(-half_depth, 0.0), Vector2(half_depth, 0.0), Vector2(0.0, apex)])
		for e in gable_ends:
			var ex: float = float(e) * (length_x * 0.5 - 0.03)
			MeshKit.add_part(g, "Gable_%d" % int(e), transformed(prism_xy(tri, 0.06), xf(Vector3(ex, 0.0, 0.0), Vector3(0.0, 90.0, 0.0))), gable_mat)

	# Decorative wooden end blocks at ridge & eave corners (toy-block look)
	if end_caps_mat != null:
		for ex: float in [-1.0, 1.0]:
			MeshKit.add_part(g, "RidgeEnd_%d" % int(ex), box(Vector3(0.12, 0.12, 0.14), 0.02), end_caps_mat,
				Vector3(ex * (roof_len * 0.5 + 0.02), eave + rise + 0.04, 0.0))
			for ez: float in [-1.0, 1.0]:
				MeshKit.add_part(g, "EaveEnd_%d_%d" % [int(ex), int(ez)], box(Vector3(0.10, 0.10, 0.10), 0.02), end_caps_mat,
					Vector3(ex * (roof_len * 0.5 + 0.01), eave + 0.02, ez * (s - 0.02)))
	return half_depth * pitch

## Glowing window. `pos` is the wall-surface point, window faces local +Z after rot_y.
static func window(parent: Node3D, wname: String, pos: Vector3, rot_y: float, w: float, h: float, frame_mat: Material, glow_mat: Material, sill: bool = true, cross: bool = true) -> Node3D:
	var g := group(parent, wname, pos, Vector3(0.0, rot_y, 0.0))
	MeshKit.add_part(g, "Frame", box(Vector3(w + 0.07, h + 0.07, 0.05), 0.012), frame_mat, Vector3(0.0, 0.0, 0.0))
	MeshKit.add_part(g, "Pane", box(Vector3(w, h, 0.03), 0.004), glow_mat, Vector3(0.0, 0.0, 0.015))
	if cross:
		MeshKit.add_part(g, "MullionV", box(Vector3(0.025, h, 0.07), 0.006), frame_mat, Vector3(0.0, 0.0, 0.0))
		MeshKit.add_part(g, "MullionH", box(Vector3(w, 0.025, 0.07), 0.006), frame_mat, Vector3(0.0, 0.0, 0.0))
	if sill:
		MeshKit.add_part(g, "Sill", box(Vector3(w + 0.13, 0.045, 0.10), 0.012), frame_mat, Vector3(0.0, -h * 0.5 - 0.05, 0.03))
	return g

## Plank door. `pos` = bottom-center on the wall surface, faces local +Z after rot_y.
static func door(parent: Node3D, dname: String, pos: Vector3, rot_y: float, w: float, h: float, wood_mat: Material, frame_mat: Material, knob_mat: Material, glow_mat: Material = null) -> Node3D:
	var g := group(parent, dname, pos, Vector3(0.0, rot_y, 0.0))
	var pw := w / 3.0
	for i in range(3):
		MeshKit.add_part(g, "Plank_%d" % i, box(Vector3(pw * 0.95, h, 0.05), 0.008), wood_mat,
			Vector3(-w * 0.5 + pw * (float(i) + 0.5), h * 0.5, 0.0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(g, "Jamb_%d" % int(sx), box(Vector3(0.06, h + 0.06, 0.08), 0.012), frame_mat,
			Vector3(sx * (w * 0.5 + 0.03), (h + 0.06) * 0.5, 0.01))
	MeshKit.add_part(g, "Lintel", box(Vector3(w + 0.14, 0.07, 0.09), 0.014), frame_mat, Vector3(0.0, h + 0.035, 0.015))
	MeshKit.add_part(g, "Knob", box(Vector3(0.04, 0.05, 0.04), 0.008), knob_mat, Vector3(w * 0.30, h * 0.45, 0.04))
	if glow_mat != null:
		window(g, "DoorWindow", Vector3(0.0, h * 0.72, 0.03), 0.0, w * 0.48, h * 0.24, wood_mat, glow_mat, false, true)
	return g

## Places `count` boxes around a ring. Box local X = radial, local Z = tangent.
static func ring_items(items: Array, count: int, radius: float, y: float, radial_w: float, h: float, gap: float = 0.94, angle_offset: float = 0.0, bevel: float = 0.012) -> void:
	var arc := TAU * radius / float(count)
	var m := box(Vector3(radial_w, h, arc * gap), bevel)
	for i in range(count):
		var th := angle_offset + TAU * float(i) / float(count)
		items.append([m, xf(Vector3(cos(th) * radius, y, sin(th) * radius), Vector3(0.0, -rad_to_deg(th), 0.0))])

# ============================================================================
# Y-JUNCTION CHANNEL / PATH POLYGONS
# ============================================================================

static func _largest_poly(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_a := -1.0
	for p: PackedVector2Array in polys:
		var a := 0.0
		for i in range(p.size()):
			var q0 := p[i]
			var q1 := p[(i + 1) % p.size()]
			a += q0.x * q1.y - q1.x * q0.y
		if absf(a) > best_a:
			best_a = absf(a)
			best = p
	return best

## Union of arm rectangles from the origin. dirs are unit Vector2 in (x, z).
static func arms_polygon(dirs: Array, half_w: float, length: float, concave_round: float = 0.0) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for d: Vector2 in dirs:
		var p := Vector2(-d.y, d.x)
		var rect := PackedVector2Array([-p * half_w - d * 0.001, -p * half_w + d * length, p * half_w + d * length, p * half_w - d * 0.001])
		if poly.is_empty():
			poly = rect
		else:
			poly = _largest_poly(Geometry2D.merge_polygons(poly, rect))
	if concave_round > 0.0:
		var grown := _largest_poly(Geometry2D.offset_polygon(poly, concave_round, Geometry2D.JOIN_ROUND))
		poly = _largest_poly(Geometry2D.offset_polygon(grown, -concave_round, Geometry2D.JOIN_MITER))
	return poly

## Wall pieces around the arms polygon with open ends (returns list of simple polygons)
static func arm_walls(dirs: Array, half_w: float, length: float, wall_t: float, concave_round: float = 0.0) -> Array:
	var inner_ext := arms_polygon(dirs, half_w, length + wall_t * 3.0, concave_round)
	var inner := arms_polygon(dirs, half_w, length, concave_round)
	var outer := _largest_poly(Geometry2D.offset_polygon(inner, wall_t, Geometry2D.JOIN_MITER))
	var pieces: Array = []
	for p: PackedVector2Array in Geometry2D.clip_polygons(outer, inner_ext):
		if p.size() >= 3:
			pieces.append(p)
	return pieces

# ============================================================================
# 3D TEXT (Korean capable)
# ============================================================================

static func korean_font() -> Font:
	if _font_cache.has("kr"):
		return _font_cache["kr"]
	var candidates := [
		"C:/Windows/Fonts/malgunbd.ttf",
		"C:/Windows/Fonts/malgun.ttf",
		"/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf",
		"/System/Library/Fonts/AppleSDGothicNeo.ttc"
	]
	var f: Font = null
	for path: String in candidates:
		if FileAccess.file_exists(path):
			var ff := FontFile.new()
			if ff.load_dynamic_font(path) == OK:
				f = ff
				break
	if f == null:
		push_warning("Korean font not found - falling back to default font")
		f = ThemeDB.fallback_font
	_font_cache["kr"] = f
	return f

static func text_width(txt: String, font_px: int) -> float:
	return korean_font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x

static func text_mesh_kr(txt: String, font_px: int, pixel_size: float, depth: float) -> ArrayMesh:
	var tm := TextMesh.new()
	tm.font = korean_font()
	tm.text = txt
	tm.font_size = font_px
	tm.pixel_size = pixel_size
	tm.depth = depth
	tm.curve_step = 0.5
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return MeshKit.prim_to_array_mesh(tm)

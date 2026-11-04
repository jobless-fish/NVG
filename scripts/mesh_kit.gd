class_name MeshKit
extends RefCounted

## Procedural 3D Mesh & PBR Material Toolkit for NODEVERSE 3D Assets

static var _tex_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}

static func clear_caches() -> void:
	_tex_cache.clear()
	_mat_cache.clear()

# ============================================================================
# NODE HIERARCHY & OWNERSHIP HELPERS
# ============================================================================

static func add_part(
	parent: Node3D,
	part_name: String,
	mesh: Mesh,
	mat: Material,
	pos: Vector3 = Vector3.ZERO,
	rot_deg: Vector3 = Vector3.ZERO,
	scale_vec: Vector3 = Vector3.ONE
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var m_copy: Mesh = mesh.duplicate()
	if m_copy is ArrayMesh and mat != null:
		var am := m_copy as ArrayMesh
		for s in range(am.get_surface_count()):
			am.surface_set_material(s, mat)
	elif m_copy is PrimitiveMesh and mat != null:
		(m_copy as PrimitiveMesh).material = mat
	mi.mesh = m_copy
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scale_vec
	parent.add_child(mi)
	return mi

static func add_light(
	parent: Node3D,
	light_name: String,
	color: Color,
	energy: float,
	omni_range: float,
	pos: Vector3
) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = light_name
	l.light_color = color
	l.light_energy = energy
	l.omni_range = omni_range
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)
	return l

static func set_owner_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		set_owner_recursive(child, root)

# ============================================================================
# GEOMETRY BUILDERS (Watertight ArrayMeshes with UVs, Normals, Tangents)
# ============================================================================

## Converts any PrimitiveMesh (e.g. TextMesh, SphereMesh, CylinderMesh) to ArrayMesh
static func prim_to_array_mesh(prim: PrimitiveMesh) -> ArrayMesh:
	var am := ArrayMesh.new()
	var arrays := prim.get_mesh_arrays()
	if arrays.size() > 0 and arrays[Mesh.ARRAY_VERTEX] != null and (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

## Rounded / Chamfered Box!
## segments = 1 -> crisp 45-degree chamfered edges (Lego/block diorama look)
## segments = 3 or 4 -> smooth rounded box (Robot head, torso, limbs)
static func beveled_box(
	size: Vector3,
	bevel: float = 0.025,
	segments: int = 1,
	smooth_normals: bool = false,
	uv_scale: float = 1.0
) -> ArrayMesh:
	var hx: float = maxf(size.x * 0.5, 0.001)
	var hy: float = maxf(size.y * 0.5, 0.001)
	var hz: float = maxf(size.z * 0.5, 0.001)
	var r: float = clampf(bevel, 0.0, minf(hx, minf(hy, hz)) * 0.95)
	var seg: int = maxi(segments, 1)

	if r <= 0.0001:
		var bm := BoxMesh.new()
		bm.size = size
		return prim_to_array_mesh(bm)

	var ix: float = hx - r
	var iy: float = hy - r
	var iz: float = hz - r

	var xs := _axis_stops(ix, r, seg)
	var ys := _axis_stops(iy, r, seg)
	var zs := _axis_stops(iz, r, seg)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 6 faces of the parameter cube, warped onto rounded/chamfered box
	# +Z face
	_emit_warped_patch(st, xs, ys, hz, 2, false, ix, iy, iz, r, smooth_normals, uv_scale)
	# -Z face
	_emit_warped_patch(st, xs, ys, -hz, 2, true, ix, iy, iz, r, smooth_normals, uv_scale)
	# +X face
	_emit_warped_patch(st, zs, ys, hx, 0, true, ix, iy, iz, r, smooth_normals, uv_scale)
	# -X face
	_emit_warped_patch(st, zs, ys, -hx, 0, false, ix, iy, iz, r, smooth_normals, uv_scale)
	# +Y face
	_emit_warped_patch(st, xs, zs, hy, 1, true, ix, iy, iz, r, smooth_normals, uv_scale)
	# -Y face
	_emit_warped_patch(st, xs, zs, -hy, 1, false, ix, iy, iz, r, smooth_normals, uv_scale)

	if not smooth_normals:
		st.generate_normals()
	st.generate_tangents()
	return st.commit()

static func _axis_stops(inner_half: float, r: float, seg: int) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for i in range(seg + 1):
		var t: float = float(i) / float(seg) # 0..1
		arr.append(-inner_half - r * (1.0 - t))
	for i in range(1, seg + 1):
		var t: float = float(i) / float(seg) # 0..1
		arr.append(inner_half + r * t)
	return arr

static func _warp_point(p: Vector3, ix: float, iy: float, iz: float, r: float) -> Array:
	var clamped := Vector3(
		clampf(p.x, -ix, ix),
		clampf(p.y, -iy, iy),
		clampf(p.z, -iz, iz)
	)
	var delta := p - clamped
	var dlen := delta.length()
	var n := Vector3.UP
	if dlen > 0.00001:
		n = delta / dlen
	return [clamped + n * r, n]

static func _emit_warped_patch(
	st: SurfaceTool,
	u_stops: PackedFloat32Array,
	v_stops: PackedFloat32Array,
	fixed_val: float,
	fixed_axis: int,
	flip_winding: bool,
	ix: float,
	iy: float,
	iz: float,
	r: float,
	smooth_normals: bool,
	uv_scale: float
) -> void:
	var nu := u_stops.size()
	var nv := v_stops.size()
	var pts: Array[Vector3] = []
	var nrms: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	pts.resize(nu * nv)
	nrms.resize(nu * nv)
	uvs.resize(nu * nv)

	for j in range(nv):
		for i in range(nu):
			var u := u_stops[i]
			var v := v_stops[j]
			var raw: Vector3
			if fixed_axis == 0:
				raw = Vector3(fixed_val, v, u)
			elif fixed_axis == 1:
				raw = Vector3(u, fixed_val, v)
			else:
				raw = Vector3(u, v, fixed_val)
			var res := _warp_point(raw, ix, iy, iz, r)
			var idx := j * nu + i
			var wp: Vector3 = res[0]
			pts[idx] = wp
			nrms[idx] = res[1]
			# Planar UV based on dominant face axis
			if fixed_axis == 0:
				uvs[idx] = Vector2(wp.z, -wp.y) * uv_scale + Vector2(0.5, 0.5)
			elif fixed_axis == 1:
				uvs[idx] = Vector2(wp.x, wp.z) * uv_scale + Vector2(0.5, 0.5)
			else:
				uvs[idx] = Vector2(wp.x, -wp.y) * uv_scale + Vector2(0.5, 0.5)

	for j in range(nv - 1):
		for i in range(nu - 1):
			var i00 := j * nu + i
			var i10 := j * nu + (i + 1)
			var i01 := (j + 1) * nu + i
			var i11 := (j + 1) * nu + (i + 1)
			if (pts[i00] - pts[i11]).length_squared() < 1e-10:
				continue
			if flip_winding:
				_add_tri(st, pts[i00], pts[i10], pts[i11], nrms[i00], nrms[i10], nrms[i11], uvs[i00], uvs[i10], uvs[i11], smooth_normals)
				_add_tri(st, pts[i00], pts[i11], pts[i01], nrms[i00], nrms[i11], nrms[i01], uvs[i00], uvs[i11], uvs[i01], smooth_normals)
			else:
				_add_tri(st, pts[i00], pts[i11], pts[i10], nrms[i00], nrms[i11], nrms[i10], uvs[i00], uvs[i11], uvs[i10], smooth_normals)
				_add_tri(st, pts[i00], pts[i01], pts[i11], nrms[i00], nrms[i01], nrms[i11], uvs[i00], uvs[i01], uvs[i11], smooth_normals)

static func _add_tri(
	st: SurfaceTool,
	p0: Vector3, p1: Vector3, p2: Vector3,
	n0: Vector3, n1: Vector3, n2: Vector3,
	uv0: Vector2, uv1: Vector2, uv2: Vector2,
	smooth: bool
) -> void:
	var area_vec := (p1 - p0).cross(p2 - p0)
	if area_vec.length_squared() < 1e-12:
		return
	if smooth:
		st.set_normal(n0); st.set_uv(uv0); st.add_vertex(p0)
		st.set_normal(n1); st.set_uv(uv1); st.add_vertex(p1)
		st.set_normal(n2); st.set_uv(uv2); st.add_vertex(p2)
	else:
		st.set_uv(uv0); st.add_vertex(p0)
		st.set_uv(uv1); st.add_vertex(p1)
		st.set_uv(uv2); st.add_vertex(p2)

## Beveled Cylinder / Tapered Cone / Lego Stud (centered at Y=0, height along Y)
static func beveled_cylinder(
	radius_bottom: float,
	radius_top: float,
	height: float,
	radial_segments: int = 20,
	bevel: float = 0.015,
	smooth_sides: bool = true
) -> ArrayMesh:
	var segs := maxi(radial_segments, 3)
	var hy := height * 0.5
	var b := clampf(bevel, 0.0, minf(minf(radius_bottom, radius_top) * 0.45, hy * 0.45))

	# Profile rings from bottom center -> top center: (radius, y)
	var profile: Array[Vector2] = []
	profile.append(Vector2(0.0, -hy))
	if b > 0.0005:
		profile.append(Vector2(maxf(radius_bottom - b, 0.0), -hy))
		profile.append(Vector2(radius_bottom, -hy + b))
		profile.append(Vector2(radius_top, hy - b))
		profile.append(Vector2(maxf(radius_top - b, 0.0), hy))
	else:
		profile.append(Vector2(radius_bottom, -hy))
		profile.append(Vector2(radius_top, hy))
	profile.append(Vector2(0.0, hy))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for r_idx in range(profile.size() - 1):
		var p_a := profile[r_idx]
		var p_b := profile[r_idx + 1]
		var is_cap := (p_a.x == 0.0 or p_b.x == 0.0)
		for s in range(segs):
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var c0 := cos(a0); var s0 := sin(a0)
			var c1 := cos(a1); var s1 := sin(a1)

			var v00 := Vector3(c0 * p_a.x, p_a.y, s0 * p_a.x)
			var v10 := Vector3(c1 * p_a.x, p_a.y, s1 * p_a.x)
			var v01 := Vector3(c0 * p_b.x, p_b.y, s0 * p_b.x)
			var v11 := Vector3(c1 * p_b.x, p_b.y, s1 * p_b.x)

			var uv00 := Vector2(float(s) / float(segs), (p_a.y + hy) / maxf(height, 0.001))
			var uv10 := Vector2(float(s + 1) / float(segs), (p_a.y + hy) / maxf(height, 0.001))
			var uv01 := Vector2(float(s) / float(segs), (p_b.y + hy) / maxf(height, 0.001))
			var uv11 := Vector2(float(s + 1) / float(segs), (p_b.y + hy) / maxf(height, 0.001))

			var dr := p_b.x - p_a.x
			var dy := p_b.y - p_a.y
			var slope_n := Vector2(dy, -dr).normalized() # outward radial/y normal
			var n0 := Vector3(c0 * slope_n.x, slope_n.y, s0 * slope_n.x).normalized()
			var n1 := Vector3(c1 * slope_n.x, slope_n.y, s1 * slope_n.x).normalized()
			if not smooth_sides and not is_cap:
				var am := (a0 + a1) * 0.5
				var nm := Vector3(cos(am) * slope_n.x, slope_n.y, sin(am) * slope_n.x).normalized()
				n0 = nm; n1 = nm

			if p_a.x == 0.0:
				# Bottom fan
				var nb := Vector3.DOWN
				_add_tri(st, v00, v01, v11, nb, nb, nb, Vector2(0.5, 0.5), uv01, uv11, true)
			elif p_b.x == 0.0:
				# Top fan
				var nt := Vector3.UP
				_add_tri(st, v00, v10, v01, nt, nt, nt, uv00, uv10, Vector2(0.5, 0.5), true)
			else:
				_add_tri(st, v00, v10, v11, n0, n1, n1, uv00, uv10, uv11, true)
				_add_tri(st, v00, v11, v01, n0, n1, n0, uv00, uv11, uv01, true)

	st.generate_tangents()
	return st.commit()

## Lego-style stud (centered at bottom Y=0 so it sits cleanly on any surface!)
static func lego_stud(radius: float = 0.075, height: float = 0.045, segments: int = 16) -> ArrayMesh:
	var cyl := beveled_cylinder(radius, radius * 0.96, height, segments, height * 0.22, true)
	return offset_mesh(cyl, Vector3(0.0, height * 0.5, 0.0))

## Offsets all vertices in an ArrayMesh by `delta`
static func offset_mesh(mesh: ArrayMesh, delta: Vector3) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in range(verts.size()):
			verts[i] += delta
		arr[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := mesh.surface_get_material(s)
		if m:
			out.surface_set_material(s, m)
	return out

## Extrudes a 2D polygon (in XZ plane, Y from -height/2 to +height/2) into a 3D prism!
static func extrude_polygon_xz(poly: PackedVector2Array, height: float, uv_scale: float = 1.0) -> ArrayMesh:
	var n := poly.size()
	if n < 3:
		return ArrayMesh.new()

	# Ensure counter-clockwise 2D winding so triangulation & outward normals are consistent
	var signed_area := 0.0
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		signed_area += (a.x * b.y - b.x * a.y)
	var pts := poly.duplicate()
	if signed_area < 0.0:
		pts.reverse()

	var indices := Geometry2D.triangulate_polygon(pts)
	var hy := height * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Top (+Y) and Bottom (-Y) caps
	# In XZ with x right, z down: (p1-p0)x(p2-p0) in 3D (x,0,z) has Y = -(dx1*dz2 - dz1*dx2).
	# Since signed_area > 0 means dx1*dz2 - dz1*dx2 > 0 -> cross product points -Y!
	# So for +Y normal we reverse (i0, i2, i1); for -Y normal we keep (i0, i1, i2).
	for t in range(0, indices.size(), 3):
		var p0 := pts[indices[t]]
		var p1 := pts[indices[t + 1]]
		var p2 := pts[indices[t + 2]]
		# Top (+Y)
		st.set_uv(p0 * uv_scale); st.add_vertex(Vector3(p0.x, hy, p0.y))
		st.set_uv(p2 * uv_scale); st.add_vertex(Vector3(p2.x, hy, p2.y))
		st.set_uv(p1 * uv_scale); st.add_vertex(Vector3(p1.x, hy, p1.y))
		# Bottom (-Y)
		st.set_uv(p0 * uv_scale); st.add_vertex(Vector3(p0.x, -hy, p0.y))
		st.set_uv(p1 * uv_scale); st.add_vertex(Vector3(p1.x, -hy, p1.y))
		st.set_uv(p2 * uv_scale); st.add_vertex(Vector3(p2.x, -hy, p2.y))

	# Side walls
	var dist := 0.0
	for i in range(n):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var seg_len := a.distance_to(b)
		var v00 := Vector3(a.x, -hy, a.y)
		var v10 := Vector3(b.x, -hy, b.y)
		var v01 := Vector3(a.x, hy, a.y)
		var v11 := Vector3(b.x, hy, b.y)
		var u0 := dist * uv_scale
		var u1 := (dist + seg_len) * uv_scale
		dist += seg_len

		st.set_uv(Vector2(u0, 1.0)); st.add_vertex(v00)
		st.set_uv(Vector2(u0, 0.0)); st.add_vertex(v01)
		st.set_uv(Vector2(u1, 0.0)); st.add_vertex(v11)

		st.set_uv(Vector2(u0, 1.0)); st.add_vertex(v00)
		st.set_uv(Vector2(u1, 0.0)); st.add_vertex(v11)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(v10)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()

## Analytical Stone Arch Span (along X from -length/2 to +length/2, thickness along Z, bottom Y=0 to top Y=height)
## Produces clean planar UVs for stone brick courses!
static func arch_span_mesh(
	length: float,
	height: float,
	width_z: float,
	arch_half_span: float,
	arch_spring_y: float,
	arch_crown_y: float,
	slices: int = 28,
	uv_scale: float = 1.0
) -> ArrayMesh:
	var hl := length * 0.5
	var hz := width_z * 0.5
	var xs := PackedFloat32Array()
	var y_bots := PackedFloat32Array()

	xs.append(-hl); y_bots.append(0.0)
	xs.append(-arch_half_span - 0.001); y_bots.append(0.0)
	for i in range(slices + 1):
		var t := float(i) / float(slices)
		var x := lerpf(-arch_half_span, arch_half_span, t)
		var nx := clampf(x / arch_half_span, -1.0, 1.0)
		var arch_h := maxf(arch_crown_y - arch_spring_y, 0.01)
		xs.append(x)
		y_bots.append(arch_spring_y + arch_h * sqrt(maxf(0.0, 1.0 - nx * nx)))
	xs.append(arch_half_span + 0.001); y_bots.append(0.0)
	xs.append(hl); y_bots.append(0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(xs.size() - 1):
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var yb0 := y_bots[i]
		var yb1 := y_bots[i + 1]

		# Front (+Z) spandrel strip
		var f00 := Vector3(x0, yb0, hz)
		var f10 := Vector3(x1, yb1, hz)
		var f11 := Vector3(x1, height, hz)
		var f01 := Vector3(x0, height, hz)
		st.set_uv(Vector2(x0, -yb0) * uv_scale); st.add_vertex(f00)
		st.set_uv(Vector2(x0, -height) * uv_scale); st.add_vertex(f01)
		st.set_uv(Vector2(x1, -height) * uv_scale); st.add_vertex(f11)
		st.set_uv(Vector2(x0, -yb0) * uv_scale); st.add_vertex(f00)
		st.set_uv(Vector2(x1, -height) * uv_scale); st.add_vertex(f11)
		st.set_uv(Vector2(x1, -yb1) * uv_scale); st.add_vertex(f10)

		# Back (-Z) spandrel strip
		var b00 := Vector3(x0, yb0, -hz)
		var b10 := Vector3(x1, yb1, -hz)
		var b11 := Vector3(x1, height, -hz)
		var b01 := Vector3(x0, height, -hz)
		st.set_uv(Vector2(-x0, -yb0) * uv_scale); st.add_vertex(b00)
		st.set_uv(Vector2(-x1, -height) * uv_scale); st.add_vertex(b11)
		st.set_uv(Vector2(-x0, -height) * uv_scale); st.add_vertex(b01)
		st.set_uv(Vector2(-x0, -yb0) * uv_scale); st.add_vertex(b00)
		st.set_uv(Vector2(-x1, -yb1) * uv_scale); st.add_vertex(b10)
		st.set_uv(Vector2(-x1, -height) * uv_scale); st.add_vertex(b11)

		# Top (+Y) deck underside
		_emit_quad(st,
			Vector3(x0, height, hz), Vector3(x1, height, hz),
			Vector3(x1, height, -hz), Vector3(x0, height, -hz),
			uv_scale
		)

		# Bottom / Arch intrados vault (facing downward)
		_emit_quad(st,
			Vector3(x0, yb0, -hz), Vector3(x1, yb1, -hz),
			Vector3(x1, yb1, hz), Vector3(x0, yb0, hz),
			uv_scale
		)

	# Left (-X) outer abutment wall
	_emit_quad(st,
		Vector3(-hl, 0.0, -hz), Vector3(-hl, 0.0, hz),
		Vector3(-hl, height, hz), Vector3(-hl, height, -hz),
		uv_scale
	)
	# Right (+X) outer abutment wall
	_emit_quad(st,
		Vector3(hl, 0.0, hz), Vector3(hl, 0.0, -hz),
		Vector3(hl, height, -hz), Vector3(hl, height, hz),
		uv_scale
	)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()

static func _emit_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, uv_scale: float) -> void:
	var u_len := p0.distance_to(p1) * uv_scale
	var v_len := p0.distance_to(p3) * uv_scale
	st.set_uv(Vector2(0.0, v_len)); st.add_vertex(p0)
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p3)
	st.set_uv(Vector2(u_len, 0.0)); st.add_vertex(p2)
	st.set_uv(Vector2(0.0, v_len)); st.add_vertex(p0)
	st.set_uv(Vector2(u_len, 0.0)); st.add_vertex(p2)
	st.set_uv(Vector2(u_len, v_len)); st.add_vertex(p1)

## 3D Extruded Text Mesh (centered at (0,0,0), facing +Z)
static func text_mesh_3d(txt: String, font_px: int = 36, pixel_size: float = 0.008, depth: float = 0.05) -> ArrayMesh:
	var tm := TextMesh.new()
	tm.text = txt
	tm.font_size = font_px
	tm.pixel_size = pixel_size
	tm.depth = depth
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return prim_to_array_mesh(tm)

# ============================================================================
# PROCEDURAL PBR TEXTURES & MATERIALS
# ============================================================================

static func ensure_textures_generated() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://textures"))
	_make_wood_tex("wood_oak", Color(0.78, 0.56, 0.30), Color(0.64, 0.43, 0.20))
	_make_wood_tex("wood_brown", Color(0.56, 0.35, 0.19), Color(0.42, 0.25, 0.12))
	_make_wood_tex("wood_dark", Color(0.42, 0.26, 0.15), Color(0.30, 0.18, 0.09))
	_make_wood_tex("wood_gold", Color(0.92, 0.68, 0.25), Color(0.78, 0.53, 0.16))
	_make_wood_tex("wood_boat", Color(0.71, 0.41, 0.25), Color(0.57, 0.31, 0.18))
	_make_earth_strata_tex("earth_strata")
	_make_grass_tex("grass_top")
	_make_brick_tex("stone_ashlar", Color(0.78, 0.76, 0.72), Color(0.58, 0.56, 0.53), 4, 3)
	_make_brick_tex("brick_dark", Color(0.28, 0.25, 0.22), Color(0.15, 0.13, 0.12), 8, 6)
	_make_water_tex("water_flow")

static func _save_and_cache_tex(key: String, img: Image) -> ImageTexture:
	var rel_path := "res://textures/%s.png" % key
	var abs_path := ProjectSettings.globalize_path(rel_path)
	# Only write the PNG when running from the editor/CLI; exported builds (web) have a read-only res://
	if OS.has_feature("editor"):
		img.save_png(abs_path)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

static func get_tex(key: String) -> ImageTexture:
	if not _tex_cache.has(key):
		ensure_textures_generated()
	return _tex_cache.get(key, null)

static func _hash_float(x: int, y: int, seed_val: int = 1337) -> float:
	var n: int = (x * 374761393 + y * 668265263 + seed_val * 1442695041) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	n = (n ^ (n >> 16)) & 0x7fffffff
	return float(n % 10000) / 10000.0

static func _make_wood_tex(key: String, c_light: Color, c_dark: Color) -> void:
	var w := 128
	var h := 128
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var streak := _hash_float(0, y / 2, key.hash())
		var ring := 0.5 + 0.5 * sin(float(y) * 0.28 + streak * 2.2)
		for x in range(w):
			var fine := _hash_float(x / 4, y, key.hash() + 7)
			var t := clampf(ring * 0.65 + streak * 0.25 + fine * 0.15, 0.0, 1.0)
			img.set_pixel(x, y, c_dark.lerp(c_light, t))
	_save_and_cache_tex(key, img)

static func _make_earth_strata_tex(key: String) -> void:
	var w := 128
	var h := 128
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var bands: Array[Color] = [
		Color(0.66, 0.45, 0.26),
		Color(0.53, 0.34, 0.19),
		Color(0.44, 0.27, 0.15),
		Color(0.36, 0.21, 0.12)
	]
	for y in range(h):
		var fy := float(y) / float(h)
		var b_idx := clampi(int(fy * 4.0), 0, 3)
		var base_c := bands[b_idx]
		for x in range(w):
			var block_n := _hash_float(x / 16, y / 12, 91)
			var fine_n := _hash_float(x / 3, y / 3, 193)
			var mul := 0.88 + block_n * 0.18 + fine_n * 0.06
			# Occasional tiny pebble highlight
			if _hash_float(x / 6, y / 6, 777) > 0.965:
				mul = 1.22
			img.set_pixel(x, y, Color(
				clampf(base_c.r * mul, 0.0, 1.0),
				clampf(base_c.g * mul, 0.0, 1.0),
				clampf(base_c.b * mul, 0.0, 1.0),
				1.0
			))
	_save_and_cache_tex(key, img)

static func _make_grass_tex(key: String) -> void:
	var w := 128
	var h := 128
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var c_base := Color(0.45, 0.78, 0.20)
	var c_bright := Color(0.62, 0.88, 0.28)
	var c_deep := Color(0.35, 0.66, 0.16)
	for y in range(h):
		for x in range(w):
			var cell := _hash_float(x / 8, y / 8, 555)
			var c := c_base
			if cell > 0.78:
				c = c_bright
			elif cell < 0.18:
				c = c_deep
			var fine := 0.96 + _hash_float(x / 2, y / 2, 333) * 0.08
			img.set_pixel(x, y, Color(c.r * fine, c.g * fine, c.b * fine, 1.0))
	_save_and_cache_tex(key, img)

static func _make_brick_tex(key: String, c_brick: Color, c_mortar: Color, rows: int, cols: int) -> void:
	var w := 128
	var h := 128
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var row_h := float(h) / float(rows)
	var col_w := float(w) / float(cols)
	for y in range(h):
		var r := int(float(y) / row_h)
		var ry := fmod(float(y), row_h)
		var x_off := (col_w * 0.5) if (r % 2 == 1) else 0.0
		for x in range(w):
			var sx := fmod(float(x) + x_off, float(w))
			var c_idx := int(sx / col_w)
			var cx := fmod(sx, col_w)
			var is_mortar := (ry < 2.0 or ry > row_h - 1.5 or cx < 2.0 or cx > col_w - 1.5)
			if is_mortar:
				img.set_pixel(x, y, c_mortar)
			else:
				var tone := 0.90 + _hash_float(c_idx, r, key.hash()) * 0.20
				var grit := 0.96 + _hash_float(x / 2, y / 2, 888) * 0.08
				var m := tone * grit
				img.set_pixel(x, y, Color(
					clampf(c_brick.r * m, 0.0, 1.0),
					clampf(c_brick.g * m, 0.0, 1.0),
					clampf(c_brick.b * m, 0.0, 1.0),
					1.0
				))
	_save_and_cache_tex(key, img)

static func _make_water_tex(key: String) -> void:
	var w := 128
	var h := 128
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var c_deep := Color(0.10, 0.56, 0.85, 0.86)
	var c_foam := Color(0.58, 0.90, 1.00, 0.92)
	for y in range(h):
		for x in range(w):
			var streak := 0.5 + 0.5 * sin(float(x) * 0.32 + _hash_float(x / 6, y / 16, 42) * 2.5)
			var ripple := 0.5 + 0.5 * sin(float(y) * 0.25 + float(x) * 0.1)
			var t := clampf(streak * 0.65 + ripple * 0.25, 0.0, 1.0)
			img.set_pixel(x, y, c_deep.lerp(c_foam, pow(t, 2.2)))
	_save_and_cache_tex(key, img)

static func mat_color(
	key: String,
	color: Color,
	roughness: float = 0.55,
	metallic: float = 0.0,
	tex_key: String = ""
) -> StandardMaterial3D:
	var cache_id := "%s_%s_%.2f_%.2f_%s" % [key, color.to_html(), roughness, metallic, tex_key]
	if _mat_cache.has(cache_id):
		return _mat_cache[cache_id]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if tex_key != "":
		m.albedo_texture = get_tex(tex_key)
	_mat_cache[cache_id] = m
	return m

static func mat_emissive(
	key: String,
	albedo: Color,
	emission_col: Color,
	energy: float = 2.2,
	roughness: float = 0.25
) -> StandardMaterial3D:
	var cache_id := "em_%s_%s_%.2f" % [key, emission_col.to_html(), energy]
	if _mat_cache.has(cache_id):
		return _mat_cache[cache_id]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = albedo
	m.roughness = roughness
	m.emission_enabled = true
	m.emission = emission_col
	m.emission_energy_multiplier = energy
	_mat_cache[cache_id] = m
	return m

static func mat_water(key: String, color: Color = Color(0.16, 0.68, 0.92, 0.84), use_flow_tex: bool = true) -> StandardMaterial3D:
	var cache_id := "water_%s_%s_%s" % [key, color.to_html(), str(use_flow_tex)]
	if _mat_cache.has(cache_id):
		return _mat_cache[cache_id]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	if use_flow_tex:
		m.albedo_texture = get_tex("water_flow")
	m.roughness = 0.12
	m.metallic = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[cache_id] = m
	return m

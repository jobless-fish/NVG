class_name StaticBatcher
extends RefCounted

## Merges every static MeshInstance3D under `root` into one mesh per material (static batching).
## The world is built from ~70 modular prefabs with many small parts, which means thousands of
## draw calls; WebGL (Compatibility renderer) chokes on that. After batching the whole map is a
## few hundred draw calls. Nodes under `exclude` (animated / moving things) are left untouched.
## Returns [meshes_before, meshes_after].

static func batch(root: Node3D, exclude: Array) -> Array:
	var excluded := {}
	for n in exclude:
		if n != null and is_instance_valid(n):
			excluded[n] = true

	var groups: Dictionary = {}   # key -> {"mat": Material, "items": [[mesh, surface, xform]]}
	var originals: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var cur: Node = stack.pop_back()
		if excluded.has(cur):
			continue
		if cur is CanvasLayer:
			continue
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if _batchable(mi):
				var xf := mi.global_transform
				var mesh := mi.mesh
				for s in range(mesh.get_surface_count()):
					var mat: Material = mi.material_override
					if mat == null:
						mat = mi.get_surface_override_material(s)
					if mat == null:
						mat = mesh.surface_get_material(s)
					var fmt: int = mesh.surface_get_format(s) & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_COLOR)
					var key := "%d_%d_%d" % [mat.get_instance_id() if mat != null else 0, fmt, int(mi.cast_shadow)]
					if not groups.has(key):
						groups[key] = {"mat": mat, "shadow": mi.cast_shadow, "items": []}
					(groups[key]["items"] as Array).append([mesh, s, xf])
				originals.append(mi)
		for ch in cur.get_children():
			stack.append(ch)

	var holder := Node3D.new()
	holder.name = "StaticBatches"
	root.add_child(holder)
	var made := 0
	for key: String in groups.keys():
		var g: Dictionary = groups[key]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for it: Array in g["items"]:
			st.append_from(it[0], it[1], it[2])
		var am := st.commit()
		if am == null or am.get_surface_count() == 0:
			continue
		if g["mat"] != null:
			am.surface_set_material(0, g["mat"])
		var out := MeshInstance3D.new()
		out.name = "Batch_%d" % made
		out.mesh = am
		out.cast_shadow = g["shadow"]
		holder.add_child(out)
		made += 1

	for mi in originals:
		if mi.get_child_count() == 0:
			mi.queue_free()
		else:
			mi.visible = false
	return [originals.size(), made]

static func _batchable(mi: MeshInstance3D) -> bool:
	if not mi.is_visible_in_tree() or mi.mesh == null:
		return false
	if mi.skeleton != NodePath("") and mi.get_node_or_null(mi.skeleton) is Skeleton3D:
		return false
	var m := mi.mesh
	if m is PrimitiveMesh:
		var pm := m as PrimitiveMesh
		if pm.material is ShaderMaterial:
			return false   # ocean & other shader-driven meshes keep their own node
	for s in range(m.get_surface_count()):
		if m is ArrayMesh and (m as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var mat := mi.get_active_material(s)
		if mat is ShaderMaterial:
			return false
	return true

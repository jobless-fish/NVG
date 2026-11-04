extends Node3D

## Renders isometric studio previews of ALL 50 3D models + 4-angle Robot turnaround
## using Godot 4.7 Vulkan Forward+ so we can verify every model visually!

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("res://renders")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Studio lighting matching map_base.png (warm sunlight from top-left + sky fill + glow)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.19, 0.24, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.84, 0.96)
	env.ambient_light_energy = 0.58
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Sun shining from top-left (-X, +Y, +Z) so +Z face is sunlit and +X face is shaded!
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.22
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(-3.5, 8.5, 6.5), Vector3.ZERO, Vector3.UP)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.80, 1.0)
	fill.light_energy = 0.45
	add_child(fill)
	fill.look_at_from_position(Vector3(6.0, 3.5, -4.0), Vector3.ZERO, Vector3.UP)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 100.0
	cam.current = true
	add_child(cam)

	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)

	await get_tree().process_frame
	await get_tree().process_frame

	# Optional: `-- --only=OBJ` renders just the matching assets
	var only_prefix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only_prefix = arg.substr(7)

	# 1. Render all 4 reference angles of 01_robot to verify against 01-04 PNGs!
	var robot_scene := load("res://scenes/assets/01_robot.tscn") as PackedScene
	if robot_scene and only_prefix == "":
		var r_angles := [
			["01_robot_front", 15.0],
			["02_robot_side", -32.0],
			["03_robot_back", -165.0],
			["04_robot_back_side", -125.0]
		]
		for ra: Array in r_angles:
			var r_inst := robot_scene.instantiate() as Node3D
			r_inst.rotation_degrees = Vector3(0.0, ra[1], 0.0)
			stage.add_child(r_inst)
			_frame_camera_ortho(cam, r_inst)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, ra[0]])
			stage.remove_child(r_inst)
			r_inst.free()

	# 2. Render all 50 catalog assets!
	var entries := AssetCatalog.get_entries()
	for entry in entries:
		var asset_id: String = entry["id"]
		if only_prefix != "" and not asset_id.begins_with(only_prefix):
			continue
		var sc := load("res://scenes/assets/%s.tscn" % asset_id) as PackedScene
		if sc == null:
			continue
		var inst := sc.instantiate() as Node3D
		if asset_id == "01_robot":
			inst.rotation_degrees = Vector3(0.0, 18.0, 0.0)
		elif asset_id.begins_with("OBJ"):
			# objects/ reference PNGs show the front face a bit more than the right side
			inst.rotation_degrees = Vector3(0.0, 22.0, 0.0)
		stage.add_child(inst)
		_frame_camera_ortho(cam, inst)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, asset_id])
		stage.remove_child(inst)
		inst.free()

	print("=== Rendered all studio previews to res://renders/ ===")
	get_tree().quit(0)

func _compute_aabb(node: Node3D) -> AABB:
	var found := false
	var result := AABB()
	var stack: Array[Node] = [node]
	while stack.size() > 0:
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var local_aabb := mi.mesh.get_aabb()
				var rel_xform := node.global_transform.affine_inverse() * mi.global_transform
				var world_aabb := rel_xform * local_aabb
				if not found:
					result = world_aabb
					found = true
				else:
					result = result.merge(world_aabb)
		for ch in cur.get_children():
			stack.append(ch)
	if not found:
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
	return result

func _frame_camera_ortho(cam: Camera3D, target_node: Node3D) -> void:
	var box := _compute_aabb(target_node)
	var center := box.position + box.size * 0.5
	var max_extent := maxf(box.size.x, maxf(box.size.y, box.size.z))
	# Project all 8 AABB corners into isometric camera space to fit tightly!
	var view_dir := Vector3(1.0, 0.82, 1.0).normalized()
	cam.look_at_from_position(center + view_dir * 12.0, center, Vector3.UP)
	var inv_cam := cam.global_transform.affine_inverse()
	var max_abs_x := 0.1
	var max_abs_y := 0.1
	for ix: float in [0.0, 1.0]:
		for iy: float in [0.0, 1.0]:
			for iz: float in [0.0, 1.0]:
				var corner := box.position + Vector3(box.size.x * ix, box.size.y * iy, box.size.z * iz)
				var cp := inv_cam * corner
				max_abs_x = maxf(max_abs_x, absf(cp.x))
				max_abs_y = maxf(max_abs_y, absf(cp.y))
	cam.size = maxf(max_abs_x, max_abs_y) * 2.38
	if cam.size < 0.4:
		cam.size = max_extent * 1.65

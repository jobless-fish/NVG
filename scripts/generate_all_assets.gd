extends SceneTree

## CLI Asset Pipeline:
## 1. Generates procedural PBR textures in res://textures/
## 2. Builds all 70 3D models (sample-assets 01-53 + objects OBJ01-OBJ20)
## 3. Exports standalone .glb files to res://models_glb/
## 4. Saves native Godot .tscn prefabs to res://scenes/assets/
## 5. Builds res://scenes/AssetShowcase.tscn gallery scene

func _initialize() -> void:
	print("=== NODEVERSE 3D Asset Generator Starting ===")
	MeshKit.clear_caches()
	MeshKit.ensure_textures_generated()

	var glb_dir := ProjectSettings.globalize_path("res://models_glb")
	var tscn_dir := ProjectSettings.globalize_path("res://scenes/assets")
	var scenes_dir := ProjectSettings.globalize_path("res://scenes")
	DirAccess.make_dir_recursive_absolute(glb_dir)
	DirAccess.make_dir_recursive_absolute(tscn_dir)
	DirAccess.make_dir_recursive_absolute(scenes_dir)

	var entries := AssetCatalog.get_entries()
	var saved_scenes: Dictionary = {}

	# Optional: `-- --only=OBJ` regenerates just the matching assets (skips the showcase rebuild)
	var only_prefix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only_prefix = arg.substr(7)

	for entry in entries:
		if only_prefix != "" and not (entry["id"] as String).begins_with(only_prefix):
			continue
		var asset_id: String = entry["id"]
		var builder: Callable = entry["build"]
		var node: Node3D = builder.call()
		node.name = asset_id

		# 1. Export universal .glb (glTF 2.0 binary)
		var gltf_doc := GLTFDocument.new()
		var gltf_state := GLTFState.new()
		var append_err := gltf_doc.append_from_scene(node, gltf_state)
		if append_err != OK:
			push_error("GLTF append failed for %s: %d" % [asset_id, append_err])
		else:
			var out_glb := "%s/%s.glb" % [glb_dir, asset_id]
			var write_err := gltf_doc.write_to_filesystem(gltf_state, out_glb)
			if write_err != OK:
				push_error("GLTF write failed for %s: %d" % [asset_id, write_err])

		# 2. Save native Godot .tscn prefab
		MeshKit.set_owner_recursive(node, node)
		var packed := PackedScene.new()
		var pack_err := packed.pack(node)
		if pack_err == OK:
			var res_path := "res://scenes/assets/%s.tscn" % asset_id
			var save_err := ResourceSaver.save(packed, res_path)
			if save_err == OK:
				saved_scenes[asset_id] = load(res_path)
			else:
				push_error("TSCN save failed for %s: %d" % [asset_id, save_err])
		node.free()
		print("Generated: %s (.glb + .tscn)" % asset_id)

	# 3. Build interactive AssetShowcase.tscn
	if only_prefix != "":
		print("=== Partial run (--only=%s): showcase not rebuilt ===" % only_prefix)
		quit(0)
		return
	_build_showcase_scene(entries, saved_scenes)
	print("=== Completed all %d 3D models! ===" % entries.size())
	quit(0)

## Max horizontal extent (X/Z) of all meshes under `node`, in node-local space
func _footprint(node: Node3D) -> float:
	var found := false
	var box := AABB()
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while stack.size() > 0:
		var item: Array = stack.pop_back()
		var cur: Node = item[0]
		var t: Transform3D = item[1]
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var wb: AABB = t * (cur as MeshInstance3D).mesh.get_aabb()
			box = wb if not found else box.merge(wb)
			found = true
		for ch in cur.get_children():
			if ch is Node3D:
				stack.append([ch, t * (ch as Node3D).transform])
	if not found:
		return 0.0
	return maxf(box.size.x, box.size.z)

func _build_showcase_scene(entries: Array[Dictionary], saved_scenes: Dictionary) -> void:
	var showcase := Node3D.new()
	showcase.name = "AssetShowcase"

	# Sunny diorama sky & environment matching map_base.png
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.24, 0.62, 0.88)
	sky_mat.sky_horizon_color = Color(0.68, 0.88, 0.96)
	sky_mat.ground_horizon_color = Color(0.20, 0.66, 0.76)
	sky_mat.ground_bottom_color = Color(0.08, 0.42, 0.56)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.65
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.25
	env.glow_bloom = 0.05
	env.ssao_enabled = true

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	showcase.add_child(world_env)

	# Key Sun Light (from top-left matching map_base.png!) + Cool Water Bounce Fill Light
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 75.0
	showcase.add_child(sun)
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)

	var fill := DirectionalLight3D.new()
	fill.name = "SkyFillLight"
	fill.light_color = Color(0.55, 0.82, 0.98)
	fill.light_energy = 0.42
	fill.shadow_enabled = false
	showcase.add_child(fill)
	fill.rotation_degrees = Vector3(-35.0, 145.0, 0.0)

	# Stylized Turquoise Ocean Floor Plane
	var ocean := MeshInstance3D.new()
	ocean.name = "OceanFloor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(90.0, 90.0)
	var ocean_mat := StandardMaterial3D.new()
	ocean_mat.albedo_color = Color(0.11, 0.58, 0.68)
	ocean_mat.roughness = 0.18
	ocean_mat.metallic = 0.08
	pm.material = ocean_mat
	ocean.mesh = pm
	ocean.position = Vector3(0.0, -0.14, 0.0)
	showcase.add_child(ocean)

	# Pedestal material
	var ped_mat := StandardMaterial3D.new()
	ped_mat.albedo_color = Color(0.86, 0.84, 0.80)
	ped_mat.roughness = 0.65
	var ped_mesh := MeshKit.beveled_box(Vector3(2.35, 0.12, 2.35), 0.02, 1, false)

	# Arrange 70 assets in clean rows by category
	var cols := 10
	var spacing_x := 2.95
	var spacing_z := 3.35
	var total_rows := int(ceil(float(entries.size()) / float(cols)))

	var gallery_root := Node3D.new()
	gallery_root.name = "AssetsGrid"
	showcase.add_child(gallery_root)

	for idx in range(entries.size()):
		var entry: Dictionary = entries[idx]
		var asset_id: String = entry["id"]
		var kr_name: String = entry["kr"]
		var col := idx % cols
		var row := idx / cols
		var gx := (float(col) - float(cols - 1) * 0.5) * spacing_x
		var gz := (float(row) - float(total_rows - 1) * 0.5) * spacing_z

		var slot := Node3D.new()
		slot.name = "Slot_" + asset_id
		slot.position = Vector3(gx, 0.0, gz)
		gallery_root.add_child(slot)

		var ped := MeshInstance3D.new()
		ped.name = "Pedestal"
		ped.mesh = ped_mesh
		ped.material_override = ped_mat
		ped.position = Vector3(0.0, -0.06, 0.0)
		slot.add_child(ped)

		if saved_scenes.has(asset_id) and saved_scenes[asset_id] != null:
			var inst: Node3D = (saved_scenes[asset_id] as PackedScene).instantiate()
			inst.name = asset_id
			slot.add_child(inst)
			# Large landmarks (plaza, maze, archive...) are shrunk to fit the pedestal in the gallery only
			var foot := _footprint(inst)
			if foot > 2.3:
				var k := 2.3 / foot
				inst.scale = Vector3(k, k, k)

		var lbl := Label3D.new()
		lbl.name = "Label3D"
		lbl.text = "%s\n%s" % [asset_id.get_slice("_", 0), kr_name]
		lbl.font_size = 34
		lbl.outline_size = 10
		lbl.pixel_size = 0.0045
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0.0, -0.22, 1.25)
		slot.add_child(lbl)

	# Interactive Camera Rig
	var cam_rig := Node3D.new()
	cam_rig.name = "ShowcaseCameraRig"
	cam_rig.set_script(load("res://scripts/showcase_camera.gd"))
	showcase.add_child(cam_rig)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 38.0
	cam.far = 250.0
	cam_rig.add_child(cam)
	cam.look_at_from_position(Vector3(20.0, 18.5, 22.5), Vector3(0.0, 0.6, 0.5), Vector3.UP)

	MeshKit.set_owner_recursive(showcase, showcase)
	var showcase_packed := PackedScene.new()
	if showcase_packed.pack(showcase) == OK:
		ResourceSaver.save(showcase_packed, "res://scenes/AssetShowcase.tscn")
	showcase.free()

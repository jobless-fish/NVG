extends Node3D

func _ready() -> void:
	var showcase_sc := load("res://scenes/AssetShowcase.tscn") as PackedScene
	var inst := showcase_sc.instantiate()
	add_child(inst)
	# Hide UI overlay for clean studio beauty shot
	for ch in inst.find_children("*", "CanvasLayer", true, false):
		(ch as CanvasLayer).visible = false
	var cam := inst.find_child("Camera3D", true, false) as Camera3D
	if cam:
		cam.fov = 34.0
		cam.look_at_from_position(Vector3(23.0, 22.5, 29.5), Vector3(0.0, 0.0, 1.6), Vector3.UP)
		cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out_png := ProjectSettings.globalize_path("res://renders/showcase_overview.png")
	get_viewport().get_texture().get_image().save_png(out_png)
	print("Saved showcase overview: ", out_png)
	inst.free()
	await get_tree().process_frame
	get_tree().quit(0)

class_name BuilderIslandSigns
extends RefCounted

## Major-island wooden signs (source: NODEVERSE objects/OBJ17-OBJ20).
## Same design for all four; only the Korean label and board width change.

static func build_island_sign(label: String) -> Node3D:
	var root := Node3D.new()
	root.name = "IslandSign"

	var mat_frame := ObjKit.m_wood_light()
	var mat_panel := ObjKit.m_wood_dark()
	var mat_stone := ObjKit.m_stone_light()
	var mat_corner := MeshKit.mat_color("isign_corner", Color(0.72, 0.70, 0.66), 0.6, 0.0)
	var mat_gold := ObjKit.m_gold()
	var mat_text := MeshKit.mat_color("isign_text", Color(0.98, 0.95, 0.88), 0.45, 0.0)

	# Board width follows the label length (같은 디자인, 글자 수에 맞춰 폭만 조정)
	var font_px := 64
	var text_h := 0.30
	var px_size := text_h / float(font_px)
	var tw := ObjKit.text_width(label, font_px) * px_size
	var W := clampf(tw + 0.62, 1.50, 2.30)
	var H := 0.74
	var board_y := 0.50 + H * 0.5
	var depth := 0.14
	var border := 0.12

	# Two legs on two-tier stone feet
	var leg_x := W * 0.5 - 0.36
	for sx: float in [-1.0, 1.0]:
		MeshKit.add_part(root, "FootLow_%d" % int(sx), ObjKit.box(Vector3(0.32, 0.10, 0.28), 0.018), mat_stone, Vector3(sx * leg_x, 0.05, 0.0))
		MeshKit.add_part(root, "FootUp_%d" % int(sx), ObjKit.box(Vector3(0.24, 0.08, 0.22), 0.016), mat_stone, Vector3(sx * leg_x, 0.14, 0.0))
		MeshKit.add_part(root, "Leg_%d" % int(sx), ObjKit.box(Vector3(0.14, 0.36, 0.12), 0.018), ObjKit.m_timber(), Vector3(sx * leg_x, 0.36, 0.0))

	# Dark plank panel
	var ph := (H - border * 1.4) / 3.0
	for i in range(3):
		MeshKit.add_part(root, "Plank_%d" % i, ObjKit.box(Vector3(W - border * 1.4, ph * 0.97, depth * 0.62), 0.008), mat_panel,
			Vector3(0.0, board_y - (H - border * 1.4) * 0.5 + ph * (float(i) + 0.5), 0.0))

	# Thick light timber frame (segmented rails)
	var frame_items: Array = []
	var seg_n := 3
	var seg_w := W / float(seg_n)
	for rail_y: float in [board_y + H * 0.5 - border * 0.5, board_y - H * 0.5 + border * 0.5]:
		for s in range(seg_n):
			frame_items.append([ObjKit.box(Vector3(seg_w - 0.01, border, depth), 0.018), ObjKit.xf(Vector3(-W * 0.5 + seg_w * (float(s) + 0.5), rail_y, 0.0))])
	for sx: float in [-1.0, 1.0]:
		frame_items.append([ObjKit.box(Vector3(border, H - border * 2.0 + 0.01, depth), 0.018), ObjKit.xf(Vector3(sx * (W * 0.5 - border * 0.5), board_y, 0.0))])
	ObjKit.add_merged(root, "Frame", frame_items, mat_frame)

	# Stone corner caps with gold studs + top end blocks
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var cp := Vector3(sx * (W * 0.5 - 0.04), board_y + sy * (H * 0.5 - 0.04), 0.0)
			MeshKit.add_part(root, "CornerCap_%d_%d" % [int(sx), int(sy)], ObjKit.box(Vector3(0.18, 0.18, depth + 0.04), 0.025), mat_corner, cp)
			MeshKit.add_part(root, "CornerStud_%d_%d" % [int(sx), int(sy)], ObjKit.box(Vector3(0.065, 0.065, 0.03), 0.01), mat_gold, cp + Vector3(0.0, 0.0, depth * 0.5 + 0.025))
		MeshKit.add_part(root, "TopBlock_%d" % int(sx), ObjKit.box(Vector3(0.20, 0.07, 0.12), 0.015), mat_frame, Vector3(sx * (W * 0.5 - 0.16), board_y + H * 0.5 + 0.035, 0.0))
		MeshKit.add_part(root, "TopStud_%d" % int(sx), ObjKit.box(Vector3(0.09, 0.04, 0.07), 0.01), mat_gold, Vector3(sx * (W * 0.5 - 0.16), board_y + H * 0.5 + 0.09, 0.0))

	# Raised white Korean lettering on the front
	var text_depth := 0.04
	MeshKit.add_part(root, "Label", ObjKit.text_mesh_kr(label, font_px, px_size, text_depth), mat_text,
		Vector3(0.0, board_y, depth * 0.31 + text_depth * 0.5))
	return root

extends Node3D

## NODEVERSE 연결섬 playable 3D world map
## (reference: reference/NODEVERSE_연결섬_전체지도.png)
##
##                [알고리즘 섬]  (-Z, north)
##                      |
##   [자료구조 섬] —— [메인 섬 / 수정 비콘] —— [SQL 섬]
##   (-X, west)          |  (+Z, south: plaza, village, pier)      (+X, east)
##
## Everything is assembled at runtime from res://scenes/assets/*.tscn prefabs
## (sample-assets 01-53 + objects OBJ01-OBJ20) plus block terrain from WorldTerrain.
## Run with `-- --capture` to save renders/world_overview*.png and quit.

const ExtraAssets = preload("res://scripts/builders/builder_extra_world_assets.gd")
const PlayerRobot = preload("res://scripts/player_robot.gd")
const ASSET_DIR: String = "res://scenes/assets/"
const WATER_Y: float = 0.05
const TOP: float = 1.0
const SEA_FAR: Color = Color(0.10, 0.50, 0.66)
const OCEAN_SIZE: float = 1400.0

const ISLANDS := {
	"MAIN": {"center": Vector2(0.0, 5.3), "rx": 7.4, "rz": 6.3, "rects": [Rect2(-2.5, -2.6, 5.0, 4.0)], "seed": 3},
	"DS": {"center": Vector2(-15.5, -1.0), "rx": 7.0, "rz": 6.5, "rects": [], "seed": 7},
	"ALGO": {"center": Vector2(0.0, -14.0), "rx": 9.5, "rz": 5.6, "rects": [], "seed": 11},
	"SQL": {"center": Vector2(15.5, -1.0), "rx": 7.0, "rz": 6.5, "rects": [], "seed": 13}
}

var player: CharacterBody3D
var island_cells: Dictionary = {}
var reserved: Array = []   # [Vector2 pos, float radius]

# HUD
var zone_label: Label
var msg_label: Label
var prompt_label: Label
var help_label: Label
var _msg_time: float = 0.0
var _zone_name: String = "MAIN"

# Shared glowing orb (list / graph / sql animations)
var orb: MeshInstance3D
var _orb_busy: bool = false

# ARRAY (자료구조 섬 west harbor)
const ARRAY_X: float = -20.2
const ARRAY_Z0: float = -4.0
var array_tiles: Array[Node3D] = []
var array_labels: Array[Label3D] = []
var array_values: Array[int] = [7, 3, 9, 4, 1]
var array_crane: Node3D
var _crane_busy: bool = false

# LIST
var list_nodes: Array[Node3D] = []

# STACK
var stack_tower: Node3D
var stack_crates: Array[Node3D] = []
const STACK_CAP: int = 4
var stack_label: Label3D

# QUEUE (conveyor runs along +X)
const QUEUE_Z: float = 3.0
const QUEUE_START_X: float = -15.3
const QUEUE_END_X: float = -10.1
const QUEUE_CAP: int = 5
var queue_crates: Array[Node3D] = []
var queue_label: Label3D
var _queue_timer: float = 2.0

# ALGORITHM graph
var graph_nodes: Array[Vector3] = []
var sort_columns: Array[Node3D] = []
var sort_node: Node3D
var fps_label: Label
var _is_web: bool = false

# SQL query channel
var sql_query: Node3D

const DS_ANCHORS := {
	"ARRAY": Vector2(-20.2, -1.6),
	"LIST": Vector2(-14.3, -5.5),
	"STACK": Vector2(-17.3, 2.6),
	"QUEUE": Vector2(-12.7, 3.0)
}

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	MeshKit.ensure_textures_generated()
	_build_environment()
	_build_ocean()
	_build_islands()
	_build_bridges()
	_build_main_island()
	_build_ds_island()
	_build_algo_island()
	_build_sql_island()
	_build_nature()
	_build_orb()
	_build_player()
	_build_hud()
	_optimize()
	print("NODEVERSE world built in %d ms" % (Time.get_ticks_msec() - t0))
	if "--capture" in OS.get_cmdline_user_args():
		_capture_overview()
	elif "--edgetest" in OS.get_cmdline_user_args():
		_edge_test()
	elif "--perf" in OS.get_cmdline_user_args():
		_perf_report()

# ============================================================================
# PERFORMANCE (web: WebGL2 / Compatibility renderer)
# ============================================================================

func _optimize() -> void:
	_is_web = OS.has_feature("web") or "--webprofile" in OS.get_cmdline_user_args()
	# 1) Static batching: thousands of small prefab parts -> one mesh per material
	if not "--nobatch" in OS.get_cmdline_user_args():
		var exclude: Array = [player, stack_tower, array_crane, orb, sort_node]
		exclude.append_array(array_tiles)
		exclude.append_array(queue_crates)
		var res := StaticBatcher.batch(self, exclude)
		print("Static batching: %d mesh parts -> %d batches" % [res[0], res[1]])
	if not _is_web:
		return
	# 2) Web: per-object point lights are expensive in the Compatibility renderer -> rely on emission
	for l in find_children("*", "OmniLight3D", true, false):
		(l as OmniLight3D).visible = false
	# 3) Web: render 3D at a lower internal resolution, UI stays sharp
	get_viewport().scaling_3d_scale = 0.75
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED

func _perf_report() -> void:
	for i in range(90):
		await get_tree().process_frame
	print("PERF fps=%.0f draw_calls=%d objects=%d primitives=%d" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit(0)

## Self-test: walk the robot toward the sea from several spots and report whether it stayed on land.
func _edge_test() -> void:
	var starts := [[Vector3(5.0, TOP + 0.3, 9.0), KEY_S], [Vector3(-6.0, TOP + 0.3, 5.0), KEY_A],
		[Vector3(0.0, TOP + 0.3, -5.0), KEY_A], [Vector3(-20.0, TOP + 0.3, 0.0), KEY_W], [Vector3(18.0, TOP + 0.3, 3.0), KEY_D]]
	for s: Array in starts:
		player.call("teleport_to", s[0])
		for i in range(10):
			await get_tree().physics_frame
		var ev := InputEventKey.new()
		ev.keycode = s[1]
		ev.physical_keycode = s[1]
		ev.pressed = true
		Input.parse_input_event(ev)
		var jump := InputEventKey.new()
		jump.keycode = KEY_SPACE
		for i in range(240):
			if i % 40 == 0:
				jump.pressed = true
				player.call("_unhandled_input", jump)
			await get_tree().physics_frame
		ev.pressed = false
		Input.parse_input_event(ev)
		var p: Vector3 = player.global_position
		print("EDGETEST start=%s end=%s on_land=%s" % [str(s[0]), str(p.snapped(Vector3(0.01, 0.01, 0.01))), str(p.y > TOP - 0.2)])
	get_tree().quit(0)

# ============================================================================
# HELPERS
# ============================================================================

func _spawn(asset: String, pos: Vector3, rot_y: float = 0.0, scl: float = 1.0, solid: bool = false, parent: Node = null) -> Node3D:
	var host: Node = self if parent == null else parent
	var ps: PackedScene = load(ASSET_DIR + asset + ".tscn") as PackedScene
	var n: Node3D = null
	if ps != null:
		n = ps.instantiate() as Node3D
	if n == null:
		push_warning("Missing asset: " + asset)
		n = Node3D.new()
	n.name = asset
	n.position = pos
	n.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	n.scale = Vector3.ONE * scl
	host.add_child(n)
	if solid:
		_solid(n)
	return n

func _spawn_v(asset: String, pos: Vector3, rot_y: float, scl: Vector3) -> Node3D:
	var n := _spawn(asset, pos, rot_y, 1.0)
	n.scale = scl
	return n

## Local-space AABB of all meshes under `node` (node's own transform excluded)
func _local_aabb(node: Node3D) -> AABB:
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
	return box if found else AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 0.6, 0.6))

## Box collider matching a spawned prop's bounds (shrunk slightly so paths stay walkable)
func _solid(n: Node3D, shrink: float = 0.9) -> void:
	var bb := _local_aabb(n)
	var body := StaticBody3D.new()
	body.name = "Collider"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(bb.size.x * shrink, bb.size.y, bb.size.z * shrink)
	cs.shape = shape
	cs.position = bb.position + bb.size * 0.5
	body.add_child(cs)
	n.add_child(body)
	_reserve(Vector2(n.position.x, n.position.z), maxf(bb.size.x, bb.size.z) * n.scale.x * 0.6)

func _collider(center: Vector3, size: Vector3, rot_y: float = 0.0) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = center
	body.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	add_child(body)

func _reserve(p: Vector2, r: float) -> void:
	reserved.append([p, r])

func _is_free(p: Vector2, r: float) -> bool:
	for it: Array in reserved:
		var q: Vector2 = it[0]
		if q.distance_to(p) < r + float(it[1]):
			return false
	return true

func _on_island(p: Vector2) -> bool:
	var key := Vector2i(int(floor(p.x)), int(floor(p.y)))
	for k: String in island_cells.keys():
		if (island_cells[k] as Dictionary).has(key):
			return true
	return false

## Walks from `from` along `dir` until leaving the island; returns the last point on land.
func _edge_point(from: Vector2, dir: Vector2) -> Vector2:
	var p := from
	var d := dir.normalized()
	for i in range(200):
		var nx := p + d * 0.25
		if not _on_island(nx):
			return p
		p = nx
	return p

func _label3d(text: String, pos: Vector3, size: int = 40, color: Color = Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = 12
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	add_child(l)
	return l

func _path(pname: String, pts: Array, width: float = 1.4) -> void:
	WorldTerrain.paving(self, pname, pts, width, TOP)
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := int(a.distance_to(b) / 0.8) + 1
		for k in range(n + 1):
			_reserve(a.lerp(b, float(k) / float(n)), width * 0.5)

# ============================================================================
# ENVIRONMENT / OCEAN
# ============================================================================

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	# Sky and fog share the far-sea color: the ocean fades into it with no visible horizon line
	sky_mat.sky_top_color = SEA_FAR
	sky_mat.sky_horizon_color = SEA_FAR
	sky_mat.ground_horizon_color = SEA_FAR
	sky_mat.ground_bottom_color = SEA_FAR
	sky_mat.sun_angle_max = 0.0
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
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = SEA_FAR
	env.fog_light_energy = 1.0
	env.fog_density = 0.0045
	env.fog_sky_affect = 1.0
	env.fog_aerial_perspective = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.82, 0.98)
	fill.light_energy = 0.4
	add_child(fill)
	fill.rotation_degrees = Vector3(-35.0, 145.0, 0.0)

	# Web build uses the Compatibility (WebGL2) renderer, which lights the same scene much brighter
	# and has no SSAO - tone it down so it matches the desktop Forward+ look.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		env.ambient_light_energy = 0.5
		env.glow_enabled = false
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 0.8
		sun.light_energy = 0.95
		fill.light_energy = 0.25
		env.ssao_enabled = false
		sun.directional_shadow_max_distance = 60.0

func _build_ocean() -> void:
	var seabed := MeshInstance3D.new()
	var spm := PlaneMesh.new()
	spm.size = Vector2(OCEAN_SIZE * 1.1, OCEAN_SIZE * 1.1)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.06, 0.46, 0.55)
	smat.roughness = 0.9
	spm.material = smat
	seabed.mesh = spm
	seabed.position = Vector3(0.0, -1.2, -2.0)
	add_child(seabed)

	var ocean := MeshInstance3D.new()
	ocean.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(OCEAN_SIZE, OCEAN_SIZE)
	# Web/WebGL: far fewer ocean vertices (waves are subtle anyway) so slower GPUs start quickly
	var subdiv := 140 if OS.has_feature("web") else 560
	pm.subdivide_width = subdiv
	pm.subdivide_depth = subdiv
	var shader: Shader = load("res://shaders/ocean_water.gdshader") as Shader
	if shader != null:
		var sm := ShaderMaterial.new()
		sm.shader = shader
		pm.material = sm
	else:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.15, 0.7, 0.8, 0.8)
		fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.material = fallback
	ocean.mesh = pm
	ocean.position = Vector3(0.0, WATER_Y, -2.0)
	add_child(ocean)

# ============================================================================
# ISLANDS + BRIDGES
# ============================================================================

func _build_islands() -> void:
	for k: String in ISLANDS.keys():
		var def: Dictionary = ISLANDS[k]
		var cells := WorldTerrain.island_cells(def)
		island_cells[k] = cells
		WorldTerrain.build_island(self, "Island_" + k, cells, TOP, int(def["seed"]))

func _build_bridges() -> void:
	var main_w := _edge_point(Vector2(0.0, 0.0), Vector2(-1.0, 0.0))
	var main_e := _edge_point(Vector2(0.0, 0.0), Vector2(1.0, 0.0))
	var main_n := _edge_point(Vector2(0.0, 0.0), Vector2(0.0, -1.0))
	var ds_e := _edge_point(Vector2(-15.5, 0.0), Vector2(1.0, 0.0))
	var sql_w := _edge_point(Vector2(15.5, 0.0), Vector2(-1.0, 0.0))
	var algo_s := _edge_point(Vector2(0.0, -14.0), Vector2(0.0, 1.0))
	WorldTerrain.arch_bridge(self, "Bridge_DS", main_w + Vector2(0.4, 0.0), ds_e - Vector2(0.4, 0.0), 1.8, TOP)
	WorldTerrain.arch_bridge(self, "Bridge_SQL", main_e - Vector2(0.4, 0.0), sql_w + Vector2(0.4, 0.0), 1.8, TOP)
	WorldTerrain.arch_bridge(self, "Bridge_ALGO", main_n + Vector2(0.0, 0.4), algo_s - Vector2(0.0, 0.4), 1.8, TOP)

# ============================================================================
# MAIN ISLAND (front): crystal beacon, round plaza, village, quest board, market, pier
# ============================================================================

func _build_main_island() -> void:
	# paths first so props avoid them
	_path("Path_Main_W", [Vector2(-4.5, 0.0), Vector2(-1.3, 0.0)], 1.4)
	_path("Path_Main_E", [Vector2(1.3, 0.0), Vector2(4.5, 0.0)], 1.4)
	_path("Path_Main_N", [Vector2(0.0, -2.8), Vector2(0.0, -1.2)], 1.4)
	_path("Path_Main_Beacon", [Vector2(0.0, 1.2), Vector2(0.0, 2.4)], 1.4)
	_path("Path_Main_S", [Vector2(0.0, 6.6), Vector2(0.0, 12.2)], 1.4)
	_path("Path_Main_Village", [Vector2(-2.2, 4.3), Vector2(-4.4, 4.9)], 1.0)
	_path("Path_Main_Market", [Vector2(2.2, 4.3), Vector2(4.4, 5.2)], 1.0)

	var beacon := _spawn("OBJ03_crystal_beacon", Vector3(0.0, TOP, 0.0), 0.0, 1.05, true)
	beacon.name = "CrystalBeacon"
	var plaza := _spawn("OBJ06_round_plaza", Vector3(0.0, TOP, 4.4), 0.0, 1.55)
	plaza.name = "RoundPlaza"
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.1
	cyl.height = 0.5
	cs.shape = cyl
	body.add_child(cs)
	body.position = Vector3(0.0, TOP + 0.25, 4.4)
	add_child(body)
	_reserve(Vector2(0.0, 4.4), 2.3)

	_spawn("OBJ01_house_blue", Vector3(-5.3, TOP, 5.6), 25.0, 1.0, true)
	_spawn("OBJ02_cottage_blue", Vector3(-3.6, TOP, 2.2), 20.0, 1.0, true)
	_spawn("OBJ04_quest_board", Vector3(4.3, TOP, 2.9), -35.0, 1.0, true)
	_spawn("OBJ05_market_stall", Vector3(5.6, TOP, 6.4), -30.0, 1.0, true)
	_spawn("OBJ17_sign_main", Vector3(0.0, TOP, 8.0), 0.0, 1.0, false)
	_collider(Vector3(-0.85, TOP + 0.3, 8.0), Vector3(0.3, 0.6, 0.3))
	_collider(Vector3(0.85, TOP + 0.3, 8.0), Vector3(0.3, 0.6, 0.3))
	_reserve(Vector2(0.0, 8.0), 1.2)

	# fences around the village & lamps along the paths
	_spawn("26_fence_short", Vector3(-6.2, TOP, 7.6), 25.0)
	_spawn("27_fence_long_dark", Vector3(-3.4, TOP, 7.9), 10.0)
	_spawn("26_fence_short", Vector3(6.5, TOP, 8.4), -30.0)
	for lp: Vector3 in [Vector3(-1.1, TOP, 7.0), Vector3(1.1, TOP, 7.0), Vector3(-1.1, TOP, 10.6), Vector3(1.1, TOP, 10.6),
			Vector3(-2.6, TOP, -0.9), Vector3(2.6, TOP, -0.9)]:
		_spawn("06_lamp", lp, 0.0, 1.0, true)

	# south pier + boat + cargo
	var tip := _edge_point(Vector2(0.0, 8.0), Vector2(0.0, 1.0))
	WorldTerrain.pier(self, "MainPier", Vector2(0.0, tip.y + 1.3), Vector2(2.2, 2.8), TOP - 0.05)
	_spawn("05_boat", Vector3(-2.2, WATER_Y - 0.05, tip.y + 2.0), 75.0)
	_spawn("09_crate_brown", Vector3(0.65, TOP - 0.05, tip.y + 2.1), 15.0, 0.7, true)
	_spawn("10_crate_gold_top", Vector3(0.7, TOP - 0.05, tip.y + 1.3), -10.0, 0.6, true)
	_spawn("07_torch", Vector3(-0.85, TOP - 0.05, tip.y + 2.5), 0.0, 1.0, true)

# ============================================================================
# DATA-STRUCTURE ISLAND (west): ARRAY harbor, LIST nodes, STACK tower, QUEUE conveyor
# ============================================================================

func _build_ds_island() -> void:
	_path("Path_DS_Main", [Vector2(-8.4, 0.0), Vector2(-18.2, 0.0)], 1.4)
	_path("Path_DS_List", [Vector2(-13.0, 0.0), Vector2(-13.0, -4.3)], 1.2)
	_path("Path_DS_Queue", [Vector2(-11.0, 0.0), Vector2(-11.0, 1.9)], 1.0)

	# ARRAY: 5 index tiles in a row + crane + crates + harbor pier & boat
	for i in range(5):
		var t := _spawn("3%d_array_tile_%d" % [i + 1, i], Vector3(ARRAY_X, TOP, ARRAY_Z0 + 1.2 * float(i)), 90.0)
		array_tiles.append(t)
		var lbl := _label3d("", Vector3(ARRAY_X + 0.2, TOP + 1.6, ARRAY_Z0 + 1.2 * float(i)), 34, Color(1.0, 0.95, 0.7))
		array_labels.append(lbl)
		_collider(Vector3(ARRAY_X - 0.3, TOP + 0.5, ARRAY_Z0 + 1.2 * float(i)), Vector3(0.3, 1.0, 0.9))
		_reserve(Vector2(ARRAY_X, ARRAY_Z0 + 1.2 * float(i)), 0.7)
	_refresh_array_labels(-1)
	_spawn("49_sign_array_a", Vector3(-19.0, TOP, -6.2), 20.0, 0.9, true)
	array_crane = _spawn("08_crane", Vector3(-18.4, TOP, -4.3), 30.0, 1.0, true)
	var west := _edge_point(Vector2(-17.0, 2.2), Vector2(-1.0, 0.0))
	WorldTerrain.pier(self, "HarborPier", Vector2(west.x - 1.2, 2.2), Vector2(2.6, 2.2), TOP - 0.05)
	_spawn("05_boat", Vector3(west.x - 2.0, WATER_Y - 0.05, 4.0), 20.0)
	_spawn("09_crate_brown", Vector3(west.x - 0.7, TOP - 0.05, 1.6), 10.0, 0.7, true)
	_spawn("11_crate_gold_front", Vector3(west.x - 1.5, TOP - 0.05, 1.7), -15.0, 0.7, true)
	_spawn("10_crate_gold_top", Vector3(-19.6, TOP, 3.6), 5.0, 0.8, true)

	# LIST: three linked nodes on the north side
	var xs: Array[float] = [-15.5, -13.3, -11.1]
	for i in range(3):
		var nd := _spawn("3%d_list_node_%d0" % [7 + i, i + 1], Vector3(xs[i], TOP, -5.5), 0.0, 1.0, true)
		list_nodes.append(nd)
	_spawn_v("40_list_link_10_20", Vector3(-14.4, TOP, -5.5), 0.0, Vector3(1.9, 1.0, 1.2))
	_spawn_v("41_list_link_20_30", Vector3(-12.2, TOP, -5.5), 0.0, Vector3(1.9, 1.0, 1.2))
	_reserve(Vector2(-13.3, -5.5), 3.2)
	_spawn("51_sign_list", Vector3(-16.4, TOP, -7.0), 10.0, 0.9, true)
	_label3d("head", Vector3(-15.5, TOP + 1.2, -5.5), 32, Color(0.6, 0.95, 1.0))

	# STACK: elevator tower near the south shore
	stack_tower = _spawn("42_stack_tower", Vector3(-17.3, TOP, 2.6), 0.0)
	_collider(Vector3(-17.3, TOP + 1.3, 2.35), Vector3(1.7, 2.6, 1.3))
	_reserve(Vector2(-17.3, 2.6), 1.4)
	for i in range(3):
		var cr: Node3D = stack_tower.get_node_or_null("StackedCrate_%d" % i) as Node3D
		if cr != null:
			stack_crates.append(cr)
	stack_label = _label3d("", Vector3(-17.3, TOP + 3.6, 2.6), 40, Color(1.0, 0.95, 0.6))
	_update_stack_label()

	# QUEUE: conveyor line running +X under a gantry gate
	var conv: Array[String] = ["43_conveyor_arrow_up", "47_conveyor_gold_plate", "44_conveyor_arrow_down_a"]
	for i in range(conv.size()):
		_spawn(conv[i], Vector3(-14.4 + 1.72 * float(i), TOP, QUEUE_Z), 90.0)
	_collider(Vector3(-12.7, TOP + 0.17, QUEUE_Z), Vector3(5.2, 0.34, 1.0))
	_reserve(Vector2(-12.7, QUEUE_Z), 1.0)
	_reserve(Vector2(-14.4, QUEUE_Z), 1.0)
	_reserve(Vector2(-11.0, QUEUE_Z), 1.0)
	var gate: Node3D = ExtraAssets.build_gantry_gate()
	gate.position = Vector3(-12.7, TOP, QUEUE_Z)
	gate.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	add_child(gate)
	_collider(Vector3(-12.7, TOP + 0.9, QUEUE_Z - 0.85), Vector3(0.35, 1.8, 0.3))
	_collider(Vector3(-12.7, TOP + 0.9, QUEUE_Z + 0.85), Vector3(0.35, 1.8, 0.3))
	_spawn("53_sign_queue", Vector3(-12.7, TOP + 2.25, QUEUE_Z), 90.0, 0.85)
	queue_label = _label3d("", Vector3(-12.7, TOP + 3.5, QUEUE_Z), 40, Color(1.0, 0.95, 0.6))
	_update_queue_label()
	for i in range(3):
		_queue_enqueue(false)
		queue_crates[queue_crates.size() - 1].position.x = QUEUE_START_X + 1.6 * float(2 - i) + 0.2

	_spawn("OBJ18_sign_ds", Vector3(-15.2, TOP, 4.6), 0.0, 1.0, true)
	for lp: Vector3 in [Vector3(-9.6, TOP, -0.9), Vector3(-13.9, TOP, -0.9), Vector3(-17.5, TOP, -0.9)]:
		_spawn("06_lamp", lp, 0.0, 1.0, true)

func _refresh_array_labels(active: int) -> void:
	for i in range(array_labels.size()):
		array_labels[i].text = "arr[%d] = %d" % [i, array_values[i]]
		array_labels[i].modulate = Color(1.0, 0.9, 0.3) if i == active else Color(1.0, 1.0, 1.0, 0.85)

func _stack_slot_y(i: int) -> float:
	return 0.29 + float(i) * 0.505

func _update_stack_label() -> void:
	stack_label.text = "STACK  size = %d / %d" % [stack_crates.size(), STACK_CAP]

func _stack_push() -> void:
	if stack_crates.size() >= STACK_CAP:
		_show_msg("Stack Overflow! 더 쌓을 수 없어요 (Q: Pop)", 2.5)
		return
	var idx: int = stack_crates.size()
	var cr: Node3D = _spawn("09_crate_brown", Vector3(0.0, _stack_slot_y(idx) + 0.9, 2.0), 0.0, 0.76, false, stack_tower)
	stack_crates.append(cr)
	var tw: Tween = create_tween()
	tw.tween_property(cr, "position", Vector3(0.0, _stack_slot_y(idx), 0.18), 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_show_msg("PUSH → 맨 위에 쌓음 (size %d)" % stack_crates.size(), 2.0)
	_update_stack_label()

func _stack_pop() -> void:
	if stack_crates.is_empty():
		_show_msg("Stack Underflow! 꺼낼 박스가 없어요 (E: Push)", 2.5)
		return
	var cr: Node3D = stack_crates.pop_back()
	var tw: Tween = create_tween()
	tw.tween_property(cr, "position", cr.position + Vector3(0.0, 0.6, 2.2), 0.5).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(cr.queue_free)
	_show_msg("POP → 맨 위 박스부터 꺼냄 (LIFO, size %d)" % stack_crates.size(), 2.0)
	_update_stack_label()

func _update_queue_label() -> void:
	queue_label.text = "QUEUE  size = %d / %d   (front → exit)" % [queue_crates.size(), QUEUE_CAP]

func _queue_enqueue(announce: bool = true) -> void:
	if queue_crates.size() >= QUEUE_CAP:
		if announce:
			_show_msg("Queue Full! 벨트가 가득 찼어요", 2.0)
		return
	if not queue_crates.is_empty():
		var last: Node3D = queue_crates[queue_crates.size() - 1]
		if last.position.x < QUEUE_START_X + 0.9:
			if announce:
				_show_msg("조금 뒤에 다시 Enqueue 하세요 (간격 확보)", 1.5)
			return
	var cr: Node3D = _spawn("10_crate_gold_top", Vector3(QUEUE_START_X, TOP + 0.24, QUEUE_Z), 0.0, 0.7)
	queue_crates.append(cr)
	if announce:
		_show_msg("ENQUEUE → 뒤쪽 입구에 추가 (size %d)" % queue_crates.size(), 2.0)
	_update_queue_label()

func _queue_dequeue(manual: bool) -> void:
	if queue_crates.is_empty():
		if manual:
			_show_msg("Queue Empty! 꺼낼 박스가 없어요", 2.0)
		return
	var cr: Node3D = queue_crates.pop_front()
	var tw: Tween = create_tween()
	tw.tween_property(cr, "position", cr.position + Vector3(1.0, 0.8, 0.0), 0.4)
	tw.tween_callback(cr.queue_free)
	if manual:
		_show_msg("DEQUEUE → 가장 먼저 들어온 박스가 나감 (FIFO)", 2.0)
	_update_queue_label()

# ============================================================================
# ALGORITHM ISLAND (north): sort steps, graph courtyard, hedge maze
# ============================================================================

func _build_algo_island() -> void:
	_spawn("OBJ16_branch_path", Vector3(0.0, TOP - 0.12, -10.6), 0.0, 1.25)
	_reserve(Vector2(0.0, -10.6), 2.0)
	_path("Path_Algo_Sort", [Vector2(-1.4, -11.4), Vector2(-4.6, -12.4)], 1.0)
	_path("Path_Algo_Maze", [Vector2(1.4, -11.4), Vector2(4.4, -12.4)], 1.0)
	_path("Path_Algo_Graph", [Vector2(0.0, -11.6), Vector2(0.0, -12.6)], 1.2)

	sort_node = _spawn("OBJ12_sort_steps", Vector3(-5.6, TOP, -15.0), 10.0, 1.15, true)
	for i in range(6):
		var c := sort_node.get_node_or_null("Column_%d" % (i + 1)) as Node3D
		if c != null:
			sort_columns.append(c)

	# graph courtyard: 5 nodes (pentagon) + glowing edges
	var gc := Vector2(0.0, -14.6)
	var gr := 2.0
	MeshKit.add_part(self, "GraphCourt", MeshKit.beveled_cylinder(2.9, 2.9, 0.06, 28, 0.01, true),
		MeshKit.mat_color("graph_court", Color(0.86, 0.74, 0.58), 0.8, 0.0, "stone_ashlar"), Vector3(gc.x, TOP + 0.03, gc.y))
	_reserve(gc, 3.0)
	for k in range(5):
		var ang := -PI * 0.5 + TAU * float(k) / 5.0
		var p := Vector3(gc.x + cos(ang) * gr, TOP, gc.y + sin(ang) * gr * 0.85)
		graph_nodes.append(p)
		_spawn("OBJ13_graph_node", p, 0.0, 0.62, true)
	var edges := [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0], [0, 2]]
	for e: Array in edges:
		var a: Vector3 = graph_nodes[e[0]]
		var b: Vector3 = graph_nodes[e[1]]
		var mid := (a + b) * 0.5
		var d := b - a
		var dist := Vector2(d.x, d.z).length()
		var yaw := -rad_to_deg(atan2(d.z, d.x))
		_spawn_v("OBJ14_graph_edge", Vector3(mid.x, TOP + 0.08, mid.z), yaw, Vector3(dist / 2.4, 0.5, 0.5))

	_spawn("OBJ15_maze_garden", Vector3(5.8, TOP - 0.04, -15.0), -8.0, 1.35, false)
	_reserve(Vector2(5.8, -15.0), 2.2)
	_spawn("OBJ20_sign_algo", Vector3(0.0, TOP, -18.3), 0.0, 1.0, true)
	for lp: Vector3 in [Vector3(-1.1, TOP, -9.0), Vector3(1.1, TOP, -9.0)]:
		_spawn("06_lamp", lp, 0.0, 1.0, true)

# ============================================================================
# SQL ISLAND (east): database tower, archive hall, libraries, table platforms, query channel
# ============================================================================

func _build_sql_island() -> void:
	_path("Path_SQL_Main", [Vector2(8.4, 0.0), Vector2(12.0, 0.0), Vector2(15.4, -2.2)], 1.4)
	_path("Path_SQL_South", [Vector2(12.0, 0.0), Vector2(14.6, 3.2)], 1.2)

	_spawn("OBJ07_sql_database", Vector3(18.6, TOP, -3.6), 0.0, 1.25, true)
	_spawn("OBJ08_sql_archive", Vector3(13.4, TOP, -4.6), 10.0, 1.0, true)
	_spawn("OBJ09_sql_library", Vector3(20.8, TOP, 0.6), -70.0, 1.0, true)
	_spawn("OBJ09_sql_library", Vector3(10.6, TOP, -3.2), 40.0, 0.85, true)
	_spawn("OBJ10_sql_table", Vector3(12.6, TOP, 2.2), 0.0, 1.0, true)
	_spawn("OBJ10_sql_table", Vector3(18.4, TOP, 1.9), 15.0, 1.0, true)
	sql_query = _spawn("OBJ11_sql_query_y", Vector3(16.4, TOP, -0.8), 180.0, 1.0, false)
	_reserve(Vector2(16.4, -0.8), 1.3)
	_spawn("OBJ19_sign_sql", Vector3(15.6, TOP, 4.6), 0.0, 1.0, true)
	for lp: Vector3 in [Vector3(9.6, TOP, -0.9), Vector3(11.4, TOP, 0.9)]:
		_spawn("06_lamp", lp, 0.0, 1.0, true)

# ============================================================================
# NATURE: trees, waterfalls, rocks, lilies
# ============================================================================

func _build_nature() -> void:
	# waterfalls spilling off cliff edges (asset faces local +Z)
	var falls := [
		[Vector2(-5.0, 6.0), Vector2(0.0, 1.0)], [Vector2(5.0, 6.0), Vector2(0.0, 1.0)],
		[Vector2(-19.0, 0.0), Vector2(0.0, 1.0)], [Vector2(-4.0, -14.0), Vector2(0.0, 1.0)],
		[Vector2(4.5, -14.0), Vector2(0.0, 1.0)], [Vector2(20.0, -1.0), Vector2(1.0, 0.0)]
	]
	for f: Array in falls:
		var ep := _edge_point(f[0], f[1])
		var dir: Vector2 = f[1]
		var yaw := rad_to_deg(atan2(dir.x, dir.y))
		_spawn("17_waterfall", Vector3(ep.x + dir.x * 0.1, TOP - 0.75, ep.y + dir.y * 0.1), yaw, 1.0)

	# clipped hedge rows lining the main walkways
	var hedges := [
		[Vector3(-1.35, TOP, 9.6), 90.0, 2.2], [Vector3(1.35, TOP, 9.6), 90.0, 2.2],
		[Vector3(-11.0, TOP, -1.1), 0.0, 2.0], [Vector3(11.0, TOP, -1.1), 0.0, 2.0],
		[Vector3(-1.3, TOP, -10.0), 90.0, 1.4], [Vector3(1.3, TOP, -10.0), 90.0, 1.4]
	]
	for hd: Array in hedges:
		var hn: Node3D = ExtraAssets.build_hedge(float(hd[2]))
		hn.position = hd[0]
		hn.rotation_degrees = Vector3(0.0, float(hd[1]), 0.0)
		add_child(hn)
		_reserve(Vector2((hd[0] as Vector3).x, (hd[0] as Vector3).z), float(hd[2]) * 0.5)

	# trees on free cells (denser near island rims, like the reference map)
	var kinds: Array[String] = ["21_tree_short", "22_tree_tall", "21_tree_short"]
	for k: String in island_cells.keys():
		var cells: Dictionary = island_cells[k]
		var c: Vector2 = (ISLANDS[k] as Dictionary)["center"]
		for key: Vector2i in cells.keys():
			var p := Vector2(float(key.x) + 0.5, float(key.y) + 0.5)
			var h := MeshKit._hash_float(key.x, key.y, 97)
			var rim := 0
			for d: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
				if not cells.has(key + d):
					rim += 1
			var chance := 0.62 if rim > 0 else 0.16
			if h > chance:
				continue
			if not _is_free(p, 0.55):
				continue
			var kind := kinds[int(MeshKit._hash_float(key.x, key.y, 5) * 3.0) % 3]
			var s := 0.75 + MeshKit._hash_float(key.y, key.x, 9) * 0.4
			_spawn(kind, Vector3(p.x, TOP, p.y), h * 360.0, s)
			_collider(Vector3(p.x, TOP + 0.6, p.y), Vector3(0.35, 1.2, 0.35))
			_reserve(p, 0.6)

	# rocks & lily pads in the shallow water around each island
	var deco: Array[String] = ["18_lily_pad_top", "19_lily_pad_pair", "20_lily_flower"]
	var n := 0
	for k: String in ISLANDS.keys():
		var def: Dictionary = ISLANDS[k]
		var c: Vector2 = def["center"]
		for i in range(10):
			var ang := TAU * (float(i) + MeshKit._hash_float(i, n, 3)) / 10.0
			var r := Vector2(cos(ang) * (float(def["rx"]) + 1.4), sin(ang) * (float(def["rz"]) + 1.4))
			var p := c + r
			if _on_island(p):
				continue
			if i % 3 == 0:
				_spawn("16_rocks", Vector3(p.x, -0.25, p.y), ang * 57.0, 0.6)
			else:
				_spawn(deco[i % 3], Vector3(p.x, WATER_Y, p.y), ang * 80.0, 1.0)
		n += 1

# ============================================================================
# PLAYER + HUD
# ============================================================================

func _build_orb() -> void:
	orb = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.16
	sph.height = 0.32
	sph.material = MeshKit.mat_emissive("world_orb", Color(0.3, 0.95, 1.0), Color(0.15, 0.85, 1.0), 4.0, 0.1)
	orb.mesh = sph
	orb.visible = false
	add_child(orb)

func _build_player() -> void:
	var spawn := Vector3(0.0, TOP + 1.0, 4.4)
	player = PlayerRobot.new()
	player.name = "Robot"
	add_child(player)
	player.global_position = spawn
	player.set("spawn_point", spawn)
	player.set("last_safe", spawn)
	player.set("cam_dist", 13.0)
	player.connect("interact_pressed", Callable(self, "_on_interact"))
	player.connect("secondary_pressed", Callable(self, "_on_secondary"))
	player.connect("fell_in_water", Callable(self, "_on_fell"))

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	var root_ctrl := Control.new()
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root_ctrl)
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 24.0
	vb.offset_top = 16.0
	vb.offset_right = -24.0
	vb.offset_bottom = -16.0
	zone_label = _hud_label(30)
	vb.add_child(zone_label)
	msg_label = _hud_label(22)
	msg_label.modulate = Color(1.0, 0.95, 0.6)
	vb.add_child(msg_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spacer)
	prompt_label = _hud_label(24)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.modulate = Color(0.7, 1.0, 1.0)
	vb.add_child(prompt_label)
	fps_label = _hud_label(16)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.visible = false
	vb.add_child(fps_label)
	help_label = _hud_label(16)
	help_label.text = "WASD/방향키: 이동  |  Space: 점프  |  Shift: 달리기  |  E / Q: 상호작용  |  R: 메인 광장 복귀  |  V: 시점 전환  |  우클릭 드래그·휠: 카메라  |  Tab: 도움말 숨김  |  F3: FPS 표시"
	vb.add_child(help_label)

func _hud_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _show_msg(t: String, secs: float) -> void:
	msg_label.text = t
	_msg_time = secs

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == KEY_TAB:
			help_label.visible = not help_label.visible
		elif ek.pressed and not ek.echo and ek.keycode == KEY_F3:
			fps_label.visible = not fps_label.visible

# ============================================================================
# FRAME UPDATE
# ============================================================================

func _zone_of(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	if q.x < -8.0:
		var best := "ARRAY"
		var bd := 1e9
		for k: String in DS_ANCHORS.keys():
			var dd: float = (DS_ANCHORS[k] as Vector2).distance_to(q)
			if dd < bd:
				bd = dd
				best = k
		return best
	if q.x > 8.0:
		return "SQL"
	if q.y < -8.0:
		return "ALGO"
	return "MAIN"

func _process(delta: float) -> void:
	if player == null:
		return
	if fps_label.visible:
		fps_label.text = "FPS %d  |  draw calls %d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
	var pp: Vector3 = player.global_position
	var z: String = _zone_of(pp)
	_zone_name = z
	match z:
		"MAIN":
			zone_label.text = "메인 섬 — 수정 비콘 광장"
			prompt_label.text = "세 개의 다리를 건너 자료구조 섬(서) · 알고리즘 섬(북) · SQL 섬(동)을 탐험하세요"
		"ARRAY":
			zone_label.text = "자료구조 섬 · ARRAY 항구 — 인덱스로 즉시 접근 O(1)"
			prompt_label.text = "황금 타일 위에 서 보세요  |  [E] 크레인으로 두 칸 교환(swap)"
		"LIST":
			zone_label.text = "자료구조 섬 · LIST — 포인터로 연결된 노드"
			prompt_label.text = "[E] 포인터 따라가기 (head → 10 → 20 → 30)"
		"STACK":
			zone_label.text = "자료구조 섬 · STACK 타워 — LIFO"
			prompt_label.text = "[E] Push (쌓기)   [Q] Pop (꺼내기)"
		"QUEUE":
			zone_label.text = "자료구조 섬 · QUEUE 컨베이어 — FIFO"
			prompt_label.text = "[E] Enqueue (줄 서기)   [Q] Dequeue (먼저 온 박스 꺼내기)"
		"ALGO":
			zone_label.text = "알고리즘 섬 — 정렬 계단 · 그래프 광장 · 미로 정원"
			prompt_label.text = "[E] 그래프 BFS 탐색 보기   [Q] 정렬 계단 다시 쌓기"
		"SQL":
			zone_label.text = "SQL 섬 — 데이터베이스 탑 · 테이블 · 쿼리 수로"
			prompt_label.text = "[E] 쿼리 실행 (두 테이블 JOIN → 결과)"

	if _msg_time > 0.0:
		_msg_time -= delta
		if _msg_time <= 0.0:
			msg_label.text = ""

	# ARRAY tile pressing
	var active: int = -1
	for i in range(array_tiles.size()):
		var tz: float = ARRAY_Z0 + 1.2 * float(i)
		var pressed: bool = absf(pp.x - ARRAY_X) < 0.5 and absf(pp.z - tz) < 0.5 and pp.y < TOP + 0.8
		var tile: Node3D = array_tiles[i]
		var target_y: float = TOP - 0.09 if pressed else TOP
		tile.position.y = move_toward(tile.position.y, target_y, delta * 0.6)
		if pressed:
			active = i
	if active >= 0:
		_refresh_array_labels(active)
		_show_msg("arr[%d] = %d  (인덱스로 바로 접근!)" % [active, array_values[active]], 0.3)
	else:
		_refresh_array_labels(-1)

	# QUEUE conveyor (+X)
	_queue_timer -= delta
	if _queue_timer <= 0.0:
		_queue_timer = 3.5
		_queue_enqueue(false)
	for cr: Node3D in queue_crates:
		cr.position.x += delta * 0.8
	while not queue_crates.is_empty() and queue_crates[0].position.x >= QUEUE_END_X:
		_queue_dequeue(false)
		if _zone_name == "QUEUE":
			_show_msg("자동 DEQUEUE → 출구 도착 (FIFO)", 1.5)

# ============================================================================
# INTERACTIONS
# ============================================================================

func _on_interact() -> void:
	match _zone_name:
		"ARRAY":
			_array_swap()
		"LIST":
			_list_pulse()
		"STACK":
			_stack_push()
		"QUEUE":
			_queue_enqueue(true)
		"ALGO":
			_graph_bfs()
		"SQL":
			_sql_query()

func _on_secondary() -> void:
	match _zone_name:
		"STACK":
			_stack_pop()
		"QUEUE":
			_queue_dequeue(true)
		"ALGO":
			_sort_bounce()

func _array_swap() -> void:
	if _crane_busy:
		return
	_crane_busy = true
	var a: int = randi() % 5
	var b: int = (a + 1 + randi() % 4) % 5
	var tmp: int = array_values[a]
	array_values[a] = array_values[b]
	array_values[b] = tmp
	_refresh_array_labels(-1)
	_show_msg("swap(arr[%d], arr[%d]) → arr[%d]=%d, arr[%d]=%d" % [a, b, a, array_values[a], b, array_values[b]], 3.0)
	var base_y := array_crane.rotation_degrees.y
	var tw: Tween = create_tween()
	tw.tween_property(array_crane, "rotation_degrees:y", base_y + 45.0, 0.5)
	tw.tween_property(array_crane, "rotation_degrees:y", base_y - 30.0, 0.7)
	tw.tween_property(array_crane, "rotation_degrees:y", base_y, 0.5)
	tw.tween_callback(func() -> void: _crane_busy = false)

func _orb_path(points: Array, msgs: Array, step: float = 0.6) -> void:
	if _orb_busy or points.is_empty():
		return
	_orb_busy = true
	orb.visible = true
	orb.position = points[0]
	var tw: Tween = create_tween()
	if msgs.size() > 0:
		_show_msg(msgs[0], 1.2)
	for i in range(1, points.size()):
		var m: String = msgs[i] if i < msgs.size() else ""
		tw.tween_property(orb, "position", points[i], step)
		if m != "":
			tw.tween_callback(func() -> void: _show_msg(m, 1.4))
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		orb.visible = false
		_orb_busy = false)

func _list_pulse() -> void:
	if list_nodes.size() < 3:
		return
	var pts: Array = []
	for nd: Node3D in list_nodes:
		pts.append(nd.position + Vector3(0.0, 1.0, 0.0))
	_orb_path(pts, ["head → 노드 10", "10.next → 노드 20", "20.next → 노드 30 (30.next = null)"], 0.7)

func _graph_bfs() -> void:
	if graph_nodes.size() < 5:
		return
	# BFS from node 0 over edges 0-1, 0-4, 0-2, 1-2, 2-3, 3-4
	var order := [0, 1, 4, 2, 3]
	var pts: Array = []
	var msgs: Array = []
	for i in range(order.size()):
		pts.append(graph_nodes[order[i]] + Vector3(0.0, 0.9, 0.0))
		msgs.append("BFS 방문 %d번째: 노드 %d" % [i + 1, order[i]])
	msgs[msgs.size() - 1] = "BFS 완료: 0 → 1 → 4 → 2 → 3 (가까운 노드부터)"
	_orb_path(pts, msgs, 0.55)

func _sort_bounce() -> void:
	var tw: Tween = create_tween()
	for c: Node3D in sort_columns:
		tw.tween_property(c, "position:y", 0.25, 0.12)
		tw.tween_property(c, "position:y", 0.0, 0.12)
	_show_msg("정렬 완료! 작은 값 → 큰 값 (오름차순)", 2.0)

func _sql_query() -> void:
	if sql_query == null:
		return
	var o := sql_query.position
	var pts := [o + Vector3(-0.85, 0.45, 0.5), o + Vector3(0.0, 0.45, 0.0), o + Vector3(0.0, 0.45, -0.95)]
	_orb_path(pts, ["SELECT * FROM 학생", "JOIN 수강 ON 학생.id = 수강.학생id", "결과 행이 합류 수로로 흘러나옵니다"], 0.8)

func _on_fell(pos: Vector3) -> void:
	_show_msg("풍덩! 마지막 안전 지점으로 돌아갑니다", 2.0)
	for i in range(8):
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		sm.material = MeshKit.mat_emissive("splash", Color(0.9, 1.0, 1.0), Color(0.7, 0.95, 1.0), 0.8, 0.3)
		s.mesh = sm
		s.position = Vector3(pos.x, WATER_Y, pos.z)
		add_child(s)
		var ang: float = TAU * float(i) / 8.0
		var tw: Tween = create_tween()
		tw.tween_property(s, "position", s.position + Vector3(cos(ang) * 0.6, 0.8, sin(ang) * 0.6), 0.35)
		tw.tween_property(s, "position:y", WATER_Y, 0.25)
		tw.tween_callback(s.queue_free)

# ============================================================================
# OVERVIEW CAPTURE (`-- --capture`)
# ============================================================================

func _capture_overview() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud:
		hud.visible = false
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.far = 1500.0
	add_child(cam)
	var shots := [
		["world_overview.png", Vector3(0.0, 36.0, 34.0), Vector3(0.0, 0.0, -3.0)],
		["world_overview_iso.png", Vector3(30.0, 30.0, 32.0), Vector3(0.0, 0.0, -3.0)],
		["world_main_island.png", Vector3(0.0, 11.0, 17.0), Vector3(0.0, 0.5, 3.5)],
		["world_ds_island.png", Vector3(-9.0, 11.0, 9.5), Vector3(-15.5, 0.5, -1.0)],
		["world_algo_island.png", Vector3(0.0, 11.0, -2.0), Vector3(0.0, 0.5, -14.0)],
		["world_sql_island.png", Vector3(21.0, 11.0, 9.5), Vector3(15.5, 0.5, -1.0)],
		# lowest allowed player camera (pitch 15 deg, max zoom-out 30) - horizon must not show
		["world_low_angle_15deg.png", Vector3(0.0, 1.6, 4.4) + Vector3(0.683, 0.259, 0.683) * 30.0, Vector3(0.0, 1.6, 4.4)]
	]
	var out_dir := ProjectSettings.globalize_path("res://renders")
	for s: Array in shots:
		cam.look_at_from_position(s[1], s[2], Vector3.UP)
		cam.current = true
		for i in range(6):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s" % [out_dir, s[0]])
		print("Saved ", s[0])
	get_tree().quit(0)

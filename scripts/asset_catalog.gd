class_name AssetCatalog
extends RefCounted

## Complete registry of all 70 modular 3D models:
##  - sample-assets/ 53 source PNGs (01-53) -> 50 models
##    (01_robot_front, 02_robot_side, 03_robot_back, 04_robot_back_side -> 01_robot)
##  - objects/ 20 source PNGs (OBJ01-OBJ20) -> 20 models

static func get_entries() -> Array[Dictionary]:
	return [
		# Category 1: Character & Harbor Props (01-11)
		{"id": "01_robot", "kr": "로봇 (4방향 통합 3D)", "cat": "Props", "src": "01_robot_front.png", "build": func(): return BuilderCharsProps.build_robot()},
		{"id": "05_boat", "kr": "나무 배", "cat": "Props", "src": "05_boat.png", "build": func(): return BuilderCharsProps.build_boat()},
		{"id": "06_lamp", "kr": "가로등", "cat": "Props", "src": "06_lamp.png", "build": func(): return BuilderCharsProps.build_lamp()},
		{"id": "07_torch", "kr": "횃불", "cat": "Props", "src": "07_torch.png", "build": func(): return BuilderCharsProps.build_torch()},
		{"id": "08_crane", "kr": "크레인", "cat": "Props", "src": "08_crane.png", "build": func(): return BuilderCharsProps.build_crane()},
		{"id": "09_crate_brown", "kr": "갈색 상자", "cat": "Props", "src": "09_crate_brown.png", "build": func(): return BuilderCharsProps.build_crate("brown")},
		{"id": "10_crate_gold_top", "kr": "노란 상자 A", "cat": "Props", "src": "10_crate_gold_top.png", "build": func(): return BuilderCharsProps.build_crate("gold_top")},
		{"id": "11_crate_gold_front", "kr": "노란 상자 B", "cat": "Props", "src": "11_crate_gold_front.png", "build": func(): return BuilderCharsProps.build_crate("gold_front")},

		# Category 2: Terrain & Nature (12-22)
		{"id": "12_ground_grass_studs", "kr": "돌기 잔디 블록", "cat": "Terrain", "src": "12_ground_grass_studs.png", "build": func(): return BuilderTerrainNature.build_ground_block("grass_studs")},
		{"id": "13_ground_grass_flat", "kr": "평평한 잔디 블록", "cat": "Terrain", "src": "13_ground_grass_flat.png", "build": func(): return BuilderTerrainNature.build_ground_block("grass_flat")},
		{"id": "14_ground_stone", "kr": "돌바닥 블록", "cat": "Terrain", "src": "14_ground_stone.png", "build": func(): return BuilderTerrainNature.build_ground_block("stone")},
		{"id": "15_plaza_half", "kr": "반원 광장", "cat": "Terrain", "src": "15_plaza_half.png", "build": func(): return BuilderTerrainNature.build_plaza_half()},
		{"id": "16_rocks", "kr": "바위 더미", "cat": "Terrain", "src": "16_rocks.png", "build": func(): return BuilderTerrainNature.build_rocks()},
		{"id": "17_waterfall", "kr": "폭포 모듈", "cat": "Terrain", "src": "17_waterfall.png", "build": func(): return BuilderTerrainNature.build_waterfall()},
		{"id": "18_lily_pad_top", "kr": "수련 잎 A", "cat": "Terrain", "src": "18_lily_pad_top.png", "build": func(): return BuilderTerrainNature.build_lily_pad_single()},
		{"id": "19_lily_pad_pair", "kr": "수련 잎 B·C", "cat": "Terrain", "src": "19_lily_pad_pair.png", "build": func(): return BuilderTerrainNature.build_lily_pad_pair()},
		{"id": "20_lily_flower", "kr": "수련 꽃", "cat": "Terrain", "src": "20_lily_flower.png", "build": func(): return BuilderTerrainNature.build_lily_flower()},
		{"id": "21_tree_short", "kr": "작은 나무", "cat": "Terrain", "src": "21_tree_short.png", "build": func(): return BuilderTerrainNature.build_tree(false)},
		{"id": "22_tree_tall", "kr": "큰 나무", "cat": "Terrain", "src": "22_tree_tall.png", "build": func(): return BuilderTerrainNature.build_tree(true)},

		# Category 3: Bridges, Docks, Fences, Stairs (23-30)
		{"id": "23_bridge_arch", "kr": "아치형 돌다리", "cat": "Structures", "src": "23_bridge_arch.png", "build": func(): return BuilderStructures.build_bridge(false)},
		{"id": "24_bridge_solid", "kr": "직선 돌다리", "cat": "Structures", "src": "24_bridge_solid.png", "build": func(): return BuilderStructures.build_bridge(true)},
		{"id": "25_dock_cluster", "kr": "목재 부두 모듈 묶음", "cat": "Structures", "src": "25_dock_cluster.png", "build": func(): return BuilderStructures.build_dock_cluster()},
		{"id": "26_fence_short", "kr": "짧은 울타리", "cat": "Structures", "src": "26_fence_short.png", "build": func(): return BuilderStructures.build_fence("short")},
		{"id": "27_fence_long_dark", "kr": "긴 울타리 A", "cat": "Structures", "src": "27_fence_long_dark.png", "build": func(): return BuilderStructures.build_fence("long_dark")},
		{"id": "28_fence_long_light", "kr": "긴 울타리 B", "cat": "Structures", "src": "28_fence_long_light.png", "build": func(): return BuilderStructures.build_fence("long_light")},
		{"id": "29_fence_long_brown", "kr": "긴 울타리 C", "cat": "Structures", "src": "29_fence_long_brown.png", "build": func(): return BuilderStructures.build_fence("long_brown")},
		{"id": "30_stairs", "kr": "돌계단", "cat": "Structures", "src": "30_stairs.png", "build": func(): return BuilderStructures.build_stairs()},

		# Category 4: Data Structure Modules - Array, List, Stack, Queue (31-48)
		{"id": "31_array_tile_0", "kr": "배열 타일 0", "cat": "DataStructs", "src": "31_array_tile_0.png", "build": func(): return BuilderDataStructs.build_array_tile(0)},
		{"id": "32_array_tile_1", "kr": "배열 타일 1", "cat": "DataStructs", "src": "32_array_tile_1.png", "build": func(): return BuilderDataStructs.build_array_tile(1)},
		{"id": "33_array_tile_2", "kr": "배열 타일 2", "cat": "DataStructs", "src": "33_array_tile_2.png", "build": func(): return BuilderDataStructs.build_array_tile(2)},
		{"id": "34_array_tile_3", "kr": "배열 타일 3", "cat": "DataStructs", "src": "34_array_tile_3.png", "build": func(): return BuilderDataStructs.build_array_tile(3)},
		{"id": "35_array_tile_4", "kr": "배열 타일 4", "cat": "DataStructs", "src": "35_array_tile_4.png", "build": func(): return BuilderDataStructs.build_array_tile(4)},
		{"id": "36_list_sign_floating", "kr": "LIST 상단 표지판", "cat": "Signs", "src": "36_list_sign_floating.png", "build": func(): return BuilderDataStructs.build_list_sign_floating()},
		{"id": "37_list_node_10", "kr": "노드 10", "cat": "DataStructs", "src": "37_list_node_10.png", "build": func(): return BuilderDataStructs.build_list_node(10)},
		{"id": "38_list_node_20", "kr": "노드 20", "cat": "DataStructs", "src": "38_list_node_20.png", "build": func(): return BuilderDataStructs.build_list_node(20)},
		{"id": "39_list_node_30", "kr": "노드 30", "cat": "DataStructs", "src": "39_list_node_30.png", "build": func(): return BuilderDataStructs.build_list_node(30)},
		{"id": "40_list_link_10_20", "kr": "연결 화살표 10→20", "cat": "DataStructs", "src": "40_list_link_10_20.png", "build": func(): return BuilderDataStructs.build_list_link(false)},
		{"id": "41_list_link_20_30", "kr": "연결 화살표 20→30", "cat": "DataStructs", "src": "41_list_link_20_30.png", "build": func(): return BuilderDataStructs.build_list_link(true)},
		{"id": "42_stack_tower", "kr": "STACK 탑", "cat": "DataStructs", "src": "42_stack_tower.png", "build": func(): return BuilderDataStructs.build_stack_tower()},
		{"id": "43_conveyor_arrow_up", "kr": "컨베이어 위쪽 화살표", "cat": "DataStructs", "src": "43_conveyor_arrow_up.png", "build": func(): return BuilderDataStructs.build_conveyor("arrow_up")},
		{"id": "44_conveyor_arrow_down_a", "kr": "컨베이어 아래쪽 화살표 A", "cat": "DataStructs", "src": "44_conveyor_arrow_down_a.png", "build": func(): return BuilderDataStructs.build_conveyor("arrow_down_a")},
		{"id": "45_conveyor_arrow_down_b", "kr": "컨베이어 아래쪽 화살표 B", "cat": "DataStructs", "src": "45_conveyor_arrow_down_b.png", "build": func(): return BuilderDataStructs.build_conveyor("arrow_down_b")},
		{"id": "46_conveyor_two_buttons", "kr": "컨베이어 버튼 2개", "cat": "DataStructs", "src": "46_conveyor_two_buttons.png", "build": func(): return BuilderDataStructs.build_conveyor("two_buttons")},
		{"id": "47_conveyor_gold_plate", "kr": "컨베이어 금색 발판", "cat": "DataStructs", "src": "47_conveyor_gold_plate.png", "build": func(): return BuilderDataStructs.build_conveyor("gold_plate")},
		{"id": "48_conveyor_crates", "kr": "컨베이어 상자 2개", "cat": "DataStructs", "src": "48_conveyor_crates.png", "build": func(): return BuilderDataStructs.build_conveyor("crates")},

		# Category 5: Standing Signs (49-53)
		{"id": "49_sign_array_a", "kr": "ARRAY 표지판 A", "cat": "Signs", "src": "49_sign_array_a.png", "build": func(): return BuilderDataStructs.build_standing_sign("ARRAY", false)},
		{"id": "50_sign_array_b", "kr": "ARRAY 표지판 B", "cat": "Signs", "src": "50_sign_array_b.png", "build": func(): return BuilderDataStructs.build_standing_sign("ARRAY", true)},
		{"id": "51_sign_list", "kr": "LIST 표지판", "cat": "Signs", "src": "51_sign_list.png", "build": func(): return BuilderDataStructs.build_standing_sign("LIST", false)},
		{"id": "52_sign_stack", "kr": "STACK 표지판", "cat": "Signs", "src": "52_sign_stack.png", "build": func(): return BuilderDataStructs.build_standing_sign("STACK", false)},
		{"id": "53_sign_queue", "kr": "QUEUE 표지판", "cat": "Signs", "src": "53_sign_queue.png", "build": func(): return BuilderDataStructs.build_standing_sign("QUEUE", false)},

		# ====================================================================
		# NODEVERSE 연결섬 objects/ (OBJ01-OBJ20) - 신규 20종
		# ====================================================================
		# Category 6: Main-island village (OBJ01-06)
		{"id": "OBJ01_house_blue", "kr": "파란 지붕 주택", "cat": "Village", "src": "objects/OBJ01_house_blue.png", "build": func(): return BuilderVillage.build_house_blue()},
		{"id": "OBJ02_cottage_blue", "kr": "파란 지붕 작은집", "cat": "Village", "src": "objects/OBJ02_cottage_blue.png", "build": func(): return BuilderVillage.build_cottage_blue()},
		{"id": "OBJ03_crystal_beacon", "kr": "중앙 수정 비콘", "cat": "Village", "src": "objects/OBJ03_crystal_beacon.png", "build": func(): return BuilderVillage.build_crystal_beacon()},
		{"id": "OBJ04_quest_board", "kr": "퀘스트 게시판", "cat": "Village", "src": "objects/OBJ04_quest_board.png", "build": func(): return BuilderVillage.build_quest_board()},
		{"id": "OBJ05_market_stall", "kr": "시장 가판대", "cat": "Village", "src": "objects/OBJ05_market_stall.png", "build": func(): return BuilderVillage.build_market_stall()},
		{"id": "OBJ06_round_plaza", "kr": "원형 광장", "cat": "Village", "src": "objects/OBJ06_round_plaza.png", "build": func(): return BuilderVillage.build_round_plaza()},

		# Category 7: SQL island (OBJ07-11)
		{"id": "OBJ07_sql_database", "kr": "SQL 데이터베이스 탑", "cat": "SQL", "src": "objects/OBJ07_sql_database.png", "build": func(): return BuilderSQL.build_sql_database()},
		{"id": "OBJ08_sql_archive", "kr": "SQL 기록 보관소", "cat": "SQL", "src": "objects/OBJ08_sql_archive.png", "build": func(): return BuilderSQL.build_sql_archive()},
		{"id": "OBJ09_sql_library", "kr": "SQL 작은 도서관", "cat": "SQL", "src": "objects/OBJ09_sql_library.png", "build": func(): return BuilderSQL.build_sql_library()},
		{"id": "OBJ10_sql_table", "kr": "SQL 테이블 플랫폼", "cat": "SQL", "src": "objects/OBJ10_sql_table.png", "build": func(): return BuilderSQL.build_sql_table()},
		{"id": "OBJ11_sql_query_y", "kr": "SQL 합류 수로", "cat": "SQL", "src": "objects/OBJ11_sql_query_y.png", "build": func(): return BuilderSQL.build_sql_query_y()},

		# Category 8: Algorithm island (OBJ12-16)
		{"id": "OBJ12_sort_steps", "kr": "정렬 계단", "cat": "Algorithm", "src": "objects/OBJ12_sort_steps.png", "build": func(): return BuilderAlgorithm.build_sort_steps()},
		{"id": "OBJ13_graph_node", "kr": "그래프 노드", "cat": "Algorithm", "src": "objects/OBJ13_graph_node.png", "build": func(): return BuilderAlgorithm.build_graph_node()},
		{"id": "OBJ14_graph_edge", "kr": "그래프 연결선", "cat": "Algorithm", "src": "objects/OBJ14_graph_edge.png", "build": func(): return BuilderAlgorithm.build_graph_edge()},
		{"id": "OBJ15_maze_garden", "kr": "미로 정원", "cat": "Algorithm", "src": "objects/OBJ15_maze_garden.png", "build": func(): return BuilderAlgorithm.build_maze_garden()},
		{"id": "OBJ16_branch_path", "kr": "분기 경로 모듈", "cat": "Algorithm", "src": "objects/OBJ16_branch_path.png", "build": func(): return BuilderAlgorithm.build_branch_path()},

		# Category 9: Major-island signs (OBJ17-20)
		{"id": "OBJ17_sign_main", "kr": "메인 섬 표지판", "cat": "IslandSigns", "src": "objects/OBJ17_sign_main.png", "build": func(): return BuilderIslandSigns.build_island_sign("메인 섬")},
		{"id": "OBJ18_sign_ds", "kr": "자료구조 섬 표지판", "cat": "IslandSigns", "src": "objects/OBJ18_sign_ds.png", "build": func(): return BuilderIslandSigns.build_island_sign("자료구조 섬")},
		{"id": "OBJ19_sign_sql", "kr": "SQL 섬 표지판", "cat": "IslandSigns", "src": "objects/OBJ19_sign_sql.png", "build": func(): return BuilderIslandSigns.build_island_sign("SQL 섬")},
		{"id": "OBJ20_sign_algo", "kr": "알고리즘 섬 표지판", "cat": "IslandSigns", "src": "objects/OBJ20_sign_algo.png", "build": func(): return BuilderIslandSigns.build_island_sign("알고리즘 섬")}
	]

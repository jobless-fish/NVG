# NODEVERSE 연결섬 — Godot 4.7 3D 프로젝트

`reference/NODEVERSE_연결섬_전체지도.png`를 기준으로 4개 섬을 다리로 연결한 플레이 가능한 3D 월드와,
그 월드를 구성하는 모듈형 3D 에셋 70종(GLB + TSCN)을 담은 프로젝트입니다.

- 월드 실행: `play_game.bat` (메인 씬 `scenes/NodeverseWorld.tscn`)
- 에셋 갤러리: `open_showcase.bat` (`scenes/AssetShowcase.tscn`)
- 에디터: `open_editor.bat`

## 월드 구성 (`scripts/nodeverse_world.gd`)

```
                [알고리즘 섬]  정렬 계단 · 그래프 광장(노드 5 + 연결선) · 미로 정원 · 분기 경로
                      |
 [자료구조 섬] —— [메인 섬] —— [SQL 섬]
 ARRAY 항구·크레인     수정 비콘 · 원형 광장(로봇 시작점)       데이터베이스 탑 · 기록 보관소
 LIST 노드 10→20→30   파란 지붕 주택/작은집 · 게시판 · 가판대   작은 도서관 ×2 · 테이블 ×2 · 합류 수로
 STACK 탑 · QUEUE 벨트  남쪽 부두 + 나무 배
```

| 섬 | 조작 |
|---|---|
| 메인 섬 | 세 방향 아치 다리로 이동 |
| 자료구조 섬 | ARRAY 타일 밟기 / E 교환, LIST E 포인터 따라가기, STACK E Push·Q Pop, QUEUE E Enqueue·Q Dequeue |
| 알고리즘 섬 | E 그래프 BFS 탐색, Q 정렬 계단 |
| SQL 섬 | E 쿼리 실행(JOIN 흐름) |

공통: WASD 이동, Space 점프, Shift 달리기, R 메인 광장 복귀, V 시점 전환, 우클릭 드래그·휠 카메라.

- 물에 빠지지 않음: `player_robot.gd`가 이동 방향 앞쪽(0.35m)에 땅(섬·다리·부두)이 있는지 검사해 바다 쪽 이동을 막습니다. 해안선을 따라 미끄러지듯 이동은 가능합니다. (`-- --edgetest`로 자동 점검)
- 카메라 각도: 최소 15° ~ 최대 80° (`CAM_MIN_PITCH`).
- 바다: 1400m 평면 + 하늘·안개를 먼 바다색과 같게 맞춰 수평선 경계가 보이지 않습니다 (`SEA_FAR`, `OCEAN_SIZE`).

섬 지형은 `scripts/builders/builder_world_terrain.gd`(WorldTerrain)가 1m 블록 셀로 생성합니다
(잔디 상판 + 흙 절벽 + 해안 바위, 충돌 포함). 섬 위치·크기는 `nodeverse_world.gd`의 `ISLANDS` 상수에서 조정합니다.

## 폴더 구조

```
godot_project/
├─ scenes/NodeverseWorld.tscn   연결섬 월드 (메인 씬)
├─ scenes/AssetShowcase.tscn    에셋 70종 갤러리
├─ scenes/assets/               에셋 프리팹 .tscn (01~53, OBJ01~OBJ20)
├─ models_glb/                  범용 glTF 2.0 (Blender·Unity 등)
├─ scripts/
│  ├─ nodeverse_world.gd        월드 조립 + 게임플레이
│  ├─ player_robot.gd           플레이어 로봇
│  ├─ asset_catalog.gd          에셋 70종 목록 (id, 한글명, 원본, 빌더)
│  ├─ generate_all_assets.gd    에셋 생성기 (GLB + TSCN + 쇼케이스)
│  └─ builders/                 에셋 빌더 + obj_kit.gd + builder_world_terrain.gd
├─ renders/                     에셋 미리보기, 비교 시트, world_*.png 월드 스크린샷
├─ reference/                   2D 원본 (전체지도, sample-assets 53종, objects 20종, 프롬프트) — Godot import 제외(.gdignore)
├─ shaders/ textures/
└─ tools/make_object_comparison.py   원본 vs 3D 비교 시트 생성
```

## 에셋

| 원본 | 모델 | 빌더 |
|---|---|---|
| `reference/sample-assets` 53종 | `01_robot` ~ `53_sign_queue` (50종) | `builder_chars_props / terrain_nature / structures / data_structs` |
| `reference/objects` 20종 | `OBJ01_house_blue` ~ `OBJ20_sign_algo` (20종) | `builder_village / sql / algorithm / island_signs` |

모든 에셋은 바닥 Y=0, 정면 +Z, 약 1m 단위입니다. 한글 표지판 글자는 생성 시 맑은 고딕 Bold로 메시화되어 GLB에 포함됩니다.

## 다시 생성하기 (godot_project 폴더에서)

```bash
# 새 스크립트 클래스를 추가했다면 먼저 한 번
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
# 에셋 전체 70종 + 쇼케이스
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/generate_all_assets.gd
# objects 20종만
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/generate_all_assets.gd -- --only=OBJ
# 에셋 미리보기 렌더
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 640x640 res://scenes/PreviewRenderer.tscn -- --only=OBJ
# 월드 스크린샷 (renders/world_*.png)
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 res://scenes/NodeverseWorld.tscn -- --capture
# 비교 시트
python tools/make_object_comparison.py
```

## 웹 빌드

- 결과물: `build/web/` (index.html + index.wasm + index.pck, 약 85MB)
- 로컬 실행: `serve_web.bat`(= `python tools/serve_web.py`) → 브라우저에서 http://localhost:8060 (file://로 직접 열면 동작하지 않음).
  캐시를 끄고 서빙하므로 다시 빌드해도 예전 파일과 섞이지 않습니다. 로딩이 멈추면 Ctrl+F5로 강력 새로고침하세요.
- 웹에서는 바다 정점 수·그림자 해상도·MSAA를 낮춰 느린 GPU에서도 빨리 시작하게 했습니다.
- 다시 빌드: `Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" build/web/index.html`
- 설정: `export_presets.cfg`의 "Web" 프리셋 (스레드 미사용 → 특별한 서버 헤더 없이 일반 웹호스팅에 올려도 동작),
  웹은 Compatibility(WebGL2) 렌더러를 쓰므로 `nodeverse_world.gd`에서 조명을 자동 보정합니다.
- 한글 UI는 `fonts/NotoSansKR-VF.ttf`(SIL Open Font License)를 프로젝트 기본 폰트로 사용합니다.
- 내보내기 템플릿: `%APPDATA%\Godot\export_templates\4.7.2.stable\` (웹 템플릿만 설치됨)

## 백업

`../_archive/` — `godot_project_before_merge_20261104`(통합 전 이 프로젝트), `asset-modeling_20261104`(이전 작업 폴더).

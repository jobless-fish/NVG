# NODEVERSE 파이프라인 (v2, 2026-11-16)

[Git 공유 범위·최신 게임 확인·인수 절차](docs/GIT_HANDOFF.md)를 먼저 읽어 주세요.

게임 이벤트 → 수집 API(`POST /v2/events`) → Kafka 브로커 3대 → Spark → Delta Lake(Bronze·Silver·Gold) → MongoDB(`nodeverse_logs`)의 실시간 컬렉션까지 이어지는 파이프라인입니다. 기준 문서는 「NODEVERSE 파이프라인 파트 구현 지시서」(공통 계약 포함)이고, 지시서와 다르게 정한 부분은 [docs/DECISIONS.md](docs/DECISIONS.md)에 있습니다. 옛 v1 코드는 `_backup/`에 있습니다.

## 인수인계 및 현재 연결 상태

[변경 사항·게임/서버 연동 기준·남은 작업](docs/INTEGRATION_STATUS.md)을 먼저 확인하세요.
현재 v2는 기존 NVG의 원격 MySQL/MongoDB 직접 적재 및 :8010 대시보드를 포함하지 않습니다.
읽기 전용 사전 점검: `python check.py` (실제 키 값 출력 및 시험 이벤트 전송 없음).

## 실제 시험·보완 결과

[2026-11-20 실제 서비스 시험 보고서](docs/E2E_TEST_REPORT_2026-11-20.md)를 참고하세요.
실제 시험 송신기: `python e2e_test.py` (시험 데이터를 생성·전송합니다).

## 5개 기술 항목 점검

[Kafka·Streaming·복구·Delta·성능 점검 기록](docs/TECHNICAL_REVIEW.md)을 참고하세요.
Silver는 이벤트 내용을 덮어쓰지 않는 insert-only MERGE로 보완했습니다.
OPTIMIZE/ZORDER는 `spark/maintain.py`로 스트리밍 쓰기를 중지한 정비 시간에 실행합니다.

## 구성

| 파일 | 역할 | 지시서 |
|---|---|---|
| `topics.py`, `build_compose.py` → `compose.json` | 토픽 5개(파티션 6/3/3/3/3, 보관 7일, 복제 3·min ISR 2), 서비스 정의 | P1 |
| `contract.py`, `collector.py`, `Dockerfile` | `/v2/events` 검사·분류·Kafka 접수 후 202, 422 + DLQ, `/v1/events`(런처 실행 이벤트) | P1, P4-2 |
| `Dockerfile.spark`, `spark/tables.py`, `spark/delta_stream.py` | Bronze append, Silver 상태 저장소 중복 제거·격리, Gold 윈도 집계, MongoDB upsert | P2, P3, P4, P4-2 |
| `simulator.py` | v2 이벤트 생성기(스모크, 계약 점검, 업데이트, 부하) | P6 |
| `spark/verify.py`, `spark/probe_latency.py` | 행 수 대조, 소비 지연, 히스토리·타임 트래블, 15초 지연 측정 | P6 |
| `launcher.py`, `build_launcher.cmd` | 실행 런처(v2 송신, `NODEVERSE_PLAYER_ID` 전달) → launcher.exe | P5 |
| `docs/DEMO_SCRIPT.md` | 강제 종료·타임 트래블 발표 시연 대본 | P6 |

Delta 테이블(`/data/delta`, 볼륨 `lake`): `bronze.game_events`, `silver.learning_events`, `silver.update_events`, `silver.quarantine`, `gold.minigame_1m`, `gold.failure_alerts`, `gold.update_progress_5m`, `gold.version_adoption`.
MongoDB 컬렉션: `rt_minigame_1m`, `rt_alerts`, `rt_summary`, `rt_updates`, `rt_versions` (쓰는 쪽은 Spark뿐, 모두 `_id` upsert).

## 실행

Docker Desktop(Linux 엔진)을 켜고 이 폴더에서 PowerShell로 실행합니다. 아래 예시는 기존 서비스와 충돌하지 않는 로컬 시험 프로젝트(8002/27019)를 사용합니다. 첫 실행에는 이미지와 Spark 패키지를 받기 위해 인터넷이 필요합니다.

```powershell
# 1) 키 설정: .env의 INGEST_KEY를 24자 이상 임의 값으로 바꿉니다 (.env.example 참고)
# 2) compose.json을 바꿨다면 다시 생성 (python만 있으면 됨)
python build_compose.py
# 3) 별도 시험 프로젝트 시작 (기존 pipeline/nodeverse-dev는 중지하거나 삭제하지 않음)
docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json up -d --build
docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json ps
docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json logs -f spark      # "started queries: [...]" 확인
```

현재 시험 API는 `http://127.0.0.1:8002`, MongoDB는 `mongodb://127.0.0.1:27019/nodeverse_logs`입니다. `review.env`가 `.env`의 바인딩/포트를 덮어씁니다. 다른 PC 접속은 별도 전환 시 수집 바인딩과 방화벽을 정한 뒤 적용하며, 기존 8000 API와 혼동하지 않습니다.

## 점검 순서

PowerShell에서 키를 환경 변수로 읽어 둡니다.

```powershell
$env:INGEST_KEY = (Get-Content .env | Where-Object { $_ -match '^INGEST_KEY=' }) -replace '^INGEST_KEY=', ''
$env:COLLECTOR_URL = 'http://127.0.0.1:8002'
```

1. **계약 점검(P1·P3):** `python simulator.py checks` → `"passed": true`. 정상 202, 같은 이벤트 재전송 202, 같은 ID 다른 내용 202(뒤에 Silver에서 격리), 허용 외 details 키 422 + DLQ, 카테고리 불일치 422, 깨진 JSON 422, 업데이트·실행 이벤트 202.
2. **스모크(P3):** `python simulator.py smoke --count 100 --run-id smoke-001` 후 같은 명령을 한 번 더(같은 본문 재전송). Silver는 100행 그대로여야 합니다.
3. **업데이트(P4-2):** `python simulator.py updates --installs 30 --hash-failures 5`
4. **행 수 대조(P6):**
   ```powershell
   $V = 'docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json exec -T spark /opt/spark/bin/spark-submit --master local[2] --conf spark.jars.ivy=/ivy --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.3,io.delta:delta-spark_2.12:3.2.1 --py-files /app/tables.py /app/verify.py'
   Invoke-Expression "$V counts"          # Bronze=Kafka, Silver 중복 0, Gold=Silver → passed=true
   Invoke-Expression "$V lag"             # Kafka 끝 오프셋 - Bronze 오프셋
   Invoke-Expression "$V history --table silver.learning_events"
   Invoke-Expression "$V timetravel --table silver.learning_events"
   ```
5. **15초 지연(P4):** `docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json exec -T spark python3 /app/probe_latency.py --probes 5`
6. **강제 종료·타임 트래블:** [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md)
7. **부하(P6):** `python simulator.py load --users 1200 --rate 200 --duration 600` → `results/load-<run-id>.json`에 202 비율·응답 시간 기록. 부하 중 `lag`과 `probe_latency.py`를 같이 돌려 기록합니다.

MongoDB 확인: `docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json exec mongo mongosh nodeverse_logs --eval "db.rt_summary.findOne()"`

## 단위 테스트

```powershell
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
.venv/Scripts/python -m pytest -q        # 34개: 수집 API 계약, 분류, DLQ, 6일 기준선, 런처 이벤트 형식
```

## 검증 기록 (2026-11-16, 클라우드 Docker 4코어에서 전체 스택 실행)

- 토픽 5개 생성, `/v2/events` 202·422 + DLQ 1건, 학습·업데이트·실행 이벤트 토픽 분류: 통과
- Bronze 행 수 = Kafka 레코드 수(토픽별): 통과. Silver 중복 0, 같은 300건 재전송 후에도 Silver 그대로, 같은 ID 다른 내용 격리 1건: 통과
- Gold 1분 합계 = Silver 집계(시도·성공·실패, 창별 불일치 0): 통과. `rt_minigame_1m`, `rt_alerts`, `rt_summary`, `rt_updates`(hash_mismatch 상위 사유 포함), `rt_versions` 갱신 확인
- 이벤트 3,000건 처리 중 `docker kill`로 Spark를 죽이고 재시작(누적 7.5만 건): Bronze=Kafka, Silver 3,000행·중복 0, Gold=Silver 모두 일치
- 부하: 가상 사용자 1,200명, 초당 200건 × 5분, 수집 202 비율 100%, 끝난 뒤 Kafka→Bronze 지연 0
- Silver 중복 판정을 상태 저장소 방식으로 바꿨습니다(DECISIONS.md D19). Silver를 다시 읽지 않으므로 데이터가 쌓여도 배치 비용이 늘지 않는 구조입니다.
- **판단 보류:** 이벤트→`rt_minigame_1m` 지연은 평시 9~18초, 부하 중 10~53초였습니다. 시험 PC의 CPU가 포화 상태(부하 평균 7~8, 4코어)여서 이 수치로는 판단할 수 없습니다. 이 PC에서 다시 측정해야 합니다.
- 이 PC에서는 아직 실행하지 않았습니다. 10분 부하 시험도 이 PC에서 해야 합니다.

## 주의

- 체크포인트와 볼륨(`lake`, `kafka-*`, `mongo`)을 지우지 마세요. 지우면 재시작 후 결과가 같다는 보장이 깨집니다. 처음부터 다시 하려면 `docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json down -v`(전부 삭제)를 씁니다.
- 503 응답이나 응답 유실 시 같은 `event_id`와 같은 본문으로 다시 보냅니다. 같은 ID에 다른 내용은 격리됩니다.
- `occurred_at`이 6일보다 오래된 이벤트는 422(`too_old`)로 거절됩니다. 런처·게임은 6일 넘은 대기열 이벤트를 보내지 않습니다(D20).
- 대시보드 값은 이벤트 후 평시 약 10~18초 뒤에 반영됩니다(D22, 제약사항).
- `INGEST_KEY`가 런처·게임 PC에 있어야 하는 것은 P7(설치별 토큰) 전까지 알려진 제약입니다.

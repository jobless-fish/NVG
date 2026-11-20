# 구현 결정 기록 (2026-11-16)

「NODEVERSE 파이프라인 파트 구현 지시서」를 이 폴더에 적용하면서 지시서가 모호하거나 이 폴더 구조와 맞지 않는 부분을 아래처럼 정했습니다. 공통 계약에 영향이 있는 항목(★)은 게임·서버 지시서에도 같은 내용으로 반영해야 합니다.

## 작업 위치

- **D0. 작업 대상 폴더.** 지시서는 NVG 저장소 `pipeline/`(stream.py, direct-writer 유지)를 대상으로 적었지만, 실제 파이프라인이 구축된 PC는 이 PC이고 담당자 부재로 인수인계가 불명확해서 이 폴더(`nodeverse-pipeline`)에서 구현했습니다(사용자 결정). 기존 v1 파일은 `_backup/v1_2026-11-16/`과 `_backup/nodeverse-pipeline_v1_2026-11-16.tar.gz`에 그대로 있습니다. NVG의 `launcher.py`, `processing.py`(해시 규칙), `gateway.py`(RuntimeEvent)는 참고만 하고 필요한 부분을 옮겼습니다. NVG 쪽 1차 파이프라인(direct_outbox, MongoDB 정제)은 이 폴더에 없으므로 "옆에 붙이는" 방식 대신 Delta 경로만 둡니다.
- **D0-1. compose 파일.** 이 폴더의 방식대로 `build_compose.py`가 `compose.json`을 만듭니다(지시서의 compose.yaml에 해당). 토픽 정의는 `topics.py` 한 곳에 있습니다.

## 토픽·수집 API

- **D1. 토픽 개수.** P1의 "토픽 4개"와 계약 표의 5개가 다릅니다. topic-init에서 계약 표의 5개(`nv.learning.v2` 6, `nv.runtime.v1` 3, `nv.bundle.v2` 3, `nv.dlq.v1` 3, `nv.update.v1` 3)를 한 번에 만듭니다. 보관 7일(`retention.ms=604800000`)을 명시합니다.
- **D2. `nv.bundle.v2`.** 생산자·소비자·스키마가 계약에 없어서 토픽만 만들어 두고 쓰지 않습니다(예약). 쓰게 되면 계약에 스키마부터 정해야 합니다.
- **D3. 브로커 구성.** 이 폴더는 이미 KRaft 브로커 3대라서 계약의 "브로커 3대 구성" 값(복제 3, min ISR 2)을 씁니다. 지시서 예시의 `kafka:9092`는 `kafka-1:9092,kafka-2:9092,kafka-3:9092`(환경 변수 `KAFKA_BOOTSTRAP`)로 바꿨습니다.
- **D4. 실행·종료 이벤트 경로 ★.** `POST /v2/events` 하나가 `event_type`으로 세 갈래를 나눕니다. 학습 8종 → `nv.learning.v2`(키 session_id), 업데이트 9종 → `nv.update.v1`(키 player_id), `run_*`/`exit_*` → `nv.runtime.v1`(키 run_id). 실행 이벤트 형식은 지금 런처 형식(schema_version 1, evidence 규칙)을 그대로 받습니다. `POST /v1/events`는 전환 기간 동안 실행 이벤트만 받습니다. 이 폴더의 옛 `/v1/events/batch`(v1 학습 스키마, Bearer 토큰)와 옛 토픽 `nodeverse.learning.events.v1`은 없앴습니다(쓰는 게임 빌드가 없음).
- **D5. DLQ 레코드 ★.** 422일 때 `nv.dlq.v1`에 `{reason, errors, endpoint, received_at, raw(앞 4KB), raw_truncated}`를 남깁니다. reason은 `invalid_json`, `unknown_event_type`, `schema_error`입니다. 키는 본문에서 읽을 수 있으면 `event_id`, 아니면 없음(null)입니다. 인증 실패(401)와 본문 16KB 초과(413)는 DLQ에 넣지 않습니다.
- **D6. 인증.** `X-API-Key` 헤더와 `.env`의 `INGEST_KEY`(24자 이상)를 비교합니다. 옛 `COLLECTOR_TOKEN`·Bearer 방식은 없앴습니다.
- **D9. 스키마 세부 ★.** `session_id`, `run_id`, `attempt_id`는 UUID 형식을 요구합니다. `attempt_id`는 `problem_started`·`problem_completed`처럼 시도 밖 이벤트가 있어서 선택 항목으로 뒀습니다. `occurred_at`은 UTC 밀리초 형식(`...12.345Z`, `+00:00`도 허용)만 받고 5분 넘게 미래면 422입니다. `minigame_id`와 `category`가 카탈로그(24종)와 맞지 않으면 422입니다(예: ST06은 ALGO). `build_version`은 `주.부.수` 형식입니다. 업데이트 이벤트는 `update_checked`에 result, `update_prompted`에 kind, `pack_download_failed`에 failure_reason, `build_changed`에 from_version이 꼭 있어야 합니다.

## Delta

- **D7. 테이블 이름.** 지시서의 `toTable("bronze.game_events")`, `DeltaTable.forName(...)`은 영속 메타스토어가 있어야 재시작 후에도 이름이 남습니다. 메타스토어를 따로 두지 않고, 테이블은 경로(`/data/delta/<db>/<table>`)에 저장하고 Spark 세션이 뜰 때마다 `CREATE TABLE IF NOT EXISTS ... USING DELTA LOCATION`으로 이름을 등록합니다. 그래서 `DESCRIBE HISTORY bronze.game_events`, `VERSION AS OF`가 스트림 프로세스와 검증 프로세스 양쪽에서 됩니다.
- **D8. 체크포인트 위치.** 지시서 예시의 `/checkpoints/...`는 볼륨 밖이라 컨테이너를 다시 만들면 사라집니다. `/data/checkpoints/...`(Delta와 같은 `lake` 볼륨)에 둡니다. 시간대는 `spark.sql.session.timeZone=UTC`로 고정합니다.
- **D10. Bronze 완료 기준.** "두 토픽 오프셋 합계"는 세 토픽(학습·실행·업데이트) 합계로 봅니다. `verify.py counts`가 토픽별로 비교합니다.
- **D11. 본문 해시와 id_conflict ★.** 해시는 수집 API가 `processing.py`와 같은 규칙(검증된 본문에서 received_at을 뺀 정렬 JSON의 SHA-256)으로 계산해 `payload_hash` 필드로 Kafka에 함께 넣습니다. Silver 두 테이블에 `payload_hash` 열이 있습니다. 같은 ID가 다시 오면 내용이 같으면 버리고, 다르면 `id_conflict`로 격리합니다(D19의 감사 스트림).
- **D12. 버전 삭제 전파.** `gold.version_adoption`은 MERGE에 `whenNotMatchedBySourceDelete`를 써서 24시간 동안 안 보인 버전을 지우고, MongoDB `rt_versions`에서도 같은 `_id`를 지웁니다(upsert만으로는 지워지지 않으므로).
- **D13. update_progress_5m 묶음 키.** `details.target_version`이 없는 이벤트(예: `build_changed`, 결과가 offline인 확인)는 `target_version = "none"`으로 묶습니다.
- **D14. player_id 의미 ★.** 보급률은 계약대로 `player_id`별 마지막 버전으로 셉니다. 학습 이벤트의 `player_id`에 회원 UUID가 들어오면 같은 설치가 둘로 세어질 수 있으니, 게임은 `player_id`에 항상 설치 ID(런처가 주는 `NODEVERSE_PLAYER_ID`)를 넣는 것을 권장합니다.
- **D15. (D19로 대체)** 처음에는 Silver 조회·MERGE를 최근 날짜 파티션으로 제한했지만, 그래도 데이터가 쌓일수록 느려지는 구조라 D19로 바꿨습니다.
- **D16. 경고 기준선.** "직전 30분 평균"은 `gold.minigame_1m`의 직전 30분(창 시작 기준) 실패 합계 ÷ (성공+실패) 합계로 계산합니다. 기준선이 없으면(첫 30분) 시도 수·실패율 조건만 봅니다. `gold.failure_alerts`에는 계약 열에 더해 `window_end`, `category`, `successes`, `baseline_rate`, `updated_at`을 둡니다. failure_rate = 실패 ÷ (성공+실패)입니다.
- **D17. rt_summary·version_adoption 주기.** 지시서는 P4 foreachBatch 안에서 부르라고 했지만, foreachBatch는 데이터가 없으면 돌지 않아 대시보드 값이 멈춥니다. 드라이버 타이머로 `rt_summary`는 10초, `version_adoption`은 60초마다 갱신합니다. `rt_summary`의 "최근 1분 이벤트 수"·"5분 활성 세션"은 received_at 기준입니다.
- **D18. 트리거 주기.** Bronze는 지시서대로 5초, Silver·Gold는 1초(`STAGE_TRIGGER`)로 둬서 15초 기준에 여유를 만들었습니다. 쿼리 일곱 개는 FAIR 스케줄러에서 함께 돕니다. 작은 파일은 자동 압축(파일 100개 이상일 때)으로 정리합니다. 정기 OPTIMIZE는 P7입니다.

- **D19. Silver 중복 판정을 상태 저장소로 (지시서 P3 변경 ★, 사용자 승인 11.16).** 지시서의 "Silver = event_id MERGE"는 배치마다 Silver 파일을 다시 읽어 ID를 찾으므로 데이터가 쌓일수록 느려집니다. 그래서 Silver를 두 스트림으로 나눴습니다.
  - `silver_learning_events`·`silver_update_events`(대시보드 경로, 1초): Spark 내장 `dropDuplicatesWithinWatermark(event_id)`가 RocksDB 상태 저장소에서 ID를 찾습니다. 처음 본 ID만 Silver에 append하고, 같은 배치 번호를 다시 실행하면 Delta가 건너뜁니다(`txnAppId`/`txnVersion`). Silver를 다시 읽지 않으므로 배치 비용은 그 배치 크기에만 비례합니다.
  - `silver_audit`(격리 경로, 30초): 상태 저장소에 `event_id → payload_hash`를 두고, 같은 ID에 다른 해시가 오면 `id_conflict`로, 깨진 JSON·필수 값 누락은 `invalid_json`·`invalid_schema`로 `silver.quarantine`에 남깁니다. 대시보드 지연에 영향을 주지 않습니다.
  - 상태 보관 기간은 Kafka 보관과 같은 7일(`DEDUP_TTL_HOURS`)입니다. 7일 넘게 지난 재전송은 Kafka에도 없으므로 문제가 없습니다.
  - Silver는 여전히 append만 하므로 Gold는 Silver를 스트림으로 그대로 읽습니다.
  - 알려진 한계: 같은 ID에 다른 내용이 **같은 배치 안에** 오면 Silver에 어느 쪽이 남을지 정해져 있지 않습니다(격리 기록은 남음). 상태 저장소 크기는 7일 동안 받은 ID 수에 비례합니다.

- **D20. 오래된 이벤트 기준선 6일 (공통 계약 추가 ★, 사용자 승인 11.16).** 수집 API는 `occurred_at`이 6일보다 오래된 이벤트를 422로 거절하고 DLQ에 `reason=too_old`로 남깁니다(DLQ reason 4종: `invalid_json`, `unknown_event_type`, `schema_error`, `too_old`). 게임과 런처는 오프라인 대기열에서 6일 넘은 이벤트를 보내지 않고 버리며, 422 응답은 다시 보내지 않습니다. 이유: Silver 중복 판정 상태 저장소와 Kafka 보관이 7일이므로, 6일 안의 재전송은 항상 상태 저장소가 기억하고 있어 중복이 생기지 않습니다. 대안(Silver를 날짜×player_id 버킷으로 나누고 오래된 이벤트만 범위 MERGE)은 장기 이력의 완전성이 필요해지면 검토합니다.
- **D21. Gold MERGE 범위 제한.** Gold 테이블 MERGE 조건에 이번 배치의 가장 이른 `window_start` 이후라는 조건을 넣어, Delta가 오래된 파일을 통계로 건너뛰게 했습니다. 경고 기준선 조회도 같은 방식(이른 창 30분 전부터)으로 읽습니다. Gold가 몇 주 쌓여도 MERGE 비용이 늘지 않습니다.
- **D22. 대시보드 반영 지연은 제약사항 (사용자 결정 11.16).** Bronze(5초)→Silver→Gold 세 단계가 각자 Delta 커밋을 마친 뒤 다음 단계가 읽는 구조라, 이벤트가 `rt_*` 컬렉션에 반영되기까지 평시 약 10~18초 걸립니다. 데이터 유실이나 접수 지연이 아닌 구조상의 지연으로 보고 제약사항으로 둡니다. 서버 대시보드는 이 지연을 화면에 밝히고 각 값의 `updated_at`을 함께 보여 줍니다. 부하 중 값은 이 PC에서 다시 잽니다.

## 남은 위험

- **15초 지연(P4 완료 기준, D22로 제약사항 처리).** 클라우드 시험 환경은 4코어 한 대에 Kafka 3대·Spark·Mongo·수집 API·부하 생성기를 함께 돌려 부하 평균이 7~8(코어 수의 두 배)까지 올라갔습니다. 이 상태에서는 평시 9~18초, 초당 200건 부하 중 10~53초로 나와 판단할 수 없었습니다. 이 PC에서 `probe_latency.py`로 다시 재야 합니다. 넘으면 Spark 코어 수를 늘리거나 Bronze 트리거를 줄이는(계약 변경) 방안을 검토합니다.
- **INGEST_KEY 배포.** 런처·게임에 키가 들어가는 문제는 P7(설치별 단기 토큰) 전까지 알려진 제약입니다.


## 2026-11-20 보완 (기존 D19 일부 대체)

- D23. 요구사항 4에 맞춰 Silver foreachBatch의 txn append를 event_id 기준 insert-only
  MERGE로 변경했다. 상태 저장소 선행 중복 제거와 체크포인트 이름은 유지한다.
  이벤트는 수정 불가이므로 matched UPDATE를 하지 않는다. 충돌은 감사 스트림 격리로 처리한다.
  기존 D19의 “MERGE 없음/대상 재조회 없음” 성능 설명은 현재 코드에 적용되지 않는다.
  Bronze는 원본/재전송 보존과 Kafka 오프셋 복구를 위해 Delta 기본 append sink를 유지한다.
- D24. OPTIMIZE ZORDER는 별도 maintain.py로 수행한다. 계획 출력이 기본값이고,
  --execute일 때만 쓰며 스트리밍 writer를 먼저 중지한다. VACUUM과 체크포인트 삭제는 하지 않는다.
- D25. maxOffsetsPerTrigger, shuffle partitions, Spark cores/driver memory, 트리거와
  호스트 포트를 설정 가능하게 했다. 기본 트리거/워터마크는 변경하지 않았다.
  처리 지표는 lake 볼륨 /data/metrics/streaming-progress.json에 기록한다.
- D26. nodeverse-v2-review 프로젝트와 localhost:8002/27019로 기존 서비스와 격리해 검증한다.
  운영 전환·원격 DB 적재·게임 저장소 병합은 이번 점검 범위와 구분한다.


## 후속 실제 시험 보완

- D27. 수집기/Mongo healthcheck 및 Mongo healthy 의존성, 시험 송신기/지연 측정 준비 대기를 추가했다.
- D28. 시험 명령의 실패 종료 코드와 업데이트 원문 재전송을 보완하고,
  RuntimeEvent에도 공통 5분 초과 미래 시각 거절을 적용했다. 공통 계약 변경으로 게임/서버에 전달한다.
- D29. MERGE 반복 스캔 행 수 경고를 관측하여 materializeSource=none 강제를 제거했다.
  Delta 기본 자동 원본 고정 정책을 유지하며, 성능을 위해 정합성 기능을 끄지 않는다.
  이전 시점의 지연 측정과 변경 후 설정을 구분해서 해석한다.

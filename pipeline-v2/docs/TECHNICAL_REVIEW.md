# Kafka / Spark / Delta 기술 점검 (2026-11-20)

## 1. Kafka 토픽·파티션·복제

| 토픽 | 파티션 | 키 | 용도 |
|---|---:|---|---|
| nv.learning.v2 | 6 | session_id | 학습 이벤트 8종 |
| nv.runtime.v1 | 3 | run_id | 실행·종료 |
| nv.update.v1 | 3 | player_id | 업데이트 9종 |
| nv.dlq.v1 | 3 | event_id 또는 null | API 규약 위반 |
| nv.bundle.v2 | 3 | 미확정 | 예약, 실제 경로 아님 |

모두 RF=3, min.insync.replicas=2, retention.ms=604800000(7일).
수집 Producer enable.idempotence=true, acks=all, 전달 확인 후 202.
키별 순서는 한 파티션 안에서 보장하며 전체 토픽 순서는 보장하지 않는다.
브로커 3개가 같은 Docker 호스트에 있어 호스트 장애에 대한 고가용성은 아니다.
현재 실제 토픽 설정은 results/review-topics.txt로 확인했다.
브로커 1대 중지 시험은 자동 승인 검토의 blocked by policy 응답으로 실행하지 않았다.

## 2. Spark Structured Streaming

명시적 StructType와 UTC timestamp를 사용한다. 수집 API의 Pydantic 검증이 앞단 계약 검증이고,
Spark의 from_json만으로 필수 필드·의미 검증 전체가 보장되는 것은 아니다.
정상 수집 API를 우회하여 Kafka에 임의 레코드를 쓰는 운영은 지원하지 않는다.

| 단계 | 워터마크/윈도 | 의미 |
|---|---|---|
| Silver | kafka_ts 168시간 / event_id 중복 제거 | 토픽별 7일 상태; 접수는 발생 후 6일 이내 |
| Gold 학습 | event_time 2분 / 1분 Tumbling | 게임별 시도·성공·실패·힌트, 근사 사용자 수 |
| Gold 경고 | event_time 2분 / 5분 Sliding, 1분 이동 | 실패율·직전 30분 기준선 |
| Gold 업데이트 | event_time 10분 / 5분 Tumbling | 다운로드·실패 사유·중앙값 |

워터마크는 “2분 뒤 화면 표시”가 아니라 상태 정리·지각 이벤트 허용 기준이다.
Gold는 update 모드로 미완성 창도 갱신한다. 충분히 오래 늦은 데이터는 집계에서 제외될 수 있다.
발생-수신 시각 차가 5분을 넘으면 집계 event_time은 received_at으로 대체한다(기존 시각 보정 정책).
원본 occurred_at은 보존된다. 장기 오프라인 데이터의 집계 시점 정책은 게임/서버와 확인해야 한다.

## 3. Exactly-once와 장애 복구 범위

- Kafka → Bronze: Delta 스트리밍 sink와 영속 checkpoint로 처리한 오프셋/커밋을 복구한다.
- Bronze → Silver: 상태 중복 제거 + event_id insert-only MERGE로 재처리 중복 삽입을 막는다.
  이벤트는 불변이다. 같은 ID 다른 내용은 감사 경로에서 id_conflict로 격리하고 덮어쓰지 않는다.
- 감사 격리: txnAppId/txnVersion으로 동일 batch 재실행 append를 건너뛴다.
- Silver → Gold: 창+게임/버전 키로 집계 전체값을 MERGE하고 MongoDB는 같은 _id로 replace upsert한다.
  증가 연산($inc)을 재실행하여 값이 부풀어 오르는 방식을 사용하지 않는다.
- Delta와 MongoDB 사이에는 분산 트랜잭션이 없다. 잠깐 불일치가 가능하고 foreachBatch 재실행으로 수렴한다.
  따라서 전체 시스템에 대한 무조건적인 원자적 Exactly-once라고 표현하지 않는다.
- 각 query의 checkpoints는 lake 볼륨 /data/checkpoints에 있다. 삭제, 복사 충돌,
  임의 checkpoint 이름 변경, Kafka 보관기간 초과 지연 시 동일 보장은 성립하지 않는다.
  failOnDataLoss=true로 오프셋 유실을 조용히 건너뛰지 않는다.
- 7일 상태, 6일 접수 기한, immutable UUID 재전송을 전제로 한다. 모든 과거 데이터에 대한
  무기한 중복 판정으로 해석하지 않는다. checkpoint 초기화는 복구가 아닌 별도 재구축이다.

## 4. Delta 증분 적재와 OPTIMIZE/ZORDER

Bronze는 전송 원문과 재전송까지 보존하므로 Delta append가 맞다. 원본을 MERGE로 지워서
중복 없는 정제 데이터처럼 만들지 않는다. Silver에는 요구사항에 맞춰 insert-only MERGE를 반영했다.
Gold는 matched update + not matched insert다. Silver matched UPDATE는 원본 불변 원칙과
하위 append 스트림을 깨뜨릴 수 있어 사용하지 않는다.

spark/maintain.py는 기본적으로 SQL 계획만 출력한다. 실행 전에 해당 스트리밍 writer를 중지한다.
날짜 파티션 범위 지정이 가능하고, OPTIMIZE ZORDER의 파일 수와 전후 행 수를 기록한다.
Bronze ZORDER(topic, partition), Silver 학습(minigame_id, player_id, event_id),
업데이트(player_id, event_id). 실제 조회 패턴에 따라 컬럼 수/선택을 재측정한다.
ZORDER가 모든 조회를 빠르게 한다고 보장하지 않으며 정비 CPU/I/O 비용이 든다.
VACUUM/볼륨 삭제는 하지 않는다. Time Travel과 지연 스트림의 파일 보존을 유지한다.

예시 (시험 프로젝트, writer를 중지한 정비 시간):

```powershell
docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json stop spark
# 실행 전 계획: 아래 명령에서 --execute를 빼면 SQL만 출력
# 검증 작업도 같은 packages/py-files 옵션을 사용
$packages = 'org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.3,io.delta:delta-spark_2.12:3.2.1'
docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json run --rm --no-deps --entrypoint /opt/spark/bin/spark-submit spark --master 'local[2]' --conf spark.jars.ivy=/ivy --packages $packages --py-files /app/tables.py /app/maintain.py --table silver.learning_events --execute
docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json up -d spark
```

## 5. 지연·처리량 튜닝

- 설정: BRONZE_TRIGGER/STAGE_TRIGGER, SPARK_CORES/DRIVER_MEMORY,
  SHUFFLE_PARTITIONS, MAX_OFFSETS_PER_TRIGGER. 후자는 Kafka 입력 배치 크기를 제한한다.
- 기본 5초/1초와 격리 시험 2초/2초를 비교했다. review.env는 5초/1초로 복귀한다.
  트리거를 짧게 하는 것만으로 처리량이 늘지는 않는다. 배치 처리 시간이 트리거보다 길면 적체된다.
- FAIR 스케줄러, RocksDB 상태 저장소, Gold 변경 창 MERGE 범위 필터와 배치 캐시를 유지한다.
  Silver MERGE는 대상 탐색 비용이 생긴다. 기존 D19의 “Silver 재조회 없음” 성능 설명은 더 이상 유효하지 않다.
- /data/metrics/streaming-progress.json: query별 inputRowsPerSecond,
  processedRowsPerSecond, durationMs, eventTime.watermark, stateOperators 확인.
  foreachBatch 다중 읽기에서 입력 행 수가 과대 계상될 수 있어 최종 처리량은 고유 저장 건수/실측 시간과 구분한다.
- 수집 API 응답 지연, Kafka→Bronze lag, 최종 rt_* 반영 지연을 별도로 기록한다.
- verify.py의 창 비교는 시도뿐 아니라 성공/실패도 검사하도록 보완했다.
  지각 이벤트가 실제 버려진 시나리오에서는 Silver 전체와 Gold가 다를 수 있어 해당 범위를 별도로 해석한다.
- probe_latency.py는 15초 초과/타임아웃 시 종료 코드 1을 반환하도록 고쳤다.
  조용한 시험 환경에서 지정 미니게임의 집계 증가를 측정하며, 동시 송신 환경에서는 다른 이벤트의
  증가를 오인할 수 있다. 운영 SLA나 개별 이벤트 추적 증거로 단독 사용하지 않는다.

## 실행 환경과 결과

기존 pipeline 프로젝트는 8000/8010을 유지한다. 새 시험 프로젝트 nodeverse-v2-review는
로컬 전용 8002(API), 27019(MongoDB)와 별도 볼륨을 사용한다.
기존 nodeverse-dev Spark는 /app/bronze.py 누락으로 종료되어 있었다. 해당 옛 볼륨은 수정하지 않았다.
회원 MySQL/.167 직접 적재와 게임/팀원 화면 연결은 이번 처리 엔진 시험과 별개이며 미전환이다.
실측 결과는 아래에 추가한다. 클라우드 README 수치와 혼동하지 않는다.

공식 근거: https://docs.delta.io/delta-update/ 및 https://docs.delta.io/delta-streaming/


## 실측 결과 (이 PC, 2026-11-20)

| 요구 항목 | 반영·검증 결과 | 판정과 한계 |
|---|---|---|
| 1 Kafka | 토픽 5개, 파티션 6/3/3/3/3, RF3/min ISR2/7일 실제 조회 | 설정 확인 완료; 단일 호스트, 브로커 중지 시험 미실시 |
| 2 Streaming | 7개 query 기동, 명시 스키마·watermark·Tumbling/Sliding 확인, 실시간 rt_* 생성 | 정상 데이터 집계 검증; 지각/역순 경계 시험은 별도 필요 |
| 3 복구 | 부하 중 Spark kill/start, checkpoint 재개 후 Kafka/Bronze·Silver·Gold·Mongo 대조 | 해당 장애 시나리오 통과; DB 간 원자성 보장은 아님 |
| 4 Delta | Silver insert-only MERGE, Bronze/Silver 3개 테이블 OPTIMIZE ZORDER 실행 | 행 수 보존; 소규모 파일 1→1로 파일 감소 효과 없음 |
| 5 성능 | 트리거/배치/리소스 설정화, 지표 기록, 지연·부하 시험 | 기본 설정 3회 15초 내; 변경 설정 1회 초과, 장시간 부하 미검증 |

- API 계약 checks: 정상/중복/충돌 접수, 스키마 오류 422 + DLQ, 학습/실행/업데이트 분류 통과.
- 같은 학습 100건을 두 번 보냈다. 충돌 본문 1건은 id_conflict 격리로 확인했다.
- 100 가상 사용자, 50건/초 × 30초 = 1,500건. Kafka 접수 202 비율 100%,
  실측 50.0건/초, API 응답 p50=16.8ms, p95=34.5ms, p99=42.4ms.
  Spark가 일부 구간 내려간 동안에도 수집 후 재처리했다. 지속적인 실시간 처리 용량을 증명하는 시험은 아니다.
- 복구 후 첫 대조: Kafka/Bronze 학습 1,706건 + 실행 1건 + 업데이트 1건.
  Silver 학습 1,604건, 고유 ID 1,604, 중복 0; 업데이트 1건; 충돌 격리 1건.
  Gold/Silver: 시도 268/268, 성공 101/101, 실패 99/99. Mongo/Gold 차이 0.
- 평시 기본 트리거 5초/1초: 8.32s, 10.86s, 9.11s, 최대 10.86s (3/3 목표 통과).
- 변경 2초/2초: 16.18s, 10.86s, 10.87s, 최대 16.18s (2/3 목표 통과).
  OPTIMIZE 후 재기동 조건도 포함되어 통제된 A/B가 아니다. 더 짧은 트리거의 개선 효과는 입증되지 않았고
  기본값을 유지한다. 15초를 언제나 보장한다고 표현하지 않는다.
- OPTIMIZE 전후: Bronze 1,708→1,708행, Silver 학습 1,604→1,604행,
  Silver 업데이트 1→1행. 각 테이블 파일 수 1→1, ZORDER 실제 파일 재작성 확인.
- 단위 테스트 30건 통과, Python 컴파일 및 compose config 검사 통과.

증거 파일은 로컬 results/에 있다(기존 gitignore 유지). review-checks.txt,
load-review-load-1120.json, review-latency-baseline.txt, review-latency-tuned.txt,
review-maintenance.json, review-verification.json과 *final* 로그를 확인한다.
최종 요약은 docs/verification-2026-11-20.json에 비밀값 없이 남긴다.

추가 검증: 10분 이상 지속 부하·동시 실제 게임, 워터마크 경계/역순 입력,
호스트 재부팅/디스크 부족/장기 중단, Mongo 장애 후 재처리, 게임 회원 연결과 팀원 대시보드.


### OPTIMIZE 이후 재기동·최종 대조

추가 지연 측정 3건을 포함한 최종 대조도 passed=true다.
Kafka/Bronze 학습 1,709건 + 실행 1건 + 업데이트 1건, Bronze 중복 오프셋 0.
Bronze의 학습 고유 ID 1,607개 = Silver 학습 1,607행, 업데이트도 고유 ID 1개 = 1행.
Gold/Silver 시도 271/271, 성공 101/101, 실패 99/99, Mongo 차이 0, Kafka→Bronze lag 0.
OPTIMIZE 이후 Silver를 읽는 Gold 스트림도 재개되어 새 이벤트가 정상 반영됐다.
시험용 스트림은 5초/1초 기본 설정으로 다시 기동했다.

재현 기동 명령(기존 서비스를 건드리지 않는 시험 구성):

```powershell
python build_compose.py
docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json up -d --build
.venv/Scripts/python check.py --url http://127.0.0.1:8002
```

이 PC API 문서: http://127.0.0.1:8002/docs
MongoDB Compass: mongodb://127.0.0.1:27019/ (DB nodeverse_logs)
로컬 바인딩이므로 다른 PC에서 바로 접속하는 운영 주소는 아니다.
팀원용 공개와 8000 서비스 교체는 별도 전환 작업으로 정한다.

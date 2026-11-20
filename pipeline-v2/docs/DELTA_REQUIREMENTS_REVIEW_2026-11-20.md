## 1. 검토 결론 · 1~5번 요구 적합성

검토 기준: 첨부 PDF 12쪽 + 현재 로컬 작업본 + 실행 지표 + 기존 실제 시험 증거 | 2026.11.20

결론: 기본 파이프라인은 구현·실행 중입니다. 그러나 1~5번을 모두 “완전 충족”으로 일괄 표시하면 안 됩니다. 특히 Silver MERGE의 성능 회귀 가능성, Exactly-once 보장 범위, 대용량/장시간 지연과 처리량 검증이 남아 있습니다.

| 요구사항 | 판정 | 현재 상태와 남은 증거 |
| --- | --- | --- |
| 1. Kafka 수집·토픽·복제 | 기본 구현 충족 | 5개 토픽, 6/3/3/3/3 파티션, RF3·min ISR2. 같은 호스트 3대이며 브로커/호스트 장애 가용성 검증은 별도 |
| 2. Structured Streaming | 기본 구현 충족 | 명시 스키마·워터마크·Tumbling/Sliding·7개 쿼리. 지각/역순/스키마 경계의 전체 시험은 미완료 |
| 3. Exactly-once·복구 | 조건부 충족 | checkpoint·멱등 sink·재시작 시험 있음. Delta/MongoDB 원자적 트랜잭션 없음. 같은 배치 충돌의 기준 원문 결정 문제 잔존 |
| 4. MERGE·OPTIMIZE/ZORDER | 부분 충족 | Bronze append, Silver insert-only MERGE, Gold upsert. ZORDER 실행·행 수 보존 확인. matched UPDATE와 성능 향상 증거는 별도 |
| 5. 지연·처리량 튜닝 | 부분 검증 | 설정·측정 도구와 단기 시험 있음. 최종 설정 지연 12.89초 1회, 6,000건 접수. 장시간 지속 처리·부하 중 목표는 미검증 |

### 자료 시점과 이번 점검 범위

첨부 v1.0은 표지 날짜가 11월 20일이지만 본문은 11월 16일까지의 상태이며, 이후 PC 변경을 반영하지 못했다고 명시합니다(PDF 2·12쪽). 따라서 과거 기록 자체와 현재 상태의 불일치를 구분했습니다. 모든 쪽수는 표지를 포함한 PDF 뷰어 쪽수입니다.

이번 재점검 시각은 2026-11-20 11:12 KST입니다. Spark 쿼리 7/7 active, 지표 갱신 약 4.5초 전, Kafka 토픽 설정 확인, 단위 테스트 34건 통과입니다. 이번 요청에서는 운영 코드·설정 변경이나 대규모 재시험을 하지 않고 검토 근거와 보고서를 추가했습니다.

증거 수준을 [현재 확인], [기존 시험], [문서 보고], [코드상 위험], [미실시 제안]으로 구분합니다. 문서의 클라우드 수치는 재현한 것처럼 쓰지 않습니다. Kafka/Delta/Spark의 용어와 의미는 공식 문서로 교차 확인했습니다.

## 2. 첨부 문서와 현재 상태의 차이

과거 기록을 지우지 말고, 현재 상태를 설명하는 별도 변경 이력으로 보완해야 합니다.

| 첨부 PDF 위치 | 11/16 기준 설명 | 현재 확인 / 검토 |
| --- | --- | --- |
| 2·6·11쪽 | PC 미실행 / main, 커밋 2건 | 별도 nodeverse-v2-review 실행·실제 시험 완료. feature/codex-v2-integration-cleanup 작업 중. HEAD 2466861이지만 미커밋 변경 다수 |
| 2·5·8쪽 | Silver 상태 중복 제거 후 append | 현재 dropDuplicatesWithinWatermark 뒤 event_id insert-only MERGE가 추가됨(D23). 상태 저장소는 유지 |
| 5·7·8쪽 | merge.materializeSource=none | 현재 강제 none 설정 제거(D29). Delta 기본 원본 고정 정책 유지. 이전에 스캔 행 수 경고 관측 |
| 11쪽 | 정기 OPTIMIZE는 후속 과제 | maintain.py 구현·실행 완료(D24). 정기 스케줄/동시 실행 방지는 미구현 |
| 9쪽 | 30개 단위 테스트 | 현재 34개 통과. 실패 종료 코드·업데이트 원문 재전송·실행 미래시각 검증 추가 |
| 9·10쪽 | 클라우드 9~18초 / 부하 10~53초 | 현재 PC 별도 시험: 6,000건/120초, 최종 설정 지연 12.89초(1회). 환경·부하가 달라 직접 우열 비교 불가 |
| 11쪽 | 기본 compose·8000/27017 | 시험은 -p nodeverse-v2-review + review.env, localhost 8002/27019. 기존 8000/8010 서비스와 공존 |
| 3·4·11쪽 | Django가 rt_*를 조회 | 현재 v2 rt_*는 로컬 MongoDB. 원격 기존 업무 5개 컬렉션과 다르며 팀원 화면 연결은 미완료 |
| 기타 후속 상황 | 원격 연결 상태는 본문 범위 아님 | 원격 .167의 MySQL 8.4.13·MongoDB 8.0.34 접속/구조 검사 정상. 회원 3명, 업무 컬렉션 각 2건. 신규 v2 원격 쓰기는 미시험 |

### 현재 변경을 설명할 때 반드시 붙일 문장

“11월 16일의 append 방식은 승인된 성능 개선안이었다. 11월 20일의 MERGE 재도입은 요구 형식에 맞추기 위한 보완이지만, 누적 테이블 검색 비용이 재발한다. 단기 정합성 시험 통과가 대용량 성능 개선을 의미하지 않는다.”

본문에서 D19를 현재 설명처럼 유지하지 말고 “11/16 이력”으로 표시하고 D23~D29를 현재 기준으로 연결합니다. 실제 코드는 로컬 미커밋 작업본이므로 HEAD만으로 식별하지 말고 파일 해시/변경 목록을 함께 전달합니다.

## 3. 요구 1·2: Kafka와 스트리밍 구조 점검

기본 구현은 요구 방식과 맞습니다. 의미를 과장하거나 워터마크를 화면 지연으로 해석하면 안 됩니다.

| 토픽 | 파티션 / 키 | 현재 목적 |
| --- | --- | --- |
| nv.learning.v2 | 6 / session_id | 학습 8종 |
| nv.runtime.v1 | 3 / run_id | 실행·종료 |
| nv.update.v1 | 3 / player_id | 업데이트 9종 |
| nv.dlq.v1 | 3 / event_id 또는 null | 형식/시각 오류 등 |
| nv.bundle.v2 | 3 / 미확정 | 예약. 생산·소비 계약 없음 |

현재 설정은 Kafka 3.9.1 KRaft, RF=3, min.insync.replicas=2, 보관 7일, producer enable.idempotence=true·acks=all입니다. 순서는 파티션 안에서만 보장합니다. 물리 호스트가 하나이므로 컨테이너 3대가 호스트 장애까지 견딘다는 뜻은 아닙니다.

PDF 4쪽의 “3대 모두 응답 후 202”는 “현재 ISR 전체의 응답을 기다리며 최소 ISR 2를 만족한 경우 접수”로 수정합니다. ISR가 3이면 3대, 2이면 2대입니다. 202는 후단 저장 완료가 아닙니다. [S1]

| 처리 단계 | 시간 기준 / 워터마크 / 창 |
| --- | --- |
| Silver 중복 제거 | Kafka 수신 시각 kafka_ts / 168시간 / event_id. 감사 스트림은 별도 processing-time timeout 7일 |
| Gold 학습 | event_time / 2분 / 1분 Tumbling |
| Gold 실패 경고 | event_time / 2분 / 5분 Sliding, 1분 간격 |
| Gold 업데이트 | event_time / 10분 / 5분 Tumbling |

contract.py의 앞단 검증과 Spark StructType 파싱을 함께 사용합니다. schema_version·필수값·카탈로그 검증 전체가 from_json만으로 이뤄지는 것은 아닙니다. 직접 Kafka에 쓰는 별도 생산자를 허용하려면 동일 계약 검증이 추가로 필요합니다.

워터마크는 최대 관측 event time을 기준으로 지각 데이터·상태를 관리합니다. 2분 기다렸다가 화면에 내보내는 설정이 아니며 무입력 구간에서는 시계처럼 계속 전진하지 않습니다. [S2] 발생·수신 차가 5분을 넘으면 현재 코드는 event_time을 수신 시각으로 바꿉니다. 예: 10:00 발생/10:10 수신은 10:10 창에 들어갈 수 있어 과거 학습 시각 통계와 구분해야 합니다.

## 4. 요구 3: Exactly-once와 복구의 보장 범위

중복 방지, 원문 선택의 결정성, 여러 DB의 원자성은 서로 다른 문제입니다.

| 경로 | 현재 장치 | 판정 |
| --- | --- | --- |
| Kafka → Bronze | Delta 기본 스트리밍 sink + 영속 query checkpoint | 동일 오프셋 재처리의 중복 커밋 방지 조건 충족 |
| Bronze → Silver | 워터마크 상태 중복 제거 + event_id insert-only MERGE | 불변 이벤트의 중복 삽입 방지. 기존 내용 갱신 아님 |
| 감사 → quarantine | txnAppId/txnVersion으로 batch 재실행 제어 | checkpoint·app ID·트랜잭션 기록의 보존 조건 필요 |
| Silver → Gold | 창/게임·버전 키의 전체 집계값 MERGE | 재실행 지표 증가 방지. updated_at 등 메타데이터는 재실행 시 달라질 수 있음 |
| Gold → MongoDB | 같은 _id에 replace upsert | 재시도 수렴 구조. Delta와 MongoDB의 동시 원자적 커밋은 아님 |

foreachBatch 자체의 기본 보장은 at-least-once입니다. 멱등 write나 batch ID 중복 제어를 구현해야 논리적으로 한 번의 결과를 얻습니다. checkpoint만 있다고 외부 DB 전체 Exactly-once가 자동 보장되지는 않습니다. [S2·S3]

### 남아 있는 중요한 정합성 위험

같은 배치에 동일 ID의 서로 다른 본문이 들어오면 Silver의 dropDuplicatesWithinWatermark는 해시 기준 원문을 선택하지 않습니다. 감사 스트림은 별도로 partition/offset을 정렬하므로 Silver가 남긴 본문과 감사의 “첫 원문”이 달라질 수 있습니다. MERGE를 추가해도 앞단에서 이미 선택된 본문을 그대로 쓰므로 이 문제는 해결되지 않습니다. 문서도 PDF 8쪽에서 인정한 한계이며, 이번에 새로 재현한 장애는 아닙니다.

개선은 공통 canonical 결정 경로/ID registry 등으로 Silver·격리의 기준을 일치시키는 방향입니다. 상태 스키마/체크포인트 마이그레이션과 처리량 시험이 필요하므로 현재 checkpoint를 삭제하거나 즉시 상태 함수를 바꾸는 작업으로 처리하지 않습니다.

### 문서에서 고쳐야 할 표현

PDF 4쪽의 “202 이후 유실되지 않는다”는 보관기간·지연·디스크·복제·보존 조건을 명시한 접수 설명으로 바꿉니다. PDF 8·11쪽의 Silver/checkpoint 동시 삭제는 일반 복구 절차로 제시하면 안 됩니다. 장애 시 기존 볼륨과 checkpoint 보존 → 원인 확인 → 같은 설정으로 재시작이 기본입니다. 재구축은 백업·별도 경로·재생 범위·sink 검증을 설계한 뒤 수행합니다.

7일 Kafka 보관과 7일 상태 TTL이 모든 장애·재전송을 무조건 덮는 것은 아닙니다. 현재 접수 6일 기준과 원문 불변 조건이 전제이며, 장기 중단/retention 초과/상태 초기화/ID 재사용은 별도입니다.

## 5. 요구 4: MERGE와 OPTIMIZE/ZORDER 검토

Bronze 원본 보존, Silver 불변 이벤트, Gold 상태 갱신의 역할을 먼저 구분합니다.

| 레이어 | 현재 방식 | 요구와의 관계 |
| --- | --- | --- |
| Bronze | Kafka 원본·재전송을 append | 정상 설계. 모든 Bronze를 upsert로 바꾸면 전송 원본·재전송 증거를 잃을 수 있음 |
| Silver 학습/업데이트 | 상태 중복 제거 뒤 event_id 기준 WHEN NOT MATCHED INSERT | MERGE 사용 충족. matched UPDATE가 없는 insert-only이며 일반적인 수정 upsert 시연과는 다름 |
| Gold | 키 MERGE의 matched UPDATE + INSERT | 집계 상태의 증분 upsert. 기존 Silver 이벤트를 덮어쓰는 방식으로 맞출 필요 없음 |

현재 Silver MERGE 조건에는 날짜/버킷 범위 제한이 없습니다. 이미 상태 중복 제거로 대부분 신규 행만 와도, INSERT 여부를 판단하려고 기존 대상 ID를 검색합니다. 문서가 없앴던 누적 파일 탐색 비용이 다시 생긴다는 점을 반드시 설명해야 합니다. [S4]

### 설계 선택은 성능 시험·요구 해석 후 확정

A 현재 hybrid 유지: Silver에 MERGE가 명시적으로 필요한 경우 적합하나 대용량 병목을 측정해야 합니다. B 문서 방식으로 append 복귀: D19의 성능 의도와 맞지만 Silver MERGE 필수 조건과 충돌할 수 있어 합의가 필요합니다. C 별도의 상태/검증 테이블에 upsert를 두거나 안정적인 키/파티션으로 탐색을 제한: 계약·마이그레이션 설계가 추가로 필요합니다. 이번 검토에서는 자동 전환하지 않았습니다.

단순히 “오늘 날짜만 MERGE” 조건을 붙이는 것은 피합니다. 재처리 시 event_time/파티션이 달라질 수 있는 현재 시각 보정 정책과 만나면 과거 동일 ID를 놓쳐 중복 삽입할 수 있습니다. 원본의 안정적인 partition 키와 전체 ID 유일성 검증을 함께 설계해야 합니다.

### ZORDER 실행과 성능 향상은 다른 증거

현재 maintain.py는 기본 계획 출력, --execute일 때 쓰기, 날짜 범위 지정과 전후 행 수/파일 수 기록을 지원합니다. Bronze·Silver 3개 테이블에서 실제 실행·행 수 보존은 확인했으나 각 파일 수가 이미 1→1이어서 압축 효과나 조회 개선을 증명하지 못했습니다. 정기 실행과 writer 중지 자동 강제 장치는 아직 없습니다.

ZORDER는 실제 WHERE/JOIN 열과 통계가 맞아야 효과가 있고 열을 늘릴수록 각 열의 정렬 효과가 약해집니다. 현재 학습의 3열(minigame_id, player_id, event_id)과 ID 단독 MERGE의 적합성을 비교해야 합니다. 랜덤 UUID라도 정렬/클러스터링 후에는 skipping이 달라질 수 있으므로 “UUID는 항상 skipping 불가”로 일반화하지 않습니다. OPTIMIZE는 데이터 변경 없이 파일을 재배치하며, writer 중지는 현재 도구의 보수적 운영 방침이지 모든 Delta reader를 멈춰야 한다는 제품 제약이 아닙니다. [S5]

## 6. 문서의 오류 수정 14건 검토 (1~7)

첨부 PDF 7쪽의 항목 번호를 그대로 사용합니다. 과거 조치의 타당성과 현재 반영을 나눕니다.

| 번호 / 문제 | 문서 조치의 이유 | 현재 검토·판정 |
| --- | --- | --- |
| 1. 테이블 이름 소실 | 경로 저장 + 세션별 테이블 이름 등록 | 유지 타당. /data/delta를 실제 저장소로 두고 현재 tables.py register_names로 등록. 영속 metastore를 구현한 것은 아님 |
| 2. checkpoint 유실 | /data/checkpoints와 lake 볼륨에 배치 | 유지 타당. 컨테이너 재생성과 볼륨 삭제는 다름. 같은 PC의 볼륨이므로 호스트/디스크 장애 백업은 별도 |
| 3. ID 충돌 감지 불가 | payload_hash 추가·격리 | 필요한 보완. 실제 순차 충돌 격리 시험 통과. 동일 배치의 원문 선택 일치 문제까지 해결됐다고 쓰지 않음 |
| 4. v1 Bronze 계약 불일치 | 3개 구독 토픽과 계약 열로 재작성 | 현재도 유지. DLQ/예약 토픽까지 Bronze가 구독하는 것은 아님. “토픽 총 5개”와 “Bronze 구독 3개” 구분 |
| 5. 무입력 구간 값 정지 | summary 10초 / 버전 60초 타이머 | 유지 타당. foreachBatch는 무입력 시 실행하지 않을 수 있으므로 별도 갱신 필요. 타이머 주기는 처리 소요시간·오류로 밀릴 수 있음 |
| 6. 사라진 버전 잔류 | Delta whenNotMatchedBySourceDelete와 Mongo 삭제 | 삭제 전파 의도 타당. 현재는 설치의 최근 24시간 관측 기준. 재시도/원격 동기화 도입 시 오래된 snapshot이 문서를 부활시키지 않도록 revision 필요 |
| 7. target_version null | none 문자열로 묶음 | 그룹 키 안정화에 타당. 실제 버전명이 아니라 미지정 그룹임을 화면/분석에서 구분. 문자열 none을 실제 릴리스로 해석하지 않음 |

### 여기서 곧바로 적용할 수 있는 문서 정리

“완료”를 코드 존재/실행 확인/화면 확인으로 나누고, 8개 Delta 테이블·7개 streaming query·2개 타이머·5개 Mongo 컬렉션을 구분해 적습니다. 버전 집계와 회원 수는 같지 않습니다. rt_versions의 분모는 최근 관측 player_id 기반이므로 설치/회원 ID 계약을 명확히 유지해야 합니다.

과거 조치는 삭제하지 않고 당시 문제·변경·증거로 남깁니다. 새 보고서에는 현재 코드 파일·검토 시각·시험 로그와 함께 “현재도 유지 / 일부 대체 / 추가 검증 필요” 상태를 붙입니다. 코드 위치가 같은 이름이더라도 11월 16일 사본과 11월 20일 미커밋 작업본을 혼동하지 않습니다.

## 7. 문서의 오류 수정 14건 검토 (8~14)

Silver 여섯 단계는 실험 이력입니다. 같은 환경의 통제된 성능 비교로 재해석해서는 안 됩니다.

| 번호 / 문제 | 문서 조치의 이유 | 현재 검토·판정 |
| --- | --- | --- |
| 8. 설치 수 이중 집계 | player_id는 설치 ID로 계약 | 설치 단위 집계에는 일관된 방향. 원격 MySQL 회원 UUID와 자동 연결되지는 않음. 로그인 매핑 별도 유지 |
| 9. 최초 Spark 오류 | 기록에 오류 내용 없음 | 구체적인 원인/예외를 추정하지 않음. 당시 실행 통과 보고와 원인 미기록을 그대로 구분 |
| 10. 지연 15초 초과 | FAIR·빈 단계 생략·트리거 단축·원본 고정 끔 | 일부 유지. materializeSource=none은 현재 제거. 시간 관련 비결정적 원본을 반복 스캔할 때 일관성 위험이 있어 기본 자동 고정 복원 [S4] |
| 11. 매 배치 압축 비용 | autoCompact 최소 파일 수 100 | 현재 유지. 작은 배치마다 고정 비용을 줄이려는 의도 타당. 장기 작은 파일 증가량·실제 발동 비용은 관찰 필요 |
| 12. Silver 누적 성능 저하 | JVM 상태 중복 제거 + 별도 감사 | 문서의 핵심 개선. 현재 여기에 MERGE가 재추가되어 “대상 재조회 없음/누적량 무관” 설명은 적용 불가. 대용량 비교 우선 |
| 13. 7일 뒤 중복 재전송 | 6일 초과 접수 거절 + DLQ | 현재 유지. Kafka 만료가 새 재전송을 막는 것은 아님. 6일 정책·불변 occurred_at·워터마크/상태 복구 조건을 함께 설명 |
| 14. Gold 전체 탐색 | MERGE 조건에 가장 이른 창 하한 | 현재 유지. 오래된 파일 skipping에 도움. 최근 범위의 파일 수·통계·유입량에 따라 비용이 늘 수 있어 “규모와 무관”이라는 절대 표현은 수정 |

### Silver 6단계 개선의 올바른 설명

1~4단계는 대상 재조회·MERGE 병목을 줄이려던 시도, 5단계는 Python 상태 처리 비용을 확인한 시도, 6단계는 JVM 상태 처리와 감사 분리로 당시 누적 검색을 제거한 안입니다. 문서 수치상 6단계의 지연 자체가 항상 더 낮지는 않습니다. CPU 포화와 서로 다른 시험 조건 때문에 처리 구조·정확성 개선과 지연 개선을 분리해야 합니다.

현재는 6단계 구조에 event_id MERGE가 재추가된 hybrid입니다. 과거 8만 건 시험은 이 hybrid의 대용량 검증 증거가 아니며, 현 7,869건·단기 시험 역시 과거 성능 문제를 해결했다는 증거가 아닙니다. 11월 20일의 재도입을 새로운 비교 대상으로 명시합니다.

## 8. 요구 5: 성능 증거와 튜닝 방향

현재 PC와 문서의 클라우드 환경, API 응답과 최종 반영 지연, 접수와 처리량을 구분합니다.

| 시점 / 출처 | 부하·접수 | 최종 집계 지연 / 해석 |
| --- | --- | --- |
| 문서 11/16 클라우드 | 1,200 사용자 / 200건·초 / 최대 5분. 202 100% 보고 | 평시 9~18초, 부하 10~53초 보고. 4코어 CPU 포화. 현재 PC에서 재현하지 않음 |
| 현재 PC 기본 5초/1초 | 별도 단기 관측 | 8.32 / 10.86 / 9.11초. 최종 원본 고정 복원 이전 측정 |
| 현재 PC 2초/2초 시도 | OPTIMIZE 후 재기동 조건 포함 | 16.18 / 10.86 / 10.87초. 1회 목표 초과, 통제된 A/B 아님. 기본값 복귀 |
| 현재 PC 2분 부하 | 100 사용자 / 50건·초 / 6,000건. 202 100%, API p95 32.7ms | 부하 종료 후 10.29 / 9.12 / 10.85초. 부하 중 SLA 증거 아님 |
| 최종 MERGE 설정 복원 후 | 새 20건과 추가 probe | 12.89초 1회. 저장 대조 통과. 장시간 안정 지연을 뜻하지 않음 |

### 현재 존재하는 튜닝 수단

BRONZE_TRIGGER·STAGE_TRIGGER, SPARK_CORES·DRIVER_MEMORY, SHUFFLE_PARTITIONS, MAX_OFFSETS_PER_TRIGGER 설정과 query별 진행 지표가 있습니다. FAIR·RocksDB·배치 캐시·Gold 범위 하한·파일 최소 수 compaction을 유지합니다. 설정 가능하다는 것과 최적값을 찾았다는 것은 다릅니다.

### 다음 성능 시험의 설계

동일 fixture·같은 자원에서 누적 1만/10만/100만 건 등 증가 규모별 append 안과 hybrid MERGE 안을 별도 lake·checkpoint로 비교합니다. 최종 실행량은 디스크/메모리 예산에 맞춰 결정하고 운영 볼륨을 초기화하지 않습니다. 입력 크기·활성 query·동시 프로젝트 등 환경을 고정합니다.

그다음 10분 이상 일정률 시험에서 API p50/p95/p99, Kafka→Bronze lag, Silver/Gold 배치시간·적체, 상태 메모리, spill/GC·CPU·디스크를 함께 기록합니다. 저장한 고유 이벤트 수/경과시간과 유입률을 비교하고, 부하 종료 뒤 lag가 0으로 회복되는지도 봅니다. foreachBatch 반복 읽기의 inputRowsPerSecond를 실제 고유 처리량으로 그대로 쓰지 않습니다. [S4]

probe_latency는 같은 게임 창의 집계 증가를 관찰합니다. 동시 송신이 있으면 다른 이벤트의 증가를 오인할 수 있습니다. 단독 환경의 관측값으로 제한하거나, 부하 중에는 전용 시험 범위/추적 가능한 source revision과 sink 반영 관계를 설계한 뒤 p95/p99 목표를 확정합니다. 트리거를 무조건 줄이거나 correctness 기능을 끄지 않습니다.

## 9. 바로 구현할 수 있는 보완과 설계 합의 항목

아래는 실행 가능한 작업안입니다. 이번 문서 검토에서 해당 패치를 운영 코드에 적용하지 않았습니다.

| 우선 | 바로 가능한 작업 | 완료 기준 |
| --- | --- | --- |
| P0 | 문서의 D19/D23/D29 시점·acks·202·복구 설명 정정 | 과거 설명과 현재 코드를 구분하고 절대적 무손실/무비용 표현 제거 |
| P1 | _COMPLETE의 NULL을 False로 정규화하여 격리 누락 방지 | schema_version 누락/null 등 방어 경로 fixture가 Silver 제외 + invalid_schema 격리로 일치 |
| P1 | 설정 시작 검증: 트리거·코어·shuffle·offset 상한 양수, TTL/접수 정책 조합 검사 | 잘못된 환경값을 시작 시 명확히 거절. 비밀값 출력 금지 |
| P1 | 진행 지표 신선도·7개 query·마지막 실패를 운영 점검에 포함 | 단순 Docker Up와 실제 처리 준비 상태를 구분. 무입력과 장애를 구분 |
| P1 | maintain 실행 시 쓰기 중지/lease 확인 및 실행 대상·일자 기록 | 동시 writer 검출 시 중단. 성공 후 행 수/파일·쿼리 시간 비교. 자동 VACUUM 없음 |
| P1 | 지각·역순·동일 배치 충돌·재시도 경계 fixture 추가 | 정상/격리/보류/집계 제외의 기대 결과를 먼저 정의해 자동 대조 |

### 코드 검토로 찾은 작은 방어 로직 문제 - 미실시 패치 예

현재 _COMPLETE는 schema_version == 2를 포함합니다. 나머지 필드가 정상이고 schema_version만 NULL이면 결과가 NULL일 수 있습니다. 감사의 where(~_COMPLETE)도 NULL이 되어 그 행이 격리에서 빠질 가능성이 있습니다. 정상 API는 앞단에서 거절하므로 현재 시험 데이터가 누락됐다는 뜻은 아닙니다. Kafka 우회/과거 오염 데이터에 대한 정적 코드 검토 결과입니다. [S6]

```python
# 제안: Silver 정상 경로와 감사 경로가 같은 boolean 판정을 사용
valid = F.coalesce(_COMPLETE, F.lit(False))
accepted = parsed.where(valid)
invalid = parsed.where(~valid)
```

### 바로 바꾸면 안 되는 것

Silver append/MERGE 전환, canonical 상태 스키마 변경, checkpoint 재생성, ID/파티션 키·player_id 계약, 6일 정책·event_time 재기준화, 원격 rt_* sink와 회원 기록 매핑은 설계 합의·격리 시험이 먼저입니다. 규격상 matched UPDATE가 꼭 필요한지 확인하고 불변 이벤트를 수정 가능한 레코드로 바꾸지 않습니다.

## 10. 보고·수정 순서와 최종 인수 기준

기존 데이터와 승인 이력을 보존하면서 요구 충족의 의미를 확정하는 순서입니다.

### 추천 실행 순서

1. 검토 결과 공유 및 4번 요구 해석 확정: Bronze 원본 append 허용, Silver insert-only MERGE가 충분한지, matched UPDATE는 어떤 상태 테이블에서 시연할지 결정합니다. 2. 즉시 보완 항목을 별도 feature 브랜치에서 작게 반영하고 회귀 시험합니다. 3. 동일 배치 충돌의 canonical 결정과 checkpoint 마이그레이션을 설계합니다. 4. 규모별 성능 비교 뒤 Silver 방식을 최종 선택합니다. 5. 원격 rt_* 동기화/상세 기록과 실제 게임·화면 통합은 별도 인수합니다.

### 팀원 AI에게 요청할 산출물

현재 코드/문서 차이표, 필드·ID·enum·시각·재시도 계약, 변경 파일과 패치, 스냅샷/데이터 보존 계획, 정상·중복·충돌·지각·재기동 시험 로그, 자원과 누적량을 포함한 성능표, 미완료 항목을 제출합니다. 최신 게임 저장소·브랜치·커밋·EXE와 병합 대상은 담당자에게 먼저 확인합니다. NVG 게임을 최신으로 가정하지 않습니다.

### 종합 완료 판정 기준

기본 구현: 토픽·스키마·창·checkpoint·각 레이어 쓰기 방식이 계약과 일치. 정합성: 원문 기준과 격리 일치, 재전송/재기동 후 중복·누락·잘못된 최신값 0. 성능: 합의된 규모/유입률/시간/자원에서 lag 안정 및 최종 반영 p95/p99 충족. 최적화: 같은 데이터·질의의 전후 읽기 파일/시간 비교. 연결: 실제 최신 EXE부터 원격 DB·대시보드까지 동일 ID 대조. 각각 다른 증거로 완료를 표시합니다.

### 검토 근거와 보관 위치

사용자 PDF: NODEVERSE_델타레이크_구현과정_오류수정내역_v1.0.pdf(12쪽). 현재 코드: topics.py, collector.py, contract.py, build_compose.py, spark/tables.py·delta_stream.py·maintain.py·verify.py. 현재 재점검: results/document-review-1120/{runtime.json, topics.txt, resources.txt, unit-tests.txt, remote-check.json, source-fingerprint.json}. 기존 시험: docs/e2e-results-2026-11-20.json 및 results/review-maintenance.json. 비밀 설정은 포함하지 않았습니다.

### 공식 참조 - 제품 버전과 문서 범위

[S1] Kafka 3.9 Topic config: https://kafka.apache.org/39/generated/topic_config.html
[S2] Spark 3.5.x Streaming guide: https://spark.apache.org/docs/3.5.8/structured-streaming-programming-guide.html
[S3] Delta streaming: https://docs.delta.io/delta-streaming/
[S4] Delta MERGE: https://docs.delta.io/delta-update/
[S5] Delta OPTIMIZE/ZORDER: https://docs.delta.io/optimizations-oss/
[S6] Spark NULL semantics: https://spark.apache.org/docs/3.5.8/sql-ref-null-semantics.html

실제 런타임은 Spark 3.5.3 + Delta 3.2.1입니다. Spark 3.5.3 공개 문서 주소의 조회가 실패하여 같은 3.5 계열의 공식 설명을 교차 참고했습니다. 버전 변경·업그레이드를 권고하거나 수행한 것은 아닙니다.

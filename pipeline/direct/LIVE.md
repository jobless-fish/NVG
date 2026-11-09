# 자동 적재 연결 - PC1 → PC2 → PC3

## 현재 연결
PC1 송신 → PC2 192.168.0.81:8000/v2/play-records → Kafka game.events.v1 → Spark foreachBatch 검증/중복 제거 → PC2 MongoDB curated_bundles/direct_outbox → direct-writer → PC3 192.168.0.167 MySQL nodeverse / MongoDB nodeverse_logs.

별도 수신 API를 PC3에 추가하지 않는다. PC2 수집 API는 계속 필요하다. direct-writer는 조회 대시보드와 별도 서비스다.

## PC1 전송 규약
X-API-Key는 PC2의 기존 INGEST_KEY다. Content-Type application/json. 본문은 schema_version=1, event_type=relational_bundle, event_id=새 UUID, manifest=회원·문제·세션·문제실행·시도·이벤트 기록 배열이다. manifest 구조는 ../handoff/README.md 및 loader.py sample을 따른다. manifest의 path는 기록 종류를 식별하는 계약 필드이며 HTTP로 해당 path에 전달하지 않는다.

기존 /v1/events는 단일 행동 규격으로 유지하며 관계 필드가 부족하므로 PC3에 자동 적재하지 않는다. 없는 회원·문제 버전·시작시각·연산 성공 여부를 추정하지 않는다. PC1은 새 규격을 구현하거나 합의된 회원·콘텐츠·세션 컨텍스트를 제공해야 한다. 원시 이벤트를 관계 문서로 무조건 변환하는 기능은 없다.

202는 Kafka 접수 성공이다. GET /v2/play-records/{event_id}에 같은 X-API-Key를 보내 state=stored인지 확인한다. not_staged는 미접수 또는 Spark 처리 대기라서 접수 여부를 확정하지 않는다. pending/processing은 원격 적재 대기, blocked는 규약·참조·상태 정책 확인 필요다. stored는 DB 쓰기 완료이며 대시보드 지표의 의미 검증을 보장하지 않는다.

같은 전송 재시도에는 envelope UUID, 내부 UUID, sequence, 날짜, 본문을 모두 유지한다. 같은 ID·다른 내용은 격리한다. 후속 manifest가 앞선 세션/문제에 의존하면 앞선 stored를 확인한 뒤 보낸다. 문제 코드는 task_id/content_version별 고정 UUID를 사용한다. sample에서 $player_id는 적재기가 회원 UUID로 대체한다.

## 실행·복구
.env의 INGEST_KEY는 PC1 인증용이며 direct/.env의 DB 계정과 다르다. direct/.env는 Git·Docker 이미지에서 제외한다.

```powershell
docker compose --profile lab --profile direct up -d --build
```

direct 프로필은 direct-writer와 영속 direct-journals 볼륨을 사용한다. 한 writer만 실행한다. DB 장애는 원본과 대기열을 유지한 채 재시도하고, 관계·내용 충돌은 blocked로 멈춘다. 데이터 삭제/자동 덮어쓰기는 없다. 환경 변경 후에는 writer/gateway 이미지 재생성과 Spark 재시작이 필요하다. 로컬 MongoDB·Kafka·checkpoint·journal을 따로 지우지 않는다.

현재 실제 테스트는 in_progress 상태값을 가정해 시작·행동까지 수행했다. 종료 갱신은 DIRECT_FINALIZATION_POLICY_CONFIRMED=0으로 차단했다. 실제 풀이/일시정지 시간 규칙, 전체 event enum, 다중 writer 동시성, 운영 계정/보관 정책은 추가 합의가 필요하다.

## 실제 수행한 검증
송신은 PC2에서 PC1 역할을 모의했다. 실제 별도 물리 PC1에서의 전송 시험은 아직 남아 있다.
정상 요청·동일 요청 재전송 후 원격 회원1명·5개 관계 기록 확인, 원본 3건/정제 bundle1건/적재 job1건/내용충돌 격리1건 확인(세 번째는 같은 ID의 다른 내용), 원격 DB 조회 화면 readback 확인. 인증 401·빈 manifest 422 확인.
운영 중 PC3 서버나 네트워크를 고의 중단하는 시험은 수행하지 않았다.

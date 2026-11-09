# NODEVERSE Django 수신 API 연동 준비

기준: 2026-11-09 전달 PDF 7쪽. 이 문서는 전달된 API 계약을 참고한 구현이며 상대 Django 소스 코드·실제 서버와 대조한 결과가 아니다.

## 현재 상태
대상 DB 호스트는 사용자 제공 192.168.0.167. PDF는 Django가 192.168.0.29의 localhost:8000에서만 수신하며 LAN 주소·실제 키는 미준비라고 명시한다. API가 167로 이전됐는지와 포트는 아직 미확인이다. 3306/27017은 API 포트가 아니다. 기존 INGEST_KEY는 이 API에 사용하지 않는다.

## 제공 기능
- Python 표준 라이브러리 기반 서버 간 전송 클라이언트. Authorization: Bearer GAME_SERVER_API_KEY 사용.
- SQLite 영속 순차 큐: 이전 요청 성공 뒤 다음 요청 전송. 동일 ID·sequence·내용 재시도.
- 회원 응답의 player_id를 보관하고 세션 요청에 대입. 게임 원본 member_id를 대신 넣지 않는다.
- 네트워크 오류/5xx는 제한 재시도 후 대기. 400/401/409/413/415 및 redirect는 차단 상태로 정지. 키나 원격 응답 원문을 로그에 저장하지 않는다.
- 사전 검증: 필수 필드·UUID·시간대·크기·음수/0 순서·중첩 비밀 필드 등. 서버의 전체 검증을 대체하지 않는다.
- 로컬 원본 조사 도구: 건수·인덱스·validator·샘플 필드 자료형만 출력. DB 문서 값과 회원정보는 내보내지 않는다.

## 실행
실제 키는 서버 환경 변수에만 설정하며 Git에 올리지 않는다. 새 작업 폴더를 지정한다.

```powershell
python client.py sample --folder C:/nodeverse-transfer/live-test
python client.py queue --folder C:/nodeverse-transfer/live-test --manifest C:/nodeverse-transfer/live-test/sample.json
# 확정 주소와 별도 발급 키 설정 후에만 send 실행
$env:HANDOFF_API_BASE_URL='http://확정된_API호스트:포트'
$env:GAME_SERVER_API_KEY='별도로_발급받은_키'
python client.py send --folder C:/nodeverse-transfer/live-test
python client.py status --folder C:/nodeverse-transfer/live-test
```

sample은 회원 → problem → session → run → attempt → operation_succeeded까지의 6개 요청을 만든다. 자동 종료 요청은 포함하지 않는다. PDF에 요구된 문제 종료 이벤트의 정확한 event_type과 추가 필수 필드가 명시되지 않아 추정하지 않았기 때문이다. 전체 종료 흐름은 상대방의 이벤트 enum·규칙을 받은 뒤 명시적으로 작성한다. end_attempt/end_run/end_session 전송 형식은 지원하지만 순서·참조·시간 관계의 최종 검증은 수신 서버가 수행한다.

동일 큐에서 sample/queue를 반복 생성하지 않는다. 재시도는 send만 다시 실행한다. blocked 상태에서는 자동 변경·스킵을 하지 않으며 원인 확인 후 별도 수정 배치를 준비한다. 새 API origin으로 기존 큐를 자동 전환하지 않는다. 하나의 큐는 한 프로세스에서만 사용한다. 이 도구는 게임 로그인 검증을 수행하지 않으며 실제 운영 회원에 대해서는 게임 서버의 검증 완료 뒤에만 호출한다.

## 데이터 이전 계획
현재 로컬 raw_events/curated/runtime_events/metrics 등과 대상의 game_sessions/game_problems/problem_runs/solution_attempts/gameplay_events는 서로 다른 모델이다. 그대로 덮어쓰기나 컬렉션 이름 변경으로 이전하지 않는다.
1. inventory.py로 원본 조사. 더미·검증 데이터는 대상 실데이터와 구분한다.
2. 실제 회원 원본 member_id → 회원 API 응답 player_id 매핑 확보. 이 프로젝트에는 이전할 실제 MySQL 회원 DB가 구축돼 있지 않으므로 회원 담당자의 원본/승인이 필요하다.
3. topic(stack/queue/tree), 문제 코드와 UUID, 상태, BSON Date, sequence(대상 1 이상)를 대조한다. 기존 sequence 0을 일괄 +1하거나 problem_id로 문제 내용을 추정하지 않는다.
4. 관계와 의미가 확정된 데이터만 임시 DB 또는 테스트 API로 검증. 최종 nodeverse_logs에 직접 쓰지 않는다.
5. 문서에는 exit_ 수집 유형과 일부 기존 이벤트의 대응 규칙이 없으므로 회원·세션 관계와 함께 추가 협의한다.

## 검증과 미완료
python -m unittest -v test_client.py 는 로컬 모의 HTTP 서버로 검증한다. 상대 서버 실연동 성공을 의미하지 않는다. 실제 LAN 수신 주소, 발급 키, 전체 이벤트 enum, 최종 Kafka/Spark 배치 여부가 필요하다. 현재는 기존 수집 경로를 자동 forwarding하거나 이중 기록하지 않는다. MySQL 관리자·권한·비밀번호·Django 세션을 자동 이관하지 않는다.

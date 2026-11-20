# Spark 최종 출력 → 대상 DB 매핑안

기존 source는 curated / runtime_events 등이며, 아래 구조의 데이터는 별도 검증/매핑 후 manifest로 준비한다. 기존 ID를 무조건 UUID로 바꾸거나 sequence를 일괄 +1하지 않는다.

| 대상 | 필수 매핑 | 현재 source에서 확인할 점 |
|---|---|---|
| game_members | 원본 member_id, display_name → external_member_key, UUID, nickname | player_id는 현재 가명 문자열. 실제 회원 원본 ID와 별도 연결 필요 |
| game_sessions | session UUID, 회원 UUID, topic, started_at | topic·시작 레코드가 없으면 적재 보류 |
| game_problems | UUID, task_id 문제 코드, content_version, title, topic | 현재 problem_id만으로 제목·버전·topic을 추정하지 않음 |
| problem_runs | run UUID, session UUID, 문제 정의 UUID, started_at | 기존 run_id는 실행 식별자이며 대상 문제 실행 의미와 같은지 확인 |
| solution_attempts | attempt UUID, 문제실행 UUID, number, started_at | 기존 attempt_id가 UUID가 아닐 수 있음. 고정 매핑 필요 |
| gameplay_events | event UUID, session/run/attempt UUID, sequence, event_type, occurred_at | operation_succeeded/failed 및 operation·상태 정보 등 원본 필수값 확보 |

## 이벤트 대응 상태
- operation → 성공 여부/연산명 정보가 없으면 operation_succeeded로 자동 변환하지 않는다.
- attempt_failed → 시도 outcome과 원인 정보의 의미를 대조한다. 연산 실패와 동일시하지 않는다.
- hint_used → hint_id/hint_step 없으면 구조화 hint로 임의 생성하지 않는다.
- problem_started/attempt_started → 시작 레코드와 행동 이벤트의 대응 정책을 확정한다.
- exit_ → 기술 장애와 학습 abandoned 상태를 자동으로 동일시하지 않는다.

## 실시간 가동 전 인수 기준
테스트 회원 UUID가 MySQL CHAR32/MongoDB 문자열에 동일하게 연결, 5개 컬렉션 참조 정상, 같은 UUID 재전송 중복 없음, UTC/밀리초 시간 표시 정상, 상태와 지표/행동 로그가 대상 대시보드에 표시됨. 현재 로컬 시험은 DB 적재만 검증하며 상대 대시보드 표시는 아직 미검증이다.

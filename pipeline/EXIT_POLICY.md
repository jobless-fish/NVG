# EXE 종료 수집 정책 및 연결 계약

## 분류
모든 종료 관련 event_type은 exit_ 접두어로 저장한다.

| 분류 | 필요한 evidence | 의미 |
|---|---|---|
| exit_normal | game_shutdown_complete | 게임 정상 종료 완료 기록 |
| exit_crash_confirmed | crash_report | 별도 크래시 보고 근거 |
| exit_forced_confirmed | user_confirmed | 사용자 강제 종료 확인 |
| exit_unexpected_unknown | launcher_observed / next_launch_recovery | 종료 원인 미확인 |
| exit_hang_suspected | watchdog | 외부 감시기의 메인 루프 정지 의심 |
| exit_connection_lost_suspected | server_timeout | 서버 수신 단절 의심 |

run_started/run_heartbeat는 실행 관측이며 종료 분류가 아니다. 런처 heartbeat는 프로세스 생존만 나타내며 메인 루프 정상 동작을 보장하지 않는다. 현재 자동 생성되는 종료 분류는 exit_normal과 exit_unexpected_unknown이다. 크래시 덤프 수집기·메인 루프 watchdog·서버 timeout 스케줄러는 아직 연결하지 않았다. API는 증거 유형 일치만 검증하며 증거의 진실성을 보증하지 않으므로 운영에서는 이벤트 발행 주체별 권한을 분리해야 한다.

## 런처 실행
Python 3 런처를 제공한다. 배포용 런처 EXE 패키징·코드 서명은 별도 작업이다.

```powershell
$env:INGEST_KEY="서버와 동일한 키"
python launcher.py C:/games/NODEVERSE.exe --build 0.1.0
```

동시에 하나의 런처만 실행한다. EXE 직접 실행은 런처 감시를 우회하므로 사이트에는 최종적으로 런처를 포함해 배포한다. 기본 SQLite 저장 위치는 %LOCALAPPDATA%/NODEVERSE/telemetry 이며 네트워크 장애에도 큐를 유지한다. 정상 접수 202 후 삭제, 401/422는 로컬 rejected 상태로 격리한다. 현재 큐 용량 상한·사용자에게 보이는 오류 알림·재시도 백오프 개선은 운영 전 과제다. 플레이어 ID는 설치별 가명이며 게임 계정과 아직 연결하지 않는다.

게임의 정상 종료 처리 마지막 단계에서 환경변수 NODEVERSE_EXIT_MARKER 경로에 NODEVERSE_RUN_ID 값을 기록하고 파일을 닫은 후 종료해야 한다. 해당 통합이 없으면 종료 코드 0이어도 exit_unexpected_unknown으로 남긴다. 게임 씬은 이번 변경에서 수정하지 않았다. 학습 이벤트 전송 큐는 이 런처가 대신 수집하지 않는다. 게임 측에서도 동일한 event_id를 보존하는 영속 큐를 연결해야 한다.

## 서버 라우팅·격리
Kafka 원본 소비자는 수신 원본을 보존한다. Spark 처리에서는 학습 이벤트는 curated, 실행 이벤트는 runtime_events, exit_ 이벤트는 추가로 incidents에 저장한다. incidents에는 정상 종료도 포함되므로 장애 지표 조회 시 exit_normal을 제외해야 한다.
전역 event_registry에서 ID와 정규화 본문 SHA256을 비교한다. 같은 ID·같은 내용은 멱등 처리한다. 같은 ID·다른 내용은 quarantine_events에 event_id_conflict로 저장하며 기존 정제 데이터를 변경하지 않는다. received_at은 비교에서 제외한다. Kafka 직접 유입의 규격 오류·JSON 오류도 격리한다. API 422 입력은 브로커 접수 전에 거부하며 원문을 서버에 보관하지 않는다.

## 분석 기준
metrics의 실패는 attempt_failed만 계산한다. exit_ 이벤트는 학습 실패·성공 수치에 포함하지 않는다. runtime_events를 run_id로 연결해 종료를 별도로 조회한다. 현재 학습 Event에 run_id 연결과 시도별 interrupted_technical/interrupted_unknown 결과 테이블 생성은 후속 과제이며, 단순 미수신으로 실패나 이탈을 확정하지 않는다.

## 인수 테스트
정상 종료 마커 유무, 작업 관리자 종료, 런처까지 종료 후 재시작, 서버 중단 후 재연결, 동일 ID 재전송·다른 내용 충돌을 확인한다. 덤프는 현재 업로드하지 않는다. 보관기간·삭제 정책과 용량 제한은 실제 운영 전 확정해야 한다.

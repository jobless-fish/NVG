# 직접 DB 적재기 - Kafka/Spark 정제 후 서버 DB 저장

대상: MySQL nodeverse.game_members / MongoDB nodeverse_logs의 game_sessions, game_problems, problem_runs, solution_attempts, gameplay_events. 서버 후보 192.168.0.167:3306/27017. 별도 HTTP 수신 API는 사용하지 않는다. 관리자·권한·Django 내부 테이블은 읽거나 쓰지 않는다.

## 구현 범위
- game:member:<원본ID>로 회원 조회. 기존 live UUID 유지, 신규 UUID 생성. MySQL CHAR(32) ↔ MongoDB 하이픈 UUID 변환.
- 문제 코드·버전의 고유 인덱스와 참조 UUID 확인. 같은 ID의 내용 변경, 다른 회원 외부 키 대소문자 충돌, demo 회원 충돌 거부.
- 세션 → 문제 실행 → 시도 → 이벤트 참조·열린 상태·시간 순서 검증. sequence/number는 1 이상, 중첩 비밀 필드 차단.
- UTC BSON Date(밀리초 정밀도) 저장. MongoDB 자료형·인덱스는 대상 사전점검.
- 기존 문서를 덮어쓰지 않는 재전송. 종료는 동일 상태·시각 재시도 허용, 자식 미종료·종료 전 발생 이벤트 위반 거부.
- SQLite 진행표: DB 저장 후 프로세스가 종료돼도 재실행 시 동일 ID로 확인·재개. 다른 manifest·다른 대상 DB에 같은 진행표 재사용 거부.
- MySQL과 MongoDB 사이의 분산 트랜잭션은 없다. 이미 성공한 회원/로그는 보존하고 실패 위치부터 재실행한다. 자동 삭제·역방향 롤백 없음.

## 실행 단계
1. Python 3.11에서 pip install -r requirements.txt. DB 계정은 별도 환경 변수로만 입력한다. .env.example은 항목 목록이며 자동 로딩하지 않는다.
2. sample 생성 및 plan 확인. 이 단계는 DB에 접속하지 않는다.

```powershell
python loader.py sample --output C:/nodeverse-transfer/direct-test.json
python loader.py plan --manifest C:/nodeverse-transfer/direct-test.json
```

3. 팀원이 확인한 정확한 진행 중 상태값을 DIRECT_SESSION_OPEN_STATUS, DIRECT_RUN_OPEN_STATUS, DIRECT_ATTEMPT_OPEN_OUTCOME에 설정한다. 문서만으로 문자열 enum을 추정하지 않았다. DIRECT_MONGO_URI는 인증 포함 연결 문자열, DIRECT_MYSQL_USER/PASSWORD는 적재 계정이다.
4. python loader.py check 로 버전·game_members 필수 컬럼·고유 인덱스·대상 컬렉션을 확인한다. 대상 구조를 생성/변경하지 않는다.
5. 해당 테스트 세션에 다른 적재 프로세스나 Django API가 쓰지 않도록 합의한다. DIRECT_EXCLUSIVE_WRITER=1 설정 후 명시적으로 apply 실행.

```powershell
python loader.py apply --manifest C:/nodeverse-transfer/direct-test.json --journal C:/nodeverse-transfer/direct-test.sqlite
```

샘플은 테스트 회원 1명·문제 정의·세션·시도·연산 이벤트로 구성하며 실제 계정 로그인 검증을 대신하지 않는다. 재실행은 같은 JSON·진행표로 한다. 새로운 샘플을 같은 파일에 덮어쓰지 않는다. 프로그램 간 동시 상태 변경은 지원하지 않는다. MySQL advisory lock은 이 적재기끼리만 직렬화하며 외부 프로그램과의 협의가 필요하다.

## 시간·상태 관련 미확정
- 시작 상태/outcome의 정확한 문자열은 대상 소스에서 확정해야 하므로 필수 설정이다.
- 종료 갱신은 DIRECT_FINALIZATION_POLICY_CONFIRMED=1로 합의 완료를 명시한 경우만 실행한다. session duration_ms는 현재 종료-시작의 경과시간이다. active_ms/paused_ms는 원본에 재개·일시정지 규칙이 없어 추정하거나 0으로 채우지 않는다.
- end_run/end_session 이벤트와 상태가 대시보드 지표에 어떻게 사용되는지는 실제 대시보드와 공동 검증해야 한다.
- 종료 event_type 매핑, enum 추가, 실제 풀이/일시정지 시간 정책 확정 전에는 자동 실시간 가동하지 않는다.

## Kafka/Spark 연결 경계
현재 Spark 출력은 curated 단일 이벤트다. 이 적재기가 사용하는 관계형 레코드 계획은 direct/FIELD_MAPPING.md에 정의한다. 존재하지 않는 세션·문제·시도와 회원을 추측해서 생성하지 않는다. 현 단계는 명시적 manifest 적재이며 기존 Spark stream.py를 자동 연결하거나 기존 raw 데이터 전체를 서버 DB로 보내지 않는다. 계정·필수 매핑·시간 규칙을 확정하고 테스트 세트가 상대 대시보드에 표시된 뒤에만 Spark 배치 sink를 활성화한다. Spark checkpoint는 DB 적재 성공 후에만 진행시키도록 연결해야 한다.

## 권한과 검증
적재 계정: game_members의 SELECT/INSERT/UPDATE, 대상 MongoDB 컬렉션의 read/insert/update 및 인덱스 메타데이터 조회. DDL·관리자 계정 수정은 불필요하다. 대시보드는 별도 read-only 계정을 권장한다. 비밀번호는 Git/로그/manifest에 넣지 않는다. 서버가 원격망에 있으면 인증과 암호화 연결 정책도 별도로 적용한다.

테스트: docker compose --project-name nodeverse-direct-loader-check -f compose.test.yaml up --build --abort-on-container-exit --exit-code-from checks

별도의 로컬 MySQL 8.4/MongoDB 8.0에만 테스트 데이터를 생성한다. 테스트 fixture는 대상 Django 마이그레이션을 복제한 것이 아니므로 실서버 구조 검증과 화면 확인을 대체하지 않는다. 두 DB는 호스트 포트를 공개하지 않는다. 테스트 컨테이너는 종료 후 데이터를 유지하며 실제 운영 DB를 삭제하지 않는다.

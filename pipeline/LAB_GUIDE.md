# NODEVERSE 파이프라인 실험실

## 1. 실행
Docker Desktop Linux 컨테이너 모드, Python 3(호스트 통합 테스트용).
기존 .env가 있다면 덮어쓰지 않습니다. 없을 때만 .env.example을 복사하고 INGEST_KEY를 설정합니다.

```powershell
# pipeline 폴더에서
Copy-Item .env.example .env  # 최초 한 번만
 docker compose --profile lab up -d --build
```

기본 대시보드 http://localhost:8010 / 수집 API http://localhost:8000/docs.
화면의 접속 키에는 .env의 INGEST_KEY를 입력합니다. 서버 측에서만 수집 키를 사용하며 웹 페이지에 키를 내장하지 않습니다. 브라우저 입력 키는 페이지 메모리에서만 사용합니다. 실험 API와 수집 API의 키를 공유하는 로컬 MVP이므로 운영 시 권한을 분리해야 합니다.
MongoDB·Kafka는 외부 포트를 공개하지 않습니다. MongoDB 문서는 인증된 대시보드의 허용된 컬렉션만 읽을 수 있습니다.

## 2. 다른 PC에서 화면 보기
.env에 LAB_BIND_IP=서버의 내부IP를 추가한 후 같은 실행 명령으로 재생성합니다. 예: LAB_BIND_IP=192.168.0.81 이면 http://192.168.0.81:8010 에 접속합니다. 기본 localhost 바인딩 대신 지정 IP에 바인딩됩니다. 같은 LAN에서만 사용하며 방화벽 TCP 8010 허용이 필요할 수 있습니다. 실험실은 Docker 내부 gateway:8000으로 전송하므로 수집 API의 LAN 공개 여부와 독립적입니다.

## 3. 화면 사용
접속 키 입력 → 연결 → 시드·시나리오 수·속도 설정 → 새 배치 시작.
기본 64개 시나리오는 중복·충돌 재전송을 포함해 80개 HTTP 요청을 만듭니다. 전송 중지는 새 전송을 중지하고 이미 접수된 데이터의 저장을 기다립니다. 한 번에 한 배치만 실행하며 동시 시작은 409로 거부합니다. 완료 배치를 선택해 MongoDB 원본·정제·종료·격리·지표 문서를 조회할 수 있습니다. 검증 로그 저장은 전체 요청·응답·기대값·최종 상태를 JSON으로 내려받습니다.

상태: sending=전송 중, settling=저장 대기, passed=응답과 DB 기대값 일치, failed=불일치/오류, stopped=사용자 중지, interrupted=Lab 재시작으로 중단. 서버 재시작 시 중단 배치는 자동 재개하지 않습니다. 이미 전송한 데이터는 보존됩니다.

## 4. 데이터 규약과 생성 분포
기준: DESIGN.md, EXIT_POLICY.md, gateway.py의 Event/RuntimeEvent. formal schema는 현재 API /openapi.json에서도 확인할 수 있습니다.
8개 시나리오를 균등 순환해 누락 없이 검증하고 시드로 플레이어·문제·행동·소요시간·지연 일수를 랜덤화합니다. 같은 시드는 동일한 구조·수치 선택을 재현하지만 UUID·시각은 배치별로 달라집니다. 실제 행동의 확률 분포나 인과관계를 재현한 학습용 데이터는 아닙니다.

| 시나리오 | 기대 API | 저장 규칙 |
|---|---|---|
| learning | 202 | raw + curated + metrics |
| runtime | 202 | raw + runtime_events, exit_는 incidents에도 저장 |
| duplicate | 202 두 번 | raw 2건, curated 1건 |
| conflict | 202 두 번 | raw 2건, curated 1건, quarantine 1건 |
| invalid | 422 | API 거부, Kafka 미적재 |
| evidence | 422 | 잘못된 크래시 근거, API 거부 |
| unauthorized | 401 | 잘못된 키, Kafka 미적재 |
| delayed | 202 | 1~4일 과거 시각, 원본·정제 적재 |

runtime은 run_started/run_heartbeat와 모든 exit_ 6종을 순환합니다. 크래시·멈춤은 모의 데이터이며 실제 프로세스 장애 수집 성공을 뜻하지 않습니다. 모든 플레이어는 lab-배치ID- 접두어로 식별해 조회를 분리합니다. 기존 데이터 삭제 기능은 없습니다.

## 5. 통합 검증
```powershell
# 기본 localhost로 실행한 경우
python test_lab.py
# 지정 IP로 실행한 경우
$env:LAB_URL='http://192.168.0.81:8010'
python test_lab.py
```
시드 42/64개, 867/128개 배치의 정확한 원본·정제·실행·종료·격리 건수 및 학습 지표(events/failures/successes/hints)를 비교합니다. 401·422는 의도된 응답이므로 테스트 오류가 아닙니다. 모든 runtime 유형, 인증 제어, 동시 시작 방지, 중지, 전체 로그 내보내기를 검사합니다. 결과 JSON에는 키를 기록하지 않습니다.

## 6. 관측과 운영 범위
화면은 MongoDB 실제 저장 건수와 생성 기대값을 2초 간격으로 비교합니다. Kafka consumer lag나 Spark 배치 지연을 직접 계측하지 않으며 고부하 성능 벤치마크도 아닙니다. 최대 1,000개 기본 시나리오, 설정상 최대 20요청/초이고 실제 처리량은 HTTP 대기시간으로 낮아질 수 있습니다. Spark 전체 집계 구조는 소규모 로컬 검증용입니다. 장시간 반복 실험 시 디스크 사용과 보관 정책을 별도로 관리해야 합니다.

종료: docker compose --profile lab down (볼륨 유지). down -v는 기존 데이터를 삭제하므로 일반 종료에 사용하지 않습니다. 규약 변경 배포 시 gateway·lab 이미지 재빌드 및 Spark 재시작이 필요합니다.

## 쉬운 그래프 요약
/overview 에서 접수·거부 도넛 그래프, 저장함별 건수, 학습 행동·종료 유형·격리 사유 막대 그래프를 볼 수 있습니다. 같은 접속 키를 사용하며 선택한 실험을 3초마다 갱신합니다. 각 저장함은 중복될 수 있어 합산하지 않습니다. 막대 길이는 그래프별 최댓값 기준이며 정확한 건수를 함께 표시합니다. 종료는 모의 데이터입니다.

# NODEVERSE 로컬 로그 파이프라인

현재 제공 범위는 실행 가능한 MVP입니다. 목표 구성과 차이·미구현 항목은 [설계서](DESIGN.md)에 명시했습니다.

## 시작
Docker Desktop의 Linux 컨테이너를 사용합니다. 이 폴더에서 다음 명령을 실행하세요.

```powershell
Copy-Item .env.example .env
# .env의 INGEST_KEY를 임의의 긴 키로 변경
 docker compose up -d --build
 docker compose ps
```

최초 실행은 이미지 및 Spark 의존성을 내려받아 수분이 걸립니다. http://localhost:8000/docs 에서 규격을 확인하고 X-API-Key에 설정한 키를 넣습니다. /health는 Kafka 연결을 확인합니다.

```powershell
$env:INGEST_KEY=".env에 설정한 키"
python smoke.py
```

테스트는 고유 player_id로 원본 두 건을 보냅니다. Python 표준 라이브러리와 Docker CLI만 필요합니다. 기본 예제 키를 그대로 사용했다면 환경 변수 생략이 가능합니다.

## 운영 확인
```powershell
docker compose logs --tail 100 gateway raw-worker spark
docker compose exec mongo mongosh nodeverse --eval 'db.curated.find().limit(5)'
docker compose exec mongo mongosh nodeverse --eval 'db.metrics.find().limit(5)'
docker compose down
```

down은 컨테이너만 중지하고 볼륨을 유지합니다. 데이터와 checkpoint는 함께 백업해야 합니다. `down -v`는 데이터를 지우므로 일반 종료에는 사용하지 않습니다. Kafka 7일 보관을 넘겨 소비가 멈춘 경우 원본 기반 별도 재처리가 필요합니다.

## 게임 담당자 전달사항
POST /v1/events로 한 이벤트씩 비동기 전송합니다. event_id는 최초 생성 후 재시도에도 유지합니다. 202 수신 후 큐에서 제거하고 503·통신 실패는 재시도합니다. 401·422는 설정/규격을 수정해야 합니다. 실제 씬과 전송 큐 연동은 아직 포함하지 않았습니다. 관리자 서비스는 MongoDB curated/metrics를 서버 측에서 조회하며 브라우저가 DB에 직접 접속하지 않습니다.

## EXE 종료 수집
[종료 정책 및 런처 연결 계약](EXIT_POLICY.md)을 확인하세요. 모든 종료 분류는 exit_ 접두어입니다. `python test_exit.py`로 종료 격리·ID 충돌·오프라인 큐를 검증합니다.

## 더미 파이프라인 실험실
`docker compose --profile lab up -d --build`로 생성·전송·관측 화면을 실행합니다. [실험실 안내](LAB_GUIDE.md)를 참고하세요. 기본 주소는 http://localhost:8010 입니다.

## 다른 PC로 이식
연결 설정·MongoDB 백업/복원·Kafka 위치 ID 충돌 방지는 [이식 안내](MIGRATION.md)를 참고하세요.

## Django 서버 간 연동
2026-11-09 상대팀 PDF 기준의 별도 Bearer 클라이언트와 이전 전 구조 조사 도구를 [handoff 안내](handoff/README.md)에 추가했습니다. 실제 LAN 주소·키는 미확정이며 기존 API를 자동 전달하지 않습니다.

## 직접 DB 적재
Kafka/Spark 정제 후 서버 MySQL·MongoDB로 쓰는 별도 적재기와 필드 매핑안은 [direct 안내](direct/README.md)를 참고하세요. 실제 계정·상태 정책 확정 전 기존 스트림에는 자동 연결하지 않습니다.

## 자동 원격 적재
새 관계 레코드 수집 API /v2/play-records와 direct 프로필 writer를 [자동 적재 안내](direct/LIVE.md)에 추가했습니다. 기존 /v1/events를 자동 변환하는 기능과는 구분합니다.

## 최신 작업 현황·공유 자료
[작업 상태와 문서 모음](docs/STATUS.md)에서 PC별 운영 지침, 현재 아키텍처, AWS 검토 결과와 남은 작업을 확인하세요.

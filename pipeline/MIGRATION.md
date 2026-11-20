# 다른 PC로의 MongoDB 이식 설계

## 원칙
애플리케이션 코드에 서버 PC IP·Windows 사용자 폴더를 넣지 않는다. 전체 Docker 스택을 이동하면 mongo:27017 서비스 이름은 그대로다. MongoDB 연결은 MONGO_URI, DB 이름은 MONGO_DATABASE로 raw-worker·Spark·Lab에 동일하게 주입한다. 기본 MongoDB 이미지 7.0.16을 유지한다. 다른 메이저 버전으로의 업그레이드는 이식과 분리한다.

## 이동 범위 선택
1. 권장: 전체 스택 이동. MongoDB 백업 외에 Kafka 데이터 볼륨과 Spark checkpoint 볼륨도 쓰기가 중지된 동일 시점 기준으로 이관한다. MongoDB 백업 파일만으로 전체 파이프라인이 복원되는 것은 아니다.
2. MongoDB만 이동하고 Kafka는 새로 시작: 아래 도구로 데이터·인덱스를 옮기되, 기존 Kafka backlog가 0이고 모든 접수 이벤트가 raw/curated 등에 반영됐는지 먼저 확인한다. 새 Kafka는 소비 위치·checkpoint를 새로 시작한다. .env의 KAFKA_EPOCH에 새 UUID와 ':'를 넣어 원본 및 격리 메시지 위치 ID 충돌을 방지한다. 예: 3cfa...:. 이전 MongoDB와 같은 Kafka를 계속 쓰는 경우 epoch를 바꾸지 않는다.

## MongoDB 백업
프로젝트의 pipeline 폴더에서 Python 3와 Docker CLI로 실행한다. 도구는 현재 번들 Mongo 서비스에만 적용된다. 외부 인증 DB의 관리자 이관은 별도 절차다.

```powershell
python mongo_transfer.py backup --project pipeline --folder D:/nodeverse-transfer/backup-20261106
```

lab·gateway·raw-worker·spark를 중지하고 MongoDB는 켜 둔 채 mongodump --archive --gzip을 실행한다. 폴더에는 압축 BSON 백업, SHA256, DB 이름, 컬렉션별 건수·인덱스 목록이 남는다. 백업 전후 목록이 다르면 실패 처리한다. 다른 외부 쓰기 프로그램도 반드시 중지해야 한다. 백업 후 writer는 자동 재개하지 않는다. 원래 compose 옵션으로 재개한다.

## 새 PC 복원
저장소의 같은 커밋, .env.example에서 작성한 새 PC용 .env, 백업 폴더를 옮긴다. 비밀 키는 Git에 올리지 않고 별도 전달한다. Docker 데이터 폴더를 실행 중 복사하거나 JSON 내보내기만으로 이식을 대신하지 않는다.

```powershell
# .env에 INGEST_KEY 설정 후, MongoDB만 먼저 실행
 docker compose --project-name pipeline up -d --wait mongo
python mongo_transfer.py restore --project pipeline --folder D:/nodeverse-transfer/backup-20261106
python mongo_transfer.py verify --project pipeline --folder D:/nodeverse-transfer/backup-20261106
```

도구는 대상 DB에 컬렉션이 하나라도 있으면 복원을 거부한다. --drop은 사용하지 않는다. 복원 실패 시 부분 데이터가 남을 수 있으므로 원본 백업을 유지하고 별도의 빈 대상에서 재시도한다. 백업 해시·컬렉션 이름·건수·인덱스를 비교한다. 문서 전체 내용의 일치나 다른 물리 PC의 네트워크까지 보증하는 검사는 아니다.

복원 후 이동 범위에 맞는 Kafka/체크포인트 상태를 준비한 뒤 docker compose --profile lab up -d --build로 실행한다. MongoDB-only 이식 시 backlog 미확인 상태에서 재개하지 않는다. 새 Kafka를 시작할 때 KAFKA_EPOCH를 모든 raw-worker·Spark에 동일하게 적용한다. 기존 클라이언트 재전송의 event_id는 유지한다.

## 새 PC에서 바꿀 값
- LAB_BIND_IP: 새 PC의 내부 IP 또는 기본 localhost. 방화벽은 필요한 LAN 포트만 허용한다.
- MONGO_URI: 같은 Docker 스택이면 mongodb://mongo:27017 유지. MongoDB를 별도 PC에 둘 경우 인증·접근 제한·전송 암호화를 구성한 주소로 변경한다. 현재 기본 MongoDB는 외부 포트를 공개하지 않는다.
- MONGO_DATABASE: 기본 nodeverse. 백업/복원 도구의 --database도 같은 이름으로 지정한다.
- 클라이언트 서버 주소: 새 서버 IP 또는 DNS로 변경한다. MongoDB에 클라이언트가 직접 접속하지 않는다.

## 롤백
이전 PC의 데이터와 백업을 유지한다. 새 PC 인수 테스트 전 기존 DB·볼륨을 삭제하지 않는다. 전환 중에는 한쪽만 쓰기 서버로 운영한다. 새 서버에서 받은 이벤트를 이전 서버로 되돌리는 데이터 병합은 별도 작업이며 자동 수행하지 않는다.

## 참고
https://www.mongodb.com/docs/database-tools/mongodump/
https://www.mongodb.com/docs/database-tools/mongorestore/

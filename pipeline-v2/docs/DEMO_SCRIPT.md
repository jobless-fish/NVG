# 시연 대본: 강제 종료 후에도 결과가 같다 (P6)

준비: 스택이 떠 있고 README "점검 순서"의 `$env:INGEST_KEY`, `$V`를 설정한 상태.

## 1. 평소 상태 보여 주기 (1분)

```powershell
Invoke-Expression "$V counts"
```
"Kafka에 들어온 건수와 Bronze 행 수가 토픽마다 같고, Silver에는 중복이 0, Gold 합계는 Silver 집계와 같습니다."

## 2. 보내는 도중에 Spark 죽이기 (2분)

```powershell
Start-Job { Set-Location $using:PWD; $env:INGEST_KEY=$using:env:INGEST_KEY; python simulator.py smoke --count 3000 --run-id demo-kill }
Start-Sleep 5
docker kill nodeverse-dev-spark-1          # 정상 종료가 아닌 강제 종료
docker compose -f compose.json up -d spark
Receive-Job -Wait (Get-Job)                 # 3000건 모두 202
```
"Spark가 처리 도중 죽었지만, 수집 API는 Kafka에 저장된 것만 202로 답했으므로 이벤트는 Kafka에 남아 있습니다. Spark는 Delta 체크포인트에서 마지막으로 커밋한 위치부터 다시 읽습니다."

## 3. 다시 맞춰 보기 (1분, 재시작 후 약 1분 기다림)

```powershell
Invoke-Expression "$V counts --run-id demo-kill"   # silver.learning_events rows = 3000, duplicates = 0
Invoke-Expression "$V counts"                      # passed = true
```
"재시작 중에 같은 배치가 한 번 더 처리돼도 Silver는 상태 저장소에 남은 event_id로 중복을 거르고 같은 배치 번호의 쓰기는 Delta가 건너뛰어 늘지 않고, Gold와 MongoDB는 창 단위 덮어쓰기라 값이 부풀지 않습니다."

## 4. 타임 트래블 (2분)

```powershell
Invoke-Expression "$V history --table silver.learning_events --limit 6"
Invoke-Expression "$V timetravel --table silver.learning_events --versions 6"
```
"Delta는 커밋마다 버전이 남습니다. 강제 종료 직전 버전과 재시작 후 버전의 행 수를 `VERSION AS OF n`으로 바로 비교할 수 있습니다."

## 5. 대시보드 값 (1분)

```powershell
docker compose -f compose.json exec mongo mongosh nodeverse_logs --quiet --eval "printjson(db.rt_summary.findOne()); printjson(db.rt_minigame_1m.find().sort({updated_at:-1}).limit(3).toArray())"
```
"서버는 이 컬렉션을 읽기만 합니다. 같은 배치를 다시 처리해도 `_id` 기준 upsert라 값이 늘지 않습니다."

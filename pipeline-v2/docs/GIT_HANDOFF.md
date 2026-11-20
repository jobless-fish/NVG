# Git 공유 범위와 팀원 인수 안내 (2026-11-20)

## 최신 게임 확인이 먼저입니다

**기존 NVG의 게임은 오래된 버전일 수 있습니다. 게임 작업/병합 전 담당자에게 반드시 질문하세요.**

> 최신 게임은 NVG와 별도 nodeverse-game 중 어느 저장소/로컬 폴더/브랜치/커밋/EXE인가요?
> 이번 변경을 반영할 기준과 병합 대상 브랜치는 어디인가요?

게임 보고서는 junbum8398-blip/nodeverse-game의 70daeaa/1d43e5c를 언급했지만 현재 최신인지는
확인하지 않았습니다. 이 공유는 게임 씬/스크립트/프로젝트 설정 변경을 포함하지 않습니다.
PR 대상은 dev이며 자동 병합하지 않습니다.

## 두 파이프라인을 구분하세요

- pipeline/: 기존 PC1 → PC2 :8000/v2/play-records → Kafka/Spark → direct_outbox → .167 DB 경로.
  기존 :8010 대시보드/백업·복원/직접 적재 코드와 지난 보고서를 보존합니다.
- pipeline-v2/: Desktop/nodeverse-pipeline에서 확인한 별도 Kafka 3대 + Spark + Delta Bronze/Silver/Gold
  + 로컬 MongoDB rt_* 경로입니다. 기존 폴더를 덮어쓰거나 운영 서비스를 자동 전환하지 않습니다.
- v2 시험: 별도 nodeverse-v2-review 프로젝트, localhost:8002(API)/27019(MongoDB).
  로컬 전용이며 팀원 PC에서 바로 접근하는 주소로 공지하지 않습니다.
- .167 MySQL/MongoDB의 접속/읽기와 기존 관계 검사는 정상입니다. 새 v2의 원격 자동 적재와
  최신 게임 EXE → 팀원 대시보드 통합은 미완료입니다.

## 먼저 읽을 자료

1. [실제 시험과 보완](E2E_TEST_REPORT_2026-11-20.md)
2. [팀원 AI 상세 인수 보고서](TEAM_AI_HANDOFF_2026-11-20.pdf)
3. [Delta 문서 대조·요구 1~5 검토](DELTA_REQUIREMENTS_REVIEW_2026-11-20.pdf)
4. [같은 검토의 Markdown](DELTA_REQUIREMENTS_REVIEW_2026-11-20.md)
5. [현재 연동 차이](INTEGRATION_STATUS.md), [기술 점검](TECHNICAL_REVIEW.md)
6. [수치·세부 검증 결과](e2e-results-2026-11-20.json), evidence-2026-11-20/

PDF/시험 기록의 로컬 경로·미등록 Git·미업로드 문구는 해당 작성 시점의 기록입니다.
현재 공유 위치는 이 브랜치의 pipeline-v2/이며 실행 위치는 클론한 폴더로 치환하세요.
단기 시험은 운영 SLA/최신 EXE/원격 적재의 완료 증거가 아닙니다.

## 재현

```powershell
cd pipeline-v2
# 기존 비밀 파일이 없을 때만 예제를 복사합니다.
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
# .env의 INGEST_KEY를 실제 임의 값으로 설정합니다. 예제 replace-* 값은 사용하지 않습니다.
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
.venv/Scripts/python -m pytest -q
python build_compose.py
docker compose -p nodeverse-v2-review --env-file .env --env-file review.env -f compose.json up -d --build
.venv/Scripts/python check.py --url http://127.0.0.1:8002
```

기존 같은 이름의 시험 프로젝트가 이미 실행 중이면 두 클론에서 동시에 기동하지 마세요.
볼륨/체크포인트 삭제(down -v)로 충돌을 해결하지 않습니다.
INGEST_KEY, DB 비밀번호, .env, 실행 DB·볼륨·journal·전체 원시 로그는 이 공유에 없습니다.
DB 계정과 키는 별도 경로로 받습니다. 상태/시간 규칙을 임의로 완성하지 않습니다.

## 현재 남은 주요 쟁점

- Silver는 상태 중복 제거 뒤 insert-only MERGE입니다. 과거 append 문서와 구분하고
  대용량 전체 대상 탐색 비용을 비교해야 합니다. matched UPDATE는 기존 이벤트에 적용하지 않습니다.
- Exactly-once의 보장 범위를 한정합니다. Delta/MongoDB 원자적 커밋은 없습니다.
- 동일 배치 ID 충돌 원문 결정, 방어적 NULL 격리, 지각/역순/장기 부하 검증 등은 검토 제안이며
  이미 적용된 기능으로 보고하지 않습니다.
- 원격 rt_* 집계 동기화와 회원/개별 기록 매핑은 별도 계약이 필요합니다.

## 코드 출처

v2 원본 로컬 Git의 기준은 2466861/d062a1e이며 11월 20일 미커밋 보완을 함께 가져왔습니다.
검토 파일 해시는 evidence-2026-11-20/source-fingerprint.json에 남아 있습니다.
검토 시점 해시는 포장용 ignore/인수 문서 추가 이후의 최종 Git blob과 다를 수 있습니다.

# CHANGELOG

## 0.1.0 — 2026-11-08 (1단계: 데이터와 로직)

### 추가
- `data/balance.json`: 심볼 7종, 배당표, 릴 스트립 3개(32칸), 8라인, 베팅 한도, 피버, 풀 (기획서 예시 수치)
- `SlotLogic`: 정지 위치 추첨, 3×3 판 생성, 라인 판정, 배당, 피버 카운터·보너스, 풀 적립·획득
- `BalanceData`: JSON 로드와 데이터 검사
- 판정 테스트 씬 `scenes/test/logic_test.tscn` (44개 항목)
- 시뮬레이션 씬 `scenes/test/sim.tscn` (10만 회, 시드 고정, RTP 출처별 분석)

### 변경
- `project.godot`: Compatibility 렌더러, 640×480, 창 1280×960, aspect keep

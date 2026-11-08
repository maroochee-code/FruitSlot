# CHANGELOG

## 0.4.0 — 2026-11-09 (4단계: 릴 회전과 STOP)

### 추가
- 릴 회전: 심볼이 balance.json 릴 스트립 순서대로 아래로 흐름 (랜덤 심볼 없음). 릴 창 위아래로 반 칸씩 더 보이고, 회전 중에는 어두운 막으로 덤 부분을 가림 (`scripts/view/reel_view.gd`)
- 릴 움직임 계산 `ReelMotion`: 가속 → 일정 속도 → 감속 미끄러짐 → 튕김 → 정확히 목표 위치에 정지 (`scripts/view/reel_motion.gd`)
- 스핀 진행 관리 `SpinController`: STOP 1/2/3, 자동 정지(START 기준 3.0초 + 0.4초 간격, 왼쪽부터), 회전 중 START = 남은 릴을 왼쪽부터 차례로 정지 (`scripts/view/spin_controller.gd`)
- STOP 1/2/3 버튼과 키 1/2/3: 회전 중이고 아직 누르지 않은 릴만 활성
- 손맛 설정 `data/feel.json` + 읽기/검사 `FeelConfig`: 회전 속도, 가속, 감속 거리·곡선, 튕김, 반 칸 노출, 자동 정지 시각·간격, 회전 중 START 간격·잠금, 정산 지연. 설명은 `docs/feel.md`
- 회전 중 COIN·BET·MAX BET·CANCEL 잠금 (버튼 비활성 + 키 무시 + GameState에서도 거절)
- `GameState`: `spin_started` 신호, `settle_spin()`(정산), `play_spin()`(시작+정산 한 번에, 테스트용), `spinning` 상태
- `scenes/test/reel_test.tscn`: 릴 움직임·컨트롤러 검사 35개
- **feel.json 실행 중 재로딩**: 파일 저장 시 0.5초 안에 자동으로(수정 시각 감시), F6으로 즉시 다시 읽음. 적용은 다음 스핀부터이고, 진행 중인 스핀은 시작 때의 설정 한 벌로 끝까지 진행(`ReelMotion.start`·`SpinController.begin`이 설정을 받음). 파일이 깨졌으면 이전 값 유지, 범위 밖 항목은 기본값 + 안내 문구. `half_row`만 재시작 필요

### 변경
- START가 둘로 나뉨: START 순간에는 베팅 차감 + 결과 확정만, 당첨금 합산·WIN·POOL·피버 갱신·당첨 연출은 세 릴이 멈추고 `result_delay` 뒤에
- 칸 높이 88 → 78, 릴 위치 y 60 → 55 (위아래 반 칸이 STOP 버튼을 덮지 않도록)
- 처음 화면의 릴은 빈 박스 대신 스트립 0번 위치의 심볼을 보여줌
- 화면 갱신(POOL·피버)은 로직 현재값이 아니라 스핀 결과의 스냅샷(`pool_after`, `fever_counts_after`)을 사용
- `state_test`: `start_spin()` → `play_spin()` 호출로 바꾸고, 시작/정산 분리·회전 중 잠금 검사 6개 추가
- `view_test`: 시간을 직접 흘리는 방식으로 개편. 300회 스핀을 STOP 키/버튼/자동/회전 중 START 4가지 입력으로 돌리며 매 프레임 검사

### 수정
- `info_box.gd`, `paytable_panel.gd`: 내장 함수와 이름이 같은 변수(`wrap`, `mini`) 경고 제거 (이름만 변경)

## 0.3.0 — 2026-11-08 (3단계: 베팅·라인 UI)

### 추가
- `GameState` 오토로드(`scripts/autoload/game_state.gd`): 크레딧·베팅·WIN 관리. COIN(+100), BET(A→H 배분, 최대에서 1로 순환), START에서 차감, 당첨금 합산, 크레딧 부족 시 BET/START 차단, 스핀 후 베팅 자동 하향
- `data/economy.json`: COIN 지급량(100)과 시작 크레딧(0)
- 라인 라벨 A~H + 라인별 베팅 수(베팅 0이면 어둡게), 당첨 라인 선 + 깜빡임, 당첨 칸 흰 테두리 (`scripts/view/line_overlay.gd`)
- 하단 바 CREDIT / 안내 / WIN / BET, 오른쪽 패널 POOL + 피버 카운터 4줄 (`scripts/view/info_box.gd`)
- 안내 문구: BET 8 미만이면 "BET 8 이상이면 피버 적립", 당첨 시 "당첨 N = 라인 X + 피버 Y + 풀 Z", 크레딧 부족 안내
- 키보드 C=COIN, B=BET, 스페이스/엔터=START
- 심볼 그림 경로를 `symbol_style.gd`의 `ICON_PATHS`에서 관리 (파일이 없으면 색 박스 + 글자)
- `scenes/test/state_test.tscn`: GameState 규칙 검사 (MAX BET·CANCEL 포함 50개)
- MAX BET 버튼(M): 베팅을 min(최대 베팅, 현재 크레딧)으로 한 번에 설정. 배분은 BET과 같음
- CANCEL 버튼(X): 베팅을 0으로. 크레딧 변화 없음. 할 수 없는 상태면 MAX BET·CANCEL 버튼 비활성
- 배당표(족보) 패널: 오른쪽 패널 피버 카운터 아래, 심볼 7줄(이름 + 색 박스 3개 + ×배수). 숫자는 balance.json에서 읽음 (`scripts/view/paytable_panel.gd`)

### 변경
- `project.godot`: 오토로드 `GameState` 등록
- 디버그 창: 기본 꺼짐(F1), 너비 확대(336px) + 줄바꿈으로 오른쪽 끝 잘림 수정
- 버튼 줄을 CANCEL / COIN / START / BET / MAX BET 5개로 확장
- `docs/기획서.md` 2·5·13장(버튼 줄, 배당표, MAX BET·CANCEL, 단축키 M·X)과 5·6장: 차감 시점(START), BET 한도·순환, 시작 크레딧 0, 베팅 자동 하향, WIN 총합 명시
- `view_test`: 크레딧·WIN·BET·POOL·피버·라인 라벨·당첨 선까지 검사하도록 확장

## 0.2.0 — 2026-11-08 (2단계: 정지 화면)

### 추가
- `scenes/main.tscn` (메인 씬으로 지정): 3×3 릴 영역, START 버튼, 스페이스/엔터로 `SlotLogic.spin()` 호출 후 결과 즉시 표시
- 심볼 7종 색 박스 + 글자 (`scripts/view/symbol_style.gd`). 세븐은 검정 바탕 + 금색 큰 7 + 금테
- 디버그 창 (F1 토글): 정지 위치, 격자, 당첨 라인, 당첨금, 피버·풀 상태, 화면↔로직 일치 여부
- 3단계용 빈 자리: 라인 라벨, STOP 1~3, 타이틀, POOL, 피버 카운터, CREDIT/안내/WIN/BET, COIN/BET 버튼(비활성)
- `scenes/test/view_test.tscn`: START 200회 자동 실행, 화면 칸과 로직 결과 비교

### 변경
- `project.godot`: 메인 씬 지정 (`run/main_scene`)

## 0.1.1 — 2026-11-08 (밸런스 1차 조정, 수치만 변경)

### 변경 (`data/balance.json` v0.1 → v0.2, 코드 변경 없음)
- 배당표: 체리 10 유지, 수박 20→30, 포도 30→35
- 릴 스트립 전면 재배치: 릴당 체리 10(1번 릴 9)·오렌지 8·수박 4·포도 4·벨 3·BAR 2·세븐 1(1번 릴 2)
- 세로 라인: 세 릴 모두 오렌지 3연속 1곳씩만 남김 (F·G·H 비중 동일, 이전에는 릴마다 체리·오렌지 2곳)
- 피버: 체리 카운터 5→20·배수 20→11 / 포도 9→4·40→30 / 벨 7→3·30→50 / 세븐 1·100 유지
- 풀: 변경 없음 (적립 5%, 초기 500)

### 결과 (시드 12345)
- BET 8, 100만 회: RTP 142% → **92.65%**, 히트 28.85%, 체리 피버 155스핀에 1회, 풀 3,497스핀에 1회
- BET 4, 10만 회: RTP **71.94%**

## 0.1.0 — 2026-11-08 (1단계: 데이터와 로직)

### 추가
- `data/balance.json`: 심볼 7종, 배당표, 릴 스트립 3개(32칸), 8라인, 베팅 한도, 피버, 풀 (기획서 예시 수치)
- `SlotLogic`: 정지 위치 추첨, 3×3 판 생성, 라인 판정, 배당, 피버 카운터·보너스, 풀 적립·획득
- `BalanceData`: JSON 로드와 데이터 검사
- 판정 테스트 씬 `scenes/test/logic_test.tscn` (44개 항목)
- 시뮬레이션 씬 `scenes/test/sim.tscn` (10만 회, 시드 고정, RTP 출처별 분석)

### 변경
- `project.godot`: Compatibility 렌더러, 640×480, 창 1280×960, aspect keep

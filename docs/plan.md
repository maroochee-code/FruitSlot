# 6-D 작업 계획 — 배경(마름모 벽지·기계 프레임)·로고

## 결정 사항 (사용자 승인)
- 프레임 범위: **B안** = 바깥 테두리(2아트px) + 가로 구분 띠 + 세로 구분 띠 + 꺼진 전구 소켓
- 로고: 두 줄(maroochee / SLOT), 직접 찍은 비트맵, 기존 Title 패널 안쪽(56×20)
- 미리보기: Python 합성 근사본
- 공통 규칙: 아트 213×160 ×3 정수배 + Nearest, 안티앨리어싱·그라데이션 금지, 1px 외곽선 #2b1b3d, 2톤 음영
- 로직·balance.json·feel.json·project.godot 불변. 기존 화면 좌표 불변.

## 6-D-1 이미지 생성 + 미리보기 (완료, 게임 코드 변경 없음)
- `tools/gen_pixel_assets.py`에 벽지·프레임·로고·미리보기 추가
- 생성: `assets/ui/wallpaper_tile.png`(48×48), `frame.png`(640×480, 가운데 투명), `logo.png`(180×72)
- 미리보기: `assets/_preview/6d_screen.png`, `6d_screen_no_frame.png`, `6d_logo_x6.png`
- → 사용자 승인 대기

## 6-D-2 화면 적용 (승인 후)
- `main.gd`: `_build_background()`에서 Background(청록 단색) → Wallpaper(TextureRect, STRETCH_TILE) → Frame(TextureRect) 순서로 맨 앞에 붙임. 모두 mouse_filter IGNORE.
- `main.gd`: `_build_title_frame()`의 Title 패널에 자식 `TitleLogo`(TextureRect, 180×72) 추가
- view_test: Wallpaper/Frame/TitleLogo 존재, 그리기 순서(벽지 < 프레임 < 보드), mouse_filter, 로고 크기, 기존 요소 위치 불변
- 기존 테스트 전부 통과: logic 44, state 96, reel 71, view 274+, match 18
- F5 확인 요청 → 커밋 제안(승인 후) → `docs/진행상황.md`, `CHANGELOG.md`(v0.11.0) 갱신

---

# 6-E 작업 계획 — FEVER! / POOL GET! 연출 아트 + 당첨 동전

## 결정 사항 (사용자 승인)
- 오버레이 범위 **B안**: 막·연출을 윗부분(아트 y 0~138 = 640×414 px)에만 깔고, 하단 CREDIT/WIN/BET 줄은 그대로 보임. 클릭 차단은 전체 화면 유지. 기획서 8장 "화면 전체" 문구 수정 승인.
- 심볼: 큰 심볼 32×24 + 칸 타일(36×28). 풀 단계는 동전 줄.
- 이름·금액은 갈무리14 글자(×3, 풀 금액 ×4). 새 비트맵은 배너 글자·장식·동전만.
- 색: FEVER! = 빨강·주황, POOL GET! = 금색·초록. 동전 8×8, 6프레임.
- 힌트(`SPACE: 건너뛰기`)는 y≈390으로 이동. `scenes/test/overlay_preview.tscn` 추가(balance.json은 건드리지 않음).
- 연출 시간·규칙·입력 잠금·정산 시점은 그대로. `feel.json` 새 키 없음.

## 6-E-1 이미지 생성 + 미리보기 (완료·승인, 게임 코드 변경 없음)
- `tools/gen_pixel_assets.py`에 6-E 추가
- 생성: `assets/ui/fever_banner_a/b.png`(120×28 아트 ×3), `pool_banner_a/b.png`(136×28), `fever_bg_0~2.png`, `pool_bg_0~2.png`(640×414), `coin_sheet.png`(48×8 아트 ×3 = 144×24)
- 미리보기: `assets/_preview/6e_fever.png`, `6e_fever_seven_b.png`, `6e_pool.png`, `6e_pool_b.png`, `6e_overview.png`, `6e_coin_x6.png`
- → 사용자 승인 대기

## 6-E-2 화면 적용 (완료·커밋됨)
- `fever_overlay.gd`: 임시 Label/Panel → 배너(`BannerFever`/`BannerPool`)·배경(`BgFrame`)·심볼 타일·BONUS 판. 막·배경은 y 0~414만. 힌트 y≈390. 위치·프레임 수는 상수로 노출.
- 새 `scripts/view/coin_sheet.gd`: 동전 시트 경로·프레임 크기·프레임 수·프레임 텍스처 (6-F용)
- 새 `scenes/test/overlay_preview.tscn`: 가짜 단계(체리→포도→벨→세븐→풀)로 연출만 재생, 키로 단계·색 변형 전환
- `docs/기획서.md` 8장 문구, `docs/진행상황.md`, `CHANGELOG.md`(v0.12.0)
- 테스트: `shown_texts()` 값 불변, 이미지 사용, 노드 이름·크기·위치, 클릭 차단 유지, 하단 표시창 위에 막 없음, 동전 시트 크기·프레임 수, 기존 요소 위치 불변, 기존 전 테스트 통과

---

# 6-F 작업 계획 — 소리·BGM·전구·당첨 정산 연출 (세 번에 나눠 진행)
- **6-F1 효과음** (구현·커밋 완료 v0.13.0): 합성 효과음 14개, SoundBank, 상황별 연결, feel 키 3개(`win_mid_ratio`, `win_big_ratio`, `sfx_volume_db`), 미리보기 씬
- **6-F2 BGM** (구현·커밋 완료 v0.14.0): bgm_main/bgm_fever 연결, 피버 때 전환·복귀(메인은 멈춘 자리부터), 코드 크로스페이드 반복, feel 키 5개, `bgm_preview.tscn`
- **6-F3a 전구** (구현 완료 v0.15.0, F5 확인 대기): bulbs.png, BulbPattern/FrameBulbs, BoardView 개조, feel 키 4개, `bulb_preview.tscn`
- **6-F3b 정산 연출 + AUTO** (구현 완료 v0.16.0, F5 확인 대기): WIN 카운트업·동전·크레딧·틱 소리, AUTO 대기 정리. 결정: START = 확정 + 다음 판 시작, 동전은 포물선, 테스트 main 생성 지점에서만 `settle_presentation=false`, AUTO 대기 연장은 view 쪽(`auto_gap_sec` 조정 + `auto_advance` 앞당김), `tick.wav` 추가(동전 도착 소리는 tick 재사용)
- 결정(6-F1): 거절=cancel, AUTO 켜기·끄기=button, 피버·풀 연출 중 win_x 생략, fever_end는 자연 종료 때만, 오디오 버스는 코드 생성, BET/MAX/CANCEL은 main 래퍼로 소리 연결

---

# 7-A 작업 계획 — 밸런스 2차 조정 (구현 완료 v0.17.0, 사용자 확인 대기)

## 결정 사항 (사용자 승인)
- 조정안 **C**: 체리 피버 카운트 20→24·배수 11→14, 풀 초기값 500→250, 적립률 5%→6%. 릴 스트립·배당표 불변
- 피버 보너스 = 카운터를 줄인 판들의 평균 베팅 × 배수. `fever.bonus_bet_basis`(기본 `"average"`, 허용 `"trigger"`/`"average"`, 그 밖은 기본값)
- RTP 목표는 BET 8~64. BET 1~7과 풀 색 기준(1,000 / 1,500)은 이번에 바꾸지 않음
- 합격 판정은 이론값(전수 계산), 10만 회 시뮬레이션은 교차 확인용(표본 오차 약 ±1.9%p)
- 화면·소리·연출 불변, 새 feel.json 키 없음, 커밋은 사용자 승인 후

## 진행
1. (완료) `sim.gd`·`sim_stats.gd`: BET 일괄 실행, 당첨 크기 분포, 이론값, 섞어 치기, 밸런스 검사
2. (완료) `balance.json` v0.3
3. (완료) `slot_logic.gd`·`balance_data.gd`: 평균 베팅 보너스 / 새 파일 `balance_theory.gd`
4. (완료) logic_test +20
5. (완료) 재측정: 10만 회(시드 12345), 300만 회(시드 777)
6. (완료) 문서: 기획서 7~10장, CHANGELOG, 진행상황, decisions

## 남은 결정
- 8의 배수가 아닌 BET(10~14, 21)의 RTP 95% 초과 처리: 릴 스트립으로 세로 라인 강화 / 허용 / 베팅 단위 변경 중 선택
- "풀베팅(8)" 표현 정리(목록은 진행상황.md)
- `data/balance_bak2.json`, `data/feel_bak.json` 정리 여부

---

# 7-B 작업 계획 — GAME OVER (구현 완료 v0.18.0, F5 확인 완료)

## 결정 사항 (사용자 승인)
- 값 파일은 `data/economy.json`: `start_credit` 3000, `continue_credit` 1000, `continue_max` 3, `coin_amount` 100(유지). 코드에 숫자를 쓰지 않는다. balance.json으로 옮기지 않는다.
- NEW GAME 코인 = `start_credit` (별도 키 없음). 시작 화면(7-C)의 START도 같은 `new_game()`을 부른다.
- CONTINUE: 판당 최대 `continue_max`번, 남은 횟수 표시, 소진 시 비활성. POOL·피버 카운터 유지. 뒤에 BET은 직전 BET으로 복구(크레딧 이내로).
- NEW GAME: 크레딧 지급 + POOL·피버 카운터(평균 베팅 합 포함) 초기화 + 이어하기 횟수 복구 + BET 0·WIN 0·AUTO 끔. "정말?" 확인 단계 없음. RNG 시드는 건드리지 않음.
- 화면: 640×414 전체를 덮고 POOL·피버 카운터를 다시 그린다. 하단 CREDIT/안내/WIN/BET 줄은 그대로 보인다. 기존 좌표 불변.
- BGM: GAME OVER 동안 `bgm_gameover_fade_sec`로 페이드 후 일시정지, CONTINUE/NEW GAME 때 이어서 재생(BgmPlayer에 일시정지·재개 함수 2개).
- COIN: `coin_allowed()` = 개발 빌드(`OS.is_debug_build()`, 테스트가 바꿔 넣을 수 있는 변수) and 테스트 모드 스위치(지금은 항상 켜짐, 8-B에서 연결). 비활성이면 버튼은 자리 그대로 회색, C 키는 소리 없이 무시.
- COIN 안내 문구: `coin_allowed()`가 false일 때만 "크레딧이 부족합니다.", 개발 빌드는 기존 "COIN(C)…" 유지. main.gd 541·701행, debug_panel.gd 20행을 같은 기준으로 처리.
- `grant_credit(amount, reason)` 입구: reason = `start` / `continue` / `test_coin`. `credit_granted` 시그널. 당첨금은 거치지 않는다. `test_coin`이면 `run_tainted = true`, `new_game()`에서 해제.
- 최고 기록: 메모리 집계만(한 판의 최고 크레딧, 스핀 수, 이어하기 사용 수, 테스트 판 여부). user:// 저장은 8단계.
- GAME OVER 판정은 로직: `settle_spin()` 맨 끝(AUTO 해제 알림 뒤)에서 크레딧 0이면 `game_over` 시그널. 화면은 `gameover_delay_sec` 뒤 표시(정산 연출·피버·오버레이 중에는 끝난 뒤). 크레딧 직접 대입에는 반응하지 않는다.
- 시작 크레딧 소진 속도는 의도대로(최대 베팅 중앙값 117스핀). F5 후 사용자가 economy.json에서 조정.
- 결과 조작 금지 유지. 로직(SlotLogic)·balance.json·project.godot 불변. 커밋은 사용자 승인 후.

## 새 키 (승인됨)
| 파일 | 키 | 기본값 | 범위 |
|---|---|---|---|
| economy.json | start_credit | 3000 | 1~999,999 (하한 0→1로 변경) |
| economy.json | continue_credit | 1000 | 1~999,999 |
| economy.json | continue_max | 3 | 0~99 (0 = 이어하기 없음) |
| feel.json | gameover_delay_sec | 0.8 | 0~5 |
| feel.json | gameover_input_lock_sec | 0.5 | 0~3 |
| feel.json | bgm_gameover_fade_sec | 0.5 | 0~5 |
user:// 저장 항목: 없음.

## 단계 (한 단계씩, 내가 "진행해"라고 하기 전에는 다음 단계를 시작하지 않는다)

### 7-B-1 GameState 규칙 + state_test
- `game_state.gd`: `grant_credit`, `credit_granted`, `continues_left`, `is_game_over()`, `can_continue()`, `continue_game()`, `new_game()`, `game_over` 시그널, `coin_allowed()`, 개발 빌드·테스트 모드 변수, 기록 집계(최고 크레딧·스핀 수·이어하기 사용 수·`run_tainted`)
- `load_economy()` 검사 확장(새 키·범위). `_ready()`가 `initialize()` 뒤에 `new_game()` 호출. `initialize()`는 크레딧 0 유지(기존 테스트 호환)
- `insert_coin()`이 `coin_allowed()`와 `grant_credit`을 거침
- state_test 추가: CONTINUE 3번 제한·4번째 거절, CONTINUE 뒤 POOL·피버·BET 복구, NEW GAME 초기화 항목 전부, 정산 순간 0 판정·회전 중 0 무판정·당첨 시 무판정, AUTO 중 0의 시그널 순서, grant_credit 이유별 동작·테스트 판 표시, COIN 활성 조건(개발/릴리즈 × 스위치), 범위 밖 economy 값 거절
- 확인: logic 64 / state 96+ / reel 71 / view 483 / match 18 이상. **view_test 1136~1140행 위험은 이 단계에서 먼저 돌려 보고, 깨지면 고치지 않고 원인부터 보고**
- 이 단계는 화면 변경 없음

### 7-B-2 그림 조사 + 미리보기 (게임 코드 변경 없음)
- `tools/gen_pixel_assets.py`: 블록 글자 A·M 추가, `gameover_banner.png`, `gameover_bg.png`(번쩍임 없는 어두운 배경, 640×414), 아트 ×3·Nearest·외곽선 #2b1b3d 규칙
- 미리보기 `assets/_preview/7b_*.png` → 사용자 승인 대기. 버튼·패널은 기존 그림 재사용

### 7-B-3 화면 + 연결
- 신규 `scripts/view/game_over_overlay.gd`: 배너, POOL·피버 카운터(로직 값 그대로), CONTINUE +1,000 / NEW GAME +3,000 버튼(금액은 economy 값에서), 남은 횟수 글자, 0회면 CONTINUE 회색·기본 선택 NEW GAME, ←/→·스페이스/엔터·마우스, 뜬 직후 입력 잠금
- `main.gd`: `game_over` 수신 → 정산 연출·피버 오버레이 끝난 뒤 `gameover_delay_sec` 후 표시, 표시 때 gameover.wav, 오버레이 중 COIN/BET/MAX BET/CANCEL/START/AUTO/STOP 잠금, COIN 버튼 회색·C 키 무시, 안내 문구 3곳
- `feel_config.gd`·`feel.json`·`docs/feel.md`: 새 키 3개
- `bgm_player.gd`: 일시정지·재개 함수 2개 (페이드는 `bgm_gameover_fade_sec`)
- view_test 추가: 오버레이 노드·크기(640×414)·z순서, 버튼 2개, 남은 횟수 글자, 0회 비활성, POOL·피버 표시 = 로직, 지연·입력 잠금, 연출 중에는 안 뜸, 키/마우스 조작, COIN 버튼 회색, gameover 소리 요청, BGM 일시정지·재개, 기존 요소 좌표 불변
- match_test는 18 유지 확인

### 7-B-4 문서·마무리
- 기획서(GAME OVER 절 신설, 5·6장 시작 크레딧 0 → economy 값, COIN·AUTO 문장), `docs/진행상황.md`, `CHANGELOG.md`(v0.18.0), `docs/decisions/`(GAME OVER 구조, `grant_credit` 입구, COIN 규칙)
- 전체 테스트 재실행(match_test는 백그라운드), F5 확인 항목 정리, 커밋 메시지 제안(커밋은 승인 후)

## F5에서 눈으로 확인할 것 (7-B-3 이후)
- 최대 베팅으로 크레딧을 다 쓰면 마지막 판을 잠깐 보여 준 뒤 GAME OVER가 뜨는지, 소리와 BGM 정지
- CONTINUE 후 POOL·피버 카운터 유지와 BET 복구, 남은 횟수 감소, 3번 후 비활성
- NEW GAME 후 시작 크레딧·POOL·피버 카운터 초기화
- AUTO 중 0이 됐을 때 AUTO 해제 → GAME OVER 순서
- COIN 버튼이 개발 실행에서는 활성(릴리즈는 회색)
- 시작 크레딧 3,000이 체감상 적당한지(조정은 economy.json)

## 위험·확인 필요
- view_test 1136~1140행(크레딧 8 / BET 8 스핀 뒤 0이 될 수 있음): 7-B-1에서 먼저 실행해 확인
- 내보내기 "디버그와 함께 내보내기" exe가 `OS.is_debug_build()`로 개발 빌드 취급되는지: 구현 때 공식 문서로 확인
- 생성기에 글자 A·M이 없어 추가 필요(7-B-2)
- 기존 테스트 약 30곳은 `initialize()`만 부르므로 크레딧 0 시작 유지가 필수


---

# 7-B-3 상세 계획 (7-B-1·7-B-2 완료, 미리보기 승인됨)

## 진행 기록
- 7-B-1 완료: GameState 규칙 (state_test 155 통과). **A안 확정**: `insert_coin()`은 `coin_allowed()`만 따르고 GAME OVER 중에도 막지 않는다. `grant_credit()`은 크레딧이 0보다 커지면 GAME OVER를 해제해 GAME OVER가 항상 "크레딧 0 + 진행 중인 판 없음"과 일치한다. GAME OVER 중 입력 잠금은 화면(오버레이)이 맡는다.
- 7-B-2 완료·승인: `gameover_banner.png`, `gameover_bg.png`를 `python tools/gen_pixel_assets.py 7b install`로 `assets/ui`에 넣음. `tools/__pycache__/` 삭제, `.gitignore`에 `__pycache__/` 추가(사용자 승인)

## 만들 것
- 신규 `scripts/view/game_over_overlay.gd` (`GameOverOverlay`): 640×480 입력 차단(마우스 STOP), 그림은 640×414만 덮음. 배경·배너(승인된 그림), POOL·피버 카운터 패널(기존 패널 그림 + 작은 아이콘 ×3 + "×N"), CONTINUE / NEW GAME 버튼(금액은 economy 값, 천 단위 쉼표), 남은 횟수 글자, 조작 안내. 좌표는 `gen_pixel_assets.py`의 `GAMEOVER_LAYOUT`과 같음. 시그널 `continue_pressed`, `new_game_pressed`
- 조작: ←/→ 선택, 스페이스/엔터 결정, 마우스 클릭(가리키면 선택). 이어하기 0회면 CONTINUE는 회색 비활성이고 선택은 NEW GAME. 뜬 직후 `gameover_input_lock_sec` 동안은 결정 입력 무시
- `main.gd`: `GameState.game_over` 수신 → 정산 연출·피버 오버레이가 모두 끝난 뒤 `gameover_delay_sec`가 지나면 오버레이 표시 + gameover.wav 한 번 + BGM 페이드 후 일시정지. CONTINUE·NEW GAME(또는 크레딧이 생겨 GAME OVER가 해제됨)이면 오버레이를 닫고 BGM을 이어서 재생(둘 다 `bgm_gameover_fade_sec`). `new_game_started`를 받으면 오른쪽 패널(POOL·피버 카운터)과 당첨선을 다시 그림
- **GAME OVER 동안 모든 입력 무효**: C 키·COIN 버튼·BET·MAX BET·CANCEL·START(스페이스 포함)·AUTO·STOP 1~3. `main`의 입력 함수(`press_coin`·`press_bet`·`press_max_bet`·`press_cancel`·`do_spin`·`press_stop`·`press_auto`)가 오버레이가 열려 있으면 바로 돌아가고, 키보드는 오버레이용 키(←/→/스페이스/엔터)와 개발용 F1·F6만 통과. 오버레이가 그림·마우스도 가리므로 이중으로 막힌다
- COIN 버튼은 자리 그대로 두고 `coin_allowed()`가 false이거나 오버레이가 열려 있으면 회색 비활성. C 키도 같은 기준
- 안내 문구 3곳(main.gd `_on_action_rejected`, `_refresh_notice`, debug_panel.gd 도움말): `coin_allowed()`면 기존 "COIN(C)…" 문구, 아니면 "크레딧이 부족합니다."(디버그 도움말은 COIN 줄 제외)
- `bgm_player.gd`: `pause_music(fade_sec)` / `resume_music(fade_sec)` 2개 (지금 곡을 페이드로 줄여 일시정지 / 멈춘 자리부터 페이드인)
- `feel_config.gd`·`feel.json`·`docs/feel.md`: `gameover_delay_sec` 0.8(0~5), `gameover_input_lock_sec` 0.5(0~3), `bgm_gameover_fade_sec` 0.5(0~5)

## 연출 시점 규칙 (GAME OVER 판정은 로직, 표시는 연출 뒤)
- GAME OVER가 되는 판은 항상 당첨 0이라 정산 연출·피버·풀 연출이 없다. 그래도 표시 조건은 "회전 중 아님 + 정산 대기 아님 + 정산 연출 없음 + 피버 오버레이 없음"을 모두 만족한 뒤 `gameover_delay_sec`를 센다
- 표시를 기다리는 동안 크레딧이 생기면(개발 빌드 COIN 등) 대기를 취소한다. 오버레이가 열려 있는데 `GameState.is_game_over()`가 아니게 되면 오버레이를 닫는다 → 화면과 로직이 어긋나는 시간이 없다

## view_test 추가 계획
1. GAME OVER 오버레이 노드(`GameOverOverlay`)·크기(640×480 입력 차단, 그림 640×414)·맨 위 그리기 순서·배너/배경 그림 경로
2. 버튼 2개(`ContinueButton`, `NewGameButton`)·금액 글자(economy 값)·남은 횟수 글자·기본 선택 CONTINUE·0회면 CONTINUE 비활성과 선택 NEW GAME
3. POOL·피버 카운터 표시값 = 로직 값
4. 표시 시점: 정산 직후에는 안 뜨고 `gameover_delay_sec` 뒤에 뜸 / 정산 연출이 도는 동안에는 안 뜨고 끝난 뒤에 뜸 / 크레딧이 0이 아니면 안 뜸 / 당첨으로 크레딧이 남으면 안 뜸
5. 소리·BGM: gameover 요청 한 번, BGM 페이드 후 일시정지(위치 기억), CONTINUE·NEW GAME 뒤 재개
6. **GAME OVER 동안 모든 입력 무효 (C 키·COIN 버튼·BET·MAX BET·CANCEL·START·AUTO·STOP 1~3 키와 버튼, 개발 빌드)**: 전부 누른 뒤 크레딧·베팅·AUTO·회전·이어하기 횟수가 그대로이고 오버레이가 그대로 열려 있음
7. **상태와 화면 일치**: 오버레이가 열려 있는 동안 `is_game_over()` and 크레딧 0 / 코드로 `insert_coin()`을 불러 크레딧이 생기면 오버레이가 닫히고 BGM이 재개됨 / CONTINUE·NEW GAME 뒤 `is_game_over()`가 false이고 오버레이가 닫혀 있음
8. 입력 잠금 시간 동안 결정 키·버튼 무시, ←/→ 선택 이동, 마우스(버튼 클릭), 이어하기 3번 뒤 4번째는 비활성
9. CONTINUE 뒤: 이어하기 횟수·크레딧·BET 복구·POOL 유지 / NEW GAME 뒤: 시작 크레딧·POOL·피버 카운터 초기화·횟수 복구, 오른쪽 패널이 다시 그려짐
10. COIN 버튼 회색 처리(`dev_build` false이면 비활성·C 키 무시·소리 없음) · 안내 문구 3곳이 기준대로 바뀜
11. 기존 요소 위치 불변: 오버레이를 열고 닫아도 버튼·표시창·릴 좌표가 그대로, 오버레이 그림이 y 414 아래로 내려가지 않음
- match_test는 18 유지 확인 (크레딧 10억이라 GAME OVER 없음)

## 위험
- 기존 view_test 중 크레딧이 0이 되는 정산 뒤에 계속 입력을 넣는 곳이 있으면, 이제 오버레이가 열려 입력이 막혀 깨질 수 있다. 깨지면 고치지 말고 원인부터 보고한다

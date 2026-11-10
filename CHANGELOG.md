# CHANGELOG

## 0.16.0 — 2026-11-10 (6-F3b: 정산 연출 + AUTO 대기)

### 추가
- 정산 연출 `SettleShow`(`scripts/view/settle_show.gd`): 당첨이 있으면 WIN 숫자가 0에서 최종값까지 올라가고(소 0.6 / 중 1.2 / 대 2.5초), 동전(소 3 / 중 6 / 대 12개, `CoinSheet` 재사용)이 WIN 칸에서 CREDIT 칸으로 포물선(0.45초)으로 날아가 도착할 때마다 CREDIT이 오름. 마지막 동전이 나머지를 더해 최종값과 정확히 일치
- 효과음 `tick.wav`(0.02초, `tools/gen_sounds.py`로 합성): 카운트업 숫자가 오를 때와 동전 도착 때 재생. 연출을 건너뛸 때는 소리 없음
- `feel.json` 새 키 9개: `countup_small_sec` `countup_mid_sec` `countup_big_sec` `countup_tick_sec` `coin_count_small` `coin_count_mid` `coin_count_big` `coin_fly_sec` `auto_effect_scale`. 설명은 `docs/feel.md`
- `main.settle_presentation`(기본 true): false면 연출 없이 숫자를 바로 반영 (기존 테스트용)
- `sound_preview`에 T 키(tick)
- view_test +49: SettleShow 단독(시간·포물선·나머지 처리·동전 수 상한·건너뛰기 무음), feel 키, 연출 중 WIN/CREDIT 표시, START·COIN 중단, AUTO 연출 시간·대기 시작 시점

### 변경
- 연출 중 START: 숫자를 최종값으로 확정하고 바로 다음 판 시작. COIN 등 다른 이유로 크레딧이 바뀌어도 연출 숫자를 먼저 최종값으로 확정
- AUTO: 정산 연출이 도는 동안 대기시간을 세지 않고, 연출이 끝난 뒤부터 센다. AUTO 중 연출 시간은 `auto_effect_scale`(0.5)배
- 피버·풀 정산 직후 피버 전구 모양의 지속 시간을 고정 1.5초에서 정산 연출 시간으로 바꿈 (연출이 없으면 기존 1.5초)
- 메시지 칸의 "당첨 N = 라인 + 피버 + 풀"은 정산 즉시 최종 숫자로 표시 (변경 없음)
- 로직, GameState, balance.json, project.godot, 기존 요소 좌표 변경 없음

## 0.15.0 — 2026-11-10 (6-F3a: 전구 애니메이션)

### 추가
- 전구 그림 시트 `assets/ui/bulbs.png`(꺼짐·노랑·빨강·흰색, 각 아트 2×2 = 6×6 px, 하이라이트 점 1개). `tools/gen_pixel_assets.py`로 생성, 미리보기 `assets/_preview/6f_bulbs.png`
- `BulbSheet`(시트 도우미), `BulbPattern`(대기/스핀/당첨/피버 모양 규칙, 순수 계산), `FrameBulbs`(프레임 소켓 18개 위에 켜진 전구를 얹음, 프레임 바로 위·다른 요소 뒤, 클릭 통과)
- 전구 모양: 대기(짝수/홀수 0.8초 교대) / 스핀(3개 중 1개가 도는 효과, 프레임은 왼쪽→오른쪽) / 당첨(전부 흰색↔꺼짐 번쩍, 당첨선 깜빡임 1.5초 동안) / 피버·풀 정산 직후(노랑↔빨강, 1.5초. 오버레이가 보드를 가리므로 끝난 직후에 보임)
- `feel.json` 새 키 4개: `bulb_idle_sec`(0.8), `bulb_spin_step_sec`(0.06), `bulb_win_flash_sec`(0.12), `bulb_fever_sec`(0.2). 설명은 `docs/feel.md`
- `LineOverlay.blink_total_sec()`: 당첨선 깜빡임 시간(1.5초). 전구 번쩍임이 이 시간을 따름 (6-F3b에서 AUTO 대기가 같은 기준을 씀)
- `scenes/test/bulb_preview.tscn`: 진짜 화면에서 1 대기 / 2 스핀 / 3 당첨 / 4 피버 모양을 키로 바꿔 보는 확인용 씬
- view_test +39: 시트·모양 규칙·보드/프레임 모드·소켓 좌표(frame.png와 일치)·게임 안 모드 전환·feel 키

### 변경
- `BoardView`: 전구를 사각형이 아니라 `bulbs.png` 그림으로 그리고, 모양은 `BulbPattern`에 따라 움직임. 시간 0의 대기 모양은 6-B 정적 모양(짝수 켜짐)과 같음
- view_test의 feel 기본값 검사(6-F1·6-F2)를 "feel.json 파일 값"이 아니라 "코드 기본값 + 파일이 오류 없이 읽힘"으로 바꿈 (사용자가 소리를 듣고 `bgm_volume_db`를 -5로 조정해서 파일 값 검사가 깨졌음)
- 로직, GameState, balance.json, project.godot, 기존 요소 좌표 변경 없음

## 0.14.0 — 2026-11-10 (6-F2: BGM)

### 추가
- `BgmPlayer`(`scripts/view/bgm_player.gd`): 메인 BGM(`bgm_main.mp3`)을 게임 시작 때 1초 페이드인으로 시작해 반복 재생. 피버 연출이 시작되면 피버 BGM(`bgm_fever.mp3`)으로 0.3초 전환, 끝나면(건너뛰기 포함) 1초 크로스페이드로 메인으로 복귀
- 메인은 피버 중 일시정지(위치 기억)하고 복귀 때 멈춘 자리부터 이어서, 피버 곡은 매번 처음부터. 풀 획득 단계에서도 피버 BGM 유지(덕킹 없음)
- 곡 끝 반복은 mp3 임포트 옵션이 아니라 코드 크로스페이드: 곡 끝 2초 전에 같은 곡을 처음부터 다시 틀고 이전 소리를 1초에 걸쳐 줄임 (곡 끝의 약 1초 무음·페이드아웃을 건너뜀). 등전력(equal-power) 곡선
- `feel.json` 새 키 5개: `bgm_volume_db`(-12.0), `bgm_to_fever_sec`(0.3), `bgm_to_main_sec`(1.0), `bgm_loop_trim_sec`(2.0), `bgm_loop_fade_sec`(1.0, trim보다 크면 둘 다 기본값). 설명은 `docs/feel.md`
- `scenes/test/bgm_preview.tscn`: M 메인 / F 피버 / J 반복 지점 앞으로 이동(이음새 듣기) / S 끄기·켜기 / -,= 볼륨
- `docs/credits.md`에 BGM 출처(Suno, 곡 ID)와 "배포 전 상업적 이용 가능 여부 확인 필요" 기록
- view_test +43: BGM 파일·노드, 시작·페이드인, 전환 곡선, 메인 위치 기억, 곡 끝 반복, 피버 연출·건너뛰기·풀 연결, feel 키 검증, 볼륨 적용

### 변경
- `overlay_preview.tscn`은 메인이 시작한 BGM을 꺼 둠 (BGM은 bgm_preview에서 확인)
- `SoundBank.default_playback_enabled()` 추가(헤드리스면 실제 재생 끔, SoundBank·BgmPlayer 공통)
- 로직, GameState, balance.json, project.godot, mp3 임포트 설정 변경 없음

## 0.13.0 — 2026-11-10 (6-F1: 효과음)

### 추가
- 효과음 14개를 직접 합성: `tools/gen_sounds.py`(표준 라이브러리만, 시드 고정이라 항상 같은 파일) → `assets/sounds/*.wav` (coin, bet, cancel, start, reel_spin(반복), reel_stop, win_small/mid/big, fever_start, fever_end, pool_get, button, gameover)
- `SoundBank`(`scripts/view/sound_bank.gd`): 이름으로 효과음 재생, 재생기 8개 돌려 쓰기(겹쳐도 안 끊김), 반복음 켜기/끄기, 연출 소리 끊기, 요청 기록(테스트용), SFX·BGM 오디오 버스를 코드로 생성(`project.godot` 변경 없음)
- 연결 지점: COIN(coin), BET·MAX BET(bet), CANCEL(cancel), 거절(cancel), START(start), 릴 회전 중(reel_spin 반복), 릴 정지마다(reel_stop), 당첨 크기별(win_small/mid/big), 피버 단계 시작(fever_start)·풀 단계 시작(pool_get)·피버 끝(fever_end), AUTO 켜기·끄기(button)
- main.gd에 `press_bet()` / `press_max_bet()` / `press_cancel()` 래퍼(버튼·키가 같은 길을 거침, 받아들여졌을 때만 소리)
- `feel.json` 새 키: `win_mid_ratio`(2.0), `win_big_ratio`(10.0), `sfx_volume_db`(0.0). 설명은 `docs/feel.md`
- `scenes/test/sound_preview.tscn`: 키 하나에 소리 하나 확인용
- view_test +49: 파일·버스·노드, 당첨 크기 경계, 상황별 요청 이름, 건너뛰기·AUTO 중 소리 정리, feel 키 검증

### 변경
- 피버·풀 연출이 있는 판에서는 당첨 크기 소리 대신 연출 소리만 남. 연출을 건너뛰면 재생 중인 소리를 끊고 마무리음(fever_end)은 없음
- 헤드리스(화면·소리 장치 없음) 실행에서는 SoundBank가 실제 재생 없이 요청만 기록
- 로직, GameState, balance.json, project.godot 변경 없음 (소리는 이미 정해진 결과를 알려 줄 뿐)

## 0.12.0 — 2026-11-10 (6-E: FEVER! / POOL GET! 연출 아트 + 당첨 동전)

### 추가
- FEVER! 배너 2종(`fever_banner_a/b.png`, 120×28 아트)·POOL GET! 배너 2종(`pool_banner_a/b.png`, 136×28): 직접 찍은 블록 글자, 색 변형 a/b는 6-F에서 번갈아 깜빡이게 쓸 예정
- 방사형 줄무늬 배경 프레임 `fever_bg_0~2.png`(적갈색)·`pool_bg_0~2.png`(녹색), 640×414
- 당첨 동전 시트 `coin_sheet.png`(8×8 6프레임, 144×24)와 도우미 `CoinSheet`(`scripts/view/coin_sheet.gd`) — 6-F용 준비
- `scenes/test/overlay_preview.tscn`: 진짜 화면 위에 가짜 단계로 오버레이만 재생해 보는 미리보기 씬(키로 단계·배너색·배경 프레임·움직임 확인). 게임 결과·balance.json과 무관
- `tools/gen_pixel_assets.py`에 6-E 에셋·전체 화면 근사 미리보기(`assets/_preview/6e_*.png`) 추가
- view_test +19: 오버레이 배경·배너·심볼 칸·금액 판·동전 줄의 크기와 위치, 단계별로 맞는 것만 보임, 입력 차단과 클릭 통과, 힌트 위치, 6자리 금액이 판 안에 들어감, 동전 시트

### 변경
- 피버·풀 오버레이를 임시 글자·상자에서 도트 그림으로 교체. 막(배경)은 화면 윗부분(640×414)만 덮고 하단 CREDIT/WIN/BET 줄은 연출 중에도 그대로 보임. 입력 차단은 화면 전체 유지
- 심볼 칸은 큰 심볼 + 칸 타일, 이름·금액은 갈무리14 ×3(풀 금액 ×4). 건너뛰기 힌트는 y=390으로 이동
- 풀 단계에서는 이름 줄("POOL")을 뺌(배너·금액 판과 중복). `shown_texts()`는 풀 단계의 이름을 빈 글자로 돌려줌(보이는 글자만 반환). 피버 단계는 그대로
- 글자색 번갈이는 이미지 배너로 바뀌며 사라짐(6-F에서 배너 a/b로 다시 구현)
- `docs/기획서.md` 8·9장: "화면 전체 오버레이" → 윗부분 오버레이(표시창 줄은 보임), 풀 단계 이름 줄 삭제
- 연출 시간·건너뛰기·입력 잠금·정산 시점·결과는 변경 없음. 로직, balance.json, feel.json, project.godot 변경 없음

## 0.11.0 — 2026-11-10 (6-D: 마름모 벽지·기계 프레임·로고)

### 추가
- 청록 두 톤 마름모 벽지(`assets/ui/wallpaper_tile.png`, 아트 16×16 → 48×48, 타일 반복). 기존의 어두운 남색 단색 배경을 대체
- 기계 프레임(`assets/ui/frame.png`, 640×480, 가운데 투명): 바깥 테두리 2아트px + 하단 표시창 위 가로 띠 + 왼쪽 영역/오른쪽 패널 사이 세로 띠 + 꺼진 전구 소켓 18개(6-F에서 켤 자리, 좌표는 `FRAME_BULB_SOCKETS`)
- 로고(`assets/ui/logo.png`, 180×72): 직접 찍은 도트 글자 `maroochee` / `SLOT` 두 줄을 타이틀 패널 안쪽에 표시
- `tools/gen_pixel_assets.py`에 벽지·프레임·로고·전체 화면 근사 미리보기(`assets/_preview/6d_*.png`) 추가
- view_test +10: 벽지·프레임·로고 존재, 그리기 순서, 클릭 통과, 보드·STOP·AUTO·첫 릴 위치 불변

### 변경
- `Background`(ColorRect) 색을 벽지 어두운 톤(#1f6f8b)으로. 프레임 오른쪽 1px(213×3=639) 보정용
- 기존 화면 요소의 좌표·크기, 로직, `balance.json`, `feel.json`, `project.godot`은 변경 없음

## 0.10.0 — 2026-11-10 (AUTO: 자동 스핀)

### 추가
- AUTO 토글 버튼(STOP 3 오른쪽, 384,318 60×33)과 단축키 A. 켜면 현재 BET을 유지한 채 정산 뒤(연출 포함) 대기시간 후 다음 판을 자동 시작
- `AutoSpin`(`scripts/logic/auto_spin.gd`): AUTO 상태·판 수·대기 타이머·큰 당첨 판단. `GameState`가 소유하고 `auto_changed`/`auto_stopped` 시그널로 화면에 알림
- `feel.json` 새 키 `auto_spin_gap_sec`(0.5, 0~10), `balance.json` 새 키 `auto_spin.stop_on_win_at`(0 = 사용 안 함)
- AUTO 중 BET / MAX BET / CANCEL / STOP 1~3 비활성, 끄기(AUTO 재클릭·A·대기 중 START)는 진행 중인 판까지만 진행
- 자동 해제: 크레딧이 총 BET보다 적을 때, 한 판 WIN이 `stop_on_win_at` 이상일 때
- 메시지 칸: 첫 줄 "AUTO N회" 고정, AUTO 중 피버 적립 안내 생략, 해제 이유는 일회성 문구
- 버튼 ON 그림 `button_on.png`(밝은 금색 면, 어두운 글자)

### 변경
- `docs/기획서.md`: 6장에 AUTO 규칙, 2장에 AUTO 버튼, 13장 조작표를 실제 키(A·M·X·키패드 포함)에 맞춰 정리
- `docs/feel.md`에 `auto_spin_gap_sec` 행 추가
- 결과 확정 로직(`SlotLogic`)·확률·RNG 사용 방식은 변경 없음 (같은 시드에서 AUTO 결과 = 수동 결과를 테스트로 확인)

## 0.9.0 — 2026-11-09 (6-C: UI 패널·버튼 3상태·도트 폰트·표시창)

### 추가
- 도트 폰트 갈무리 9/11/14 (`assets/fonts`, OFL 1.1 라이선스 파일 동봉, 출처는 `docs/credits.md`). 안티앨리어싱·힌팅·서브픽셀 끔
- `UiFont`(폰트·정수배 크기), `UiSkin`(패널 9-slice, 버튼 3상태, 라인 라벨 그림, 기본 테마)
- `tools/gen_pixel_assets.py` 확장: `panel.png`, `button_normal/pressed/disabled.png`, `line_label_a~h.png` (최종 크기로 저장), 미리보기 `sheet.png`에 추가

### 변경
- 오른쪽 패널을 x=450, 폭 180으로 재배치: 타이틀(빈 틀) / POOL / 피버 카운터 / 배당표
- 하단 표시창을 y=414, 높이 57로 재배치: CREDIT, 메시지, WIN, BET. 숫자 색 CREDIT #7dff9a, WIN #ffe14d, POOL #ff9a1f, BET 흰색, 라벨 #9aa0c8
- 하단 버튼 줄: 어두운 띠(x=6, y=354, 444×48) 위 버튼 5개 (y=360, 81×36). STOP 버튼도 3상태 스킨
- 피버 카운터: 4행 1열(체리, 포도, 벨, 세븐), 행 높이 26. 아이콘 ×2(24×20) 왼쪽, "×개수"는 오른쪽 고정 열에 오른쪽 정렬(갈무리9 ×2 = 20px). 세븐 개수는 빨간색 #e8283c
- 배당표: 2열(체리·수박·벨·BAR / 오렌지·포도·세븐), 아이콘(×2) + 배수 오른쪽 정렬, 어두운 구분선
- 당첨 강조 테두리: 흰 5px → 금색 #ffe14d 3px
- 피버 연출 글자를 갈무리 정수배로: FEVER! 75, 이름 45, BONUS 48
- 라인 라벨: 그림 바탕, 색을 A~H 지정색으로 변경
- 한 줄 숫자가 칸을 넘치면 글자를 반으로 줄임
- 디버그 창 높이를 줄여 하단 표시창 위에서 끝남
- 로직·`balance.json`·`feel.json` 변경 없음

## 0.8.0 — 2026-11-09 (6-B: 심볼·릴 보드 적용)

### 추가
- `BoardView`(`scripts/view/board_view.gd`): 릴 뒤 보드. 바탕 #3a2a5c, 외곽선 #2b1b3d, 전구 링 100개(아트 2×2, 4칸 간격, 켜짐 #ffe14d / 꺼짐 #8a7a3a 교대, 정지 상태)
- 칸 그림: 칸 바탕에 `cell_tile.png`, 그 위에 심볼 PNG를 아트 (2,2) 오프셋에 정수 3배로 배치 (`SymbolStyle.ART_SCALE`)
- 렌더링 설정: 기본 텍스처 필터 Nearest, 스트레치 `scale_mode=integer` (`project.godot` 두 줄)

### 변경
- 배치를 아트 좌표 ×3으로 변경: 칸 108×84(간격 없음), 첫 칸 (54,48), 보드 (42,36) 348×276
- STOP 버튼 96×33, y=318, 칸 가운데 정렬
- 라인 라벨 33×21, 보드 바깥으로 이동 (왼쪽 x=6 / 오른쪽 x=396 / 위쪽 y=9). 붙는 칸 기준과 위아래 쌓기는 그대로
- 릴 창의 회색 2px 테두리 제거 (타일 그림에 테두리가 있음). 그림 파일이 없으면 예전 색 박스+글자로 표시
- 하단 버튼 줄은 릴 가운데에 맞춰 놓이는 방식이라 보드 이동에 따라 왼쪽으로 14px 이동 (코드 변경 없음)
- 로직·`balance.json`·`feel.json` 변경 없음

### 수정
- 라인 라벨 크기가 기본 글꼴 기준 최소 크기로 커지던 문제 (글꼴 지정 후 크기를 줌)

## 0.7.0 — 2026-11-09 (5-C: 풀 획득 연출과 화면=로직 일치 검증)

### 추가
- 풀 획득 단계(`FeverOverlay.KIND_POOL`): 세븐 피버로 풀을 획득한 스핀은 세븐 단계 뒤에 "POOL GET!" / "POOL" / "POOL +금액" 단계가 이어짐. 단계가 끝나면 POOL 숫자가 초기값으로 돌아가고, CREDIT·WIN·안내 문구는 연출이 모두 끝난 뒤 한 번에 갱신 (건너뛰기·입력 잠금은 5-B와 같음)
- `feel.json` 새 키 `pool_overlay_sec` (기본 3.0, 범위 0.2~10): 풀 획득 단계를 보여 주는 시간. 다음 스핀부터 적용, 진행 중 연출 불변
- `scenes/test/match_test.tscn`: 같은 시드로 화면을 통해 1만 회(실제 밸런스 + 시험용 데이터 각각) 돌려 피버 발동 횟수·풀 획득 횟수·총 지급액을 로직 단독 시뮬레이션과 비교. 스핀마다 정지 방식(자동/START/키)과 연출(재생/스페이스 건너뜀/START 건너뜀)을 섞음

### 변경
- `FeverOverlay`: 단계마다 시간이 다를 수 있게 단계별 시작·끝 시각을 계산 (`play`에 `pool_sec` 추가, `total_seconds`가 단계 목록을 받음). `step_at()` 읽기 함수 추가
- 결과 확정 로직(`scripts/logic/`)·`balance.json` 변경 없음

## 0.6.0 — 2026-11-09 (5-B: 피버 발동 연출)

### 추가
- `FeverOverlay`(`scripts/view/fever_overlay.gd`): 화면 전체 오버레이. 단계마다 "FEVER!" / 심볼 이름 / "BONUS +금액". 피버가 여럿이면 balance.json 피버 대상 순서(체리, 포도, 벨, 세븐)로 차례 재생. 풀 획득 단계(`KIND_POOL`) 자리는 비워 둠(5-C)
- 오버레이 중 COIN/BET/MAX BET/CANCEL/STOP 잠금, 스페이스(START)로 연출 건너뛰기 (뜬 직후 잠금 시간 동안은 무시)
- `feel.json` 새 키: `fever_overlay_sec`(2.0, 0.2~10), `fever_step_gap`(0.3, 0~5), `fever_skip_lock_sec`(0.4, 0~5). 다음 스핀부터 적용, 진행 중 연출 불변

### 변경
- 정산(`GameState.settle_spin`) 호출 시점을 피버 연출이 끝난 뒤로 미룸. CREDIT·WIN·POOL·카운터·"라인 X + 피버 Y + 풀 Z" 안내는 그때 한 번에 갱신. 피버가 없는 스핀은 전과 같음
- 카운터: 오버레이가 뜨면 발동한 심볼이 0으로 보이고, 단계가 끝날 때 초기값으로
- 당첨 선은 정산이 아니라 릴이 멈춘 직후(오버레이 전)에 켬
- 결과 확정 로직(`scripts/logic/`)·`balance.json` 변경 없음

### 수정
- `FeverOverlay.total_seconds` 매개변수 이름이 `step_count()`와 겹치던 경고

## 0.5.0 — 2026-11-09 (5-A: 피버 카운터 패널과 POOL 색 단계)

### 추가
- `FeverPanel`(`scripts/view/fever_panel.gd`): 피버 카운터를 심볼별 한 줄(색 박스 + 이름 + ×남은 횟수)로 표시. 초기값 2 이상인 심볼이 마지막 1회 남으면 깜빡임(세븐 등 초기값 1은 제외)
- POOL 숫자 색 3단계: 주황 → 노랑 → 빨강+깜빡임. 기준은 `feel.json`의 `pool_yellow_from`(1000), `pool_red_from`(1500)

### 변경
- 피버 카운터가 글자 한 덩어리(InfoBox)에서 `FeverPanel`로 교체 (노드 이름 `FeverBox` 유지)
- `docs/기획서.md` 8·9장: 피버·풀 수치는 `balance.json`이 기준임을 명시, 풀 색 단계 추가
- 로직·`balance.json` 변경 없음

## 0.4.1 — 2026-11-09 (5단계 선행 과제: 릴 연출 방식 변경)

### 추가
- 릴별 출발 시간차·속도차를 `data/feel.json`으로 분리: `reel_start_delay`(릴1~3, 기본 [0, 0.08, 0.16]초), `reel_speed_scale`(릴1~3, 기본 [1.0, 0.95, 1.05]). 다음 스핀부터 적용, 진행 중 스핀은 불변 (`FeelConfig.ARRAY_SPECS`)
- `SpinController`: 출발 지연 처리, `reel_started` 신호, `has_started()`. 출발 전 릴은 STOP 불가, 회전 중 START는 출발 전 릴도 예약해 출발 직후 정지. 자동 정지 시각은 계속 START 기준
- `ReelMotion.start(target, feel, speed_scale)`: 릴별 속도 배율. `current_speed()`
- `ReelView.windows_are_sound()`, `window_at()`, `main.spin_controller()` (테스트용)

### 변경
- **칸 단위 클리핑 창**: 9칸의 테두리는 고정, 각 칸은 자기 칸 모양으로 잘라 보여 주고 그 안에서 심볼 두 개가 반쪽씩 걸쳐 스크롤. 심볼이 칸 밖으로 나가거나 이웃과 겹치지 않음. 위아래 반 칸 덤 영역과 어두운 가림막 제거 (`reel_view.gd`, `main.gd`)
- 칸 테두리(고정, 2px)를 창 위에 덧그림 (`ReelView.WINDOW_FRAME_*`)
- `docs/기획서.md` 릴 영역 문구, `docs/feel.md` 갱신
- 결과 확정 로직(`scripts/logic/`, `balance.json`)은 변경 없음

### 삭제
- `feel.json`의 `half_row` (칸 단위 창에서는 필요 없음)

### 수정
- (개발 중 발견) 출발 지연 중인 릴의 STOP 버튼이 출발해도 켜지지 않던 문제: `reel_started` 신호로 버튼 갱신

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

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
- **6-F3b 정산 연출 + AUTO** (다음): WIN 카운트업·동전·크레딧·틱 소리, AUTO 대기 정리. 결정: START = 확정 + 다음 판 시작, 동전은 포물선, 테스트 main 생성 지점에서만 `settle_presentation=false`, AUTO 대기 연장은 view 쪽(`auto_gap_sec` 조정 + `auto_advance` 앞당김), `tick.wav` 추가(동전 도착 소리는 tick 재사용)
- 결정(6-F1): 거절=cancel, AUTO 켜기·끄기=button, 피버·풀 연출 중 win_x 생략, fever_end는 자연 종료 때만, 오디오 버스는 코드 생성, BET/MAX/CANCEL은 main 래퍼로 소리 연결

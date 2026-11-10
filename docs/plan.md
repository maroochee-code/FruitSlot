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

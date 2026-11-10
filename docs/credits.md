# 출처와 라이선스 (credits)

## 폰트 — 갈무리 (Galmuri)
- 사용 파일: `assets/fonts/Galmuri9.ttf`, `Galmuri11.ttf`, `Galmuri14.ttf` (버전 v2.40.4, 수정 없이 원래 이름 그대로 사용)
- 저작권자: Copyright (c) 2019–2025 Lee Minseo (quiple@quiple.dev)
- 라이선스: SIL Open Font License 1.1 → 전문은 `assets/fonts/LICENSE.txt` (갈무리 배포본에 들어 있던 파일 그대로)
- 출처: https://github.com/quiple/galmuri (릴리스 v2.40.4), 공식 사이트 galmuri.quiple.dev
- **예약 폰트명(Reserved Font Name)**: 라이선스 파일의 저작권 문구 뒤에 지정된 예약 폰트명이 **없음**을 확인했다. 그래도 폰트 파일을 고치거나 이름을 바꾸지 않고 그대로 쓴다.
- 허용 범위(OFL 1.1 요약): 사용·게임에 포함·재배포 가능, 폰트 파일 자체를 단독으로 파는 것만 금지. 라이선스 문서와 저작권 표기를 같이 둘 것.
- 사용 크기(원래 크기의 정수배): 갈무리9(10px) ×1, 갈무리11(12px) ×1·×2·×4, 갈무리14(15px) ×3·×5
- 가져오기 설정: 안티앨리어싱 끔, 힌팅 끔, 서브픽셀 위치 끔 (각 `.ttf.import`)
- 갈무리 저장소에는 "Nintendo DS는 닌텐도의 상표이며 이 프로젝트와 무관하다"는 안내가 있다. 이 게임과는 관계없다.

## BGM — Suno로 만든 곡 (사용자 제작)
- `assets/sounds/bgm_main.mp3`: "Arcade Daydream" (Suno 곡 ID `0e7184c9-f7c9-405f-9d1e-fd2999057990`, https://suno.com/song/0e7184c9-f7c9-405f-9d1e-fd2999057990)
- `assets/sounds/bgm_fever.mp3`: "Fever Rush" (Suno 곡 ID `1cf549c1-9680-40b0-8cfa-036e1e6983e4`, https://suno.com/song/1cf549c1-9680-40b0-8cfa-036e1e6983e4)
- 제작일 2026-11-09, 두 곡 모두 **Suno 무료 플랜**으로 만들었다. 파일 메타데이터에 "made with suno"와 C2PA 출처 정보가 들어 있다(수정하지 않음).
- **확인 필요 (배포 전)**: 무료 플랜으로 만든 곡의 상업적 이용 가능 여부와 조건을 Suno의 공식 약관(Terms of Service / 플랜별 사용 권한)으로 다시 확인한다. 지금은 개인 테스트용으로만 쓴다. 확인 결과와 확인한 날짜를 이 항목에 적을 것. 상업적 이용이 안 되면 곡을 바꾸거나 유료 플랜 조건을 따져 봐야 한다.
- 프로젝트 안에서 곡을 코드로 반복·페이드해서 재생할 뿐 파일 자체는 편집하지 않았다.

## 효과음
- `assets/sounds/*.wav`(BGM 제외)는 `tools/gen_sounds.py`로 직접 합성한 소리다(펄스·삼각·노이즈 파형, 외부 녹음·원작 소리 없음). 시드를 고정해서 다시 만들면 같은 파일이 나온다.

## 도트 그림
- `assets/symbols`, `assets/ui` 의 그림은 `tools/gen_pixel_assets.py`로 직접 만든 것이다. 외부 그림을 쓰지 않았다. (6-D 벽지·프레임·로고의 글자 도트도 직접 찍었으며 폰트를 쓰지 않았다.)

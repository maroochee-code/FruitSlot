# maroochee slot

어릴 적 오락실에서 즐기던 **3×3 릴, 8라인 과일 슬롯**을 도트 그래픽으로 다시 만든 PC 게임입니다.
Godot 4.7.2와 Claude Code로 만든 1인 개발 프로젝트이며, 프로젝트 폴더 이름은 `FruitSlot`입니다.

> 이 게임의 크레딧은 게임 안의 점수일 뿐입니다. 현금·결제·환전은 없습니다.

## 특징

- 3×3 릴, 8라인(가로 3 · 세로 3 · 대각선 2) 클래식 과일 슬롯
- BET을 올리면 라인 A→H 순서로 1씩 배분되는 오락실식 베팅
- STOP 버튼으로 릴을 하나씩 멈추는 손맛 (STOP ALL로 한 번에 멈추기, 시간이 지나면 자동 정지)
- **피버**: 같은 과일 3개 당첨이 쌓이면 터지는 누적 보너스
- **풀**: 계속 쌓이는 누적 잭팟, 세븐 피버와 함께 획득
- AUTO 스핀, 당첨 정산 연출, 효과음 15종과 BGM 2곡
- GAME OVER 후 CONTINUE(최대 3회) / NEW GAME
- 최고 기록(BEST) 저장, 운영자 설정 화면
- 640×480 도트 화면을 3배(1280×960 창)로 확대하는 정수 배율 렌더링

## 실행 방법

[Releases](../../releases)에서 최신 zip을 받아 압축을 풀고 `FruitSlot.exe`를 실행합니다.
(Windows 64비트, 설치 필요 없음, exe 하나로 실행됩니다.)

## 조작

| 입력 | 동작 |
|---|---|
| B | BET (누를 때마다 1 증가) |
| Space / Enter | START (회전 중에는 STOP ALL, 연출 중에는 SKIP) |
| 1 / 2 / 3 | 릴 1 / 2 / 3 STOP |
| M · X · A | MAX BET · CANCEL · AUTO |
| 마우스 | 화면의 버튼 클릭 |
| Esc | 시작 화면에서 종료 |

시작 화면에서 **F2**를 누르면 운영자 설정(소리, 시작 크레딧, AUTO, 연출 속도 등)이 열립니다.
설정과 최고 기록은 `%APPDATA%\Godot\app_userdata\FruitSlot\` 에 저장됩니다.

## 규칙 요약

- 활성 라인에서 **같은 심볼 3개**가 나오면 당첨입니다. 당첨금은 심볼별 배당 × 그 라인의 베팅 수이고, 여러 라인이 동시에 당첨되면 합산됩니다.
- **BET 8 이상**(모든 라인에 베팅)일 때만 피버 적립과 풀 획득이 가능합니다.
- 시작 크레딧은 3,000이며, 크레딧이 0이 되면 GAME OVER 후 CONTINUE(+1,000, 최대 3회) 또는 NEW GAME(+3,000)을 고릅니다.
- 결과는 START를 누르는 순간 정해지며, STOP은 멈추는 타이밍 연출입니다.

자세한 규칙과 수치는 [기획서](기획서.md)와 `data/balance.json`에 있습니다.

## 소스에서 실행

1. [Godot 4.7.2](https://godotengine.org/)를 설치합니다.
2. 이 저장소를 받아 Godot으로 프로젝트를 엽니다.
3. F5로 실행합니다. 개발 빌드에서는 테스트 모드(시작 화면 F3)와 COIN 등 개발용 기능이 켜집니다.

내보내기 절차는 [docs/내보내기.md](docs/내보내기.md)를 보세요. 릴리스 exe는 반드시 **"디버그와 함께 내보내기"를 끄고** 만들어야 개발용 기능이 닫힙니다.

## 구조

- `scripts/logic/` — 슬롯 로직(결과 결정, 라인 판정, 피버·풀). 화면과 분리되어 있어 헤드리스로 테스트합니다.
- `scripts/view/` — 화면, 연출, 소리
- `data/` — `balance.json`(밸런스), `feel.json`(연출 값), `economy.json`(크레딧 규칙)
- `scenes/test/` — 테스트와 확인용 씬

테스트는 헤드리스로 실행합니다. 예: `godot --headless --path . res://scenes/test/settings_test.tscn`

## 크레딧

- 폰트: 갈무리 (OFL 1.1) — 출처는 [docs/credits.md](docs/credits.md)
- 효과음: 코드로 직접 합성
- BGM: Suno로 생성 — 곡 정보와 사용 조건은 [docs/credits.md](docs/credits.md)
- 엔진: [Godot Engine](https://godotengine.org/) (MIT License)

## 라이선스

아직 정하지 않았습니다. 별도 표기가 있기 전까지 모든 권리는 저작자에게 있습니다.

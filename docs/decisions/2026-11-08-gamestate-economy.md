# GameState 오토로드와 economy.json (2026-11-08, 3단계)

## 고른 것
- 크레딧·베팅·WIN은 `GameState` 오토로드(`scripts/autoload/game_state.gd`)가 관리하고, `SlotLogic`도 여기서 소유한다. 화면은 `insert_coin / raise_bet / start_spin`만 부르고 시그널로 값을 받는다.
- COIN 지급량(100)과 시작 크레딧(0)은 `data/economy.json`에 둔다.

## 이유
- 화면 여러 곳(하단 바, 버튼, 라벨)이 같은 값을 봐야 해서 전역 한 곳이 단순하다.
- 수치 하드코딩 금지 규칙을 지키되, `scripts/logic/`(BalanceData)는 건드리지 않기 위해 `balance.json`과 별도 파일로 뒀다.
- 오토로드 스크립트에는 `class_name`을 붙이지 않는다(오토로드 이름과 충돌). 테스트는 스크립트를 직접 `new()`해서 별도 인스턴스로 검사한다.

## 다른 후보
- `balance.json`에 economy 항목 추가: `BalanceData` 수정이 필요해 보류. 필요해지면 합칠 수 있다.
- 크레딧을 SlotLogic 안에 넣기: 로직이 화면 상태(COIN/BET 입력)까지 알게 되어 분리 원칙에 어긋난다.

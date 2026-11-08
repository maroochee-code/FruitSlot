# 출발 지연 중인 릴의 STOP 버튼이 출발해도 켜지지 않음

- **증상:** 릴별 출발 지연(`reel_start_delay`)을 넣은 뒤, 지연이 있는 릴이 출발해도 그 릴의 STOP 버튼이 회색(비활성) 그대로였다. (키 1·2·3은 정상 동작)
- **원인:** STOP 버튼 상태는 `_refresh_buttons()`가 정하는데, 이 함수는 START·STOP·릴 정지 같은 이벤트에서만 불렸다. "릴이 출발했다"는 이벤트가 없어서, 출발 시점에는 갱신되지 않았다.
- **발견:** `view_test`의 "모든 릴이 출발한 뒤 STOP 1·2·3 활성" 검사 실패
- **해결:** `SpinController`에 `reel_started(index)` 신호를 추가하고, `main.gd`가 받아서 `_refresh_buttons()`를 부르게 했다. `reel_test`에 신호 횟수 검사(릴마다 정확히 1번) 추가.
- **관련 파일:** `scripts/view/spin_controller.gd`, `scripts/view/main.gd`, `scenes/test/view_test.gd`, `scenes/test/reel_test.gd`
- **비슷한 버그를 만나면:** 화면 상태가 "시간이 지나서" 바뀌는 경우(출발·정지 등)는 그 변화를 알리는 신호가 있는지, 그 신호에 화면 갱신이 연결돼 있는지 먼저 확인한다.

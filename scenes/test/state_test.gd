extends Node
## GameState 테스트: COIN / BET 배분 / 크레딧 차감·합산 / 크레딧 부족 차단 / 베팅 자동 하향.
## 실제 balance.json과 economy.json을 쓰지만, 검사하는 것은 규칙(배분·차감·합산)이라 수치가 바뀌어도 유지된다.

const GAME_STATE_SCRIPT: String = "res://scripts/autoload/game_state.gd"
const SPINS_FOR_ACCOUNTING: int = 2000

var _passed: int = 0
var _failed: int = 0
var _data: BalanceData
var _rejects: Array[StringName] = []
## AUTO 테스트가 만든 GameState들 (판이 진행 중인 채 끝나면 종료 때 누수 경고가 나서 끝날 때 해제한다)
var _auto_states: Array[Node] = []


func _ready() -> void:
	_data = BalanceData.load_from_file()
	_test_start_state()
	_test_coin()
	_test_bet_distribution()
	_test_bet_wraps_at_max()
	_test_bet_limited_by_credit()
	_test_start_blocked()
	_test_max_bet()
	_test_cancel_bet()
	_test_spin_accounting()
	_test_two_phase_spin()
	_test_spin_lock()
	_test_bet_lowered_when_credit_short()
	_test_bet_zero_when_broke()
	_test_auto_continues()
	_test_auto_blocks_bet_buttons()
	_test_auto_toggle_rules()
	_test_auto_off_finishes_current_spin()
	_test_auto_on_during_spin()
	_test_auto_stops_when_credit_short()
	_test_auto_stop_on_win()
	_test_auto_same_results_as_manual()
	for state: Node in _auto_states:
		state.free()
	_auto_states.clear()
	print("==================== STATE TEST: %d 통과 / %d 실패 ====================" % [_passed, _failed])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------- 도우미

## 새 GameState를 만든다 (오토로드와 별개의 인스턴스).
func _fresh(rng_seed: int = 1) -> Node:
	var state: Node = load(GAME_STATE_SCRIPT).new()
	var economy: Dictionary = state.call("load_economy")
	state.call("initialize", _data, economy, rng_seed)
	_rejects.clear()
	state.connect("action_rejected", func(reason: StringName) -> void: _rejects.append(reason))
	return state


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", label)


func _ints(values: PackedInt32Array) -> Array[int]:
	var out: Array[int] = []
	for value: int in values:
		out.append(value)
	return out


func _bet_up_to(state: Node, target: int) -> void:
	while state.bet != target:
		state.raise_bet()


# ---------------------------------------------------------------- AUTO 도우미

## 크레딧을 넉넉히 넣고 베팅을 맞춘 새 상태. AUTO 대기시간은 0.5초로 고정한다.
func _auto_state(rng_seed: int, total_bet: int = 8, coins: int = 40) -> Node:
	var state: Node = _fresh(rng_seed)
	for i: int in coins:
		state.insert_coin()
	_bet_up_to(state, total_bet)
	state.auto_gap_sec = 0.5
	_auto_states.append(state)
	return state


## 이 시드로 첫 판을 돌렸을 때 총 당첨금 (같은 조건의 다른 인스턴스로 미리 확인)
func _first_payout(rng_seed: int, total_bet: int, coins: int) -> int:
	var probe: Node = _auto_state(rng_seed, total_bet, coins)
	return probe.play_spin().total_payout()


## 첫 판 당첨금이 조건을 만족하는 시드를 찾는다 (없으면 -1)
func _find_seed(total_bet: int, coins: int, want_win: bool) -> int:
	for candidate: int in range(1, 400):
		if (_first_payout(candidate, total_bet, coins) > 0) == want_win:
			return candidate
	return -1


# ---------------------------------------------------------------- 테스트

func _test_start_state() -> void:
	var state: Node = _fresh()
	_check(state.credit == 0, "시작 크레딧 0")
	_check(state.bet == 0, "시작 베팅 0")
	_check(state.last_win == 0, "시작 WIN 0")
	_check(not state.can_start(), "시작 직후 START 불가")
	_check(not state.can_raise_bet(), "크레딧 0이면 BET 불가")
	state.free()


func _test_coin() -> void:
	var state: Node = _fresh()
	state.insert_coin()
	_check(state.credit == state.coin_amount, "COIN 1회 = coin_amount")
	state.insert_coin()
	_check(state.credit == state.coin_amount * 2, "COIN 2회 누적")
	state.free()


func _test_bet_distribution() -> void:
	var state: Node = _fresh()
	state.insert_coin()
	state.raise_bet()
	_check(_ints(state.line_bets) == [1, 0, 0, 0, 0, 0, 0, 0], "BET 1 → A에 1")
	state.raise_bet()
	state.raise_bet()
	_check(_ints(state.line_bets) == [1, 1, 1, 0, 0, 0, 0, 0], "BET 3 → A,B,C에 1씩")
	_bet_up_to(state, 8)
	_check(_ints(state.line_bets) == [1, 1, 1, 1, 1, 1, 1, 1], "BET 8 → 모든 라인 1")
	state.raise_bet()
	_check(state.bet == 9 and _ints(state.line_bets) == [2, 1, 1, 1, 1, 1, 1, 1], "BET 9 → A만 2")
	_bet_up_to(state, 16)
	_check(_ints(state.line_bets) == [2, 2, 2, 2, 2, 2, 2, 2], "BET 16 → 모든 라인 2")
	state.free()


func _test_bet_wraps_at_max() -> void:
	var state: Node = _fresh()
	state.credit = 1000
	_bet_up_to(state, _data.max_total_bet)
	_check(state.bet == _data.max_total_bet, "최대 베팅 도달")
	_check(state.line_bets[0] == _data.max_total_bet / _data.line_count(), "최대 베팅 라인당 값")
	var ok: bool = state.raise_bet()
	_check(ok and state.bet == 1, "최대에서 BET 한 번 더 → 1로 순환")
	_check(state.credit == 1000, "BET은 크레딧을 차감하지 않음")
	state.free()


func _test_bet_limited_by_credit() -> void:
	var state: Node = _fresh()
	state.credit = 5
	_bet_up_to(state, 5)
	var ok: bool = state.raise_bet()
	_check(not ok and state.bet == 5, "크레딧(5) 이상으로 BET 증가 불가")
	_check(_rejects == [&"bet_over_credit"], "거절 사유 bet_over_credit")
	_check(not state.can_raise_bet(), "크레딧 한도에서 can_raise_bet false")
	state.free()
	var broke: Node = _fresh()
	var broke_ok: bool = broke.raise_bet()
	_check(not broke_ok and broke.bet == 0 and _rejects == [&"no_credit"], "크레딧 0에서 BET 거절(no_credit)")
	broke.free()


func _test_start_blocked() -> void:
	var state: Node = _fresh()
	_check(state.play_spin() == null and _rejects == [&"no_credit"], "크레딧 0에서 START 거절")
	state.insert_coin()
	_rejects.clear()
	_check(state.play_spin() == null and _rejects == [&"no_bet"], "베팅 0에서 START 거절(no_bet)")
	_check(state.credit == state.coin_amount, "거절된 START는 크레딧을 건드리지 않음")
	state.bet = 9999
	_rejects.clear()
	_check(state.play_spin() == null and _rejects == [&"no_credit"], "베팅이 크레딧보다 크면 START 거절")
	_check(state.credit == state.coin_amount, "거절 시 크레딧 불변")
	state.free()


func _test_max_bet() -> void:
	var state: Node = _fresh()
	_check(not state.max_bet() and _rejects == [&"no_credit"], "크레딧 0에서 MAX BET 거절")
	_check(not state.can_max_bet(), "크레딧 0이면 can_max_bet false")
	state.credit = 37
	_check(state.can_max_bet(), "크레딧 37, 베팅 0이면 MAX BET 가능")
	_check(state.max_bet() and state.bet == 37, "MAX BET = min(최대 베팅, 크레딧 37) = 37")
	_check(state.credit == 37, "MAX BET은 크레딧을 차감하지 않음")
	_check(_ints(state.line_bets) == _expected_bets(37), "MAX BET 37 → A→H 순서 배분")
	_check(not state.can_max_bet() and not state.max_bet(), "이미 목표값이면 MAX BET 불가")
	state.credit = 1000
	_check(state.can_max_bet(), "크레딧이 늘면 다시 MAX BET 가능")
	state.max_bet()
	_check(state.bet == _data.max_total_bet, "크레딧 1000이면 최대 베팅 %d" % _data.max_total_bet)
	_check(_ints(state.line_bets) == _expected_bets(_data.max_total_bet), "최대 베팅 배분")
	state.free()
	# 같은 베팅이면 BET 버튼으로 올린 것과 라인 배분이 같다
	var by_bet: Node = _fresh()
	by_bet.credit = 500
	_bet_up_to(by_bet, 21)
	var by_max: Node = _fresh()
	by_max.credit = 21
	by_max.max_bet()
	_check(_ints(by_bet.line_bets) == _ints(by_max.line_bets), "MAX BET 배분 = BET으로 올린 배분 (21)")
	by_bet.free()
	by_max.free()


func _test_cancel_bet() -> void:
	var state: Node = _fresh()
	_check(not state.can_cancel_bet() and not state.cancel_bet(), "베팅 0이면 CANCEL 불가")
	state.credit = 50
	_bet_up_to(state, 10)
	_check(state.can_cancel_bet(), "베팅 10이면 CANCEL 가능")
	_check(state.cancel_bet(), "CANCEL 성공")
	_check(state.bet == 0 and _ints(state.line_bets) == [0, 0, 0, 0, 0, 0, 0, 0], "CANCEL 후 베팅 0, 라인 베팅 모두 0")
	_check(state.credit == 50, "CANCEL은 크레딧을 바꾸지 않음")
	_check(not state.can_start(), "CANCEL 후 START 불가")
	state.raise_bet()
	_check(state.bet == 1, "CANCEL 후 BET 다시 1부터")
	state.free()


## 총 베팅을 A→H 순서로 나눈 기대값
func _expected_bets(total: int) -> Array[int]:
	var out: Array[int] = []
	var lines: int = _data.line_count()
	for i: int in lines:
		@warning_ignore("integer_division")
		out.append(total / lines + (1 if i < total % lines else 0))
	return out


## 스핀마다: 크레딧 = 이전 - 베팅 + 총 당첨금, WIN = 총 당첨금, 베팅은 항상 크레딧 이하
func _test_spin_accounting() -> void:
	var state: Node = _fresh(777)
	var bad: int = 0
	var spins: int = 0
	for i: int in SPINS_FOR_ACCOUNTING:
		if state.credit < 8:
			state.insert_coin()
		_bet_up_to(state, 8)
		var before: int = state.credit
		var result: SpinResult = state.play_spin()
		if result == null:
			bad += 1
			continue
		spins += 1
		var expected: int = before - 8 + result.total_payout()
		if state.credit != expected or state.last_win != result.total_payout() or state.bet > state.credit:
			bad += 1
	_check(spins == SPINS_FOR_ACCOUNTING, "스핀 %d회 모두 실행" % SPINS_FOR_ACCOUNTING)
	_check(bad == 0, "크레딧 = 이전 - 베팅 + 당첨금 (어긋난 횟수 %d)" % bad)
	state.free()


## 크레딧 8, 베팅 8에서 꽝이면 크레딧 0 → 베팅 0. 시드를 바꿔 가며 꽝/당첨 양쪽을 모두 만난다.
func _test_bet_lowered_when_credit_short() -> void:
	var lowered_seen: bool = false
	var kept_seen: bool = false
	var bad: int = 0
	for rng_seed: int in 200:
		var state: Node = _fresh(rng_seed)
		state.credit = 10
		state.bet = 8
		# 람다는 바깥 변수를 복사해 가므로, 값을 받을 배열을 따로 둔다.
		var captured: Array[int] = [-1]
		state.connect("spin_finished", func(_r: SpinResult, from: int) -> void: captured[0] = from)
		var result: SpinResult = state.play_spin()
		var credit: int = state.credit
		var lowered_from: int = captured[0]
		if credit < 8:
			lowered_seen = true
			if state.bet != credit or lowered_from != 8:
				bad += 1
		else:
			kept_seen = true
			if state.bet != 8 or lowered_from != 0:
				bad += 1
		if result == null:
			bad += 1
		state.free()
	_check(lowered_seen, "크레딧 부족 사례 발생")
	_check(kept_seen, "크레딧 충분 사례 발생")
	_check(bad == 0, "부족하면 베팅=크레딧으로 하향, 충분하면 유지 (어긋난 횟수 %d)" % bad)


func _test_bet_zero_when_broke() -> void:
	var broke_seen: bool = false
	var bad: int = 0
	for rng_seed: int in 100:
		var state: Node = _fresh(rng_seed)
		state.credit = 8
		state.bet = 8
		state.play_spin()
		if state.credit == 0:
			broke_seen = true
			if state.bet != 0 or state.can_start() or state.can_raise_bet():
				bad += 1
			if _ints(state.line_bets) != [0, 0, 0, 0, 0, 0, 0, 0]:
				bad += 1
		state.free()
	_check(broke_seen, "크레딧 0이 되는 사례 발생")
	_check(bad == 0, "크레딧 0이면 베팅 0, 라인 베팅 모두 0, START·BET 불가 (어긋난 횟수 %d)" % bad)


## START는 "차감 + 결과 확정", 정산은 따로. 정산 전에는 당첨금이 크레딧·WIN에 들어오지 않는다.
func _test_two_phase_spin() -> void:
	var bad: int = 0
	var seen_win: bool = false
	for rng_seed: int in 300:
		var state: Node = _fresh(rng_seed)
		state.credit = 100
		_bet_up_to(state, 8)
		var started: Array[SpinResult] = []
		var finished: Array[SpinResult] = []
		state.connect("spin_started", func(r: SpinResult) -> void: started.append(r))
		state.connect("spin_finished", func(r: SpinResult, _from: int) -> void: finished.append(r))
		var result: SpinResult = state.start_spin()
		if result == null or started.size() != 1 or not state.spinning:
			bad += 1
			state.free()
			continue
		if state.credit != 92 or state.last_win != 0 or not finished.is_empty():
			bad += 1
		if state.can_start() or state.start_spin() != null:
			bad += 1
		var settled: SpinResult = state.settle_spin()
		if settled != result or finished.size() != 1 or finished[0] != started[0] or state.spinning:
			bad += 1
		if state.credit != 92 + result.total_payout() or state.last_win != result.total_payout():
			bad += 1
		if result.total_payout() > 0:
			seen_win = true
		if state.settle_spin() != null:
			bad += 1
		state.free()
	_check(seen_win, "당첨 사례가 한 번 이상 나옴 (정산 검사용)")
	_check(bad == 0, "START는 차감만, 정산 후에 당첨금 합산, 이중 시작·이중 정산 거절 (어긋난 횟수 %d)" % bad)


## 회전 중에는 COIN/BET/MAX BET/CANCEL/START가 모두 막히고 상태가 바뀌지 않는다.
func _test_spin_lock() -> void:
	var state: Node = _fresh(5)
	state.credit = 100
	_bet_up_to(state, 8)
	state.start_spin()
	var credit: int = state.credit
	var bet: int = state.bet
	var lines: Array[int] = _ints(state.line_bets)
	state.insert_coin()
	var results: Array[bool] = [state.raise_bet(), state.max_bet(), state.cancel_bet()]
	_check(results == [false, false, false], "회전 중 BET·MAX BET·CANCEL 거절")
	_check(state.credit == credit and state.bet == bet and _ints(state.line_bets) == lines, "회전 중 COIN·BET·MAX BET·CANCEL이 상태를 바꾸지 않음")
	_check(not state.can_raise_bet() and not state.can_max_bet() and not state.can_cancel_bet() and not state.can_start(), "회전 중 can_* 모두 false")
	state.settle_spin()
	_check(state.can_cancel_bet(), "정산 뒤에는 다시 조작 가능")
	state.free()


# ---------------------------------------------------------------- AUTO 테스트

func _test_auto_continues() -> void:
	var state: Node = _auto_state(5)
	_check(state.start_auto() and state.auto_on, "AUTO ON: 켜짐")
	_check(state.spinning and state.auto_count() == 1, "AUTO ON: 쉬는 중이면 바로 첫 판 시작 (1회)")
	state.settle_spin()
	_check(not state.spinning and state.auto_on, "정산 뒤에도 AUTO는 켜져 있음")
	state.auto_advance(0.4)
	_check(not state.spinning, "대기시간(0.5초)이 지나기 전에는 다음 판이 시작되지 않음")
	state.auto_advance(0.2)
	_check(state.spinning and state.auto_count() == 2, "대기시간이 지나면 다음 판이 자동 시작 (2회)")
	state.auto_advance(5.0)
	_check(state.auto_count() == 2, "회전 중에는 대기시간이 흘러도 새 판이 시작되지 않음")
	var bets: Array[int] = []
	for i: int in 4:
		state.settle_spin()
		bets.append(state.bet)
		state.auto_advance(0.5)
	_check(bets == [8, 8, 8, 8] and state.bet == 8, "AUTO 중 BET 값 유지")
	_check(state.auto_count() == 6, "AUTO 켠 뒤 시작한 판 수 세기")
	var fast: Node = _auto_state(5)
	fast.auto_gap_sec = 0.0
	fast.start_auto()
	fast.settle_spin()
	fast.auto_advance(0.0)
	_check(fast.spinning, "대기시간 0이면 정산 직후 곧바로 다음 판")


func _test_auto_blocks_bet_buttons() -> void:
	var state: Node = _auto_state(6, 8)
	state.start_auto()
	state.settle_spin()
	var credit_before: int = state.credit
	_check(not state.can_raise_bet() and not state.can_max_bet() and not state.can_cancel_bet(), "AUTO 중 BET / MAX BET / CANCEL 비활성")
	_check(not state.raise_bet() and not state.max_bet() and not state.cancel_bet(), "AUTO 중 BET / MAX BET / CANCEL 무시")
	_check(state.bet == 8 and state.credit == credit_before, "무시된 입력은 베팅·크레딧을 바꾸지 않음")
	state.insert_coin()
	_check(state.credit == credit_before + state.coin_amount, "AUTO 중에도 COIN은 허용")
	state.stop_auto(AutoSpin.REASON_USER)
	_check(state.can_raise_bet() and state.can_cancel_bet(), "AUTO를 끄면 BET / CANCEL이 다시 활성")


func _test_auto_toggle_rules() -> void:
	var state: Node = _fresh(7)
	_auto_states.append(state)
	_check(not state.can_toggle_auto(), "베팅이 없으면 AUTO를 켤 수 없음")
	state.toggle_auto()
	_check(not state.auto_on and _rejects.size() == 1, "베팅 없이 AUTO를 켜면 거절")
	state.insert_coin()
	state.raise_bet()
	_check(state.can_toggle_auto(), "베팅이 있으면 AUTO를 켤 수 있음")
	var events: Array[String] = []
	state.connect("auto_changed", func(enabled: bool, count: int) -> void: events.append("changed %s %d" % [enabled, count]))
	state.connect("auto_stopped", func(reason: StringName) -> void: events.append("stopped %s" % reason))
	state.toggle_auto()
	_check(state.auto_on, "toggle_auto로 켜짐")
	state.settle_spin()
	state.toggle_auto()
	_check(not state.auto_on, "toggle_auto로 다시 끔")
	_check(events == ["changed true 0", "changed true 1", "changed false 1", "stopped user"], "시그널: 켜짐 → 첫 판(1회) → 꺼짐 → 이유(user): %s" % [events])


func _test_auto_off_finishes_current_spin() -> void:
	var state: Node = _auto_state(8)
	var finished: Array[int] = []
	state.connect("spin_finished", func(_result: SpinResult, _lowered: int) -> void: finished.append(1))
	state.start_auto()
	_check(state.spinning, "AUTO 첫 판 진행 중")
	state.stop_auto(AutoSpin.REASON_USER)
	_check(state.spinning and not state.auto_on, "AUTO를 꺼도 진행 중인 판은 끊기지 않음")
	var credit_before: int = state.credit
	var result: SpinResult = state.settle_spin()
	_check(result != null and finished.size() == 1 and state.credit == credit_before + result.total_payout(), "끈 뒤에도 진행 중인 판은 정상 정산됨")
	state.auto_advance(10.0)
	_check(not state.spinning and state.auto_count() == 1, "끈 뒤에는 다음 판이 시작되지 않음")
	var waiting: Node = _auto_state(8)
	waiting.start_auto()
	waiting.settle_spin()
	waiting.stop_auto(AutoSpin.REASON_USER)
	waiting.auto_advance(10.0)
	_check(not waiting.spinning and waiting.auto_count() == 1, "대기시간 중에 끄면 다음 판이 시작되지 않음")


func _test_auto_on_during_spin() -> void:
	var state: Node = _auto_state(9)
	state.start_spin()
	_check(state.can_toggle_auto(), "회전 중에도 AUTO를 켤 수 있음")
	state.start_auto()
	_check(state.auto_on and state.auto_count() == 0 and state.spinning, "회전 중에 켜면 이 판은 세지 않고 계속 진행")
	state.settle_spin()
	state.auto_advance(0.5)
	_check(state.spinning and state.auto_count() == 1, "정산 뒤 대기시간이 지나면 이어서 시작 (1회)")


func _test_auto_stops_when_credit_short() -> void:
	# 크레딧 100, 베팅 64: 당첨이 없으면 정산 뒤 크레딧(36)이 베팅보다 적다
	var lose_seed: int = _find_seed(64, 1, false)
	_check(lose_seed > 0, "(준비) 베팅 64 첫 판이 꽝인 시드를 찾음")
	var state: Node = _auto_state(lose_seed, 64, 1)
	var events: Array[String] = []
	state.connect("spin_finished", func(_result: SpinResult, lowered: int) -> void: events.append("finished %d" % lowered))
	state.connect("auto_stopped", func(reason: StringName) -> void: events.append("stopped %s" % reason))
	state.start_auto()
	state.settle_spin()
	_check(not state.auto_on, "크레딧이 총 BET보다 적으면 AUTO 자동 OFF")
	_check(events == ["finished 64", "stopped no_credit"], "정산(spin_finished) 다음에 해제 이유(no_credit)가 옴: %s" % [events])
	_check(state.bet == state.credit, "AUTO가 꺼진 뒤 기존 규칙대로 베팅이 크레딧만큼 낮아짐")
	state.auto_advance(10.0)
	_check(not state.spinning, "꺼진 뒤에는 다음 판이 시작되지 않음")


func _test_auto_stop_on_win() -> void:
	var win_seed: int = _find_seed(8, 40, true)
	var lose_seed: int = _find_seed(8, 40, false)
	_check(win_seed > 0 and lose_seed > 0, "(준비) 첫 판이 당첨인 시드와 꽝인 시드를 찾음")
	var original: int = _data.auto_stop_on_win_at
	_data.auto_stop_on_win_at = 0
	var off: Node = _auto_state(win_seed)
	off.start_auto()
	off.settle_spin()
	_check(off.auto_on, "stop_on_win_at = 0 이면 당첨이 있어도 AUTO 계속")
	_data.auto_stop_on_win_at = 1
	var stopped_reasons: Array[StringName] = []
	var on: Node = _auto_state(win_seed)
	on.connect("auto_stopped", func(reason: StringName) -> void: stopped_reasons.append(reason))
	on.start_auto()
	var win: int = on.settle_spin().total_payout()
	_check(win >= 1 and not on.auto_on and stopped_reasons == [AutoSpin.REASON_BIG_WIN], "stop_on_win_at = 1: 당첨(%d)이면 AUTO OFF (이유 big_win)" % win)
	var quiet: Node = _auto_state(lose_seed)
	quiet.start_auto()
	quiet.settle_spin()
	_check(quiet.auto_on, "당첨이 없으면(꽝) 기준 1이어도 AUTO 계속")
	_data.auto_stop_on_win_at = win + 1
	var above: Node = _auto_state(win_seed)
	above.start_auto()
	above.settle_spin()
	_check(above.auto_on, "당첨금이 기준 미만이면 AUTO 계속")
	_data.auto_stop_on_win_at = win
	var equal: Node = _auto_state(win_seed)
	equal.start_auto()
	equal.settle_spin()
	_check(not equal.auto_on, "당첨금이 기준과 같으면(이상) AUTO OFF")
	_data.auto_stop_on_win_at = original


## AUTO를 켜도 결과(RNG)는 켜지 않았을 때와 같은 시드에서 같다
func _test_auto_same_results_as_manual() -> void:
	var spins: int = 12
	var manual: Node = _auto_state(31)
	var manual_stops: Array = []
	var manual_payouts: Array[int] = []
	for i: int in spins:
		var result: SpinResult = manual.play_spin()
		manual_stops.append(_ints(result.stops))
		manual_payouts.append(result.total_payout())
	var auto: Node = _auto_state(31)
	var auto_stops: Array = []
	var auto_payouts: Array[int] = []
	auto.connect("spin_started", func(result: SpinResult) -> void: auto_stops.append(_ints(result.stops)))
	auto.start_auto()
	for i: int in spins:
		auto_payouts.append(auto.settle_spin().total_payout())
		auto.auto_advance(0.5)
	auto.stop_auto(AutoSpin.REASON_USER)
	auto_stops.resize(spins)
	_check(auto_stops == manual_stops and auto_payouts == manual_payouts, "같은 시드에서 AUTO 결과 = 수동 결과 (정지 위치·당첨금 %d판)" % spins)

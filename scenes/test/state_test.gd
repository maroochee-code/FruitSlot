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
	UserSettings.configure(false)
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
	_test_economy_values()
	_test_grant_credit()
	_test_coin_allowed()
	_test_game_over_judgement()
	_test_game_over_with_auto()
	_test_coin_during_game_over()
	_test_continue()
	_test_continue_keeps_run()
	_test_new_game()
	_test_title_start()
	_test_user_values()
	_test_high_score_hook()
	_test_mode_start_values()
	_test_tools_grant_credit()
	_test_tools_fever_and_pool()
	_test_force_next_win()
	_test_results_unchanged_by_test_mode()
	_test_tainted_and_high_score()
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


# ---------------------------------------------------------------- 7-B: GAME OVER / CONTINUE / NEW GAME / grant_credit / COIN

## 크레딧과 베팅이 이 값인 채 한 판을 돌려 "마지막 판"을 만든다 (꽝이면 크레딧 0)
const LAST_BET: int = 8
const DRAIN_MAX_SPINS: int = 3000
const SEED_SEARCH_MAX: int = 400


## economy 값 일부를 바꾼 새 GameState (오토로드와 별개의 인스턴스)
func _fresh_with(overrides: Dictionary, rng_seed: int = 1) -> Node:
	var state: Node = load(GAME_STATE_SCRIPT).new()
	var economy: Dictionary = state.call("load_economy")
	for key: Variant in overrides:
		economy[key] = overrides[key]
	state.call("initialize", _data, economy, rng_seed)
	_rejects.clear()
	return state


## 크레딧 LAST_BET, 베팅 LAST_BET로 한 판 돌렸을 때 당첨이 있는(want_win) / 없는 시드를 찾는다 (없으면 -1)
func _last_spin_seed(want_win: bool) -> int:
	for candidate: int in range(1, SEED_SEARCH_MAX):
		var probe: Node = _fresh(candidate)
		probe.credit = LAST_BET
		probe.bet = LAST_BET
		var result: SpinResult = probe.play_spin()
		probe.free()
		if (result != null and result.total_payout() > 0) == want_win:
			return candidate
	return -1


## 크레딧을 LAST_BET로 맞춰 가며 GAME OVER가 될 때까지 판을 돌린다 (직접 대입은 테스트 준비용). GAME OVER가 됐으면 true.
func _drain_to_game_over(state: Node) -> bool:
	for i: int in DRAIN_MAX_SPINS:
		if state.is_game_over():
			return true
		state.credit = LAST_BET
		state.bet = LAST_BET
		state.play_spin()
	return state.is_game_over()


## 이미 GAME OVER가 된 새 GameState
func _game_over_state(overrides: Dictionary = {}, rng_seed: int = 3) -> Node:
	var state: Node = _fresh_with(overrides, rng_seed)
	_drain_to_game_over(state)
	return state


func _test_economy_values() -> void:
	var probe: Node = load(GAME_STATE_SCRIPT).new()
	var economy: Dictionary = probe.call("load_economy")
	probe.free()
	_check(economy.has("start_credit") and economy.has("continue_credit") and economy.has("continue_max") and economy.has("coin_amount"), "economy: 4개 키를 모두 읽음")
	_check(int(economy["start_credit"]) >= 1 and int(economy["continue_credit"]) >= 1 and int(economy["continue_max"]) >= 0 and int(economy["coin_amount"]) >= 1, "economy 값이 허용 범위 안 (시작·CONTINUE 1 이상, 횟수 0 이상, COIN 1 이상)")
	var state: Node = _fresh()
	_check(state.credit == 0 and state.continues_left == state.continue_max and state.continue_max == int(economy["continue_max"]), "initialize는 크레딧 0으로 시작하고 이어하기 횟수만 채움")
	state.free()


func _test_grant_credit() -> void:
	var state: Node = _fresh()
	var events: Array[String] = []
	state.connect("credit_granted", func(amount: int, reason: StringName) -> void: events.append("%d %s" % [amount, reason]))
	var seen: Array[int] = []
	state.connect("credit_changed", func(value: int) -> void: seen.append(value))
	state.grant_credit(500, &"start")
	_check(state.credit == 500 and events == ["500 start"] and seen == [500], "grant_credit(start): 크레딧 +, credit_granted와 credit_changed 시그널")
	_check(not state.run_tainted, "start 지급은 테스트 판 표시를 남기지 않음")
	state.grant_credit(200, &"continue")
	_check(state.credit == 700 and not state.run_tainted, "grant_credit(continue): 표시 없음")
	state.grant_credit(100, &"test_coin")
	_check(state.credit == 800 and state.run_tainted and events[2] == "100 test_coin", "grant_credit(test_coin): 테스트 판 표시")
	_check(state.run_peak_credit == 800, "지급이 최고 크레딧 기록에 반영됨")
	state.free()
	# 시작 지급·CONTINUE·COIN이 모두 이 입구를 거친다
	var routed: Node = _fresh_with({ "start_credit": 40, "continue_credit": 30, "coin_amount": 20 })
	var reasons: Array[StringName] = []
	routed.connect("credit_granted", func(_amount: int, reason: StringName) -> void: reasons.append(reason))
	routed.new_game()
	routed.insert_coin()
	_drain_to_game_over(routed)
	routed.continue_game()
	_check(reasons == [&"start", &"test_coin", &"continue"], "NEW GAME·COIN·CONTINUE가 모두 grant_credit을 거침 (이유 %s)" % [reasons])
	routed.free()


func _test_coin_allowed() -> void:
	var state: Node = _fresh()
	_check(state.coin_allowed() == OS.is_debug_build(), "coin_allowed: 개발 빌드(테스트 모드 켜짐)에서는 true")
	state.dev_build = true
	state.test_mode = true
	_check(state.coin_allowed(), "개발 빌드 + 테스트 모드 켜짐 → COIN 가능")
	state.test_mode = false
	_check(not state.coin_allowed(), "개발 빌드라도 테스트 모드가 꺼지면 COIN 불가")
	state.dev_build = false
	state.test_mode = true
	_check(not state.coin_allowed(), "릴리즈 빌드는 테스트 모드와 상관없이 COIN 불가")
	var granted: Array[int] = []
	var inserted: Array[int] = []
	state.connect("credit_granted", func(amount: int, _reason: StringName) -> void: granted.append(amount))
	state.connect("coin_inserted", func(amount: int) -> void: inserted.append(amount))
	state.insert_coin()
	_check(state.credit == 0 and granted.is_empty() and inserted.is_empty() and not state.run_tainted, "COIN 불가면 크레딧·시그널·테스트 판 표시 모두 변화 없음")
	state.dev_build = true
	state.insert_coin()
	_check(state.credit == state.coin_amount and inserted == [state.coin_amount] and state.run_tainted, "COIN 가능으로 돌리면 지급 + 테스트 판 표시")
	state.free()


## GAME OVER 판정은 정산 순간, 로직 크레딧이 0일 때만
func _test_game_over_judgement() -> void:
	var lose_seed: int = _last_spin_seed(false)
	var win_seed: int = _last_spin_seed(true)
	_check(lose_seed > 0 and win_seed > 0, "마지막 판이 꽝인 시드·당첨인 시드를 모두 찾음")
	# 꽝: 정산 순간 GAME OVER
	var lost: Node = _fresh(lose_seed)
	var signals: Array[String] = []
	lost.connect("game_over", func() -> void: signals.append("game_over"))
	lost.credit = LAST_BET
	lost.bet = LAST_BET
	lost.start_spin()
	_check(lost.credit == 0 and lost.spinning and not lost.is_game_over() and signals.is_empty(), "회전 중에는 크레딧이 0이어도 GAME OVER가 아님")
	lost.settle_spin()
	_check(lost.credit == 0 and lost.is_game_over() and signals == ["game_over"], "정산 뒤 크레딧 0 → GAME OVER (시그널 한 번)")
	_check(lost.bet == 0 and not lost.spinning and not lost.can_start() and not lost.can_raise_bet(), "GAME OVER 때 베팅 0·START/BET 불가")
	lost.free()
	# 당첨: 크레딧이 0이 아니므로 GAME OVER가 아님
	var won: Node = _fresh(win_seed)
	var won_signals: Array[String] = []
	won.connect("game_over", func() -> void: won_signals.append("game_over"))
	won.credit = LAST_BET
	won.bet = LAST_BET
	won.play_spin()
	_check(won.credit > 0 and not won.is_game_over() and won_signals.is_empty(), "당첨으로 크레딧이 남으면 GAME OVER가 아님")
	won.free()
	# 크레딧이 남은 꽝: GAME OVER가 아님
	var kept: Node = _fresh(lose_seed)
	kept.credit = 100
	kept.bet = LAST_BET
	kept.play_spin()
	_check(kept.credit == 92 and not kept.is_game_over(), "꽝이어도 크레딧이 남으면 GAME OVER가 아님")
	kept.free()
	# 크레딧을 직접 0으로 놓아도(정산을 거치지 않으면) 판정하지 않음
	var direct: Node = _fresh()
	direct.credit = 0
	_check(not direct.is_game_over(), "정산을 거치지 않은 크레딧 0은 GAME OVER가 아님 (처음 상태 포함)")
	direct.free()
	# NEW GAME 직후도 GAME OVER가 아님
	var fresh: Node = _fresh()
	fresh.new_game()
	_check(not fresh.is_game_over() and fresh.credit == fresh.start_credit, "NEW GAME 직후는 GAME OVER가 아님")
	fresh.free()


## AUTO 중 크레딧이 0이 되면: AUTO 꺼짐 → 정산 완료 → AUTO 해제 이유 → GAME OVER 순서
func _test_game_over_with_auto() -> void:
	var lose_seed: int = _last_spin_seed(false)
	var state: Node = _fresh(lose_seed)
	_auto_states.append(state)
	state.credit = LAST_BET
	state.bet = LAST_BET
	state.auto_gap_sec = 0.5
	state.start_auto()
	var events: Array[String] = []
	state.connect("auto_changed", func(enabled: bool, _count: int) -> void: events.append("auto_changed %s" % enabled))
	state.connect("spin_finished", func(_r: SpinResult, _from: int) -> void: events.append("spin_finished"))
	state.connect("auto_stopped", func(reason: StringName) -> void: events.append("auto_stopped %s" % reason))
	state.connect("game_over", func() -> void: events.append("game_over"))
	state.settle_spin()
	_check(events == ["auto_changed false", "spin_finished", "auto_stopped no_credit", "game_over"], "AUTO 중 0: AUTO 꺼짐 → 정산 완료 → 해제 이유 → GAME OVER 순서 (%s)" % [events])
	_check(not state.auto_on and state.is_game_over() and state.credit == 0, "그 뒤 AUTO는 꺼져 있고 GAME OVER")
	state.auto_advance(10.0)
	_check(not state.spinning, "GAME OVER 뒤에는 AUTO가 새 판을 시작하지 않음")
	_check(not state.can_toggle_auto(), "GAME OVER 중에는 AUTO를 켤 수 없음")


## 개발 빌드: GAME OVER 중 COIN으로 크레딧이 생기면 GAME OVER가 해제되어 상태가 일관됨
func _test_coin_during_game_over() -> void:
	var state: Node = _game_over_state()
	_check(state.is_game_over() and state.credit == 0 and state.coin_allowed(), "준비: GAME OVER + 개발 빌드")
	var game_over_count: Array[int] = [0]
	state.connect("game_over", func() -> void: game_over_count[0] += 1)
	var continues_before: int = state.continues_left
	state.insert_coin()
	_check(state.credit == state.coin_amount and not state.is_game_over(), "GAME OVER 중 COIN → 크레딧이 생기고 GAME OVER 해제")
	_check(not state.can_continue() and not state.continue_game(), "해제된 뒤에는 CONTINUE 불가")
	_check(state.continues_left == continues_before and state.run_tainted, "이어하기 횟수는 안 줄고, 테스트 판 표시")
	# 다시 0이 되면 GAME OVER가 다시 판정되고, 이어하기 횟수는 그대로
	_check(_drain_to_game_over(state) and game_over_count[0] == 1 and state.continues_left == continues_before, "다시 0이 되면 GAME OVER 다시 판정 (시그널 1번, 횟수 불변)")
	state.free()


func _test_continue() -> void:
	# GAME OVER가 아니면 CONTINUE는 거절된다
	var alive: Node = _fresh()
	alive.credit = 50
	_check(not alive.can_continue() and not alive.continue_game() and alive.credit == 50 and alive.continues_left == alive.continue_max, "GAME OVER가 아니면 CONTINUE 거절·상태 불변")
	alive.free()
	# 3번까지 가능하고 4번째는 거절
	var state: Node = _game_over_state()
	var results: Array[bool] = []
	var credits: Array[int] = []
	var lefts: Array[int] = []
	for i: int in state.continue_max + 1:
		if not state.is_game_over():
			_check(_drain_to_game_over(state), "CONTINUE %d번째 준비: 다시 GAME OVER" % i)
		results.append(state.continue_game())
		credits.append(state.credit)
		lefts.append(state.continues_left)
	var want_results: Array[bool] = []
	var want_credits: Array[int] = []
	var want_lefts: Array[int] = []
	for i: int in state.continue_max + 1:
		var allowed: bool = i < state.continue_max
		want_results.append(allowed)
		want_credits.append(state.continue_credit if allowed else 0)
		want_lefts.append(maxi(0, state.continue_max - i - 1))
	_check(results == want_results, "CONTINUE는 continue_max(%d)번까지만 성공 (%s)" % [state.continue_max, results])
	_check(credits == want_credits and lefts == want_lefts, "CONTINUE마다 continue_credit 지급·남은 횟수 감소 (크레딧 %s, 남은 %s)" % [credits, lefts])
	_check(state.is_game_over() and not state.can_continue() and state.run_continues_used == state.continue_max, "횟수를 다 쓰면 GAME OVER 그대로·CONTINUE 불가·사용 횟수 = continue_max")
	state.free()
	# continue_max가 0이면 처음부터 이어하기 없음
	var none: Node = _game_over_state({ "continue_max": 0 })
	_check(none.is_game_over() and none.continues_left == 0 and not none.can_continue() and not none.continue_game(), "continue_max 0이면 이어하기 없음")
	none.free()
	# CONTINUE 뒤 베팅 복구: 직전 베팅(크레딧 이내)
	var restored: Node = _game_over_state()
	_check(restored.bet == 0, "GAME OVER 때 베팅은 0")
	restored.continue_game()
	_check(restored.bet == mini(LAST_BET, restored.continue_credit) and restored.credit == restored.continue_credit and _ints(restored.line_bets) == _expected_bets(restored.bet), "CONTINUE 뒤 베팅이 직전 베팅(최대 %d)으로 복구되고 라인 배분도 맞음" % LAST_BET)
	_check(not restored.is_game_over() and restored.can_start(), "CONTINUE 뒤 GAME OVER 해제·START 가능")
	restored.free()
	var short: Node = _game_over_state({ "continue_credit": 5 })
	short.continue_game()
	_check(short.credit == 5 and short.bet == 5, "크레딧이 모자라면 베팅은 크레딧 이내로 복구 (5)")
	short.free()


## CONTINUE는 POOL·피버 카운터와 판 기록을 그대로 유지한다
func _test_continue_keeps_run() -> void:
	var state: Node = _fresh(11)
	state.credit = 100000
	state.bet = LAST_BET
	for i: int in 40:
		state.play_spin()
	_check(_drain_to_game_over(state), "준비: 여러 판 뒤 GAME OVER")
	var pool: int = state.get_pool()
	var counts_hash: int = state.get_fever_counts().hash()
	var spins: int = state.run_spins
	var peak: int = state.run_peak_credit
	_check(pool > _data.pool_initial, "준비: POOL이 초기값보다 쌓여 있음 (%d > %d)" % [pool, _data.pool_initial])
	state.continue_game()
	_check(state.get_pool() == pool and state.get_fever_counts().hash() == counts_hash, "CONTINUE 뒤에도 POOL·피버 카운터 유지")
	_check(state.run_spins == spins and state.run_peak_credit >= peak and state.run_continues_used == 1, "판 기록(스핀 수·최고 크레딧)은 이어지고 이어하기 사용 수 1")
	state.free()


func _test_new_game() -> void:
	var state: Node = _fresh(11)
	state.credit = 100000
	state.bet = LAST_BET
	for i: int in 40:
		state.play_spin()
	state.insert_coin()
	_drain_to_game_over(state)
	state.continue_game()
	_drain_to_game_over(state)
	_check(state.is_game_over() and state.continues_left == state.continue_max - 1 and state.run_tainted and state.run_spins > 0, "준비: POOL·카운터가 쌓이고, 이어하기 1회 사용, 테스트 판 표시, GAME OVER")
	var events: Array[String] = []
	state.connect("new_game_started", func() -> void: events.append("new_game_started"))
	state.connect("credit_granted", func(amount: int, reason: StringName) -> void: events.append("granted %d %s" % [amount, reason]))
	_check(state.new_game(), "NEW GAME 성공")
	_check(state.credit == state.start_credit and not state.is_game_over(), "NEW GAME: 크레딧 = 시작 크레딧(3000), GAME OVER 해제")
	_check(state.get_pool() == _data.pool_initial and state.get_fever_counts().hash() == _data.fever_initial_counts.hash(), "NEW GAME: POOL·피버 카운터 초기화")
	_check(state.continues_left == state.continue_max, "NEW GAME: 이어하기 횟수 복구")
	_check(state.bet == 0 and _ints(state.line_bets) == [0, 0, 0, 0, 0, 0, 0, 0] and state.last_win == 0 and not state.auto_on and not state.spinning, "NEW GAME: 베팅 0·WIN 0·AUTO 꺼짐")
	_check(state.run_spins == 0 and state.run_continues_used == 0 and not state.run_tainted and state.run_peak_credit == state.start_credit, "NEW GAME: 판 기록(스핀 수·이어하기 사용·테스트 판 표시·최고 크레딧) 초기화")
	_check(events == ["new_game_started", "granted %d start" % state.start_credit], "NEW GAME 시그널: 초기화 알림 → 시작 지급 (%s)" % [events])
	# 초기화 뒤 다시 정상 플레이 가능
	state.raise_bet()
	_check(state.play_spin() != null, "NEW GAME 뒤 정상 플레이")
	state.free()
	# 시작 크레딧 값을 따른다 (별도 NEW GAME 코인 값 없음)
	var other: Node = _fresh_with({ "start_credit": 777 })
	other.new_game()
	_check(other.credit == 777, "NEW GAME 코인은 start_credit 값을 따름 (777)")
	other.free()
	# 회전 중에는 거절하고 아무것도 바꾸지 않는다
	var busy: Node = _fresh(5)
	busy.new_game()
	busy.raise_bet()
	busy.start_spin()
	var credit: int = busy.credit
	_check(not busy.new_game() and busy.credit == credit and busy.spinning, "회전 중 NEW GAME은 거절·상태 불변")
	busy.settle_spin()
	busy.free()


## 7-C: 오토로드는 크레딧 0으로 대기하고, 시작 화면의 START(= new_game())가 시작 크레딧을 준다.
func _test_title_start() -> void:
	# 게임을 켠 직후(오토로드 _ready)에는 크레딧 0, 시작 지급 없음
	var booted: Node = load(GAME_STATE_SCRIPT).new()
	var boot_grants: Array[StringName] = []
	booted.connect("credit_granted", func(_amount: int, reason: StringName) -> void: boot_grants.append(reason))
	add_child(booted)
	_check(booted.ready_ok and booted.credit == 0 and not booted.is_game_over() and booted.bet == 0, "시작 직후: 크레딧 0, GAME OVER 아님, 베팅 0")
	_check(boot_grants.is_empty() and not booted.run_tainted and booted.continues_left == booted.continue_max, "시작 직후: 지급 없음(시작 크레딧은 START가 준다)")
	# START = new_game(): grant_credit(start) 경유로 시작 크레딧 한 번, POOL·카운터·이어하기 초기값
	var grants: Array[String] = []
	booted.connect("credit_granted", func(amount: int, reason: StringName) -> void: grants.append("%d %s" % [amount, reason]))
	_check(booted.new_game(), "START(new_game) 성공")
	_check(booted.credit == booted.start_credit and grants == ["%d start" % booted.start_credit], "START: 시작 크레딧이 grant_credit(start)로 한 번만 지급 (%s)" % [grants])
	_check(booted.get_pool() == _data.pool_initial and booted.get_fever_counts().hash() == _data.fever_initial_counts.hash() and booted.continues_left == booted.continue_max, "START: POOL·피버 카운터·이어하기 횟수 초기값")
	_check(not booted.run_tainted and booted.bet == 0 and booted.last_win == 0 and not booted.is_game_over(), "START: 테스트 판 표시 없음·베팅 0·WIN 0")
	# START 뒤 COIN은 coin_allowed() 그대로: 릴리즈 빌드와 테스트 모드 꺼짐에서는 비활성
	booted.dev_build = false
	var credit: int = booted.credit
	var coin_events: Array[int] = []
	booted.connect("coin_inserted", func(amount: int) -> void: coin_events.append(amount))
	booted.insert_coin()
	_check(not booted.coin_allowed() and booted.credit == credit and coin_events.is_empty() and not booted.run_tainted, "START 뒤 릴리즈 빌드(dev_build false): COIN 불가, 크레딧·테스트 판 표시 불변")
	booted.dev_build = true
	booted.test_mode = false
	booted.insert_coin()
	_check(not booted.coin_allowed() and booted.credit == credit, "START 뒤 테스트 모드 꺼짐: COIN 불가")
	booted.test_mode = true
	booted.insert_coin()
	_check(booted.coin_allowed() and booted.credit == credit + booted.coin_amount and booted.run_tainted, "START 뒤 개발 빌드+테스트 모드: COIN 지급, 테스트 판 표시")
	booted.free()


## 8-A: 운영자 설정이 economy 값·AUTO 기준에 적용되는 방식과 GAME OVER 때의 최고 기록
func _test_user_values() -> void:
	UserSettings.configure(false)
	# 기본값: 설정이 없으면 economy.json 값 그대로
	var state: Node = _fresh(21)
	var base_start: int = state.start_credit
	var base_continue: int = state.continue_credit
	var base_max: int = state.continue_max
	var base_coin: int = state.coin_amount
	state.apply_user_values()
	_check(state.start_credit == base_start and state.continue_credit == base_continue and state.continue_max == base_max and state.coin_amount == base_coin, "설정이 없으면(꺼짐) apply_user_values 뒤에도 economy 값 그대로")
	# 덮어쓰기
	var user: UserSettings = UserSettings.new()
	user.set_value("start_credit", 5000)
	user.set_value("continue_credit", 1500)
	user.set_value("continue_max", 1)
	user.set_value("coin_amount", 50)
	user.set_value("auto_stop_on_win_at", 777)
	var grants: Array[String] = []
	state.connect("credit_granted", func(amount: int, reason: StringName) -> void: grants.append("%d %s" % [amount, reason]))
	state.apply_user_values(user)
	_check(state.start_credit == 5000 and state.continue_credit == 1500 and state.continue_max == 1 and state.coin_amount == 50, "apply_user_values: economy 4개 값을 덮어씀")
	_check(state._auto.stop_on_win_at == 777, "apply_user_values: AUTO 큰 당첨 정지 기준을 덮어씀")
	_check(state.credit == 0 and grants.is_empty(), "apply_user_values는 크레딧을 올리지 않음 (grant_credit을 거치지 않음)")
	# 다음 NEW GAME부터 적용
	_check(state.new_game() and state.credit == 5000 and grants == ["5000 start"], "다음 NEW GAME(START)부터 새 시작 크레딧이 grant_credit(start)로 지급")
	_check(state.continues_left == 1, "NEW GAME이 CONTINUE 횟수를 새 값(1)으로 복구")
	_check(_drain_to_game_over(state) and state.can_continue(), "GAME OVER 뒤 CONTINUE 가능")
	grants.clear()
	_check(state.continue_game() and state.credit == 1500 and grants == ["1500 continue"], "CONTINUE는 새 CONTINUE 코인(1500)을 grant_credit(continue)로 지급")
	_drain_to_game_over(state)
	_check(not state.can_continue() and not state.continue_game(), "CONTINUE 횟수 1회를 쓰면 더는 안 됨")
	# 설정을 지우면 기본값으로 돌아감 (economy 사전을 다시 읽지 않아도)
	state.apply_user_values(UserSettings.new())
	_check(state.start_credit == base_start and state.continue_credit == base_continue and state.continue_max == base_max and state.coin_amount == base_coin and state._auto.stop_on_win_at == 0, "설정을 지우고 적용하면 기본값(economy.json·balance.json)으로 복귀")
	state.free()
	# COIN은 덮어쓴 지급량을 쓰되 coin_allowed 규칙·grant_credit 경유는 그대로
	var coin_state: Node = _fresh(22)
	var coin_user: UserSettings = UserSettings.new()
	coin_user.set_value("coin_amount", 250)
	coin_state.apply_user_values(coin_user)
	var coin_grants: Array[String] = []
	coin_state.connect("credit_granted", func(amount: int, reason: StringName) -> void: coin_grants.append("%d %s" % [amount, reason]))
	coin_state.dev_build = true
	coin_state.insert_coin()
	_check(coin_state.credit == 250 and coin_grants == ["250 test_coin"] and coin_state.run_tainted, "COIN 지급량 덮어쓰기: grant_credit(test_coin) 경유, 테스트 판 표시")
	coin_state.dev_build = false
	coin_state.insert_coin()
	_check(coin_state.credit == 250, "지급량을 바꿔도 릴리즈 빌드(dev_build false)에서는 COIN 불가")
	coin_state.free()
	# 초기화되지 않은 GameState에서는 아무것도 하지 않음
	var raw: Node = load(GAME_STATE_SCRIPT).new()
	raw.apply_user_values(user)
	_check(raw.start_credit == 0 and not raw.ready_ok, "initialize 전에는 apply_user_values가 아무것도 안 함")
	raw.free()
	# AUTO 정지 기준이 실제 동작에 쓰임
	var auto_state: Node = _fresh(23)
	var auto_user: UserSettings = UserSettings.new()
	auto_user.set_value("auto_stop_on_win_at", 1)
	auto_state.apply_user_values(auto_user)
	_check(auto_state._auto.is_big_win(1) and not auto_state._auto.is_big_win(0), "AUTO 정지 기준 1: 당첨 1 이상이면 정지 판정")
	auto_state.free()


func _test_high_score_hook() -> void:
	UserSettings.configure(false)
	# 테스트 판(COIN 사용)은 기록하지 않음
	var tainted: Node = _fresh(31)
	tainted.new_game()
	tainted.dev_build = true
	tainted.insert_coin()
	_check(tainted.run_tainted, "준비: COIN을 쓴 테스트 판")
	_check(_drain_to_game_over(tainted), "테스트 판도 GAME OVER까지 진행")
	_check(HighScore.active().best_peak_credit == 0, "테스트 판의 GAME OVER는 최고 기록을 바꾸지 않음")
	tainted.free()
	# 일반 판은 GAME OVER 때 그 판의 최고 크레딧을 기록
	var clean: Node = _fresh(32)
	clean.new_game()
	_check(_drain_to_game_over(clean), "준비: 일반 판 GAME OVER")
	var peak: int = clean.run_peak_credit
	_check(peak >= clean.start_credit and HighScore.active().best_peak_credit == peak, "GAME OVER 때 판의 최고 크레딧(%d)이 최고 기록으로 저장" % peak)
	# CONTINUE 뒤 다시 GAME OVER: 더 큰 값일 때만 갱신
	clean.continue_game()
	_drain_to_game_over(clean)
	_check(HighScore.active().best_peak_credit == clean.run_peak_credit and clean.run_peak_credit >= peak, "CONTINUE 뒤 두 번째 GAME OVER에서도 판 최고치 기준으로 기록")
	clean.free()
	# 더 낮은 판은 기록을 낮추지 않음
	var low: Node = _fresh_with({ "start_credit": 10 }, 33)
	low.new_game()
	_drain_to_game_over(low)
	_check(HighScore.active().best_peak_credit >= peak, "더 낮은 판의 GAME OVER는 최고 기록을 낮추지 않음")
	low.free()
	UserSettings.configure(false)


# ---------------------------------------------------------------- 8-B 테스트 모드

## 한 판을 처음부터 끝까지 돌린다 (START → 정산). 크레딧·베팅은 직접 정해 둔다.
func _spin_once(state: Node, spin_bet: int = LAST_BET) -> SpinResult:
	state.credit = 100000
	state.bet = spin_bet
	var result: SpinResult = state.start_spin()
	state.settle_spin()
	return result


func _test_mode_start_values() -> void:
	# 트리 밖에서 만든 인스턴스(_ready 없음)는 클래스 기본값(켜짐)을 쓴다 → 기존 COIN 검사가 그대로 유지됨
	var plain: Node = _fresh()
	_check(plain.test_mode and plain.dev_build == OS.is_debug_build(), "트리 밖 인스턴스: 테스트 모드 기본값 켜짐 (기존 테스트 호환)")
	plain.free()
	# 게임을 켠 것처럼 트리에 넣으면(_ready) 테스트 모드가 꺼진 채 시작
	var booted: Node = load(GAME_STATE_SCRIPT).new()
	add_child(booted)
	_check(booted.ready_ok and not booted.test_mode, "게임을 켜면(_ready) 테스트 모드는 꺼진 상태로 시작")
	booted.dev_build = true
	_check(not booted.coin_allowed(), "개발 빌드여도 테스트 모드가 꺼져 있으면 COIN 불가")
	booted.insert_coin()
	_check(booted.credit == 0 and not booted.run_tainted, "꺼진 상태의 COIN은 아무 일도 안 함")
	booted.test_mode = true
	_check(booted.coin_allowed(), "테스트 모드를 켜면 COIN 가능")
	booted.dev_build = false
	_check(not booted.coin_allowed(), "릴리즈 빌드는 테스트 모드가 켜져 있어도 COIN 불가")
	booted.free()


func _test_tools_grant_credit() -> void:
	var state: Node = _fresh(41)
	var grants: Array[String] = []
	state.connect("credit_granted", func(amount: int, reason: StringName) -> void: grants.append("%d %s" % [amount, reason]))
	_check(state.test_grant_credit(state.coin_amount * 10) and state.credit == state.coin_amount * 10, "크레딧 지급: coin_amount × 10")
	_check(grants == ["%d test_coin" % (state.coin_amount * 10)] and state.run_tainted, "grant_credit(test_coin)을 거치고 테스트 판 표시")
	_check(not state.test_grant_credit(0) and not state.test_grant_credit(-5) and state.credit == state.coin_amount * 10, "0·음수 지급은 거절")
	state.test_mode = false
	_check(not state.test_grant_credit(100) and state.credit == state.coin_amount * 10, "테스트 모드 꺼짐: 지급 거절")
	state.test_mode = true
	state.dev_build = false
	_check(not state.test_grant_credit(100) and state.credit == state.coin_amount * 10, "릴리즈 빌드: 지급 거절")
	state.dev_build = true
	state.bet = LAST_BET
	state.start_spin()
	var credit_during: int = state.credit
	_check(not state.test_grant_credit(100) and state.credit == credit_during, "릴 회전 중에는 거절")
	state.settle_spin()
	state.free()
	# 크레딧이 0이 된 GAME OVER 중에도 기존 grant_credit 규칙대로 GAME OVER가 풀림 (새 규칙 없음)
	var over: Node = _game_over_state({}, 42)
	over.test_mode = true
	over.dev_build = true
	_check(over.is_game_over() and over.test_grant_credit(500) and not over.is_game_over(), "GAME OVER 중 지급: 기존 grant_credit 규칙대로 GAME OVER 해제")
	over.free()


func _test_tools_fever_and_pool() -> void:
	var state: Node = _fresh(43)
	var changes: Array[int] = [0]
	state.connect("test_state_changed", func() -> void: changes[0] += 1)
	_check(state.test_set_fever_count("CHERRY", 1) and state.get_fever_counts()["CHERRY"] == 1, "체리 카운터를 1로 설정")
	_check(state.run_tainted and changes[0] == 1, "설정하면 테스트 판 표시 + 상태 변경 시그널 1번")
	var untouched: bool = state.get_fever_counts()["GRAPE"] == _data.fever_initial_counts["GRAPE"] and state.get_fever_counts()["BELL"] == _data.fever_initial_counts["BELL"]
	_check(untouched, "다른 심볼 카운터는 그대로")
	_check(not state.test_set_fever_count("LEMON", 1) and not state.test_set_fever_count("CHERRY", 0) and not state.test_set_fever_count("CHERRY", _data.fever_initial_counts["CHERRY"] + 1), "모르는 심볼·0·초기값 초과는 거절")
	_check(changes[0] == 1, "거절하면 시그널도 없음")
	_check(state.test_set_pool(1500) and state.get_pool() == 1500 and changes[0] == 2, "풀 금액 설정 + 시그널")
	_check(not state.test_set_pool(-1) and state.get_pool() == 1500, "음수 풀은 거절")
	state.test_mode = false
	_check(not state.test_set_pool(10) and not state.test_set_fever_count("GRAPE", 1) and state.get_pool() == 1500, "테스트 모드 꺼짐: 상태 설정 거절")
	state.test_mode = true
	state.dev_build = false
	_check(not state.test_set_pool(10) and not state.test_set_fever_count("GRAPE", 1) and state.get_pool() == 1500, "릴리즈 빌드: 상태 설정 거절")
	state.dev_build = true
	state.credit = 100
	state.bet = LAST_BET
	state.start_spin()
	_check(not state.test_set_pool(10) and not state.test_set_fever_count("GRAPE", 1) and state.get_pool() != 10, "릴 회전 중에는 상태 설정 거절")
	state.settle_spin()
	state.free()
	# 설정한 카운터가 기존 규칙으로 피버·보너스로 이어짐 (평균 베팅 합 = (초기-설정) × max(BET, 피버 최소 베팅))
	for bet_value: int in [16, 0]:
		var flow: Node = _fresh(44)
		flow.bet = bet_value
		flow.test_set_fever_count("CHERRY", 1)
		flow.test_force_next_win("CHERRY")
		var trigger_bet: int = bet_value if bet_value > 0 else LAST_BET
		var result: SpinResult = _spin_once(flow, trigger_bet)
		var expected: int = int(_data.fever_multipliers["CHERRY"]) * trigger_bet
		_check(result.fever_triggers.has("CHERRY") and result.fever_bonuses["CHERRY"] == expected, "카운터 1 설정(BET %d) → 체리 당첨에서 피버 발동, 보너스 = 배수 × %d" % [bet_value, trigger_bet])
		_check(flow.get_fever_counts()["CHERRY"] == _data.fever_initial_counts["CHERRY"], "발동 뒤 카운터는 초기값으로")
		flow.free()
	# 설정한 풀을 세븐 피버가 기존 규칙으로 획득하고 풀은 초기값으로 돌아감
	var pool_flow: Node = _fresh(45)
	pool_flow.test_set_pool(1800)
	pool_flow.test_force_next_win("SEVEN")
	var pool_result: SpinResult = _spin_once(pool_flow)
	var contribution: int = roundi(LAST_BET * _data.pool_contribution_rate)
	_check(pool_result.pool_won >= 1800 and pool_result.pool_won <= 1800 + contribution + 1 and pool_flow.get_pool() == _data.pool_initial, "설정한 풀 1800을 세븐 피버로 획득 (적립 포함), 풀은 초기값으로")
	_check(pool_result.fever_triggers.has("SEVEN") and pool_result.total_payout() == pool_result.line_payout + pool_result.fever_bonus + pool_result.pool_won, "지급 = 라인 + 피버 + 풀 (기존 규칙)")
	pool_flow.free()


func _test_force_next_win() -> void:
	var state: Node = _fresh(46)
	_check(state.forced_symbol() == "", "처음엔 예약 없음")
	_check(state.test_force_next_win("SEVEN") and state.forced_symbol() == "SEVEN" and state.run_tainted, "다음 판 세븐 당첨 예약, 테스트 판 표시")
	_check(not state.test_force_next_win("LEMON") and state.forced_symbol() == "SEVEN", "모르는 심볼은 거절하고 기존 예약 유지")
	state.credit = 100000
	state.bet = LAST_BET
	var result: SpinResult = state.start_spin()
	var seven_line: bool = false
	for win: LineWin in result.line_wins:
		seven_line = seven_line or win.symbol == "SEVEN"
	_check(seven_line and result.fever_triggers.has("SEVEN") and result.pool_won > 0, "예약한 판에 세븐 라인 당첨 + 세븐 피버 + 풀 획득 (기존 규칙)")
	_check(state.forced_symbol() == "", "예약은 1회용 (판이 시작되면 지워짐)")
	var credit_before_settle: int = state.credit
	state.settle_spin()
	_check(state.credit == credit_before_settle + result.total_payout() and state.run_tainted, "정산은 기존 규칙 그대로 (당첨금 합산), 테스트 판")
	_check(state.test_force_next_win("CHERRY") and state.test_force_next_win("") and state.forced_symbol() == "", "빈 문자열로 예약 취소")
	var normal: SpinResult = _spin_once(state)
	_check(normal != null and state.forced_symbol() == "", "취소한 뒤의 판은 평소 판")
	# 예약 뒤 테스트 모드가 꺼지면(또는 릴리즈) 지정값이 들어가지 않고 예약도 지워짐
	var guard: Node = _fresh(47)
	var twin: Node = _fresh(47)
	guard.test_force_next_win("SEVEN")
	guard.test_mode = false
	var guarded: SpinResult = _spin_once(guard)
	var plain: SpinResult = _spin_once(twin)
	_check(guarded.stops == plain.stops and guard.forced_symbol() == "", "예약 뒤 테스트 모드가 꺼지면 지정값이 들어가지 않음 (같은 시드와 같은 결과)")
	guard.free()
	twin.free()
	var release: Node = _fresh(48)
	release.dev_build = false
	_check(not release.test_force_next_win("SEVEN") and release.forced_symbol() == "", "릴리즈 빌드: 예약 자체가 거절")
	release.free()
	var busy: Node = _fresh(49)
	busy.credit = 100
	busy.bet = LAST_BET
	busy.start_spin()
	_check(not busy.test_force_next_win("SEVEN"), "릴 회전 중에는 예약 거절")
	busy.settle_spin()
	busy.free()
	state.free()


## 테스트 도구를 쓰지 않으면 결과가 로직과 완전히 같고, 강제 판 뒤의 시드 순서도 변하지 않는다
func _test_results_unchanged_by_test_mode() -> void:
	var off: Node = _fresh(51)
	off.test_mode = false
	var on: Node = _fresh(51)
	var bare: SlotLogic = SlotLogic.new(_data, 51)
	var same: bool = true
	for i: int in 300:
		var a: SpinResult = _spin_once(off)
		var b: SpinResult = _spin_once(on)
		var c: SpinResult = bare.spin(LAST_BET)
		same = same and a.stops == b.stops and b.stops == c.stops and a.total_payout() == c.total_payout()
	_check(same, "테스트 모드 꺼짐/켜짐/순수 로직: 같은 시드 300판 정지 위치·지급이 완전히 같음 (도구를 쓰지 않으면 불변)")
	_check(not on.run_tainted and not off.run_tainted, "테스트 모드를 켜 두기만 하면 테스트 판 표시가 켜지지 않음")
	off.free()
	on.free()
	var forced: Node = _fresh(52)
	var reference: Node = _fresh(52)
	forced.test_force_next_win("SEVEN")
	_spin_once(forced)
	_spin_once(reference)
	var follows: bool = true
	for i: int in 100:
		follows = follows and _spin_once(forced).stops == _spin_once(reference).stops
	_check(follows, "강제한 판 뒤의 100판은 강제하지 않은 경우와 같은 정지 위치 (RNG를 평소처럼 소비)")
	forced.free()
	reference.free()


func _test_tainted_and_high_score() -> void:
	UserSettings.configure(false)
	# 도구를 쓴 판은 GAME OVER가 되어도 최고 기록에 들어가지 않고, NEW GAME에서 표시와 예약이 풀림
	for tool_index: int in 3:
		var state: Node = _fresh(60 + tool_index)
		state.new_game()
		_check(not state.run_tainted, "도구 사용 전에는 테스트 판 표시 없음 (%d)" % tool_index)
		match tool_index:
			0:
				state.test_set_pool(900)
			1:
				state.test_set_fever_count("GRAPE", 1)
			_:
				state.test_force_next_win("CHERRY")
		_check(state.run_tainted, "도구 사용 뒤 테스트 판 표시 (%d)" % tool_index)
		_drain_to_game_over(state)
		_check(HighScore.active().best_peak_credit == 0, "테스트 도구를 쓴 판의 GAME OVER는 최고 기록에 들어가지 않음 (%d)" % tool_index)
		state.free()
	var again: Node = _fresh(63)
	again.new_game()
	again.test_force_next_win("SEVEN")
	again.new_game()
	_check(not again.run_tainted and again.forced_symbol() == "", "NEW GAME: 테스트 판 표시와 예약이 풀림")
	_drain_to_game_over(again)
	_check(HighScore.active().best_peak_credit == again.run_peak_credit and again.run_peak_credit > 0, "도구를 쓰지 않은 판은 평소처럼 최고 기록으로 남음")
	again.free()
	UserSettings.configure(false)

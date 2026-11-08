extends Node
## GameState 테스트: COIN / BET 배분 / 크레딧 차감·합산 / 크레딧 부족 차단 / 베팅 자동 하향.
## 실제 balance.json과 economy.json을 쓰지만, 검사하는 것은 규칙(배분·차감·합산)이라 수치가 바뀌어도 유지된다.

const GAME_STATE_SCRIPT: String = "res://scripts/autoload/game_state.gd"
const SPINS_FOR_ACCOUNTING: int = 2000

var _passed: int = 0
var _failed: int = 0
var _data: BalanceData
var _rejects: Array[StringName] = []


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
	_test_bet_lowered_when_credit_short()
	_test_bet_zero_when_broke()
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
	_check(state.start_spin() == null and _rejects == [&"no_credit"], "크레딧 0에서 START 거절")
	state.insert_coin()
	_rejects.clear()
	_check(state.start_spin() == null and _rejects == [&"no_bet"], "베팅 0에서 START 거절(no_bet)")
	_check(state.credit == state.coin_amount, "거절된 START는 크레딧을 건드리지 않음")
	state.bet = 9999
	_rejects.clear()
	_check(state.start_spin() == null and _rejects == [&"no_credit"], "베팅이 크레딧보다 크면 START 거절")
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
		var result: SpinResult = state.start_spin()
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
		var result: SpinResult = state.start_spin()
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
		state.start_spin()
		if state.credit == 0:
			broke_seen = true
			if state.bet != 0 or state.can_start() or state.can_raise_bet():
				bad += 1
			if _ints(state.line_bets) != [0, 0, 0, 0, 0, 0, 0, 0]:
				bad += 1
		state.free()
	_check(broke_seen, "크레딧 0이 되는 사례 발생")
	_check(bad == 0, "크레딧 0이면 베팅 0, 라인 베팅 모두 0, START·BET 불가 (어긋난 횟수 %d)" % bad)

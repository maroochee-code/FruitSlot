extends Node
## SlotLogic 판정 테스트. 손으로 만든 판과 테스트 전용 데이터로 규칙을 확인한다.
## 실제 balance.json 수치를 바꿔도 이 테스트는 영향을 받지 않는다.

const C: String = "CHERRY"
const O: String = "ORANGE"
const G: String = "GRAPE"
const S: String = "SEVEN"
const FULL_BET: int = 8

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_real_balance_loads()
	_test_distribute_bet()
	_test_no_win()
	_test_horizontal_vertical_diagonal()
	_test_inactive_line_does_not_pay()
	_test_line_bet_multiplies_payout()
	_test_build_grid_wraps()
	_test_seed_reproducible()
	_test_cherry_fever()
	_test_fever_needs_full_bet()
	_test_multiple_fever_symbols_one_spin()
	_test_pool_accumulates_and_awards()
	_test_pool_not_awarded_below_full_bet()
	_test_fever_bonus_average_bet()
	_test_fever_bonus_basis_setting()
	_test_theory_hand_checked()
	_test_theory_matches_logic()
	_test_forced_stops_keep_rng_sequence()
	_test_set_fever_count()
	_test_set_pool()
	_test_find_stops_with_win()
	print("==================== LOGIC TEST: %d 통과 / %d 실패 ====================" % [_passed, _failed])
	# 화면 없이(--headless) 실행할 때만 종료한다. 에디터·MCP 실행은 창을 열어 둔다.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------- 테스트 데이터

## 릴 스트립(10칸): 0~2 체리, 3~5 세븐, 6 오렌지, 7 포도, 8 오렌지, 9 포도
func _test_dict() -> Dictionary:
	var strip: Array = [C, C, C, S, S, S, O, G, O, G]
	return {
		"version": "test",
		"reel_count": 3,
		"visible_rows": 3,
		"symbols": [{ "id": C }, { "id": O }, { "id": G }, { "id": S }],
		"paytable": { C: 10, O: 15, G: 30, S: 200 },
		"reels": [strip, strip.duplicate(), strip.duplicate()],
		"lines": [
			{ "id": "A", "type": "horizontal", "cells": [[0, 1], [1, 1], [2, 1]] },
			{ "id": "B", "type": "horizontal", "cells": [[0, 0], [1, 0], [2, 0]] },
			{ "id": "C", "type": "horizontal", "cells": [[0, 2], [1, 2], [2, 2]] },
			{ "id": "D", "type": "diagonal", "cells": [[0, 0], [1, 1], [2, 2]] },
			{ "id": "E", "type": "diagonal", "cells": [[0, 2], [1, 1], [2, 0]] },
			{ "id": "F", "type": "vertical", "cells": [[0, 0], [0, 1], [0, 2]] },
			{ "id": "G", "type": "vertical", "cells": [[1, 0], [1, 1], [1, 2]] },
			{ "id": "H", "type": "vertical", "cells": [[2, 0], [2, 1], [2, 2]] },
		],
		"bet": { "max_total": 64 },
		"fever": {
			"min_total_bet": 8,
			"targets": [
				{ "symbol": C, "initial_count": 5, "bonus_multiplier": 20 },
				{ "symbol": G, "initial_count": 2, "bonus_multiplier": 40 },
				{ "symbol": S, "initial_count": 1, "bonus_multiplier": 100 },
			],
		},
		"pool": { "initial": 500, "contribution_rate": 0.05, "min_total_bet": 8, "award_on_fever": S },
	}


func _new_logic() -> SlotLogic:
	return SlotLogic.new(BalanceData.from_dict(_test_dict()), 1)


## 열 단위로 적은 판: [[열0 위,가운데,아래], [열1 ...], [열2 ...]]
func _grid(columns: Array) -> Array[PackedStringArray]:
	var grid: Array[PackedStringArray] = []
	for column: Variant in columns:
		grid.append(PackedStringArray(column))
	return grid


func _win_ids(wins: Array[LineWin]) -> String:
	var ids: PackedStringArray = PackedStringArray()
	for win: LineWin in wins:
		ids.append(win.line_id)
	return ",".join(ids)


# ---------------------------------------------------------------- 테스트

func _test_real_balance_loads() -> void:
	var data: BalanceData = BalanceData.load_from_file()
	_check(data != null, "balance.json 로드·검사 통과")
	if data == null:
		return
	_check(data.line_count() == 8, "라인 8개")
	for i: int in data.reels.size():
		_check(data.reels[i].size() == 32, "릴 %d 스트립 32칸" % (i + 1))


func _test_distribute_bet() -> void:
	var logic: SlotLogic = _new_logic()
	_check(logic.distribute_bet(1) == PackedInt32Array([1, 0, 0, 0, 0, 0, 0, 0]), "BET 1 → A만 1")
	_check(logic.distribute_bet(3) == PackedInt32Array([1, 1, 1, 0, 0, 0, 0, 0]), "BET 3 → A,B,C 1")
	_check(logic.distribute_bet(8) == PackedInt32Array([1, 1, 1, 1, 1, 1, 1, 1]), "BET 8 → 모두 1")
	_check(logic.distribute_bet(11) == PackedInt32Array([2, 2, 2, 1, 1, 1, 1, 1]), "BET 11 → A~C 2, 나머지 1")
	_check(logic.distribute_bet(16) == PackedInt32Array([2, 2, 2, 2, 2, 2, 2, 2]), "BET 16 → 모두 2")
	_check(not logic.is_valid_bet(0) and not logic.is_valid_bet(65) and logic.is_valid_bet(64), "베팅 범위 1~64")


func _test_no_win() -> void:
	var logic: SlotLogic = _new_logic()
	var grid: Array[PackedStringArray] = _grid([[C, O, G], [O, G, C], [O, C, S]])
	var wins: Array[LineWin] = logic.evaluate_lines(grid, logic.distribute_bet(FULL_BET))
	_check(wins.is_empty(), "일치 없음 → 당첨 0")


func _test_horizontal_vertical_diagonal() -> void:
	var logic: SlotLogic = _new_logic()
	var bets: PackedInt32Array = logic.distribute_bet(FULL_BET)
	var middle: Array[LineWin] = logic.evaluate_lines(_grid([[O, C, G], [G, C, O], [O, C, G]]), bets)
	_check(_win_ids(middle) == "A" and middle[0].payout == 10, "가운데 줄 체리 → A, 10")
	var column: Array[LineWin] = logic.evaluate_lines(_grid([[G, G, G], [O, C, O], [C, O, C]]), bets)
	_check(_win_ids(column) == "F" and column[0].payout == 30 and column[0].line_type == "vertical", "왼쪽 세로 포도 → F, 30")
	var diagonal: Array[LineWin] = logic.evaluate_lines(_grid([[S, O, C], [O, S, O], [C, O, S]]), bets)
	_check(_win_ids(diagonal) == "D" and diagonal[0].payout == 200, "↘ 대각 세븐 → D, 200")
	var anti: Array[LineWin] = logic.evaluate_lines(_grid([[S, O, C], [O, C, O], [C, O, S]]), bets)
	_check(_win_ids(anti) == "E" and anti[0].symbol == C, "↗ 대각 체리 → E")
	var full: Array[LineWin] = logic.evaluate_lines(_grid([[C, C, C], [C, C, C], [C, C, C]]), bets)
	_check(full.size() == 8, "9칸 모두 체리 → 8라인 모두 당첨")


func _test_inactive_line_does_not_pay() -> void:
	var logic: SlotLogic = _new_logic()
	var grid: Array[PackedStringArray] = _grid([[C, O, G], [C, G, O], [C, O, G]])
	_check(logic.evaluate_lines(grid, logic.distribute_bet(1)).is_empty(), "BET 1(A만) → 윗줄(B) 체리는 미지급")
	_check(_win_ids(logic.evaluate_lines(grid, logic.distribute_bet(2))) == "B", "BET 2 → B 지급")


func _test_line_bet_multiplies_payout() -> void:
	var logic: SlotLogic = _new_logic()
	var grid: Array[PackedStringArray] = _grid([[O, C, G], [G, C, O], [O, C, G]])
	var wins: Array[LineWin] = logic.evaluate_lines(grid, logic.distribute_bet(24))
	_check(wins.size() == 1 and wins[0].line_bet == 3 and wins[0].payout == 30, "라인 베팅 3 × 체리 10 = 30")


func _test_build_grid_wraps() -> void:
	var logic: SlotLogic = _new_logic()
	var grid: Array[PackedStringArray] = logic.build_grid(PackedInt32Array([9, 0, 8]))
	_check(grid[0] == PackedStringArray([G, C, C]), "정지 9 → 9,0,1번 (끝에서 처음으로 이어짐)")
	_check(grid[1] == PackedStringArray([C, C, C]), "정지 0 → 0,1,2번")
	_check(grid[2] == PackedStringArray([O, G, C]), "정지 8 → 8,9,0번")


func _test_seed_reproducible() -> void:
	var first: SlotLogic = _new_logic()
	var second: SlotLogic = _new_logic()
	var same: bool = true
	for i: int in 200:
		if first.spin(FULL_BET).stops != second.spin(FULL_BET).stops:
			same = false
	_check(same, "같은 시드 → 같은 결과 200회")


func _test_cherry_fever() -> void:
	var logic: SlotLogic = _new_logic()
	var all_cherry: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var result: SpinResult
	for i: int in 4:
		result = logic.resolve_stops(all_cherry, FULL_BET)
	_check(result.line_payout == 80, "체리 8라인 당첨 → 80")
	_check(logic.get_fever_counts()[C] == 1, "여러 라인 당첨돼도 스핀당 1 감소 (5 → 4회 후 1)")
	result = logic.resolve_stops(all_cherry, FULL_BET)
	_check(result.fever_triggers == PackedStringArray([C]), "5번째 체리 당첨 → 체리 피버 발동")
	_check(result.fever_bonus == 160, "피버 보너스 = 20 × 총 베팅 8 = 160")
	_check(result.total_payout() == 240, "총 지급 = 라인 80 + 피버 160")
	_check(logic.get_fever_counts()[C] == 5, "발동 후 카운터 초기값 5로 리셋")


func _test_fever_needs_full_bet() -> void:
	var logic: SlotLogic = _new_logic()
	var result: SpinResult = logic.resolve_stops(PackedInt32Array([0, 0, 0]), 7)
	_check(result.line_payout == 70 and result.fever_hits.is_empty(), "BET 7 → 당첨은 지급, 피버 카운트 없음")
	_check(logic.get_fever_counts()[C] == 5, "BET 7 → 체리 카운터 그대로 5")


func _test_multiple_fever_symbols_one_spin() -> void:
	var logic: SlotLogic = _new_logic()
	# 정지 [9,9,9] → 모든 열 G,C,C : 윗줄 포도(B), 가운데·아랫줄 체리(A,C)
	var both: PackedInt32Array = PackedInt32Array([9, 9, 9])
	var first: SpinResult = logic.resolve_stops(both, FULL_BET)
	_check(_win_ids(first.line_wins) == "A,B,C", "윗줄 포도 + 가운데·아랫줄 체리 → A,B,C")
	_check(first.fever_hits == PackedStringArray([C, G]), "체리·포도 동시 당첨 → 둘 다 1 감소")
	_check(logic.get_fever_counts()[C] == 4 and logic.get_fever_counts()[G] == 1, "체리 5→4, 포도 2→1")
	var second: SpinResult = logic.resolve_stops(both, FULL_BET)
	_check(second.fever_triggers == PackedStringArray([G]) and second.fever_bonus == 320, "포도 피버 발동, 40 × 8 = 320")


func _test_pool_accumulates_and_awards() -> void:
	var logic: SlotLogic = _new_logic()
	var no_seven: PackedInt32Array = PackedInt32Array([6, 7, 6])
	for i: int in 3:
		logic.resolve_stops(no_seven, FULL_BET)
	_check(logic.get_pool() == 501, "풀 500 + 0.4 × 3 = 501.2 → 표시 501")
	var result: SpinResult = logic.resolve_stops(PackedInt32Array([3, 3, 3]), FULL_BET)
	_check(result.line_payout == 1600, "세븐 9칸 → 8라인 × 200 = 1600")
	_check(result.fever_triggers.has(S) and result.fever_bonuses[S] == 800, "세븐 피버 보너스 = 100 × 8 = 800")
	_check(result.pool_won == 501, "풀 획득 = 501.6의 정수 501 (적립 후 판정)")
	_check(logic.get_pool() == 500, "획득 후 풀 500으로 리셋")
	_check(result.total_payout() == 1600 + 800 + 501, "총 지급 = 라인 + 피버 + 풀")


func _test_pool_not_awarded_below_full_bet() -> void:
	var logic: SlotLogic = _new_logic()
	var result: SpinResult = logic.resolve_stops(PackedInt32Array([3, 3, 3]), 4)
	_check(result.pool_won == 0 and result.fever_bonus == 0, "BET 4 세븐 → 피버·풀 없음")
	_check(logic.get_pool() == 500, "BET 4도 풀 적립: 500 + 0.2 → 표시 500")


## 체리 카운터(5)를 주어진 베팅 순서로 줄여 발동시키고, 마지막 판의 결과를 돌려준다.
func _cherry_fever_with(logic: SlotLogic, bet_list: Array[int]) -> SpinResult:
	var result: SpinResult
	for bet: int in bet_list:
		result = logic.resolve_stops(PackedInt32Array([0, 0, 0]), bet)
	return result


func _test_fever_bonus_average_bet() -> void:
	var logic: SlotLogic = _new_logic()
	var mixed: SpinResult = _cherry_fever_with(logic, [8, 8, 8, 8, 64])
	_check(mixed.fever_triggers == PackedStringArray([C]) and mixed.fever_bonuses[C] == 384, "베팅 8,8,8,8,64 → 보너스 = 20 × 평균 19.2 = 384 (발동 판 베팅 64 기준 1280이 아님)")
	var next: SpinResult = _cherry_fever_with(logic, [8, 8, 8, 8, 8])
	_check(next.fever_bonuses[C] == 160, "발동 뒤에는 베팅 합이 0부터 다시 쌓임 (8 × 5판 → 160)")
	var fixed: SpinResult = _cherry_fever_with(_new_logic(), [16, 16, 16, 16, 16])
	_check(fixed.fever_bonuses[C] == 320, "같은 베팅 16으로만 치면 기존과 같은 20 × 16 = 320")
	var floored: SpinResult = _cherry_fever_with(_new_logic(), [8, 8, 8, 8, 9])
	_check(floored.fever_bonuses[C] == 164, "베팅 합 41 → 20 × 41 ÷ 5 = 164 (소수점 버림)")
	var skipped: SpinResult = _cherry_fever_with(_new_logic(), [8, 8, 7, 8, 8, 8])
	_check(skipped.fever_bonuses[C] == 160, "BET 7 판은 카운터도 평균도 건드리지 않음 → 160")
	var lowered: SpinResult = _cherry_fever_with(_new_logic(), [64, 64, 64, 64, 8])
	_check(lowered.fever_bonuses[C] == 1056, "베팅 64,64,64,64,8 → 20 × 264 ÷ 5 = 1056 (낮춰 쳐도 손해 없음)")


func _test_fever_bonus_basis_setting() -> void:
	_check(BalanceData.from_dict(_test_dict()).fever_bonus_bet_basis == "average", "bonus_bet_basis가 없으면 기본값 average")
	var trigger_dict: Dictionary = _test_dict()
	trigger_dict["fever"]["bonus_bet_basis"] = "trigger"
	var trigger: SpinResult = _cherry_fever_with(SlotLogic.new(BalanceData.from_dict(trigger_dict), 1), [8, 8, 8, 8, 64])
	_check(trigger.fever_bonuses[C] == 1280, "trigger로 두면 발동한 판의 베팅 기준 (20 × 64 = 1280)")
	var bad_dict: Dictionary = _test_dict()
	bad_dict["fever"]["bonus_bet_basis"] = "아무거나"
	var bad: BalanceData = BalanceData.from_dict(bad_dict)
	_check(bad != null and bad.fever_bonus_bet_basis == "average" and bad.warnings.size() == 1, "허용하지 않는 값은 기본값 average로 대체하고 경고 1건")
	_check(BalanceData.from_dict(_test_dict()).warnings.is_empty(), "정상 데이터는 경고 없음")


## 손으로 검산하는 작은 데이터: 릴 3개 × 2칸(체리, 오렌지), 보이는 줄 1, 라인 1개 → 조합 8가지.
## 체리 3개 1가지(배당 4), 오렌지 3개 1가지(배당 8).
func _tiny_dict() -> Dictionary:
	return {
		"version": "tiny",
		"reel_count": 3,
		"visible_rows": 1,
		"symbols": [{ "id": C }, { "id": O }],
		"paytable": { C: 4, O: 8 },
		"reels": [[C, O], [C, O], [C, O]],
		"lines": [{ "id": "A", "type": "horizontal", "cells": [[0, 0], [1, 0], [2, 0]] }],
		"bet": { "max_total": 4 },
		"fever": {
			"min_total_bet": 1,
			"targets": [
				{ "symbol": C, "initial_count": 2, "bonus_multiplier": 3 },
				{ "symbol": O, "initial_count": 1, "bonus_multiplier": 0 },
			],
		},
		"pool": { "initial": 16, "contribution_rate": 0.5, "min_total_bet": 2, "award_on_fever": O },
	}


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _test_theory_hand_checked() -> void:
	var theory: BalanceTheory = BalanceTheory.new(BalanceData.from_dict(_tiny_dict()))
	var one: BalanceTheory.Report = theory.compute(1)
	_check(_near(one.line_rtp, 150.0), "이론값: 라인 RTP = (4 + 8) ÷ 8 = 150%")
	_check(_near(one.hit_rate, 25.0), "이론값: 히트 빈도 = 2 ÷ 8 = 25%")
	_check(_near(one.fever_intervals[C], 16.0) and _near(one.fever_rtps[C], 18.75), "이론값: 체리 피버 = 카운트 2 × 8스핀 = 16스핀에 1회, RTP 3 ÷ 16 = 18.75%")
	_check(_near(one.fever_interval, 16.0 / 3.0), "이론값: 피버 전체 간격 = 1 ÷ (1/16 + 1/8) = 5.33스핀")
	_check(_near(one.pool_interval, 0.0) and _near(one.pool_rtp, 0.0) and _near(one.rtp, 168.75), "이론값: BET 1은 풀 최소 베팅(2) 미만 → 풀 없음, RTP 168.75%")
	var two: BalanceTheory.Report = theory.compute(2)
	_check(_near(two.pool_interval, 8.0) and _near(two.pool_average, 24.0), "이론값: BET 2 풀 = 8스핀에 1회, 평균 16 + 0.5 × 2 × 8 = 24")
	_check(_near(two.pool_rtp, 150.0) and _near(two.rtp, 318.75), "이론값: BET 2 풀 RTP = 24 ÷ 16 = 150%, 합계 318.75%")


## 8라인 테스트 데이터(조합 1000가지)에서 SlotLogic으로 직접 센 값과 이론값이 같아야 한다.
func _test_theory_matches_logic() -> void:
	var data: BalanceData = BalanceData.from_dict(_test_dict())
	var theory: BalanceTheory = BalanceTheory.new(data)
	for bet: int in [3, FULL_BET, 11]:
		var counted: Vector2 = _count_with_logic(data, bet)
		var report: BalanceTheory.Report = theory.compute(bet)
		_check(_near(report.line_rtp, counted.x) and _near(report.hit_rate, counted.y), "이론값 = SlotLogic 전수 집계 (BET %d: 라인 RTP %.2f%%, 히트 %.2f%%)" % [bet, counted.x, counted.y])


## 모든 정지 조합을 SlotLogic 판정으로 직접 센다. x = 라인 RTP(%), y = 히트 빈도(%)
func _count_with_logic(data: BalanceData, bet: int) -> Vector2:
	var logic: SlotLogic = SlotLogic.new(data, 1)
	var line_bets: PackedInt32Array = logic.distribute_bet(bet)
	var size: int = data.reels[0].size()
	var payout: int = 0
	var hits: int = 0
	for index: int in size * size * size:
		@warning_ignore("integer_division")
		var stops: PackedInt32Array = PackedInt32Array([index % size, (index / size) % size, index / (size * size)])
		var wins: Array[LineWin] = logic.evaluate_lines(logic.build_grid(stops), line_bets)
		hits += 1 if not wins.is_empty() else 0
		for win: LineWin in wins:
			payout += win.payout
	var combos: float = float(size * size * size)
	return Vector2(100.0 * payout / (combos * bet), 100.0 * hits / combos)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		push_error("  [FAIL] " + label)


# ---------------------------------------------------------------- 8-B 테스트 모드용 입구

## spin(bet)과 spin(bet, 빈 목록)은 완전히 같고, 지정값이 있어도 RNG는 평소처럼 소비된다
func _test_forced_stops_keep_rng_sequence() -> void:
	var plain: SlotLogic = _new_logic()
	var explicit: SlotLogic = _new_logic()
	var same: bool = true
	for i: int in 300:
		var a: SpinResult = plain.spin(FULL_BET)
		var b: SpinResult = explicit.spin(FULL_BET, PackedInt32Array())
		same = same and a.stops == b.stops and a.line_payout == b.line_payout and a.fever_bonus == b.fever_bonus and a.pool_won == b.pool_won
	_check(same, "forced_stops를 비우거나 생략하면 같은 시드 결과가 300회 완전히 같음 (기존 동작 불변)")
	var base: SlotLogic = _new_logic()
	var forced: SlotLogic = _new_logic()
	var rolled: SpinResult = base.spin(FULL_BET)
	var shown: SpinResult = forced.spin(FULL_BET, PackedInt32Array([0, 0, 0]))
	_check(shown.stops == PackedInt32Array([0, 0, 0]) and rolled.stops.size() == 3, "지정한 정지 위치가 그 판의 결과가 됨")
	_check(shown.stops == PackedInt32Array([0, 0, 0]) and shown.line_payout == 80, "지정 판도 기존 규칙으로 계산 (체리 9칸 → 80)")
	var follows: bool = true
	for i: int in 100:
		follows = follows and base.spin(FULL_BET).stops == forced.spin(FULL_BET).stops
	_check(follows, "강제 판 뒤의 시드 순서가 변하지 않음 (다음 100판이 강제하지 않은 경우와 같은 정지 위치)")
	var bad_size: SlotLogic = _new_logic()
	var bad_range: SlotLogic = _new_logic()
	var negative: SlotLogic = _new_logic()
	var reference: SlotLogic = _new_logic()
	var expected: PackedInt32Array = reference.spin(FULL_BET).stops
	_check(bad_size.spin(FULL_BET, PackedInt32Array([0, 0])).stops == expected, "개수가 맞지 않는 지정값은 무시")
	_check(bad_range.spin(FULL_BET, PackedInt32Array([0, 99, 0])).stops == expected, "범위 밖 지정값은 무시")
	_check(negative.spin(FULL_BET, PackedInt32Array([-1, 0, 0])).stops == expected, "음수 지정값은 무시")


func _test_set_fever_count() -> void:
	var logic: SlotLogic = _new_logic()
	_check(logic.set_fever_count(C, 1, FULL_BET) and logic.get_fever_counts()[C] == 1, "체리 카운터를 1로 설정")
	var all_cherry: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var result: SpinResult = logic.resolve_stops(all_cherry, FULL_BET)
	_check(result.fever_triggers == PackedStringArray([C]), "설정 뒤 첫 체리 당첨에서 기존 규칙대로 체리 피버 발동")
	_check(result.fever_bonuses[C] == 160, "피버 보너스 = 20 × 8 (평균 베팅 합을 (초기-설정) × 기준 베팅으로 채움)")
	_check(logic.get_fever_counts()[C] == 5, "발동 뒤 카운터 초기값으로 복귀")
	var other: SlotLogic = _new_logic()
	other.set_fever_count(C, 3, 16)
	var after: SpinResult = other.resolve_stops(all_cherry, 16)
	_check(other.get_fever_counts()[C] == 2 and after.fever_triggers.is_empty(), "카운터 3으로 설정하면 한 번 당첨 뒤 2 (발동 안 함)")
	var guard: SlotLogic = _new_logic()
	_check(not guard.set_fever_count("BELL", 1, FULL_BET) and not guard.set_fever_count(C, 0, FULL_BET) and not guard.set_fever_count(C, 6, FULL_BET) and not guard.set_fever_count(C, 1, 0), "모르는 심볼·0·초기값 초과·기준 베팅 0은 거절")
	_check(guard.get_fever_counts()[C] == 5 and guard.get_fever_counts()[G] == 2, "거절하면 카운터 그대로")
	_check(guard.set_fever_count(S, 1, FULL_BET) and guard.get_fever_counts()[S] == 1, "초기 카운트가 1인 세븐은 1 그대로 허용")


func _test_set_pool() -> void:
	var logic: SlotLogic = _new_logic()
	_check(logic.set_pool(1234) and logic.get_pool() == 1234, "풀 금액 설정")
	logic.resolve_stops(PackedInt32Array([6, 7, 6]), FULL_BET)
	_check(logic.get_pool() == 1234, "설정 뒤 적립은 기존 규칙 (+0.4 → 표시 1234)")
	for i: int in 2:
		logic.resolve_stops(PackedInt32Array([6, 7, 6]), FULL_BET)
	_check(logic.get_pool() == 1235, "적립이 계속 쌓여 1235.2 → 표시 1235")
	var win: SpinResult = logic.resolve_stops(PackedInt32Array([3, 3, 3]), FULL_BET)
	_check(win.pool_won == 1235 and logic.get_pool() == 500, "세븐 피버로 설정한 풀을 기존 규칙대로 획득, 풀은 초기값 500으로")
	_check(not logic.set_pool(-1) and logic.get_pool() == 500, "음수 풀은 거절")
	_check(logic.set_pool(0) and logic.get_pool() == 0, "0은 허용")


func _test_find_stops_with_win() -> void:
	var logic: SlotLogic = _new_logic()
	var full_bets: PackedInt32Array = logic.distribute_bet(FULL_BET)
	var counts_before: Dictionary[String, int] = logic.get_fever_counts()
	var pool_before: int = logic.get_pool()
	var all_ok: bool = true
	for symbol: String in [C, G, S]:
		var stops: PackedInt32Array = logic.find_stops_with_win(symbol, full_bets)
		var found: bool = false
		if stops.size() == 3:
			for win: LineWin in logic.evaluate_lines(logic.build_grid(stops), full_bets):
				found = found or win.symbol == symbol
		all_ok = all_ok and found
	_check(all_ok, "체리·포도·세븐: 찾은 정지 위치에서 그 심볼의 라인 당첨이 실제로 나옴")
	_check(logic.find_stops_with_win(C, full_bets) == PackedInt32Array([0, 0, 0]), "가장 앞선 조합을 돌려줌 (체리: 0,0,0)")
	_check(logic.find_stops_with_win("BELL", full_bets).is_empty(), "스트립에 없는 심볼은 빈 목록")
	var line_a_only: PackedInt32Array = logic.distribute_bet(1)
	var one_line: PackedInt32Array = logic.find_stops_with_win(S, line_a_only)
	var line_a_win: bool = false
	if one_line.size() == 3:
		for win: LineWin in logic.evaluate_lines(logic.build_grid(one_line), line_a_only):
			line_a_win = line_a_win or win.symbol == S
	_check(line_a_win, "베팅 1(라인 A만)에서도 그 라인의 당첨으로 찾음")
	_check(logic.get_fever_counts().hash() == counts_before.hash() and logic.get_pool() == pool_before, "찾기만 하면 카운터·풀이 변하지 않음")
	var fresh: SlotLogic = _new_logic()
	_check(logic.spin(FULL_BET).stops == fresh.spin(FULL_BET).stops, "찾기는 RNG를 쓰지 않음 (다음 스핀이 새 로직과 같음)")

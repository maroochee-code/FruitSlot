class_name SlotLogic
extends RefCounted
## 슬롯 핵심 로직. 화면과 무관하며 단독으로 테스트할 수 있다.
## 결과는 spin()에서 한 번에 확정되고, 이후 연출은 결과를 바꾸지 못한다.

## 스핀 결과가 확정될 때 알린다 (화면 연결용)
signal spin_resolved(result: SpinResult)

## 풀의 소수점(예: 8 × 5% = 0.4)을 보존하기 위한 내부 정밀도. 밸런스 수치가 아님.
const POOL_SCALE: int = 10000

var _data: BalanceData
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _fever_counts: Dictionary[String, int] = {}
## 심볼별로, 이번 카운터를 줄인 판들의 총 베팅 합 (평균 베팅 방식 보너스 계산용)
var _fever_bet_sums: Dictionary[String, int] = {}
## 풀 금액 × POOL_SCALE
var _pool_units: int = 0


func _init(data: BalanceData, rng_seed: int = 0) -> void:
	_data = data
	set_seed(rng_seed)
	reset_state()


func set_seed(rng_seed: int) -> void:
	_rng.seed = rng_seed


## 피버 카운터와 풀을 초기값으로 되돌린다.
func reset_state() -> void:
	_fever_counts.clear()
	_fever_bet_sums.clear()
	for symbol: String in _data.fever_symbols:
		_fever_counts[symbol] = _data.fever_initial_counts[symbol]
		_fever_bet_sums[symbol] = 0
	_pool_units = _data.pool_initial * POOL_SCALE


func get_data() -> BalanceData:
	return _data


func get_fever_counts() -> Dictionary[String, int]:
	return _fever_counts.duplicate()


## 화면 표시·지급용 풀 금액 (정수, 소수점 버림)
func get_pool() -> int:
	@warning_ignore("integer_division")
	return _pool_units / POOL_SCALE


func is_valid_bet(total_bet: int) -> bool:
	return total_bet >= 1 and total_bet <= _data.max_total_bet


## 총 베팅을 라인 순서(A→H)대로 1씩 나눈다. 예: 3 → [1,1,1,0,...], 16 → 모두 2
func distribute_bet(total_bet: int) -> PackedInt32Array:
	var count: int = _data.line_count()
	var bets: PackedInt32Array = PackedInt32Array()
	bets.resize(count)
	for i: int in count:
		@warning_ignore("integer_division")
		bets[i] = total_bet / count + (1 if i < total_bet % count else 0)
	return bets


## 스핀 1회. 정지 위치를 RNG로 정하고 모든 결과를 확정한다.
## forced_stops는 테스트 모드 전용 입구다 (비어 있으면 기존과 완전히 같다). 주어져도 roll_stops()는 평소처럼 먼저 불러
## RNG를 소비하고 그 결과만 지정값으로 바꿔치기하므로, 강제 판 뒤의 시드 순서는 변하지 않는다.
## 정지 위치 개수·범위가 맞지 않는 지정값은 무시한다.
func spin(total_bet: int, forced_stops: PackedInt32Array = PackedInt32Array()) -> SpinResult:
	if not is_valid_bet(total_bet):
		push_error("SlotLogic.spin: 잘못된 베팅 %d (1~%d)" % [total_bet, _data.max_total_bet])
		return null
	var stops: PackedInt32Array = roll_stops()
	if _is_valid_stops(forced_stops):
		stops = forced_stops
	var result: SpinResult = resolve_stops(stops, total_bet)
	spin_resolved.emit(result)
	return result


## 테스트 모드 전용: 피버 카운터를 count(1~초기 카운트)로 정한다. 평균 베팅 합은
## (초기 카운트 − count) × reference_bet으로 채워, 카운터를 그만큼 줄인 판들이 있었던 것처럼 보너스가 계산되게 한다.
## 알 수 없는 심볼·범위 밖이면 false. 이후 피버 발동은 기존 규칙(_apply_fever)을 그대로 탄다.
func set_fever_count(symbol: String, count: int, reference_bet: int) -> bool:
	if not _fever_counts.has(symbol):
		return false
	var initial: int = _data.fever_initial_counts[symbol]
	if count < 1 or count > initial or reference_bet < 1:
		return false
	_fever_counts[symbol] = count
	_fever_bet_sums[symbol] = (initial - count) * reference_bet
	return true


## 테스트 모드 전용: 풀 금액을 amount(0 이상)로 정한다. 이후 적립·획득은 기존 규칙을 그대로 탄다.
func set_pool(amount: int) -> bool:
	if amount < 0:
		return false
	_pool_units = amount * POOL_SCALE
	return true


## 테스트 모드 전용: 이 라인 베팅에서 symbol의 라인 당첨이 한 줄 이상 나오는 정지 위치를 찾는다 (가장 앞선 조합).
## 상태를 바꾸지 않고 RNG도 쓰지 않는다. 없으면 빈 목록.
func find_stops_with_win(symbol: String, line_bets: PackedInt32Array) -> PackedInt32Array:
	var reel_count: int = _data.reels.size()
	if reel_count != 3:
		return PackedInt32Array()
	for a: int in _data.reels[0].size():
		for b: int in _data.reels[1].size():
			for c: int in _data.reels[2].size():
				var stops: PackedInt32Array = PackedInt32Array([a, b, c])
				if _has_win_with(evaluate_lines(build_grid(stops), line_bets), symbol):
					return stops
	return PackedInt32Array()


func _is_valid_stops(stops: PackedInt32Array) -> bool:
	if stops.size() != _data.reels.size():
		return false
	for i: int in stops.size():
		if stops[i] < 0 or stops[i] >= _data.reels[i].size():
			return false
	return true


## 릴별 정지 위치를 추첨한다.
func roll_stops() -> PackedInt32Array:
	var stops: PackedInt32Array = PackedInt32Array()
	for strip: PackedStringArray in _data.reels:
		stops.append(_rng.randi_range(0, strip.size() - 1))
	return stops


## 주어진 정지 위치로 결과를 계산하고 피버·풀 상태를 갱신한다.
## spin() 내부와 테스트에서만 쓴다. 화면이 직접 호출하면 안 된다.
func resolve_stops(stops: PackedInt32Array, total_bet: int) -> SpinResult:
	var result: SpinResult = SpinResult.new()
	result.total_bet = total_bet
	result.stops = stops
	result.line_bets = distribute_bet(total_bet)
	result.grid = build_grid(stops)
	result.line_wins = evaluate_lines(result.grid, result.line_bets)
	for win: LineWin in result.line_wins:
		result.line_payout += win.payout
	_add_pool_contribution(total_bet)
	_apply_fever(result)
	result.fever_counts_after = get_fever_counts()
	result.pool_after = get_pool()
	return result


## 정지 위치로 3×3 판을 만든다. grid[열][행], 윗줄 = 정지 위치, 아래로 +1, +2 (끝에서 처음으로 이어짐)
func build_grid(stops: PackedInt32Array) -> Array[PackedStringArray]:
	var grid: Array[PackedStringArray] = []
	for reel_index: int in _data.reel_count:
		var strip: PackedStringArray = _data.reels[reel_index]
		var column: PackedStringArray = PackedStringArray()
		for row: int in _data.visible_rows:
			column.append(strip[(stops[reel_index] + row) % strip.size()])
		grid.append(column)
	return grid


## 활성 라인(베팅 1 이상)에서 같은 심볼이 모두 일치하면 당첨.
func evaluate_lines(grid: Array[PackedStringArray], line_bets: PackedInt32Array) -> Array[LineWin]:
	var wins: Array[LineWin] = []
	for i: int in _data.line_count():
		if line_bets[i] <= 0:
			continue
		var line: LineDef = _data.lines[i]
		var symbol: String = _matching_symbol(grid, line)
		if symbol.is_empty():
			continue
		var win: LineWin = LineWin.new()
		win.line_id = line.id
		win.line_type = line.type
		win.symbol = symbol
		win.line_bet = line_bets[i]
		win.multiplier = _data.paytable[symbol]
		win.payout = win.multiplier * win.line_bet
		wins.append(win)
	return wins


## 라인의 모든 칸이 같은 심볼이면 그 심볼, 아니면 빈 문자열.
func _matching_symbol(grid: Array[PackedStringArray], line: LineDef) -> String:
	var first: Vector2i = line.cells[0]
	var symbol: String = grid[first.x][first.y]
	for cell: Vector2i in line.cells:
		if grid[cell.x][cell.y] != symbol:
			return ""
	return symbol


func _add_pool_contribution(total_bet: int) -> void:
	_pool_units += roundi(total_bet * _data.pool_contribution_rate * POOL_SCALE)


## 피버 카운터 감소·발동, 그리고 풀 획득을 처리한다.
func _apply_fever(result: SpinResult) -> void:
	if result.total_bet < _data.fever_min_total_bet:
		return
	for symbol: String in _data.fever_symbols:
		if not _has_win_with(result.line_wins, symbol):
			continue
		result.fever_hits.append(symbol)
		_fever_counts[symbol] -= 1
		_fever_bet_sums[symbol] += result.total_bet
		if _fever_counts[symbol] > 0:
			continue
		_trigger_fever(result, symbol)


func _trigger_fever(result: SpinResult, symbol: String) -> void:
	result.fever_triggers.append(symbol)
	var bonus: int = _fever_bonus_amount(symbol, result.total_bet)
	result.fever_bonuses[symbol] = bonus
	result.fever_bonus += bonus
	_fever_counts[symbol] = _data.fever_initial_counts[symbol]
	_fever_bet_sums[symbol] = 0
	if symbol == _data.pool_award_on_fever and result.total_bet >= _data.pool_min_total_bet:
		result.pool_won += get_pool()
		_pool_units = _data.pool_initial * POOL_SCALE


## 피버 보너스 금액. average = 배수 × (카운터를 줄인 판들의 베팅 합 ÷ 초기 카운트), 소수점 버림.
## 같은 베팅으로만 쳤다면 trigger(배수 × 발동한 판의 베팅)와 금액이 같다.
func _fever_bonus_amount(symbol: String, trigger_bet: int) -> int:
	var multiplier: int = _data.fever_multipliers[symbol]
	if _data.fever_bonus_bet_basis == BalanceData.FEVER_BASIS_TRIGGER:
		return multiplier * trigger_bet
	@warning_ignore("integer_division")
	return multiplier * _fever_bet_sums[symbol] / _data.fever_initial_counts[symbol]


func _has_win_with(wins: Array[LineWin], symbol: String) -> bool:
	for win: LineWin in wins:
		if win.symbol == symbol:
			return true
	return false

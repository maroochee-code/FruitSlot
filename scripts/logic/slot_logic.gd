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
	for symbol: String in _data.fever_symbols:
		_fever_counts[symbol] = _data.fever_initial_counts[symbol]
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
func spin(total_bet: int) -> SpinResult:
	if not is_valid_bet(total_bet):
		push_error("SlotLogic.spin: 잘못된 베팅 %d (1~%d)" % [total_bet, _data.max_total_bet])
		return null
	var result: SpinResult = resolve_stops(roll_stops(), total_bet)
	spin_resolved.emit(result)
	return result


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
		if _fever_counts[symbol] > 0:
			continue
		_trigger_fever(result, symbol)


func _trigger_fever(result: SpinResult, symbol: String) -> void:
	result.fever_triggers.append(symbol)
	var bonus: int = _data.fever_multipliers[symbol] * result.total_bet
	result.fever_bonuses[symbol] = bonus
	result.fever_bonus += bonus
	_fever_counts[symbol] = _data.fever_initial_counts[symbol]
	if symbol == _data.pool_award_on_fever and result.total_bet >= _data.pool_min_total_bet:
		result.pool_won += get_pool()
		_pool_units = _data.pool_initial * POOL_SCALE


func _has_win_with(wins: Array[LineWin], symbol: String) -> bool:
	for win: LineWin in wins:
		if win.symbol == symbol:
			return true
	return false

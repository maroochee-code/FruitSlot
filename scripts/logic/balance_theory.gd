class_name BalanceTheory
extends RefCounted
## 이론값(전수 계산). 릴 정지 위치의 모든 조합을 하나씩 따져 RTP·히트 빈도·피버/풀 간격을 계산한다.
## 난수를 쓰지 않으므로 표본 오차가 없다. "같은 베팅으로 계속 친다"는 가정의 값이다.

const PERCENT: float = 100.0

## 한 가지 베팅에 대한 이론값
class Report:
	extends RefCounted
	var total_bet: int = 0
	## RTP(%) = 라인 + 피버 + 풀
	var rtp: float = 0.0
	var line_rtp: float = 0.0
	var fever_rtp: float = 0.0
	var pool_rtp: float = 0.0
	## 1개 라인 이상 당첨되는 스핀의 비율(%)
	var hit_rate: float = 0.0
	## 피버(전체) 평균 발동 간격(스핀). 0 = 발동 없음
	var fever_interval: float = 0.0
	## 심볼별 평균 발동 간격(스핀). 0 = 발동 없음
	var fever_intervals: Dictionary[String, float] = {}
	var fever_rtps: Dictionary[String, float] = {}
	## 풀 평균 획득 간격(스핀). 0 = 획득 없음
	var pool_interval: float = 0.0
	var pool_average: float = 0.0


## 활성 라인 수 하나에 대한 전수 집계 (베팅이 달라도 활성 라인이 같으면 다시 쓴다)
class Profile:
	extends RefCounted
	var combos: int = 0
	var hit_combos: int = 0
	## 라인별: 모든 조합에 걸친 당첨 배수의 합
	var line_multiplier_sums: PackedInt64Array = PackedInt64Array()
	## 심볼 번호별: 그 심볼로 1개 라인 이상 당첨되는 조합 수
	var symbol_hit_combos: PackedInt64Array = PackedInt64Array()


var _data: BalanceData
## 릴 스트립을 심볼 번호로 바꿔 둔 것
var _strips: Array[PackedInt32Array] = []
var _multipliers: PackedInt32Array = PackedInt32Array()
## 활성 라인 수 → 집계
var _profiles: Dictionary[int, Profile] = {}


func _init(data: BalanceData) -> void:
	_data = data
	for id: String in data.symbol_ids:
		_multipliers.append(data.paytable[id])
	for strip: PackedStringArray in data.reels:
		var indexed: PackedInt32Array = PackedInt32Array()
		for symbol: String in strip:
			indexed.append(data.symbol_ids.find(symbol))
		_strips.append(indexed)


## 총 베팅 하나의 이론값을 계산한다.
func compute(total_bet: int) -> Report:
	var line_bets: PackedInt32Array = _line_bets(total_bet)
	var profile: Profile = _profile_for(_active_lines(line_bets))
	var report: Report = Report.new()
	report.total_bet = total_bet
	var weighted: int = 0
	for i: int in line_bets.size():
		weighted += line_bets[i] * profile.line_multiplier_sums[i]
	report.line_rtp = PERCENT * weighted / (float(profile.combos) * total_bet)
	report.hit_rate = PERCENT * profile.hit_combos / profile.combos
	_fill_fever(report, profile)
	_fill_pool(report)
	report.rtp = report.line_rtp + report.fever_rtp + report.pool_rtp
	return report


## 라인 종류별(가로/세로/대각) 라인 RTP(%)
func line_type_rtps(total_bet: int) -> Dictionary[String, float]:
	var line_bets: PackedInt32Array = _line_bets(total_bet)
	var profile: Profile = _profile_for(_active_lines(line_bets))
	var out: Dictionary[String, float] = {}
	for line_type: String in LineDef.TYPES:
		out[line_type] = 0.0
	for i: int in line_bets.size():
		out[_data.lines[i].type] += PERCENT * line_bets[i] * profile.line_multiplier_sums[i] / (float(profile.combos) * total_bet)
	return out


## SlotLogic.distribute_bet와 같은 규칙 (라인 순서대로 1씩)
func _line_bets(total_bet: int) -> PackedInt32Array:
	var count: int = _data.line_count()
	var bets: PackedInt32Array = PackedInt32Array()
	bets.resize(count)
	for i: int in count:
		@warning_ignore("integer_division")
		bets[i] = total_bet / count + (1 if i < total_bet % count else 0)
	return bets


func _active_lines(line_bets: PackedInt32Array) -> int:
	var active: int = 0
	for bet: int in line_bets:
		if bet > 0:
			active += 1
	return active


func _fill_fever(report: Report, profile: Profile) -> void:
	if report.total_bet < _data.fever_min_total_bet:
		return
	var rate: float = 0.0
	for symbol: String in _data.fever_symbols:
		var hits: int = profile.symbol_hit_combos[_data.symbol_ids.find(symbol)]
		if hits == 0:
			report.fever_intervals[symbol] = 0.0
			report.fever_rtps[symbol] = 0.0
			continue
		var interval: float = float(_data.fever_initial_counts[symbol]) * profile.combos / hits
		report.fever_intervals[symbol] = interval
		report.fever_rtps[symbol] = PERCENT * _data.fever_multipliers[symbol] / interval
		report.fever_rtp += report.fever_rtps[symbol]
		rate += 1.0 / interval
	if rate > 0.0:
		report.fever_interval = 1.0 / rate


## 풀은 "지급 재원"이 아니라 표시용 누적값이라, 획득액이 그대로 RTP에 더해진다.
## 평균 획득액 = 초기값 + 적립률 × 베팅 × 획득 간격
func _fill_pool(report: Report) -> void:
	if report.total_bet < _data.pool_min_total_bet:
		return
	var interval: float = report.fever_intervals.get(_data.pool_award_on_fever, 0.0)
	if interval <= 0.0:
		return
	report.pool_interval = interval
	report.pool_average = _data.pool_initial + _data.pool_contribution_rate * report.total_bet * interval
	report.pool_rtp = PERCENT * report.pool_average / (interval * report.total_bet)


func _profile_for(active_lines: int) -> Profile:
	if not _profiles.has(active_lines):
		_profiles[active_lines] = _build_profile(active_lines)
	return _profiles[active_lines]


func _build_profile(active_lines: int) -> Profile:
	var profile: Profile = Profile.new()
	profile.line_multiplier_sums.resize(_data.line_count())
	profile.symbol_hit_combos.resize(_data.symbol_count())
	var stops: PackedInt32Array = PackedInt32Array()
	stops.resize(_strips.size())
	var more: bool = true
	while more:
		_add_combo(profile, stops, active_lines)
		more = _next_stops(stops)
	return profile


## 정지 조합 하나를 집계에 더한다.
func _add_combo(profile: Profile, stops: PackedInt32Array, active_lines: int) -> void:
	profile.combos += 1
	var won_mask: int = 0
	for i: int in active_lines:
		var symbol: int = _matching_symbol(stops, _data.lines[i])
		if symbol < 0:
			continue
		profile.line_multiplier_sums[i] += _multipliers[symbol]
		won_mask |= 1 << symbol
	if won_mask == 0:
		return
	profile.hit_combos += 1
	for symbol: int in _multipliers.size():
		if won_mask & (1 << symbol):
			profile.symbol_hit_combos[symbol] += 1


## 라인의 모든 칸이 같은 심볼이면 그 심볼 번호, 아니면 -1.
func _matching_symbol(stops: PackedInt32Array, line: LineDef) -> int:
	var symbol: int = _symbol_at(stops, line.cells[0])
	for cell: Vector2i in line.cells:
		if _symbol_at(stops, cell) != symbol:
			return -1
	return symbol


func _symbol_at(stops: PackedInt32Array, cell: Vector2i) -> int:
	var strip: PackedInt32Array = _strips[cell.x]
	return strip[(stops[cell.x] + cell.y) % strip.size()]


## 다음 정지 조합으로 넘긴다 (주행거리계처럼). 한 바퀴 다 돌았으면 false.
func _next_stops(stops: PackedInt32Array) -> bool:
	for reel: int in stops.size():
		stops[reel] += 1
		if stops[reel] < _strips[reel].size():
			return true
		stops[reel] = 0
	return false

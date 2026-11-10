class_name SimStats
extends RefCounted
## 시뮬레이션 통계를 모으고 보고서 문자열로 만든다.

const LINE_TYPES: PackedStringArray = LineDef.TYPES
const LINE_TYPE_NAMES: Dictionary[String, String] = {
	"horizontal": "가로", "vertical": "세로", "diagonal": "대각",
}

## 당첨 크기 구간의 아래 경계 (총 지급 ÷ 총 베팅 배수). 통계를 나눠 보는 눈금일 뿐 밸런스 수치가 아니다.
const SIZE_EDGES: PackedFloat32Array = [1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0]
const SIZE_NAMES: PackedStringArray = ["꽝", "1배 미만", "1~2배", "2~5배", "5~10배", "10~25배", "25~50배", "50~100배", "100배 이상"]
const SIZE_NONE: int = 0
const SIZE_UNDER_ONE: int = 1

var spins: int = 0
var total_bet: int = 0
var line_payout: int = 0
var fever_payout: int = 0
var pool_payout: int = 0
var hit_spins: int = 0
var max_win: int = 0
var symbol_wins: Dictionary[String, int] = {}
var symbol_payout: Dictionary[String, int] = {}
var type_wins: Dictionary[String, int] = {}
var type_payout: Dictionary[String, int] = {}
var fever_counts: Dictionary[String, int] = {}
var fever_bonus_by_symbol: Dictionary[String, int] = {}
var pool_awards: int = 0
## 당첨 크기 구간별 스핀 수와 지급액 (SIZE_NAMES 순서)
var size_spins: PackedInt64Array = PackedInt64Array()
var size_payout: PackedInt64Array = PackedInt64Array()

var _data: BalanceData


func _init(data: BalanceData) -> void:
	_data = data
	size_spins.resize(SIZE_NAMES.size())
	size_payout.resize(SIZE_NAMES.size())
	for id: String in data.symbol_ids:
		symbol_wins[id] = 0
		symbol_payout[id] = 0
	for line_type: String in LINE_TYPES:
		type_wins[line_type] = 0
		type_payout[line_type] = 0
	for symbol: String in data.fever_symbols:
		fever_counts[symbol] = 0
		fever_bonus_by_symbol[symbol] = 0


func record(result: SpinResult) -> void:
	spins += 1
	total_bet += result.total_bet
	line_payout += result.line_payout
	fever_payout += result.fever_bonus
	pool_payout += result.pool_won
	max_win = maxi(max_win, result.total_payout())
	if result.is_hit():
		hit_spins += 1
	for win: LineWin in result.line_wins:
		symbol_wins[win.symbol] += 1
		symbol_payout[win.symbol] += win.payout
		type_wins[win.line_type] += 1
		type_payout[win.line_type] += win.payout
	for symbol: String in result.fever_triggers:
		fever_counts[symbol] += 1
		fever_bonus_by_symbol[symbol] += result.fever_bonuses[symbol]
	if result.pool_won > 0:
		pool_awards += 1
	var bucket: int = size_bucket(result.total_payout(), result.total_bet)
	size_spins[bucket] += 1
	size_payout[bucket] += result.total_payout()


## 당첨 크기 구간 번호. 0 = 꽝, 1 = 1배 미만, 그 뒤는 SIZE_EDGES 순서.
static func size_bucket(payout: int, bet: int) -> int:
	if payout <= 0:
		return SIZE_NONE
	var bucket: int = SIZE_UNDER_ONE
	for i: int in SIZE_EDGES.size():
		if payout >= SIZE_EDGES[i] * bet:
			bucket = SIZE_UNDER_ONE + i + 1
	return bucket


func total_payout() -> int:
	return line_payout + fever_payout + pool_payout


func rtp() -> float:
	return _percent(total_payout(), total_bet)


func hit_rate() -> float:
	return _percent(hit_spins, spins)


## 피버(전체) 평균 발동 간격. 발동이 없으면 0.
func fever_interval() -> float:
	return 0.0 if total_fevers() == 0 else float(spins) / total_fevers()


## 풀 평균 획득 간격. 획득이 없으면 0.
func pool_interval() -> float:
	return 0.0 if pool_awards == 0 else float(spins) / pool_awards


func total_fevers() -> int:
	var sum: int = 0
	for symbol: String in fever_counts:
		sum += fever_counts[symbol]
	return sum


func build_report(header: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	out.append("==================== %s ====================" % header)
	out.append("총 스핀        : %d" % spins)
	out.append("총 베팅        : %d" % total_bet)
	out.append("총 지급        : %d" % total_payout())
	out.append("RTP            : %.2f%%" % rtp())
	out.append("  - 라인 당첨  : %.2f%%  (%d)" % [_percent(line_payout, total_bet), line_payout])
	out.append("  - 피버 보너스: %.2f%%  (%d)" % [_percent(fever_payout, total_bet), fever_payout])
	out.append("  - 풀         : %.2f%%  (%d)" % [_percent(pool_payout, total_bet), pool_payout])
	out.append("히트 빈도      : %.2f%%  (%d 스핀)" % [hit_rate(), hit_spins])
	out.append("최대 1회 지급  : %d" % max_win)
	out.append_array(_symbol_section())
	out.append_array(_type_section())
	out.append_array(_fever_section())
	out.append("[풀]")
	out.append("  획득 %d회, 평균 %s 스핀에 1회, 평균 획득액 %s" % [
		pool_awards, _interval(pool_awards), _average(pool_payout, pool_awards)])
	out.append_array(_size_section())
	return "\n".join(out)


func _size_section() -> PackedStringArray:
	var out: PackedStringArray = ["[당첨 크기 분포] 총 지급 ÷ 총 베팅"]
	for i: int in SIZE_NAMES.size():
		out.append("  %-9s : %8d 스핀 (%6.2f%%), RTP 비중 %6.2f%%" % [
			SIZE_NAMES[i], size_spins[i], _percent(size_spins[i], spins), _percent(size_payout[i], total_bet)])
	return out


func _symbol_section() -> PackedStringArray:
	var out: PackedStringArray = ["[심볼별 당첨 라인]"]
	for id: String in _data.symbol_ids:
		out.append("  %-7s 배당 %4d : %7d 라인, 지급 %9d (RTP %6.2f%%)" % [
			id, _data.paytable[id], symbol_wins[id], symbol_payout[id], _percent(symbol_payout[id], total_bet)])
	return out


func _type_section() -> PackedStringArray:
	var out: PackedStringArray = ["[라인 종류별 당첨]"]
	for line_type: String in LINE_TYPES:
		out.append("  %s : %7d 라인, 지급 %9d (RTP %6.2f%%)" % [
			LINE_TYPE_NAMES[line_type], type_wins[line_type], type_payout[line_type],
			_percent(type_payout[line_type], total_bet)])
	return out


func _fever_section() -> PackedStringArray:
	var out: PackedStringArray = ["[피버] 총 %d회, 평균 %s 스핀에 1회" % [total_fevers(), _interval(total_fevers())]]
	for symbol: String in _data.fever_symbols:
		out.append("  %-7s : %6d회, 평균 %8s 스핀에 1회, 보너스 %9d (RTP %6.2f%%)" % [
			symbol, fever_counts[symbol], _interval(fever_counts[symbol]),
			fever_bonus_by_symbol[symbol], _percent(fever_bonus_by_symbol[symbol], total_bet)])
	return out


func _interval(count: int) -> String:
	return "-" if count == 0 else "%.1f" % (float(spins) / count)


func _average(amount: int, count: int) -> String:
	return "-" if count == 0 else "%.1f" % (float(amount) / count)


static func _percent(part: int, whole: int) -> float:
	return 0.0 if whole == 0 else 100.0 * part / whole

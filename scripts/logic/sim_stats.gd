class_name SimStats
extends RefCounted
## 시뮬레이션 통계를 모으고 보고서 문자열로 만든다.

const LINE_TYPES: PackedStringArray = LineDef.TYPES
const LINE_TYPE_NAMES: Dictionary[String, String] = {
	"horizontal": "가로", "vertical": "세로", "diagonal": "대각",
}

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

var _data: BalanceData


func _init(data: BalanceData) -> void:
	_data = data
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


func total_payout() -> int:
	return line_payout + fever_payout + pool_payout


func rtp() -> float:
	return _percent(total_payout(), total_bet)


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
	out.append("히트 빈도      : %.2f%%  (%d 스핀)" % [_percent(hit_spins, spins), hit_spins])
	out.append("최대 1회 지급  : %d" % max_win)
	out.append_array(_symbol_section())
	out.append_array(_type_section())
	out.append_array(_fever_section())
	out.append("[풀]")
	out.append("  획득 %d회, 평균 %s 스핀에 1회, 평균 획득액 %s" % [
		pool_awards, _interval(pool_awards), _average(pool_payout, pool_awards)])
	return "\n".join(out)


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

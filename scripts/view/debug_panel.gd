class_name DebugPanel
extends PanelContainer
## 로직 결과를 글자로 보여주는 디버그 창. F1로 켜고 끈다.

const FONT_SIZE: int = 10
const BG_COLOR: Color = Color(0, 0, 0, 0.82)
const TEXT_COLOR: Color = Color("C8FFC8")

var _label: Label = Label.new()


func _init() -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = BG_COLOR
	add_theme_stylebox_override("panel", box)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_label)
	_label.text = "[디버그] START 또는 스페이스로 스핀\nF1: 이 창 켜기/끄기"


func show_result(result: SpinResult, data: BalanceData, grid_matches: bool) -> void:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("== 스핀 결과 (BET %d) ==" % result.total_bet)
	rows.append("정지 위치: %s" % _join_ints(result.stops))
	rows.append("화면=로직: %s" % ("일치 OK" if grid_matches else "불일치!! 확인 필요"))
	rows.append("격자(릴별 위→아래)")
	for col: int in result.grid.size():
		rows.append("  릴%d: %s" % [col + 1, " / ".join(result.grid[col])])
	rows.append("-- 당첨 라인 %d개 --" % result.line_wins.size())
	for win: LineWin in result.line_wins:
		rows.append("  %s(%s) %s %d×%d=%d" % [win.line_id, win.line_type, win.symbol, win.line_bet, win.multiplier, win.payout])
	rows.append("라인 합계: %d" % result.line_payout)
	rows.append("피버 적중: %s" % _join_strings(result.fever_hits))
	rows.append("피버 발동: %s (+%d)" % [_join_strings(result.fever_triggers), result.fever_bonus])
	rows.append("풀 지급: %d" % result.pool_won)
	rows.append("총 당첨금: %d" % result.total_payout())
	rows.append("-- 스핀 후 상태 --")
	for symbol: String in data.fever_symbols:
		rows.append("  피버 %s 남음 %d" % [symbol, result.fever_counts_after.get(symbol, -1)])
	rows.append("  POOL %d" % result.pool_after)
	_label.text = "\n".join(rows)


func _join_ints(values: PackedInt32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value: int in values:
		parts.append(str(value))
	return ", ".join(parts)


func _join_strings(values: PackedStringArray) -> String:
	return "없음" if values.is_empty() else ", ".join(values)

class_name DebugPanel
extends PanelContainer
## 로직 결과를 글자로 보여주는 디버그 창. F1로 켜고 끈다. (기본 꺼짐)

const BG_COLOR: Color = Color(0, 0, 0, 0.88)
const TEXT_COLOR: Color = Color("C8FFC8")

var _label: Label = Label.new()
## 지금 글자가 도움말인가 (스핀 결과가 표시되면 false)
var _showing_help: bool = true


func _init() -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = BG_COLOR
	add_theme_stylebox_override("panel", box)
	UiFont.apply(_label, UiFont.Face.SMALL)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	# 오른쪽 끝에서 잘리지 않도록 줄바꿈을 켠다.
	_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	add_child(_label)
	refresh_help(true)


## 처음 도움말. COIN을 쓸 수 있을 때만 COIN 키(C)를 안내한다 (coin_allowed 기준).
func refresh_help(coin_allowed: bool) -> void:
	# 스핀 결과가 표시된 뒤에는 결과 글자를 지우지 않는다
	if not _showing_help:
		return
	if coin_allowed:
		_label.text = "[디버그] F1: 이 창 켜기/끄기\nC=COIN B=BET 스페이스/엔터=START"
	else:
		_label.text = "[디버그] F1: 이 창 켜기/끄기\nB=BET 스페이스/엔터=START (COIN 사용 불가)"


## 지금 도움말 글자 (테스트용)
func help_text() -> String:
	return _label.text


func show_result(result: SpinResult, data: BalanceData, grid_matches: bool, credit_after: int) -> void:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("== 스핀 결과 (BET %d) / 크레딧 %d ==" % [result.total_bet, credit_after])
	rows.append("라인별 베팅: %s" % _join_ints(result.line_bets))
	rows.append("정지 위치: %s" % _join_ints(result.stops))
	rows.append("화면=로직: %s" % ("일치 OK" if grid_matches else "불일치!! 확인 필요"))
	for col: int in result.grid.size():
		rows.append("릴%d(위→아래): %s" % [col + 1, " / ".join(result.grid[col])])
	rows.append("-- 당첨 라인 %d개 --" % result.line_wins.size())
	for win: LineWin in result.line_wins:
		rows.append("%s %s %d×%d=%d" % [win.line_id, win.symbol, win.line_bet, win.multiplier, win.payout])
	rows.append("라인 %d + 피버 %d + 풀 %d = %d" % [result.line_payout, result.fever_bonus, result.pool_won, result.total_payout()])
	rows.append("피버 적중: %s / 발동: %s" % [_join_strings(result.fever_hits), _join_strings(result.fever_triggers)])
	var counts: PackedStringArray = PackedStringArray()
	for symbol: String in data.fever_symbols:
		counts.append("%s %d" % [symbol, result.fever_counts_after.get(symbol, -1)])
	rows.append("피버 남음: %s" % ", ".join(counts))
	rows.append("POOL %d" % result.pool_after)
	_showing_help = false
	_label.text = "\n".join(rows)


func _join_ints(values: PackedInt32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value: int in values:
		parts.append(str(value))
	return ", ".join(parts)


func _join_strings(values: PackedStringArray) -> String:
	return "없음" if values.is_empty() else ", ".join(values)

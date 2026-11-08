class_name FeverPanel
extends Panel
## 피버 카운터 패널: 대상 심볼마다 한 줄(색 박스 + 이름 + ×남은 횟수).
## 숫자는 balance.json(BalanceData)에서만 읽는다. 초기값이 2 이상인 심볼이 마지막 1회만 남으면 그 줄이 깜빡인다.
## (초기값이 처음부터 1인 심볼은 항상 1이라 깜빡이지 않는다.)

const TITLE_TEXT: String = "피버 카운터"
const BG_COLOR: Color = Color("1A1A22")
const BORDER_COLOR: Color = Color("3A3A48")
const TITLE_COLOR: Color = Color("8A8AA0")
const NAME_COLOR: Color = Color("D8D8E4")
const COUNT_COLOR: Color = Color("F2F2F2")
## 깜빡임 "켜짐" 때의 글자 색 (꺼짐일 때는 위의 평소 색)
const LAST_ONE_COLOR: Color = Color("FF5050")
const TITLE_FONT_SIZE: int = 10
const ROW_FONT_SIZE: int = 14
const PAD: float = 6.0
const TITLE_HEIGHT: float = 16.0
const NAME_WIDTH: float = 52.0
const MINI_SIZE: Vector2 = Vector2(14, 14)
const MINI_BORDER: int = 1
const MINI_GAP: float = 6.0

var _data: BalanceData
var _name_labels: Dictionary[String, Label] = {}
var _count_labels: Dictionary[String, Label] = {}
var _counts: Dictionary[String, int] = {}
var _blink_on: bool = false


func _init(box_name: String, rect: Rect2) -> void:
	name = box_name
	position = rect.position
	size = rect.size
	clip_contents = true
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = BG_COLOR
	box.border_color = BORDER_COLOR
	box.set_border_width_all(1)
	add_theme_stylebox_override("panel", box)


## 피버 대상 심볼(balance.json의 fever.targets 순서)대로 한 줄씩 만든다.
func setup(data: BalanceData) -> void:
	_data = data
	var title: Label = Label.new()
	title.text = TITLE_TEXT
	title.position = Vector2(PAD, 1.0)
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	add_child(title)
	var rows: int = data.fever_symbols.size()
	var row_height: float = (size.y - TITLE_HEIGHT) / maxf(1.0, rows)
	for i: int in rows:
		_add_row(data.fever_symbols[i], Vector2(PAD, TITLE_HEIGHT + i * row_height), row_height)


## 스핀 결과의 카운터 스냅샷으로 숫자를 바꾼다.
func set_counts(counts: Dictionary[String, int]) -> void:
	for symbol: String in _data.fever_symbols:
		_counts[symbol] = counts[symbol]
		_count_labels[symbol].text = "×%d" % counts[symbol]
	_apply_blink()


## 깜빡임 켜짐/꺼짐. 시간 계산은 main이 하고 이 패널은 상태만 받는다 (테스트가 시간을 직접 정할 수 있게).
func set_blink(on: bool) -> void:
	if on == _blink_on:
		return
	_blink_on = on
	_apply_blink()


## 이 심볼이 "마지막 1회 남음" 상태인가 (초기값 2 이상 + 남은 1)
func is_last_one(symbol: String) -> bool:
	return _data.fever_initial_counts[symbol] >= 2 and _counts.get(symbol, 0) == 1


## 이 심볼의 줄이 지금 깜빡임 "켜짐" 색으로 보이는가
func is_flashing(symbol: String) -> bool:
	return is_last_one(symbol) and _blink_on


## 기존 형식 그대로의 텍스트 ("체리 ×20" 줄바꿈 목록). 테스트·디버그용
func value_text() -> String:
	var rows: PackedStringArray = PackedStringArray()
	for symbol: String in _data.fever_symbols:
		rows.append("%s %s" % [_name_labels[symbol].text, _count_labels[symbol].text])
	return "\n".join(rows)


## 이 심볼 줄의 숫자(×N) 글자 색 (테스트용)
func count_color(symbol: String) -> Color:
	return _count_labels[symbol].get_theme_color("font_color")


func row_count() -> int:
	return _count_labels.size()


func _apply_blink() -> void:
	for symbol: String in _data.fever_symbols:
		var color_name: Color = NAME_COLOR
		var color_count: Color = COUNT_COLOR
		if is_flashing(symbol):
			color_name = LAST_ONE_COLOR
			color_count = LAST_ONE_COLOR
		_name_labels[symbol].add_theme_color_override("font_color", color_name)
		_count_labels[symbol].add_theme_color_override("font_color", color_count)


func _add_row(symbol: String, top_left: Vector2, row_height: float) -> void:
	var mini_y: float = top_left.y + (row_height - MINI_SIZE.y) / 2.0
	add_child(_make_mini_box(symbol, Vector2(top_left.x, mini_y)))
	var name_x: float = top_left.x + MINI_SIZE.x + MINI_GAP
	var name_label: Label = _make_label(_data.symbol_names.get(symbol, symbol), NAME_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.position = Vector2(name_x, top_left.y)
	name_label.size = Vector2(NAME_WIDTH, row_height)
	add_child(name_label)
	var count_x: float = name_x + NAME_WIDTH
	var count_label: Label = _make_label("×%d" % _data.fever_initial_counts[symbol], COUNT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	count_label.position = Vector2(count_x, top_left.y)
	count_label.size = Vector2(size.x - PAD - count_x, row_height)
	add_child(count_label)
	_name_labels[symbol] = name_label
	_count_labels[symbol] = count_label
	_counts[symbol] = _data.fever_initial_counts[symbol]


## 화면의 칸과 같은 색의 작은 박스
func _make_mini_box(symbol: String, pos: Vector2) -> Panel:
	var style: Dictionary = SymbolStyle.get_style(symbol)
	var mini_box: Panel = Panel.new()
	mini_box.position = pos
	mini_box.size = MINI_SIZE
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = style["bg"]
	box.border_color = style["border"]
	box.set_border_width_all(MINI_BORDER)
	mini_box.add_theme_stylebox_override("panel", box)
	return mini_box


func _make_label(text: String, color: Color, align: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label

class_name PaytablePanel
extends Panel
## 배당표(족보): 심볼 3개 일치 → 배수. 숫자는 balance.json(BalanceData.paytable)에서 읽는다.
## 배수는 "그 라인의 베팅"에 곱해지므로 제목에 그 사실을 적는다.

const TITLE_TEXT: String = "배당표 (3개 일치 × 라인 베팅)"
const BG_COLOR: Color = Color("1A1A22")
const BORDER_COLOR: Color = Color("3A3A48")
const TITLE_COLOR: Color = Color("8A8AA0")
const NAME_COLOR: Color = Color("D8D8E4")
const MULT_COLOR: Color = Color("FFD700")
const TITLE_FONT_SIZE: int = 10
const ROW_FONT_SIZE: int = 12
const PAD: float = 6.0
const TITLE_HEIGHT: float = 16.0
const NAME_WIDTH: float = 44.0
const MINI_SIZE: Vector2 = Vector2(14, 14)
const MINI_GAP: float = 2.0
const MINI_BORDER: int = 1

var _multiplier_labels: Dictionary[String, Label] = {}


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


## 심볼 순서(balance.json의 symbols 순서)대로 한 줄씩 만든다.
func setup(data: BalanceData) -> void:
	var title: Label = Label.new()
	title.text = TITLE_TEXT
	title.position = Vector2(PAD, 1.0)
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	add_child(title)
	var row_height: float = (size.y - TITLE_HEIGHT) / maxf(1.0, data.symbol_count())
	for i: int in data.symbol_count():
		var symbol: String = data.symbol_ids[i]
		_add_row(symbol, data, Vector2(PAD, TITLE_HEIGHT + i * row_height), row_height)


func multiplier_text(symbol_id: String) -> String:
	return _multiplier_labels[symbol_id].text


func row_count() -> int:
	return _multiplier_labels.size()


func _add_row(symbol: String, data: BalanceData, top_left: Vector2, row_height: float) -> void:
	var name_label: Label = _make_label(data.symbol_names.get(symbol, symbol), NAME_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.position = top_left
	name_label.size = Vector2(NAME_WIDTH, row_height)
	add_child(name_label)
	var mini_y: float = top_left.y + (row_height - MINI_SIZE.y) / 2.0
	var mini_x: float = top_left.x + NAME_WIDTH
	for n: int in data.reel_count:
		add_child(_make_mini_box(symbol, Vector2(mini_x + n * (MINI_SIZE.x + MINI_GAP), mini_y)))
	var mult_x: float = mini_x + data.reel_count * (MINI_SIZE.x + MINI_GAP) + MINI_GAP
	var mult_label: Label = _make_label("×%d" % data.paytable[symbol], MULT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	mult_label.position = Vector2(mult_x, top_left.y)
	mult_label.size = Vector2(size.x - PAD - mult_x, row_height)
	add_child(mult_label)
	_multiplier_labels[symbol] = mult_label


## 화면의 칸과 같은 색의 작은 박스
func _make_mini_box(symbol: String, pos: Vector2) -> Panel:
	var style: Dictionary = SymbolStyle.get_style(symbol)
	var mini: Panel = Panel.new()
	mini.position = pos
	mini.size = MINI_SIZE
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = style["bg"]
	box.border_color = style["border"]
	box.set_border_width_all(MINI_BORDER)
	mini.add_theme_stylebox_override("panel", box)
	return mini


func _make_label(text: String, color: Color, align: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label

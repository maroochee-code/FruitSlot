class_name PaytablePanel
extends Panel
## 배당표(족보): 심볼 3개 일치 → 배수. 숫자는 balance.json(BalanceData.paytable)에서 읽는다.
## 배수는 "그 라인의 베팅"에 곱해지므로 제목에 그 사실을 적는다.
## 2열 격자: 줄마다 작은 아이콘(아트 ×2) + 배수(오른쪽 정렬), 사이에 어두운 구분선(아트 1px).

const TITLE_TEXT: String = "배당표 (라인 베팅 ×)"
const TITLE_COLOR: Color = UiSkin.LABEL_TEXT_COLOR
const MULT_COLOR: Color = Color("ffe14d")
const DIVIDER_COLOR: Color = Color("0e1130")
## 아이콘은 줄 높이(28)에 맞추려고 아트 ×2 (아이콘 12×10 → 24×20)
const ICON_SCALE: int = 2
## 열 배치 (화면 설정). 여기 없는 심볼은 마지막 열 끝에 붙는다.
const COLUMN_LAYOUT: Array = [
	["CHERRY", "MELON", "BELL", "BAR"],
	["ORANGE", "GRAPE", "SEVEN"],
]
## 패널 모서리(9-slice 6px) 안쪽 여백
const PAD: float = 6.0
const TITLE_X: float = 9.0
const TITLE_HEIGHT: float = 14.0
## 구분선 두께 = 아트 1px
const DIVIDER_WIDTH: float = 3.0
const ICON_LEFT_PAD: float = 3.0
const MULT_RIGHT_PAD: float = 3.0
const MAX_ICON_WIDTH: float = 30.0

var _multiplier_labels: Dictionary[String, Label] = {}
var _icons: Dictionary[String, TextureRect] = {}


func _init(box_name: String, rect: Rect2) -> void:
	name = box_name
	position = rect.position
	size = rect.size
	clip_contents = true
	add_theme_stylebox_override("panel", UiSkin.panel_box())


## 열 배치(COLUMN_LAYOUT)대로 줄을 만든다. 배당표에 없는 심볼은 무시하고, 배치에 없는 심볼은 마지막 열에 붙인다.
func setup(data: BalanceData) -> void:
	var title: Label = Label.new()
	title.name = "Title"
	title.text = TITLE_TEXT
	title.position = Vector2(TITLE_X, PAD)
	UiFont.apply(title, UiFont.Face.SMALL)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	add_child(title)
	var columns: Array[PackedStringArray] = _build_columns(data)
	var grid_top: float = PAD + TITLE_HEIGHT
	var column_width: float = (size.x - PAD * 2.0) / columns.size()
	var row_count_max: int = 0
	for column: PackedStringArray in columns:
		row_count_max = maxi(row_count_max, column.size())
	var row_height: float = (size.y - PAD - grid_top) / maxf(1.0, row_count_max)
	for c: int in columns.size():
		var column_x: float = PAD + c * column_width
		for r: int in columns[c].size():
			_add_row(columns[c][r], data, Rect2(column_x, grid_top + r * row_height, column_width, row_height))
			if r > 0:
				_add_divider(Rect2(column_x, grid_top + r * row_height - DIVIDER_WIDTH / 2.0, column_width, DIVIDER_WIDTH))
		if c > 0:
			_add_divider(Rect2(column_x - DIVIDER_WIDTH / 2.0, grid_top, DIVIDER_WIDTH, row_height * row_count_max))


func multiplier_text(symbol_id: String) -> String:
	return _multiplier_labels[symbol_id].text


func row_count() -> int:
	return _multiplier_labels.size()


## 이 심볼의 아이콘과 배수 글자 (테스트용)
func icon_of(symbol_id: String) -> TextureRect:
	return _icons[symbol_id]


func multiplier_label_of(symbol_id: String) -> Label:
	return _multiplier_labels[symbol_id]


func _build_columns(data: BalanceData) -> Array[PackedStringArray]:
	var columns: Array[PackedStringArray] = []
	var placed: Dictionary[String, bool] = {}
	for layout_column: Array in COLUMN_LAYOUT:
		var column: PackedStringArray = PackedStringArray()
		for symbol: String in layout_column:
			if data.paytable.has(symbol):
				column.append(symbol)
				placed[symbol] = true
		columns.append(column)
	for symbol: String in data.symbol_ids:
		if not placed.has(symbol):
			columns[-1].append(symbol)
	return columns


func _add_row(symbol: String, data: BalanceData, cell: Rect2) -> void:
	var icon: TextureRect = _make_icon(symbol)
	icon.position = cell.position + Vector2(ICON_LEFT_PAD, (cell.size.y - icon.size.y) / 2.0)
	add_child(icon)
	var mult_x: float = ICON_LEFT_PAD + MAX_ICON_WIDTH
	var mult_label: Label = Label.new()
	mult_label.name = "Mult_%s" % symbol
	mult_label.text = "×%d" % data.paytable[symbol]
	mult_label.position = cell.position + Vector2(mult_x, 0.0)
	mult_label.size = Vector2(cell.size.x - mult_x - MULT_RIGHT_PAD, cell.size.y)
	mult_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mult_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiFont.apply(mult_label, UiFont.Face.BODY)
	mult_label.add_theme_color_override("font_color", MULT_COLOR)
	add_child(mult_label)
	_icons[symbol] = icon
	_multiplier_labels[symbol] = mult_label


func _add_divider(rect: Rect2) -> void:
	var line: ColorRect = ColorRect.new()
	line.name = "Divider"
	line.color = DIVIDER_COLOR
	line.position = rect.position
	line.size = rect.size
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)


func _make_icon(symbol: String) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon_%s" % symbol
	icon.texture = SymbolStyle.load_small_icon(symbol)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon.texture != null:
		icon.size = icon.texture.get_size() * ICON_SCALE
	return icon

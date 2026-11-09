class_name FeverPanel
extends Panel
## 피버 카운터 패널: 대상 심볼마다 한 행 (작은 아이콘 ×2 왼쪽 + "×남은 횟수" 오른쪽 고정 열). 4행 1열.
## 숫자는 balance.json(BalanceData)에서만 읽는다. 초기값이 2 이상인 심볼이 마지막 1회만 남으면 그 줄이 깜빡인다.
## (초기값이 처음부터 1인 심볼은 항상 1이라 깜빡이지 않는다.)

const TITLE_TEXT: String = "피버 카운터"
const TITLE_COLOR: Color = UiSkin.LABEL_TEXT_COLOR
const COUNT_COLOR: Color = Color("ffffff")
## 심볼별 평소 숫자 색 (여기 없는 심볼은 COUNT_COLOR). 세븐은 빨간색.
const COUNT_COLORS: Dictionary = {
	"SEVEN": Color("e8283c"),
}
## 깜빡임 "켜짐" 때의 글자 색 (꺼짐일 때는 평소 색)
const LAST_ONE_COLOR: Color = Color("FF5050")
## 개수 글자: 갈무리9(10px) ×2 = 20px. 아이콘 높이(10×2 = 20)와 맞춘다.
const COUNT_FONT_MULTIPLE: int = 2
const ICON_SCALE: int = 2
## 한 행 높이. 제목(14) + 4행(104) + 위아래 여백(12)이 패널 높이 132 안에 들어간다.
const ROW_HEIGHT: float = 26.0
const ICON_LEFT_PAD: float = 3.0
## 아이콘이 차지할 수 있는 최대 폭 (피버 대상 아이콘은 모두 12×10 → 24)
const MAX_ICON_WIDTH: float = 24.0
const COUNT_RIGHT_PAD: float = 3.0
## 패널 모서리(9-slice 6px) 안쪽 여백
const PAD: float = 6.0
const TITLE_X: float = 9.0
const TITLE_HEIGHT: float = 14.0

var _data: BalanceData
var _count_labels: Dictionary[String, Label] = {}
var _icons: Dictionary[String, TextureRect] = {}
var _counts: Dictionary[String, int] = {}
var _blink_on: bool = false


func _init(box_name: String, rect: Rect2) -> void:
	name = box_name
	position = rect.position
	size = rect.size
	clip_contents = true
	add_theme_stylebox_override("panel", UiSkin.panel_box())


## 피버 대상 심볼(balance.json의 fever.targets 순서)대로 격자 칸을 만든다.
func setup(data: BalanceData) -> void:
	_data = data
	var title: Label = Label.new()
	title.name = "Title"
	title.text = TITLE_TEXT
	title.position = Vector2(TITLE_X, PAD)
	UiFont.apply(title, UiFont.Face.SMALL)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	add_child(title)
	var grid_top: float = PAD + TITLE_HEIGHT
	for i: int in data.fever_symbols.size():
		_add_row(data.fever_symbols[i], Rect2(PAD, grid_top + i * ROW_HEIGHT, size.x - PAD * 2.0, ROW_HEIGHT))


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


## "체리 ×20" 형식의 줄바꿈 목록. 화면에는 아이콘+숫자만 보이고, 테스트·디버그가 이 글자로 값을 확인한다.
func value_text() -> String:
	var rows: PackedStringArray = PackedStringArray()
	for symbol: String in _data.fever_symbols:
		rows.append("%s %s" % [_data.symbol_names.get(symbol, symbol), _count_labels[symbol].text])
	return "\n".join(rows)


## 이 심볼 줄의 숫자(×N) 글자 색 (테스트용)
func count_color(symbol: String) -> Color:
	return _count_labels[symbol].get_theme_color("font_color")


## 깜빡이지 않을 때 이 심볼 숫자의 색
func normal_count_color(symbol: String) -> Color:
	return COUNT_COLORS.get(symbol, COUNT_COLOR)


func row_count() -> int:
	return _count_labels.size()


## 이 심볼의 아이콘과 숫자 글자 (테스트용)
func icon_of(symbol: String) -> TextureRect:
	return _icons[symbol]


func count_label_of(symbol: String) -> Label:
	return _count_labels[symbol]


func _apply_blink() -> void:
	for symbol: String in _data.fever_symbols:
		var color_count: Color = LAST_ONE_COLOR if is_flashing(symbol) else normal_count_color(symbol)
		_count_labels[symbol].add_theme_color_override("font_color", color_count)


## 한 행: 아이콘은 왼쪽, 개수는 같은 오른쪽 끝에 맞춘 고정 열 (오른쪽 정렬)
func _add_row(symbol: String, cell: Rect2) -> void:
	var icon: TextureRect = _make_icon(symbol)
	icon.position = cell.position + Vector2(ICON_LEFT_PAD, (cell.size.y - icon.size.y) / 2.0)
	add_child(icon)
	var count_label: Label = Label.new()
	count_label.name = "Count_%s" % symbol
	count_label.text = "×%d" % _data.fever_initial_counts[symbol]
	var count_x: float = cell.position.x + ICON_LEFT_PAD + MAX_ICON_WIDTH
	count_label.position = Vector2(count_x, cell.position.y)
	count_label.size = Vector2(cell.end.x - COUNT_RIGHT_PAD - count_x, cell.size.y)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiFont.apply(count_label, UiFont.Face.SMALL, COUNT_FONT_MULTIPLE)
	count_label.add_theme_color_override("font_color", normal_count_color(symbol))
	add_child(count_label)
	_icons[symbol] = icon
	_count_labels[symbol] = count_label
	_counts[symbol] = _data.fever_initial_counts[symbol]


## 작은 아이콘을 아트 ×2로 놓는다. 그림이 없으면 빈 칸.
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

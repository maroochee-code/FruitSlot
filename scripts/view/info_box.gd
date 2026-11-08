class_name InfoBox
extends Panel
## 제목 + 값을 보여주는 상자. CREDIT / 안내 / WIN / BET / POOL / 피버 카운터에 쓴다.

const BG_COLOR: Color = Color("1A1A22")
const BORDER_COLOR: Color = Color("3A3A48")
const TITLE_COLOR: Color = Color("8A8AA0")
const VALUE_COLOR: Color = Color("F2F2F2")
const TITLE_FONT_SIZE: int = 10
const PAD: float = 6.0
const TITLE_HEIGHT: float = 15.0
const NO_TITLE_TOP: float = 3.0
const BOTTOM_PAD: float = 2.0

var _value: Label = Label.new()


func _init(box_name: String, title: String, rect: Rect2, value_font_size: int, align: HorizontalAlignment, wrap: bool = false, center_vertical: bool = true) -> void:
	name = box_name
	position = rect.position
	size = rect.size
	clip_contents = true
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = BG_COLOR
	box.border_color = BORDER_COLOR
	box.set_border_width_all(1)
	add_theme_stylebox_override("panel", box)
	var top: float = NO_TITLE_TOP
	if not title.is_empty():
		var title_label: Label = Label.new()
		title_label.text = title
		title_label.position = Vector2(PAD, 1.0)
		title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
		title_label.add_theme_color_override("font_color", TITLE_COLOR)
		add_child(title_label)
		top = TITLE_HEIGHT
	_value.position = Vector2(PAD, top)
	_value.size = Vector2(rect.size.x - PAD * 2.0, rect.size.y - top - BOTTOM_PAD)
	_value.horizontal_alignment = align
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if center_vertical else VERTICAL_ALIGNMENT_TOP
	_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	_value.add_theme_font_size_override("font_size", value_font_size)
	_value.add_theme_color_override("font_color", VALUE_COLOR)
	add_child(_value)


func set_value(text: String) -> void:
	_value.text = text


func value_text() -> String:
	return _value.text


func set_value_color(color: Color) -> void:
	_value.add_theme_color_override("font_color", color)

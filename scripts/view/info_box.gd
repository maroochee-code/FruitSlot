class_name InfoBox
extends Panel
## 제목 + 값을 보여주는 상자. CREDIT / 안내 / WIN / BET / POOL에 쓴다. 바탕은 도트 패널(9-slice).

const TITLE_COLOR: Color = UiSkin.LABEL_TEXT_COLOR
const VALUE_COLOR: Color = Color("ffffff")
## 패널 모서리(9-slice 6px) 안쪽 여백
const PAD: float = 9.0
const TOP_PAD: float = 6.0
const BOTTOM_PAD: float = 6.0
## 제목 아래로 값이 시작하는 높이 (갈무리9 글자 높이 11 + 여유)
const TITLE_HEIGHT: float = 12.0
## 숫자가 칸을 넘칠 때 글자 크기를 나누는 값
const SHRINK_DIVISOR: int = 2

var _value: Label = Label.new()
var _title_label: Label
var _value_font_size: int = 0
var _wrap: bool = false


## inline_title: 제목을 값 위가 아니라 같은 줄 왼쪽에 둔다 (낮은 상자용, POOL)
func _init(box_name: String, title: String, rect: Rect2, value_font_size: int, align: HorizontalAlignment, wrap_text: bool = false, center_vertical: bool = true, inline_title: bool = false) -> void:
	name = box_name
	position = rect.position
	size = rect.size
	clip_contents = true
	add_theme_stylebox_override("panel", UiSkin.panel_box())
	var top: float = TOP_PAD
	if not title.is_empty():
		_title_label = Label.new()
		_title_label.name = "Title"
		_title_label.text = title
		UiFont.apply(_title_label, UiFont.Face.SMALL)
		_title_label.add_theme_color_override("font_color", TITLE_COLOR)
		if inline_title:
			_title_label.position = Vector2(PAD, TOP_PAD)
			_title_label.size = Vector2(rect.size.x - PAD * 2.0, rect.size.y - TOP_PAD - BOTTOM_PAD)
			_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		else:
			_title_label.position = Vector2(PAD, TOP_PAD)
			top = TOP_PAD + TITLE_HEIGHT
		add_child(_title_label)
	_value.position = Vector2(PAD, top)
	_value.size = Vector2(rect.size.x - PAD * 2.0, rect.size.y - top - BOTTOM_PAD)
	_value.horizontal_alignment = align
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if center_vertical else VERTICAL_ALIGNMENT_TOP
	_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap_text else TextServer.AUTOWRAP_OFF
	_value_font_size = value_font_size
	_wrap = wrap_text
	_value.add_theme_font_size_override("font_size", value_font_size)
	_value.add_theme_color_override("font_color", VALUE_COLOR)
	add_child(_value)


## 값을 바꾼다. 한 줄 숫자가 칸 폭을 넘으면 글자를 반으로 줄인다 (24 → 12: 도트 폰트 원래 크기의 정수배 유지).
func set_value(text: String) -> void:
	_value.text = text
	if _wrap:
		return
	var size_now: int = _value_font_size
	var font: Font = _value.get_theme_font("font")
	if font != null and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now).x > _value.size.x:
		size_now = maxi(1, _value_font_size / SHRINK_DIVISOR)
	_value.add_theme_font_size_override("font_size", size_now)


## 지금 값 글자 크기 (테스트용)
func value_font_size_now() -> int:
	return _value.get_theme_font_size("font_size")


func value_text() -> String:
	return _value.text


func set_value_color(color: Color) -> void:
	_value.add_theme_color_override("font_color", color)


func value_color() -> Color:
	return _value.get_theme_color("font_color")


## 값 글자가 상자 안에 들어가는지 확인용 (테스트): 값 칸 영역과 글자의 최소 크기
func value_area() -> Rect2:
	return Rect2(_value.position, _value.size)


func value_min_size() -> Vector2:
	return _value.get_combined_minimum_size()


func title_label() -> Label:
	return _title_label

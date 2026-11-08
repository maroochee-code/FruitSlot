class_name SymbolCell
extends PanelContainer
## 3×3 릴의 칸 하나. 색 박스 + 글자. 로직 결과를 보여주기만 한다.

const BORDER_WIDTH: int = 3
const EMPTY_BG: Color = Color("202028")
const EMPTY_BORDER: Color = Color("404050")

var symbol_id: String = ""
var _label: Label = Label.new()


func _init() -> void:
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	show_empty()


func show_empty() -> void:
	symbol_id = ""
	_label.text = ""
	add_theme_stylebox_override("panel", _make_box(EMPTY_BG, EMPTY_BORDER))


func show_symbol(new_id: String) -> void:
	symbol_id = new_id
	var style: Dictionary = SymbolStyle.get_style(new_id)
	_label.text = style["text"]
	_label.add_theme_color_override("font_color", style["fg"])
	_label.add_theme_font_size_override("font_size", style.get("font_size", SymbolStyle.DEFAULT_FONT_SIZE))
	add_theme_stylebox_override("panel", _make_box(style["bg"], style["border"]))


func _make_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(BORDER_WIDTH)
	return box

class_name SymbolCell
extends PanelContainer
## 3×3 릴의 칸 하나. 색 박스 + 글자, 그림 파일이 있으면 그림. 로직 결과를 보여주기만 한다.

const BORDER_WIDTH: int = 3
const FRAME_WIDTH: int = 5
const FRAME_COLOR: Color = Color("FFFFFF")
const EMPTY_BG: Color = Color("202028")
const EMPTY_BORDER: Color = Color("404050")

var symbol_id: String = ""
var _label: Label = Label.new()
var _icon: TextureRect = TextureRect.new()
## 당첨 강조용 테두리 (평소엔 숨김)
var _frame: Panel = Panel.new()


func _init() -> void:
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	add_child(_icon)
	var frame_box: StyleBoxFlat = StyleBoxFlat.new()
	frame_box.bg_color = Color(0, 0, 0, 0)
	frame_box.border_color = FRAME_COLOR
	frame_box.set_border_width_all(FRAME_WIDTH)
	_frame.add_theme_stylebox_override("panel", frame_box)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)
	show_empty()


func show_empty() -> void:
	symbol_id = ""
	_label.text = ""
	_label.visible = true
	_icon.visible = false
	add_theme_stylebox_override("panel", _make_box(EMPTY_BG, EMPTY_BORDER))


func show_symbol(new_id: String) -> void:
	symbol_id = new_id
	var style: Dictionary = SymbolStyle.get_style(new_id)
	var texture: Texture2D = SymbolStyle.load_icon(new_id)
	_icon.texture = texture
	_icon.visible = texture != null
	_label.visible = texture == null
	_label.text = style["text"]
	_label.add_theme_color_override("font_color", style["fg"])
	_label.add_theme_font_size_override("font_size", style.get("font_size", SymbolStyle.DEFAULT_FONT_SIZE))
	add_theme_stylebox_override("panel", _make_box(style["bg"], style["border"]))


func set_highlight(on: bool) -> void:
	_frame.visible = on
	_frame.modulate.a = 1.0


func set_highlight_alpha(alpha: float) -> void:
	_frame.modulate.a = alpha


func is_highlighted() -> bool:
	return _frame.visible


func _make_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(BORDER_WIDTH)
	return box

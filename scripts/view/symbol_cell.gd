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
## 그림 모드: 칸 바탕 타일 + 그 위의 심볼. 둘 다 아트 좌표 × 정수 배율로 정확히 놓는다.
var _art: Control = Control.new()
var _tile: TextureRect = TextureRect.new()
var _icon: TextureRect = TextureRect.new()
## 당첨 강조용 테두리 (평소엔 숨김)
var _frame: Panel = Panel.new()


func _init() -> void:
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	add_child(_art)
	_setup_art_rect(_tile)
	_setup_art_rect(_icon)
	var frame_box: StyleBoxFlat = StyleBoxFlat.new()
	frame_box.bg_color = Color(0, 0, 0, 0)
	frame_box.border_color = FRAME_COLOR
	frame_box.set_border_width_all(FRAME_WIDTH)
	_frame.add_theme_stylebox_override("panel", frame_box)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)
	show_empty()


func _setup_art_rect(rect: TextureRect) -> void:
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.add_child(rect)


## 그림 크기(아트 좌표) × 배율로 타일과 심볼의 크기·위치를 정한다. 심볼은 타일 안쪽 오프셋에 놓인다.
func _place_art(tile: Texture2D, icon: Texture2D) -> void:
	_tile.texture = tile
	_tile.position = Vector2.ZERO
	_tile.size = tile.get_size() * SymbolStyle.ART_SCALE
	_icon.texture = icon
	_icon.position = Vector2(SymbolStyle.SYMBOL_ART_OFFSET * SymbolStyle.ART_SCALE)
	_icon.size = icon.get_size() * SymbolStyle.ART_SCALE


func show_empty() -> void:
	symbol_id = ""
	_label.text = ""
	_label.visible = true
	_art.visible = false
	add_theme_stylebox_override("panel", _make_box(EMPTY_BG, EMPTY_BORDER))


func show_symbol(new_id: String) -> void:
	symbol_id = new_id
	var style: Dictionary = SymbolStyle.get_style(new_id)
	var texture: Texture2D = SymbolStyle.load_icon(new_id)
	var tile: Texture2D = SymbolStyle.load_tile()
	var art_mode: bool = texture != null and tile != null
	_art.visible = art_mode
	_label.visible = not art_mode
	if art_mode:
		_place_art(tile, texture)
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		return
	_label.text = style["text"]
	_label.add_theme_color_override("font_color", style["fg"])
	_label.add_theme_font_size_override("font_size", style.get("font_size", SymbolStyle.DEFAULT_FONT_SIZE))
	add_theme_stylebox_override("panel", _make_box(style["bg"], style["border"]))


func set_highlight(on: bool) -> void:
	_frame.visible = on
	_frame.modulate.a = 1.0


func set_highlight_alpha(alpha: float) -> void:
	_frame.modulate.a = alpha


## 그림 모드로 보이는지 (테스트용)
func art_visible() -> bool:
	return _art.visible


## 타일·심볼이 칸 안에서 차지하는 영역 (테스트용)
func tile_rect() -> Rect2:
	return Rect2(_tile.position, _tile.size)


func symbol_rect() -> Rect2:
	return Rect2(_icon.position, _icon.size)


func is_highlighted() -> bool:
	return _frame.visible


func _make_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(BORDER_WIDTH)
	return box

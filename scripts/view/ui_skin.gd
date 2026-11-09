class_name UiSkin
extends RefCounted
## 도트 UI 스킨(패널·버튼 3상태·라인 라벨 그림)을 Godot 스타일로 바꿔 주는 곳.
## 그림은 tools/gen_pixel_assets.py가 만든 최종 크기(아트 ×3)이고, 9-slice는 모서리 6px(아트 2px)다.

const UI_DIR: String = "res://assets/ui/"
const PANEL_PATH: String = UI_DIR + "panel.png"
const BUTTON_PATHS: Dictionary = {
	"normal": UI_DIR + "button_normal.png",
	"pressed": UI_DIR + "button_pressed.png",
	"disabled": UI_DIR + "button_disabled.png",
}
const LINE_LABEL_PATH: String = UI_DIR + "line_label_%s.png"
const LINE_LETTERS: String = "abcdefgh"
const NINE_MARGIN: int = 6
## 눌린 버튼은 글자가 아트 1px(= 3px) 아래로 내려간다
const PRESSED_TEXT_SHIFT: int = 3
const DEFAULT_FONT_MULTIPLE: int = 1
const BUTTON_TEXT_COLOR: Color = Color("ffffff")
const BUTTON_DISABLED_TEXT_COLOR: Color = Color("6b7099")
## 라벨(작은 제목) 글자색
const LABEL_TEXT_COLOR: Color = Color("9aa0c8")
const TEXT_COLOR: Color = Color("ffffff")


## 9-slice 패널 바탕
static func panel_box() -> StyleBoxTexture:
	return _nine_box(PANEL_PATH)


## 버튼 상태("normal" / "pressed" / "disabled")의 바탕. 눌린 상태는 글자 위치가 3px 내려가도록 안쪽 여백을 바꾼다.
static func button_box(state: String) -> StyleBoxTexture:
	var box: StyleBoxTexture = _nine_box(BUTTON_PATHS[state])
	if state == "pressed":
		box.content_margin_top = NINE_MARGIN + PRESSED_TEXT_SHIFT
		box.content_margin_bottom = NINE_MARGIN - PRESSED_TEXT_SHIFT
	return box


## 라인 라벨 바탕 (index 0~7 = A~H). 크기는 그림 그대로 33×21.
static func line_label_box(index: int) -> StyleBoxTexture:
	var box: StyleBoxTexture = StyleBoxTexture.new()
	box.texture = load(LINE_LABEL_PATH % LINE_LETTERS[index % LINE_LETTERS.length()]) as Texture2D
	box.set_content_margin_all(0.0)
	return box


## 게임 전체 기본 테마: 갈무리 11(×1) 글자, 버튼 3상태 그림
static func make_theme() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = UiFont.font(UiFont.Face.BODY)
	theme.default_font_size = UiFont.size_of(UiFont.Face.BODY, DEFAULT_FONT_MULTIPLE)
	theme.set_color("font_color", "Label", TEXT_COLOR)
	theme.set_stylebox("normal", "Button", button_box("normal"))
	theme.set_stylebox("hover", "Button", button_box("normal"))
	theme.set_stylebox("pressed", "Button", button_box("pressed"))
	theme.set_stylebox("disabled", "Button", button_box("disabled"))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", BUTTON_TEXT_COLOR)
	theme.set_color("font_hover_color", "Button", BUTTON_TEXT_COLOR)
	theme.set_color("font_pressed_color", "Button", BUTTON_TEXT_COLOR)
	theme.set_color("font_hover_pressed_color", "Button", BUTTON_TEXT_COLOR)
	theme.set_color("font_disabled_color", "Button", BUTTON_DISABLED_TEXT_COLOR)
	return theme


static func _nine_box(path: String) -> StyleBoxTexture:
	var box: StyleBoxTexture = StyleBoxTexture.new()
	box.texture = load(path) as Texture2D
	box.set_texture_margin_all(NINE_MARGIN)
	return box

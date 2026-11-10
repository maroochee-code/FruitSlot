class_name TitleScreen
extends Control
## 시작 화면(7-C): 로고 + START / EXIT + 깜빡이는 PRESS START. 게임 규칙·결과 계산과 무관하다.
## START는 GameState.new_game()을 딱 한 번 부르고, button.wav가 끝난 뒤 게임 화면(main.tscn)으로 넘어간다.
## 조작: SPACE / ENTER = START, ESC = EXIT, 마우스 클릭. F1·F6 같은 개발용 키는 이 화면에서 무시한다.
## 화면 배치는 승인된 미리보기 assets/_preview/7c_title_logo_x2.png와 같다 (기존 로고 ×2, 기존 벽지·프레임·버튼·패널 재사용).

## START가 받아들여졌다 (new_game()을 부른 직후)
signal start_requested
## START 소리가 끝나 게임 화면으로 넘어갈 때가 됐다
signal start_finished
signal exit_requested

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const UI_DIR: String = UiSkin.UI_DIR
const BACKGROUND_COLOR: Color = Color("1f6f8b")
const WALLPAPER_PATH: String = UI_DIR + "wallpaper_tile.png"
const FRAME_PATH: String = UI_DIR + "frame.png"
const LOGO_PATH: String = UI_DIR + "logo.png"
## 기존 로고(180×72)를 정수 2배로 쓴다 (Nearest)
const LOGO_SCALE: int = 2

const PANEL_RECT: Rect2 = Rect2(57, 9, 526, 345)
const LOGO_Y: float = 30.0
const BUTTON_SIZE: Vector2 = Vector2(160, 36)
const START_Y: float = 222.0
const EXIT_Y: float = 276.0
const BOTTOM_RECT: Rect2 = Rect2(57, 414, 526, 57)
const PRESS_OFFSET_Y: float = 10.0
const HINT_OFFSET_Y: float = 32.0
const LABEL_H: float = 20.0
const PRESS_COLOR: Color = Color("ffd23a")
const HINT_COLOR: Color = Color("8a8aa0")
const PRESS_TEXT: String = "PRESS START"
const HINT_TEXT: String = "SPACE / ENTER  시작     ESC  종료"

## 테스트가 false로 두면 씬 전환·종료를 직접 하지 않는다 (시그널만 보낸다)
var auto_connect: bool = true

var _feel: FeelConfig
var _sound: SoundBank
var _bulbs: FrameBulbs
var _press: Label
var _start_button: Button
var _exit_button: Button
var _logo: TextureRect
var _blink_time: float = 0.0
## START가 받아들여진 뒤 true. 이후 모든 입력(START·EXIT·키)을 무시한다.
var _starting: bool = false
var _finished: bool = false
var _wait_left: float = 0.0


func _ready() -> void:
	theme = UiSkin.make_theme()
	_feel = FeelConfig.load_from_file()
	_build_background()
	_build_panels()
	_build_buttons()
	_build_texts()
	_sound = SoundBank.new()
	add_child(_sound)
	_sound.set_sfx_volume_db(_feel.sfx_volume_db)
	if auto_connect:
		start_finished.connect(_go_main)
		exit_requested.connect(_quit_game)
	_refresh_blink()


func _process(delta: float) -> void:
	advance(delta)


## 시간을 흘린다 (전구 대기 패턴, PRESS START 깜빡임, START 소리 대기)
func advance(delta: float) -> void:
	_bulbs.advance(delta)
	_blink_time += delta
	_refresh_blink()
	if not _starting or _finished:
		return
	_wait_left -= delta
	if _wait_left <= 0.0:
		_finished = true
		start_finished.emit()


## START: 새 게임을 시작한다. 이미 눌렸으면(소리가 끝나길 기다리는 중 포함) 무시하고 false.
func press_start() -> bool:
	if _starting or not GameState.ready_ok:
		return false
	if not GameState.new_game():
		return false
	_starting = true
	_sound.play(SoundBank.NAME_BUTTON)
	_wait_left = _button_sound_length()
	start_requested.emit()
	return true


## EXIT: 확인 없이 바로 종료를 요청한다. START가 이미 받아들여졌으면 무시.
func press_exit() -> bool:
	if _starting:
		return false
	exit_requested.emit()
	return true


func is_starting() -> bool:
	return _starting


## 지금 PRESS START 글자가 보이는 상태인가
func blink_visible() -> bool:
	return int(_blink_time / _feel.title_blink_sec) % 2 == 0


func sound_bank() -> SoundBank:
	return _sound


func frame_bulbs() -> FrameBulbs:
	return _bulbs


func start_button() -> Button:
	return _start_button


func exit_button() -> Button:
	return _exit_button


func logo() -> TextureRect:
	return _logo


func press_label() -> Label:
	return _press


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			press_start()
		KEY_ESCAPE:
			press_exit()


func _button_sound_length() -> float:
	var stream: AudioStream = load(SoundBank.sound_path(SoundBank.NAME_BUTTON)) as AudioStream
	return stream.get_length() if stream != null else 0.0


func _refresh_blink() -> void:
	_press.visible = blink_visible()


func _go_main() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _quit_game() -> void:
	get_tree().quit()


func _build_background() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.color = BACKGROUND_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var wall: TextureRect = TextureRect.new()
	wall.name = "Wallpaper"
	wall.texture = load(WALLPAPER_PATH) as Texture2D
	wall.stretch_mode = TextureRect.STRETCH_TILE
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wall)
	var frame: TextureRect = TextureRect.new()
	frame.name = "Frame"
	frame.texture = load(FRAME_PATH) as Texture2D
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	# 프레임 가로 띠의 전구: 기존 대기(IDLE) 패턴 그대로
	_bulbs = FrameBulbs.new()
	_bulbs.apply_feel(_feel)
	add_child(_bulbs)


func _build_panels() -> void:
	_add_panel("MainPanel", PANEL_RECT)
	_add_panel("BottomPanel", BOTTOM_RECT)
	_logo = TextureRect.new()
	_logo.name = "Logo"
	_logo.texture = load(LOGO_PATH) as Texture2D
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_SCALE
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.size = _logo.texture.get_size() * float(LOGO_SCALE)
	_logo.position = Vector2(PANEL_RECT.position.x + floorf((PANEL_RECT.size.x - _logo.size.x) / 2.0), LOGO_Y)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)


func _add_panel(node_name: String, rect: Rect2) -> void:
	var panel: Panel = Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", UiSkin.panel_box())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)


func _build_buttons() -> void:
	var x: float = PANEL_RECT.position.x + floorf((PANEL_RECT.size.x - BUTTON_SIZE.x) / 2.0)
	_start_button = _make_button("StartButton", "START", Vector2(x, START_Y))
	_start_button.pressed.connect(press_start)
	_exit_button = _make_button("ExitButton", "EXIT", Vector2(x, EXIT_Y))
	_exit_button.pressed.connect(press_exit)


func _make_button(node_name: String, text: String, pos: Vector2) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.position = pos
	button.size = BUTTON_SIZE
	# 스페이스·엔터가 버튼 클릭으로 한 번 더 처리되지 않게 한다.
	button.focus_mode = Control.FOCUS_NONE
	UiFont.apply(button, UiFont.Face.LARGE)
	add_child(button)
	return button


func _build_texts() -> void:
	_press = _make_label("PressLabel", PRESS_TEXT, UiFont.Face.LARGE, PRESS_COLOR, PRESS_OFFSET_Y)
	_make_label("HintLabel", HINT_TEXT, UiFont.Face.BODY, HINT_COLOR, HINT_OFFSET_Y)


func _make_label(node_name: String, text: String, face: UiFont.Face, color: Color, offset_y: float) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.position = Vector2(BOTTOM_RECT.position.x, BOTTOM_RECT.position.y + offset_y)
	label.size = Vector2(BOTTOM_RECT.size.x, LABEL_H)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFont.apply(label, face)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label

class_name GameOverOverlay
extends Control
## GAME OVER 화면 (7-B). 화면 윗부분(하단 CREDIT/WIN/BET 줄 위까지, 640×414)을 덮고, 입력(마우스)은 화면 전체를 막는다.
## 배너 / POOL·피버 카운터 패널 / CONTINUE·NEW GAME 버튼 / 남은 횟수 / 조작 안내.
## 이 클래스는 보여주고 선택만 받는다. CONTINUE·NEW GAME 처리는 시그널을 받은 main이 GameState에 맡긴다.
## 값(POOL·카운터·금액·남은 횟수)은 open()으로 받은 로직 값 그대로이고, 좌표는 tools/gen_pixel_assets.py의 GAMEOVER_LAYOUT과 같다.

signal continue_pressed
signal new_game_pressed

const SCREEN_SIZE: Vector2 = Vector2(640, 480)
const ART: int = SymbolStyle.ART_SCALE
## 그림이 덮는 영역 = 아트 138줄 = 640×414 (하단 표시창 y=414 바로 위까지)
const OVERLAY_SIZE: Vector2 = Vector2(640, 414)
const ART_WIDTH: int = 213
const BG_PATH: String = "res://assets/ui/gameover_bg.png"
const BANNER_PATH: String = "res://assets/ui/gameover_banner.png"
const BANNER_Y_ART: int = 10
## POOL·피버 카운터 패널 (아트 x, y, 폭, 높이)
const INFO_RECT_ART: Rect2i = Rect2i(22, 44, 168, 32)
const POOL_LABEL_Y: float = 9.0
const POOL_LABEL_H: float = 36.0
const COUNT_ROW_Y: float = 54.0
## 카운터 한 칸: 아이콘(12×10 아트 ×3 = 36×30) + 간격 + "×N" 글자 폭
const ICON_SCALE: int = 3
const ICON_COUNT_GAP: float = 6.0
const COUNT_LABEL_W: float = 54.0
const ROW_H: float = 30.0
## 버튼 (아트 y, 높이, 폭, 왼쪽 x 둘)
const BUTTON_Y_ART: int = 84
const BUTTON_SIZE_ART: Vector2i = Vector2i(80, 18)
const BUTTON_XS_ART: Array[int] = [22, 111]
const BUTTON_CONTINUE: int = 0
const BUTTON_NEW_GAME: int = 1
const BUTTON_TEXT_GAP: float = 6.0
## 남은 횟수·조작 안내 글자 줄 (px)
const REMAIN_Y: float = 321.0
const HINT_Y: float = 390.0
const TEXT_H: float = 24.0
const POOL_COLOR: Color = Color("ff9a1f")
const CREAM: Color = Color("f7e6b8")
const GOLD: Color = Color("ffd23a")
const REMAIN_ZERO_COLOR: Color = Color("ff6a6a")
const HINT_COLOR: Color = Color("8a8aa0")
const HINT_TEXT: String = "←  → 선택     SPACE / ENTER 결정"
const POOL_FONT_MULTIPLE: int = 2
const THOUSANDS_GROUP: int = 3

var _bg: TextureRect = TextureRect.new()
var _banner: TextureRect = TextureRect.new()
var _info: Panel = Panel.new()
var _pool_label: Label = Label.new()
var _remain: Label = Label.new()
var _hint: Label = Label.new()
var _buttons: Array[Button] = []
var _tops: Array[Label] = []
var _bottoms: Array[Label] = []
var _count_icons: Dictionary[String, TextureRect] = {}
var _count_labels: Dictionary[String, Label] = {}
var _data: BalanceData
var _open: bool = false
var _selected: int = BUTTON_CONTINUE
var _can_continue: bool = false
var _lock_left: float = 0.0


func _init() -> void:
	name = "GameOverOverlay"
	position = Vector2.ZERO
	size = SCREEN_SIZE
	# 아래 화면의 마우스 입력을 막는다 (버튼 클릭 방지)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_art()
	_build_info()
	_build_buttons()
	_build_texts()


## 천 단위 쉼표 (1000 → "1,000")
static func format_amount(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % THOUSANDS_GROUP == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


## 화면을 연다. 값은 모두 로직(GameState)의 현재 값이다.
func open(data: BalanceData, pool: int, counts: Dictionary[String, int], left: int, left_max: int, continue_credit: int, start_credit: int, lock_sec: float) -> void:
	_ensure_counts(data)
	_pool_label.text = "POOL %s" % format_amount(pool)
	for symbol: String in data.fever_symbols:
		_count_labels[symbol].text = "×%d" % counts[symbol]
	_can_continue = left > 0
	_tops[BUTTON_CONTINUE].text = "CONTINUE"
	_bottoms[BUTTON_CONTINUE].text = "+%s" % format_amount(continue_credit)
	_tops[BUTTON_NEW_GAME].text = "NEW GAME"
	_bottoms[BUTTON_NEW_GAME].text = "+%s" % format_amount(start_credit)
	_buttons[BUTTON_CONTINUE].disabled = not _can_continue
	_remain.text = "CONTINUE 남은 횟수  %d / %d" % [left, left_max]
	_remain.add_theme_color_override("font_color", CREAM if _can_continue else REMAIN_ZERO_COLOR)
	_selected = BUTTON_CONTINUE if _can_continue else BUTTON_NEW_GAME
	_lock_left = maxf(0.0, lock_sec)
	_open = true
	visible = true
	_apply_selection()


func close() -> void:
	_open = false
	visible = false


func is_open() -> bool:
	return _open


## 뜬 직후 입력 잠금 시간을 흘린다. main.advance()가 부른다.
func advance(delta: float) -> void:
	if _lock_left > 0.0:
		_lock_left = maxf(0.0, _lock_left - delta)


## 결정 입력(스페이스·엔터·클릭)이 잠겨 있는가
func is_locked() -> bool:
	return _lock_left > 0.0


## 0 = CONTINUE, 1 = NEW GAME
func selected() -> int:
	return _selected


## 선택을 옮긴다. 비활성 버튼(이어하기 0회의 CONTINUE)으로는 옮기지 않는다.
func move(direction: int) -> void:
	if not _open:
		return
	select(clampi(_selected + direction, BUTTON_CONTINUE, BUTTON_NEW_GAME))


func select(index: int) -> void:
	if not _open or (index == BUTTON_CONTINUE and not _can_continue):
		return
	_selected = index
	_apply_selection()


## 선택한 버튼을 결정한다. 잠금 중이거나 비활성이면 아무것도 하지 않는다. 결정했으면 true.
func confirm() -> bool:
	return _activate(_selected)


func continue_button() -> Button:
	return _buttons[BUTTON_CONTINUE]


func new_game_button() -> Button:
	return _buttons[BUTTON_NEW_GAME]


## 버튼 글자 (위 줄, 아래 줄)
func button_texts(index: int) -> PackedStringArray:
	return PackedStringArray([_tops[index].text, _bottoms[index].text])


func remaining_text() -> String:
	return _remain.text


func remaining_color() -> Color:
	return _remain.get_theme_color("font_color")


func pool_text() -> String:
	return _pool_label.text


## "체리 ×17" 형식의 줄바꿈 목록 (피버 패널 value_text와 같은 형식)
func counts_text() -> String:
	var rows: PackedStringArray = PackedStringArray()
	for symbol: String in _data.fever_symbols:
		rows.append("%s %s" % [_data.symbol_names.get(symbol, symbol), _count_labels[symbol].text])
	return "\n".join(rows)


func banner() -> TextureRect:
	return _banner


func background() -> TextureRect:
	return _bg


func info_panel() -> Panel:
	return _info


## 눈에 보이는 그림·글자 노드의 가장 아래 y (414를 넘으면 안 됨, 테스트용)
func content_bottom() -> float:
	var bottom: float = 0.0
	for child: Node in get_children():
		var control: Control = child as Control
		if control != null and control.visible:
			bottom = maxf(bottom, control.position.y + control.size.y)
	return bottom


func _activate(index: int) -> bool:
	if not _open or _lock_left > 0.0:
		return false
	if index == BUTTON_CONTINUE:
		if not _can_continue:
			return false
		continue_pressed.emit()
	else:
		new_game_pressed.emit()
	return true


func _apply_selection() -> void:
	for i: int in _buttons.size():
		var button: Button = _buttons[i]
		var on: bool = i == _selected
		var disabled: bool = button.disabled
		for state: String in ["normal", "hover"]:
			if on and not disabled:
				button.add_theme_stylebox_override(state, UiSkin.button_box("on"))
			else:
				button.remove_theme_stylebox_override(state)
		var top_color: Color = UiSkin.BUTTON_TEXT_COLOR
		var bottom_color: Color = GOLD
		if disabled:
			top_color = UiSkin.BUTTON_DISABLED_TEXT_COLOR
			bottom_color = UiSkin.BUTTON_DISABLED_TEXT_COLOR
		elif on:
			top_color = UiSkin.BUTTON_ON_TEXT_COLOR
			bottom_color = UiSkin.BUTTON_ON_TEXT_COLOR
		_tops[i].add_theme_color_override("font_color", top_color)
		_bottoms[i].add_theme_color_override("font_color", bottom_color)


func _build_art() -> void:
	_bg.name = "Bg"
	_bg.texture = load(BG_PATH) as Texture2D
	_bg.size = OVERLAY_SIZE
	_setup_art(_bg)
	_banner.name = "Banner"
	_banner.texture = load(BANNER_PATH) as Texture2D
	_banner.size = _banner.texture.get_size()
	var banner_art_width: int = int(_banner.size.x) / ART
	_banner.position = Vector2((ART_WIDTH - banner_art_width) / 2 * ART, BANNER_Y_ART * ART)
	_setup_art(_banner)


func _build_info() -> void:
	_info.name = "InfoPanel"
	_info.position = Vector2(INFO_RECT_ART.position * ART)
	_info.size = Vector2(INFO_RECT_ART.size * ART)
	_info.add_theme_stylebox_override("panel", UiSkin.panel_box())
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)
	_pool_label.name = "PoolLabel"
	_pool_label.position = Vector2(0.0, POOL_LABEL_Y)
	_pool_label.size = Vector2(_info.size.x, POOL_LABEL_H)
	_style_label(_pool_label, UiFont.Face.LARGE, POOL_FONT_MULTIPLE, POOL_COLOR)
	_info.add_child(_pool_label)


## 피버 카운터 줄(아이콘 + ×N)은 심볼 목록이 정해진 뒤(첫 open)에 한 번 만든다.
func _ensure_counts(data: BalanceData) -> void:
	if _data != null:
		return
	_data = data
	var columns: int = data.fever_symbols.size()
	var column_w: float = _info.size.x / float(columns)
	var group_w: float = float(ICON_SCALE * 12) + ICON_COUNT_GAP + COUNT_LABEL_W
	for i: int in columns:
		var symbol: String = data.fever_symbols[i]
		var x: float = column_w * i + (column_w - group_w) / 2.0
		var icon: TextureRect = TextureRect.new()
		icon.name = "Icon_%s" % symbol
		icon.texture = SymbolStyle.load_small_icon(symbol)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if icon.texture != null:
			icon.size = icon.texture.get_size() * ICON_SCALE
		icon.position = Vector2(x, COUNT_ROW_Y + (ROW_H - icon.size.y) / 2.0)
		_info.add_child(icon)
		var label: Label = Label.new()
		label.name = "Count_%s" % symbol
		label.position = Vector2(x + float(ICON_SCALE * 12) + ICON_COUNT_GAP, COUNT_ROW_Y)
		label.size = Vector2(COUNT_LABEL_W, ROW_H)
		_style_label(label, UiFont.Face.LARGE, 1, CREAM)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_info.add_child(label)
		_count_icons[symbol] = icon
		_count_labels[symbol] = label


func _build_buttons() -> void:
	var names: Array[String] = ["ContinueButton", "NewGameButton"]
	var button_size: Vector2 = Vector2(BUTTON_SIZE_ART * ART)
	for i: int in names.size():
		var button: Button = Button.new()
		button.name = names[i]
		button.position = Vector2(BUTTON_XS_ART[i] * ART, BUTTON_Y_ART * ART)
		button.size = button_size
		button.focus_mode = Control.FOCUS_NONE
		UiFont.apply(button, UiFont.Face.LARGE)
		add_child(button)
		button.pressed.connect(_activate.bind(i))
		button.mouse_entered.connect(select.bind(i))
		_buttons.append(button)
		# 글자는 두 줄(이름 / 금액)을 따로 칠하려고 라벨 둘을 버튼 위에 얹는다
		var line_h: float = float(UiFont.size_of(UiFont.Face.LARGE))
		var top_y: float = (button_size.y - (line_h * 2.0 + BUTTON_TEXT_GAP)) / 2.0
		var top: Label = Label.new()
		top.name = "Top"
		top.position = Vector2(0.0, top_y)
		top.size = Vector2(button_size.x, line_h)
		_style_label(top, UiFont.Face.LARGE, 1, UiSkin.BUTTON_TEXT_COLOR)
		button.add_child(top)
		var bottom: Label = Label.new()
		bottom.name = "Bottom"
		bottom.position = Vector2(0.0, top_y + line_h + BUTTON_TEXT_GAP)
		bottom.size = Vector2(button_size.x, line_h)
		_style_label(bottom, UiFont.Face.LARGE, 1, GOLD)
		button.add_child(bottom)
		_tops.append(top)
		_bottoms.append(bottom)


func _build_texts() -> void:
	_remain.name = "RemainLabel"
	_remain.position = Vector2(0.0, REMAIN_Y)
	_remain.size = Vector2(SCREEN_SIZE.x, TEXT_H)
	_style_label(_remain, UiFont.Face.BODY, 1, CREAM)
	add_child(_remain)
	_hint.name = "HintLabel"
	_hint.position = Vector2(0.0, HINT_Y)
	_hint.size = Vector2(SCREEN_SIZE.x, TEXT_H)
	_style_label(_hint, UiFont.Face.BODY, 1, HINT_COLOR)
	_hint.text = HINT_TEXT
	add_child(_hint)


## 그림 노드 공통 설정: 클릭을 막지 않고, 정해 준 크기로 늘린다.
func _setup_art(rect: TextureRect) -> void:
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(rect)


func _style_label(label: Label, face: UiFont.Face, multiple: int, color: Color) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFont.apply(label, face, multiple)
	label.add_theme_color_override("font_color", color)

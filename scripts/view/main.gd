extends Control
## 2단계 정지 화면. START(또는 스페이스/엔터)로 SlotLogic.spin()을 부르고 결과를 바로 보여준다.
## 결과는 로직이 정한다. 이 스크립트는 그 값을 표시만 한다.

# --- 화면 배치 (640×480 기준) ---
const REEL_COLS: int = 3
const REEL_ROWS: int = 3
const CELL_SIZE: Vector2 = Vector2(100, 88)
const CELL_GAP: float = 4.0
const REEL_ORIGIN: Vector2 = Vector2(76, 60)
const LABEL_SLOT_SIZE: Vector2 = Vector2(36, 28)
const LABEL_SLOTS_PER_SIDE: int = 4
const LABEL_SLOT_STEP: float = 68.0
const LEFT_LABEL_X: float = 32.0
const RIGHT_LABEL_X: float = 392.0
const STOP_SLOT_Y: float = 340.0
const STOP_SLOT_SIZE: Vector2 = Vector2(100, 28)
const BUTTON_ROW_Y: float = 376.0
const BUTTON_SIZE: Vector2 = Vector2(96, 32)
const START_BUTTON_SIZE: Vector2 = Vector2(120, 32)
const SIDE_PANEL_RECT: Rect2 = Rect2(468, 8, 168, 404)
const TITLE_RECT: Rect2 = Rect2(468, 8, 168, 48)
const POOL_RECT: Rect2 = Rect2(468, 62, 168, 48)
const FEVER_RECT: Rect2 = Rect2(468, 116, 168, 140)
const BOTTOM_Y: float = 420.0
const BOTTOM_H: float = 56.0
const BOTTOM_SLOTS: Array[Dictionary] = [
	{ "name": "Credit", "text": "CREDIT", "x": 4.0, "w": 140.0 },
	{ "name": "Notice", "text": "안내", "x": 148.0, "w": 220.0 },
	{ "name": "Win", "text": "WIN", "x": 372.0, "w": 124.0 },
	{ "name": "Bet", "text": "BET", "x": 500.0, "w": 136.0 },
]
const PLACEHOLDER_BG: Color = Color("1A1A22")
const PLACEHOLDER_BORDER: Color = Color("3A3A48")
const PLACEHOLDER_TEXT: Color = Color("6A6A7A")
const PLACEHOLDER_FONT_SIZE: int = 10
const BACKGROUND_COLOR: Color = Color("0C0C14")
## 한글이 깨지지 않도록 시스템 한글 글꼴을 우선 지정
const FONT_NAMES: PackedStringArray = ["Malgun Gothic", "맑은 고딕", "Noto Sans CJK KR", "Apple SD Gothic Neo", "sans-serif"]

var _logic: SlotLogic
var _data: BalanceData
var _cells: Array[Array] = []
var _debug: DebugPanel
var _debug_visible: bool = true
var _last_result: SpinResult
## 2단계는 베팅 UI가 없어 풀베팅 값을 balance.json에서 읽어 쓴다.
var _test_bet: int = 0


func _ready() -> void:
	_apply_font()
	_data = BalanceData.load_from_file()
	if _data == null:
		push_error("main: balance.json 로드 실패")
		return
	_test_bet = _data.fever_min_total_bet
	_logic = SlotLogic.new(_data, int(Time.get_ticks_usec()))
	_build_background()
	_build_reels()
	_build_placeholders()
	_build_buttons()
	_build_debug()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			do_spin()
		KEY_F1:
			toggle_debug()


## 스핀 1회를 실행하고 결과를 표시한다. 테스트에서도 부른다.
func do_spin() -> SpinResult:
	var result: SpinResult = _logic.spin(_test_bet)
	if result == null:
		return null
	_last_result = result
	_show_grid(result.grid)
	_debug.show_result(result, _data, grid_matches_logic())
	return result


## 화면 칸에 실제로 표시된 심볼이 마지막 로직 결과와 같은지 비교한다.
func grid_matches_logic() -> bool:
	if _last_result == null:
		return false
	for col: int in REEL_COLS:
		for row: int in REEL_ROWS:
			var cell: SymbolCell = _cells[col][row]
			if cell.symbol_id != _last_result.grid[col][row]:
				return false
	return true


func toggle_debug() -> void:
	_debug_visible = not _debug_visible
	_debug.visible = _debug_visible


func _show_grid(grid: Array[PackedStringArray]) -> void:
	for col: int in REEL_COLS:
		for row: int in REEL_ROWS:
			var cell: SymbolCell = _cells[col][row]
			cell.show_symbol(grid[col][row])


func _apply_font() -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = FONT_NAMES
	var ui_theme: Theme = Theme.new()
	ui_theme.default_font = font
	theme = ui_theme


func _build_background() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.color = BACKGROUND_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _build_reels() -> void:
	var holder: Control = Control.new()
	holder.name = "Reels"
	add_child(holder)
	for col: int in REEL_COLS:
		var column: Array = []
		for row: int in REEL_ROWS:
			var cell: SymbolCell = SymbolCell.new()
			cell.name = "Cell_%d_%d" % [col, row]
			cell.position = REEL_ORIGIN + Vector2(col * (CELL_SIZE.x + CELL_GAP), row * (CELL_SIZE.y + CELL_GAP))
			cell.size = CELL_SIZE
			holder.add_child(cell)
			column.append(cell)
		_cells.append(column)


## 3단계 이후에 채울 자리들을 빈 칸으로 미리 잡아 둔다.
func _build_placeholders() -> void:
	for i: int in LABEL_SLOTS_PER_SIDE:
		var y: float = REEL_ORIGIN.y + i * LABEL_SLOT_STEP
		_add_placeholder("LineLabelL%d" % i, "", Rect2(Vector2(LEFT_LABEL_X, y), LABEL_SLOT_SIZE))
		_add_placeholder("LineLabelR%d" % i, "", Rect2(Vector2(RIGHT_LABEL_X, y), LABEL_SLOT_SIZE))
	for col: int in REEL_COLS:
		var x: float = REEL_ORIGIN.x + col * (CELL_SIZE.x + CELL_GAP)
		_add_placeholder("StopSlot%d" % (col + 1), "STOP %d" % (col + 1), Rect2(Vector2(x, STOP_SLOT_Y), STOP_SLOT_SIZE))
	_add_placeholder("Title", "타이틀", TITLE_RECT)
	_add_placeholder("Pool", "POOL", POOL_RECT)
	_add_placeholder("FeverCounter", "피버 카운터", FEVER_RECT)
	for slot: Dictionary in BOTTOM_SLOTS:
		_add_placeholder(slot["name"], slot["text"], Rect2(slot["x"], BOTTOM_Y, slot["w"], BOTTOM_H))


func _add_placeholder(node_name: String, text: String, rect: Rect2) -> void:
	var panel: Panel = Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PLACEHOLDER_BG
	box.border_color = PLACEHOLDER_BORDER
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", PLACEHOLDER_FONT_SIZE)
	label.add_theme_color_override("font_color", PLACEHOLDER_TEXT)
	panel.add_child(label)
	add_child(panel)


func _build_buttons() -> void:
	var reels_width: float = REEL_COLS * CELL_SIZE.x + (REEL_COLS - 1) * CELL_GAP
	var center_x: float = REEL_ORIGIN.x + reels_width / 2.0
	var start_x: float = center_x - START_BUTTON_SIZE.x / 2.0
	var start: Button = _make_button("StartButton", "START", Rect2(Vector2(start_x, BUTTON_ROW_Y), START_BUTTON_SIZE))
	start.pressed.connect(do_spin)
	var coin: Button = _make_button("CoinButton", "COIN", Rect2(Vector2(start_x - BUTTON_SIZE.x - CELL_GAP, BUTTON_ROW_Y), BUTTON_SIZE))
	var bet: Button = _make_button("BetButton", "BET", Rect2(Vector2(start_x + START_BUTTON_SIZE.x + CELL_GAP, BUTTON_ROW_Y), BUTTON_SIZE))
	# COIN/BET은 3단계에서 연결한다.
	coin.disabled = true
	bet.disabled = true


func _make_button(node_name: String, text: String, rect: Rect2) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.position = rect.position
	button.size = rect.size
	# 스페이스·엔터가 버튼 클릭으로 한 번 더 처리되지 않게 한다.
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	return button


func _build_debug() -> void:
	_debug = DebugPanel.new()
	_debug.name = "DebugPanel"
	_debug.position = SIDE_PANEL_RECT.position
	_debug.size = SIDE_PANEL_RECT.size
	_debug.clip_contents = true
	add_child(_debug)

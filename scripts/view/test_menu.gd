class_name TestMenu
extends Control
## 테스트 메뉴(8-B). 개발 빌드 + 테스트 모드에서만 게임 화면의 F3로 연다. 릴·AUTO·정산 연출·피버 오버레이·GAME OVER 중에는 열지 않는다(열기 조건은 main이 판단).
## 탭 3개:
##   미리보기  — FEVER!/POOL GET!, 정산 연출(소/중/대), GAME OVER 화면, 전구 모양. 별도 인스턴스를 띄울 뿐 게임 상태·main의 WIN/CREDIT 박스를 바꾸지 않는다.
##   상태 설정 — 크레딧 지급(grant_credit test_coin), 피버 카운터 1, 풀 금액. GameState의 테스트 모드 입구만 쓰고 결과는 기존 규칙을 그대로 탄다.
##   다음 판 당첨 — 다음 한 판의 정지 위치를 지정(결과 강제). RNG는 평소처럼 소비되고 그 결과만 바뀐다. 쓰면 테스트 판 표시가 켜진다.
## 값(금액·기준)은 모두 balance.json·economy.json·feel.json에서 읽고 새 수치를 만들지 않는다.

## 상태를 바꿨을 때의 안내 글자 (main이 안내 칸에 보여 준다)
signal message(text: String)

enum Tab { PREVIEW, STATE, FORCE }

const TAB_NAMES: PackedStringArray = ["미리보기", "상태 설정", "다음 판 당첨"]
const BACKDROP_SIZE: Vector2 = Vector2(640, 414)
const BACKDROP_COLOR: Color = Color(0, 0, 0, 0.6)
const PANEL_RECT: Rect2 = Rect2(57, 9, 526, 396)
const TITLE_Y: float = 16.0
const TITLE_H: float = 20.0
const TAB_Y: float = 42.0
const TAB_SIZE: Vector2 = Vector2(150, 26)
const TAB_GAP: float = 8.0
const ROWS_Y: float = 82.0
const ROW_H: float = 27.0
const ROW_X: float = 69.0
const ROW_W: float = 502.0
const ROW_BUTTON_H: float = 26.0
const HINT_Y: float = 380.0
const HINT_H: float = 20.0
const SETTLE_LABEL_Y: float = 372.0
const SETTLE_LABEL_H: float = 24.0
const BULB_PREVIEW_SEC: float = 3.0
const TITLE_TEXT: String = "TEST MENU"
const HINT_TEXT: String = "↑↓ 선택   Enter 실행   Tab 탭   Esc·F3 닫기"
const GOLD: Color = Color("ffd23a")
const HINT_COLOR: Color = Color("8a8aa0")
const CREAM: Color = Color("f7e6b8")
const ID_SEPARATOR: String = ":"
const ID_FEVER: String = "fever"
const ID_SETTLE: String = "settle"
const ID_GAME_OVER: String = "gameover"
const ID_BULB: String = "bulb"
const ID_CREDIT: String = "credit"
const ID_COUNTER: String = "counter"
const ID_POOL: String = "pool"
const ID_FORCE: String = "force"
const POOL_INITIAL: String = "initial"
const POOL_YELLOW: String = "yellow"
const POOL_RED: String = "red"
const FORCE_CLEAR: String = "none"
const CREDIT_MULTIPLIERS: Array[int] = [1, 10, 100]
const BULB_MODES: Dictionary = {
	"spin": BulbPattern.Mode.SPIN,
	"win": BulbPattern.Mode.WIN,
	"fever": BulbPattern.Mode.FEVER,
}
const BULB_LABELS: Dictionary = { "spin": "스핀", "win": "당첨", "fever": "피버" }
const SETTLE_TIERS: Dictionary = { "small": FeelConfig.TIER_SMALL, "mid": FeelConfig.TIER_MID, "big": FeelConfig.TIER_BIG }
const SETTLE_LABELS: Dictionary = { "small": "소", "mid": "중", "big": "대" }

var _data: BalanceData
var _feel: FeelConfig
var _sound: SoundBank
var _bulb_player: Callable
var _win_point: Vector2 = Vector2.ZERO
var _credit_point: Vector2 = Vector2.ZERO
var _open: bool = false
var _tab: int = Tab.PREVIEW
var _selected: int = 0
var _items: Array[Dictionary] = []
var _layer: Control = Control.new()
var _rows_box: Control = Control.new()
var _tab_buttons: Array[Button] = []
var _row_buttons: Array[Button] = []
var _fever: FeverOverlay
var _fever_steps: Array[Dictionary] = []
var _settle: SettleShow
var _settle_label: Label
var _win_shown: int = 0
var _credit_shown: int = 0
var _over: GameOverOverlay


func _init() -> void:
	name = "TestMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_layer.name = "Layer"
	_layer.size = BACKDROP_SIZE
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.visible = false
	add_child(_layer)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = BACKDROP_COLOR
	backdrop.size = BACKDROP_SIZE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(backdrop)
	var panel: Panel = Panel.new()
	panel.name = "Panel"
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.add_theme_stylebox_override("panel", UiSkin.panel_box())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(panel)
	_make_label(_layer, "TitleLabel", TITLE_TEXT, Vector2(PANEL_RECT.position.x, TITLE_Y), Vector2(PANEL_RECT.size.x, TITLE_H), HORIZONTAL_ALIGNMENT_CENTER, GOLD, UiFont.Face.LARGE)
	_build_tabs()
	_rows_box.name = "Rows"
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_rows_box)
	_make_label(_layer, "HintLabel", HINT_TEXT, Vector2(PANEL_RECT.position.x, HINT_Y), Vector2(PANEL_RECT.size.x, HINT_H), HORIZONTAL_ALIGNMENT_CENTER, HINT_COLOR)
	_build_previews()


func _process(delta: float) -> void:
	advance(delta)


## 데이터·소리·정산 연출의 출발/도착 위치·전구 모양 바꾸기(Callable(mode, hold_sec))를 받는다. main이 한 번 부른다.
func configure(data: BalanceData, bank: SoundBank, win_point: Vector2, credit_point: Vector2, bulb_player: Callable) -> void:
	_data = data
	_sound = bank
	_win_point = win_point
	_credit_point = credit_point
	_bulb_player = bulb_player


## 효과음 뱅크는 main이 소리를 만든 뒤에 넘겨 준다
func set_sound(bank: SoundBank) -> void:
	_sound = bank


func is_open() -> bool:
	return _open


## 미리보기 연출이 재생 중인가 (이 동안 키 입력은 건너뛰기로만 쓰이고, 아래 화면은 입력을 받지 않는다)
func is_previewing() -> bool:
	return _fever.is_playing() or _settle.is_active() or _over.is_open()


func tab() -> int:
	return _tab


func selected() -> int:
	return _selected


## 지금 탭의 항목 목록 (id, label)
func items() -> Array[Dictionary]:
	return _items


func item_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for item: Dictionary in _items:
		ids.append(String(item["id"]))
	return ids


func row_button(index: int) -> Button:
	return _row_buttons[index]


func tab_button(index: int) -> Button:
	return _tab_buttons[index]


func fever_overlay() -> FeverOverlay:
	return _fever


func settle_show() -> SettleShow:
	return _settle


func game_over_preview() -> GameOverOverlay:
	return _over


func settle_label() -> Label:
	return _settle_label


## 메뉴를 연다. 열 수 있는 순간인지는 부른 쪽(main)이 판단한다.
func open(feel: FeelConfig) -> bool:
	if _data == null or _open:
		return false
	_feel = feel
	_open = true
	_layer.visible = true
	select_tab(Tab.PREVIEW)
	return true


func close() -> void:
	_open = false
	_layer.visible = false


func select_tab(index: int) -> void:
	_tab = clampi(index, 0, TAB_NAMES.size() - 1)
	_selected = 0
	_rebuild_rows()
	_refresh_tabs()


func move(delta: int) -> void:
	if not _open or _items.is_empty():
		return
	_selected = posmod(_selected + delta, _items.size())
	_refresh_rows()


func select_index(index: int) -> void:
	if index >= 0 and index < _items.size():
		_selected = index
		_refresh_rows()


func execute_selected() -> bool:
	if not _open or _selected >= _items.size():
		return false
	return execute(String(_items[_selected]["id"]))


## 항목 하나를 실행한다. 미리보기는 메뉴를 닫고 재생하며, 상태 설정은 GameState의 테스트 모드 입구를 거친다.
func execute(id: String) -> bool:
	if _data == null:
		return false
	var parts: PackedStringArray = id.split(ID_SEPARATOR)
	if parts.size() != 2 and id != ID_GAME_OVER:
		return false
	match parts[0]:
		ID_FEVER:
			return _start_fever_preview(parts[1])
		ID_SETTLE:
			return _start_settle_preview(parts[1])
		ID_GAME_OVER:
			return _start_game_over_preview()
		ID_BULB:
			return _start_bulb_preview(parts[1])
		ID_CREDIT:
			return _grant_credit(int(parts[1]))
		ID_COUNTER:
			return _set_counter(parts[1])
		ID_POOL:
			return _set_pool(parts[1])
		ID_FORCE:
			return _force_next(parts[1])
	return false


## 시간을 흘린다 (미리보기 연출). 테스트는 이걸 직접 부른다.
func advance(delta: float) -> void:
	_fever.advance(delta)
	_settle.advance(delta)
	_over.advance(delta)
	_settle_label.visible = _settle.is_active()


## 재생 중인 미리보기를 건너뛴다 (정산 연출은 끝값으로, GAME OVER 화면은 닫음, 피버는 잠금 시간이 지난 뒤)
func skip_preview() -> void:
	if _fever.is_playing():
		_fever.skip()
	if _settle.is_active():
		_settle.finish_now()
	if _over.is_open():
		_over.close()


## main이 넘겨 주는 키 입력. 열려 있거나 미리보기 중일 때만 쓴다.
func handle_key(key: InputEventKey) -> void:
	if is_previewing():
		match key.keycode:
			KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				skip_preview()
		return
	if not _open:
		return
	match key.keycode:
		KEY_ESCAPE, KEY_F3:
			close()
		KEY_UP:
			move(-1)
		KEY_DOWN:
			move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			execute_selected()
		KEY_TAB:
			select_tab(posmod(_tab + (-1 if key.shift_pressed else 1), TAB_NAMES.size()))
		KEY_PAGEUP:
			select_tab(posmod(_tab - 1, TAB_NAMES.size()))
		KEY_PAGEDOWN:
			select_tab(posmod(_tab + 1, TAB_NAMES.size()))


# ---------------------------------------------------------------- 미리보기 (게임 상태를 바꾸지 않음)

## 기준 베팅: 지금 BET, 없으면 피버 최소 베팅
func _reference_bet() -> int:
	return maxi(GameState.bet, _data.fever_min_total_bet)


func _start_fever_preview(symbol: String) -> bool:
	if not _data.fever_symbols.has(symbol):
		return false
	var reference_bet: int = _reference_bet()
	var result: SpinResult = SpinResult.new()
	result.total_bet = reference_bet
	result.fever_triggers.append(symbol)
	result.fever_bonuses[symbol] = int(_data.fever_multipliers[symbol]) * reference_bet
	if symbol == _data.pool_award_on_fever:
		result.pool_won = GameState.get_pool()
	_fever_steps = FeverOverlay.build_steps(result, _data)
	close()
	_fever.set_motion(_feel.fever_bg_frame_sec, _feel.fever_banner_flash_sec, _feel.pool_coin_frame_sec)
	_fever.play(_fever_steps, _feel.fever_overlay_sec, _feel.fever_step_gap, _feel.fever_skip_lock_sec, _feel.pool_overlay_sec)
	return true


func _start_settle_preview(tier_name: String) -> bool:
	if not SETTLE_TIERS.has(tier_name):
		return false
	var tier: int = SETTLE_TIERS[tier_name]
	var reference_bet: int = _reference_bet()
	var payout: int = reference_bet
	match tier:
		FeelConfig.TIER_MID:
			payout = roundi(reference_bet * _feel.win_mid_ratio)
		FeelConfig.TIER_BIG:
			payout = roundi(reference_bet * _feel.win_big_ratio)
	_win_shown = 0
	_credit_shown = GameState.credit
	_refresh_settle_label()
	close()
	_play(SoundBank.win_sound_for(payout, reference_bet, _feel.win_mid_ratio, _feel.win_big_ratio))
	_settle.start(payout, GameState.credit, _feel.countup_sec(tier), _feel.coin_count(tier), _feel.coin_fly_sec, _feel.countup_tick_sec, _win_point, _credit_point)
	_settle_label.visible = true
	return true


func _start_game_over_preview() -> bool:
	close()
	_over.open(_data, GameState.get_pool(), GameState.get_fever_counts(), GameState.continues_left, GameState.continue_max, GameState.continue_credit, GameState.start_credit, 0.0)
	_play(SoundBank.NAME_GAMEOVER)
	return true


func _start_bulb_preview(mode_name: String) -> bool:
	if not BULB_MODES.has(mode_name) or not _bulb_player.is_valid():
		return false
	close()
	_bulb_player.call(BULB_MODES[mode_name], BULB_PREVIEW_SEC)
	message.emit("테스트: 전구 모양 '%s' (%d초 뒤 대기 모양으로 돌아옵니다)" % [BULB_LABELS[mode_name], int(BULB_PREVIEW_SEC)])
	return true


# ---------------------------------------------------------------- 상태 설정 (GameState의 테스트 모드 입구)

func _grant_credit(multiplier: int) -> bool:
	var amount: int = GameState.coin_amount * multiplier
	var ok: bool = GameState.test_grant_credit(amount)
	_finish_action(ok, "테스트: 크레딧 +%s (테스트 판)" % GameOverOverlay.format_amount(amount))
	return ok


func _set_counter(symbol: String) -> bool:
	var ok: bool = GameState.test_set_fever_count(symbol, 1)
	_finish_action(ok, "테스트: %s 피버 카운터 = 1 (테스트 판)" % _symbol_name(symbol))
	return ok


func _set_pool(kind: String) -> bool:
	var amount: int = _pool_preset(kind)
	var ok: bool = amount >= 0 and GameState.test_set_pool(amount)
	_finish_action(ok, "테스트: 풀 금액 = %s (테스트 판)" % GameOverOverlay.format_amount(amount))
	return ok


func _force_next(symbol: String) -> bool:
	var clear: bool = symbol == FORCE_CLEAR
	var ok: bool = GameState.test_force_next_win("" if clear else symbol)
	_finish_action(ok, "테스트: 다음 판 예약을 취소했습니다" if clear else "테스트: 다음 판 %s 당첨 예약 (테스트 판)" % _symbol_name(symbol))
	return ok


func _finish_action(ok: bool, text: String) -> void:
	close()
	message.emit(text if ok else "테스트: 지금은 쓸 수 없습니다")


func _pool_preset(kind: String) -> int:
	match kind:
		POOL_INITIAL:
			return _data.pool_initial
		POOL_YELLOW:
			return int(_feel.pool_yellow_from)
		POOL_RED:
			return int(_feel.pool_red_from)
	return -1


func _symbol_name(symbol: String) -> String:
	return String(_data.symbol_names.get(symbol, symbol))


func _play(sound_name: StringName) -> void:
	if _sound != null:
		_sound.play(sound_name)


# ---------------------------------------------------------------- 항목·화면

func _build_items(tab_index: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	match tab_index:
		Tab.PREVIEW:
			for symbol: String in _data.fever_symbols:
				var label: String = "FEVER!  %s" % _symbol_name(symbol)
				if symbol == _data.pool_award_on_fever:
					label += "  + POOL GET!"
				list.append(_item(ID_FEVER + ID_SEPARATOR + symbol, label))
			for tier_name: String in SETTLE_TIERS:
				list.append(_item(ID_SETTLE + ID_SEPARATOR + tier_name, "정산 연출  %s" % SETTLE_LABELS[tier_name]))
			list.append(_item(ID_GAME_OVER, "GAME OVER 화면"))
			for mode_name: String in BULB_MODES:
				list.append(_item(ID_BULB + ID_SEPARATOR + mode_name, "전구 모양  %s" % BULB_LABELS[mode_name]))
		Tab.STATE:
			for multiplier: int in CREDIT_MULTIPLIERS:
				list.append(_item(ID_CREDIT + ID_SEPARATOR + str(multiplier), "크레딧 +%s" % GameOverOverlay.format_amount(GameState.coin_amount * multiplier)))
			for symbol: String in _data.fever_symbols:
				if int(_data.fever_initial_counts[symbol]) > 1:
					list.append(_item(ID_COUNTER + ID_SEPARATOR + symbol, "피버 카운터  %s = 1" % _symbol_name(symbol)))
			list.append(_item(ID_POOL + ID_SEPARATOR + POOL_INITIAL, "풀 금액 = 초기값 (%s)" % GameOverOverlay.format_amount(_pool_preset(POOL_INITIAL))))
			list.append(_item(ID_POOL + ID_SEPARATOR + POOL_YELLOW, "풀 금액 = 노랑 기준 (%s)" % GameOverOverlay.format_amount(_pool_preset(POOL_YELLOW))))
			list.append(_item(ID_POOL + ID_SEPARATOR + POOL_RED, "풀 금액 = 빨강 기준 (%s)" % GameOverOverlay.format_amount(_pool_preset(POOL_RED))))
		_:
			for symbol: String in _data.fever_symbols:
				var marked: String = "  (예약됨)" if GameState.forced_symbol() == symbol else ""
				list.append(_item(ID_FORCE + ID_SEPARATOR + symbol, "다음 판  %s 당첨%s" % [_symbol_name(symbol), marked]))
			list.append(_item(ID_FORCE + ID_SEPARATOR + FORCE_CLEAR, "예약 취소"))
	return list


func _item(id: String, label: String) -> Dictionary:
	return { "id": id, "label": label }


func _rebuild_rows() -> void:
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.free()
	_row_buttons.clear()
	_items = _build_items(_tab)
	for i: int in _items.size():
		var button: Button = _make_button(_rows_box, "Row%d" % i, String(_items[i]["label"]), Vector2(ROW_X, ROWS_Y + float(i) * ROW_H), Vector2(ROW_W, ROW_BUTTON_H))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_row_pressed.bind(i))
		_row_buttons.append(button)
	_refresh_rows()


func _on_row_pressed(index: int) -> void:
	select_index(index)
	execute_selected()


func _refresh_rows() -> void:
	for i: int in _row_buttons.size():
		var button: Button = _row_buttons[i]
		if i == _selected:
			button.add_theme_stylebox_override("normal", UiSkin.button_box("on"))
			button.add_theme_stylebox_override("hover", UiSkin.button_box("on"))
			button.add_theme_color_override("font_color", UiSkin.BUTTON_ON_TEXT_COLOR)
			button.add_theme_color_override("font_hover_color", UiSkin.BUTTON_ON_TEXT_COLOR)
		else:
			button.remove_theme_stylebox_override("normal")
			button.remove_theme_stylebox_override("hover")
			button.remove_theme_color_override("font_color")
			button.remove_theme_color_override("font_hover_color")


func _refresh_tabs() -> void:
	for i: int in _tab_buttons.size():
		var button: Button = _tab_buttons[i]
		if i == _tab:
			button.add_theme_stylebox_override("normal", UiSkin.button_box("on"))
			button.add_theme_stylebox_override("hover", UiSkin.button_box("on"))
			button.add_theme_color_override("font_color", UiSkin.BUTTON_ON_TEXT_COLOR)
			button.add_theme_color_override("font_hover_color", UiSkin.BUTTON_ON_TEXT_COLOR)
		else:
			button.remove_theme_stylebox_override("normal")
			button.remove_theme_stylebox_override("hover")
			button.remove_theme_color_override("font_color")
			button.remove_theme_color_override("font_hover_color")


func _refresh_settle_label() -> void:
	_settle_label.text = "WIN %s     CREDIT %s" % [GameOverOverlay.format_amount(_win_shown), GameOverOverlay.format_amount(_credit_shown)]


func _build_tabs() -> void:
	var total: float = TAB_SIZE.x * float(TAB_NAMES.size()) + TAB_GAP * float(TAB_NAMES.size() - 1)
	var x0: float = PANEL_RECT.position.x + floorf((PANEL_RECT.size.x - total) / 2.0)
	for i: int in TAB_NAMES.size():
		var button: Button = _make_button(_layer, "Tab%d" % i, TAB_NAMES[i], Vector2(x0 + float(i) * (TAB_SIZE.x + TAB_GAP), TAB_Y), TAB_SIZE)
		button.pressed.connect(select_tab.bind(i))
		_tab_buttons.append(button)


## 미리보기용 별도 인스턴스. main의 오버레이·정산 연출·GAME OVER 화면과 시그널로 이어져 있지 않다 (게임 상태를 바꾸지 않음).
func _build_previews() -> void:
	_fever = FeverOverlay.new()
	_fever.name = "PreviewFever"
	add_child(_fever)
	_fever.step_started.connect(_on_fever_step_started)
	_settle = SettleShow.new()
	_settle.name = "PreviewSettle"
	add_child(_settle)
	_settle.win_shown_changed.connect(_on_preview_win_shown)
	_settle.credit_shown_changed.connect(_on_preview_credit_shown)
	_settle.tick.connect(_on_preview_tick)
	_settle.coin_landed.connect(_on_preview_tick)
	_settle_label = _make_label(self, "SettleLabel", "", Vector2(0.0, SETTLE_LABEL_Y), Vector2(BACKDROP_SIZE.x, SETTLE_LABEL_H), HORIZONTAL_ALIGNMENT_CENTER, GOLD, UiFont.Face.LARGE)
	_settle_label.visible = false
	_over = GameOverOverlay.new()
	_over.name = "PreviewGameOver"
	add_child(_over)
	_over.continue_pressed.connect(_over.close)
	_over.new_game_pressed.connect(_over.close)


func _on_fever_step_started(index: int) -> void:
	var is_pool: bool = _fever_steps[index]["kind"] == FeverOverlay.KIND_POOL
	_play(SoundBank.NAME_POOL_GET if is_pool else SoundBank.NAME_FEVER_START)


func _on_preview_win_shown(value: int) -> void:
	_win_shown = value
	_refresh_settle_label()


func _on_preview_credit_shown(value: int) -> void:
	_credit_shown = value
	_refresh_settle_label()


func _on_preview_tick() -> void:
	_play(SoundBank.NAME_TICK)


## 글자 노드는 트리에 넣은 뒤에 크기를 정한다 (넣기 전에 정하면 기본 글꼴 기준의 큰 최소 크기가 남는다).
func _make_button(parent: Node, node_name: String, text: String, pos: Vector2, button_size: Vector2) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	UiFont.apply(button, UiFont.Face.BODY)
	parent.add_child(button)
	button.position = pos
	button.size = button_size
	return button


func _make_label(parent: Node, node_name: String, text: String, pos: Vector2, label_size: Vector2, align: HorizontalAlignment, color: Color, face: UiFont.Face = UiFont.Face.BODY) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFont.apply(label, face)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	label.position = pos
	label.size = label_size
	return label

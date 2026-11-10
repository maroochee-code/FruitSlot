class_name SettingsScreen
extends Control
## 운영자 설정 화면(8-A). 시작 화면 위에 얹는 오버레이로, 시작 화면에서 F2로 연다 (게임 중에는 열지 않는다).
## 값은 "초안"(UserSettings 복사본)에서만 바꾸고, 파일 저장·GameState 반영은 "저장하고 닫기"에서만 한다.
## 소리 세 항목은 만지는 동안 오디오 버스에 바로 반영해 들어 볼 수 있고, 취소하면 원래 소리로 되돌린다.
## 기본값(data/*.json)과 다른(= 설정 파일에 저장될) 값은 노랑으로 표시한다. 저장된 키는 economy.json·feel.json을 고쳐도 반영되지 않는다.
## 밸런스(릴·배당·피버·풀)는 어디에도 없다. 입력은 시작 화면이 handle_key()로 넘겨 준다 (Esc가 게임 종료로 새지 않게 한 곳에서 처리).

## 닫혔다. saved가 true면 "저장하고 닫기"
signal closed(saved: bool)

enum Tab { SOUND, CREDIT, EFFECT }

const TAB_NAMES: PackedStringArray = ["소리·AUTO", "크레딧", "연출"]
const ROW_BEST: String = "best"
const ROW_BEST_RESET: String = "best_reset"
const LABELS: Dictionary = {
	"sfx_volume_db": "효과음 볼륨",
	"bgm_volume_db": "BGM 볼륨",
	"bgm_enabled": "BGM",
	"auto_stop_on_win_at": "AUTO 큰 당첨 정지",
	"auto_effect_scale": "AUTO 연출 배율",
	"start_credit": "시작 크레딧",
	"continue_credit": "CONTINUE 코인",
	"continue_max": "CONTINUE 횟수",
	"coin_amount": "COIN 지급량 (개발용)",
	ROW_BEST: "최고 기록",
	ROW_BEST_RESET: "최고 기록 초기화",
	"countup_small_sec": "정산 연출 소 (초)",
	"countup_mid_sec": "정산 연출 중 (초)",
	"countup_big_sec": "정산 연출 대 (초)",
	"win_mid_ratio": "당첨 중 기준 (배)",
	"win_big_ratio": "당첨 대 기준 (배)",
}
const AUDIO_KEYS: PackedStringArray = ["sfx_volume_db", "bgm_volume_db", "bgm_enabled"]

const PANEL_RECT: Rect2 = Rect2(57, 9, 526, 345)
const FOOTER_RECT: Rect2 = Rect2(57, 414, 526, 57)
const TITLE_Y: float = 16.0
const TITLE_H: float = 20.0
const TAB_Y: float = 42.0
const TAB_SIZE: Vector2 = Vector2(150, 26)
const TAB_GAP: float = 8.0
const ROWS_Y: float = 82.0
const ROW_H: float = 30.0
const ROW_X: float = 69.0
const ROW_W: float = 502.0
const ROW_INNER_H: float = 28.0
const LABEL_X: float = 12.0
const LABEL_W: float = 236.0
const LEFT_X: float = 258.0
const VALUE_X: float = 292.0
const VALUE_W: float = 116.0
const RIGHT_X: float = 414.0
const ARROW_SIZE: Vector2 = Vector2(28, 26)
const ARROW_Y: float = 1.0
const ACTION_W: float = 184.0
const HINT_Y: float = 322.0
const HINT_H: float = 20.0
const FOOTER_BUTTON_SIZE: Vector2 = Vector2(150, 36)
const FOOTER_BUTTON_GAP: float = 10.0
const FOOTER_BUTTON_Y: float = 424.0
const NORMAL_COLOR: Color = Color("ffffff")
const CHANGED_COLOR: Color = Color("ffd23a")
const LABEL_COLOR: Color = Color("c8cce8")
const HINT_COLOR: Color = Color("8a8aa0")
const SELECT_BAR_COLOR: Color = Color("27338a")
const TITLE_TEXT: String = "SETTINGS"
const HINT_TEXT: String = "↑↓ 선택   ←→ 변경(Shift 크게)   Tab 탭   Space 실행   Enter 저장   Esc 취소"
const DEFAULTS_TEXT: String = "기본값으로"
const DEFAULTS_ARMED_TEXT: String = "한 번 더 누르세요"
const CANCEL_TEXT: String = "취소"
const SAVE_TEXT: String = "저장하고 닫기"
const RESET_TEXT: String = "초기화"
const RESET_ARMED_TEXT: String = "한 번 더 누르면 초기화"
const NO_RECORD_TEXT: String = "기록 없음"
const AUTO_OFF_TEXT: String = "사용 안 함"

## 마지막 저장이 파일에 잘 써졌는가 (쓰기 실패해도 이번 실행에는 메모리로 적용된다)
var last_save_ok: bool = true

var _sound: SoundBank
var _draft: UserSettings = UserSettings.new()
var _base: Dictionary = {}
var _open: bool = false
var _tab: int = Tab.SOUND
var _selected: int = 0
var _rows: Array[String] = []
var _rows_box: Control = Control.new()
var _row_nodes: Dictionary[String, Control] = {}
var _tab_buttons: Array[Button] = []
var _defaults_button: Button
var _cancel_button: Button
var _save_button: Button
var _defaults_armed: bool = false
var _best_armed: bool = false


func _init() -> void:
	name = "SettingsScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_add_panel("MainPanel", PANEL_RECT)
	_add_panel("FooterPanel", FOOTER_RECT)


## 글자가 있는 노드는 트리에 들어온 뒤(부모 테마가 적용된 뒤)에 만든다. 그 전에 크기를 정하면 기본 글꼴 기준의 큰 최소 크기가 남는다.
func _ready() -> void:
	_build_header()
	_build_tabs()
	_rows_box.name = "Rows"
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows_box)
	_build_hint()
	_build_footer()


## 소리 설정 버스에 반영한다. BGM 끄기는 BGM 버스를 mute하는 방식이라 BgmPlayer 로직은 그대로다.
static func apply_audio(sfx_db: float, bgm_db: float, bgm_on: bool) -> void:
	SoundBank.ensure_buses()
	var sfx_index: int = AudioServer.get_bus_index(SoundBank.BUS_SFX)
	var bgm_index: int = AudioServer.get_bus_index(SoundBank.BUS_BGM)
	AudioServer.set_bus_volume_db(sfx_index, sfx_db)
	AudioServer.set_bus_volume_db(bgm_index, bgm_db)
	AudioServer.set_bus_mute(bgm_index, not bgm_on)


## BGM 켜짐 여부만 버스에 반영 (게임 화면이 단독으로 실행될 때도 설정을 따르게)
static func apply_bgm_mute(bgm_on: bool) -> void:
	SoundBank.ensure_buses()
	AudioServer.set_bus_mute(AudioServer.get_bus_index(SoundBank.BUS_BGM), not bgm_on)


## 값 표시 글자
static func format_value(key: String, value: Variant) -> String:
	match key:
		"sfx_volume_db", "bgm_volume_db":
			return "%d dB" % int(roundf(float(value)))
		UserSettings.KEY_BGM_ENABLED:
			return "켜짐" if bool(value) else "꺼짐"
		UserSettings.KEY_AUTO_STOP:
			return AUTO_OFF_TEXT if int(value) == 0 else GameOverOverlay.format_amount(int(value))
		"auto_effect_scale", UserSettings.KEY_WIN_MID, UserSettings.KEY_WIN_BIG:
			return "×%.1f" % float(value)
		"continue_max":
			return "%d회" % int(value)
		"countup_small_sec", "countup_mid_sec", "countup_big_sec":
			return "%.2f초" % float(value)
		_:
			return GameOverOverlay.format_amount(int(value))


## 효과음 뱅크 (값을 바꿀 때 들려주는 소리용). 시작 화면이 넘겨 준다.
func set_sound(bank: SoundBank) -> void:
	_sound = bank


func is_open() -> bool:
	return _open


func tab() -> int:
	return _tab


func draft() -> UserSettings:
	return _draft


## 지금 탭에 보이는 줄의 키 목록 (값 줄, 정보 줄, 실행 줄)
func row_keys() -> Array[String]:
	return _rows


func selected_key() -> String:
	return _rows[_selected] if _selected < _rows.size() else ""


func row_node(key: String) -> Control:
	return _row_nodes.get(key)


func value_label(key: String) -> Label:
	var row: Control = row_node(key)
	return row.get_node("Value") as Label if row != null else null


func arrow_button(key: String, direction: int) -> Button:
	var row: Control = row_node(key)
	if row == null:
		return null
	return row.get_node_or_null("Left" if direction < 0 else "Right") as Button


func action_button() -> Button:
	var row: Control = row_node(ROW_BEST_RESET)
	return row.get_node("Action") as Button if row != null else null


func tab_button(index: int) -> Button:
	return _tab_buttons[index]


func defaults_button() -> Button:
	return _defaults_button


func cancel_button() -> Button:
	return _cancel_button


func save_button() -> Button:
	return _save_button


## 이 키의 지금 값(초안 기준). 바꾸지 않았으면 기본값(data/*.json)이다.
func effective(key: String) -> Variant:
	return _draft.get_or(key, _base[key])


## 이 키가 기본값과 달라 설정 파일에 저장될 값인가 (노랑 표시)
func value_is_changed(key: String) -> bool:
	return _draft.has_value(key)


func value_text(key: String) -> String:
	var label: Label = value_label(key)
	return label.text if label != null else ""


func open() -> void:
	if _open:
		return
	_draft = UserSettings.active().duplicate_settings()
	_base = _build_base()
	_tab = Tab.SOUND
	_selected = 0
	_defaults_armed = false
	_best_armed = false
	_open = true
	visible = true
	_rebuild_rows()
	_refresh_tabs()
	_refresh_footer()


func select_tab(index: int) -> void:
	if not _open:
		return
	_tab = clampi(index, 0, TAB_NAMES.size() - 1)
	_selected = 0
	_disarm()
	_rebuild_rows()
	_refresh_tabs()


func move(delta: int) -> void:
	if not _open or _rows.is_empty():
		return
	_disarm()
	_selected = posmod(_selected + delta, _rows.size())
	_refresh_rows()


func select_key(key: String) -> void:
	var index: int = _rows.find(key)
	if index != -1 and index != _selected:
		_disarm()
		_selected = index
		_refresh_rows()


## 선택한 줄의 값을 한 단계(big이면 큰 단계) 바꾼다. 범위 끝이거나 값 줄이 아니면 false.
func adjust(key: String, direction: int, big: bool) -> bool:
	if not _open or not _base.has(key) or not _rows.has(key):
		return false
	_disarm()
	var current: Dictionary = _effective_all()
	var next: Variant = UserSettings.step_value(key, current, direction, big)
	if _same(next, current[key]):
		return false
	if _same(next, _base[key]):
		_draft.clear_value(key)
	else:
		_draft.set_value(key, next)
	if AUDIO_KEYS.has(key):
		_apply_draft_audio()
	if key == "sfx_volume_db":
		_play(SoundBank.NAME_BUTTON)
	_refresh_rows()
	return true


func adjust_selected(direction: int, big: bool) -> bool:
	return adjust(selected_key(), direction, big)


## 선택한 줄이 실행 줄(최고 기록 초기화)이면 실행. 처음엔 확인 글자로 바뀌고 두 번째에 실행한다.
func activate_selected() -> bool:
	if _open and selected_key() == ROW_BEST_RESET:
		return press_best_reset()
	return false


## 최고 기록 초기화: 첫 번째는 확인 상태로만 바뀌고, 두 번째에 실행한다 (최고 기록은 설정과 별도 파일이라 저장 버튼과 무관하게 바로 지워진다)
func press_best_reset() -> bool:
	if not _open:
		return false
	if not _best_armed:
		_defaults_armed = false
		_best_armed = true
		_refresh_rows()
		_refresh_footer()
		return false
	HighScore.active().reset()
	_best_armed = false
	_refresh_rows()
	return true


## 기본값으로 되돌리기: 첫 번째는 확인 상태로만 바뀌고, 두 번째에 설정 값 전체를 지운다 (저장 전까지는 초안만 바뀜, 최고 기록은 그대로)
func press_defaults() -> bool:
	if not _open:
		return false
	if not _defaults_armed:
		_best_armed = false
		_defaults_armed = true
		_refresh_rows()
		_refresh_footer()
		return false
	_draft.clear_all()
	_defaults_armed = false
	_apply_draft_audio()
	_refresh_rows()
	_refresh_footer()
	return true


## 저장하고 닫기: 파일 저장 + GameState에 economy·AUTO 값 반영 + 소리 확정. 파일 쓰기가 실패해도 이번 실행에는 적용한다.
func save() -> bool:
	if not _open:
		return false
	last_save_ok = UserSettings.commit(_draft)
	if not last_save_ok:
		push_warning("SettingsScreen: 설정을 파일에 저장하지 못했습니다 (이번 실행에만 적용)")
	GameState.apply_user_values(UserSettings.active())
	_apply_audio_from(UserSettings.active())
	_play(SoundBank.NAME_BUTTON)
	_close(true)
	return last_save_ok


## 취소: 변경을 버리고 소리를 원래대로 되돌린다
func cancel() -> void:
	if not _open:
		return
	_apply_audio_from(UserSettings.active())
	_close(false)


## 시작 화면이 넘겨 주는 키 입력. 열려 있는 동안 모든 키는 여기서만 처리되고 시작 화면에는 새지 않는다.
func handle_key(key: InputEventKey) -> void:
	if not _open:
		return
	match key.keycode:
		KEY_ESCAPE:
			cancel()
		KEY_ENTER, KEY_KP_ENTER:
			save()
		KEY_UP:
			move(-1)
		KEY_DOWN:
			move(1)
		KEY_LEFT:
			adjust_selected(-1, key.shift_pressed)
		KEY_RIGHT:
			adjust_selected(1, key.shift_pressed)
		KEY_TAB:
			select_tab(posmod(_tab + (-1 if key.shift_pressed else 1), TAB_NAMES.size()))
		KEY_PAGEUP:
			select_tab(posmod(_tab - 1, TAB_NAMES.size()))
		KEY_PAGEDOWN:
			select_tab(posmod(_tab + 1, TAB_NAMES.size()))
		KEY_SPACE:
			activate_selected()


# ---------------------------------------------------------------- 안쪽

func _close(saved: bool) -> void:
	_open = false
	visible = false
	_disarm()
	closed.emit(saved)


func _build_base() -> Dictionary:
	var feel: FeelConfig = FeelConfig.load_from_file(FeelConfig.DEFAULT_PATH, false)
	var economy: Dictionary = GameState.load_economy()
	var auto_stop: int = GameState.get_balance().auto_stop_on_win_at
	return UserSettings.base_values(feel, economy, auto_stop)


func _effective_all() -> Dictionary:
	var all: Dictionary = {}
	for key: String in UserSettings.keys():
		all[key] = effective(key)
	return all


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b


func _play(sound_name: StringName) -> void:
	if _sound != null:
		_sound.play(sound_name)


func _apply_draft_audio() -> void:
	_apply_audio_from(_draft)


func _apply_audio_from(settings: UserSettings) -> void:
	var sfx: float = float(settings.get_or("sfx_volume_db", _base["sfx_volume_db"]))
	var bgm: float = float(settings.get_or("bgm_volume_db", _base["bgm_volume_db"]))
	apply_audio(sfx, bgm, settings.bgm_enabled())


func _disarm() -> void:
	if not _defaults_armed and not _best_armed:
		return
	_defaults_armed = false
	_best_armed = false
	_refresh_rows()
	_refresh_footer()


func _tab_rows(tab_index: int) -> Array[String]:
	var keys: Array[String] = []
	match tab_index:
		Tab.SOUND:
			keys = ["sfx_volume_db", "bgm_volume_db", "bgm_enabled", "auto_stop_on_win_at", "auto_effect_scale"]
		Tab.CREDIT:
			keys = ["start_credit", "continue_credit", "continue_max"]
			if GameState.dev_build:
				keys.append("coin_amount")
			keys.append(ROW_BEST)
			keys.append(ROW_BEST_RESET)
		_:
			keys = ["countup_small_sec", "countup_mid_sec", "countup_big_sec", "win_mid_ratio", "win_big_ratio"]
	return keys


func _rebuild_rows() -> void:
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.free()
	_row_nodes.clear()
	_rows = _tab_rows(_tab)
	for i: int in _rows.size():
		_row_nodes[_rows[i]] = _make_row(_rows[i], i)
	_refresh_rows()


func _make_row(key: String, index: int) -> Control:
	var row: Control = Control.new()
	row.name = "Row_%s" % key
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.add_child(row)
	row.position = Vector2(ROW_X, ROWS_Y + float(index) * ROW_H)
	row.size = Vector2(ROW_W, ROW_INNER_H)
	var bar: ColorRect = ColorRect.new()
	bar.name = "Highlight"
	bar.color = SELECT_BAR_COLOR
	bar.size = row.size
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	row.add_child(bar)
	_make_label(row, "Label", LABELS[key], Vector2(LABEL_X, 0.0), Vector2(LABEL_W, ROW_INNER_H), HORIZONTAL_ALIGNMENT_LEFT, LABEL_COLOR)
	if key == ROW_BEST_RESET:
		_make_button(row, "Action", RESET_TEXT, Vector2(LEFT_X, ARROW_Y), Vector2(ACTION_W, ARROW_SIZE.y)).pressed.connect(_on_action_pressed)
		return row
	_make_label(row, "Value", "", Vector2(VALUE_X, 0.0), Vector2(VALUE_W, ROW_INNER_H), HORIZONTAL_ALIGNMENT_CENTER, NORMAL_COLOR)
	if key == ROW_BEST:
		return row
	_make_button(row, "Left", "<", Vector2(LEFT_X, ARROW_Y), ARROW_SIZE).pressed.connect(_on_arrow_pressed.bind(key, -1))
	_make_button(row, "Right", ">", Vector2(RIGHT_X, ARROW_Y), ARROW_SIZE).pressed.connect(_on_arrow_pressed.bind(key, 1))
	return row


func _on_arrow_pressed(key: String, direction: int) -> void:
	select_key(key)
	adjust(key, direction, Input.is_key_pressed(KEY_SHIFT))


func _on_action_pressed() -> void:
	select_key(ROW_BEST_RESET)
	press_best_reset()


## 줄 글자·색·선택 막대를 지금 상태에 맞춘다
func _refresh_rows() -> void:
	for i: int in _rows.size():
		var key: String = _rows[i]
		var row: Control = _row_nodes[key]
		(row.get_node("Highlight") as ColorRect).visible = (i == _selected)
		if key == ROW_BEST_RESET:
			(row.get_node("Action") as Button).text = RESET_ARMED_TEXT if _best_armed else RESET_TEXT
			continue
		var label: Label = row.get_node("Value")
		if key == ROW_BEST:
			var best: int = HighScore.active().best_peak_credit
			label.text = GameOverOverlay.format_amount(best) if best > 0 else NO_RECORD_TEXT
			label.add_theme_color_override("font_color", NORMAL_COLOR)
			continue
		label.text = format_value(key, effective(key))
		label.add_theme_color_override("font_color", CHANGED_COLOR if value_is_changed(key) else NORMAL_COLOR)


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


func _refresh_footer() -> void:
	_defaults_button.text = DEFAULTS_ARMED_TEXT if _defaults_armed else DEFAULTS_TEXT


func _add_panel(node_name: String, rect: Rect2) -> void:
	var panel: Panel = Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", UiSkin.panel_box())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)


func _build_header() -> void:
	_make_label(self, "TitleLabel", TITLE_TEXT, Vector2(PANEL_RECT.position.x, TITLE_Y), Vector2(PANEL_RECT.size.x, TITLE_H), HORIZONTAL_ALIGNMENT_CENTER, CHANGED_COLOR, UiFont.Face.LARGE)


func _build_tabs() -> void:
	var total: float = TAB_SIZE.x * float(TAB_NAMES.size()) + TAB_GAP * float(TAB_NAMES.size() - 1)
	var x0: float = PANEL_RECT.position.x + floorf((PANEL_RECT.size.x - total) / 2.0)
	for i: int in TAB_NAMES.size():
		var button: Button = _make_button(self, "Tab%d" % i, TAB_NAMES[i], Vector2(x0 + float(i) * (TAB_SIZE.x + TAB_GAP), TAB_Y), TAB_SIZE)
		button.pressed.connect(select_tab.bind(i))
		_tab_buttons.append(button)


func _build_hint() -> void:
	_make_label(self, "HintLabel", HINT_TEXT, Vector2(PANEL_RECT.position.x, HINT_Y), Vector2(PANEL_RECT.size.x, HINT_H), HORIZONTAL_ALIGNMENT_CENTER, HINT_COLOR)


func _build_footer() -> void:
	var total: float = FOOTER_BUTTON_SIZE.x * 3.0 + FOOTER_BUTTON_GAP * 2.0
	var x0: float = FOOTER_RECT.position.x + floorf((FOOTER_RECT.size.x - total) / 2.0)
	_defaults_button = _make_button(self, "DefaultsButton", DEFAULTS_TEXT, Vector2(x0, FOOTER_BUTTON_Y), FOOTER_BUTTON_SIZE)
	_defaults_button.pressed.connect(press_defaults)
	_cancel_button = _make_button(self, "CancelButton", CANCEL_TEXT, Vector2(x0 + FOOTER_BUTTON_SIZE.x + FOOTER_BUTTON_GAP, FOOTER_BUTTON_Y), FOOTER_BUTTON_SIZE)
	_cancel_button.pressed.connect(cancel)
	_save_button = _make_button(self, "SaveButton", SAVE_TEXT, Vector2(x0 + (FOOTER_BUTTON_SIZE.x + FOOTER_BUTTON_GAP) * 2.0, FOOTER_BUTTON_Y), FOOTER_BUTTON_SIZE)
	_save_button.pressed.connect(save)


## 버튼을 만들어 parent에 넣는다. 크기는 트리에 넣은 뒤에 정한다 (넣기 전에 정하면 기본 글꼴 기준 최소 크기로 커져서 남는다).
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

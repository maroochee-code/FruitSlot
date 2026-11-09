extends Control
## 3단계 메인 화면. COIN/BET/START 입력을 GameState에 전달하고, GameState의 시그널을 받아 화면을 갱신한다.
## 결과는 로직이 정한다. 이 스크립트는 그 값을 표시만 하며 크레딧·베팅 같은 상태를 직접 바꾸지 않는다.

# --- 화면 배치 (640×480 기준) ---
const REEL_COLS: int = 3
const REEL_ROWS: int = 3
## 6-B: 아트 좌표(213×160) × 3. 보드 외곽 (42,36) 348×276, 칸 108×84 (간격 없음), 첫 칸 (54,48).
const BOARD_ORIGIN: Vector2 = Vector2(42, 36)
const CELL_SIZE: Vector2 = Vector2(108, 84)
const CELL_GAP: float = 0.0
const REEL_ORIGIN: Vector2 = Vector2(54, 48)
## STOP 버튼은 칸 아래(보드 아래끝 312 밑)에서 칸 가운데에 맞춘다.
const STOP_SLOT_Y: float = 318.0
const STOP_SLOT_SIZE: Vector2 = Vector2(96, 33)
const BUTTON_ROW_Y: float = 376.0
const BUTTON_SIZE: Vector2 = Vector2(76, 32)
const START_BUTTON_SIZE: Vector2 = Vector2(100, 32)
const BUTTON_GAP: float = 4.0
const BUTTON_FONT_SIZE: int = 13
const TITLE_RECT: Rect2 = Rect2(468, 8, 168, 48)
const POOL_RECT: Rect2 = Rect2(468, 62, 168, 48)
const FEVER_RECT: Rect2 = Rect2(468, 116, 168, 140)
const PAYTABLE_RECT: Rect2 = Rect2(468, 260, 168, 156)
## 디버그 창은 화면 오른쪽 절반을 덮는다 (글자가 잘리지 않도록 넓게)
const DEBUG_RECT: Rect2 = Rect2(300, 4, 336, 412)
const BOTTOM_Y: float = 420.0
const BOTTOM_H: float = 56.0
const CREDIT_RECT: Rect2 = Rect2(4, BOTTOM_Y, 140, BOTTOM_H)
const NOTICE_RECT: Rect2 = Rect2(148, BOTTOM_Y, 220, BOTTOM_H)
const WIN_RECT: Rect2 = Rect2(372, BOTTOM_Y, 124, BOTTOM_H)
const BET_RECT: Rect2 = Rect2(500, BOTTOM_Y, 136, BOTTOM_H)
const BIG_FONT_SIZE: int = 24
const POOL_FONT_SIZE: int = 22
const NOTICE_FONT_SIZE: int = 11
const PLACEHOLDER_BG: Color = Color("1A1A22")
const PLACEHOLDER_BORDER: Color = Color("3A3A48")
const PLACEHOLDER_TEXT: Color = Color("6A6A7A")
const PLACEHOLDER_FONT_SIZE: int = 10
const BACKGROUND_COLOR: Color = Color("0C0C14")
const CREDIT_COLOR: Color = Color("7CFF9A")
const WIN_COLOR: Color = Color("FFD700")
## POOL 숫자 색 3단계: 주황(기본) → 노랑(pool_yellow_from 이상) → 빨강+깜빡임(pool_red_from 이상). 기준 숫자는 feel.json
const POOL_COLOR: Color = Color("FFB040")
const POOL_COLOR_YELLOW: Color = Color("FFE94A")
const POOL_COLOR_RED: Color = Color("FF4040")
const POOL_COLOR_RED_DIM: Color = Color("8A2222")
const POOL_TIER_NORMAL: int = 0
const POOL_TIER_YELLOW: int = 1
const POOL_TIER_RED: int = 2
## 깜빡임 한 주기(초). 절반은 켜짐, 절반은 꺼짐. 피버 카운터 마지막 1회 깜빡임과 POOL 빨강 단계가 함께 쓴다.
const BLINK_PERIOD: float = 0.8
## feel.json 수정 시각을 확인하는 간격 (초)
const FEEL_POLL_SEC: float = 0.5
## 한글이 깨지지 않도록 시스템 한글 글꼴을 우선 지정
const FONT_NAMES: PackedStringArray = ["Malgun Gothic", "맑은 고딕", "Noto Sans CJK KR", "Apple SD Gothic Neo", "sans-serif"]

var _data: BalanceData
## 지금 도는(또는 마지막으로 돈) 스핀이 쓰는 손맛 설정. 스핀 시작 때만 바뀐다.
var _feel: FeelConfig
## 파일에서 가장 최근에 읽은 설정. 다음 START에서 _feel이 된다.
var _latest_feel: FeelConfig
var _feel_path: String = FeelConfig.DEFAULT_PATH
var _feel_mtime: int = 0
var _feel_poll_left: float = FEEL_POLL_SEC
var _reels: Array[ReelView] = []
var _spin: SpinController
var _stop_buttons: Array[Button] = []
## 마지막 릴이 멈춘 뒤 정산까지 남은 시간 (정산 대기 중일 때만)
var _settle_left: float = 0.0
var _settling: bool = false
var _cells: Array[Array] = []
var _overlay: LineOverlay
var _debug: DebugPanel
var _debug_visible: bool = false
var _last_result: SpinResult
## 거절·당첨 같은 일회성 안내. 비어 있으면 상태에 맞는 기본 안내를 보여준다.
var _notice_override: String = ""
var _credit_box: InfoBox
var _notice_box: InfoBox
var _win_box: InfoBox
var _bet_box: InfoBox
var _pool_box: InfoBox
var _fever_panel: FeverPanel
var _fever_overlay: FeverOverlay
## 지금 연출 중인 피버 단계 목록과, 그동안 카운터 패널에 보여 주는 숫자 (피버 심볼은 0에서 시작해 단계가 끝나면 초기값)
var _fever_steps: Array[Dictionary] = []
var _fever_counts_shown: Dictionary[String, int] = {}
## 이번 스핀의 당첨 선을 이미 켰는지 (피버 연출 전에 먼저 켠다)
var _wins_shown: bool = false
## 깜빡임 시계(초)와 지금 켜짐인지
var _blink_time: float = 0.0
var _blink_on: bool = false
## 지금 화면에 표시 중인 POOL 숫자
var _pool_shown: int = 0
var _paytable: PaytablePanel
var _bet_button: Button
var _max_bet_button: Button
var _cancel_button: Button
var _start_button: Button


func _ready() -> void:
	_apply_font()
	if not GameState.ready_ok:
		push_error("main: GameState 초기화 실패")
		return
	_data = GameState.get_balance()
	_feel = FeelConfig.load_from_file()
	_latest_feel = _feel
	set_feel_path(FeelConfig.DEFAULT_PATH)
	_build_background()
	_build_board()
	_build_reels()
	_build_overlay()
	_build_placeholders()
	_build_info_boxes()
	_build_buttons()
	_build_stop_buttons()
	_build_debug()
	_connect_state()
	GameState.refresh()
	_refresh_side_panel(GameState.get_pool(), GameState.get_fever_counts())
	_refresh_buttons()


func _process(delta: float) -> void:
	advance(delta)
	_feel_poll_left -= delta
	if _feel_poll_left <= 0.0:
		_feel_poll_left = FEEL_POLL_SEC
		poll_feel_file()


## 감시할 feel 파일을 정하고 현재 수정 시각을 기억한다.
func set_feel_path(path: String) -> void:
	_feel_path = path
	_feel_mtime = FileAccess.get_modified_time(path)


## 파일 수정 시각이 바뀌었으면 다시 읽는다. 다시 읽었으면 true.
func poll_feel_file() -> bool:
	var mtime: int = FileAccess.get_modified_time(_feel_path)
	if mtime == _feel_mtime:
		return false
	_feel_mtime = mtime
	return reload_feel()


## feel 파일을 다시 읽어 "다음 스핀부터 쓸 설정"으로 보관한다. 진행 중인 스핀에는 영향이 없다.
## 파일이 깨져서 못 읽으면 이전 설정을 그대로 두고 false를 돌려준다.
func reload_feel() -> bool:
	var loaded: FeelConfig = FeelConfig.load_from_file(_feel_path, false)
	if not loaded.file_ok:
		_announce_feel("feel.json을 읽지 못해 이전 값을 유지합니다. (파일을 확인하세요)")
		return false
	_latest_feel = loaded
	var message: String = "feel.json 다시 읽음: 다음 스핀부터 적용"
	if not loaded.errors.is_empty():
		message += "\n문제 %d개는 기본값으로 대체: %s" % [loaded.errors.size(), loaded.errors[0]]
	_announce_feel(message)
	return true


func _announce_feel(message: String) -> void:
	print("[feel] ", message.replace("\n", " / "))
	if not GameState.spinning:
		_notice_override = message
		_refresh_notice()


## 시간을 delta초 진행한다. 릴 움직임, 자동 정지, 정산 대기를 처리한다. (테스트는 이걸 직접 부른다.)
func advance(delta: float) -> void:
	_advance_blink(delta)
	if _spin.is_active():
		_spin.advance(delta)
		for reel: ReelView in _reels:
			reel.refresh()
	if _fever_overlay.is_playing():
		_fever_overlay.advance(delta)
	if _settling:
		_settle_left -= delta
		if _settle_left <= 0.0:
			_settle_now()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_C:
			GameState.insert_coin()
		KEY_B:
			GameState.raise_bet()
		KEY_M:
			GameState.max_bet()
		KEY_X:
			GameState.cancel_bet()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			do_spin()
		KEY_1, KEY_KP_1:
			press_stop(0)
		KEY_2, KEY_KP_2:
			press_stop(1)
		KEY_3, KEY_KP_3:
			press_stop(2)
		KEY_F1:
			toggle_debug()
		KEY_F6:
			reload_feel()


## START. 멈춰 있으면 크레딧 차감 + 결과 확정(GameState), 릴이 돌고 있으면 남은 릴을 차례로 정지시킨다.
## 새 스핀이 시작됐을 때만 결과를 돌려준다.
func do_spin() -> SpinResult:
	# 피버 연출 중 START(스페이스)는 연출 건너뛰기. 숫자는 연출이 끝날 때 똑같이 반영된다.
	if _fever_overlay.is_playing():
		_fever_overlay.skip()
		return null
	if GameState.spinning:
		if _spin.press_quick_stop():
			_refresh_buttons()
		return null
	return GameState.start_spin()


## STOP 1/2/3 (index 0~2). 받아들여지면 true.
func press_stop(index: int) -> bool:
	var accepted: bool = _spin.press_stop(index)
	_refresh_buttons()
	return accepted


## 깜빡임 시계를 진행한다. 켜짐/꺼짐이 바뀔 때만 화면을 고친다.
func _advance_blink(delta: float) -> void:
	_blink_time = fmod(_blink_time + delta, BLINK_PERIOD)
	var on: bool = _blink_time >= BLINK_PERIOD / 2.0
	if on == _blink_on:
		return
	_blink_on = on
	_fever_panel.set_blink(on)
	_refresh_pool_color()


## POOL 숫자의 색 단계 (POOL_TIER_*). 기준 숫자는 지금 스핀이 쓰는 손맛 설정(_feel)에서 읽는다.
func pool_tier(pool: int) -> int:
	if float(pool) >= _feel.pool_red_from:
		return POOL_TIER_RED
	if float(pool) >= _feel.pool_yellow_from:
		return POOL_TIER_YELLOW
	return POOL_TIER_NORMAL


func _refresh_pool_color() -> void:
	match pool_tier(_pool_shown):
		POOL_TIER_RED:
			_pool_box.set_value_color(POOL_COLOR_RED if _blink_on else POOL_COLOR_RED_DIM)
		POOL_TIER_YELLOW:
			_pool_box.set_value_color(POOL_COLOR_YELLOW)
		_:
			_pool_box.set_value_color(POOL_COLOR)


## 릴 index(0~2)의 화면 노드 (테스트용)
func reel_view(index: int) -> ReelView:
	return _reels[index]


## 스핀 진행 관리자 (테스트용: 릴이 출발했는지 등을 본다)
func spin_controller() -> SpinController:
	return _spin


## 지금 스핀이 쓰는 손맛 설정
func feel() -> FeelConfig:
	return _feel


## 다음 스핀부터 쓸 손맛 설정 (파일에서 가장 최근에 읽은 것)
func pending_feel() -> FeelConfig:
	return _latest_feel


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


func _connect_state() -> void:
	GameState.credit_changed.connect(_on_credit_changed)
	GameState.bet_changed.connect(_on_bet_changed)
	GameState.win_changed.connect(_on_win_changed)
	GameState.coin_inserted.connect(_on_coin_inserted)
	GameState.action_rejected.connect(_on_action_rejected)
	GameState.spin_started.connect(_on_spin_started)
	GameState.spin_finished.connect(_on_spin_finished)
	_spin.reel_started.connect(_on_reel_started)
	_spin.reel_stopped.connect(_on_reel_stopped)
	_spin.all_stopped.connect(_on_all_stopped)


func _on_credit_changed(credit: int) -> void:
	_credit_box.set_value(str(credit))
	_refresh_buttons()
	_refresh_notice()


func _on_bet_changed(total_bet: int, line_bets: PackedInt32Array) -> void:
	_bet_box.set_value(str(total_bet))
	_overlay.update_bets(line_bets)
	_overlay.clear_wins()
	_notice_override = ""
	_refresh_buttons()
	_refresh_notice()


func _on_win_changed(win: int) -> void:
	_win_box.set_value(str(win))


func _on_coin_inserted(_amount: int) -> void:
	_notice_override = ""


func _on_action_rejected(reason: StringName) -> void:
	if reason == GameState.REASON_NO_CREDIT:
		_notice_override = "크레딧이 없습니다. COIN(C)을 누르세요."
	elif reason == GameState.REASON_NO_BET:
		_notice_override = "BET(B)을 눌러 베팅하세요."
	elif reason == GameState.REASON_BET_OVER_CREDIT:
		_notice_override = "크레딧이 부족해 BET을 더 올릴 수 없습니다."
	_refresh_notice()


## START 직후: 결과는 이미 정해졌다. 릴만 돌리고, 숫자(WIN·POOL·피버)는 정지 후에 보여준다.
func _on_spin_started(result: SpinResult) -> void:
	_last_result = result
	_overlay.clear_wins()
	_wins_shown = false
	_notice_override = ""
	_settling = false
	# 새 손맛 설정은 여기서만 받아들인다. 이 스핀은 끝까지 이 설정 한 벌로 움직인다.
	_feel = _latest_feel
	_spin.begin(result.stops, _feel)
	_refresh_buttons()
	_refresh_notice()


## 릴이 출발하면 그 릴의 STOP 버튼이 켜진다 (출발 지연 중에는 꺼져 있음)
func _on_reel_started(_index: int) -> void:
	_refresh_buttons()


func _on_reel_stopped(index: int) -> void:
	_reels[index].refresh()
	_refresh_buttons()


## 세 릴이 모두 멈춤: 잠시 뒤(result_delay) 정산하고 당첨 연출을 시작한다.
func _on_all_stopped() -> void:
	_settle_left = _feel.result_delay
	_settling = true
	if _settle_left <= 0.0:
		_settle_now()


## 릴이 멈추고 result_delay가 지난 시점. 당첨 선을 먼저 켜고, 피버가 있으면 오버레이 연출을 한 뒤에 정산한다.
## 피버가 없으면 곧바로 정산한다. 정산(크레딧·WIN·POOL·카운터 반영)은 항상 한 번, 연출이 끝난 뒤에만 일어난다.
func _settle_now() -> void:
	_settling = false
	_overlay.show_wins(_last_result.line_wins)
	_wins_shown = true
	_fever_steps = FeverOverlay.build_steps(_last_result, _data)
	if _fever_steps.is_empty():
		GameState.settle_spin()
		return
	_start_fever_show()


func _start_fever_show() -> void:
	_fever_counts_shown = _last_result.fever_counts_after.duplicate()
	for step: Dictionary in _fever_steps:
		if step["kind"] == FeverOverlay.KIND_FEVER:
			_fever_counts_shown[step["symbol"]] = 0
	_fever_panel.set_counts(_fever_counts_shown)
	_notice_override = ""
	# 이번 스핀이 쓰는 설정(_feel)으로 재생 → 연출 도중 feel.json을 바꿔도 이번 연출은 그대로
	_fever_overlay.play(_fever_steps, _feel.fever_overlay_sec, _feel.fever_step_gap, _feel.fever_skip_lock_sec, _feel.pool_overlay_sec)
	_refresh_buttons()
	_refresh_notice()


## 피버 단계 하나가 끝나면 그 심볼의 카운터를 초기값(스핀 결과의 스냅샷)으로 되돌려 보여 준다.
## 풀 획득 단계가 끝나면 POOL 숫자를 스핀 후 값(초기값)으로 되돌려 보여 준다. 크레딧·WIN은 아직 그대로다.
func _on_fever_step_finished(index: int) -> void:
	var step: Dictionary = _fever_steps[index]
	if step["kind"] == FeverOverlay.KIND_POOL:
		_pool_shown = _last_result.pool_after
		_pool_box.set_value(str(_pool_shown))
		_refresh_pool_color()
		return
	var symbol: String = step["symbol"]
	_fever_counts_shown[symbol] = _last_result.fever_counts_after[symbol]
	_fever_panel.set_counts(_fever_counts_shown)


func _on_fever_finished(_skipped: bool) -> void:
	GameState.settle_spin()


## 피버 연출이 재생 중인가 (테스트용)
func fever_playing() -> bool:
	return _fever_overlay.is_playing()


func _on_spin_finished(result: SpinResult, lowered_from: int) -> void:
	_last_result = result
	if not _wins_shown:
		_overlay.show_wins(result.line_wins)
		_wins_shown = true
	_refresh_side_panel(result.pool_after, result.fever_counts_after)
	_notice_override = _build_result_notice(result, lowered_from)
	_debug.show_result(result, _data, grid_matches_logic(), GameState.credit)
	_refresh_buttons()
	_refresh_notice()


func _build_result_notice(result: SpinResult, lowered_from: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if result.total_payout() > 0:
		parts.append("당첨 %d = 라인 %d + 피버 %d + 풀 %d" % [result.total_payout(), result.line_payout, result.fever_bonus, result.pool_won])
	if lowered_from > 0:
		parts.append("크레딧이 부족해 BET을 %d → %d로 낮췄습니다." % [lowered_from, GameState.bet])
	return "\n".join(parts)


## 안내 문구: (일회성 안내 또는 상태 안내) + BET 8 미만이면 피버 안내
func _refresh_notice() -> void:
	var lines: PackedStringArray = PackedStringArray()
	if not _notice_override.is_empty():
		lines.append(_notice_override)
	elif _fever_overlay.is_playing():
		lines.append("피버 발동! 스페이스로 연출을 건너뛸 수 있습니다.")
	elif GameState.spinning:
		lines.append("STOP 1·2·3 또는 START로 릴을 멈추세요.")
	elif GameState.credit < 1:
		lines.append("COIN(C)으로 크레딧을 넣으세요.")
	elif GameState.bet < 1:
		lines.append("BET(B)으로 베팅하세요.")
	if GameState.bet < _data.fever_min_total_bet:
		lines.append("BET %d 이상이면 피버 적립" % _data.fever_min_total_bet)
	_notice_box.set_value("\n".join(lines))


func _refresh_buttons() -> void:
	_bet_button.disabled = not GameState.can_raise_bet()
	_max_bet_button.disabled = not GameState.can_max_bet()
	_cancel_button.disabled = not GameState.can_cancel_bet()
	# 회전 중에는 START가 "남은 릴 차례로 정지" 역할을 하므로 정지시킬 릴이 남아 있으면 켠다.
	# 피버 연출 중에는 START(스페이스)가 "연출 건너뛰기"라서 켠다.
	_start_button.disabled = not (GameState.can_start() or _spin.can_quick_stop() or _fever_overlay.is_playing())
	for i: int in _stop_buttons.size():
		_stop_buttons[i].disabled = not _spin.can_stop(i)


## 오른쪽 패널: POOL 숫자(색 단계)와 피버 카운터. 스핀 결과의 스냅샷을 받아 정지 후에만 갱신한다.
## (피버 발동·풀 획득 연출은 5-B, 5-C)
func _refresh_side_panel(pool: int, counts: Dictionary[String, int]) -> void:
	_pool_shown = pool
	_pool_box.set_value(str(pool))
	_refresh_pool_color()
	_fever_panel.set_counts(counts)


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


func _build_board() -> void:
	var board: BoardView = BoardView.new()
	board.name = "Board"
	board.position = BOARD_ORIGIN
	add_child(board)


func _build_reels() -> void:
	var holder: Control = Control.new()
	holder.name = "Reels"
	add_child(holder)
	var motions: Array[ReelMotion] = []
	for col: int in REEL_COLS:
		var strip: PackedStringArray = _data.reels[col]
		var motion: ReelMotion = ReelMotion.new(strip.size(), _feel)
		var reel: ReelView = ReelView.new()
		reel.name = "Reel%d" % (col + 1)
		reel.position = REEL_ORIGIN + Vector2(col * (CELL_SIZE.x + CELL_GAP), 0.0)
		holder.add_child(reel)
		reel.setup(strip, motion, CELL_SIZE, CELL_GAP, REEL_ROWS)
		var column: Array = []
		for row: int in REEL_ROWS:
			column.append(reel.cell_at(row))
		_cells.append(column)
		_reels.append(reel)
		motions.append(motion)
	_spin = SpinController.new(motions, _feel)


func _build_overlay() -> void:
	_overlay = LineOverlay.new()
	_overlay.name = "LineOverlay"
	add_child(_overlay)
	_overlay.setup(_data, _cells, REEL_ORIGIN, CELL_SIZE, CELL_GAP)


## 아직 기능이 없는 자리 (타이틀은 6단계)
func _build_placeholders() -> void:
	_add_placeholder("Title", "타이틀", TITLE_RECT)


## 릴 아래 STOP 1/2/3 버튼
func _build_stop_buttons() -> void:
	for col: int in REEL_COLS:
		var x: float = REEL_ORIGIN.x + col * (CELL_SIZE.x + CELL_GAP) + (CELL_SIZE.x - STOP_SLOT_SIZE.x) / 2.0
		var button: Button = _make_button("StopButton%d" % (col + 1), "STOP %d" % (col + 1), Rect2(Vector2(x, STOP_SLOT_Y), STOP_SLOT_SIZE))
		button.pressed.connect(press_stop.bind(col))
		_stop_buttons.append(button)


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


func _build_info_boxes() -> void:
	_credit_box = _add_box(InfoBox.new("CreditBox", "CREDIT", CREDIT_RECT, BIG_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	_credit_box.set_value_color(CREDIT_COLOR)
	_notice_box = _add_box(InfoBox.new("NoticeBox", "", NOTICE_RECT, NOTICE_FONT_SIZE, HORIZONTAL_ALIGNMENT_LEFT, true, false))
	_win_box = _add_box(InfoBox.new("WinBox", "WIN", WIN_RECT, BIG_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	_win_box.set_value_color(WIN_COLOR)
	_bet_box = _add_box(InfoBox.new("BetBox", "BET", BET_RECT, BIG_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	_pool_box = _add_box(InfoBox.new("PoolBox", "POOL", POOL_RECT, POOL_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	_pool_box.set_value_color(POOL_COLOR)
	_fever_panel = FeverPanel.new("FeverBox", FEVER_RECT)
	add_child(_fever_panel)
	_fever_panel.setup(_data)
	_paytable = PaytablePanel.new("PaytablePanel", PAYTABLE_RECT)
	add_child(_paytable)
	_paytable.setup(_data)


func _add_box(box: InfoBox) -> InfoBox:
	add_child(box)
	return box


## 버튼 한 줄: CANCEL | COIN | START | BET | MAX BET (릴 가운데 기준으로 가운데 정렬)
func _build_buttons() -> void:
	var reels_width: float = REEL_COLS * CELL_SIZE.x + (REEL_COLS - 1) * CELL_GAP
	var center_x: float = REEL_ORIGIN.x + reels_width / 2.0
	var row_width: float = BUTTON_SIZE.x * 4.0 + START_BUTTON_SIZE.x + BUTTON_GAP * 4.0
	var x: float = center_x - row_width / 2.0
	_cancel_button = _make_button("CancelButton", "CANCEL", Rect2(Vector2(x, BUTTON_ROW_Y), BUTTON_SIZE))
	_cancel_button.pressed.connect(GameState.cancel_bet)
	x += BUTTON_SIZE.x + BUTTON_GAP
	var coin: Button = _make_button("CoinButton", "COIN", Rect2(Vector2(x, BUTTON_ROW_Y), BUTTON_SIZE))
	coin.pressed.connect(GameState.insert_coin)
	x += BUTTON_SIZE.x + BUTTON_GAP
	_start_button = _make_button("StartButton", "START", Rect2(Vector2(x, BUTTON_ROW_Y), START_BUTTON_SIZE))
	_start_button.pressed.connect(do_spin)
	x += START_BUTTON_SIZE.x + BUTTON_GAP
	_bet_button = _make_button("BetButton", "BET", Rect2(Vector2(x, BUTTON_ROW_Y), BUTTON_SIZE))
	_bet_button.pressed.connect(GameState.raise_bet)
	x += BUTTON_SIZE.x + BUTTON_GAP
	_max_bet_button = _make_button("MaxBetButton", "MAX BET", Rect2(Vector2(x, BUTTON_ROW_Y), BUTTON_SIZE))
	_max_bet_button.pressed.connect(GameState.max_bet)


func _make_button(node_name: String, text: String, rect: Rect2) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.position = rect.position
	button.size = rect.size
	# 스페이스·엔터가 버튼 클릭으로 한 번 더 처리되지 않게 한다.
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	add_child(button)
	return button


func _build_debug() -> void:
	_debug = DebugPanel.new()
	_debug.name = "DebugPanel"
	_debug.position = DEBUG_RECT.position
	_debug.size = DEBUG_RECT.size
	_debug.clip_contents = true
	_debug.visible = _debug_visible
	add_child(_debug)
	# 피버 오버레이는 가장 위(디버그 창보다도 위)에 둔다
	_fever_overlay = FeverOverlay.new()
	add_child(_fever_overlay)
	_fever_overlay.step_finished.connect(_on_fever_step_finished)
	_fever_overlay.finished.connect(_on_fever_finished)

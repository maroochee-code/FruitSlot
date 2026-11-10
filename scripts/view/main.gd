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
## AUTO 토글 버튼: STOP 3과 오른쪽 패널 사이 (아트 x=128, y=106, 20×11)
const AUTO_RECT: Rect2 = Rect2(384, 318, 60, 33)
## AUTO 해제 이유 → 일회성 안내 문구
const AUTO_STOP_NOTICES: Dictionary = {
	AutoSpin.REASON_USER: "AUTO를 해제했습니다. 진행 중인 판까지만 진행합니다.",
	AutoSpin.REASON_NO_CREDIT: "크레딧이 부족해 AUTO를 해제했습니다.",
	AutoSpin.REASON_BIG_WIN: "큰 당첨! AUTO를 해제했습니다.",
}
## 하단 버튼 줄: 어두운 띠 위에 CANCEL / COIN / START / BET / MAX BET (6-C, 640×480 기준)
const BUTTON_STRIP_RECT: Rect2 = Rect2(6, 354, 444, 48)
const BUTTON_STRIP_COLOR: Color = Color("0e1130")
const BUTTON_Y: float = 360.0
const BUTTON_SIZE: Vector2 = Vector2(81, 36)
const BUTTON_XS: Array[float] = [15.0, 102.0, 189.0, 276.0, 363.0]
## 글자 크기는 갈무리11 원래 크기(12)의 정수배
const BUTTON_FONT_MULTIPLE: int = 1
## 오른쪽 패널 (x=450, 폭 180)
const TITLE_RECT: Rect2 = Rect2(450, 9, 180, 72)
const POOL_RECT: Rect2 = Rect2(450, 87, 180, 42)
const FEVER_RECT: Rect2 = Rect2(450, 135, 180, 132)
const PAYTABLE_RECT: Rect2 = Rect2(450, 273, 180, 138)
## 디버그 창은 화면 오른쪽 절반을 덮는다 (하단 표시창 y=414 위에서 끝나도록 높이 406)
const DEBUG_RECT: Rect2 = Rect2(300, 4, 336, 406)
## 하단 표시창 (y=414, 높이 57)
const BOTTOM_Y: float = 414.0
const BOTTOM_H: float = 57.0
const CREDIT_RECT: Rect2 = Rect2(9, BOTTOM_Y, 150, BOTTOM_H)
const NOTICE_RECT: Rect2 = Rect2(165, BOTTOM_Y, 264, BOTTOM_H)
const WIN_RECT: Rect2 = Rect2(435, BOTTOM_Y, 96, BOTTOM_H)
const BET_RECT: Rect2 = Rect2(537, BOTTOM_Y, 93, BOTTOM_H)
## 큰 숫자 = 갈무리11(12) ×2 = 24, 안내 글자 = 갈무리11 ×1 = 12
const BIG_FONT_SIZE: int = 24
const POOL_FONT_SIZE: int = 24
const NOTICE_FONT_SIZE: int = 12
## 6-D: 벽지 뒤 바탕색(벽지 타일이 못 덮는 곳과 프레임 오른쪽 1px용)은 벽지 어두운 톤과 같게
const BACKGROUND_COLOR: Color = Color("1f6f8b")
const WALLPAPER_PATH: String = UiSkin.UI_DIR + "wallpaper_tile.png"
const FRAME_PATH: String = UiSkin.UI_DIR + "frame.png"
const LOGO_PATH: String = UiSkin.UI_DIR + "logo.png"
const CREDIT_COLOR: Color = Color("7dff9a")
const WIN_COLOR: Color = Color("ffe14d")
## POOL 숫자 색 3단계: 주황(기본) → 노랑(pool_yellow_from 이상) → 빨강+깜빡임(pool_red_from 이상). 기준 숫자는 feel.json
const POOL_COLOR: Color = Color("ff9a1f")
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
## COIN을 쓸 수 없을 때(릴리즈 빌드 등) 크레딧이 없다는 안내
const NO_CREDIT_NOTICE: String = "크레딧이 부족합니다."

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
## 전구 (6-F3a): 보드 링과 프레임 소켓. 대기/스핀/당첨/피버 모양은 BulbPattern 규칙
var _board: BoardView
var _frame_bulbs: FrameBulbs
## 당첨·피버 전구 모양을 보여 줄 남은 시간 (이 시간이 지나면 대기 모양으로 돌아감)
var _bulb_hold_left: float = 0.0
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
var _auto_button: Button
var _coin_button: Button
## GAME OVER 화면 (7-B). 크레딧이 0이 된 판의 연출이 끝나고 gameover_delay_sec가 지나면 뜬다.
var _game_over: GameOverOverlay
## GameState.game_over를 받았지만 아직 화면을 띄우지 않았는지, 띄우기까지 남은 시간 (연출이 끝난 뒤부터 센다)
var _game_over_pending: bool = false
var _game_over_delay_left: float = 0.0
## 효과음 (6-F1). 소리는 이미 정해진 결과를 알려 주기만 한다.
var _sound: SoundBank
## BGM (6-F2). 피버 연출이 시작되면 피버 곡, 끝나면 메인 곡 (건너뛰어도 한 쌍)
var _bgm: BgmPlayer
## 피버 연출을 건너뛰는 중인지 (건너뛸 때 한꺼번에 나가는 단계 시작 알림에는 소리를 내지 않는다)
var _skipping_fever: bool = false
## 소리를 낼 때 쓰는 "AUTO가 켜져 있던가" (판마다 오는 auto_changed에는 소리를 내지 않는다)
var _auto_sound_on: bool = false
## 정산 연출 (6-F3b). false면 정산 숫자를 연출 없이 바로 반영한다 (기존 테스트용).
## 켜져 있으면 WIN·CREDIT 표시 숫자가 로직 값과 잠시 달라지고, 연출이 끝나면(또는 건너뛰면) 같아진다.
var settle_presentation: bool = true
var _settle: SettleShow
## GameState.settle_spin()을 부르는 동안 true (이때 오는 크레딧·WIN 변화는 연출이 대신 보여 준다)
var _in_settle_call: bool = false


func _ready() -> void:
	_apply_theme()
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
	_build_title_frame()
	_build_info_boxes()
	_build_buttons()
	_build_stop_buttons()
	_build_settle_show()
	_build_debug()
	_build_game_over()
	_build_sound()
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
	_bgm.advance(delta)
	_settle.advance(delta)
	_game_over.advance(delta)
	_advance_bulbs(delta)
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
	# AUTO 대기는 정산 연출이 끝난 뒤부터 센다 (연출 중에는 시간을 흘리지 않는다)
	if not _settle.is_active():
		GameState.auto_advance(delta)
	_advance_game_over(delta)


## GAME OVER 화면을 띄울 때를 기다린다. 회전·정산 대기·정산 연출·피버 연출이 모두 끝난 뒤부터 gameover_delay_sec를 센다.
## 기다리는 동안 크레딧이 생겨 GAME OVER가 풀렸으면(개발 빌드 COIN 등) 취소한다.
func _advance_game_over(delta: float) -> void:
	if not _game_over_pending:
		return
	if not GameState.is_game_over():
		_game_over_pending = false
		return
	if GameState.spinning or _settling or _settle.is_active() or _fever_overlay.is_playing():
		return
	_game_over_delay_left -= delta
	if _game_over_delay_left <= 0.0:
		_show_game_over()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# GAME OVER 화면이 떠 있는 동안은 화면용 키(←/→/스페이스/엔터)와 개발용 F1·F6만 받는다
	if _game_over.is_open():
		_handle_game_over_key(key)
		return
	match key.keycode:
		KEY_C:
			press_coin()
		KEY_B:
			press_bet()
		KEY_M:
			press_max_bet()
		KEY_X:
			press_cancel()
		KEY_A:
			press_auto()
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


## GAME OVER 화면이 떠 있을 때의 키 처리
func _handle_game_over_key(key: InputEventKey) -> void:
	match key.keycode:
		KEY_LEFT:
			_game_over.move(-1)
		KEY_RIGHT:
			_game_over.move(1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_game_over.confirm()
		KEY_F1:
			toggle_debug()
		KEY_F6:
			reload_feel()


## COIN (버튼·C 키). 개발 빌드(coin_allowed)에서만 동작하고, GAME OVER 화면이 떠 있는 동안은 무효다.
func press_coin() -> void:
	if _game_over.is_open() or not GameState.coin_allowed():
		return
	GameState.insert_coin()


## AUTO 켜기/끄기 (버튼·A 키). GAME OVER 화면이 떠 있는 동안은 무효다.
func press_auto() -> void:
	if _game_over.is_open():
		return
	GameState.toggle_auto()


## BET +1 (버튼·B 키). 받아들여지면 true이고 BET 소리가 난다. 거절은 GameState의 action_rejected로 알려진다.
func press_bet() -> bool:
	if _game_over.is_open():
		return false
	var accepted: bool = GameState.raise_bet()
	if accepted:
		_sound.play(SoundBank.NAME_BET)
	return accepted


## MAX BET (버튼·M 키)
func press_max_bet() -> bool:
	if _game_over.is_open():
		return false
	var accepted: bool = GameState.max_bet()
	if accepted:
		_sound.play(SoundBank.NAME_BET)
	return accepted


## CANCEL (버튼·X 키)
func press_cancel() -> bool:
	if _game_over.is_open():
		return false
	var accepted: bool = GameState.cancel_bet()
	if accepted:
		_sound.play(SoundBank.NAME_CANCEL)
	return accepted


## 효과음 도우미 (테스트용)
func sound_bank() -> SoundBank:
	return _sound


## 전구 모양을 바꾼다. hold_sec > 0이면 그 시간이 지난 뒤 대기 모양으로 돌아간다.
func _set_bulb_mode(mode: int, hold_sec: float = 0.0) -> void:
	_bulb_hold_left = hold_sec
	_board.set_mode(mode)
	_frame_bulbs.set_mode(mode)


func _advance_bulbs(delta: float) -> void:
	_board.advance(delta)
	_frame_bulbs.advance(delta)
	if _bulb_hold_left <= 0.0:
		return
	_bulb_hold_left -= delta
	if _bulb_hold_left <= 0.0:
		_set_bulb_mode(BulbPattern.Mode.IDLE)


## 지금 전구 모양 (BulbPattern.Mode, 테스트용)
func bulb_mode() -> int:
	return _board.mode()


## 보드 링 / 프레임 소켓 (테스트용)
func board_view() -> BoardView:
	return _board


func frame_bulbs() -> FrameBulbs:
	return _frame_bulbs


## BGM 재생기 (테스트·미리보기용)
func bgm_player() -> BgmPlayer:
	return _bgm


## START. 멈춰 있으면 크레딧 차감 + 결과 확정(GameState), 릴이 돌고 있으면 남은 릴을 차례로 정지시킨다.
## 새 스핀이 시작됐을 때만 결과를 돌려준다.
func do_spin() -> SpinResult:
	# GAME OVER 화면이 떠 있는 동안 START(스페이스)는 화면의 결정 키라서 새 판을 시작하지 않는다
	if _game_over.is_open():
		return null
	# 피버 연출 중 START(스페이스)는 연출 건너뛰기. 숫자는 연출이 끝날 때 똑같이 반영된다.
	if _fever_overlay.is_playing():
		_skipping_fever = true
		_fever_overlay.skip()
		_skipping_fever = false
		return null
	# 정산 연출 중 START: 숫자를 최종값으로 확정하고 이어서 다음 판을 시작한다
	confirm_settle_show()
	if GameState.spinning:
		if _spin.press_quick_stop():
			_refresh_buttons()
		return null
	# AUTO 대기 중의 START는 "AUTO 끄기" (새 판을 시작하지 않는다)
	if GameState.auto_on:
		GameState.stop_auto(AutoSpin.REASON_USER)
		return null
	return GameState.start_spin()


## STOP 1/2/3 (index 0~2). 받아들여지면 true.
func press_stop(index: int) -> bool:
	if GameState.auto_on or _game_over.is_open():
		return false
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
	GameState.auto_changed.connect(_on_auto_changed)
	GameState.auto_stopped.connect(_on_auto_stopped)
	GameState.spin_started.connect(_on_spin_started)
	GameState.spin_finished.connect(_on_spin_finished)
	GameState.game_over.connect(_on_game_over)
	GameState.new_game_started.connect(_on_new_game_started)
	_spin.reel_started.connect(_on_reel_started)
	_spin.reel_stopped.connect(_on_reel_stopped)
	_spin.all_stopped.connect(_on_all_stopped)


## GAME OVER 화면이 열려 있는데 로직이 GAME OVER가 아니게 됐으면(CONTINUE·NEW GAME·크레딧 지급) 닫고 BGM을 이어서 튼다.
## 화면과 로직 상태가 어긋난 채로 남지 않게 하는 단일 지점이다.
func _sync_game_over_screen() -> void:
	if not _game_over.is_open() or GameState.is_game_over():
		return
	_game_over.close()
	_bgm.resume_music(_feel.bgm_gameover_fade_sec)


func _on_credit_changed(credit: int) -> void:
	_sync_game_over_screen()
	# 정산 때가 아닌 변화(COIN·다음 판 차감 등)가 연출 도중에 오면 연출 숫자를 먼저 최종값으로 확정한다
	if not _in_settle_call:
		confirm_settle_show()
	if not _holds_settle_numbers():
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
	if not _in_settle_call:
		confirm_settle_show()
	if not _holds_settle_numbers():
		_win_box.set_value(str(win))


## 정산 호출 중이고 연출이 켜져 있으면, 크레딧·WIN 숫자 반영은 연출이 맡는다
func _holds_settle_numbers() -> bool:
	return _in_settle_call and settle_presentation


## GameState.settle_spin()을 부르고, 당첨이 있으면 정산 연출을 시작한다
func _settle_game() -> void:
	_in_settle_call = true
	var result: SpinResult = GameState.settle_spin()
	_in_settle_call = false
	if result == null or not settle_presentation or result.total_payout() <= 0:
		return
	_start_settle_show(result)


func _start_settle_show(result: SpinResult) -> void:
	var tier: int = _settle_tier(result)
	var scale: float = _feel.auto_effect_scale if GameState.auto_on else 1.0
	var payout: int = result.total_payout()
	_settle.start(payout, GameState.credit - payout, _feel.countup_sec(tier) * scale, _feel.coin_count(tier), _feel.coin_fly_sec * scale, _feel.countup_tick_sec, WIN_RECT.get_center(), CREDIT_RECT.get_center())


## 당첨 크기 단계 (당첨 효과음 소/중/대와 같은 기준)
func _settle_tier(result: SpinResult) -> int:
	var sound_name: StringName = SoundBank.win_sound_for(result.total_payout(), result.total_bet, _feel.win_mid_ratio, _feel.win_big_ratio)
	if sound_name == SoundBank.NAME_WIN_BIG:
		return FeelConfig.TIER_BIG
	if sound_name == SoundBank.NAME_WIN_MID:
		return FeelConfig.TIER_MID
	return FeelConfig.TIER_SMALL


## 정산 연출 중이면 건너뛰고 WIN·CREDIT를 최종값으로 확정한다. 연출 중이 아니면 아무것도 하지 않는다.
func confirm_settle_show() -> void:
	_settle.finish_now()


## 정산 연출이 재생 중인가 (테스트용)
func settle_active() -> bool:
	return _settle.is_active()


func settle_show() -> SettleShow:
	return _settle


func _on_settle_win_shown(value: int) -> void:
	_win_box.set_value(str(value))


func _on_settle_credit_shown(value: int) -> void:
	_credit_box.set_value(str(value))


func _on_auto_changed(enabled: bool, _count: int) -> void:
	# 켜짐/꺼짐이 바뀔 때만 소리 (켜진 동안 판이 시작될 때마다도 이 시그널이 온다)
	if enabled != _auto_sound_on:
		_auto_sound_on = enabled
		_sound.play(SoundBank.NAME_BUTTON)
	_apply_auto_skin()
	_refresh_buttons()
	_refresh_notice()


## AUTO가 꺼진 이유를 일회성 문구로 보여 준다. 정산 때 꺼진 경우는 결과 문구 뒤에 붙는다 (GameState가 spin_finished 다음에 알려 준다).
func _on_auto_stopped(reason: StringName) -> void:
	var note: String = AUTO_STOP_NOTICES.get(reason, "")
	if note.is_empty():
		return
	_notice_override = note if _notice_override.is_empty() else _notice_override + "\n" + note
	_refresh_notice()


## 크레딧 0으로 정산됐다. 연출이 모두 끝난 뒤 gameover_delay_sec가 지나면 화면을 띄운다 (_advance_game_over).
func _on_game_over() -> void:
	_game_over_pending = true
	_game_over_delay_left = _feel.gameover_delay_sec


func _show_game_over() -> void:
	_game_over_pending = false
	_sound.play(SoundBank.NAME_GAMEOVER)
	_bgm.pause_music(_feel.bgm_gameover_fade_sec)
	_game_over.open(_data, GameState.get_pool(), GameState.get_fever_counts(), GameState.continues_left, GameState.continue_max, GameState.continue_credit, GameState.start_credit, _feel.gameover_input_lock_sec)
	_refresh_buttons()
	_refresh_notice()


## CONTINUE·NEW GAME이 받아들여졌을 때만 버튼 소리(button.wav)를 낸다
func _on_continue_pressed() -> void:
	if GameState.continue_game():
		_sound.play(SoundBank.NAME_BUTTON)


func _on_new_game_pressed() -> void:
	if GameState.new_game():
		_sound.play(SoundBank.NAME_BUTTON)


## NEW GAME(또는 시작): 오른쪽 패널(POOL·피버 카운터)과 당첨선을 처음 상태로 다시 그린다
func _on_new_game_started() -> void:
	_sync_game_over_screen()
	_game_over_pending = false
	_overlay.clear_wins()
	_notice_override = ""
	_refresh_side_panel(GameState.get_pool(), GameState.get_fever_counts())


func _on_coin_inserted(_amount: int) -> void:
	_notice_override = ""
	_sound.play(SoundBank.NAME_COIN)


func _on_action_rejected(reason: StringName) -> void:
	_sound.play(SoundBank.NAME_CANCEL)
	if reason == GameState.REASON_NO_CREDIT:
		_notice_override = "크레딧이 없습니다. COIN(C)을 누르세요." if GameState.coin_allowed() else NO_CREDIT_NOTICE
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
	_sound.set_sfx_volume_db(_feel.sfx_volume_db)
	_bgm.apply_feel(_feel)
	_board.apply_feel(_feel)
	_frame_bulbs.apply_feel(_feel)
	_set_bulb_mode(BulbPattern.Mode.SPIN)
	_sound.play(SoundBank.NAME_START)
	GameState.auto_gap_sec = _feel.auto_spin_gap_sec
	_spin.begin(result.stops, _feel)
	_refresh_buttons()
	_refresh_notice()


## 릴이 출발하면 그 릴의 STOP 버튼이 켜진다 (출발 지연 중에는 꺼져 있음)
func _on_reel_started(_index: int) -> void:
	_sound.play_loop(SoundBank.NAME_REEL_SPIN)
	_refresh_buttons()


func _on_reel_stopped(index: int) -> void:
	_sound.play(SoundBank.NAME_REEL_STOP)
	_reels[index].refresh()
	_refresh_buttons()


## 세 릴이 모두 멈춤: 잠시 뒤(result_delay) 정산하고 당첨 연출을 시작한다.
func _on_all_stopped() -> void:
	_sound.stop_loop(SoundBank.NAME_REEL_SPIN)
	_set_bulb_mode(BulbPattern.Mode.IDLE)
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
		# 당첨선이 깜빡이는 동안 전구도 번쩍인다 (피버·풀이 있으면 연출이 끝난 뒤 피버 전구)
		if not _last_result.line_wins.is_empty():
			_set_bulb_mode(BulbPattern.Mode.WIN, LineOverlay.blink_total_sec())
		# 피버·풀 연출이 없을 때만 당첨 크기 소리 (연출이 있으면 연출 소리가 당첨 소리다)
		var win_name: StringName = SoundBank.win_sound_for(_last_result.total_payout(), _last_result.total_bet, _feel.win_mid_ratio, _feel.win_big_ratio)
		if win_name != &"":
			_sound.play(win_name)
		_settle_game()
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
	_bgm.switch_to(BgmPlayer.TRACK_FEVER)
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


## 피버 단계가 시작될 때 소리. 건너뛰는 중에 한꺼번에 오는 알림은 무시한다.
func _on_fever_step_started(index: int) -> void:
	if _skipping_fever:
		return
	var is_pool: bool = _fever_steps[index]["kind"] == FeverOverlay.KIND_POOL
	_sound.play(SoundBank.NAME_POOL_GET if is_pool else SoundBank.NAME_FEVER_START)


func _on_fever_finished(skipped: bool) -> void:
	_bgm.switch_to(BgmPlayer.TRACK_MAIN)
	# 건너뛰면 재생 중인 연출 소리를 끊고 마무리음도 없다. 끝까지 봤을 때만 마무리음.
	if skipped:
		_sound.cut_oneshots()
	else:
		_sound.play(SoundBank.NAME_FEVER_END)
	_settle_game()
	# 연출 오버레이가 보드를 가리고 있었으므로 끝난 직후에 피버 전구. 정산 카운트업이 있으면 그 시간 동안 (없으면 당첨선 깜빡임 시간)
	var bulb_sec: float = _settle.total_sec() if _settle.is_active() else LineOverlay.blink_total_sec()
	_set_bulb_mode(BulbPattern.Mode.FEVER, bulb_sec)


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
	# AUTO 중에는 첫 줄에 "AUTO N회"를 고정한다
	if GameState.auto_on:
		lines.append("AUTO %d회" % GameState.auto_count())
	if not _notice_override.is_empty():
		lines.append(_notice_override)
	elif _fever_overlay.is_playing():
		lines.append("피버 발동! 스페이스로 연출을 건너뛸 수 있습니다.")
	elif GameState.spinning:
		if not GameState.auto_on:
			lines.append("STOP 1·2·3 또는 START로 릴을 멈추세요.")
	elif GameState.credit < 1:
		lines.append("COIN(C)으로 크레딧을 넣으세요." if GameState.coin_allowed() else NO_CREDIT_NOTICE)
	elif GameState.bet < 1:
		lines.append("BET(B)으로 베팅하세요.")
	if GameState.bet < _data.fever_min_total_bet and not GameState.auto_on:
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
		_stop_buttons[i].disabled = not _spin.can_stop(i) or GameState.auto_on
	_auto_button.disabled = not GameState.can_toggle_auto()
	# COIN은 개발 빌드(coin_allowed)에서만 켜지고, GAME OVER 화면이 떠 있는 동안은 꺼진다
	_coin_button.disabled = not GameState.coin_allowed() or _game_over.is_open()
	_debug.refresh_help(GameState.coin_allowed())


## 오른쪽 패널: POOL 숫자(색 단계)와 피버 카운터. 스핀 결과의 스냅샷을 받아 정지 후에만 갱신한다.
## (피버 발동·풀 획득 연출은 5-B, 5-C)
func _refresh_side_panel(pool: int, counts: Dictionary[String, int]) -> void:
	_pool_shown = pool
	_pool_box.set_value(str(pool))
	_refresh_pool_color()
	_fever_panel.set_counts(counts)


## 기본 테마: 갈무리 도트 폰트 + 버튼 3상태 그림 (UiSkin)
func _apply_theme() -> void:
	theme = UiSkin.make_theme()


func _build_background() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.color = BACKGROUND_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# 6-D: 마름모 벽지(타일 반복) → 기계 프레임. 둘 다 다른 요소보다 뒤에 그려지고 클릭을 막지 않는다.
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
	# 6-F3a: 프레임 가로 띠의 전구 소켓 18개 (프레임 바로 위, 다른 요소 뒤)
	_frame_bulbs = FrameBulbs.new()
	add_child(_frame_bulbs)


func _build_board() -> void:
	_board = BoardView.new()
	_board.name = "Board"
	_board.position = BOARD_ORIGIN
	add_child(_board)
	_board.apply_feel(_feel)
	_frame_bulbs.apply_feel(_feel)


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


## 타이틀 칸: 패널 틀 위에 로고 그림(180×72, 배경 투명)을 올린다
func _build_title_frame() -> void:
	var frame: Panel = Panel.new()
	frame.name = "Title"
	frame.position = TITLE_RECT.position
	frame.size = TITLE_RECT.size
	frame.add_theme_stylebox_override("panel", UiSkin.panel_box())
	add_child(frame)
	var logo: TextureRect = TextureRect.new()
	logo.name = "TitleLogo"
	logo.texture = load(LOGO_PATH) as Texture2D
	logo.size = TITLE_RECT.size
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(logo)


## 릴 아래 STOP 1/2/3 버튼
func _build_stop_buttons() -> void:
	for col: int in REEL_COLS:
		var x: float = REEL_ORIGIN.x + col * (CELL_SIZE.x + CELL_GAP) + (CELL_SIZE.x - STOP_SLOT_SIZE.x) / 2.0
		var button: Button = _make_button("StopButton%d" % (col + 1), "STOP %d" % (col + 1), Rect2(Vector2(x, STOP_SLOT_Y), STOP_SLOT_SIZE))
		button.pressed.connect(press_stop.bind(col))
		_stop_buttons.append(button)
	_auto_button = _make_button("AutoButton", "AUTO", AUTO_RECT)
	_auto_button.pressed.connect(press_auto)


func _build_info_boxes() -> void:
	_credit_box = _add_box(InfoBox.new("CreditBox", "CREDIT", CREDIT_RECT, BIG_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	_credit_box.set_value_color(CREDIT_COLOR)
	_notice_box = _add_box(InfoBox.new("NoticeBox", "", NOTICE_RECT, NOTICE_FONT_SIZE, HORIZONTAL_ALIGNMENT_LEFT, true, false))
	_win_box = _add_box(InfoBox.new("WinBox", "WIN", WIN_RECT, BIG_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	_win_box.set_value_color(WIN_COLOR)
	_bet_box = _add_box(InfoBox.new("BetBox", "BET", BET_RECT, BIG_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	_pool_box = _add_box(InfoBox.new("PoolBox", "POOL", POOL_RECT, POOL_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, false, true, true))
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


## 버튼 한 줄: CANCEL | COIN | START | BET | MAX BET (어두운 띠 위, 위치는 BUTTON_XS)
func _build_buttons() -> void:
	var strip: ColorRect = ColorRect.new()
	strip.name = "ButtonStrip"
	strip.color = BUTTON_STRIP_COLOR
	strip.position = BUTTON_STRIP_RECT.position
	strip.size = BUTTON_STRIP_RECT.size
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	_cancel_button = _make_row_button("CancelButton", "CANCEL", 0)
	_cancel_button.pressed.connect(press_cancel)
	_coin_button = _make_row_button("CoinButton", "COIN", 1)
	_coin_button.pressed.connect(press_coin)
	_start_button = _make_row_button("StartButton", "START", 2)
	_start_button.pressed.connect(do_spin)
	_bet_button = _make_row_button("BetButton", "BET", 3)
	_bet_button.pressed.connect(press_bet)
	_max_bet_button = _make_row_button("MaxBetButton", "MAX BET", 4)
	_max_bet_button.pressed.connect(press_max_bet)


func _make_row_button(node_name: String, text: String, slot: int) -> Button:
	return _make_button(node_name, text, Rect2(Vector2(BUTTON_XS[slot], BUTTON_Y), BUTTON_SIZE))


## AUTO가 켜지면 버튼을 ON 그림(밝은 금색 면, 어두운 글자)으로, 꺼지면 기본 스킨으로 되돌린다.
func _apply_auto_skin() -> void:
	var on_states: PackedStringArray = PackedStringArray(["normal", "hover"])
	var color_keys: PackedStringArray = PackedStringArray(["font_color", "font_hover_color"])
	for state: String in on_states:
		if GameState.auto_on:
			_auto_button.add_theme_stylebox_override(state, UiSkin.button_box("on"))
		else:
			_auto_button.remove_theme_stylebox_override(state)
	for key: String in color_keys:
		if GameState.auto_on:
			_auto_button.add_theme_color_override(key, UiSkin.BUTTON_ON_TEXT_COLOR)
		else:
			_auto_button.remove_theme_color_override(key)


func _make_button(node_name: String, text: String, rect: Rect2) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.position = rect.position
	button.size = rect.size
	# 스페이스·엔터가 버튼 클릭으로 한 번 더 처리되지 않게 한다.
	button.focus_mode = Control.FOCUS_NONE
	UiFont.apply(button, UiFont.Face.BODY, BUTTON_FONT_MULTIPLE)
	add_child(button)
	return button


## 정산 연출 (6-F3b): 동전이 버튼·안내 칸 위를 지나가므로 그 위, 피버 오버레이 아래에 둔다
func _build_settle_show() -> void:
	_settle = SettleShow.new()
	add_child(_settle)
	_settle.win_shown_changed.connect(_on_settle_win_shown)
	_settle.credit_shown_changed.connect(_on_settle_credit_shown)
	_settle.tick.connect(_on_settle_tick)
	_settle.coin_landed.connect(_on_settle_tick)


## 카운트업 증가와 동전 도착은 같은 틱 소리
func _on_settle_tick() -> void:
	_sound.play(SoundBank.NAME_TICK)


## 효과음 도우미. 다른 요소와 상관없는 Node라 그리기 순서·좌표에 영향이 없다.
func _build_sound() -> void:
	_sound = SoundBank.new()
	add_child(_sound)
	_sound.set_sfx_volume_db(_feel.sfx_volume_db)
	_bgm = BgmPlayer.new()
	add_child(_bgm)
	_bgm.apply_feel(_feel)
	_bgm.start()


## GAME OVER 화면: 피버 오버레이처럼 맨 위에 둔다 (둘은 동시에 뜨지 않는다)
func _build_game_over() -> void:
	_game_over = GameOverOverlay.new()
	add_child(_game_over)
	_game_over.continue_pressed.connect(_on_continue_pressed)
	_game_over.new_game_pressed.connect(_on_new_game_pressed)


## GAME OVER 화면이 떠 있는가 / 화면 노드 (테스트용)
func game_over_open() -> bool:
	return _game_over.is_open()


func game_over_overlay() -> GameOverOverlay:
	return _game_over


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
	_fever_overlay.step_started.connect(_on_fever_step_started)
	_fever_overlay.step_finished.connect(_on_fever_step_finished)
	_fever_overlay.finished.connect(_on_fever_finished)

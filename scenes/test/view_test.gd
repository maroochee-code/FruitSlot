extends Node
## 화면 검증: main 씬을 띄우고 키보드·START·STOP을 여러 방식으로 눌러서
## 화면 칸, 릴 정지 위치, CREDIT/WIN/BET/POOL/피버 표시, 라인 라벨, 당첨 선이 로직 결과와 매번 같은지 확인한다.
## 시간은 main.advance()로 테스트가 직접 흘린다 (실제 시간에 의존하지 않음).

@export var spin_count: int = 300
@export var quit_when_headless: bool = true

const FULL_BET: int = 8
const TEST_SEED: int = 12345
const FRAME_DT: float = 1.0 / 60.0
const SPIKE_DT: float = 0.2
const SPIKE_CHANCE: float = 0.02
const MAX_SPIN_SEC: float = 40.0
## 회전 중 조작 잠금을 한 번 검사하는 시각 (START 잠금 시간보다 뒤)
const LOCK_CHECK_SEC: float = 0.5
const INPUT_MODES: int = 4

var _passed: int = 0
var _failed: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _strip_errors: int = 0
var _early_reveal: int = 0
var _lock_errors: int = 0
var _final_errors: int = 0
var _stuck_spins: int = 0
var _window_errors: int = 0
var _window_moves: int = 0
var _delay_errors: int = 0
## 300회 스핀 중 피버 연출이 재생된 프레임 수 (일반 스핀 흐름에서도 정산이 연출 뒤로 밀리는지 확인용)
var _fever_frames: int = 0


func _ready() -> void:
	# 설정 파일 격리: 개발자 PC의 실제 user://settings.json·highscore.json을 읽지도 쓰지도 않는다
	UserSettings.configure(false)
	# 오토로드 상태를 처음 상태로 되돌린 뒤 시작한다.
	GameState.initialize(GameState.get_balance(), GameState.load_economy(), TEST_SEED)
	_rng.seed = TEST_SEED
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	main.settle_presentation = false
	add_child(main)
	# 시간은 테스트가 main.advance()로 직접 흘린다.
	main.set_process(false)
	await get_tree().process_frame
	_test_initial_screen(main)
	_test_layout(main)
	_test_board_layout(main)
	_test_ui_layout(main)
	_test_backdrop(main)
	_test_paytable(main)
	_test_fever_panel(main)
	_test_pool_color(main)
	_test_keyboard(main)
	_test_max_and_cancel(main)
	await _test_spins(main)
	_test_labels_follow_bet(main)
	_test_stop_flow(main)
	_test_feel_reload(main)
	main.free()
	await get_tree().process_frame
	await _test_fever_show()
	await _test_overlay_art()
	await _test_sound()
	await _test_bgm()
	await _test_bulbs()
	await _test_auto_view()
	await _test_settle_show()
	await _test_game_over_view()
	await _test_title_screen()
	await _test_settings_screen()
	print("==================== VIEW TEST: %d 통과 / %d 실패 ====================" % [_passed, _failed])
	if quit_when_headless and DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", label)


func _box(main: Control, node_name: String) -> InfoBox:
	return main.get_node(node_name) as InfoBox


func _fever(main: Control) -> FeverPanel:
	return main.get_node("FeverBox") as FeverPanel


func _press(main: Control, keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	main._unhandled_key_input(event)


func _test_initial_screen(main: Control) -> void:
	var overlay: LineOverlay = main.get_node("LineOverlay")
	_check(_box(main, "CreditBox").value_text() == "0", "처음 CREDIT 0")
	_check(_box(main, "BetBox").value_text() == "0", "처음 BET 0")
	_check(_box(main, "WinBox").value_text() == "0", "처음 WIN 0")
	_check(_box(main, "PoolBox").value_text() == str(GameState.get_pool()), "POOL 초기값 표시")
	var all_dim: bool = true
	for i: int in GameState.get_balance().line_count():
		all_dim = all_dim and overlay.label_is_dim(i)
	_check(all_dim, "베팅 0이면 라인 라벨 모두 어둡게")
	_check((main.get_node("StartButton") as Button).disabled, "처음 START 비활성")
	_check((main.get_node("BetButton") as Button).disabled, "처음 BET 비활성")
	_check(not (main.get_node("CoinButton") as Button).disabled, "COIN은 항상 활성")
	_check(_box(main, "NoticeBox").value_text().contains("COIN"), "크레딧 0이면 COIN 안내")
	var stops_disabled: bool = true
	for i: int in 3:
		stops_disabled = stops_disabled and (main.get_node("StopButton%d" % (i + 1)) as Button).disabled
	_check(stops_disabled, "멈춰 있을 때 STOP 1·2·3 버튼 비활성")


func _test_layout(main: Control) -> void:
	var stop_y: float = (main.get_node("StopButton1") as Button).position.y
	var fits: bool = true
	for i: int in 3:
		var reel: ReelView = main.reel_view(i)
		fits = fits and reel.position.y >= 0.0 and reel.position.y + reel.size.y <= stop_y
	_check(fits, "릴(3칸)이 화면 안, STOP 버튼 위에서 끝남")
	var window: float = 3.0 * main.CELL_SIZE.y + 2.0 * main.CELL_GAP
	_check(is_equal_approx(main.reel_view(0).size.y, window), "릴 높이 = 3칸 + 칸 사이 간격 (위아래 덤 영역 없음)")
	_check(not main.reel_view(0).has_node("TopShade") and not main.reel_view(0).has_node("BottomShade"), "덤 가림막이 없음")
	var windows_ok: bool = true
	for i: int in 3:
		for row: int in 3:
			var cell_window: Control = main.reel_view(i).window_at(row)
			windows_ok = windows_ok and cell_window.clip_contents and cell_window.size == main.CELL_SIZE \
					and is_equal_approx(cell_window.position.y, row * (main.CELL_SIZE.y + main.CELL_GAP))
	_check(windows_ok, "릴 3개 × 칸 창 3개가 칸 크기·간격대로 놓이고 모두 잘라서(clip) 보여 줌")
	for i: int in 3:
		_check(main.reel_view(i).is_consistent(), "처음 화면 릴%d의 심볼이 스트립 순서와 같음" % (i + 1))
		_check(main.reel_view(i).windows_are_sound(), "처음 화면 릴%d의 칸 창이 심볼로 빈틈없이 채워짐" % (i + 1))


## 6-B: 보드·칸·심볼 그림·STOP·라벨이 목표 배치(640×480)와 정확히 맞는지
func _test_board_layout(main: Control) -> void:
	var board: BoardView = main.get_node("Board")
	_check(board.position == Vector2(42, 36) and board.size == Vector2(348, 276), "보드 외곽 (42,36) 348×276")
	_check(main.CELL_SIZE == Vector2(108, 84) and main.CELL_GAP == 0.0, "칸 108×84, 칸 사이 간격 없음")
	var cells_ok: bool = true
	var art_ok: bool = true
	for col: int in 3:
		var reel: ReelView = main.reel_view(col)
		cells_ok = cells_ok and reel.position == Vector2(54 + 108 * col, 48)
		for row: int in 3:
			var window: Control = reel.window_at(row)
			cells_ok = cells_ok and reel.position + window.position == Vector2(54 + 108 * col, 48 + 84 * row)
			var cell: SymbolCell = reel.cell_at(row)
			art_ok = art_ok and cell.tile_rect() == Rect2(0, 0, 108, 84) and cell.symbol_rect() == Rect2(6, 6, 96, 72)
			art_ok = art_ok and cell.art_visible()
	_check(cells_ok, "칸 위치 (54+108c, 48+84r)")
	_check(art_ok, "칸마다 타일 108×84 + 심볼 96×72가 칸 안쪽 (6,6)에 놓임 (정수 3배)")
	_check(board.bulb_count() == 100, "전구 링 100개")
	var bulbs_ok: bool = true
	for i: int in board.bulb_count():
		var p: Vector2i = board.bulb_art_position(i)
		bulbs_ok = bulbs_ok and p.x >= 1 and p.y >= 1 and p.x <= 113 and p.y <= 89
		bulbs_ok = bulbs_ok and (p.x == 1 or p.x == 113 or p.y == 1 or p.y == 89)
		bulbs_ok = bulbs_ok and board.bulb_is_lit(i) == (i % 2 == 0)
	_check(bulbs_ok, "전구가 보드 안쪽 테두리 위에만 있고 켜짐/꺼짐이 교대")
	var stop_ok: bool = true
	for col: int in 3:
		var button: Button = main.get_node("StopButton%d" % (col + 1))
		stop_ok = stop_ok and button.size == Vector2(96, 33) and button.position == Vector2(60 + 108 * col, 318)
	_check(stop_ok, "STOP 버튼 96×33, y=318, 칸 가운데 정렬")
	var labels_ok: bool = true
	var label_count: int = 0
	for child: Node in main.get_node("LineOverlay").get_children():
		var label: Label = child as Label
		if label == null:
			continue
		label_count += 1
		labels_ok = labels_ok and label.size == Vector2(33, 21)
		var left: bool = is_equal_approx(label.position.x, 6.0)
		var right: bool = is_equal_approx(label.position.x, 396.0)
		var top: bool = is_equal_approx(label.position.y, 9.0)
		labels_ok = labels_ok and (left or right or top)
		if left or right:
			labels_ok = labels_ok and label.position.y >= 48.0 and label.position.y + 21.0 <= 300.0
	_check(label_count > 0 and labels_ok, "라인 라벨 33×21, 보드 바깥 (왼쪽 x=6 / 오른쪽 x=396 / 위쪽 y=9)")


## 6-F3a: 전구 (시트 그림, 모양 규칙, 보드 링·프레임 소켓, 모드 전환, feel 키)
func _test_bulbs() -> void:
	_test_bulb_sheet_and_pattern()
	_test_bulb_nodes()
	await _test_bulb_modes_in_game()
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)


func _test_bulb_sheet_and_pattern() -> void:
	var sheet: Texture2D = BulbSheet.sheet()
	_check(sheet != null and sheet.get_size() == Vector2(24, 6), "bulbs.png: 전구 4상태 가로 시트 24×6")
	var frames_ok: bool = true
	for state: int in BulbSheet.STATE_COUNT:
		frames_ok = frames_ok and BulbSheet.frame(state).region == Rect2(state * 6, 0, 6, 6)
	_check(frames_ok and BulbSheet.frame(99).region == BulbSheet.frame(BulbSheet.STATE_COUNT - 1).region, "상태마다 6×6 칸 (범위 밖 번호는 마지막 칸)")
	var pattern: BulbPattern = BulbPattern.new()
	var idle_ok: bool = true
	for i: int in 100:
		idle_ok = idle_ok and pattern.state_of(BulbPattern.Mode.IDLE, i, 0.0) == (BulbSheet.STATE_ON if i % 2 == 0 else BulbSheet.STATE_OFF)
	_check(idle_ok, "대기 모양: 시간 0에서 짝수 번호 켜짐 (6-B 정적 모양과 같음)")
	_check(pattern.state_of(BulbPattern.Mode.IDLE, 0, 0.8) == BulbSheet.STATE_OFF and pattern.state_of(BulbPattern.Mode.IDLE, 1, 0.8) == BulbSheet.STATE_ON, "대기: bulb_idle_sec(0.8초)마다 짝수/홀수가 바뀜")
	_check(pattern.state_of(BulbPattern.Mode.IDLE, 0, 1.6) == BulbSheet.STATE_ON, "대기: 두 번 바뀌면 처음 모양")
	var spin_start: PackedInt32Array = pattern.states_of(BulbPattern.Mode.SPIN, 100, 0.0)
	var lit: int = 0
	for state: int in spin_start:
		lit += 1 if state == BulbSheet.STATE_ON else 0
	_check(lit == 34 and spin_start[0] == BulbSheet.STATE_ON and spin_start[1] == BulbSheet.STATE_OFF, "스핀 모양: 3개 중 1개씩 켜짐 (100개 중 %d개)" % lit)
	var spin_next: PackedInt32Array = pattern.states_of(BulbPattern.Mode.SPIN, 100, 0.06)
	_check(spin_next[0] == BulbSheet.STATE_OFF and spin_next[1] == BulbSheet.STATE_ON and spin_next[4] == BulbSheet.STATE_ON, "스핀: bulb_spin_step_sec(0.06초)마다 켜진 전구가 한 칸 앞으로")
	_check(pattern.states_of(BulbPattern.Mode.SPIN, 100, 0.18) == spin_start, "스핀: 3칸 돌면 처음 모양")
	var win_on: bool = true
	var win_off: bool = true
	for i: int in 100:
		win_on = win_on and pattern.state_of(BulbPattern.Mode.WIN, i, 0.0) == BulbSheet.STATE_WHITE
		win_off = win_off and pattern.state_of(BulbPattern.Mode.WIN, i, 0.12) == BulbSheet.STATE_OFF
	_check(win_on and win_off, "당첨 모양: 전부 흰색 ↔ 전부 꺼짐 번쩍 (bulb_win_flash_sec 0.12초)")
	_check(pattern.state_of(BulbPattern.Mode.FEVER, 5, 0.0) == BulbSheet.STATE_ON and pattern.state_of(BulbPattern.Mode.FEVER, 5, 0.2) == BulbSheet.STATE_RED, "피버 모양: 노랑 ↔ 빨강 전체 교대 (bulb_fever_sec 0.2초)")
	var slow: FeelConfig = FeelConfig.from_dict({ "bulb_idle_sec": 2.0 })
	var custom: BulbPattern = BulbPattern.new()
	custom.apply_feel(slow)
	_check(custom.state_of(BulbPattern.Mode.IDLE, 0, 1.9) == BulbSheet.STATE_ON and custom.state_of(BulbPattern.Mode.IDLE, 0, 2.0) == BulbSheet.STATE_OFF, "feel 값(bulb_idle_sec 2.0)이 모양 규칙에 반영됨")
	var defaults: FeelConfig = FeelConfig.from_dict({})
	_check(defaults.bulb_idle_sec == 0.8 and defaults.bulb_spin_step_sec == 0.06 and defaults.bulb_win_flash_sec == 0.12 and defaults.bulb_fever_sec == 0.2, "전구 feel 키 4개 기본값 0.8 / 0.06 / 0.12 / 0.2")
	var bad: FeelConfig = FeelConfig.from_dict({ "bulb_idle_sec": 99.0, "bulb_spin_step_sec": 0.0 })
	_check(bad.bulb_idle_sec == 0.8 and bad.bulb_spin_step_sec == 0.06, "전구 feel 키 범위 밖은 기본값")


func _test_bulb_nodes() -> void:
	var board: BoardView = BoardView.new()
	add_child(board)
	_check(board.bulb_count() == 100 and board.mode() == BulbPattern.Mode.IDLE and board.bulb_is_lit(0) and not board.bulb_is_lit(1), "보드 링: 처음엔 대기 모양")
	board.set_mode(BulbPattern.Mode.SPIN)
	_check(board.bulb_state(0) == BulbSheet.STATE_ON and board.bulb_state(1) == BulbSheet.STATE_OFF, "보드 링: 스핀 모드 시작")
	board.advance(0.06)
	_check(board.bulb_state(0) == BulbSheet.STATE_OFF and board.bulb_state(1) == BulbSheet.STATE_ON, "보드 링: 시간이 흐르면 켜진 전구가 돎")
	board.set_mode(BulbPattern.Mode.IDLE)
	_check(board.bulb_state(0) == BulbSheet.STATE_ON and board.bulb_state(1) == BulbSheet.STATE_OFF, "보드 링: 모드를 바꾸면 시간이 0부터 다시 셈")
	board.set_mode(BulbPattern.Mode.FEVER)
	board.advance(0.2)
	_check(board.bulb_state(7) == BulbSheet.STATE_RED and board.bulb_is_lit(7), "보드 링: 빨강도 켜진 전구로 셈")
	_check(board.mouse_filter == Control.MOUSE_FILTER_IGNORE, "보드 링은 클릭을 막지 않음")
	board.free()
	var socket_row: FrameBulbs = FrameBulbs.new()
	add_child(socket_row)
	var positions_ok: bool = socket_row.socket_count() == 18
	for i: int in socket_row.socket_count():
		positions_ok = positions_ok and socket_row.socket_art_position(i) == Vector2i(6 + i * 8, 135)
	_check(positions_ok, "프레임 소켓 18개: x = 6, 14, … 142 / y = 135 (아트 좌표)")
	_check(socket_row.mouse_filter == Control.MOUSE_FILTER_IGNORE and socket_row.bulb_state(0) == BulbSheet.STATE_ON and socket_row.bulb_state(1) == BulbSheet.STATE_OFF, "프레임 소켓은 클릭을 막지 않고, 처음엔 대기 모양")
	socket_row.set_mode(BulbPattern.Mode.SPIN)
	socket_row.advance(0.12)
	_check(socket_row.bulb_state(2) == BulbSheet.STATE_ON and socket_row.bulb_state(0) == BulbSheet.STATE_OFF, "프레임 소켓: 스핀 모드에서 왼쪽 → 오른쪽으로 달림")
	# frame.png에 구워진 꺼진 소켓 위치와 같은지 (생성기와 게임 좌표가 어긋나지 않게)
	var frame_image: Image = (load("res://assets/ui/frame.png") as Texture2D).get_image()
	var bake_ok: bool = true
	for i: int in socket_row.socket_count():
		var pos: Vector2i = socket_row.socket_art_position(i) * SymbolStyle.ART_SCALE
		for offset: Vector2i in [Vector2i(0, 0), Vector2i(5, 5)]:
			bake_ok = bake_ok and frame_image.get_pixelv(pos + offset).is_equal_approx(Color("8a7a3a"))
		bake_ok = bake_ok and not frame_image.get_pixelv(pos + Vector2i(-3, 0)).is_equal_approx(Color("8a7a3a"))
	_check(bake_ok, "frame.png의 꺼진 소켓 18개가 FrameBulbs 좌표와 일치")
	socket_row.free()


func _test_bulb_modes_in_game() -> void:
	var win_seed: int = _sound_find_plain_win_seed()
	var lose_seed: int = _auto_find_seed(1000, 8, false)
	_check(win_seed > 0 and lose_seed > 0, "전구 시험용 일반 당첨·무당첨 시드를 찾음")
	if win_seed <= 0 or lose_seed <= 0:
		return
	var main: Control = await _auto_main(lose_seed, 1000, 8)
	var frame_index: int = main.get_node("Frame").get_index()
	var bulbs: FrameBulbs = main.frame_bulbs()
	_check(bulbs == main.get_node("FrameBulbs") and bulbs.get_index() == frame_index + 1 and main.get_node("Board").get_index() > bulbs.get_index(), "FrameBulbs는 프레임 바로 위, 보드·다른 요소보다 뒤")
	_check(main.bulb_mode() == BulbPattern.Mode.IDLE, "처음엔 대기 모양")
	main.do_spin()
	_check(main.bulb_mode() == BulbPattern.Mode.SPIN and main.board_view().mode() == BulbPattern.Mode.SPIN and bulbs.mode() == BulbPattern.Mode.SPIN, "스핀이 시작되면 보드와 프레임이 스핀 모양")
	_advance_for(main, 1.0)
	_check(main.bulb_mode() == BulbPattern.Mode.SPIN, "릴이 도는 동안 스핀 모양 유지")
	_settle(main)
	_check(GameState.last_win == 0 and main.bulb_mode() == BulbPattern.Mode.IDLE, "무당첨: 릴이 멈추면 대기 모양, 당첨 번쩍 없음")
	main.free()
	await get_tree().process_frame
	# 일반 당첨: 당첨선이 깜빡이는 동안(1.5초) 번쩍
	var win_main: Control = await _auto_main(win_seed, 1000, 8)
	win_main.do_spin()
	_settle(win_main)
	var blink: float = LineOverlay.blink_total_sec()
	_check(_near(blink, 1.5), "당첨선 깜빡임 시간 1.5초 (3사이클)")
	_check(GameState.last_win > 0 and win_main.bulb_mode() == BulbPattern.Mode.WIN and win_main.frame_bulbs().mode() == BulbPattern.Mode.WIN, "일반 당첨: 정산 때 전구가 당첨 모양")
	_advance_for(win_main, blink - 0.2)
	_check(win_main.bulb_mode() == BulbPattern.Mode.WIN, "당첨 모양은 깜빡임이 끝나기 전까지 유지")
	_advance_for(win_main, 0.4)
	_check(win_main.bulb_mode() == BulbPattern.Mode.IDLE, "깜빡임이 끝나면 대기 모양으로 돌아감")
	# 당첨 모양 도중 다음 판이 시작되면 스핀 모양이 우선
	win_main.free()
	await get_tree().process_frame
	win_main = await _auto_main(win_seed, 1000, 8)
	win_main.do_spin()
	_settle(win_main)
	win_main.advance(0.3)
	GameState.credit = 1000
	win_main.do_spin()
	_advance_for(win_main, 2.0)
	_check(win_main.bulb_mode() == BulbPattern.Mode.SPIN, "당첨 모양 도중 다음 판을 시작하면 스핀 모양이 우선 (남은 시간이 스핀을 끊지 않음)")
	win_main.free()
	await get_tree().process_frame
	# 피버: 오버레이가 보드를 가리는 동안은 대기 모양, 끝난 직후 피버 모양(1.5초)
	var data: BalanceData = _fever_test_data()
	var fever_n: int = _find_fever_spin(data, 1)
	var fever_main: Control = await _fever_world(data, fever_n)
	fever_main.do_spin()
	_check(_advance_to_fever(fever_main) and fever_main.bulb_mode() == BulbPattern.Mode.IDLE, "피버 연출 중에는 전구 모양이 따로 바뀌지 않음 (오버레이가 가림)")
	_settle(fever_main)
	_check(fever_main.bulb_mode() == BulbPattern.Mode.FEVER and fever_main.frame_bulbs().mode() == BulbPattern.Mode.FEVER, "피버 연출이 끝난 직후 전구가 피버 모양")
	_advance_for(fever_main, blink + 0.2)
	_check(fever_main.bulb_mode() == BulbPattern.Mode.IDLE, "피버 모양은 1.5초 뒤 대기 모양으로")
	fever_main.free()
	await get_tree().process_frame
	# 건너뛰어도 피버 모양
	var skip_main: Control = await _fever_world(data, fever_n)
	skip_main.do_spin()
	_advance_to_fever(skip_main)
	skip_main.advance(0.6)
	skip_main.do_spin()
	_check(skip_main.bulb_mode() == BulbPattern.Mode.FEVER, "연출을 건너뛰어도 끝난 직후 피버 모양")
	skip_main.free()
	await get_tree().process_frame


## 6-F2: BGM (곡 파일·길이, 시작, 메인↔피버 전환 곡선, 메인 위치 기억, 곡 끝 반복, 피버 연출과의 연결, feel 키)
func _test_bgm() -> void:
	await _test_bgm_basics()
	_test_bgm_crossfade()
	_test_bgm_loop()
	await _test_bgm_with_main()
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)


func _bgm_log(bgm: BgmPlayer) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry: StringName in bgm.requests():
		parts.append(String(entry))
	return ",".join(parts)


func _near(a: float, b: float, tolerance: float = 0.002) -> bool:
	return absf(a - b) <= tolerance


## 시험용 BgmPlayer (기본 feel 값, 소리 재생은 헤드리스라 요청만)
func _make_bgm() -> BgmPlayer:
	var bgm: BgmPlayer = BgmPlayer.new()
	add_child(bgm)
	bgm.apply_feel(FeelConfig.from_dict({}))
	return bgm


func _test_bgm_basics() -> void:
	var main: Control = await _auto_main(5, 1000, 8)
	var bgm: BgmPlayer = main.bgm_player()
	_check(bgm != null and main.get_node("BgmPlayer") == bgm, "main 안에 BgmPlayer 노드")
	var files_ok: bool = true
	for track: StringName in BgmPlayer.TRACK_PATHS:
		files_ok = files_ok and ResourceLoader.exists(BgmPlayer.TRACK_PATHS[track]) and load(BgmPlayer.TRACK_PATHS[track]) is AudioStreamMP3
	_check(files_ok and bgm.track_length(BgmPlayer.TRACK_MAIN) > 60.0 and bgm.track_length(BgmPlayer.TRACK_FEVER) > 60.0, "BGM 파일 2개(main %.1f초 / fever %.1f초)가 mp3로 읽힘" % [bgm.track_length(BgmPlayer.TRACK_MAIN), bgm.track_length(BgmPlayer.TRACK_FEVER)])
	_check(DisplayServer.get_name() != "headless" or not bgm.playback_enabled, "헤드리스에서는 실제 재생 없이 요청·상태만 셈")
	_check(bgm.current_track() == BgmPlayer.TRACK_MAIN and _bgm_log(bgm) == "start:main", "게임이 시작되면 메인 BGM 시작 (%s)" % _bgm_log(bgm))
	_check(bgm.gain_of(BgmPlayer.TRACK_MAIN) == 0.0, "시작은 무음에서 페이드인")
	main.advance(1.0)
	_check(_near(bgm.gain_of(BgmPlayer.TRACK_MAIN), 1.0) and bgm.position_of(BgmPlayer.TRACK_MAIN) > 0.9, "1초(bgm_to_main_sec) 뒤 메인 BGM 풀 음량, 위치가 흐름")
	bgm.start()
	_check(_bgm_log(bgm) == "start:main", "start()를 또 불러도 다시 시작하지 않음")
	# 일반 스핀은 BGM을 건드리지 않음
	bgm.clear_requests()
	main.press_bet()
	main.do_spin()
	_settle(main)
	_check(_bgm_log(bgm) == "" or not _bgm_log(bgm).contains("fever"), "피버 없는 일반 판은 BGM을 바꾸지 않음")
	# feel 키
	# 사용자가 feel.json을 듣고 조정하므로(예: bgm_volume_db) 파일 값이 아니라 "기본값"과 "파일이 오류 없이 읽힘"을 확인한다
	var feel: FeelConfig = FeelConfig.from_dict({})
	_check(feel.bgm_volume_db == -12.0 and feel.bgm_to_fever_sec == 0.3 and feel.bgm_to_main_sec == 1.0 and feel.bgm_loop_trim_sec == 2.0 and feel.bgm_loop_fade_sec == 1.0, "BGM 키 5개 기본값: -12 / 0.3 / 1.0 / 2.0 / 1.0")
	_check(FeelConfig.load_from_file().errors.is_empty(), "feel.json이 오류 없이 읽힘 (모든 키가 범위 안)")
	var bad: FeelConfig = FeelConfig.from_dict({ "bgm_loop_trim_sec": 1.0, "bgm_loop_fade_sec": 2.0 })
	_check(bad.bgm_loop_trim_sec == 2.0 and bad.bgm_loop_fade_sec == 1.0, "반복 크로스페이드가 trim보다 길면 둘 다 기본값")
	_check(FeelConfig.from_dict({ "bgm_volume_db": 50.0 }).bgm_volume_db == -12.0 and FeelConfig.from_dict({ "bgm_to_main_sec": 9.0 }).bgm_to_main_sec == 1.0, "BGM 키 범위 밖은 기본값")
	# 볼륨은 스핀 시작 때 새 설정으로 BGM 버스에 적용
	main.set_feel_path(FEEL_TEMP_PATH)
	_write_feel_file(FEEL_TEMP_PATH, { "bgm_volume_db": -20.0 })
	main.reload_feel()
	GameState.credit = 1000
	main.press_bet()
	main.do_spin()
	_check(_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(SoundBank.BUS_BGM)), -20.0, 0.01), "bgm_volume_db가 BGM 버스에 적용됨 (다음 스핀부터)")
	_settle(main)
	_write_feel_file(FEEL_TEMP_PATH, {})
	main.reload_feel()
	main.set_feel_path(FeelConfig.DEFAULT_PATH)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SoundBank.BUS_BGM), 0.0)
	# 끄기 / 다시 시작
	bgm.stop_all()
	_check(bgm.current_track() == &"" and bgm.active_voices() == 0, "stop_all(): 모두 꺼짐 (미리보기 씬용)")
	bgm.start()
	_check(bgm.current_track() == BgmPlayer.TRACK_MAIN and bgm.active_voices() == 1, "stop_all() 뒤 start(): 다시 시작")
	bgm.seek(100.0)
	_check(_near(bgm.position_of(BgmPlayer.TRACK_MAIN), 100.0), "seek(): 위치 이동 (미리보기용)")
	main.free()
	await get_tree().process_frame


## 메인 → 피버 → 메인: 등전력 곡선, 메인은 일시정지로 위치 기억, 피버는 매번 처음부터
func _test_bgm_crossfade() -> void:
	var bgm: BgmPlayer = _make_bgm()
	bgm.start()
	bgm.advance(1.0)
	var main_track: StringName = BgmPlayer.TRACK_MAIN
	var fever_track: StringName = BgmPlayer.TRACK_FEVER
	bgm.switch_to(fever_track)
	bgm.switch_to(fever_track)
	_check(_bgm_log(bgm) == "start:main,to:fever", "같은 곡으로 또 바꿔도 요청은 한 번")
	bgm.advance(0.15)
	_check(_near(bgm.gain_of(main_track), cos(PI / 4.0)) and _near(bgm.gain_of(fever_track), sin(PI / 4.0)), "전환 중간(0.15/0.3초): 등전력 곡선 (메인 %.3f / 피버 %.3f)" % [bgm.gain_of(main_track), bgm.gain_of(fever_track)])
	bgm.advance(0.15)
	_check(bgm.gain_of(main_track) == 0.0 and _near(bgm.gain_of(fever_track), 1.0) and bgm.is_paused(main_track), "전환이 끝나면 메인은 일시정지(무음), 피버는 풀 음량")
	var paused_at: float = bgm.position_of(main_track)
	bgm.advance(5.0)
	_check(_near(bgm.position_of(main_track), paused_at) and _near(bgm.position_of(fever_track), 5.3), "일시정지 중 메인 위치는 그대로(%.2f초), 피버는 처음부터 흐름" % paused_at)
	bgm.switch_to(main_track)
	_check(_bgm_log(bgm) == "start:main,to:fever,to:main" and not bgm.is_paused(main_track), "피버 → 메인: 메인 이어서 재생")
	bgm.advance(0.5)
	_check(_near(bgm.gain_of(main_track), sin(PI / 4.0)) and _near(bgm.gain_of(fever_track), cos(PI / 4.0)), "복귀 중간(0.5/1.0초): 등전력 곡선")
	bgm.advance(0.5)
	_check(_near(bgm.gain_of(main_track), 1.0) and bgm.gain_of(fever_track) == 0.0 and bgm.active_voices() == 1, "복귀가 끝나면 메인만 남음 (피버 재생기 정리)")
	_check(_near(bgm.position_of(main_track), paused_at + 1.0), "메인은 멈춘 자리(%.2f초)부터 이어짐 → %.2f초" % [paused_at, bgm.position_of(main_track)])
	bgm.switch_to(fever_track)
	_check(bgm.position_of(fever_track) == 0.0, "피버 곡은 매번 처음부터")
	# 전환 도중 다시 전환해도 음량이 튀지 않음
	bgm.advance(0.1)
	var before: float = bgm.gain_of(main_track)
	bgm.switch_to(main_track)
	_check(_near(bgm.gain_of(main_track), before), "전환 도중 되돌려도 음량이 끊기지 않고 이어짐")
	bgm.advance(2.0)
	_check(bgm.current_track() == main_track and _near(bgm.gain_of(main_track), 1.0) and bgm.active_voices() == 1, "연속 전환 뒤에도 메인만 정상으로 남음")
	bgm.free()


## 곡 끝 반복: 길이 - trim 시각에 한 번, 크로스페이드, 이음새 없이 계속
func _test_bgm_loop() -> void:
	var bgm: BgmPlayer = _make_bgm()
	bgm.start()
	var main_track: StringName = BgmPlayer.TRACK_MAIN
	var length: float = bgm.track_length(main_track)
	_check(_near(BgmPlayer.loop_point(length, 2.0), length - 2.0) and BgmPlayer.loop_point(1.0, 5.0) == 0.0, "반복 시각 = 곡 길이 - trim (음수면 0)")
	bgm.advance(1.0)
	var point: float = BgmPlayer.loop_point(length, 2.0)
	var guard: float = 1.0
	while guard + 1.0 < point:
		bgm.advance(1.0)
		guard += 1.0
	_check(_bgm_log(bgm) == "start:main", "반복 시각 전에는 반복 요청이 없음 (위치 %.1f초 / 시각 %.1f초)" % [guard, point])
	bgm.advance(1.0)
	_check(_bgm_log(bgm) == "start:main,loop:main" and bgm.active_voices() == 2, "반복 시각이 되면 같은 곡을 다시 틀고 이전 소리는 줄이는 중 (재생기 2개)")
	bgm.advance(0.5)
	_check(bgm.gain_of(main_track) > 0.2 and bgm.gain_of(main_track) < 0.95 and bgm.position_of(main_track) < 3.0, "새 소리는 처음부터 커지는 중")
	bgm.advance(1.0)
	_check(bgm.active_voices() == 1 and _near(bgm.gain_of(main_track), 1.0), "크로스페이드가 끝나면 이전 재생기 정리, 새 소리 풀 음량")
	for i: int in 30:
		bgm.advance(1.0)
	_check(_bgm_log(bgm) == "start:main,loop:main", "한 번 반복한 뒤 곧바로 또 반복하지 않음")
	for i: int in int(length - 2.0):
		bgm.advance(1.0)
	_check(_bgm_log(bgm) == "start:main,loop:main,loop:main", "다음 곡 끝에서 또 반복 (계속 이어짐)")
	# 피버로 일시정지 중에는 반복하지 않음
	bgm.switch_to(BgmPlayer.TRACK_FEVER)
	bgm.advance(1.0)
	var loops_before: int = bgm.requests().count(&"loop:main")
	bgm.advance(60.0)
	_check(bgm.requests().count(&"loop:main") == loops_before and not bgm.requests().has(&"loop:fever"), "일시정지 중인 메인은 반복을 시작하지 않음 (피버 곡도 60초 안에는 반복 없음)")
	bgm.free()


## 피버 연출과의 연결: 연출이 시작되면 피버 곡, 끝나면(건너뛰기 포함) 메인 곡, 한 쌍만
func _test_bgm_with_main() -> void:
	var data: BalanceData = _fever_test_data()
	var multi_n: int = _find_fever_spin(data, 2)
	var pool_n: int = _find_pool_spin(data)
	_check(multi_n >= 0 and pool_n >= 0, "BGM 시험용 피버 2개 스핀·풀 획득 스핀을 찾음")
	if multi_n < 0 or pool_n < 0:
		return
	for n: int in [multi_n, pool_n]:
		var main: Control = await _fever_world(data, n)
		var bgm: BgmPlayer = main.bgm_player()
		main.do_spin()
		_check(_advance_to_fever(main) and bgm.current_track() == BgmPlayer.TRACK_FEVER, "피버 연출이 시작되면 피버 곡으로 전환")
		_settle(main)
		var tag: String = "풀 획득 스핀" if n == pool_n else "피버 2개 스핀"
		_check(_bgm_log(bgm) == "start:main,to:fever,to:main" and bgm.current_track() == BgmPlayer.TRACK_MAIN, "%s: 연출 내내 피버 곡 → 끝나면 메인 곡, 전환은 한 쌍만 (%s)" % [tag, _bgm_log(bgm)])
		main.free()
		await get_tree().process_frame
	# 건너뛰기
	var skip_main: Control = await _fever_world(data, multi_n)
	var skip_bgm: BgmPlayer = skip_main.bgm_player()
	skip_main.do_spin()
	_check(_advance_to_fever(skip_main), "BGM 건너뛰기 시험: 피버 연출 시작")
	skip_main.advance(0.6)
	var main_pos: float = skip_bgm.position_of(BgmPlayer.TRACK_MAIN)
	skip_main.do_spin()
	_check(not skip_main.fever_playing() and skip_bgm.current_track() == BgmPlayer.TRACK_MAIN, "건너뛰면 메인 곡으로 복귀")
	_check(_bgm_log(skip_bgm) == "start:main,to:fever,to:main", "건너뛰어도 전환은 한 쌍만 (%s)" % _bgm_log(skip_bgm))
	skip_main.advance(2.0)
	_check(_near(skip_bgm.gain_of(BgmPlayer.TRACK_MAIN), 1.0) and skip_bgm.position_of(BgmPlayer.TRACK_MAIN) > main_pos and skip_bgm.active_voices() == 1, "복귀 뒤 메인은 멈춘 자리 이후로 이어지고 피버 재생기는 정리됨")
	skip_main.free()
	await get_tree().process_frame


## 6-F1: 효과음 요청 (소리 자체가 아니라 "맞는 상황에 맞는 이름이 요청됐는지"를 SoundBank의 요청 기록으로 확인한다)
func _test_sound() -> void:
	await _test_sound_basics()
	await _test_sound_spin()
	await _test_sound_fever()
	await _test_sound_auto()
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)


## 요청 기록을 "a,b,c" 한 줄로
func _sound_log(bank: SoundBank) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry: StringName in bank.requests():
		parts.append(String(entry))
	return ",".join(parts)


func _sound_count(bank: SoundBank, sound_name: StringName) -> int:
	return bank.requests().count(sound_name)


func _test_sound_basics() -> void:
	var files_ok: bool = true
	for sound_name: StringName in SoundBank.ALL_NAMES:
		files_ok = files_ok and ResourceLoader.exists(SoundBank.sound_path(sound_name))
	_check(files_ok and SoundBank.ALL_NAMES.size() == 15, "효과음 파일 15개가 모두 있음 (assets/sounds/*.wav, tick 포함)")
	var main: Control = await _auto_main(5, 1000, 8)
	var bank: SoundBank = main.sound_bank()
	_check(bank != null and main.get_node("SoundBank") == bank, "main 안에 SoundBank 노드")
	_check(AudioServer.get_bus_index(SoundBank.BUS_SFX) != -1 and AudioServer.get_bus_index(SoundBank.BUS_BGM) != -1, "SFX / BGM 오디오 버스가 만들어짐")
	_check(bank.get_child_count() == SoundBank.VOICES + SoundBank.LOOP_NAMES.size(), "재생기 %d개 + 반복음 재생기" % SoundBank.VOICES)
	_check(DisplayServer.get_name() != "headless" or not bank.playback_enabled, "헤드리스에서는 실제 재생 없이 요청만 기록 (소리 장치 없이도 에러 없음)")
	# 당첨 크기 기준 (총 지급 ÷ 총 베팅)
	var mid: float = 2.0
	var big: float = 10.0
	_check(SoundBank.win_sound_for(0, 8, mid, big) == &"", "당첨 0이면 당첨 소리 없음")
	_check(SoundBank.win_sound_for(15, 8, mid, big) == SoundBank.NAME_WIN_SMALL, "15 ÷ 8 = 1.9배 → win_small")
	_check(SoundBank.win_sound_for(16, 8, mid, big) == SoundBank.NAME_WIN_MID, "16 ÷ 8 = 2배 → win_mid (경계 포함)")
	_check(SoundBank.win_sound_for(79, 8, mid, big) == SoundBank.NAME_WIN_MID, "79 ÷ 8 = 9.9배 → win_mid")
	_check(SoundBank.win_sound_for(80, 8, mid, big) == SoundBank.NAME_WIN_BIG, "80 ÷ 8 = 10배 → win_big (경계 포함)")
	_check(SoundBank.win_sound_for(10, 0, mid, big) == SoundBank.NAME_WIN_BIG, "총 베팅 0이어도 나누기 오류 없음")
	# COIN / BET / MAX BET / CANCEL / 거절
	bank.clear_requests()
	GameState.insert_coin()
	_check(_sound_log(bank) == "coin", "COIN → coin")
	bank.clear_requests()
	_check(main.press_bet() and _sound_log(bank) == "bet", "BET → bet")
	bank.clear_requests()
	_check(main.press_max_bet() and _sound_log(bank) == "bet", "MAX BET → bet")
	bank.clear_requests()
	_check(not main.press_max_bet() and _sound_log(bank) == "", "이미 최대인 MAX BET은 소리 없음")
	bank.clear_requests()
	_check(main.press_cancel() and _sound_log(bank) == "cancel", "CANCEL → cancel")
	bank.clear_requests()
	_check(not main.press_cancel() and _sound_log(bank) == "", "베팅이 없을 때 CANCEL은 소리 없음")
	bank.clear_requests()
	_press(main, KEY_B)
	_check(_sound_log(bank) == "bet", "B 키도 BET → bet")
	bank.clear_requests()
	(main.get_node("BetButton") as Button).pressed.emit()
	_check(_sound_log(bank) == "bet", "BET 버튼 클릭도 bet")
	bank.clear_requests()
	GameState.credit = 0
	_check(not main.press_bet() and _sound_log(bank) == "cancel", "크레딧 없이 BET 거절 → cancel")
	GameState.credit = 1000
	# 요청 기록은 오래된 것부터 버림
	bank.clear_requests()
	for i: int in SoundBank.LOG_MAX + 20:
		bank.play(SoundBank.NAME_BUTTON)
	_check(bank.requests().size() == SoundBank.LOG_MAX, "요청 기록은 최대 %d개" % SoundBank.LOG_MAX)
	# 반복음은 한 번만 켜지고 한 번만 꺼짐
	bank.clear_requests()
	bank.play_loop(SoundBank.NAME_REEL_SPIN)
	bank.play_loop(SoundBank.NAME_REEL_SPIN)
	_check(_sound_log(bank) == "reel_spin" and bank.is_loop_on(SoundBank.NAME_REEL_SPIN), "반복음을 두 번 켜도 한 번만 시작")
	bank.stop_loop(SoundBank.NAME_REEL_SPIN)
	bank.stop_loop(SoundBank.NAME_REEL_SPIN)
	_check(_sound_log(bank) == "reel_spin,reel_spin:stop" and not bank.is_loop_on(SoundBank.NAME_REEL_SPIN), "반복음을 두 번 꺼도 한 번만 정지")
	# feel 키: 기본값·범위·중 < 대
	var feel: FeelConfig = FeelConfig.from_dict({})
	_check(feel.win_mid_ratio == 2.0 and feel.win_big_ratio == 10.0 and feel.sfx_volume_db == 0.0, "효과음 키 기본값: win_mid_ratio 2 / win_big_ratio 10 / sfx_volume_db 0")
	var swapped: FeelConfig = FeelConfig.from_dict({ "win_mid_ratio": 5.0, "win_big_ratio": 3.0 })
	_check(swapped.win_mid_ratio == 2.0 and swapped.win_big_ratio == 10.0, "중 기준이 대 기준 이상이면 둘 다 기본값")
	_check(FeelConfig.from_dict({ "sfx_volume_db": 99.0 }).sfx_volume_db == 0.0 and FeelConfig.from_dict({ "sfx_volume_db": -60.0 }).sfx_volume_db == 0.0, "sfx_volume_db 범위(-40~6) 밖은 기본값")
	# SFX 볼륨은 스핀 시작 때 새 설정으로 적용
	main.set_feel_path(FEEL_TEMP_PATH)
	_write_feel_file(FEEL_TEMP_PATH, { "sfx_volume_db": -6.0 })
	main.reload_feel()
	GameState.credit = 1000
	main.press_bet()
	main.do_spin()
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(SoundBank.BUS_SFX)), -6.0), "sfx_volume_db가 SFX 버스에 적용됨 (다음 스핀부터)")
	_settle(main)
	_write_feel_file(FEEL_TEMP_PATH, {})
	main.reload_feel()
	main.set_feel_path(FeelConfig.DEFAULT_PATH)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SoundBank.BUS_SFX), 0.0)
	main.free()
	await get_tree().process_frame


## 피버·풀 없는 한 판: start → 회전음 → 릴 정지 ×3 → 회전음 끝 → (당첨이면) 크기별 당첨음
func _test_sound_spin() -> void:
	var win_seed: int = _sound_find_plain_win_seed()
	var lose_seed: int = _auto_find_seed(1000, 8, false)
	_check(win_seed > 0 and lose_seed > 0, "일반 당첨·무당첨 시드를 찾음")
	if win_seed <= 0 or lose_seed <= 0:
		return
	var main: Control = await _auto_main(lose_seed, 1000, 8)
	var bank: SoundBank = main.sound_bank()
	bank.clear_requests()
	main.do_spin()
	_advance_for(main, 1.0)
	_check(bank.is_loop_on(SoundBank.NAME_REEL_SPIN), "릴이 도는 동안 회전음이 켜져 있음")
	_settle(main)
	_check(not bank.is_loop_on(SoundBank.NAME_REEL_SPIN), "릴이 모두 멈추면 회전음이 꺼짐")
	_check(GameState.last_win == 0 and _sound_log(bank) == "start,reel_spin,reel_stop,reel_stop,reel_stop,reel_spin:stop", "무당첨: start → 회전음 → 릴 정지 ×3 → 회전음 끝, 당첨음 없음 (%s)" % _sound_log(bank))
	main.free()
	await get_tree().process_frame
	main = await _auto_main(win_seed, 1000, 8)
	bank = main.sound_bank()
	bank.clear_requests()
	main.do_spin()
	_settle(main)
	var feel: FeelConfig = main.feel()
	var want: StringName = SoundBank.win_sound_for(GameState.last_win, 8, feel.win_mid_ratio, feel.win_big_ratio)
	_check(GameState.last_win > 0 and want != &"", "당첨 판 (WIN %d)" % GameState.last_win)
	_check(_sound_log(bank) == "start,reel_spin,reel_stop,reel_stop,reel_stop,reel_spin:stop,%s" % want, "일반 당첨: 마지막에 크기에 맞는 당첨음 %s (%s)" % [want, _sound_log(bank)])
	main.free()
	await get_tree().process_frame


## 첫 판이 일반 당첨(라인만, 피버·풀 없음)인 시드
func _sound_find_plain_win_seed() -> int:
	for candidate: int in range(1, 400):
		GameState.initialize(GameState.get_balance(), GameState.load_economy(), candidate)
		GameState.credit = 1000
		while GameState.bet != 8:
			GameState.raise_bet()
		var result: SpinResult = GameState.play_spin()
		if result.total_payout() > 0 and result.fever_triggers.is_empty() and result.pool_won == 0:
			return candidate
	return -1


## 피버: 단계마다 fever_start (풀 단계는 pool_get), 끝까지 보면 fever_end, 당첨음은 없음. 건너뛰면 한꺼번에 오는 단계 알림에 소리가 쌓이지 않고 연출 소리를 끊음.
func _test_sound_fever() -> void:
	var data: BalanceData = _fever_test_data()
	var multi_n: int = _find_fever_spin(data, 2)
	var pool_n: int = _find_pool_spin(data)
	_check(multi_n >= 0 and pool_n >= 0, "소리 시험용 피버 2개 스핀·풀 획득 스핀을 찾음")
	if multi_n < 0 or pool_n < 0:
		return
	for n: int in [multi_n, pool_n]:
		var main: Control = await _fever_world(data, n)
		var bank: SoundBank = main.sound_bank()
		var overlay: FeverOverlay = main.get_node("FeverOverlay")
		bank.clear_requests()
		main.do_spin()
		_settle(main)
		var fever_steps: int = 0
		var pool_steps: int = 0
		for i: int in overlay.step_count():
			if overlay.step_at(i)["kind"] == FeverOverlay.KIND_POOL:
				pool_steps += 1
			else:
				fever_steps += 1
		var tag: String = "풀 획득 스핀" if n == pool_n else "피버 2개 스핀"
		_check(_sound_count(bank, SoundBank.NAME_FEVER_START) == fever_steps and _sound_count(bank, SoundBank.NAME_POOL_GET) == pool_steps, "%s: 단계마다 fever_start %d / pool_get %d (%s)" % [tag, fever_steps, pool_steps, _sound_log(bank)])
		_check(_sound_count(bank, SoundBank.NAME_FEVER_END) == 1 and bank.requests()[bank.requests().size() - 1] == SoundBank.NAME_FEVER_END, "%s: 끝까지 보면 마지막에 fever_end 한 번" % tag)
		_check(_sound_count(bank, SoundBank.NAME_WIN_SMALL) + _sound_count(bank, SoundBank.NAME_WIN_MID) + _sound_count(bank, SoundBank.NAME_WIN_BIG) == 0, "%s: 연출이 있으면 당첨 크기 소리는 생략" % tag)
		main.free()
		await get_tree().process_frame
	# 건너뛰기
	var skip_main: Control = await _fever_world(data, multi_n)
	var skip_bank: SoundBank = skip_main.sound_bank()
	skip_bank.clear_requests()
	skip_main.do_spin()
	_check(_advance_to_fever(skip_main), "건너뛰기 시험: 피버 연출 시작")
	skip_main.advance(0.6)
	var before: int = _sound_count(skip_bank, SoundBank.NAME_FEVER_START)
	skip_main.do_spin()
	_check(not skip_main.fever_playing() and not GameState.spinning, "건너뛰기: 연출 종료 + 정산")
	_check(before == 1 and _sound_count(skip_bank, SoundBank.NAME_FEVER_START) == 1 and _sound_count(skip_bank, SoundBank.NAME_POOL_GET) == 0, "건너뛰어도 남은 단계의 fever_start가 쌓이지 않음 (%s)" % _sound_log(skip_bank))
	_check(_sound_count(skip_bank, SoundBank.CUT_MARK) == 1 and _sound_count(skip_bank, SoundBank.NAME_FEVER_END) == 0, "건너뛰면 연출 소리를 끊고(cut) 마무리음은 없음")
	skip_main.free()
	await get_tree().process_frame


## AUTO: 켜기·끄기만 button, 판이 이어져도 판마다 start와 회전음은 매번 나고 button은 쌓이지 않음
func _test_sound_auto() -> void:
	var main: Control = await _auto_main(7, 5000, 8)
	var bank: SoundBank = main.sound_bank()
	bank.clear_requests()
	GameState.toggle_auto()
	_check(_sound_log(bank).begins_with("button,start") and _sound_count(bank, SoundBank.NAME_BUTTON) == 1, "AUTO 켜기 → button (쉬는 중이면 바로 첫 판이 시작되어 start가 이어짐)")
	bank.clear_requests()
	var frames: int = 0
	while GameState.auto_count() < 3 and frames < 20000:
		main.advance(FRAME_DT)
		frames += 1
	_check(GameState.auto_count() >= 3, "AUTO로 판이 이어짐 (%d회)" % GameState.auto_count())
	_check(_sound_count(bank, SoundBank.NAME_BUTTON) == 0, "AUTO 중 판이 시작될 때마다 button이 울리지 않음")
	var starts: int = _sound_count(bank, SoundBank.NAME_START)
	_check(starts >= 2 and _sound_count(bank, SoundBank.NAME_REEL_SPIN) >= starts - 1, "판마다 start와 회전음이 매번 남 (start %d / 회전음 %d)" % [starts, _sound_count(bank, SoundBank.NAME_REEL_SPIN)])
	bank.clear_requests()
	GameState.toggle_auto()
	_check(_sound_log(bank) == "button", "AUTO 끄기 → button")
	_settle(main)
	main.free()
	await get_tree().process_frame


## 6-E: 피버·풀 오버레이가 새 그림(배경·배너·심볼 칸·동전)과 정해 둔 위치·크기로 만들어졌는지, 단계마다 맞는 것만 보이는지
func _test_overlay_art() -> void:
	var overlay: FeverOverlay = FeverOverlay.new()
	add_child(overlay)
	await get_tree().process_frame
	_check(overlay.size == Vector2(640, 480) and overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "오버레이: 입력은 화면 전체(640×480)를 막음")
	var bg: TextureRect = overlay.get_node("BgFrame") as TextureRect
	_check(bg.position == Vector2.ZERO and bg.size == Vector2(640, 414) and bg.texture.get_size() == Vector2(640, 414), "배경 프레임 640×414: 하단 표시창(y=414) 위까지만 덮음")
	var fever_banner: TextureRect = overlay.get_node("BannerFever") as TextureRect
	var pool_banner: TextureRect = overlay.get_node("BannerPool") as TextureRect
	_check(fever_banner.size == Vector2(360, 84) and fever_banner.position == Vector2(138, 30), "FEVER! 배너 360×84 (138,30)")
	_check(pool_banner.size == Vector2(408, 84) and pool_banner.position == Vector2(114, 30), "POOL GET! 배너 408×84 (114,30)")
	var tile: TextureRect = overlay.get_node("SymbolTile") as TextureRect
	_check(tile.position == Vector2(264, 132) and tile.size == Vector2(108, 84) and tile.get_node("SymbolIcon") != null, "심볼 칸 타일 108×84 (264,132) + 심볼 그림")
	var plate: Panel = overlay.get_node("BonusPlate") as Panel
	_check(plate.position == Vector2(66, 288) and plate.size == Vector2(504, 84), "BONUS 판 504×84 (66,288)")
	var coins: Control = overlay.get_node("CoinRow") as Control
	var coins_ok: bool = coins.get_child_count() == FeverOverlay.COIN_ROW_COUNT
	for coin: Node in coins.get_children():
		coins_ok = coins_ok and (coin as TextureRect).size == Vector2(24, 24) and (coin as TextureRect).texture is AtlasTexture
	_check(coins_ok, "풀 단계 동전 줄: 동전 5개, 24×24 (크기는 6-F에서 조정)")
	var hint: Label = null
	for child: Node in overlay.get_children():
		if child is Label and (child as Label).text == FeverOverlay.HINT_TEXT:
			hint = child as Label
	_check(hint != null and hint.position.y == 390.0 and hint.position.y + hint.size.y == 414.0, "건너뛰기 힌트 y=390 (그림 영역 맨 아래, 표시창을 가리지 않음)")
	var ignores: bool = true
	for node: Node in overlay.find_children("*", "Control", true, false):
		ignores = ignores and (node as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE
	_check(ignores, "오버레이 안의 그림·글자는 모두 클릭 통과 (막는 것은 오버레이 본체뿐)")
	# 피버 단계 → 풀 단계 (금액은 5자리·6자리까지 판 안에 들어가는지)
	var steps: Array[Dictionary] = [
		{ "kind": FeverOverlay.KIND_FEVER, "symbol": "SEVEN", "name": "세븐", "bonus": 123456 },
		{ "kind": FeverOverlay.KIND_POOL, "symbol": "", "name": FeverOverlay.POOL_NAME_TEXT, "bonus": 12345 },
	]
	overlay.play(steps, 1.0, 0.3, 0.0, 1.0)
	var label: Label = overlay.get_node("BonusPlate/BonusLabel") as Label
	var name_label: Label = overlay.get_node("NameLabel") as Label
	_check(bg.visible and fever_banner.visible and not pool_banner.visible and tile.visible and not coins.visible and name_label.visible, "피버 단계: FEVER! 배너·심볼 칸·이름 줄만 보임")
	_check(overlay.shown_texts() == { "title": "FEVER!", "name": "세븐", "bonus": "BONUS +123456" }, "피버 단계 글자 FEVER! / 이름 / BONUS +금액")
	_check(label.get_minimum_size().x <= plate.size.x, "피버 금액 6자리(BONUS +123456)가 판 안에 들어감 (%d / %d px)" % [label.get_minimum_size().x, plate.size.x])
	overlay.advance(1.0)
	_check(not overlay.is_showing_step() and bg.visible and not fever_banner.visible and not plate.visible, "단계 사이 간격: 배경만 보임")
	overlay.advance(0.3)
	_check(bg.visible and pool_banner.visible and not fever_banner.visible and not tile.visible and coins.visible and not name_label.visible and plate.visible, "풀 단계: POOL GET! 배너·동전 줄·금액 판만 보임 (이름 줄 없음)")
	_check(overlay.shown_texts() == { "title": "POOL GET!", "name": "", "bonus": "POOL +12345" }, "풀 단계 글자 POOL GET! / 이름 없음 / POOL +금액")
	_check(label.get_minimum_size().x <= plate.size.x, "풀 금액 5자리(POOL +12345, ×4)가 판 안에 들어감 (%d / %d px)" % [label.get_minimum_size().x, plate.size.x])
	overlay.set_bg_frame(2)
	overlay.set_banner_variant(1)
	_check(overlay.get_node("BgFrame").texture.resource_path.ends_with("pool_bg_2.png") and pool_banner.texture.resource_path.ends_with("pool_banner_b.png"), "배경 프레임·배너 색 변형 바꾸기 (6-F용)")
	overlay.skip()
	_check(not overlay.visible and not bg.visible, "건너뛰기: 오버레이가 사라지고 배경도 숨음")
	_check(CoinSheet.sheet().get_size() == Vector2(144, 24) and CoinSheet.FRAME_COUNT == 6 and CoinSheet.frame(7).region == CoinSheet.frame(1).region, "동전 시트 144×24, 6프레임 (번호는 순환)")
	overlay.free()
	await get_tree().process_frame


## 6-D: 벽지·프레임·로고가 있고, 모든 기존 요소보다 뒤에 그려지며, 기존 요소 위치는 그대로인지
func _test_backdrop(main: Control) -> void:
	var wall: TextureRect = main.get_node_or_null("Wallpaper") as TextureRect
	var frame: TextureRect = main.get_node_or_null("Frame") as TextureRect
	var board: Control = main.get_node("Board")
	_check(wall != null and wall.texture != null and wall.texture.get_size() == Vector2(48, 48) and wall.stretch_mode == TextureRect.STRETCH_TILE, "벽지: 48×48 타일을 반복해서 깖")
	_check(frame != null and frame.texture != null and frame.texture.get_size() == Vector2(640, 480), "프레임: 640×480 그림")
	if wall == null or frame == null:
		return
	_check(wall.get_index() == 1 and frame.get_index() == 2 and main.get_node("Background").get_index() == 0, "그리는 순서: Background < Wallpaper < Frame")
	var behind: bool = true
	for child: Node in main.get_children():
		if child != main.get_node("Background") and child != wall and child != frame:
			behind = behind and child.get_index() > frame.get_index()
	_check(behind and board.get_index() > frame.get_index(), "벽지·프레임이 다른 모든 요소보다 뒤")
	_check(wall.mouse_filter == Control.MOUSE_FILTER_IGNORE and frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "벽지·프레임은 클릭을 막지 않음")
	_check(wall.size == Vector2(640, 480) and frame.size == Vector2(640, 480) and wall.position == Vector2.ZERO and frame.position == Vector2.ZERO, "벽지·프레임이 화면 전체를 덮음")
	var logo: TextureRect = main.get_node("Title").get_node_or_null("TitleLogo") as TextureRect
	_check(logo != null and logo.texture != null and logo.size == Vector2(180, 72) and logo.position == Vector2.ZERO and logo.texture.get_size() == Vector2(180, 72), "로고: Title 안에 180×72")
	_check(logo != null and logo.mouse_filter == Control.MOUSE_FILTER_IGNORE, "로고는 클릭을 막지 않음")
	var rects: Dictionary = {
		"Board": Rect2(42, 36, 348, 276), "AutoButton": Rect2(384, 318, 60, 33),
		"StopButton1": Rect2(60, 318, 96, 33), "StopButton2": Rect2(168, 318, 96, 33), "StopButton3": Rect2(276, 318, 96, 33),
	}
	var moved: bool = false
	for node_name: String in rects:
		var node: Control = main.get_node(node_name)
		var rect: Rect2 = rects[node_name]
		if node.position != rect.position or node.size != rect.size:
			moved = true
			print("  위치 변경: ", node_name, " ", node.position, node.size)
	_check(not moved, "보드·STOP·AUTO 위치가 6-D 전과 동일")
	_check((main.get_node("Reels") as Control).get_child(0).position == Vector2(54, 48), "첫 릴 위치 (54,48) 그대로")


## 6-C: 오른쪽 패널·하단 표시창·버튼 줄·아이콘·폰트가 목표 배치(640×480)와 맞는지, 글자가 상자 밖으로 넘치지 않는지
func _test_ui_layout(main: Control) -> void:
	var rects: Dictionary = {
		"Title": Rect2(450, 9, 180, 72), "PoolBox": Rect2(450, 87, 180, 42),
		"FeverBox": Rect2(450, 135, 180, 132), "PaytablePanel": Rect2(450, 273, 180, 138),
		"CreditBox": Rect2(9, 414, 150, 57), "NoticeBox": Rect2(165, 414, 264, 57),
		"WinBox": Rect2(435, 414, 96, 57), "BetBox": Rect2(537, 414, 93, 57),
		"ButtonStrip": Rect2(6, 354, 444, 48),
	}
	var rects_ok: bool = true
	for node_name: String in rects:
		var node: Control = main.get_node(node_name)
		var rect: Rect2 = rects[node_name]
		if node.position != rect.position or node.size != rect.size:
			rects_ok = false
			print("  배치 불일치: ", node_name, " ", node.position, node.size)
	_check(rects_ok, "오른쪽 패널·하단 표시창·버튼 띠 위치와 크기가 목표대로")
	var xs: Array = [15.0, 102.0, 189.0, 276.0, 363.0]
	var names: Array = ["CancelButton", "CoinButton", "StartButton", "BetButton", "MaxBetButton"]
	var buttons_ok: bool = true
	for i: int in names.size():
		var button: Button = main.get_node(names[i])
		buttons_ok = buttons_ok and button.position == Vector2(xs[i], 360) and button.size == Vector2(81, 36)
	_check(buttons_ok, "버튼 5개 y=360, 81×36, x=15/102/189/276/363")
	var skin_ok: bool = true
	for node_name: String in ["CancelButton", "StopButton1", "StartButton"]:
		var button: Button = main.get_node(node_name)
		for state: String in ["normal", "pressed", "disabled"]:
			skin_ok = skin_ok and button.get_theme_stylebox(state) is StyleBoxTexture
	_check(skin_ok, "버튼(STOP 포함)이 3상태 그림 스킨을 씀")
	var pressed: StyleBoxTexture = (main.get_node("StartButton") as Button).get_theme_stylebox("pressed")
	_check(pressed.content_margin_top - pressed.content_margin_bottom == 6.0, "눌린 버튼은 글자가 3px(아트 1px) 내려감")
	_check((main.get_node("StartButton") as Button).get_theme_color("font_disabled_color") == Color("6b7099"), "비활성 버튼 글자색 #6b7099")
	var font: FontFile = main.get_theme_default_font() as FontFile
	_check(font != null and font.antialiasing == TextServer.FONT_ANTIALIASING_NONE and font.hinting == TextServer.HINTING_NONE 			and font.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED, "기본 폰트: 갈무리, 안티앨리어싱·힌팅·서브픽셀 끔")
	_check(font != null and font.resource_path.ends_with("Galmuri11.ttf") and main.get_theme_default_font_size() == 12, "기본 글자 갈무리11 12px (원래 크기 ×1)")
	var sizes_ok: bool = true
	for face: UiFont.Face in UiFont.NATIVE_SIZES:
		sizes_ok = sizes_ok and UiFont.size_of(face, 3) == 3 * int(UiFont.NATIVE_SIZES[face])
	_check(sizes_ok, "도트 폰트 크기는 원래 크기의 정수배")
	_check(_box(main, "CreditBox").value_color() == Color("7dff9a") and _box(main, "WinBox").value_color() == Color("ffe14d") 			and _box(main, "PoolBox").value_color() == Color("ff9a1f") and _box(main, "BetBox").value_color() == Color("ffffff"), "숫자 색: CREDIT #7dff9a / WIN #ffe14d / POOL #ff9a1f / BET 흰색")
	_check(_box(main, "CreditBox").title_label().get_theme_color("font_color") == Color("9aa0c8"), "라벨 글자색 #9aa0c8")
	_check(SymbolCell.FRAME_WIDTH == 3 and SymbolCell.FRAME_COLOR == Color("ffe14d"), "당첨 강조: 금색 #ffe14d 3px")
	_check(main.DEBUG_RECT.end.y <= 414.0, "디버그 창이 하단 표시창 위에서 끝남")
	_test_ui_icons(main)
	_test_number_shrink(main)
	_test_ui_text_fits(main)


## 큰 숫자가 칸 폭을 넘으면 글자가 반(원래 크기의 정수배)으로 줄고, 원래 숫자로 돌아오면 다시 커짐
func _test_number_shrink(main: Control) -> void:
	var win: InfoBox = _box(main, "WinBox")
	var before: String = win.value_text()
	win.set_value("0")
	_check(win.value_font_size_now() == 24, "WIN 짧은 숫자는 24px")
	win.set_value("12345678")
	_check(win.value_font_size_now() == 12 and win.value_min_size().x <= win.value_area().size.x, "WIN 8자리는 12px로 줄어 칸 안에 들어감")
	win.set_value(before)
	_check(win.value_font_size_now() == 24, "짧은 숫자로 돌아오면 다시 24px")


func _test_ui_icons(main: Control) -> void:
	var fever: FeverPanel = _fever(main)
	var data: BalanceData = GameState.get_balance()
	var fever_ok: bool = true
	var seven_red: bool = true
	for symbol: String in data.fever_symbols:
		var icon: TextureRect = fever.icon_of(symbol)
		fever_ok = fever_ok and icon.texture != null and icon.size == icon.texture.get_size() * 2.0
		fever_ok = fever_ok and Rect2(Vector2.ZERO, fever.size).encloses(Rect2(icon.position, icon.size))
	seven_red = fever.normal_count_color("SEVEN") == Color("e8283c") and fever.count_color("SEVEN") == Color("e8283c")
	_check(fever_ok, "피버 카운터 아이콘이 아트 ×2(24×20) 크기로 패널 안에 있음")
	_check(seven_red, "세븐 개수는 빨간색 #e8283c")
	_test_fever_rows(fever, data)
	var table: PaytablePanel = main.get_node("PaytablePanel")
	var left: Array = ["CHERRY", "MELON", "BELL", "BAR"]
	var right: Array = ["ORANGE", "GRAPE", "SEVEN"]
	var cols_ok: bool = true
	for symbol: String in left:
		cols_ok = cols_ok and table.icon_of(symbol).position.x < 90.0
	for symbol: String in right:
		cols_ok = cols_ok and table.icon_of(symbol).position.x >= 90.0
	for i: int in left.size() - 1:
		cols_ok = cols_ok and table.icon_of(left[i]).position.y < table.icon_of(left[i + 1]).position.y
	for i: int in right.size() - 1:
		cols_ok = cols_ok and table.icon_of(right[i]).position.y < table.icon_of(right[i + 1]).position.y
	_check(cols_ok, "배당표 2열: 왼쪽 체리·수박·벨·BAR / 오른쪽 오렌지·포도·세븐 (위→아래)")
	var icons_ok: bool = true
	for symbol: String in data.symbol_ids:
		var icon: TextureRect = table.icon_of(symbol)
		icons_ok = icons_ok and icon.texture != null and icon.size == icon.texture.get_size() * 2.0
		icons_ok = icons_ok and table.multiplier_label_of(symbol).horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT
	_check(icons_ok, "배당표 아이콘(12×10, BAR 15×10)이 정수 배율, 배수는 오른쪽 정렬")
	var dividers: int = 0
	var divider_color_ok: bool = true
	for child: Node in table.get_children():
		if child is ColorRect:
			dividers += 1
			divider_color_ok = divider_color_ok and (child as ColorRect).color == Color("0e1130")
	_check(dividers == 3 + 2 + 1 and divider_color_ok, "배당표 구분선(가로 5 + 세로 1)이 어두운 색 #0e1130")


## 피버 카운터: 4행 1열, 행 높이 26, 아이콘은 같은 x, 개수는 같은 오른쪽 끝(고정 열)에 오른쪽 정렬
func _test_fever_rows(fever: FeverPanel, data: BalanceData) -> void:
	_check(data.fever_symbols == PackedStringArray(["CHERRY", "GRAPE", "BELL", "SEVEN"]), "피버 대상 순서: 체리, 포도, 벨, 세븐")
	var rows_ok: bool = true
	var icon_x: float = fever.icon_of(data.fever_symbols[0]).position.x
	var right_edge: float = fever.count_label_of(data.fever_symbols[0]).position.x + fever.count_label_of(data.fever_symbols[0]).size.x
	var title: Label = fever.get_node("Title")
	var previous_y: float = title.position.y + title.get_combined_minimum_size().y
	for symbol: String in data.fever_symbols:
		var icon: TextureRect = fever.icon_of(symbol)
		var label: Label = fever.count_label_of(symbol)
		rows_ok = rows_ok and icon.position.x == icon_x
		rows_ok = rows_ok and label.position.x + label.size.x == right_edge and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT
		rows_ok = rows_ok and label.size.y == 26.0 and label.position.y >= previous_y
		rows_ok = rows_ok and absf((icon.position.y + icon.size.y / 2.0) - (label.position.y + label.size.y / 2.0)) < 0.01
		previous_y = label.position.y + label.size.y
	_check(rows_ok, "피버 카운터 4행 1열: 아이콘 x 고정, 개수 오른쪽 끝 고정·오른쪽 정렬, 행 높이 26, 제목 아래에서 시작")
	_check(previous_y <= fever.size.y - 6.0 and right_edge <= fever.size.x - 6.0, "피버 카운터 4행이 패널(132) 안쪽 여백 안에 모두 들어감")
	var same_size: bool = true
	for symbol: String in data.fever_symbols:
		same_size = same_size and fever.count_label_of(symbol).get_theme_font_size("font_size") == 20
	_check(same_size, "피버 개수 글자 20px (갈무리9 ×2, 아이콘 높이 20과 맞춤)")


## 모든 글자 칸의 최소 크기가 자기 칸(부모 패널) 안에 들어가는지: 넘치면 글자가 잘린다
func _test_ui_text_fits(main: Control) -> void:
	var problems: PackedStringArray = PackedStringArray()
	for node_name: String in ["PoolBox", "CreditBox", "WinBox", "BetBox", "NoticeBox", "FeverBox", "PaytablePanel"]:
		var panel: Control = main.get_node(node_name)
		for child: Node in panel.get_children():
			var label: Label = child as Label
			if label == null:
				continue
			var need: Vector2 = label.get_combined_minimum_size()
			if label.autowrap_mode == TextServer.AUTOWRAP_OFF and need.x > label.size.x + 0.5:
				problems.append("%s/%s 폭 %s > %s" % [node_name, label.name, need.x, label.size.x])
			if need.y > label.size.y + 0.5 and label.autowrap_mode == TextServer.AUTOWRAP_OFF:
				problems.append("%s/%s 높이 %s > %s" % [node_name, label.name, need.y, label.size.y])
	for message: String in problems:
		print("  글자 넘침: ", message)
	_check(problems.is_empty(), "패널 안 글자가 칸 밖으로 넘치지 않음 (초기 화면)")


func _test_paytable(main: Control) -> void:
	var data: BalanceData = GameState.get_balance()
	var panel: PaytablePanel = main.get_node("PaytablePanel")
	_check(panel.row_count() == data.symbol_count(), "배당표 줄 수 = 심볼 수")
	var all_match: bool = true
	for symbol: String in data.symbol_ids:
		all_match = all_match and panel.multiplier_text(symbol) == "×%d" % data.paytable[symbol]
	_check(all_match, "배당표 숫자 = balance.json")
	var fever: Control = main.get_node("FeverBox")
	_check(panel.position.y >= fever.position.y + fever.size.y, "배당표가 피버 카운터 아래")
	_check(panel.position.y + panel.size.y <= 420.0, "배당표가 하단 바 위")


## 깜빡임 시계를 0으로 돌린 뒤 켜짐(주기의 3/4 지점) 또는 꺼짐(1/4 지점) 상태로 맞춘다
func _set_blink(main: Control, on: bool) -> void:
	main.set("_blink_time", 0.0)
	main.advance(main.BLINK_PERIOD * (0.75 if on else 0.25))


func _test_fever_panel(main: Control) -> void:
	var data: BalanceData = GameState.get_balance()
	var panel: FeverPanel = _fever(main)
	_check(panel.row_count() == data.fever_symbols.size(), "피버 카운터 줄 수 = balance.json 피버 대상 수")
	var expected: PackedStringArray = PackedStringArray()
	for symbol: String in data.fever_symbols:
		expected.append("%s ×%d" % [data.symbol_names[symbol], data.fever_initial_counts[symbol]])
	_check(panel.value_text() == "\n".join(expected), "처음 피버 카운터 숫자 = balance.json 초기값")
	_set_blink(main, true)
	var none_flash: bool = true
	for symbol: String in data.fever_symbols:
		none_flash = none_flash and not panel.is_flashing(symbol)
	_check(none_flash, "초기 카운터에서는 깜빡이는 줄이 없음 (세븐 초기값 1도 제외)")
	# 마지막 1회: 초기값 2 이상인 심볼만 깜빡인다. 세븐(초기값 1)은 항상 1이어도 제외.
	var counts: Dictionary[String, int] = {}
	for symbol: String in data.fever_symbols:
		counts[symbol] = 1
	main._refresh_side_panel(GameState.get_pool(), counts)
	for symbol: String in data.fever_symbols:
		var should_blink: bool = data.fever_initial_counts[symbol] >= 2
		_set_blink(main, true)
		_check(panel.is_last_one(symbol) == should_blink and panel.is_flashing(symbol) == should_blink, "남은 1회: %s 깜빡임 켜짐 = %s (초기값 %d)" % [symbol, should_blink, data.fever_initial_counts[symbol]])
		_check((panel.count_color(symbol) == FeverPanel.LAST_ONE_COLOR) == should_blink, "남은 1회: %s 켜짐일 때 글자색 = 강조색 여부 %s" % [symbol, should_blink])
		_set_blink(main, false)
		_check(not panel.is_flashing(symbol) and panel.count_color(symbol) == panel.normal_count_color(symbol), "남은 1회: %s 꺼짐일 때 평소 색" % symbol)
	# 남은 횟수가 2 이상이면 켜짐 때도 깜빡이지 않음
	for symbol: String in data.fever_symbols:
		counts[symbol] = maxi(2, data.fever_initial_counts[symbol])
	main._refresh_side_panel(GameState.get_pool(), counts)
	_set_blink(main, true)
	var calm: bool = true
	for symbol: String in data.fever_symbols:
		calm = calm and not panel.is_flashing(symbol)
	_check(calm, "남은 횟수 2 이상이면 깜빡이지 않음")
	main._refresh_side_panel(GameState.get_pool(), GameState.get_fever_counts())


func _test_pool_color(main: Control) -> void:
	var feel: FeelConfig = main.feel()
	var yellow: int = int(feel.pool_yellow_from)
	var red: int = int(feel.pool_red_from)
	_check(main.pool_tier(yellow - 1) == main.POOL_TIER_NORMAL and main.pool_tier(0) == main.POOL_TIER_NORMAL, "POOL 노랑 기준 미만은 기본(주황) 단계")
	_check(main.pool_tier(yellow) == main.POOL_TIER_YELLOW and main.pool_tier(red - 1) == main.POOL_TIER_YELLOW, "POOL 노랑 기준 이상·빨강 기준 미만은 노랑 단계")
	_check(main.pool_tier(red) == main.POOL_TIER_RED and main.pool_tier(red * 10) == main.POOL_TIER_RED, "POOL 빨강 기준 이상은 빨강 단계")
	var pool_box: InfoBox = _box(main, "PoolBox")
	var counts: Dictionary[String, int] = GameState.get_fever_counts()
	main._refresh_side_panel(yellow - 1, counts)
	_check(pool_box.value_text() == str(yellow - 1) and pool_box.value_color() == main.POOL_COLOR, "POOL 기본 단계: 숫자와 주황")
	main._refresh_side_panel(yellow, counts)
	_check(pool_box.value_color() == main.POOL_COLOR_YELLOW, "POOL 노랑 기준 도달: 노랑")
	_set_blink(main, false)
	main._refresh_side_panel(red, counts)
	var off_color: Color = pool_box.value_color()
	_set_blink(main, true)
	var on_color: Color = pool_box.value_color()
	_check(off_color == main.POOL_COLOR_RED_DIM and on_color == main.POOL_COLOR_RED, "POOL 빨강 단계: 깜빡임 꺼짐/켜짐에 따라 색이 바뀜")
	_set_blink(main, true)
	main._refresh_side_panel(yellow, counts)
	_check(pool_box.value_color() == main.POOL_COLOR_YELLOW, "POOL이 빨강 기준 아래로 내려가면 깜빡임 없이 노랑")
	main._refresh_side_panel(GameState.get_pool(), GameState.get_fever_counts())
	_check(pool_box.value_text() == str(GameState.get_pool()), "POOL 표시를 원래 값으로 되돌림")


func _test_max_and_cancel(main: Control) -> void:
	var max_button: Button = main.get_node("MaxBetButton")
	var cancel_button: Button = main.get_node("CancelButton")
	GameState.credit = 30
	GameState.cancel_bet()
	GameState.refresh()
	_check(cancel_button.disabled, "베팅 0이면 CANCEL 비활성")
	_check(not max_button.disabled, "크레딧 30, 베팅 0이면 MAX BET 활성")
	_press(main, KEY_M)
	_check(GameState.bet == 30 and _box(main, "BetBox").value_text() == "30", "M = MAX BET (min(최대, 30))")
	_check(max_button.disabled and not cancel_button.disabled, "MAX BET 후 MAX BET 비활성, CANCEL 활성")
	_press(main, KEY_X)
	_check(GameState.bet == 0 and _box(main, "BetBox").value_text() == "0", "X = CANCEL")
	_check(GameState.credit == 30 and _box(main, "CreditBox").value_text() == "30", "CANCEL 후 크레딧 그대로")
	GameState.credit = 0
	GameState.refresh()
	_check(max_button.disabled and cancel_button.disabled, "크레딧 0이면 MAX BET·CANCEL 모두 비활성")
	GameState.credit = 500
	GameState.max_bet()
	_check(GameState.bet == GameState.get_balance().max_total_bet, "크레딧 500이면 MAX BET = 최대 베팅")
	GameState.cancel_bet()
	GameState.credit = GameState.coin_amount
	GameState.refresh()


func _test_keyboard(main: Control) -> void:
	_press(main, KEY_C)
	_check(GameState.credit == GameState.coin_amount, "C = COIN")
	_check(_box(main, "CreditBox").value_text() == str(GameState.credit), "COIN 후 CREDIT 표시")
	_press(main, KEY_B)
	_check(GameState.bet == 1, "B = BET +1")
	_check(_box(main, "BetBox").value_text() == "1", "BET 표시 1")
	_check(_box(main, "NoticeBox").value_text().contains("BET 8 이상이면 피버 적립"), "BET 8 미만이면 피버 안내")
	var before: int = GameState.credit
	_press(main, KEY_SPACE)
	_check(GameState.spinning and GameState.credit == before - 1, "스페이스 = START (정산 전에는 베팅만 차감)")
	_settle(main)
	_check(not GameState.spinning, "스페이스 스핀이 정산까지 끝남")
	_check(main.grid_matches_logic(), "스페이스 스핀 후 화면=로직")
	_press(main, KEY_ENTER)
	_check(GameState.spinning, "엔터 = START")
	_settle(main)
	_check(main.grid_matches_logic(), "엔터 스핀 후 화면=로직")


func _test_spins(main: Control) -> void:
	var overlay: LineOverlay = main.get_node("LineOverlay")
	var mismatches: int = 0
	var hud_errors: int = 0
	var wins_seen: int = 0
	var lowered_notice_seen: bool = false
	for i: int in spin_count:
		if GameState.credit < FULL_BET:
			GameState.insert_coin()
		while GameState.bet != FULL_BET:
			GameState.raise_bet()
		var result: SpinResult = main.do_spin()
		if result == null:
			mismatches += 1
			continue
		_run_spin(main, i % INPUT_MODES, result.stops)
		if not main.grid_matches_logic():
			mismatches += 1
			continue
		if not _hud_matches(main, overlay, result):
			hud_errors += 1
		if result.is_hit():
			wins_seen += 1
		if i % 50 == 0:
			await get_tree().process_frame
	_check(mismatches == 0, "화면 칸=로직 결과 (불일치 %d회)" % mismatches)
	_check(hud_errors == 0, "CREDIT/WIN/BET/POOL/피버/당첨 선 표시=로직 (불일치 %d회)" % hud_errors)
	_check(wins_seen > 0, "당첨 사례가 한 번 이상 나옴")
	_check(_final_errors == 0, "릴 정지 위치 == 로직 stops (어긋난 횟수 %d)" % _final_errors)
	_check(_strip_errors == 0, "회전 중 모든 프레임에서 보이는 심볼이 실제 릴 스트립 순서와 같음 (어긋난 프레임 %d)" % _strip_errors)
	_check(_window_errors == 0, "회전 중 모든 프레임에서 칸 창이 두 심볼로 빈틈없이 채워지고 잘라서 보여 줌 (어긋난 프레임 %d)" % _window_errors)
	_check(_window_moves == 0, "회전 중에도 9칸 창(테두리)의 위치·크기가 고정 (움직인 프레임 %d)" % _window_moves)
	_check(_delay_errors == 0, "릴별 출발 지연: 지연 전에는 정지 상태·STOP 불가, 지연 후 출발 (어긋난 프레임 %d)" % _delay_errors)
	_check(_early_reveal == 0, "정산 전에는 CREDIT·WIN·POOL·피버가 먼저 바뀌지 않음 (어긋난 프레임 %d)" % _early_reveal)
	_check(_lock_errors == 0, "회전 중 COIN·BET·MAX BET·CANCEL 잠금, STOP 버튼 상태 (어긋난 횟수 %d)" % _lock_errors)
	_check(_stuck_spins == 0, "모든 스핀이 제한 시간 안에 끝남 (%d)" % _stuck_spins)
	# 크레딧이 모자라 베팅이 내려간 상황의 안내 문구
	GameState.credit = 8
	while GameState.bet != FULL_BET:
		GameState.raise_bet()
	for tries: int in 200:
		GameState.credit = 8
		GameState.bet = FULL_BET
		var lost: SpinResult = main.do_spin()
		_settle(main)
		if lost != null and GameState.credit < FULL_BET:
			lowered_notice_seen = _box(main, "NoticeBox").value_text().contains("낮췄습니다")
			break
	_check(lowered_notice_seen, "베팅이 자동으로 낮아지면 안내 문구 표시")


## 한 번의 스핀 뒤 화면 숫자가 로직과 같은지 (같으면 true)
func _hud_matches(main: Control, overlay: LineOverlay, result: SpinResult) -> bool:
	var data: BalanceData = GameState.get_balance()
	if _box(main, "CreditBox").value_text() != str(GameState.credit):
		return false
	if _box(main, "WinBox").value_text() != str(result.total_payout()):
		return false
	if _box(main, "BetBox").value_text() != str(GameState.bet):
		return false
	if _box(main, "PoolBox").value_text() != str(result.pool_after):
		return false
	var rows: PackedStringArray = _fever(main).value_text().split("\n")
	for i: int in data.fever_symbols.size():
		var symbol: String = data.fever_symbols[i]
		if rows[i] != "%s ×%d" % [data.symbol_names[symbol], result.fever_counts_after[symbol]]:
			return false
	if overlay.win_line_count() != result.line_wins.size():
		return false
	if result.is_hit() != (overlay.lit_cell_count() > 0):
		return false
	if result.is_hit() and not _box(main, "NoticeBox").value_text().contains("당첨 %d = 라인 %d + 피버 %d + 풀 %d" % [result.total_payout(), result.line_payout, result.fever_bonus, result.pool_won]):
		return false
	return true


func _test_labels_follow_bet(main: Control) -> void:
	var overlay: LineOverlay = main.get_node("LineOverlay")
	GameState.credit = 1000
	while GameState.bet != 3:
		GameState.raise_bet()
	_check(overlay.label_text(0) == "A 1" and not overlay.label_is_dim(0), "BET 3: A 1 밝음")
	_check(overlay.label_text(2) == "C 1" and not overlay.label_is_dim(2), "BET 3: C 1 밝음")
	_check(overlay.label_is_dim(3), "BET 3: D 베팅 0이라 어둡게")
	_check(overlay.label_is_dim(7), "BET 3: H 베팅 0이라 어둡게")
	_check(overlay.win_line_count() == 0, "베팅을 바꾸면 이전 당첨 선이 지워짐")
	while GameState.bet != 9:
		GameState.raise_bet()
	_check(overlay.label_text(0) == "A 2", "BET 9: A 2")
	_check(overlay.label_text(7) == "H 1" and not overlay.label_is_dim(7), "BET 9: H 1 밝음")


# ---------------------------------------------------------------- 시간 진행 도우미

## 입력 없이 자동 정지·정산까지 시간을 흘린다.
func _settle(main: Control) -> void:
	var time: float = 0.0
	while GameState.spinning and time < MAX_SPIN_SEC:
		main.advance(FRAME_DT)
		time += FRAME_DT
	if GameState.spinning:
		_stuck_spins += 1


func _frame_dt() -> float:
	return SPIKE_DT if _rng.randf() < SPIKE_CHANCE else _rng.randf_range(0.004, 0.034)


## 입력 계획: 모드마다 STOP·START를 무작위 시각·순서로 누른다.
## 0 = 입력 없음(자동 정지), 1 = STOP 3개를 무작위 순서·시각에 키보드로, 2 = 회전 중 START,
## 3 = 일부는 버튼 클릭, 일부는 키, 가끔 START를 섞음
func _make_plan(mode: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var reels: Array[int] = [0, 1, 2]
	reels.shuffle()
	if mode == 1:
		for reel: int in reels:
			plan.append({ "time": _rng.randf_range(0.0, 2.5), "kind": "key", "reel": reel, "done": false })
	elif mode == 2:
		plan.append({ "time": _rng.randf_range(0.0, 2.0), "kind": "start", "reel": -1, "done": false })
	elif mode == 3:
		for reel: int in reels:
			if _rng.randf() < 0.6:
				var kind: String = "key" if _rng.randf() < 0.5 else "button"
				plan.append({ "time": _rng.randf_range(0.0, 3.5), "kind": kind, "reel": reel, "done": false })
		if _rng.randf() < 0.5:
			plan.append({ "time": _rng.randf_range(0.0, 3.5), "kind": "start", "reel": -1, "done": false })
	return plan


func _do_input(main: Control, entry: Dictionary) -> void:
	entry["done"] = true
	var reel: int = entry["reel"]
	if entry["kind"] == "key":
		_press(main, (KEY_1 + reel) as Key)
	elif entry["kind"] == "button":
		(main.get_node("StopButton%d" % (reel + 1)) as Button).pressed.emit()
	elif entry["kind"] == "start":
		_press(main, KEY_SPACE)


## 이미 START된 스핀 하나를 끝까지 굴린다. 매 프레임 검사:
## 보이는 심볼이 실제 스트립과 같은가, 정산 전에 숫자가 먼저 바뀌지 않았는가, 회전 중 잠금이 지켜지는가.
func _run_spin(main: Control, mode: int, stops: PackedInt32Array) -> void:
	var credit_text: String = _box(main, "CreditBox").value_text()
	var pool_text: String = _box(main, "PoolBox").value_text()
	var fever_text: String = _fever(main).value_text()
	var plan: Array[Dictionary] = _make_plan(mode)
	var rects: Array[Rect2] = _window_rects(main)
	var feel: FeelConfig = main.feel()
	var spin: SpinController = main.spin_controller()
	var time: float = 0.0
	var lock_checked: bool = false
	while GameState.spinning and time < MAX_SPIN_SEC:
		for entry: Dictionary in plan:
			if not entry["done"] and time >= float(entry["time"]):
				_do_input(main, entry)
		var dt: float = _frame_dt()
		main.advance(dt)
		time += dt
		for i: int in 3:
			if not main.reel_view(i).is_consistent():
				_strip_errors += 1
			if not main.reel_view(i).windows_are_sound():
				_window_errors += 1
			# 출발 시각 = START 기준 지연 시각 (테스트 시계와 컨트롤러 시계는 같은 덧셈이라 정확히 일치)
			if spin.has_started(i) != (time >= feel.reel_start_delay[i]):
				_delay_errors += 1
			if not spin.has_started(i) and spin.can_stop(i):
				_delay_errors += 1
		if _window_rects(main) != rects:
			_window_moves += 1
		if GameState.spinning:
			if _box(main, "CreditBox").value_text() != credit_text or _box(main, "WinBox").value_text() != "0" \
					or _box(main, "PoolBox").value_text() != pool_text:
				_early_reveal += 1
			# 피버 카운터는 피버 연출 중에만 (발동한 심볼 0 → 초기값) 먼저 바뀐다. 그 밖에는 정산 전에 불변.
			if not main.fever_playing() and _fever(main).value_text() != fever_text:
				_early_reveal += 1
			if main.fever_playing():
				_fever_frames += 1
			if not lock_checked and time >= LOCK_CHECK_SEC:
				lock_checked = true
				_check_lock(main)
	if GameState.spinning:
		_stuck_spins += 1
		return
	for i: int in 3:
		var motion: ReelMotion = main.reel_view(i).motion
		if motion.position != float(stops[i]) or motion.is_spinning():
			_final_errors += 1


## 칸 창 9개의 화면 좌표 사각형 (회전 중 창이 움직이지 않는지 비교용)
func _window_rects(main: Control) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for i: int in 3:
		for row: int in 3:
			rects.append(main.reel_view(i).window_at(row).get_global_rect())
	return rects


## 회전 중 COIN·BET·MAX BET·CANCEL이 아무것도 바꾸지 못하고 버튼이 잠겨 있는지
func _check_lock(main: Control) -> void:
	var credit: int = GameState.credit
	var bet: int = GameState.bet
	var lines: PackedInt32Array = GameState.line_bets.duplicate()
	_press(main, KEY_C)
	_press(main, KEY_B)
	_press(main, KEY_M)
	_press(main, KEY_X)
	if GameState.credit != credit or GameState.bet != bet or GameState.line_bets != lines:
		_lock_errors += 1
	for node_name: String in ["BetButton", "MaxBetButton", "CancelButton"]:
		if not (main.get_node(node_name) as Button).disabled:
			_lock_errors += 1


# ---------------------------------------------------------------- STOP 흐름 (장면 하나씩)

## 정산 전 상태, STOP 버튼 활성/비활성, 회전 중 START 동작, 정산 후 복귀
func _test_stop_flow(main: Control) -> void:
	GameState.credit = 100
	while GameState.bet != FULL_BET:
		GameState.raise_bet()
	GameState.refresh()
	var credit_before: int = GameState.credit
	var result: SpinResult = main.do_spin()
	_check(result != null and GameState.spinning, "START: 결과 확정, 회전 시작")
	_check(GameState.credit == credit_before - FULL_BET, "START 직후 크레딧은 베팅만큼만 차감")
	var spin: SpinController = main.spin_controller()
	_check(spin.has_started(0) and not spin.has_started(2), "START 직후: 지연 0인 릴1만 출발, 릴3은 출발 대기")
	_check(not (main.get_node("StopButton1") as Button).disabled and (main.get_node("StopButton3") as Button).disabled, "출발 전 릴의 STOP 버튼은 비활성, 출발한 릴은 활성")
	_check(not main.press_stop(2), "출발 전 릴3의 STOP은 받지 않음")
	main.advance(main.feel().reel_start_delay[2] + FRAME_DT)
	var stop_enabled: bool = true
	for i: int in 3:
		stop_enabled = stop_enabled and not (main.get_node("StopButton%d" % (i + 1)) as Button).disabled
	_check(stop_enabled, "모든 릴이 출발한 뒤 STOP 1·2·3 활성")
	_check(not (main.get_node("StartButton") as Button).disabled, "회전 중 START(남은 릴 정지) 활성")
	_check(_box(main, "NoticeBox").value_text().contains("STOP"), "회전 중 안내 문구에 STOP 안내")
	_check(main.do_spin() == null and GameState.spinning, "회전 중 START는 새 스핀을 시작하지 않음")
	for step: int in 40:
		main.advance(FRAME_DT)
	_check(main.press_stop(1), "릴2 STOP 수락")
	_check(not main.press_stop(1), "같은 릴 STOP을 또 눌러도 무시")
	_check((main.get_node("StopButton2") as Button).disabled, "누른 릴의 STOP 버튼은 비활성")
	_check(not (main.get_node("StopButton1") as Button).disabled, "안 누른 릴의 STOP 버튼은 활성")
	_press(main, KEY_SPACE)
	_settle(main)
	_check(not GameState.spinning, "회전 중 START 후 정산까지 끝남")
	_check(main.grid_matches_logic(), "회전 중 START 후 화면 == 로직")
	var all_stop_disabled: bool = true
	for i: int in 3:
		all_stop_disabled = all_stop_disabled and (main.get_node("StopButton%d" % (i + 1)) as Button).disabled
	_check(all_stop_disabled, "정산 후 STOP 버튼 모두 비활성")
	_check(_box(main, "WinBox").value_text() == str(result.total_payout()), "정산 후 WIN 표시")
	var settled_windows: bool = true
	for i: int in 3:
		settled_windows = settled_windows and main.reel_view(i).windows_are_sound() and main.reel_view(i).is_consistent()
	_check(settled_windows, "정지 후 칸 창이 심볼 하나로 꽉 차 있고 스트립 순서와 같음")
	_check(not (main.get_node("BetButton") as Button).disabled or GameState.credit < 1, "정산 후 BET 버튼 복귀")


# ---------------------------------------------------------------- feel.json 실행 중 재로딩

const FEEL_TEMP_PATH: String = "user://feel_test.json"
const RELOAD_SEED: int = 777
const RELOAD_SPINS: int = 3
const RELOAD_STOP_AT_SEC: float = 0.5


## 손맛 설정 사전을 파일로 쓴다 (기본값에 overrides를 덮어씀)
func _write_feel_file(path: String, overrides: Dictionary, raw_text: String = "") -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if raw_text.is_empty():
		var values: Dictionary = {}
		for key: String in FeelConfig.SPECS:
			values[key] = FeelConfig.SPECS[key][0]
		for key: String in FeelConfig.ARRAY_SPECS:
			values[key] = FeelConfig.ARRAY_SPECS[key][0]
		values.merge(overrides, true)
		file.store_string(JSON.stringify(values))
	else:
		file.store_string(raw_text)
	file.close()


## 정해진 입력(릴1 STOP을 0.5초에 누름, 나머지는 자동)으로 스핀 한 번을 돌리고
## { stops: 릴별 정지 위치, times: 릴별 멈춘 시각, feel: 이 스핀이 쓴 설정 } 을 돌려준다.
## on_frame(시간)은 매 프레임 불리며 테스트가 중간에 개입할 때 쓴다.
func _scripted_spin(main: Control, on_frame: Callable) -> Dictionary:
	for i: int in 3:
		main.reel_view(i).motion.position = 0.0
		main.reel_view(i).refresh()
	var result: SpinResult = main.do_spin()
	var times: Array[float] = [-1.0, -1.0, -1.0]
	var time: float = 0.0
	var pressed: bool = false
	var guard: int = 0
	while GameState.spinning and guard < 6000:
		if not pressed and time >= RELOAD_STOP_AT_SEC:
			pressed = true
			main.press_stop(0)
		on_frame.call(time)
		main.advance(FRAME_DT)
		time += FRAME_DT
		guard += 1
		for i: int in 3:
			if times[i] < 0.0 and main.spin_controller().has_started(i) and not main.reel_view(i).motion.is_spinning():
				times[i] = time
	return { "stops": result.stops, "times": times, "feel": main.feel() }


func _prepare_reload_run(main: Control) -> void:
	GameState.initialize(GameState.get_balance(), GameState.load_economy(), RELOAD_SEED)
	GameState.credit = 5000
	while GameState.bet != FULL_BET:
		GameState.raise_bet()
	GameState.refresh()


func _test_feel_reload(main: Control) -> void:
	# --- 1) 파일 읽기: 정상 / 깨진 파일 / 범위 밖 값 / 감시
	_write_feel_file(FEEL_TEMP_PATH, { "spin_speed": 40.0, "auto_stop_start": 1.0 })
	main.set_feel_path(FEEL_TEMP_PATH)
	var before: FeelConfig = main.pending_feel()
	_check(not main.poll_feel_file(), "파일이 그대로면 감시가 다시 읽지 않음")
	_check(main.reload_feel() and main.pending_feel().spin_speed == 40.0 and main.pending_feel() != before, "reload_feel: 새 값을 대기 설정으로 보관")
	_check(main.feel() != main.pending_feel(), "다시 읽어도 지금 스핀 설정은 그대로 (다음 START부터 적용)")
	var good: FeelConfig = main.pending_feel()
	_write_feel_file(FEEL_TEMP_PATH, {}, "{ \"spin_speed\": 3")
	_check(not main.reload_feel() and main.pending_feel() == good, "깨진 파일이면 이전 설정 유지")
	_write_feel_file(FEEL_TEMP_PATH, { "spin_speed": 9999.0 })
	_check(main.reload_feel() and main.pending_feel().spin_speed == FeelConfig.SPECS["spin_speed"][0] and not main.pending_feel().errors.is_empty(), "범위 밖 항목은 기본값으로 대체하고 문제로 기록")
	_check(_box(main, "NoticeBox").value_text().contains("다음 스핀부터"), "다시 읽으면 안내 문구로 알림")
	main.set("_feel_mtime", -1)
	_check(main.poll_feel_file(), "수정 시각이 바뀌면 감시가 다시 읽음")
	var key_before: FeelConfig = main.pending_feel()
	_press(main, KEY_F6)
	_check(main.pending_feel() != key_before, "F6 = 즉시 다시 읽기")

	# --- 2) 진행 중 스핀 불변: 같은 시드로 두 번 돌려 비교
	_write_feel_file(FEEL_TEMP_PATH, {})
	main.reload_feel()
	_prepare_reload_run(main)
	var control_feel: FeelConfig = main.pending_feel()
	var control: Array[Dictionary] = []
	for n: int in RELOAD_SPINS:
		control.append(_scripted_spin(main, func(_t: float) -> void: pass))
	# 두 번째 실행: 첫 스핀 0.3초에 설정을 크게 바꿔 다시 읽는다 (회전 속도·자동 정지·튕김 모두 변경)
	_prepare_reload_run(main)
	var changed: Dictionary = { "spin_speed": 60.0, "auto_stop_start": 1.0, "auto_stop_interval": 0.1, "slide_cells": 1.0, "bounce_cells": 0.0, "accel_time": 0.0 }
	var tested: Array[Dictionary] = []
	for n: int in RELOAD_SPINS:
		var hook: Callable = func(_t: float) -> void: pass
		if n == 0:
			var state: Array[bool] = [false]
			hook = func(t: float) -> void:
				if not state[0] and t >= 0.3:
					state[0] = true
					_write_feel_file(FEEL_TEMP_PATH, changed)
					main.reload_feel()
		tested.append(_scripted_spin(main, hook))
	var results_same: bool = true
	for n: int in RELOAD_SPINS:
		results_same = results_same and control[n]["stops"] == tested[n]["stops"]
	_check(results_same, "설정을 중간에 바꿔도 스핀 결과(정지 위치) 순서가 그대로")
	_check(tested[0]["feel"] == control_feel and tested[0]["feel"].spin_speed != 60.0, "진행 중이던 첫 스핀은 옛 설정으로 끝까지 진행")
	_check(tested[0]["times"] == control[0]["times"], "진행 중이던 첫 스핀의 릴별 정지 시각이 설정을 안 바꾼 경우와 완전히 같음")
	_check(tested[1]["feel"].spin_speed == 60.0, "다음 스핀부터 새 설정 적용")
	_check(tested[1]["times"] != control[1]["times"], "다음 스핀의 연출 타이밍은 새 설정대로 달라짐")
	var auto_ok: bool = true
	# 릴1은 스크립트가 0.5초에 손으로 멈추므로 자동 정지인 릴2·3만 본다
	for i: int in [1, 2]:
		auto_ok = auto_ok and tested[2]["times"][i] >= 1.0 + i * 0.1 and tested[2]["times"][i] < control[2]["times"][i]
	_check(auto_ok, "새 설정(자동 정지 1.0초 + 0.1초 간격, 더 빠른 속도)이 다음 스핀에 반영됨")

	# --- 정리: 원래 파일을 다시 감시하고 설정을 되돌림
	main.set_feel_path(FeelConfig.DEFAULT_PATH)
	main.reload_feel()
	_prepare_reload_run(main)
	_scripted_spin(main, func(_t: float) -> void: pass)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FEEL_TEMP_PATH))


# ---------------------------------------------------------------- 피버 발동 연출 (5-B)

const FEVER_SEED: int = 4242
const FEVER_SEARCH_MAX: int = 6000
const POOL_SEARCH_MAX: int = 60000
const FEVER_START_CREDIT: int = 100000


## 피버 대상 초기값을 모두 1로 낮춘 밸런스 (테스트 전용. 파일은 건드리지 않음). 첫 당첨 심볼이 바로 피버가 된다.
func _fever_test_data() -> BalanceData:
	var json: JSON = JSON.new()
	json.parse(FileAccess.get_file_as_string("res://data/balance.json"))
	var raw: Dictionary = json.data
	for target: Variant in raw["fever"]["targets"]:
		(target as Dictionary)["initial_count"] = 1
	return BalanceData.from_dict(raw)


## 같은 시드로 n번째(0부터) 스핀이 피버 min_triggers개 이상인 n을 찾는다. 없으면 -1.
func _find_fever_spin(data: BalanceData, min_triggers: int) -> int:
	var probe: SlotLogic = SlotLogic.new(data, FEVER_SEED)
	for n: int in FEVER_SEARCH_MAX:
		var result: SpinResult = probe.spin(FULL_BET)
		if result.fever_triggers.size() >= min_triggers:
			return n
	return -1


## 같은 시드로 풀을 획득하는(세븐 피버 + 풀) 스핀 번호를 찾는다. 없으면 -1.
func _find_pool_spin(data: BalanceData) -> int:
	var probe: SlotLogic = SlotLogic.new(data, FEVER_SEED)
	for n: int in POOL_SEARCH_MAX:
		if probe.spin(FULL_BET).pool_won > 0:
			return n
	return -1


## 시드·n으로 상태를 맞추고 n번째 스핀 직전의 화면(main)을 돌려준다.
func _fever_world(data: BalanceData, n: int) -> Control:
	GameState.initialize(data, GameState.load_economy(), FEVER_SEED)
	GameState.credit = FEVER_START_CREDIT
	while GameState.bet != FULL_BET:
		GameState.raise_bet()
	for i: int in n:
		GameState.play_spin()
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settle_presentation = false
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	GameState.refresh()
	return main


## START 후 피버 연출이 시작될 때까지 시간을 흘린다. 시작했으면 true.
func _advance_to_fever(main: Control) -> bool:
	var guard: int = 0
	while GameState.spinning and not main.fever_playing() and guard < 6000:
		main.advance(FRAME_DT)
		guard += 1
	return main.fever_playing()


func _fever_rows(main: Control) -> PackedStringArray:
	return _fever(main).value_text().split("\n")


func _test_fever_show() -> void:
	var data: BalanceData = _fever_test_data()
	var multi_n: int = _find_fever_spin(data, 2)
	_check(multi_n >= 0, "시험용 데이터에서 피버가 한 스핀에 둘 이상 나오는 스핀을 찾음 (n=%d)" % multi_n)
	if multi_n < 0:
		return
	var snapshot: Dictionary = await _fever_natural_run(data, multi_n)
	await _fever_skip_run(data, multi_n, snapshot)
	var single_n: int = _find_fever_spin(data, 1)
	var single: Dictionary = await _fever_natural_run(data, single_n)
	_check(single["steps"] == 1, "피버 1개인 스핀은 단계 1개")
	# 세븐 피버 + 풀 획득: 마지막에 POOL GET 단계가 붙는다
	var pool_n: int = _find_pool_spin(data)
	_check(pool_n >= 0, "시험용 데이터에서 풀을 획득하는 스핀을 찾음 (n=%d)" % pool_n)
	if pool_n >= 0:
		var pool_run: Dictionary = await _fever_natural_run(data, pool_n)
		_check(pool_run["steps"] >= 2, "풀 획득 스핀은 세븐 피버 단계 + POOL 단계 (단계 %d개)" % pool_run["steps"])
		await _fever_skip_run(data, pool_n, pool_run)
	# 시험이 끝나면 원래 밸런스로 되돌린다.
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)


## 끝까지 자연 재생: 순서·글자·카운터·잠금·시간·정산 시점을 매 프레임 확인하고 최종 화면 숫자를 돌려준다.
func _fever_natural_run(data: BalanceData, n: int) -> Dictionary:
	var main: Control = await _fever_world(data, n)
	var overlay: FeverOverlay = main.get_node("FeverOverlay")
	var credit_start: int = GameState.credit
	var result: SpinResult = main.do_spin()
	var expected: Array[String] = []
	for symbol: String in data.fever_symbols:
		if result.fever_triggers.has(symbol):
			expected.append(symbol)
	var pool_step: bool = result.pool_won > 0
	var step_total: int = expected.size() + (1 if pool_step else 0)
	# 풀 단계가 끝나는 순간(정산 직전)의 POOL·CREDIT·WIN 글자를 기록한다 (main의 처리가 먼저 실행된 뒤 불린다)
	var pool_probe: Dictionary = { "pool": "", "credit": "", "win": "" }
	var pool_before: String = _box(main, "PoolBox").value_text()
	overlay.step_finished.connect(func(index: int) -> void:
		if overlay.step_at(index)["kind"] == FeverOverlay.KIND_POOL:
			pool_probe["pool"] = _box(main, "PoolBox").value_text()
			pool_probe["credit"] = _box(main, "CreditBox").value_text()
			pool_probe["win"] = _box(main, "WinBox").value_text())
	_check(_advance_to_fever(main), "피버가 나온 스핀: 릴이 멈추면 오버레이 재생 (단계 %d개)" % step_total)
	_check(overlay.step_count() == step_total and step_total >= 1, "단계 수 = 발동한 피버 수")
	_check(GameState.spinning and GameState.credit == credit_start - FULL_BET, "오버레이 중: 정산 전이라 크레딧은 베팅만 차감된 상태")
	_check(_box(main, "WinBox").value_text() == "0", "오버레이 중: WIN은 아직 0")
	_check(_box(main, "NoticeBox").value_text().contains("건너뛸 수"), "오버레이 중 안내 문구: 건너뛰기 안내")
	_check(not _box(main, "NoticeBox").value_text().contains("라인 "), "오버레이 중: '라인 X + 피버 Y + 풀 Z' 내역은 아직 안 보임")
	_check(not (main.get_node("StartButton") as Button).disabled, "오버레이 중 START(건너뛰기) 켜짐")
	var rows: PackedStringArray = _fever_rows(main)
	var zero_ok: bool = true
	for i: int in data.fever_symbols.size():
		var symbol: String = data.fever_symbols[i]
		var want: int = 0 if expected.has(symbol) else result.fever_counts_after[symbol]
		zero_ok = zero_ok and rows[i] == "%s ×%d" % [data.symbol_names[symbol], want]
	_check(zero_ok, "오버레이 시작: 발동한 심볼의 카운터는 0, 나머지는 스핀 후 값")
	var feel: FeelConfig = main.feel()
	var total: float = FeverOverlay.total_seconds(FeverOverlay.build_steps(result, data), feel.fever_overlay_sec, feel.fever_step_gap, feel.pool_overlay_sec)
	var frames: int = 0
	var text_errors: int = 0
	var counter_errors: int = 0
	var order_seen: Array[int] = []
	var lock_errors: int = 0
	var gap_seen: bool = step_total < 2
	var early_skip_ignored: bool = false
	var reloaded: bool = false
	main.set_feel_path(FEEL_TEMP_PATH)
	while main.fever_playing() and frames < 6000:
		var step: int = overlay.current_step()
		if step >= 0:
			if order_seen.is_empty() or order_seen[order_seen.size() - 1] != step:
				order_seen.append(step)
			var texts: Dictionary = overlay.shown_texts()
			if step >= expected.size():
				# 6-E: 풀 단계는 이름 줄이 없다(배너·금액 판과 중복) → 보이는 이름 글자는 빈 글자
				if texts["title"] != "POOL GET!" or texts["name"] != "" or texts["bonus"] != "POOL +%d" % result.pool_won:
					text_errors += 1
			else:
				var step_symbol: String = expected[step]
				if texts["title"] != "FEVER!" or texts["name"] != data.symbol_names[step_symbol] or texts["bonus"] != "BONUS +%d" % result.fever_bonuses[step_symbol]:
					text_errors += 1
		else:
			gap_seen = true
		# 카운터: 끝난 단계의 심볼은 초기값, 아직인 단계는 0
		var shown: PackedStringArray = _fever_rows(main)
		for i: int in data.fever_symbols.size():
			var sym: String = data.fever_symbols[i]
			var idx: int = expected.find(sym)
			var done: bool = idx >= 0 and overlay.elapsed() >= idx * (feel.fever_overlay_sec + feel.fever_step_gap) + feel.fever_overlay_sec
			var want_count: int = result.fever_counts_after[sym] if (idx < 0 or done) else 0
			if shown[i] != "%s ×%d" % [data.symbol_names[sym], want_count]:
				counter_errors += 1
		if frames == 5:
			lock_errors += _fever_lock_errors(main, credit_start - FULL_BET)
			# 건너뛰기 잠금 시간 안의 스페이스는 무시
			_press(main, KEY_SPACE)
			early_skip_ignored = main.fever_playing()
		if frames == 10 and not reloaded:
			reloaded = true
			_write_feel_file(FEEL_TEMP_PATH, { "fever_overlay_sec": 9.0, "fever_step_gap": 3.0 })
			main.reload_feel()
		main.advance(FRAME_DT)
		frames += 1
	var played: float = frames * FRAME_DT
	var want_order: Array[int] = []
	for i: int in step_total:
		want_order.append(i)
	_check(order_seen == want_order, "단계가 체리·포도·벨·세븐(피버 대상 순서) → 풀 획득 순으로 차례로 나옴: %s" % [order_seen])
	_check(text_errors == 0, "단계마다 'FEVER!' / 심볼 이름 / 'BONUS +금액'이 결과와 같음 (어긋난 프레임 %d)" % text_errors)
	_check(counter_errors == 0, "카운터: 단계가 끝날 때마다 해당 심볼만 0에서 초기값으로 (어긋난 프레임 %d)" % counter_errors)
	_check(lock_errors == 0, "오버레이 중 COIN·BET·MAX BET·CANCEL·STOP 잠금 (어긋난 횟수 %d)" % lock_errors)
	_check(gap_seen, "단계 사이 빈 간격이 있음")
	_check(early_skip_ignored, "오버레이가 뜬 직후 스페이스는 무시 (건너뛰기 잠금)")
	_check(absf(played - total) <= FRAME_DT + 0.001, "재생 시간 = 단계 수×시간 + 간격 (%.3f초, 기대 %.3f초) — 도중에 feel.json을 바꿔도 불변" % [played, total])
	_check(main.pending_feel().fever_overlay_sec == 9.0, "도중에 다시 읽은 새 설정은 다음 스핀용으로 보관됨")
	_check(not GameState.spinning and not overlay.visible, "연출이 끝나면 정산되고 오버레이가 사라짐")
	var snapshot: Dictionary = _fever_snapshot(main)
	if pool_step:
		_check(result.pool_won >= int(pool_before), "획득 금액(%d)은 획득 전 POOL 표시(%s) 이상 (그 사이 적립분 포함)" % [result.pool_won, pool_before])
		_check(pool_probe["pool"] == str(result.pool_after) and result.pool_after == data.pool_initial, "POOL GET 단계가 끝나면 POOL이 초기값(%d)으로 돌아감" % data.pool_initial)
		_check(pool_probe["credit"] == str(credit_start - FULL_BET) and pool_probe["win"] == "0", "POOL GET 단계가 끝난 순간에도 CREDIT·WIN은 아직 안 바뀜 (정산은 연출이 모두 끝난 뒤 한 번에)")
		_check(result.pool_won >= data.pool_initial and snapshot["notice"].contains("풀 %d" % result.pool_won), "안내 문구의 풀 금액 = 연출에서 보여 준 풀 금액 (%d)" % result.pool_won)
	_check(GameState.credit == credit_start - FULL_BET + result.total_payout(), "정산: 크레딧 = 시작 - 베팅 + 총 지급")
	_check(snapshot["win"] == str(result.total_payout()), "정산: WIN = 총 지급 (한 번에 갱신)")
	_check(snapshot["notice"].contains("당첨 %d = 라인 %d + 피버 %d + 풀 %d" % [result.total_payout(), result.line_payout, result.fever_bonus, result.pool_won]), "연출이 끝난 뒤 안내 문구에 '라인 X + 피버 Y + 풀 Z' 내역")
	var final_ok: bool = true
	for i: int in data.fever_symbols.size():
		var sym2: String = data.fever_symbols[i]
		final_ok = final_ok and _fever_rows(main)[i] == "%s ×%d" % [data.symbol_names[sym2], result.fever_counts_after[sym2]]
	_check(final_ok and result.fever_counts_after[expected[0]] == data.fever_initial_counts[expected[0]], "끝난 뒤 카운터 = 초기값으로 리셋된 스핀 후 값")
	_check(snapshot["pool"] == str(result.pool_after), "정산: POOL = 스핀 후 값")
	main.set_feel_path(FeelConfig.DEFAULT_PATH)
	snapshot["steps"] = step_total
	main.free()
	await get_tree().process_frame
	return snapshot


## 같은 시드·같은 스핀을 다시 돌리되 연출을 스페이스로 건너뛴다. 최종 숫자가 자연 재생과 완전히 같아야 한다.
func _fever_skip_run(data: BalanceData, n: int, natural: Dictionary) -> void:
	var main: Control = await _fever_world(data, n)
	var overlay: FeverOverlay = main.get_node("FeverOverlay")
	main.do_spin()
	_advance_to_fever(main)
	main.advance(0.1)
	_press(main, KEY_SPACE)
	_check(main.fever_playing(), "건너뛰기 잠금 시간 안의 스페이스는 무시")
	_check(main.do_spin() == null and main.fever_playing(), "잠금 시간 안의 START도 무시")
	main.advance(0.5)
	_check(main.fever_playing(), "건너뛰기 전까지 연출 계속")
	_press(main, KEY_SPACE)
	_check(not main.fever_playing() and not GameState.spinning and not overlay.visible, "잠금이 풀린 뒤 스페이스: 연출 즉시 종료 + 정산")
	var snapshot: Dictionary = _fever_snapshot(main)
	var same: bool = true
	for key: String in ["credit", "win", "bet", "pool", "fever", "notice"]:
		if snapshot[key] != natural[key]:
			same = false
			print("  달라진 항목 ", key, ": ", snapshot[key], " / ", natural[key])
	_check(same, "건너뛰어도 CREDIT·WIN·BET·POOL·피버 카운터·안내 문구가 자연 재생과 완전히 같음")
	main.free()
	await get_tree().process_frame


func _fever_snapshot(main: Control) -> Dictionary:
	return {
		"credit": _box(main, "CreditBox").value_text(),
		"win": _box(main, "WinBox").value_text(),
		"bet": _box(main, "BetBox").value_text(),
		"pool": _box(main, "PoolBox").value_text(),
		"fever": _fever(main).value_text(),
		"notice": _box(main, "NoticeBox").value_text(),
	}


## 오버레이 중 COIN·BET·MAX BET·CANCEL·STOP이 아무 것도 바꾸지 못하는지 (어긋난 개수)
func _fever_lock_errors(main: Control, expected_credit: int) -> int:
	var errors: int = 0
	var bet: int = GameState.bet
	_press(main, KEY_C)
	_press(main, KEY_B)
	_press(main, KEY_M)
	_press(main, KEY_X)
	if GameState.credit != expected_credit or GameState.bet != bet:
		errors += 1
	for i: int in 3:
		if main.press_stop(i):
			errors += 1
		if not (main.get_node("StopButton%d" % (i + 1)) as Button).disabled:
			errors += 1
	for node_name: String in ["BetButton", "MaxBetButton", "CancelButton"]:
		if not (main.get_node(node_name) as Button).disabled:
			errors += 1
	return errors


# ---------------------------------------------------------------- AUTO (화면)

const AUTO_GAP_SEC: float = 0.5


## AUTO 시험용으로 오토로드를 새로 시작하고 main 씬을 띄운다. credit/bet은 호출한 쪽이 정한다.
func _auto_main(rng_seed: int, credit: int, total_bet: int) -> Control:
	GameState.initialize(GameState.get_balance(), GameState.load_economy(), rng_seed)
	GameState.credit = credit
	while GameState.bet != total_bet:
		GameState.raise_bet()
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settle_presentation = false
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	GameState.refresh()
	return main


func _notice(main: Control) -> String:
	return _box(main, "NoticeBox").value_text()


func _advance_for(main: Control, seconds: float) -> void:
	var time: float = 0.0
	while time < seconds:
		main.advance(FRAME_DT)
		time += FRAME_DT


## 첫 판 당첨금이 0인지/아닌지가 want_win인 시드를 찾는다 (오토로드로 한 판 돌려 본다)
func _auto_find_seed(credit: int, total_bet: int, want_win: bool) -> int:
	for candidate: int in range(1, 400):
		GameState.initialize(GameState.get_balance(), GameState.load_economy(), candidate)
		GameState.credit = credit
		while GameState.bet != total_bet:
			GameState.raise_bet()
		if (GameState.play_spin().total_payout() > 0) == want_win:
			return candidate
	return -1


func _test_auto_view() -> void:
	await _test_auto_button_and_flow()
	await _test_auto_stop_paths()
	await _test_auto_notice_and_stops()
	await _test_auto_with_fever()
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)


func _test_auto_button_and_flow() -> void:
	var main: Control = await _auto_main(21, 0, 0)
	var button: Button = main.get_node("AutoButton")
	_check(button.position == Vector2(384, 318) and button.size == Vector2(60, 33) and button.text == "AUTO", "AUTO 버튼: (384,318) 60×33, 글자 AUTO")
	var stop3: Button = main.get_node("StopButton3")
	_check(button.position.x >= stop3.position.x + stop3.size.x and button.position.x + button.size.x <= main.PAYTABLE_RECT.position.x, "AUTO 버튼이 STOP 3과 오른쪽 패널 사이에 있음")
	_check(button.disabled, "베팅이 없으면 AUTO 버튼 비활성")
	_check(button.get_theme_stylebox("normal").texture.resource_path.ends_with("button_normal.png"), "AUTO 꺼짐: 기본 버튼 그림")
	GameState.insert_coin()
	GameState.insert_coin()
	GameState.raise_bet()
	main._refresh_buttons()
	_check(not button.disabled, "베팅이 있으면 AUTO 버튼 활성")
	_press(main, KEY_A)
	_check(GameState.auto_on and GameState.spinning, "A 키: AUTO 켜짐, 첫 판 시작")
	_check(button.get_theme_stylebox("normal").texture.resource_path.ends_with("button_on.png") and button.get_theme_stylebox("hover").texture.resource_path.ends_with("button_on.png"), "AUTO 켜짐: ON 그림(밝은 금색 면)")
	_check(button.get_theme_color("font_color") == UiSkin.BUTTON_ON_TEXT_COLOR, "AUTO 켜짐: 어두운 글자색")
	_check(_notice(main).split("\n")[0] == "AUTO 1회", "메시지 첫 줄 'AUTO 1회'")
	_check(GameState.auto_gap_sec == main.feel().auto_spin_gap_sec, "스핀 시작 때 feel.json의 auto_spin_gap_sec를 로직에 넘김")
	var locked: bool = (main.get_node("BetButton") as Button).disabled and (main.get_node("MaxBetButton") as Button).disabled and (main.get_node("CancelButton") as Button).disabled
	_check(locked, "AUTO 중 BET / MAX BET / CANCEL 버튼 비활성")
	_advance_for(main, 0.6)
	var stops_locked: bool = true
	for i: int in 3:
		stops_locked = stops_locked and (main.get_node("StopButton%d" % (i + 1)) as Button).disabled and not main.press_stop(i)
	_check(stops_locked, "AUTO 중 STOP 1~3 비활성·입력 무시 (회전 중에도)")
	var bet_before: int = GameState.bet
	_press(main, KEY_B)
	_press(main, KEY_M)
	_press(main, KEY_X)
	_check(GameState.bet == bet_before, "AUTO 중 B / M / X 키 무시")
	_settle(main)
	_check(not GameState.spinning and GameState.auto_on, "한 판이 정산되고 AUTO는 유지")
	_check(_notice(main).split("\n")[0] == "AUTO 1회", "정산 뒤 대기 중에도 'AUTO 1회' 첫 줄")
	_advance_for(main, AUTO_GAP_SEC - 0.1)
	_check(not GameState.spinning, "대기시간 전에는 다음 판이 시작되지 않음")
	_advance_for(main, 0.2)
	_check(GameState.spinning and GameState.auto_count() == 2 and _notice(main).split("\n")[0] == "AUTO 2회", "대기시간 뒤 다음 판 자동 시작 ('AUTO 2회')")
	_check(GameState.bet == bet_before, "AUTO 중 BET 값 유지")
	main.free()
	await get_tree().process_frame


func _test_auto_stop_paths() -> void:
	# 버튼으로 끄기: 회전 중에 끄면 진행 중인 판까지만 돌고 멈춘다
	var main: Control = await _auto_main(22, 400, FULL_BET)
	var button: Button = main.get_node("AutoButton")
	button.pressed.emit()
	_advance_for(main, 0.5)
	button.pressed.emit()
	_check(not GameState.auto_on and GameState.spinning, "AUTO 버튼 재클릭: 꺼지지만 진행 중인 판은 계속")
	_check(button.get_theme_stylebox("normal").texture.resource_path.ends_with("button_normal.png") and _notice(main).contains("AUTO를 해제"), "꺼짐 표시로 돌아가고 해제 문구가 나옴")
	_settle(main)
	_advance_for(main, 2.0)
	_check(not GameState.spinning and GameState.auto_count() == 1, "끈 뒤 진행 중이던 판은 정산되고 새 판은 시작되지 않음")
	_check(not (main.get_node("BetButton") as Button).disabled, "AUTO를 끄면 BET 버튼이 다시 활성")
	# START로 끄기: 대기시간 중의 START는 AUTO 끄기 (새 판을 시작하지 않는다)
	GameState.start_auto()
	_settle(main)
	var started_before: int = GameState.auto_count()
	_check(GameState.auto_on and not GameState.spinning, "(준비) AUTO 대기 상태")
	var result: SpinResult = main.do_spin()
	_check(result == null and not GameState.auto_on and not GameState.spinning, "대기 중 START: AUTO만 꺼지고 새 판은 시작하지 않음")
	_advance_for(main, 2.0)
	_check(not GameState.spinning and GameState.auto_count() == started_before, "START로 끈 뒤 새 판이 시작되지 않음")
	_check(_notice(main).contains("AUTO를 해제"), "START로 끄면 해제 문구")
	# 회전 중 START는 기존대로 남은 릴을 멈추고 AUTO는 유지
	GameState.start_auto()
	_advance_for(main, 0.5)
	main.do_spin()
	_check(GameState.auto_on, "회전 중 START(남은 릴 정지)는 AUTO를 끄지 않음")
	_settle(main)
	_check(not GameState.spinning, "(정리) 회전 중 START 뒤에도 정상 정산")
	main.free()
	await get_tree().process_frame


func _test_auto_notice_and_stops() -> void:
	# 피버 적립 안내(BET 8 미만)는 AUTO 중에는 생략, AUTO가 아니면 표시
	var main: Control = await _auto_main(23, 400, 3)
	_check(_notice(main).contains("피버 적립"), "(기준) AUTO 꺼짐 + BET 3: 피버 적립 안내 표시")
	GameState.start_auto()
	_check(not _notice(main).contains("피버 적립") and _notice(main).begins_with("AUTO 1회"), "AUTO 중에는 피버 적립 안내 줄을 생략")
	_settle(main)
	GameState.stop_auto(AutoSpin.REASON_USER)
	main.free()
	await get_tree().process_frame
	# 크레딧 부족: 해제 이유 + 기존 베팅 낮춤 문구
	var lose_seed: int = _auto_find_seed(64, 64, false)
	main = await _auto_main(lose_seed, 64, 64)
	GameState.start_auto()
	_settle(main)
	_check(not GameState.auto_on and _notice(main).contains("크레딧이 부족해 AUTO를 해제"), "크레딧 부족: AUTO 자동 해제 + 이유 문구")
	_check(_notice(main).contains("BET을"), "크레딧 부족: 기존 베팅 낮춤 문구도 함께 나옴")
	main.free()
	await get_tree().process_frame
	# 큰 당첨: stop_on_win_at 이상이면 해제
	var win_seed: int = _auto_find_seed(400, FULL_BET, true)
	var data: BalanceData = GameState.get_balance()
	var original: int = data.auto_stop_on_win_at
	data.auto_stop_on_win_at = 1
	main = await _auto_main(win_seed, 400, FULL_BET)
	GameState.start_auto()
	_settle(main)
	_check(not GameState.auto_on and _notice(main).contains("큰 당첨! AUTO를 해제"), "큰 당첨: AUTO 해제 + 이유 문구 (결과 문구 뒤)")
	_check(_notice(main).begins_with("당첨"), "큰 당첨: 결과 문구가 먼저, 해제 이유가 그 뒤")
	data.auto_stop_on_win_at = original
	main.free()
	await get_tree().process_frame


## 피버 연출 중에는 대기시간이 흐르지 않고, 연출이 끝나 정산된 뒤부터 대기시간이 시작된다
func _test_auto_with_fever() -> void:
	var data: BalanceData = _fever_test_data()
	var n: int = _find_fever_spin(data, 1)
	if n < 0:
		_check(false, "(준비) 피버가 나오는 스핀을 찾음")
		return
	var main: Control = await _fever_world(data, n)
	GameState.start_auto()
	var reached: bool = _advance_to_fever(main)
	_check(reached, "AUTO 판에서 피버 연출이 시작됨")
	_advance_for(main, 0.3)
	_check(main.fever_playing() and GameState.spinning and GameState.auto_count() == 1, "피버 연출 중에는 새 판이 시작되지 않음")
	var guard: int = 0
	while GameState.spinning and guard < 6000:
		main.advance(FRAME_DT)
		guard += 1
	_check(not GameState.spinning and not main.fever_playing(), "연출이 끝나고 정산됨")
	_advance_for(main, AUTO_GAP_SEC - 0.15)
	_check(not GameState.spinning, "연출이 끝난 뒤 대기시간 전에는 다음 판이 시작되지 않음")
	_advance_for(main, 0.3)
	_check(GameState.spinning and GameState.auto_count() == 2, "연출이 끝난 뒤 대기시간이 지나면 다음 판 시작")
	GameState.stop_auto(AutoSpin.REASON_USER)
	main.free()
	await get_tree().process_frame


# ---------------------------------------------------------------- 6-F3b 정산 연출

## 정산 연출이 켜진(기본값) main. 크레딧은 넉넉히 둔다.
func _settle_main(rng_seed: int, credit: int, total_bet: int) -> Control:
	GameState.initialize(GameState.get_balance(), GameState.load_economy(), rng_seed)
	GameState.credit = credit
	while GameState.bet != total_bet:
		GameState.raise_bet()
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	GameState.refresh()
	return main


## START부터 정산 연출이 시작될 때까지 흘린다 (피버 연출은 끝까지 본다). 시작했으면 true, 당첨 없이 끝났으면 false.
func _run_to_settle_show(main: Control) -> bool:
	main.do_spin()
	var guard: int = 0
	while guard < 9000:
		main.advance(FRAME_DT)
		guard += 1
		if main.settle_active():
			return true
		if not GameState.spinning and not main.fever_playing():
			return false
	return false


func _find_settle_show(main: Control, tries: int) -> bool:
	for i: int in tries:
		if _run_to_settle_show(main):
			return true
	return false


func _test_settle_show() -> void:
	_test_settle_unit()
	_test_settle_feel_keys()
	await _test_settle_main_flow()
	await _test_settle_interrupts()
	await _test_settle_auto()
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)


func _test_settle_feel_keys() -> void:
	var defaults: FeelConfig = FeelConfig.from_dict({})
	_check(defaults.countup_small_sec == 0.6 and defaults.countup_mid_sec == 1.2 and defaults.countup_big_sec == 2.5, "카운트업 시간 기본값 소 0.6 / 중 1.2 / 대 2.5")
	_check(defaults.coin_count(FeelConfig.TIER_SMALL) == 3 and defaults.coin_count(FeelConfig.TIER_MID) == 6 and defaults.coin_count(FeelConfig.TIER_BIG) == 12, "동전 개수 기본값 소 3 / 중 6 / 대 12")
	_check(defaults.coin_fly_sec == 0.45 and defaults.auto_effect_scale == 0.5 and defaults.countup_tick_sec == 0.05, "동전 비행 0.45 / AUTO 배율 0.5 / 틱 간격 0.05")
	_check(defaults.countup_sec(FeelConfig.TIER_MID) == 1.2 and defaults.countup_sec(FeelConfig.TIER_BIG) == 2.5, "countup_sec(단계) 조회")
	var bad: FeelConfig = FeelConfig.from_dict({"countup_big_sec": 99, "coin_count_mid": 0, "auto_effect_scale": 2})
	_check(bad.countup_big_sec == 2.5 and bad.coin_count(FeelConfig.TIER_MID) == 6 and bad.auto_effect_scale == 0.5, "범위 밖 값은 기본값으로 대체")
	var from_file: FeelConfig = FeelConfig.load_from_file(FeelConfig.DEFAULT_PATH, false)
	_check(from_file.file_ok and from_file.errors.is_empty(), "feel.json이 새 키 포함해서 오류 없이 읽힘")


func _test_settle_unit() -> void:
	var show: SettleShow = SettleShow.new()
	add_child(show)
	var counts: Dictionary = {"tick": 0, "land": 0, "fin": 0}
	show.tick.connect(func() -> void: counts["tick"] += 1)
	show.coin_landed.connect(func() -> void: counts["land"] += 1)
	show.finished.connect(func() -> void: counts["fin"] += 1)
	show.start(100, 500, 1.0, 4, 0.5, 0.1, Vector2(400, 0), Vector2(0, 0))
	_check(show.is_active() and show.win_shown() == 0 and show.credit_shown() == 500, "시작: WIN 0, CREDIT은 정산 전 값")
	_check(is_equal_approx(show.total_sec(), 1.5) and show.coin_count() == 4 and show.credit_final() == 600, "총 시간 = 카운트업 + 비행, 동전 4개, 최종 600")
	show.advance(0.5)
	_check(show.win_shown() == 50, "카운트업 절반 → WIN 50")
	_check(show.flying_count() == 2 and show.landed_count() == 0 and show.credit_shown() == 500, "동전 2개 비행 중, 아직 도착 없음 → CREDIT 그대로")
	var coin0: TextureRect = show.get_node("Coin0")
	_check(coin0.position.is_equal_approx(Vector2(200.0 - 12.0, -SettleShow.COIN_ARC_PX - 12.0)), "동전은 포물선: 중간 지점에서 가장 높이(%.0fpx) 솟음" % SettleShow.COIN_ARC_PX)
	show.advance(0.3)
	_check(show.landed_count() == 1 and show.credit_shown() == 525 and counts["land"] == 1, "동전 1개 도착 → CREDIT +25")
	show.advance(0.8)
	_check(not show.is_active() and show.win_shown() == 100 and show.credit_shown() == 600, "끝: WIN 100, CREDIT 600 (최종값과 정확히 일치)")
	_check(counts["land"] == 4 and counts["fin"] == 1 and counts["tick"] > 0 and show.flying_count() == 0, "동전 4번 도착 / 끝 알림 1번 / 틱 소리 있음 / 남은 동전 없음")
	# 나머지는 마지막 동전이 더한다
	show.start(10, 0, 0.6, 3, 0.45, 0.05, Vector2.ZERO, Vector2(100, 0))
	var shares: Array[int] = [show.coin_share(0), show.coin_share(1), show.coin_share(2)]
	_check(shares == [3, 3, 4], "10을 동전 3개로: 3 + 3 + 4 (마지막 동전이 나머지)")
	for i: int in 200:
		show.advance(0.01)
	_check(show.credit_shown() == 10 and not show.is_active(), "나머지 포함 CREDIT이 정확히 최종값")
	# 동전 수는 당첨금을 넘지 않는다 + 건너뛰기
	show.start(2, 40, 1.0, 12, 0.5, 0.05, Vector2.ZERO, Vector2(100, 0))
	_check(show.coin_count() == 2, "당첨금 2이면 동전 2개로 줄임")
	show.advance(0.2)
	var lands_before: int = counts["land"]
	var ticks_before: int = counts["tick"]
	show.finish_now()
	_check(not show.is_active() and show.win_shown() == 2 and show.credit_shown() == 42, "건너뛰기: 바로 최종값 (WIN 2, CREDIT 42)")
	_check(counts["land"] == lands_before and counts["tick"] == ticks_before, "건너뛰기에는 소리(틱·도착)가 나지 않음")
	var fin_before: int = counts["fin"]
	show.finish_now()
	show.advance(5.0)
	_check(counts["fin"] == fin_before and show.credit_shown() == 42, "끝난 뒤 건너뛰기·시간 진행은 아무 영향 없음")
	show.free()


func _test_settle_main_flow() -> void:
	var main: Control = await _settle_main(31, 100000, FULL_BET)
	_check(main.settle_presentation and not main.settle_active(), "정산 연출 기본값 켜짐, 처음엔 재생 중 아님")
	_check(main.get_node("SettleShow") == main.settle_show() and main.settle_show().mouse_filter == Control.MOUSE_FILTER_IGNORE, "SettleShow 노드: 클릭 통과")
	_check(main.get_node("SettleShow").get_index() < main.get_node("FeverOverlay").get_index(), "그리기 순서: SettleShow가 피버 오버레이보다 아래")
	var bank: SoundBank = main.sound_bank()
	var found: bool = _find_settle_show(main, 400)
	_check(found, "(준비) 당첨 정산 연출이 시작됨")
	if not found:
		main.free()
		await get_tree().process_frame
		return
	var show: SettleShow = main.settle_show()
	var payout: int = GameState.last_win
	var final_credit: int = GameState.credit
	var base_credit: int = final_credit - payout
	_check(show.credit_final() == final_credit, "연출의 최종 CREDIT == 로직 크레딧")
	_check(_box(main, "WinBox").value_text() == "0" and _box(main, "CreditBox").value_text() == str(base_credit), "정산 직후: WIN 0 / CREDIT은 당첨금 더하기 전 값을 표시 (로직 값은 이미 최종)")
	_check(_notice(main).contains("당첨 %d =" % payout), "메시지 칸은 정산 즉시 최종 당첨금을 표시")
	_check(GameState.credit == final_credit and GameState.last_win == payout, "연출 중에도 로직 값은 최종값 그대로")
	bank.clear_requests()
	var total: float = show.total_sec()
	_advance_for(main, total * 0.4)
	var win_mid: int = int(_box(main, "WinBox").value_text())
	_check(win_mid < payout or payout == 1, "카운트업 도중: WIN(%d)이 최종(%d)보다 작음" % [win_mid, payout])
	_check(int(_box(main, "CreditBox").value_text()) <= final_credit, "도중 CREDIT이 최종을 넘지 않음")
	_advance_for(main, total)
	_check(not main.settle_active(), "연출이 끝남")
	_check(_box(main, "WinBox").value_text() == str(payout) and _box(main, "CreditBox").value_text() == str(final_credit), "끝난 뒤 WIN·CREDIT == 최종값 (정확히)")
	_check(show.landed_count() == show.coin_count(), "동전이 모두 도착")
	_check(bank.requests().count(SoundBank.NAME_TICK) >= show.coin_count(), "틱 소리: 동전 도착마다 + 카운트업 증가 때 (%d번)" % bank.requests().count(SoundBank.NAME_TICK))
	main.free()
	await get_tree().process_frame
	# 정산 연출을 끈 main은 숫자가 바로 반영된다
	var off: Control = await _settle_main(31, 100000, FULL_BET)
	off.settle_presentation = false
	var found_off: bool = _find_settle_show(off, 3)
	_check(not found_off and not off.settle_active(), "settle_presentation=false: 연출이 시작되지 않음")
	_check(_box(off, "CreditBox").value_text() == str(GameState.credit) and _box(off, "WinBox").value_text() == str(GameState.last_win), "settle_presentation=false: 숫자 즉시 반영")
	off.free()
	await get_tree().process_frame


## 연출이 시작된 상태의 main을 준비한다. 못 찾으면 null.
func _settle_started_main(rng_seed: int) -> Control:
	var main: Control = await _settle_main(rng_seed, 100000, FULL_BET)
	if _find_settle_show(main, 400):
		return main
	main.free()
	await get_tree().process_frame
	return null


func _test_settle_interrupts() -> void:
	# START: 최종값으로 확정하고 바로 다음 판 시작
	var main: Control = await _settle_started_main(41)
	_check(main != null, "(준비) START 중단용 연출")
	if main != null:
		var show: SettleShow = main.settle_show()
		var last: Dictionary = {"win": -1, "credit": -1}
		show.win_shown_changed.connect(func(v: int) -> void: last["win"] = v)
		show.credit_shown_changed.connect(func(v: int) -> void: last["credit"] = v)
		var payout: int = GameState.last_win
		var final_credit: int = GameState.credit
		_advance_for(main, 0.1)
		var started: SpinResult = main.do_spin()
		_check(started != null and GameState.spinning and not main.settle_active(), "연출 중 START: 연출 종료 + 다음 판 바로 시작")
		_check(last["win"] == payout and last["credit"] == final_credit, "START 직전에 숫자를 최종값(WIN %d / CREDIT %d)으로 확정" % [payout, final_credit])
		_check(_box(main, "CreditBox").value_text() == str(GameState.credit) and _box(main, "WinBox").value_text() == "0", "새 판: CREDIT은 베팅 차감 값, WIN 0")
		# 연타: 이어지는 START는 회전 중 START(남은 릴 정지)로 처리되어 문제 없이 한 판이 끝남
		main.do_spin()
		main.do_spin()
		var guard: int = 0
		while GameState.spinning and guard < 9000:
			main.advance(FRAME_DT)
			guard += 1
		_check(not GameState.spinning, "START 연타 뒤에도 판이 정상적으로 끝남")
		main.free()
		await get_tree().process_frame
	# COIN: 연출 숫자를 먼저 확정한 뒤 크레딧 추가
	main = await _settle_started_main(41)
	if main != null:
		var show2: SettleShow = main.settle_show()
		var last2: Dictionary = {"credit": -1}
		show2.credit_shown_changed.connect(func(v: int) -> void: last2["credit"] = v)
		var final2: int = GameState.credit
		_advance_for(main, 0.1)
		GameState.insert_coin()
		_check(not main.settle_active() and last2["credit"] == final2, "연출 중 COIN: 먼저 최종값 확정")
		_check(_box(main, "CreditBox").value_text() == str(GameState.credit) and GameState.credit == final2 + GameState.coin_amount, "COIN 반영 후 CREDIT == 최종 + 투입량")
		_check(_box(main, "WinBox").value_text() == str(GameState.last_win), "COIN 뒤에도 WIN은 이번 판 당첨금 유지")
		main.free()
		await get_tree().process_frame


func _test_settle_auto() -> void:
	var main: Control = await _settle_main(51, 100000, FULL_BET)
	var found: bool = false
	GameState.start_auto()
	var guard: int = 0
	while guard < 60000:
		main.advance(FRAME_DT)
		guard += 1
		if main.settle_active() and GameState.auto_on:
			found = true
			break
		if not GameState.auto_on:
			GameState.start_auto()
	_check(found, "(준비) AUTO 중 정산 연출이 시작됨")
	if not found:
		GameState.stop_auto(AutoSpin.REASON_USER)
		main.free()
		await get_tree().process_frame
		return
	var show: SettleShow = main.settle_show()
	var feel: FeelConfig = main.feel()
	var tier: int = main._settle_tier(main._last_result)
	var expected: float = (feel.countup_sec(tier) + feel.coin_fly_sec) * feel.auto_effect_scale
	_check(is_equal_approx(show.total_sec(), expected), "AUTO 중 연출 시간은 배율(%.1f)만큼 짧음: %.2f초" % [feel.auto_effect_scale, expected])
	var count: int = GameState.auto_count()
	var frames: int = 0
	var leaked: bool = false
	while main.settle_active() and frames < 6000:
		main.advance(FRAME_DT)
		frames += 1
		if main.settle_active() and (GameState.spinning or GameState.auto_count() != count):
			leaked = true
	_check(not leaked and GameState.auto_on, "연출이 도는 동안 AUTO 대기가 흐르지 않고 새 판도 없음")
	_advance_for(main, feel.auto_spin_gap_sec - 0.15)
	_check(not GameState.spinning and GameState.auto_count() == count, "연출이 끝난 뒤부터 대기시간을 셈: 대기 전에는 다음 판 없음")
	_advance_for(main, 0.3)
	_check(GameState.spinning and GameState.auto_count() == count + 1, "대기시간이 지나면 다음 판 시작")
	GameState.stop_auto(AutoSpin.REASON_USER)
	main.free()
	await get_tree().process_frame


# ---------------------------------------------------------------- 7-B-3: GAME OVER 화면

## 크레딧 = 베팅 = GO_BET인 마지막 판
const GO_BET: int = 8
const GO_DRAIN_MAX_SPINS: int = 200
const GO_SCREEN_BOTTOM: float = 414.0


func _test_game_over_view() -> void:
	GameState.dev_build = OS.is_debug_build()
	var lose_seed: int = _auto_find_seed(GO_BET, GO_BET, false)
	var win_seed: int = _auto_find_seed(GO_BET, GO_BET, true)
	_check(lose_seed > 0 and win_seed > 0, "GAME OVER 테스트용 시드(마지막 판이 꽝 / 당첨)를 찾음")
	_test_go_feel_keys()
	_test_go_format_and_bgm()
	await _test_go_timing(lose_seed, win_seed)
	await _test_go_screen(lose_seed)
	await _test_go_input_blocked(lose_seed)
	await _test_go_sync_with_logic(lose_seed)
	await _test_go_continue_and_new_game(lose_seed)
	await _test_go_coin_disabled()
	GameState.dev_build = OS.is_debug_build()
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)


## 크레딧 GO_BET·베팅 GO_BET로 한 판 돌려 정산까지 끝낸다
func _go_run_spin(main: Control) -> void:
	main.do_spin()
	var time: float = 0.0
	while GameState.spinning and time < MAX_SPIN_SEC:
		main.advance(FRAME_DT)
		time += FRAME_DT


## 꽝 판을 돌려 GAME OVER 화면이 뜬 main (크레딧 0)
func _go_open_main(lose_seed: int) -> Control:
	var main: Control = await _auto_main(lose_seed, GO_BET, GO_BET)
	_go_run_spin(main)
	_advance_for(main, main.feel().gameover_delay_sec + 0.1)
	return main


## 이어하기를 쓰려고 GAME OVER가 다시 될 때까지 판을 돌린다 (크레딧을 GO_BET로 맞춰 가며). 화면이 뜰 때까지 시간을 흘린다.
func _go_drain(main: Control) -> bool:
	for i: int in GO_DRAIN_MAX_SPINS:
		if GameState.is_game_over():
			break
		GameState.credit = GO_BET
		GameState.bet = GO_BET
		_go_run_spin(main)
	_advance_for(main, main.feel().gameover_delay_sec + 0.1)
	return GameState.is_game_over() and main.game_over_open()


func _go_rows(main: Control) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for node_name: String in ["CoinButton", "StartButton", "BetButton", "MaxBetButton", "CancelButton", "AutoButton", "StopButton1", "StopButton3", "CreditBox", "WinBox", "BetBox", "NoticeBox", "PoolBox", "FeverBox", "PaytablePanel", "Title", "Reels"]:
		var control: Control = main.get_node(node_name)
		rects.append(Rect2(control.position, control.size))
	return rects


func _go_snapshot() -> Dictionary:
	return { "credit": GameState.credit, "bet": GameState.bet, "lines": GameState.line_bets.duplicate(), "win": GameState.last_win, "auto": GameState.auto_on, "spinning": GameState.spinning, "continues": GameState.continues_left, "over": GameState.is_game_over() }


func _test_go_feel_keys() -> void:
	var defaults: FeelConfig = FeelConfig.from_dict({})
	_check(defaults.gameover_delay_sec == 0.8 and defaults.gameover_input_lock_sec == 0.5 and defaults.bgm_gameover_fade_sec == 0.5, "feel 새 키 3개 기본값 (0.8 / 0.5 / 0.5)")
	var bad: FeelConfig = FeelConfig.from_dict({ "gameover_delay_sec": 99.0, "gameover_input_lock_sec": 3.5, "bgm_gameover_fade_sec": -1.0 })
	_check(bad.gameover_delay_sec == 0.8 and bad.gameover_input_lock_sec == 0.5 and bad.bgm_gameover_fade_sec == 0.5, "범위 밖 값(5 초과 / 3 초과 / 음수)은 기본값으로 대체")
	var edge: FeelConfig = FeelConfig.from_dict({ "gameover_delay_sec": 0.0, "gameover_input_lock_sec": 3.0, "bgm_gameover_fade_sec": 5.0 })
	_check(edge.gameover_delay_sec == 0.0 and edge.gameover_input_lock_sec == 3.0 and edge.bgm_gameover_fade_sec == 5.0, "범위 끝 값(0 / 3 / 5)은 그대로 읽음")
	var from_file: FeelConfig = FeelConfig.load_from_file(FeelConfig.DEFAULT_PATH, false)
	_check(from_file.errors.is_empty() and from_file.gameover_delay_sec == 0.8 and from_file.gameover_input_lock_sec == 0.5 and from_file.bgm_gameover_fade_sec == 0.5, "feel.json에 새 키 3개가 있고 문제 없음")


func _test_go_format_and_bgm() -> void:
	_check(GameOverOverlay.format_amount(0) == "0" and GameOverOverlay.format_amount(999) == "999" and GameOverOverlay.format_amount(1000) == "1,000", "천 단위 쉼표 (0 / 999 / 1,000)")
	_check(GameOverOverlay.format_amount(1234567) == "1,234,567" and GameOverOverlay.format_amount(-5000) == "-5,000", "천 단위 쉼표 (1,234,567 / -5,000)")
	# BGM 일시정지·재개
	var bgm: BgmPlayer = _make_bgm()
	bgm.pause_music(0.5)
	_check(not bgm.is_suspended() and _bgm_log(bgm) == "", "시작 전 pause_music은 아무것도 하지 않음")
	bgm.start()
	bgm.advance(1.2)
	_check(_near(bgm.gain_of(BgmPlayer.TRACK_MAIN), 1.0), "준비: 메인 BGM이 최대 음량")
	bgm.pause_music(0.5)
	bgm.pause_music(0.5)
	_check(bgm.is_suspended() and _bgm_log(bgm).count("pause") == 1, "pause_music은 한 번만 기록 (중복 호출 무시)")
	bgm.advance(0.25)
	var mid_gain: float = bgm.gain_of(BgmPlayer.TRACK_MAIN)
	_check(mid_gain > 0.0 and mid_gain < 1.0 and not bgm.is_paused(BgmPlayer.TRACK_MAIN), "페이드 중에는 소리가 줄어드는 중")
	bgm.advance(0.4)
	var held_pos: float = bgm.position_of(BgmPlayer.TRACK_MAIN)
	_check(_near(bgm.gain_of(BgmPlayer.TRACK_MAIN), 0.0) and bgm.is_paused(BgmPlayer.TRACK_MAIN), "페이드가 끝나면 음량 0 + 일시정지")
	bgm.advance(5.0)
	_check(_near(bgm.position_of(BgmPlayer.TRACK_MAIN), held_pos, 0.0001), "일시정지 동안 곡 위치가 그대로")
	bgm.resume_music(0.5)
	bgm.resume_music(0.5)
	_check(not bgm.is_suspended() and _bgm_log(bgm).count("resume") == 1, "resume_music도 한 번만 기록")
	bgm.advance(0.6)
	_check(_near(bgm.gain_of(BgmPlayer.TRACK_MAIN), 1.0) and not bgm.is_paused(BgmPlayer.TRACK_MAIN), "재개하면 음량이 돌아오고 일시정지 해제")
	_check(bgm.position_of(BgmPlayer.TRACK_MAIN) > held_pos and bgm.current_track() == BgmPlayer.TRACK_MAIN, "멈춘 자리부터 이어서 재생")
	var before: int = bgm.requests().size()
	bgm.resume_music(0.5)
	_check(bgm.requests().size() == before, "멈춰 있지 않을 때 resume_music은 무시")
	bgm.free()


## 표시 시점: 정산 직후엔 안 뜨고, 연출이 끝난 뒤 지연 시간이 지나야 뜬다. 크레딧이 남으면 안 뜬다.
func _test_go_timing(lose_seed: int, win_seed: int) -> void:
	var main: Control = await _auto_main(lose_seed, GO_BET, GO_BET)
	var overlay: GameOverOverlay = main.get_node("GameOverOverlay")
	var delay: float = main.feel().gameover_delay_sec
	_check(overlay != null and not overlay.visible and not main.game_over_open(), "처음에는 GAME OVER 화면이 없다(숨김)")
	_go_run_spin(main)
	_check(GameState.credit == 0 and GameState.is_game_over() and not GameState.spinning, "꽝 정산 직후: 로직은 이미 GAME OVER (크레딧 0)")
	_check(not main.game_over_open(), "정산 직후에는 화면이 아직 안 뜸")
	_advance_for(main, delay - 0.2)
	_check(not main.game_over_open(), "지연 시간(%.1f초)이 지나기 전에는 안 뜸" % delay)
	_advance_for(main, 0.4)
	_check(main.game_over_open() and overlay.visible, "지연 시간이 지나면 GAME OVER 화면이 뜸")
	main.free()
	await get_tree().process_frame
	# 정산 연출이 도는 동안에는 안 뜨고, 끝난 뒤 지연 시간을 센다
	var shown: Control = await _auto_main(lose_seed, GO_BET, GO_BET)
	_go_run_spin(shown)
	shown.settle_show().start(100, 0, 1.0, 3, 0.45, 0.05, Vector2(100, 100), Vector2(200, 200))
	_advance_for(shown, 1.2)
	_check(shown.settle_active() and not shown.game_over_open(), "정산 연출이 도는 동안(지연 시간이 지나도) 화면이 안 뜸")
	var frames: int = 0
	while shown.settle_active() and frames < 600:
		shown.advance(FRAME_DT)
		frames += 1
	_check(not shown.settle_active() and not shown.game_over_open(), "정산 연출이 끝난 직후에도 아직 안 뜸 (지연 시간은 연출이 끝난 뒤부터)")
	_advance_for(shown, delay + 0.1)
	_check(shown.game_over_open(), "정산 연출이 끝나고 지연 시간이 지나면 뜸")
	shown.free()
	await get_tree().process_frame
	# 당첨으로 크레딧이 남으면 안 뜬다
	var won: Control = await _auto_main(win_seed, GO_BET, GO_BET)
	_go_run_spin(won)
	_advance_for(won, delay + 1.0)
	_check(GameState.credit > 0 and not GameState.is_game_over() and not won.game_over_open(), "당첨으로 크레딧이 남으면 안 뜸")
	won.free()
	await get_tree().process_frame
	# 꽝이어도 크레딧이 남으면 안 뜬다
	var kept_seed: int = _auto_find_seed(100, GO_BET, false)
	var kept: Control = await _auto_main(kept_seed, 100, GO_BET)
	_go_run_spin(kept)
	_advance_for(kept, delay + 1.0)
	_check(GameState.credit == 100 - GO_BET and not kept.game_over_open(), "꽝이어도 크레딧이 남으면 안 뜸")
	kept.free()
	await get_tree().process_frame
	# 기다리는 동안 크레딧이 생기면(개발 빌드 COIN) 취소
	var canceled: Control = await _auto_main(lose_seed, GO_BET, GO_BET)
	_go_run_spin(canceled)
	GameState.insert_coin()
	_advance_for(canceled, delay + 1.0)
	_check(not GameState.is_game_over() and not canceled.game_over_open(), "기다리는 중 크레딧이 생기면 화면 표시를 취소")
	canceled.free()
	await get_tree().process_frame


## 화면 구성: 노드·크기·그림·버튼·글자·표시값·소리·BGM·기존 요소 위치
func _test_go_screen(lose_seed: int) -> void:
	var main: Control = await _auto_main(lose_seed, GO_BET, GO_BET)
	var before: Array[Rect2] = _go_rows(main)
	var pool_text: String = _box(main, "PoolBox").value_text()
	_go_run_spin(main)
	_advance_for(main, main.feel().gameover_delay_sec + 0.1)
	var overlay: GameOverOverlay = main.get_node("GameOverOverlay")
	var bank: SoundBank = main.sound_bank()
	_check(main.game_over_open() and overlay.is_open(), "준비: GAME OVER 화면이 뜸")
	var last_drawn: Node = null
	for child: Node in main.get_children():
		if child is CanvasItem:
			last_drawn = child
	_check(last_drawn == overlay, "GAME OVER 화면은 그려지는 노드 중 가장 위 (소리 노드는 그리기와 무관)")
	_check(overlay.position == Vector2.ZERO and overlay.size == Vector2(640, 480) and overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "화면 크기 640×480, 마우스 입력을 막음")
	_check(overlay.background().size == Vector2(640, 414) and overlay.background().position == Vector2.ZERO, "배경 그림은 640×414 (하단 표시창 줄 위까지)")
	_check(overlay.background().texture.resource_path.ends_with("gameover_bg.png") and overlay.banner().texture.resource_path.ends_with("gameover_banner.png"), "승인된 배경·배너 그림을 씀")
	_check(overlay.banner().size == Vector2(456, 84) and overlay.banner().position == Vector2(90, 30), "배너 456×84, 위치 (90, 30)")
	_check(overlay.content_bottom() <= GO_SCREEN_BOTTOM, "화면의 모든 그림·글자가 y 414 위에서 끝남 (하단 CREDIT/WIN/BET 줄은 보임)")
	var continue_button: Button = overlay.get_node("ContinueButton")
	var new_button: Button = overlay.get_node("NewGameButton")
	_check(continue_button.position == Vector2(66, 252) and new_button.position == Vector2(333, 252) and continue_button.size == Vector2(240, 54) and new_button.size == Vector2(240, 54), "버튼 2개: (66,252) / (333,252), 240×54")
	var continue_text: String = "+%s" % GameOverOverlay.format_amount(GameState.continue_credit)
	var new_text: String = "+%s" % GameOverOverlay.format_amount(GameState.start_credit)
	_check(overlay.button_texts(0) == PackedStringArray(["CONTINUE", continue_text]) and overlay.button_texts(1) == PackedStringArray(["NEW GAME", new_text]), "버튼 글자와 금액은 economy 값 (%s / %s)" % [continue_text, new_text])
	_check(overlay.remaining_text() == "CONTINUE 남은 횟수  %d / %d" % [GameState.continue_max, GameState.continue_max], "남은 횟수 글자 3 / 3")
	_check(overlay.selected() == GameOverOverlay.BUTTON_CONTINUE and not continue_button.disabled, "이어하기가 남았으면 CONTINUE가 선택되어 있고 활성")
	_check(continue_button.get_theme_stylebox("normal").texture.resource_path.ends_with("button_on.png") and new_button.get_theme_stylebox("normal").texture.resource_path.ends_with("button_normal.png"), "선택된 버튼은 켜짐(금색) 그림, 아닌 버튼은 기본 그림")
	_check(overlay.pool_text() == "POOL %s" % GameOverOverlay.format_amount(GameState.get_pool()), "POOL 표시 = 로직 값 (%s)" % overlay.pool_text())
	_check(overlay.counts_text() == _fever(main).value_text(), "피버 카운터 표시가 오른쪽 패널(로직 값)과 같음")
	_check(_sound_count(bank, SoundBank.NAME_GAMEOVER) == 1, "gameover 소리 요청이 한 번")
	var bgm: BgmPlayer = main.bgm_player()
	_check(bgm.is_suspended(), "BGM 일시정지 요청됨")
	_advance_for(main, main.feel().bgm_gameover_fade_sec + 0.1)
	_check(_near(bgm.gain_of(BgmPlayer.TRACK_MAIN), 0.0) and bgm.is_paused(BgmPlayer.TRACK_MAIN), "페이드 뒤 BGM 음량 0 + 일시정지")
	_check(_go_rows(main) == before, "GAME OVER 화면이 떠 있어도 기존 요소(버튼·표시창·릴·패널) 좌표가 그대로")
	_check(_box(main, "PoolBox").value_text() == str(GameState.get_pool()) and int(pool_text) <= GameState.get_pool(), "오른쪽 패널의 POOL은 로직 값 그대로 (마지막 판의 적립만 반영)")
	main.free()
	await get_tree().process_frame


## GAME OVER 동안 모든 입력이 무효다 (개발 빌드: COIN 가능 상태에서)
func _test_go_input_blocked(lose_seed: int) -> void:
	GameState.dev_build = true
	var main: Control = await _go_open_main(lose_seed)
	var overlay: GameOverOverlay = main.get_node("GameOverOverlay")
	var bank: SoundBank = main.sound_bank()
	_check(GameState.coin_allowed() and main.game_over_open(), "준비: 개발 빌드(COIN 가능) + GAME OVER 화면")
	_check(overlay.is_locked(), "뜬 직후에는 결정 입력이 잠겨 있음")
	# 잠금 시간 동안 결정 키·클릭 무시
	_press(main, KEY_SPACE)
	_press(main, KEY_ENTER)
	overlay.continue_button().pressed.emit()
	overlay.new_game_button().pressed.emit()
	_check(main.game_over_open() and GameState.is_game_over() and GameState.continues_left == GameState.continue_max and GameState.credit == 0, "잠금 시간 동안 스페이스·엔터·버튼 클릭이 무시됨")
	_advance_for(main, main.feel().gameover_input_lock_sec + 0.1)
	_check(not overlay.is_locked(), "잠금 시간이 지나면 풀림")
	# ←/→ 선택, 마우스 가리키기
	_press(main, KEY_RIGHT)
	_check(overlay.selected() == GameOverOverlay.BUTTON_NEW_GAME, "→ : NEW GAME 선택")
	_press(main, KEY_LEFT)
	_check(overlay.selected() == GameOverOverlay.BUTTON_CONTINUE, "← : CONTINUE 선택")
	_press(main, KEY_LEFT)
	_check(overlay.selected() == GameOverOverlay.BUTTON_CONTINUE, "← 한 번 더: 끝에서 멈춤")
	overlay.new_game_button().mouse_entered.emit()
	_check(overlay.selected() == GameOverOverlay.BUTTON_NEW_GAME, "마우스를 NEW GAME에 올리면 선택")
	overlay.select(GameOverOverlay.BUTTON_CONTINUE)
	# 모든 입력이 무효
	var coin_button: Button = main.get_node("CoinButton")
	_check(coin_button.disabled, "GAME OVER 화면이 떠 있는 동안 COIN 버튼은 비활성(회색)")
	var snapshot: Dictionary = _go_snapshot()
	var requests: int = bank.requests().size()
	for keycode: Key in [KEY_C, KEY_B, KEY_M, KEY_X, KEY_A, KEY_1, KEY_2, KEY_3, KEY_KP_1, KEY_KP_2, KEY_KP_3]:
		_press(main, keycode)
	_check(main.do_spin() == null, "START(do_spin)는 새 판을 시작하지 않음")
	_check(not main.press_bet() and not main.press_max_bet() and not main.press_cancel(), "BET·MAX BET·CANCEL 함수 무효")
	_check(not main.press_stop(0) and not main.press_stop(1) and not main.press_stop(2), "STOP 1~3 함수 무효")
	main.press_coin()
	main.press_auto()
	for node_name: String in ["CoinButton", "BetButton", "MaxBetButton", "CancelButton", "StartButton", "AutoButton", "StopButton1", "StopButton2", "StopButton3"]:
		(main.get_node(node_name) as Button).pressed.emit()
	_check(_go_snapshot().hash() == snapshot.hash(), "C 키·COIN 버튼·BET·MAX BET·CANCEL·START·AUTO·STOP 1~3을 모두 눌러도 크레딧·베팅·AUTO·회전·이어하기 횟수가 그대로")
	_check(main.game_over_open() and bank.requests().size() == requests, "화면은 그대로 열려 있고 소리도 나지 않음")
	_check(GameState.is_game_over() and GameState.credit == 0, "화면이 떠 있는 동안 상태 일관: GAME OVER ⇔ 크레딧 0")
	main.free()
	await get_tree().process_frame


## 화면과 로직이 어긋나지 않는다: 크레딧이 생기면 화면이 닫히고 BGM이 이어진다
func _test_go_sync_with_logic(lose_seed: int) -> void:
	GameState.dev_build = true
	var main: Control = await _go_open_main(lose_seed)
	var bgm: BgmPlayer = main.bgm_player()
	_advance_for(main, main.feel().bgm_gameover_fade_sec + 0.1)
	_check(main.game_over_open() and bgm.is_suspended(), "준비: GAME OVER 화면 + BGM 정지")
	GameState.insert_coin()
	_check(not GameState.is_game_over() and not main.game_over_open() and GameState.credit == GameState.coin_amount, "코드로 COIN을 넣어 크레딧이 생기면 GAME OVER 해제와 함께 화면도 닫힘")
	_check(not bgm.is_suspended() and not (main.get_node("GameOverOverlay") as Control).visible, "BGM 재개 요청, 화면 숨김")
	_advance_for(main, main.feel().bgm_gameover_fade_sec + 0.1)
	_check(_near(bgm.gain_of(BgmPlayer.TRACK_MAIN), 1.0) and not bgm.is_paused(BgmPlayer.TRACK_MAIN), "BGM이 원래 음량으로 이어서 재생")
	_check((main.get_node("CoinButton") as Button).disabled == (not GameState.coin_allowed()), "화면이 닫히면 COIN 버튼이 다시 활성")
	main.free()
	await get_tree().process_frame


## CONTINUE 3번(상태 유지·횟수·BET 복구) → 4번째는 비활성 → NEW GAME(초기화·패널 다시 그림)
func _test_go_continue_and_new_game(lose_seed: int) -> void:
	GameState.dev_build = OS.is_debug_build()
	var main: Control = await _go_open_main(lose_seed)
	var overlay: GameOverOverlay = main.get_node("GameOverOverlay")
	var bgm: BgmPlayer = main.bgm_player()
	var bank: SoundBank = main.sound_bank()
	var data: BalanceData = GameState.get_balance()
	for n: int in GameState.continue_max:
		_advance_for(main, main.feel().gameover_input_lock_sec + main.feel().bgm_gameover_fade_sec + 0.1)
		_check(overlay.is_open() and overlay.selected() == GameOverOverlay.BUTTON_CONTINUE and overlay.remaining_text() == "CONTINUE 남은 횟수  %d / %d" % [GameState.continue_max - n, GameState.continue_max], "CONTINUE %d번째 전: 남은 횟수 %d / %d" % [n + 1, GameState.continue_max - n, GameState.continue_max])
		var pool: String = _box(main, "PoolBox").value_text()
		var counts: String = _fever(main).value_text()
		var button_sounds: int = _sound_count(bank, SoundBank.NAME_BUTTON)
		_press(main, KEY_ENTER)
		_check(_sound_count(bank, SoundBank.NAME_BUTTON) == button_sounds + 1, "CONTINUE %d번째: 버튼 소리(button) 한 번" % [n + 1])
		_check(not main.game_over_open() and not GameState.is_game_over() and GameState.continues_left == GameState.continue_max - n - 1, "CONTINUE %d번째: 화면 닫힘, GAME OVER 해제, 남은 횟수 %d" % [n + 1, GameState.continue_max - n - 1])
		_check(GameState.credit == GameState.continue_credit and GameState.bet == mini(GO_BET, GameState.continue_credit) and _box(main, "BetBox").value_text() == str(GameState.bet) and _box(main, "CreditBox").value_text() == str(GameState.credit), "CONTINUE 뒤 크레딧 %d, BET 직전 값(최대 %d)으로 복구, 표시도 맞음" % [GameState.continue_credit, GO_BET])
		_check(_box(main, "PoolBox").value_text() == pool and _fever(main).value_text() == counts, "CONTINUE 뒤 POOL·피버 카운터 표시 유지")
		_check(not bgm.is_suspended(), "CONTINUE 뒤 BGM 재개")
		_check(_go_drain(main), "다시 크레딧을 다 써서 GAME OVER 화면이 뜸 (%d번째)" % [n + 2])
	# 이어하기를 다 썼다
	_advance_for(main, main.feel().gameover_input_lock_sec + 0.1)
	_check(GameState.continues_left == 0 and overlay.continue_button().disabled and overlay.selected() == GameOverOverlay.BUTTON_NEW_GAME, "이어하기 0회: CONTINUE 비활성, 선택은 NEW GAME")
	_check(overlay.remaining_text() == "CONTINUE 남은 횟수  0 / %d" % GameState.continue_max and overlay.remaining_color() == GameOverOverlay.REMAIN_ZERO_COLOR, "남은 횟수 0 / 3, 글자 빨강")
	_check(overlay.continue_button().get_theme_stylebox("disabled").texture.resource_path.ends_with("button_disabled.png"), "비활성 CONTINUE는 회색 버튼 그림")
	_press(main, KEY_LEFT)
	_press(main, KEY_RIGHT)
	_check(overlay.selected() == GameOverOverlay.BUTTON_NEW_GAME, "←/→로도 비활성 CONTINUE는 선택되지 않음")
	overlay.continue_button().pressed.emit()
	overlay.continue_pressed.emit()
	_check(main.game_over_open() and GameState.is_game_over() and GameState.credit == 0 and GameState.continues_left == 0, "비활성 CONTINUE 클릭은 무효 (화면·상태 그대로)")
	_check(_sound_count(bank, SoundBank.NAME_BUTTON) == GameState.continue_max, "무효한 CONTINUE 클릭에는 버튼 소리가 나지 않음 (성공한 %d번만)" % GameState.continue_max)
	# NEW GAME
	_check(_sound_count(bank, SoundBank.NAME_GAMEOVER) == GameState.continue_max + 1, "GAME OVER 화면이 뜰 때마다 gameover 소리 (총 %d번)" % [GameState.continue_max + 1])
	_press(main, KEY_ENTER)
	_check(_sound_count(bank, SoundBank.NAME_BUTTON) == GameState.continue_max + 1, "NEW GAME: 버튼 소리(button) 한 번")
	_check(not main.game_over_open() and not GameState.is_game_over(), "NEW GAME: 화면 닫힘, GAME OVER 해제")
	_check(GameState.credit == GameState.start_credit and _box(main, "CreditBox").value_text() == str(GameState.start_credit), "NEW GAME: 크레딧 = 시작 크레딧, 표시도 맞음")
	_check(GameState.get_pool() == data.pool_initial and _box(main, "PoolBox").value_text() == str(data.pool_initial), "NEW GAME: POOL 초기화, 오른쪽 패널이 다시 그려짐")
	var rows: PackedStringArray = PackedStringArray()
	for symbol: String in data.fever_symbols:
		rows.append("%s ×%d" % [data.symbol_names[symbol], data.fever_initial_counts[symbol]])
	_check(_fever(main).value_text() == "\n".join(rows), "NEW GAME: 피버 카운터 초기값으로 다시 그려짐")
	_check(GameState.continues_left == GameState.continue_max and GameState.bet == 0 and _box(main, "BetBox").value_text() == "0" and _box(main, "WinBox").value_text() == "0", "NEW GAME: 이어하기 횟수 복구, BET 0, WIN 0")
	_check(not bgm.is_suspended(), "NEW GAME 뒤 BGM 재개")
	_check(GameState.raise_bet() and main.do_spin() != null, "NEW GAME 뒤 정상 플레이 (BET → START)")
	main.free()
	await get_tree().process_frame


## COIN 비활성(coin_allowed가 false): 회색 버튼, C 키 무시, 안내 문구 3곳
func _test_go_coin_disabled() -> void:
	var main: Control = await _auto_main(1, 0, 0)
	var bank: SoundBank = main.sound_bank()
	var coin_button: Button = main.get_node("CoinButton")
	var position_before: Vector2 = coin_button.position
	var debug: DebugPanel = main.get_node("DebugPanel")
	GameState.dev_build = true
	GameState.refresh()
	_check(GameState.coin_allowed() and not coin_button.disabled, "개발 빌드: COIN 버튼 활성")
	_check(_notice(main).contains("COIN(C)") and debug.help_text().contains("C=COIN"), "개발 빌드: 안내 문구와 디버그 도움말에 COIN(C)")
	GameState.raise_bet()
	_check(_notice(main).contains("COIN(C)을 누르세요") and not _notice(main).contains("크레딧이 부족합니다."), "개발 빌드: 크레딧 거절 안내는 기존 COIN(C) 문구")
	GameState.dev_build = false
	GameState.refresh()
	_check(not GameState.coin_allowed() and coin_button.disabled, "릴리즈 빌드(dev_build false): COIN 버튼 회색 비활성")
	_check(coin_button.position == position_before, "COIN 버튼 위치는 그대로")
	_check(_notice(main).contains("크레딧이 부족합니다.") and not _notice(main).contains("COIN(C)"), "릴리즈 빌드: 안내 문구가 '크레딧이 부족합니다.'")
	GameState.raise_bet()
	_check(_notice(main).contains("크레딧이 부족합니다.") and not _notice(main).contains("COIN(C)"), "릴리즈 빌드: 크레딧 거절 안내도 '크레딧이 부족합니다.'")
	_check(not debug.help_text().contains("C=COIN") and debug.help_text().contains("COIN 사용 불가"), "릴리즈 빌드: 디버그 도움말에서 COIN 줄이 빠짐")
	bank.clear_requests()
	_press(main, KEY_C)
	coin_button.pressed.emit()
	main.press_coin()
	_check(GameState.credit == 0 and _sound_count(bank, SoundBank.NAME_COIN) == 0 and not GameState.run_tainted, "COIN 불가: C 키·버튼이 크레딧을 바꾸지 않고 소리도 없음")
	GameState.dev_build = true
	GameState.refresh()
	_press(main, KEY_C)
	_check(GameState.credit == GameState.coin_amount and GameState.run_tainted and _sound_count(bank, SoundBank.NAME_COIN) == 1, "다시 개발 빌드: C 키로 COIN 지급 + 소리 + 테스트 판 표시")
	main.free()
	await get_tree().process_frame


# ---------------------------------------------------------------- 7-C 시작 화면

const TITLE_SCENE_PATH: String = "res://scenes/title.tscn"
const MAIN_SCENE_FILE: String = "res://scenes/main.tscn"


## 시작 화면 인스턴스를 만든다 (씬 전환·종료는 직접 하지 않고 시그널만 받는다).
func _make_title() -> TitleScreen:
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)
	var title: TitleScreen = (load(TITLE_SCENE_PATH) as PackedScene).instantiate() as TitleScreen
	title.auto_connect = false
	add_child(title)
	title.set_process(false)
	return title


func _key(target: Node, keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	target._unhandled_key_input(event)


func _test_title_screen() -> void:
	await _test_title_entry()
	await _test_title_layout()
	await _test_title_animation()
	await _test_title_start()
	await _test_title_exit_and_keys()
	_test_title_feel_key()


## 메인 씬 설정, main 단독 실행(F6), 게임 화면 요소 위치 불변
func _test_title_entry() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == TITLE_SCENE_PATH, "프로젝트 메인 씬 = title.tscn")
	_check(ResourceLoader.exists(MAIN_SCENE_FILE) and TitleScreen.MAIN_SCENE_PATH == MAIN_SCENE_FILE, "START 뒤에 갈 게임 씬(main.tscn)이 있음")
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)
	var solo: Control = (load(MAIN_SCENE_FILE) as PackedScene).instantiate()
	solo.settle_presentation = false
	add_child(solo)
	solo.set_process(false)
	await get_tree().process_frame
	_check(GameState.credit == 0 and not GameState.is_game_over() and not solo.game_over_overlay().is_open(), "initialize 직후 main은 GAME OVER 아님 (크레딧 0, 오버레이 닫힘)")
	var start_button: Button = solo.get_node("StartButton")
	_check(start_button.position == Vector2(189, 360) and start_button.size == Vector2(81, 36), "게임 화면 START 버튼 위치·크기 불변")
	var title_panel: Panel = solo.get_node("Title")
	_check(title_panel.position == Vector2(450, 9) and title_panel.size == Vector2(180, 72), "게임 화면 오른쪽 위 로고 칸 위치·크기 불변")
	_check(solo.get_node("Title/TitleLogo") != null and solo.get_node("FrameBulbs") != null, "게임 화면 로고·전구 노드 그대로")
	solo.free()
	await get_tree().process_frame


func _test_title_layout() -> void:
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	for node_name: String in ["Background", "Wallpaper", "Frame", "FrameBulbs", "MainPanel", "BottomPanel", "Logo", "StartButton", "ExitButton", "PressLabel", "HintLabel", "SoundBank"]:
		_check(title.get_node_or_null(node_name) != null, "시작 화면 노드 있음: %s" % node_name)
	var logo: TextureRect = title.logo()
	_check(logo.texture.resource_path.ends_with("assets/ui/logo.png") and logo.texture.get_size() == Vector2(180, 72), "로고는 기존 logo.png(180×72)")
	_check(logo.size == Vector2(360, 144) and logo.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "로고는 정수 2배(360×144) + Nearest")
	_check(logo.position == Vector2(140, 30) and logo.position == logo.position.floor(), "로고 위치 (140, 30) 정수 좌표 (미리보기와 같음)")
	var start: Button = title.start_button()
	var exit: Button = title.exit_button()
	_check(start.text == "START" and exit.text == "EXIT", "버튼 글자 START / EXIT")
	_check(start.position == Vector2(240, 222) and exit.position == Vector2(240, 276) and start.size == Vector2(160, 36) and exit.size == Vector2(160, 36), "START·EXIT 위치·크기 (미리보기와 같음)")
	_check(start.focus_mode == Control.FOCUS_NONE and exit.focus_mode == Control.FOCUS_NONE, "버튼은 포커스를 받지 않음 (스페이스·엔터 이중 처리 방지)")
	var same_look: bool = start.get_theme_stylebox("normal") == exit.get_theme_stylebox("normal") and start.get_theme_color("font_color") == exit.get_theme_color("font_color")
	_check(same_look and not start.has_theme_stylebox_override("normal") and not exit.has_theme_stylebox_override("normal"), "START·EXIT는 선택 강조 없이 같은 일반 버튼 모양")
	_check(title.press_label().text == "PRESS START" and (title.get_node("HintLabel") as Label).text == "SPACE / ENTER  시작     ESC  종료", "PRESS START·안내 문구")
	var panel: Panel = title.get_node("MainPanel")
	_check(panel.position == Vector2(57, 9) and panel.size == Vector2(526, 345), "큰 패널 위치·크기")
	var bottom: Panel = title.get_node("BottomPanel")
	_check(bottom.position == Vector2(57, 414) and bottom.size == Vector2(526, 57), "하단 패널 위치·크기")
	_check(title.sound_bank() != null and AudioServer.get_bus_index(SoundBank.BUS_SFX) != -1, "효과음 뱅크와 SFX 버스 준비")
	var has_bgm: bool = false
	for child: Node in title.get_children():
		has_bgm = has_bgm or child is BgmPlayer
	_check(not has_bgm, "시작 화면 BGM은 무음 (BgmPlayer 없음)")
	title.free()
	await get_tree().process_frame


func _test_title_animation() -> void:
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	var feel: FeelConfig = FeelConfig.load_from_file()
	var bulbs: FrameBulbs = title.frame_bulbs()
	_check(bulbs.mode() == BulbPattern.Mode.IDLE and bulbs.socket_count() == 18, "전구는 기존 대기(IDLE) 패턴, 소켓 18개")
	var before: int = bulbs.bulb_state(0)
	title.advance(feel.bulb_idle_sec)
	_check(bulbs.bulb_state(0) != before, "전구 대기 패턴이 시간에 따라 번갈아 켜짐")
	_check(title.press_label().visible == title.blink_visible(), "PRESS START 표시 = 깜빡임 상태")
	var fresh: TitleScreen = _make_title()
	await get_tree().process_frame
	_check(fresh.blink_visible() and fresh.press_label().visible, "처음엔 PRESS START가 보임")
	fresh.advance(feel.title_blink_sec)
	_check(not fresh.blink_visible() and not fresh.press_label().visible, "title_blink_sec 뒤에 꺼짐")
	fresh.advance(feel.title_blink_sec)
	_check(fresh.blink_visible() and fresh.press_label().visible, "다시 title_blink_sec 뒤에 켜짐")
	fresh.free()
	title.free()
	await get_tree().process_frame


func _test_title_start() -> void:
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	var events: Array[String] = []
	var on_new_game: Callable = func() -> void: events.append("new_game")
	var on_granted: Callable = func(amount: int, reason: StringName) -> void: events.append("granted %d %s" % [amount, reason])
	GameState.new_game_started.connect(on_new_game)
	GameState.credit_granted.connect(on_granted)
	title.start_requested.connect(func() -> void: events.append("requested"))
	title.start_finished.connect(func() -> void: events.append("finished"))
	var bank: SoundBank = title.sound_bank()
	bank.clear_requests()
	_check(GameState.credit == 0 and not GameState.is_game_over(), "START 전: 크레딧 0")
	_key(title, KEY_ENTER)
	var data: BalanceData = GameState.get_balance()
	_check(title.is_starting() and GameState.credit == GameState.start_credit, "ENTER: new_game() 실행 → 시작 크레딧 지급")
	_check(GameState.get_pool() == data.pool_initial and GameState.get_fever_counts().hash() == data.fever_initial_counts.hash(), "START: POOL·피버 카운터 초기값")
	_check(GameState.continues_left == GameState.continue_max and not GameState.run_tainted and GameState.bet == 0, "START: 이어하기 횟수 복구·테스트 판 표시 없음·베팅 0")
	_check(events == ["new_game", "granted %d start" % GameState.start_credit, "requested"], "START 순서: new_game_started → 시작 지급(start) → requested (%s)" % [events])
	_check(_sound_count(bank, SoundBank.NAME_BUTTON) == 1, "START: button.wav 한 번")
	# 소리가 끝나기 전의 중복 입력은 모두 무시
	_key(title, KEY_SPACE)
	_key(title, KEY_KP_ENTER)
	title.start_button().pressed.emit()
	title.exit_button().pressed.emit()
	_key(title, KEY_ESCAPE)
	var duplicate_start: bool = title.press_start()
	var duplicate_exit: bool = title.press_exit()
	_check(not duplicate_start and not duplicate_exit, "소리 대기 중 START·EXIT 재입력은 거절")
	var granted_count: int = events.filter(func(e: String) -> bool: return e.begins_with("granted")).size()
	_check(granted_count == 1 and events.count("new_game") == 1 and GameState.credit == GameState.start_credit, "중복 입력해도 new_game()은 한 번 (시작 크레딧 한 번만)")
	_check(_sound_count(bank, SoundBank.NAME_BUTTON) == 1 and events.count("requested") == 1, "중복 입력해도 소리·요청은 한 번")
	# 소리 길이만큼 기다린 뒤에만 게임 화면으로 넘어간다
	var length: float = (load(SoundBank.sound_path(SoundBank.NAME_BUTTON)) as AudioStream).get_length()
	title.advance(maxf(0.0, length - 0.05))
	_check(events.count("finished") == 0, "button.wav가 끝나기 전에는 전환하지 않음 (소리가 잘리지 않음)")
	title.advance(0.1)
	_check(events.count("finished") == 1, "button.wav가 끝나면 전환 신호 한 번")
	title.advance(5.0)
	_check(events.count("finished") == 1, "전환 신호는 한 번만")
	GameState.new_game_started.disconnect(on_new_game)
	GameState.credit_granted.disconnect(on_granted)
	title.free()
	await get_tree().process_frame
	# START 뒤 COIN은 coin_allowed() 규칙 그대로
	var dev_before: bool = GameState.dev_build
	GameState.dev_build = false
	GameState.insert_coin()
	_check(not GameState.coin_allowed() and GameState.credit == GameState.start_credit, "START 뒤 릴리즈 빌드: COIN 불가")
	GameState.dev_build = dev_before


func _test_title_exit_and_keys() -> void:
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	var exits: Array[int] = [0]
	title.exit_requested.connect(func() -> void: exits[0] += 1)
	var starts: Array[int] = [0]
	title.start_requested.connect(func() -> void: starts[0] += 1)
	# 개발용·게임용 키는 이 화면에서 무시
	for keycode: Key in [KEY_F1, KEY_F6, KEY_C, KEY_B, KEY_M, KEY_X, KEY_A, KEY_1, KEY_LEFT, KEY_RIGHT]:
		_key(title, keycode)
	_check(starts[0] == 0 and exits[0] == 0 and GameState.credit == 0 and not title.is_starting(), "F1·F6·C·B 등 다른 키는 무시 (시작도 종료도 안 됨)")
	_key(title, KEY_ESCAPE)
	_check(exits[0] == 1 and GameState.credit == 0 and not title.is_starting(), "ESC = 확인 없이 바로 EXIT 요청 (크레딧·상태 불변)")
	title.exit_button().pressed.emit()
	_check(exits[0] == 2, "EXIT 버튼 클릭도 종료 요청")
	_check(starts[0] == 0, "EXIT는 START를 부르지 않음")
	title.free()
	await get_tree().process_frame


func _test_title_feel_key() -> void:
	var defaults: FeelConfig = FeelConfig.from_dict({})
	_check(defaults.title_blink_sec == 0.6, "feel 새 키 title_blink_sec 기본값 0.6")
	var low: FeelConfig = FeelConfig.from_dict({ "title_blink_sec": 0.1 })
	var high: FeelConfig = FeelConfig.from_dict({ "title_blink_sec": 2.5 })
	_check(low.title_blink_sec == 0.6 and high.title_blink_sec == 0.6, "범위 밖 값(0.2 미만 / 2 초과)은 기본값으로 대체")
	var edge: FeelConfig = FeelConfig.from_dict({ "title_blink_sec": 0.2 })
	var edge_high: FeelConfig = FeelConfig.from_dict({ "title_blink_sec": 2.0 })
	_check(edge.title_blink_sec == 0.2 and edge_high.title_blink_sec == 2.0, "경계값 0.2 / 2.0은 그대로")
	var real: FeelConfig = FeelConfig.load_from_file()
	_check(real.errors.is_empty() and real.title_blink_sec == 0.6, "data/feel.json의 title_blink_sec = 0.6, 문제 없음")


# ---------------------------------------------------------------- 8-A 운영자 설정 화면

## 설정 저장·불러오기를 확인할 때만 켜는 격리 폴더. 개발자 PC의 실제 user://settings.json·highscore.json은 건드리지 않는다.
const SETTINGS_TEST_DIR: String = "user://settings_test_view/"


func _settings_begin() -> void:
	_settings_clean()
	UserSettings.configure(true, SETTINGS_TEST_DIR)


func _settings_end() -> void:
	UserSettings.configure(false)
	_settings_clean()
	var feel: FeelConfig = FeelConfig.load_from_file()
	SettingsScreen.apply_audio(feel.sfx_volume_db, feel.bgm_volume_db, true)


func _settings_clean() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null or not dir.dir_exists("settings_test_view"):
		return
	var inner: DirAccess = DirAccess.open(SETTINGS_TEST_DIR)
	for file_name: String in inner.get_files():
		inner.remove(file_name)
	dir.remove("settings_test_view")


func _key_shift(target: Node, keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = true
	target._unhandled_key_input(event)


func _sfx_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(SoundBank.BUS_SFX))


func _bgm_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(SoundBank.BUS_BGM))


func _bgm_muted() -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(SoundBank.BUS_BGM))


func _test_settings_screen() -> void:
	await _test_settings_open_and_keys()
	await _test_settings_layout_and_tabs()
	await _test_settings_values()
	await _test_settings_save_and_cancel()
	await _test_settings_resets()
	await _test_settings_applied_in_game()
	await _test_settings_dev_and_best()


## F2로 열기, 열려 있는 동안 입력 격리 (Esc는 설정만 닫고 게임을 종료하지 않음)
func _test_settings_open_and_keys() -> void:
	_settings_begin()
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	var settings: SettingsScreen = title.settings_screen()
	var exits: Array[int] = [0]
	title.exit_requested.connect(func() -> void: exits[0] += 1)
	var starts: Array[int] = [0]
	title.start_requested.connect(func() -> void: starts[0] += 1)
	var closes: Array[bool] = []
	settings.closed.connect(func(saved: bool) -> void: closes.append(saved))
	_check(settings != null and not settings.is_open() and not settings.visible, "설정 화면: 처음엔 닫혀 있고 보이지 않음")
	_check(title.get_child(title.get_child_count() - 1) == settings, "설정 화면은 시작 화면 위(맨 마지막 자식)")
	_check(settings.size == Vector2(640, 480) and settings.mouse_filter == Control.MOUSE_FILTER_STOP, "설정 화면: 640×480 전체를 덮고 클릭을 막음")
	for keycode: Key in [KEY_F1, KEY_F6, KEY_C, KEY_B, KEY_LEFT]:
		_key(title, keycode)
	_check(not settings.is_open(), "F2가 아닌 키로는 열리지 않음")
	_key(title, KEY_F2)
	_check(settings.is_open() and settings.visible and not title.is_starting(), "F2: 운영자 설정 열림")
	_check(not title.open_settings() and not title.press_start() and not title.press_exit(), "열려 있는 동안: 다시 열기·START·EXIT 모두 거절")
	_key(title, KEY_F2)
	_check(settings.is_open(), "열려 있을 때 F2를 또 눌러도 그대로")
	for keycode: Key in [KEY_F1, KEY_F6, KEY_C, KEY_B, KEY_M, KEY_X, KEY_A, KEY_1]:
		_key(title, keycode)
	_check(settings.draft().is_empty() and settings.is_open() and starts[0] == 0 and exits[0] == 0, "열려 있는 동안 F1·F6·C 등은 무반응")
	_key(title, KEY_SPACE)
	_check(starts[0] == 0 and not title.is_starting() and GameState.credit == 0, "열려 있는 동안 Space는 START가 아님")
	_key(title, KEY_ESCAPE)
	_check(not settings.is_open() and not settings.visible and exits[0] == 0 and closes == [false], "Esc: 설정만 닫고(취소) 게임을 종료하지 않음")
	_check(not title.is_starting() and GameState.credit == 0, "Esc로 닫아도 START·크레딧에는 변화 없음")
	_key(title, KEY_ESCAPE)
	_check(exits[0] == 1, "설정이 닫힌 뒤의 Esc는 원래대로 EXIT 요청")
	_key(title, KEY_F2)
	_key(title, KEY_ENTER)
	_check(not settings.is_open() and closes == [false, true] and starts[0] == 0 and not title.is_starting() and GameState.credit == 0, "Enter: 저장하고 닫기이고 START는 아님")
	title.free()
	await get_tree().process_frame
	# START가 받아들여진 뒤에는 열리지 않음
	var started: TitleScreen = _make_title()
	await get_tree().process_frame
	started.press_start()
	_key(started, KEY_F2)
	_check(not started.settings_screen().is_open() and not started.open_settings(), "START 뒤(소리 대기 중)에는 F2가 열리지 않음")
	started.free()
	await get_tree().process_frame
	_settings_end()


func _test_settings_layout_and_tabs() -> void:
	_settings_begin()
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	var settings: SettingsScreen = title.settings_screen()
	for node_name: String in ["MainPanel", "FooterPanel", "TitleLabel", "Tab0", "Tab1", "Tab2", "Rows", "HintLabel", "DefaultsButton", "CancelButton", "SaveButton"]:
		_check(settings.get_node_or_null(node_name) != null, "설정 화면 노드 있음: %s" % node_name)
	var main_panel: Panel = settings.get_node("MainPanel")
	var footer: Panel = settings.get_node("FooterPanel")
	_check(main_panel.position == Vector2(57, 9) and main_panel.size == Vector2(526, 345) and footer.position == Vector2(57, 414) and footer.size == Vector2(526, 57), "패널 위치·크기 (시작 화면 패널과 같은 자리)")
	_check(settings.defaults_button().position == Vector2(85, 424) and settings.cancel_button().position == Vector2(245, 424) and settings.save_button().position == Vector2(405, 424) and settings.save_button().size == Vector2(150, 36), "하단 버튼 3개 위치·크기")
	_check(settings.defaults_button().text == "기본값으로" and settings.cancel_button().text == "취소" and settings.save_button().text == "저장하고 닫기", "하단 버튼 글자")
	_check(settings.tab_button(0).text == "소리·AUTO" and settings.tab_button(1).text == "크레딧" and settings.tab_button(2).text == "연출" and settings.tab_button(0).position == Vector2(87, 42), "탭 버튼 3개 글자·위치")
	settings.open()
	_check(settings.tab() == 0 and settings.row_keys() == ["sfx_volume_db", "bgm_volume_db", "bgm_enabled", "auto_stop_on_win_at", "auto_effect_scale"], "소리·AUTO 탭의 줄 5개")
	settings.select_tab(1)
	_check(settings.row_keys() == ["start_credit", "continue_credit", "continue_max", "coin_amount", "best", "best_reset"], "크레딧 탭의 줄 (개발 빌드: COIN 지급량 포함)")
	settings.select_tab(2)
	_check(settings.row_keys() == ["countup_small_sec", "countup_mid_sec", "countup_big_sec", "win_mid_ratio", "win_big_ratio"], "연출 탭의 줄 5개")
	var within: bool = true
	for tab_index: int in 3:
		settings.select_tab(tab_index)
		for key: String in settings.row_keys():
			var row: Control = settings.row_node(key)
			within = within and row.position.x >= 57 and row.position.x + row.size.x <= 583 and row.position.y >= 82 and row.position.y + row.size.y <= 322
	_check(within, "모든 줄이 큰 패널 안, 안내 글자 위에 들어감")
	_check(settings.row_node("win_mid_ratio").position == Vector2(69, 82 + 30 * 3), "줄 위치: x 69, y = 82 + 30 × 줄 번호")
	# 탭 이동: 클릭 / Tab / Shift+Tab / PageUp·PageDown (돌아서 이어짐)
	settings.select_tab(0)
	settings.tab_button(1).pressed.emit()
	_check(settings.tab() == 1, "탭 버튼 클릭")
	_key(title, KEY_TAB)
	_check(settings.tab() == 2, "Tab: 다음 탭")
	_key(title, KEY_TAB)
	_check(settings.tab() == 0, "Tab: 마지막 탭에서 처음으로")
	_key_shift(title, KEY_TAB)
	_check(settings.tab() == 2, "Shift+Tab: 이전 탭 (처음에서 마지막으로)")
	_key(title, KEY_PAGEUP)
	_check(settings.tab() == 1, "PageUp: 이전 탭")
	_key(title, KEY_PAGEDOWN)
	_key(title, KEY_PAGEDOWN)
	_check(settings.tab() == 0, "PageDown: 다음 탭 (돌아서 처음으로)")
	# 줄 선택: ↑/↓ (돌아서 이어짐), 탭을 바꾸면 첫 줄
	_check(settings.selected_key() == "sfx_volume_db", "탭을 열면 첫 줄이 선택됨")
	_key(title, KEY_UP)
	_check(settings.selected_key() == "auto_effect_scale", "↑: 첫 줄에서 마지막 줄로")
	_key(title, KEY_DOWN)
	_check(settings.selected_key() == "sfx_volume_db", "↓: 마지막 줄에서 첫 줄로")
	_key(title, KEY_DOWN)
	_check(settings.selected_key() == "bgm_volume_db" and (settings.row_node("bgm_volume_db").get_node("Highlight") as ColorRect).visible and not (settings.row_node("sfx_volume_db").get_node("Highlight") as ColorRect).visible, "↓: 다음 줄, 선택 막대는 한 줄에만")
	settings.select_tab(1)
	_check(settings.selected_key() == "start_credit", "탭을 바꾸면 그 탭의 첫 줄이 선택됨")
	settings.cancel()
	title.free()
	await get_tree().process_frame
	# 릴리즈 빌드(dev_build false): 개발 전용 줄·DEV 라벨 없음
	var dev_before: bool = GameState.dev_build
	GameState.dev_build = false
	var release: TitleScreen = _make_title()
	await get_tree().process_frame
	release.open_settings()
	release.settings_screen().select_tab(1)
	_check(release.settings_screen().row_keys() == ["start_credit", "continue_credit", "continue_max", "best", "best_reset"] and release.settings_screen().row_node("coin_amount") == null, "릴리즈 빌드: COIN 지급량 줄이 없음 (밸런스 줄은 어디에도 없음)")
	_check(release.get_node_or_null("DevLabel") == null, "릴리즈 빌드: DEV 라벨 노드를 만들지 않음")
	release.settings_screen().cancel()
	release.free()
	await get_tree().process_frame
	GameState.dev_build = true
	var dev: TitleScreen = _make_title()
	await get_tree().process_frame
	var dev_label: Label = dev.get_node_or_null("DevLabel") as Label
	_check(dev_label != null and dev_label.text == "DEV" and dev_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "개발 빌드: 오른쪽 아래에 DEV 라벨")
	_check(dev_label.position == Vector2(583 - 48 - 6, 414 + 6) and dev.get_node("BottomPanel").get_rect().encloses(dev_label.get_rect()), "DEV 라벨은 하단 패널 오른쪽 안")
	dev.free()
	await get_tree().process_frame
	GameState.dev_build = dev_before
	_settings_end()


func _test_settings_values() -> void:
	_settings_begin()
	var feel: FeelConfig = FeelConfig.load_from_file()
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	var settings: SettingsScreen = title.settings_screen()
	var bank: SoundBank = title.sound_bank()
	title.open_settings()
	_check(settings.value_text("sfx_volume_db") == "%d dB" % int(feel.sfx_volume_db) and settings.value_text("bgm_enabled") == "켜짐" and settings.value_text("auto_stop_on_win_at") == "사용 안 함", "처음 값 표시는 기본값(feel.json·balance.json)")
	var all_white: bool = true
	for key: String in settings.row_keys():
		all_white = all_white and (settings.value_is_changed(key) == false)
	_check(all_white and settings.value_label("sfx_volume_db").get_theme_color("font_color") == Color("ffffff"), "기본값과 같으면 흰색 (노랑 아님)")
	# SFX 볼륨: ←/→ 1dB, Shift 5dB, 만지는 동안 버스에 바로 반영 + 소리 확인용 효과음
	bank.clear_requests()
	_key(title, KEY_RIGHT)
	_check(is_equal_approx(_sfx_db(), feel.sfx_volume_db + 1.0) and settings.value_text("sfx_volume_db") == "%d dB" % int(feel.sfx_volume_db + 1.0), "→: 효과음 볼륨 +1 dB가 버스에 즉시 반영")
	_check(_sound_count(bank, SoundBank.NAME_BUTTON) == 1, "효과음 볼륨을 바꾸면 확인용 소리가 남")
	_check(settings.value_is_changed("sfx_volume_db") and settings.value_label("sfx_volume_db").get_theme_color("font_color") == Color("ffd23a"), "기본값과 다르면 노랑")
	_check(settings.draft().get_or("sfx_volume_db", -99.0) == feel.sfx_volume_db + 1.0, "초안에 저장될 값으로 들어감")
	_key(title, KEY_LEFT)
	_check(not settings.value_is_changed("sfx_volume_db") and not settings.draft().has_value("sfx_volume_db") and settings.value_label("sfx_volume_db").get_theme_color("font_color") == Color("ffffff"), "기본값으로 돌아오면 저장 대상에서 빠지고 흰색")
	_key_shift(title, KEY_LEFT)
	_check(is_equal_approx(_sfx_db(), feel.sfx_volume_db - 5.0), "Shift+←: 효과음 볼륨 -5 dB")
	for i: int in 20:
		_key_shift(title, KEY_LEFT)
	_check(is_equal_approx(_sfx_db(), -40.0) and settings.value_text("sfx_volume_db") == "-40 dB", "최소 -40 dB에서 멈춤")
	# BGM 볼륨·켜기/끄기
	_key(title, KEY_DOWN)
	_key(title, KEY_RIGHT)
	_check(is_equal_approx(_bgm_db(), feel.bgm_volume_db + 1.0) and settings.value_is_changed("bgm_volume_db"), "BGM 볼륨 +1 dB가 버스에 즉시 반영")
	_key(title, KEY_DOWN)
	_check(settings.selected_key() == "bgm_enabled" and not _bgm_muted(), "BGM 줄 선택, 처음엔 켜짐")
	_key(title, KEY_RIGHT)
	_check(_bgm_muted() and settings.value_text("bgm_enabled") == "꺼짐" and settings.value_is_changed("bgm_enabled"), "BGM 끄기: 버스 mute + 노랑")
	_key(title, KEY_LEFT)
	_check(not _bgm_muted() and settings.value_text("bgm_enabled") == "켜짐" and not settings.value_is_changed("bgm_enabled"), "BGM 다시 켜기: 어느 화살표든 반전, 기본값이라 저장 대상에서 빠짐")
	# AUTO
	_key(title, KEY_DOWN)
	_key(title, KEY_RIGHT)
	_check(settings.value_text("auto_stop_on_win_at") == "1,000" and settings.value_is_changed("auto_stop_on_win_at"), "AUTO 큰 당첨 정지: 사용 안 함 → 1,000")
	_key_shift(title, KEY_RIGHT)
	_check(settings.value_text("auto_stop_on_win_at") == "11,000", "Shift: +10,000")
	_key(title, KEY_LEFT)
	_key(title, KEY_LEFT)
	_key_shift(title, KEY_LEFT)
	_check(settings.value_text("auto_stop_on_win_at") == "사용 안 함" and not settings.value_is_changed("auto_stop_on_win_at"), "0 아래로는 내려가지 않고 '사용 안 함'(기본값)")
	_key(title, KEY_DOWN)
	_key(title, KEY_RIGHT)
	_check(settings.value_text("auto_effect_scale") == "×%.1f" % (feel.auto_effect_scale + 0.1), "AUTO 연출 배율 +0.1")
	# 마우스: 화살표 버튼
	settings.arrow_button("sfx_volume_db", 1).pressed.emit()
	_check(settings.selected_key() == "sfx_volume_db" and is_equal_approx(_sfx_db(), -39.0), "마우스: 화살표 클릭이 그 줄을 선택하고 한 단계 바꿈")
	_check(settings.arrow_button("sfx_volume_db", -1).size == Vector2(28, 26) and settings.arrow_button("sfx_volume_db", -1).text == "<" and settings.arrow_button("sfx_volume_db", 1).text == ">", "화살표 버튼 모양")
	# 크레딧 탭: 단계 값 (기본값은 economy.json에서 읽어 비교)
	var eco: Dictionary = GameState.load_economy()
	settings.select_tab(1)
	_key(title, KEY_RIGHT)
	_check(settings.value_text("start_credit") == GameOverOverlay.format_amount(int(eco["start_credit"]) + 100) and settings.value_is_changed("start_credit"), "시작 크레딧 ←/→ 100씩")
	_key_shift(title, KEY_RIGHT)
	_check(settings.value_text("start_credit") == GameOverOverlay.format_amount(int(eco["start_credit"]) + 1100), "시작 크레딧 Shift 1,000씩")
	_key(title, KEY_DOWN)
	_key(title, KEY_LEFT)
	_check(settings.value_text("continue_credit") == GameOverOverlay.format_amount(int(eco["continue_credit"]) - 100), "CONTINUE 코인 ←/→ 100씩")
	for i: int in 3:
		_key_shift(title, KEY_LEFT)
	_check(settings.value_text("continue_credit") == "1", "CONTINUE 코인은 1에서 멈춤")
	_key(title, KEY_DOWN)
	_key(title, KEY_RIGHT)
	_check(settings.value_text("continue_max") == "%d회" % (int(eco["continue_max"]) + 1), "CONTINUE 횟수 +1")
	_key_shift(title, KEY_LEFT)
	_check(settings.value_text("continue_max") == "0회", "CONTINUE 횟수 0에서 멈춤")
	_key(title, KEY_DOWN)
	_check(settings.selected_key() == "coin_amount", "개발 빌드: COIN 지급량 줄")
	_key(title, KEY_RIGHT)
	_check(settings.value_text("coin_amount") == GameOverOverlay.format_amount(int(eco["coin_amount"]) + 10), "COIN 지급량 ←/→ 10씩")
	_key_shift(title, KEY_RIGHT)
	_check(settings.value_text("coin_amount") == GameOverOverlay.format_amount(int(eco["coin_amount"]) + 110), "COIN 지급량 Shift 100씩")
	# 연출 탭: 시간·기준, 중 < 대
	settings.select_tab(2)
	_key(title, KEY_RIGHT)
	_check(settings.value_text("countup_small_sec") == "%.2f초" % (feel.countup_small_sec + 0.1) and settings.value_is_changed("countup_small_sec"), "정산 연출 소: 0.1초씩")
	_key(title, KEY_DOWN)
	_key_shift(title, KEY_RIGHT)
	_check(settings.value_text("countup_mid_sec") == "%.2f초" % (feel.countup_mid_sec + 0.5), "정산 연출 중: Shift 0.5초씩")
	_key(title, KEY_DOWN)
	_key(title, KEY_DOWN)
	_check(settings.selected_key() == "win_mid_ratio", "당첨 중 기준 줄")
	for i: int in 30:
		_key_shift(title, KEY_RIGHT)
	_check(is_equal_approx(float(settings.effective("win_mid_ratio")), float(settings.effective("win_big_ratio")) - 0.1), "당첨 중 기준은 대 기준보다 0.1 작은 값에서 멈춤 (중 < 대)")
	_key(title, KEY_DOWN)
	for i: int in 30:
		_key_shift(title, KEY_LEFT)
	_check(is_equal_approx(float(settings.effective("win_big_ratio")), float(settings.effective("win_mid_ratio")) + 0.1), "당첨 대 기준은 중 기준보다 0.1 큰 값에서 멈춤")
	_check(float(settings.effective("win_mid_ratio")) < float(settings.effective("win_big_ratio")), "어떤 조작으로도 중 ≥ 대가 되지 않음")
	settings.cancel()
	title.free()
	await get_tree().process_frame
	_settings_end()


func _test_settings_save_and_cancel() -> void:
	_settings_begin()
	var feel: FeelConfig = FeelConfig.load_from_file()
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	var settings: SettingsScreen = title.settings_screen()
	var closes: Array[bool] = []
	settings.closed.connect(func(saved: bool) -> void: closes.append(saved))
	var base_start: int = GameState.start_credit
	var base_continue: int = GameState.continue_credit
	# 취소: 파일·GameState·소리가 모두 원래대로
	title.open_settings()
	_key_shift(title, KEY_RIGHT)
	_key(title, KEY_DOWN)
	_key(title, KEY_DOWN)
	_key(title, KEY_RIGHT)
	settings.select_tab(1)
	_key_shift(title, KEY_RIGHT)
	_check(_sfx_db() != feel.sfx_volume_db and _bgm_muted() and settings.draft().values.size() == 3, "준비: 소리·BGM·시작 크레딧을 바꿔 둠")
	_key(title, KEY_ESCAPE)
	_check(closes == [false] and not settings.is_open(), "Esc/취소: 닫힘(saved=false)")
	_check(is_equal_approx(_sfx_db(), feel.sfx_volume_db) and is_equal_approx(_bgm_db(), feel.bgm_volume_db) and not _bgm_muted(), "취소: 소리가 원래대로 복구 (볼륨·BGM mute)")
	_check(not FileAccess.file_exists(SETTINGS_TEST_DIR + "settings.json") and UserSettings.active().is_empty() and GameState.start_credit == base_start, "취소: 파일을 쓰지 않고 지금 설정·시작 크레딧도 그대로")
	title.open_settings()
	_check(settings.draft().is_empty() and settings.tab() == 0, "다시 열면 취소한 값이 남아 있지 않음 (첫 탭, 초안 비어 있음)")
	settings.cancel_button().pressed.emit()
	_check(closes == [false, false], "취소 버튼도 같은 동작")
	# 저장: 바꾼 키만 파일에, GameState 반영, 소리 확정
	var bank: SoundBank = title.sound_bank()
	title.open_settings()
	_key(title, KEY_RIGHT)
	_key(title, KEY_RIGHT)
	_key(title, KEY_DOWN)
	_key(title, KEY_DOWN)
	_key(title, KEY_RIGHT)
	_key(title, KEY_DOWN)
	_key_shift(title, KEY_RIGHT)
	settings.select_tab(1)
	_key_shift(title, KEY_RIGHT)
	_key(title, KEY_DOWN)
	_key(title, KEY_RIGHT)
	settings.select_tab(2)
	_key_shift(title, KEY_RIGHT)
	bank.clear_requests()
	settings.save_button().pressed.emit()
	_check(closes == [false, false, true] and not settings.is_open() and settings.last_save_ok, "저장하고 닫기: 닫힘(saved=true), 파일 쓰기 성공")
	_check(_sound_count(bank, SoundBank.NAME_BUTTON) >= 1, "저장하면 버튼 소리")
	var json: JSON = JSON.new()
	_check(FileAccess.file_exists(SETTINGS_TEST_DIR + "settings.json") and json.parse(FileAccess.get_file_as_string(SETTINGS_TEST_DIR + "settings.json")) == OK, "저장 파일이 생기고 JSON으로 읽힘")
	var values: Dictionary = (json.data as Dictionary)["values"]
	_check(int(json.data["version"]) == 1 and values.has("sfx_volume_db") and values.has("bgm_enabled") and values.has("auto_stop_on_win_at") and values.has("start_credit") and values.has("continue_credit") and values.has("countup_small_sec"), "저장 파일: 바꾼 키만 들어 있음 (%s)" % [values.keys()])
	_check(not values.has("bgm_volume_db") and not values.has("continue_max") and not values.has("win_big_ratio"), "바꾸지 않은 키는 파일에 없음")
	_check(UserSettings.active().get_or("start_credit", 0) == base_start + 1000 and GameState.start_credit == base_start + 1000, "지금 설정과 GameState 시작 크레딧에 반영")
	_check(GameState.continue_credit == base_continue + 100 and GameState._auto.stop_on_win_at == 10000, "CONTINUE 코인·AUTO 정지 기준도 GameState에 반영")
	_check(_bgm_muted() and is_equal_approx(_sfx_db(), feel.sfx_volume_db + 2.0), "저장한 소리 설정이 유지됨 (BGM 꺼짐, 효과음 +2 dB)")
	# 다음 START부터 새 시작 크레딧
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)
	GameState.apply_user_values()
	title.free()
	await get_tree().process_frame
	var started: TitleScreen = (load(TITLE_SCENE_PATH) as PackedScene).instantiate() as TitleScreen
	started.auto_connect = false
	add_child(started)
	started.set_process(false)
	await get_tree().process_frame
	started.press_start()
	_check(GameState.credit == base_start + 1000, "다음 START: 새 시작 크레딧이 지급됨")
	started.free()
	await get_tree().process_frame
	# 다시 열면 저장한 값이 노랑으로 보이고, 값은 설정 파일이 우선
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)
	var again: TitleScreen = _make_title()
	await get_tree().process_frame
	again.open_settings()
	var s2: SettingsScreen = again.settings_screen()
	_check(s2.value_is_changed("sfx_volume_db") and s2.value_label("sfx_volume_db").get_theme_color("font_color") == Color("ffd23a") and s2.value_text("bgm_enabled") == "꺼짐", "다시 열면 저장된 값이 노랑으로 보임")
	_check(not s2.value_is_changed("bgm_volume_db") and s2.value_label("bgm_volume_db").get_theme_color("font_color") == Color("ffffff"), "저장되지 않은 키는 흰색 (feel.json을 고치면 계속 반영됨)")
	s2.cancel()
	again.free()
	await get_tree().process_frame
	_settings_end()


func _test_settings_resets() -> void:
	_settings_begin()
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	var settings: SettingsScreen = title.settings_screen()
	var feel: FeelConfig = FeelConfig.load_from_file()
	HighScore.active().submit(5000, false)
	title.open_settings()
	_key_shift(title, KEY_RIGHT)
	settings.select_tab(1)
	_key(title, KEY_RIGHT)
	# 기본값으로 되돌리기: 두 번 눌러야 실행, 다른 조작이 끼면 확인이 풀림
	settings.defaults_button().pressed.emit()
	_check(settings.defaults_button().text == "한 번 더 누르세요" and settings.draft().values.size() == 2, "기본값으로: 첫 클릭은 확인 글자만 바뀌고 값은 그대로")
	settings.select_tab(0)
	_check(settings.defaults_button().text == "기본값으로" and settings.draft().values.size() == 2, "다른 조작(탭 이동)이 끼면 확인이 풀림")
	settings.defaults_button().pressed.emit()
	_key(title, KEY_DOWN)
	_check(settings.defaults_button().text == "기본값으로", "다른 조작(줄 이동)도 확인을 풂")
	settings.defaults_button().pressed.emit()
	settings.defaults_button().pressed.emit()
	_check(settings.draft().is_empty() and settings.defaults_button().text == "기본값으로" and is_equal_approx(_sfx_db(), feel.sfx_volume_db), "두 번째 클릭: 설정 값 전체가 기본값으로 (소리도 즉시 원래대로)")
	settings.select_tab(1)
	_check(settings.value_text("start_credit") == GameOverOverlay.format_amount(GameState.load_economy()["start_credit"]) and not settings.value_is_changed("start_credit"), "기본값으로 뒤에는 economy.json 값 표시, 노랑 아님")
	_check(HighScore.active().best_peak_credit == 5000, "기본값으로 되돌려도 최고 기록은 그대로")
	_check(not FileAccess.file_exists(SETTINGS_TEST_DIR + "settings.json"), "기본값으로 눌러도 저장 전에는 파일이 바뀌지 않음")
	# 이미 저장된 설정을 기본값으로 되돌리고 저장 → 파일은 빈 설정
	settings.cancel()
	var saved: UserSettings = UserSettings.new()
	saved.set_value("start_credit", 9000)
	UserSettings.commit(saved)
	title.open_settings()
	_check(settings.value_is_changed("sfx_volume_db") == false and settings.draft().get_or("start_credit", 0) == 9000, "저장된 설정을 읽어 초안으로")
	settings.press_defaults()
	settings.press_defaults()
	settings.save()
	_check(UserSettings.load_from(SETTINGS_TEST_DIR + "settings.json").is_empty() and UserSettings.active().is_empty() and GameState.start_credit == GameState.load_economy()["start_credit"], "기본값으로 + 저장: 파일이 빈 설정, GameState도 economy.json 값으로 복귀")
	# 최고 기록 초기화: 두 번 눌러야 실행, Space로도 가능, 저장 버튼과 무관하게 바로 지워짐
	title.open_settings()
	settings.select_tab(1)
	_check(settings.value_text("best") == "5,000", "최고 기록 표시 5,000")
	var action: Button = settings.action_button()
	_check(action.text == "초기화", "최고 기록 초기화 버튼 글자")
	action.pressed.emit()
	_check(action.text == "한 번 더 누르면 초기화" and HighScore.active().best_peak_credit == 5000 and settings.selected_key() == "best_reset", "첫 클릭: 확인 글자만 바뀌고 기록은 그대로 (그 줄이 선택됨)")
	_key(title, KEY_UP)
	_check(action.text == "초기화" and HighScore.active().best_peak_credit == 5000, "다른 조작이 끼면 확인이 풀림")
	_key(title, KEY_DOWN)
	_key(title, KEY_SPACE)
	_check(action.text == "한 번 더 누르면 초기화", "Space로도 확인 단계로")
	_key(title, KEY_SPACE)
	_check(HighScore.active().best_peak_credit == 0 and settings.value_text("best") == "기록 없음" and action.text == "초기화", "두 번째에 최고 기록 초기화, 표시도 '기록 없음'")
	_check(HighScore.load_from(SETTINGS_TEST_DIR + "highscore.json").best_peak_credit == 0, "최고 기록 파일에도 반영")
	settings.cancel()
	_check(title.best_label().visible == false, "닫으면 시작 화면 BEST 표시도 사라짐")
	title.free()
	await get_tree().process_frame
	_settings_end()


## 게임 화면이 설정을 받는지: 연출 키 덮어쓰기, F6 뒤에도 유지, BGM 끄기, 창 닫기 기록, 꺼져 있으면 무시
func _test_settings_applied_in_game() -> void:
	_settings_begin()
	var feel: FeelConfig = FeelConfig.load_from_file()
	var user: UserSettings = UserSettings.new()
	user.set_value("countup_big_sec", 4.0)
	user.set_value("win_mid_ratio", 3.0)
	user.set_value("bgm_volume_db", -20.0)
	user.set_value("bgm_enabled", false)
	UserSettings.commit(user)
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)
	var main: Control = (load(MAIN_SCENE_FILE) as PackedScene).instantiate()
	main.settle_presentation = false
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	var pending: FeelConfig = main.pending_feel()
	_check(pending.countup_big_sec == 4.0 and pending.win_mid_ratio == 3.0 and pending.bgm_volume_db == -20.0, "main: 설정의 연출 키가 feel.json 값 위에 덮어써짐")
	_check(pending.countup_small_sec == feel.countup_small_sec and pending.win_big_ratio == feel.win_big_ratio and pending.sfx_volume_db == feel.sfx_volume_db, "main: 안 바꾼 키는 feel.json 값 그대로")
	_check(_bgm_muted(), "main: BGM 끄기 설정이 버스 mute로 반영")
	_check(main.reload_feel() and main.pending_feel().countup_big_sec == 4.0 and main.pending_feel().win_mid_ratio == 3.0 and main.pending_feel().bgm_volume_db == -20.0, "F6 재로딩 뒤에도 설정 키의 덮어쓰기가 유지됨")
	_check(main.pending_feel().countup_small_sec == feel.countup_small_sec, "F6 재로딩: 안 바꾼 키는 계속 feel.json을 따름")
	# 창 닫기: 판의 최고 크레딧을 기록 (더 클 때만, 테스트 판 제외)
	GameState.run_peak_credit = 9000
	GameState.run_tainted = false
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(HighScore.active().best_peak_credit == 9000 and HighScore.load_from(SETTINGS_TEST_DIR + "highscore.json").best_peak_credit == 9000, "창 닫기: 최고 크레딧 9,000을 기록 (파일에도)")
	GameState.run_peak_credit = 8000
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(HighScore.active().best_peak_credit == 9000, "창 닫기: 더 작으면 기록하지 않음")
	GameState.run_peak_credit = 99999
	GameState.run_tainted = true
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(HighScore.active().best_peak_credit == 9000, "창 닫기: 테스트 판(run_tainted)은 기록하지 않음")
	GameState.run_tainted = false
	main.free()
	await get_tree().process_frame
	SettingsScreen.apply_bgm_mute(true)
	# 설정 사용이 꺼져 있으면(헤드리스 테스트) 파일이 있어도 무시
	UserSettings.configure(false)
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)
	var plain: Control = (load(MAIN_SCENE_FILE) as PackedScene).instantiate()
	plain.settle_presentation = false
	add_child(plain)
	plain.set_process(false)
	await get_tree().process_frame
	_check(plain.pending_feel().countup_big_sec == feel.countup_big_sec and plain.pending_feel().win_mid_ratio == feel.win_mid_ratio and not _bgm_muted(), "설정 사용이 꺼져 있으면 저장 파일이 있어도 feel.json 값 그대로 (테스트 격리)")
	plain.free()
	await get_tree().process_frame
	_settings_end()


func _test_settings_dev_and_best() -> void:
	_settings_begin()
	# 시작 화면 BEST 표시: 기록이 있을 때만, 작은 글자로 EXIT 아래
	var empty: TitleScreen = _make_title()
	await get_tree().process_frame
	_check(not empty.best_label().visible, "최고 기록이 없으면 BEST 표시가 숨겨짐")
	empty.free()
	await get_tree().process_frame
	HighScore.active().submit(12345, false)
	var title: TitleScreen = _make_title()
	await get_tree().process_frame
	var best: Label = title.best_label()
	_check(best.visible and best.text == "BEST 12,345", "최고 기록이 있으면 시작 화면에 BEST 12,345")
	_check(best.position == Vector2(57, 324) and best.size == Vector2(526, 20) and best.mouse_filter == Control.MOUSE_FILTER_IGNORE, "BEST 라벨 위치·크기 (큰 패널 안, EXIT 버튼 아래)")
	_check(best.position.y >= title.exit_button().position.y + title.exit_button().size.y and best.position.y + best.size.y <= 354, "BEST는 EXIT 버튼과 겹치지 않고 큰 패널 안")
	_check(title.logo().position == Vector2(140, 30) and title.start_button().position == Vector2(240, 222) and title.exit_button().position == Vector2(240, 276), "기존 시작 화면 요소 위치 불변 (로고·START·EXIT)")
	title.open_settings()
	title.settings_screen().select_tab(1)
	_check(title.settings_screen().value_text("best") == "12,345", "설정 화면의 최고 기록 줄도 12,345")
	title.settings_screen().cancel()
	title.free()
	await get_tree().process_frame
	# GAME OVER가 오면 최고 기록 (일반 판만)
	UserSettings.configure(true, SETTINGS_TEST_DIR)
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), TEST_SEED)
	GameState.new_game()
	HighScore.active().reset()
	for i: int in 400:
		if GameState.is_game_over():
			break
		GameState.credit = 8
		GameState.bet = 8
		GameState.play_spin()
	_check(GameState.is_game_over() and HighScore.active().best_peak_credit == GameState.run_peak_credit and GameState.run_peak_credit >= GameState.start_credit, "GAME OVER가 오면 그 판의 최고 크레딧이 최고 기록으로 남음")
	_check(HighScore.load_from(SETTINGS_TEST_DIR + "highscore.json").best_peak_credit == GameState.run_peak_credit, "최고 기록 파일에도 저장됨")
	_settings_end()

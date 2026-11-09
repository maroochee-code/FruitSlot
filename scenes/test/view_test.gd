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
	# 오토로드 상태를 처음 상태로 되돌린 뒤 시작한다.
	GameState.initialize(GameState.get_balance(), GameState.load_economy(), TEST_SEED)
	_rng.seed = TEST_SEED
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	add_child(main)
	# 시간은 테스트가 main.advance()로 직접 흘린다.
	main.set_process(false)
	await get_tree().process_frame
	_test_initial_screen(main)
	_test_layout(main)
	_test_board_layout(main)
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
		_check(not panel.is_flashing(symbol) and panel.count_color(symbol) == FeverPanel.COUNT_COLOR, "남은 1회: %s 꺼짐일 때 평소 색" % symbol)
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
				if texts["title"] != "POOL GET!" or texts["name"] != "POOL" or texts["bonus"] != "POOL +%d" % result.pool_won:
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

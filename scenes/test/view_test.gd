extends Node
## 화면 검증: main 씬을 띄우고 키보드·START를 여러 번 눌러서
## 화면 칸, 크레딧/WIN/BET/POOL/피버 표시, 라인 라벨, 당첨 선이 로직 결과와 매번 같은지 확인한다.

@export var spin_count: int = 300
@export var quit_when_headless: bool = true

const FULL_BET: int = 8
const TEST_SEED: int = 12345

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# 오토로드 상태를 처음 상태로 되돌린 뒤 시작한다.
	GameState.initialize(GameState.get_balance(), GameState.load_economy(), TEST_SEED)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	_test_initial_screen(main)
	_test_paytable(main)
	_test_keyboard(main)
	_test_max_and_cancel(main)
	await _test_spins(main)
	_test_labels_follow_bet(main)
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
	_check(GameState.credit != before or GameState.last_win == 0, "스페이스 = START (크레딧 변화)")
	_check(main.grid_matches_logic(), "스페이스 스핀 후 화면=로직")
	_press(main, KEY_ENTER)
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
		if result == null or not main.grid_matches_logic():
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
	# 크레딧이 모자라 베팅이 내려간 상황의 안내 문구
	GameState.credit = 8
	while GameState.bet != FULL_BET:
		GameState.raise_bet()
	for tries: int in 200:
		GameState.credit = 8
		GameState.bet = FULL_BET
		var lost: SpinResult = main.do_spin()
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
	var rows: PackedStringArray = _box(main, "FeverBox").value_text().split("\n")
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

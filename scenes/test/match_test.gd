extends Node
## 일치 검증(5-C): 같은 시드로 화면(main 씬)을 통해 스핀을 대량으로 돌리고, 로직 단독 시뮬레이션과 비교한다.
## 비교 항목: 피버 발동 횟수, 풀 획득 횟수, 총 지급액(+ 스핀마다 CREDIT·WIN·POOL·피버 카운터).
## 입력은 스핀마다 무작위로 섞는다: 릴 정지(자동 / 회전 중 START / 키 1·2·3) × 피버 연출(끝까지 재생 / 스페이스로 건너뜀 / START로 건너뜀).
## 시간은 main.advance()로 테스트가 직접 흘린다. 판정 값은 화면에 표시된 글자와 오버레이가 받은 단계에서 읽는다.

@export var spin_count: int = 10000
@export var quit_when_headless: bool = true

const FULL_BET: int = 8
const MATCH_SEED: int = 20261109
## 한 프레임 길이. 1만 회를 현실적인 시간에 돌리려고 크게 잡았다 (view_test도 0.2초짜리 튀는 프레임을 쓴다)
const FRAME_DT: float = 0.2
const START_CREDIT: int = 1000000000
const MAX_SPIN_FRAMES: int = 6000
const QUICK_STOP_AT_SEC: float = 0.45
const STOP_KEYS_AT_SEC: float = 0.5
const STOP_KEYS_GAP_SEC: float = 0.2
## 건너뛰기 잠금이 풀린 뒤 이만큼 더 기다렸다가 건너뛴다
const SKIP_EXTRA_SEC: float = 0.05
const STOP_MODES: int = 3
const SKIP_MODES: int = 3
const MISMATCH_PRINT_MAX: int = 8
## 시험용 데이터: 릴 스트립에서 이 간격마다 SEVEN으로 바꿔 세븐 피버·풀 획득이 자주 나오게 한다
const BOOST_SEVEN_EVERY: int = 4
const BOOST_SEVEN_OFFSET: int = 2

var _passed: int = 0
var _failed: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	UserSettings.configure(false)
	_rng.seed = MATCH_SEED
	# 사용법: godot --headless res://scenes/test/match_test.tscn -- --spins=2000 (스핀 수 줄여 빨리 돌려 볼 때)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--spins="):
			spin_count = int(arg.get_slice("=", 1))
	var real: BalanceData = BalanceData.load_from_file()
	await _run_case("실제 balance.json", real, false)
	await _run_case("시험용(세븐 많이·피버 초기값 낮춤)", _boosted_data(), true)
	print("==================== MATCH TEST: %d 통과 / %d 실패 ====================" % [_passed, _failed])
	GameState.initialize(BalanceData.load_from_file(), GameState.load_economy(), MATCH_SEED)
	if quit_when_headless and DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", label)


## 파일은 건드리지 않고, 메모리에서만 세븐을 늘리고 피버 초기값을 낮춘 밸런스를 만든다 (테스트 전용).
func _boosted_data() -> BalanceData:
	var json: JSON = JSON.new()
	json.parse(FileAccess.get_file_as_string("res://data/balance.json"))
	var raw: Dictionary = json.data
	for strip: Variant in raw["reels"]:
		var cells: Array = strip
		for i: int in cells.size():
			if i % BOOST_SEVEN_EVERY == BOOST_SEVEN_OFFSET:
				cells[i] = "SEVEN"
	var counts: Dictionary = { "CHERRY": 3, "GRAPE": 2, "BELL": 2, "SEVEN": 1 }
	for target: Variant in raw["fever"]["targets"]:
		var entry: Dictionary = target
		entry["initial_count"] = counts[entry["symbol"]]
	return BalanceData.from_dict(raw)


## 로직 단독 시뮬레이션: 화면 없이 같은 시드로 spin_count번 돌린 결과 목록
func _reference(data: BalanceData) -> Array[SpinResult]:
	var logic: SlotLogic = SlotLogic.new(data, MATCH_SEED)
	var results: Array[SpinResult] = []
	for i: int in spin_count:
		results.append(logic.spin(FULL_BET))
	return results


## require_events가 true면 피버 연출(재생·건너뜀 모두)과 풀 획득이 실제로 나와야 한다 (실제 밸런스는 풀 획득이 드물어 요구하지 않음)
func _run_case(label: String, data: BalanceData, require_events: bool) -> void:
	var started_ms: int = Time.get_ticks_msec()
	var reference: Array[SpinResult] = _reference(data)
	var stats: SimStats = SimStats.new(data)
	for result: SpinResult in reference:
		stats.record(result)
	var ref_fever_total: int = 0
	for symbol: String in data.fever_symbols:
		ref_fever_total += stats.fever_counts[symbol]
	var main: Control = await _make_screen(data)
	var overlay: FeverOverlay = main.get_node("FeverOverlay")
	var screen: Dictionary = { "fever_steps": 0, "pool_steps": 0, "fever_amount": 0, "pool_amount": 0 }
	overlay.step_started.connect(_on_step_started.bind(overlay, screen))
	var mismatches: int = 0
	var natural_overlays: int = 0
	var skipped_overlays: int = 0
	var stuck: int = 0
	var expected_credit: int = START_CREDIT
	for n: int in spin_count:
		var ref: SpinResult = reference[n]
		var before: Dictionary = screen.duplicate()
		var outcome: Dictionary = _drive_spin(main, overlay)
		if outcome["stuck"]:
			stuck += 1
			break
		expected_credit += ref.total_payout() - FULL_BET
		var problem: String = _spin_problem(main, data, ref, outcome["result"], expected_credit, before, screen)
		if not problem.is_empty():
			mismatches += 1
			if mismatches <= MISMATCH_PRINT_MAX:
				print("  불일치 스핀 %d: %s" % [n, problem])
		if outcome["overlay_played"]:
			if outcome["skipped"]:
				skipped_overlays += 1
			else:
				natural_overlays += 1
		if n % 2000 == 1999:
			await get_tree().process_frame
	var screen_paid: int = int(_box(main, "CreditBox").value_text()) - START_CREDIT + spin_count * FULL_BET
	var ref_paid: int = stats.line_payout + stats.fever_payout + stats.pool_payout
	print("[%s] 스핀 %d회 / 피버 발동 %d / 풀 획득 %d / 총 지급 %d / 연출 재생 %d·건너뜀 %d / %.1f초" % [label, spin_count, ref_fever_total, stats.pool_awards, ref_paid, natural_overlays, skipped_overlays, (Time.get_ticks_msec() - started_ms) / 1000.0])
	_check(stuck == 0, "[%s] 스핀이 끝나지 않고 멈춘 적 없음" % label)
	_check(mismatches == 0, "[%s] 스핀마다 CREDIT·WIN·POOL·피버 카운터·정지 위치가 로직과 같음 (불일치 %d회)" % [label, mismatches])
	_check(screen["fever_steps"] == ref_fever_total, "[%s] 화면이 보여 준 피버 발동 횟수 %d == 로직 %d" % [label, screen["fever_steps"], ref_fever_total])
	_check(screen["pool_steps"] == stats.pool_awards, "[%s] 화면이 보여 준 풀 획득 횟수 %d == 로직 %d" % [label, screen["pool_steps"], stats.pool_awards])
	_check(screen["fever_amount"] == stats.fever_payout, "[%s] 화면이 보여 준 피버 보너스 합 %d == 로직 %d" % [label, screen["fever_amount"], stats.fever_payout])
	_check(screen["pool_amount"] == stats.pool_payout, "[%s] 화면이 보여 준 풀 금액 합 %d == 로직 %d" % [label, screen["pool_amount"], stats.pool_payout])
	_check(screen_paid == ref_paid, "[%s] 화면 크레딧으로 계산한 총 지급 %d == 로직 %d" % [label, screen_paid, ref_paid])
	_check(not require_events or (natural_overlays > 0 and skipped_overlays > 0), "[%s] 끝까지 재생과 건너뛰기가 모두 섞여 있음 (재생 %d / 건너뜀 %d)" % [label, natural_overlays, skipped_overlays])
	_check(not require_events or stats.pool_awards > 0, "[%s] 풀 획득이 한 번 이상 나와 비교가 의미 있음 (%d회)" % [label, stats.pool_awards])
	main.free()
	await get_tree().process_frame


func _make_screen(data: BalanceData) -> Control:
	GameState.initialize(data, GameState.load_economy(), MATCH_SEED)
	GameState.credit = START_CREDIT
	while GameState.bet != FULL_BET:
		GameState.raise_bet()
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.settle_presentation = false
	add_child(main)
	main.set_process(false)
	await get_tree().process_frame
	GameState.refresh()
	return main


## 오버레이가 단계를 시작할 때마다 화면이 받은 내용을 센다. 연출을 건너뛰어도 단계 시작은 모두 알려진다.
func _on_step_started(index: int, overlay: FeverOverlay, screen: Dictionary) -> void:
	var step: Dictionary = overlay.step_at(index)
	if step["kind"] == FeverOverlay.KIND_POOL:
		screen["pool_steps"] += 1
		screen["pool_amount"] += step["bonus"]
	else:
		screen["fever_steps"] += 1
		screen["fever_amount"] += step["bonus"]


## START부터 정산까지 입력을 무작위로 섞어 진행한다.
func _drive_spin(main: Control, overlay: FeverOverlay) -> Dictionary:
	var stop_mode: int = _rng.randi_range(0, STOP_MODES - 1)
	var skip_mode: int = _rng.randi_range(0, SKIP_MODES - 1)
	var key_order: Array[int] = [0, 1, 2]
	key_order.shuffle()
	var outcome: Dictionary = { "result": main.do_spin(), "stuck": false, "overlay_played": false, "skipped": false }
	var elapsed: float = 0.0
	var frames: int = 0
	var quick_done: bool = false
	var keys_done: int = 0
	while GameState.spinning:
		if frames >= MAX_SPIN_FRAMES:
			outcome["stuck"] = true
			return outcome
		main.advance(FRAME_DT)
		elapsed += FRAME_DT
		frames += 1
		if main.fever_playing():
			outcome["overlay_played"] = true
			if skip_mode != 0 and overlay.elapsed() >= main.feel().fever_skip_lock_sec + SKIP_EXTRA_SEC:
				_skip(main, skip_mode)
				outcome["skipped"] = true
		elif stop_mode == 1 and not quick_done and elapsed >= QUICK_STOP_AT_SEC:
			quick_done = true
			main.do_spin()
		elif stop_mode == 2 and keys_done < 3 and elapsed >= STOP_KEYS_AT_SEC + keys_done * STOP_KEYS_GAP_SEC:
			main.press_stop(key_order[keys_done])
			keys_done += 1
	return outcome


## 연출 건너뛰기: 1 = 스페이스 키, 2 = START 버튼
func _skip(main: Control, skip_mode: int) -> void:
	if skip_mode == 1:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_SPACE
		event.pressed = true
		main._unhandled_key_input(event)
	else:
		(main.get_node("StartButton") as Button).pressed.emit()


## 정산 뒤 화면이 로직 결과와 같은지 본다. 다르면 이유 글, 같으면 빈 글.
func _spin_problem(main: Control, data: BalanceData, ref: SpinResult, result: SpinResult, expected_credit: int, before: Dictionary, screen: Dictionary) -> String:
	if result == null:
		return "START가 결과를 돌려주지 않음"
	if result.stops != ref.stops:
		return "정지 위치 %s != 로직 %s" % [result.stops, ref.stops]
	if _box(main, "CreditBox").value_text() != str(expected_credit):
		return "CREDIT %s != 기대 %d" % [_box(main, "CreditBox").value_text(), expected_credit]
	if _box(main, "WinBox").value_text() != str(ref.total_payout()):
		return "WIN %s != 로직 %d" % [_box(main, "WinBox").value_text(), ref.total_payout()]
	if _box(main, "PoolBox").value_text() != str(ref.pool_after):
		return "POOL %s != 로직 %d" % [_box(main, "PoolBox").value_text(), ref.pool_after]
	var rows: PackedStringArray = PackedStringArray()
	for symbol: String in data.fever_symbols:
		rows.append("%s ×%d" % [data.symbol_names[symbol], ref.fever_counts_after[symbol]])
	var shown: String = (main.get_node("FeverBox") as FeverPanel).value_text()
	if shown != "\n".join(rows):
		return "피버 카운터 %s != 로직 %s" % [shown.replace("\n", " "), "\n".join(rows).replace("\n", " ")]
	var fever_now: int = screen["fever_steps"] - before["fever_steps"]
	if fever_now != ref.fever_triggers.size():
		return "이번 스핀 피버 단계 %d != 로직 %d" % [fever_now, ref.fever_triggers.size()]
	var pool_now: int = screen["pool_steps"] - before["pool_steps"]
	var pool_want: int = 1 if ref.pool_won > 0 else 0
	if pool_now != pool_want:
		return "이번 스핀 풀 단계 %d != 로직 %d" % [pool_now, pool_want]
	if (main.get_node("FeverOverlay") as Control).visible or GameState.spinning:
		return "정산 뒤에도 오버레이가 보이거나 스핀 중 상태"
	return ""


func _box(main: Control, node_name: String) -> InfoBox:
	return main.get_node(node_name) as InfoBox

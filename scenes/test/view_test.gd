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
	await _test_auto_view()
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
	var feel: FeelConfig = FeelConfig.load_from_file()
	_check(feel.bgm_volume_db == -12.0 and feel.bgm_to_fever_sec == 0.3 and feel.bgm_to_main_sec == 1.0 and feel.bgm_loop_trim_sec == 2.0 and feel.bgm_loop_fade_sec == 1.0, "feel.json 새 키 5개: -12 / 0.3 / 1.0 / 2.0 / 1.0")
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
	_check(files_ok and SoundBank.ALL_NAMES.size() == 14, "효과음 파일 14개가 모두 있음 (assets/sounds/*.wav)")
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
	var feel: FeelConfig = FeelConfig.load_from_file()
	_check(feel.win_mid_ratio == 2.0 and feel.win_big_ratio == 10.0 and feel.sfx_volume_db == 0.0, "feel.json 새 키: win_mid_ratio 2 / win_big_ratio 10 / sfx_volume_db 0")
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

extends Node
## 6-E 미리보기 씬: 진짜 메인 화면 위에 피버·풀 오버레이를 가짜 단계로 재생해서 눈으로 확인한다.
## balance.json·게임 결과·크레딧은 건드리지 않는다 (이 씬의 오버레이는 정산과 연결되어 있지 않다).
## 실행: scenes/test/overlay_preview.tscn 을 열고 F6(현재 씬 실행)
## 키: R 처음부터(체리→포도→벨→세븐→풀) / 1~5 그 단계만 / A 배너 색 변형 바꾸기 / B 배경 프레임 바꾸기
##     M 움직임 미리보기 켜기·끄기(배경 프레임·배너 색을 번갈아 보여 줌, 6-F에서 쓸 속도의 예시) / SPACE 건너뛰기 / L 반복 켜기·끄기

const STEP_SEC: float = 3.0
const GAP_SEC: float = 0.3
const POOL_SEC: float = 4.0
## 미리보기용 가짜 금액 (실제 결과와 무관)
const SAMPLE_BONUS: Dictionary = { "CHERRY": 88, "GRAPE": 240, "BELL": 400, "SEVEN": 800 }
const SAMPLE_POOL: int = 1523
const PREVIEW_SYMBOLS: PackedStringArray = ["CHERRY", "GRAPE", "BELL", "SEVEN"]
## 움직임 미리보기 속도 (초). 확정값이 아니라 보기 위한 예시다.
const BG_FRAME_SEC: float = 0.25
const BANNER_FLASH_SEC: float = 0.15
const REPLAY_WAIT_SEC: float = 0.8
const LEGEND_TEXT: String = "R 처음부터  1~5 단계  A 배너색  B 배경  M 움직임  L 반복  SPACE 건너뛰기"

var _overlay: FeverOverlay
var _steps: Array[Dictionary] = []
var _all_steps: Array[Dictionary] = []
var _motion: bool = true
var _loop: bool = true
var _clock: float = 0.0
var _replay_left: float = -1.0
var _only_one: bool = false


func _ready() -> void:
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	main.set_process(false)
	_all_steps = _make_steps()
	_overlay = FeverOverlay.new()
	add_child(_overlay)
	_overlay.finished.connect(_on_finished)
	var legend: Label = Label.new()
	legend.text = LEGEND_TEXT
	legend.position = Vector2(8, 4)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.add_theme_color_override("font_color", Color("8a8aa0"))
	legend.z_index = 10
	add_child(legend)
	print("[overlay_preview] ", LEGEND_TEXT)
	_play(_all_steps, false)


func _process(delta: float) -> void:
	_overlay.advance(delta)
	if _motion and _overlay.is_playing():
		_clock += delta
		_overlay.set_bg_frame(int(_clock / BG_FRAME_SEC))
		_overlay.set_banner_variant(int(_clock / BANNER_FLASH_SEC))
	if _replay_left >= 0.0:
		_replay_left -= delta
		if _replay_left < 0.0:
			_play(_steps, _only_one)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_R:
			_play(_all_steps, false)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			var index: int = key.keycode - KEY_1
			_play([_all_steps[index]] as Array[Dictionary], true)
		KEY_A:
			_motion = false
			_overlay.set_banner_variant(_overlay._banner_variant + 1)
		KEY_B:
			_motion = false
			_overlay.set_bg_frame(_overlay._bg_frame + 1)
		KEY_M:
			_motion = not _motion
		KEY_L:
			_loop = not _loop
		KEY_SPACE:
			_overlay.skip()


func _make_steps() -> Array[Dictionary]:
	var names: Dictionary = GameState.get_balance().symbol_names
	var steps: Array[Dictionary] = []
	for symbol: String in PREVIEW_SYMBOLS:
		steps.append({ "kind": FeverOverlay.KIND_FEVER, "symbol": symbol, "name": names.get(symbol, symbol), "bonus": SAMPLE_BONUS[symbol] })
	steps.append({ "kind": FeverOverlay.KIND_POOL, "symbol": "", "name": FeverOverlay.POOL_NAME_TEXT, "bonus": SAMPLE_POOL })
	return steps


func _play(steps: Array[Dictionary], only_one: bool) -> void:
	_steps = steps
	_only_one = only_one
	_replay_left = -1.0
	_clock = 0.0
	_overlay.play(steps, STEP_SEC, GAP_SEC, 0.0, POOL_SEC)


func _on_finished(_skipped: bool) -> void:
	if _loop:
		_replay_left = REPLAY_WAIT_SEC

class_name FeverOverlay
extends Control
## 피버 발동 연출: 화면 전체를 덮는 오버레이. 단계(step)를 차례로 보여 준다.
## 한 단계 = 심볼 하나의 "FEVER! / 심볼 이름 / BONUS +금액". 단계 사이에는 빈 간격이 있다.
## 이 클래스는 보여주기만 한다. 금액·순서는 확정된 SpinResult에서 그대로 받고, 건너뛰어도 숫자는 달라지지 않는다.
## 5-C에서 풀 획득 단계(kind = KIND_POOL)가 같은 목록 끝에 붙는다.

signal step_started(index: int)
signal step_finished(index: int)
## 모든 단계가 끝났거나 건너뛰었을 때. skipped가 true면 건너뜀.
signal finished(skipped: bool)

const KIND_FEVER: StringName = &"fever"
const KIND_POOL: StringName = &"pool"

const SCREEN_SIZE: Vector2 = Vector2(640, 480)
const DIM_COLOR: Color = Color(0.0, 0.0, 0.05, 0.88)
const TITLE_TEXT: String = "FEVER!"
const TITLE_Y: float = 70.0
const TITLE_FONT_SIZE: int = 80
const TITLE_COLOR_A: Color = Color("FFD700")
const TITLE_COLOR_B: Color = Color("FF4040")
## FEVER! 글자 색이 바뀌는 간격(초)
const TITLE_FLASH_SEC: float = 0.15
const BANNER_RECT: Rect2 = Rect2(170, 180, 300, 70)
const NAME_FONT_SIZE: int = 44
const BONUS_Y: float = 275.0
const BONUS_FONT_SIZE: int = 48
const BONUS_COLOR: Color = Color("FFD700")
const COUNT_FONT_SIZE: int = 14
const COUNT_COLOR: Color = Color("8A8AA0")
const HINT_TEXT: String = "SPACE: 건너뛰기"
const HINT_FONT_SIZE: int = 12
const HINT_Y: float = 440.0

var _steps: Array[Dictionary] = []
var _step_sec: float = 0.0
var _gap_sec: float = 0.0
var _skip_lock_sec: float = 0.0
var _elapsed: float = 0.0
var _playing: bool = false
## 지금까지 시작/끝난 단계 수
var _started_count: int = 0
var _finished_count: int = 0

var _title: Label = Label.new()
var _banner: Panel = Panel.new()
var _banner_box: StyleBoxFlat = StyleBoxFlat.new()
var _name: Label = Label.new()
var _bonus: Label = Label.new()
var _counter: Label = Label.new()
var _hint: Label = Label.new()


func _init() -> void:
	name = "FeverOverlay"
	position = Vector2.ZERO
	size = SCREEN_SIZE
	# 아래 화면의 마우스 입력을 막는다 (버튼 클릭 방지)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim: ColorRect = ColorRect.new()
	dim.color = DIM_COLOR
	dim.size = SCREEN_SIZE
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_setup_label(_title, Rect2(0, TITLE_Y, SCREEN_SIZE.x, 100), TITLE_FONT_SIZE, TITLE_COLOR_A)
	_title.text = TITLE_TEXT
	_banner.position = BANNER_RECT.position
	_banner.size = BANNER_RECT.size
	_banner.add_theme_stylebox_override("panel", _banner_box)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_name.size = BANNER_RECT.size
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_banner.add_child(_name)
	_setup_label(_bonus, Rect2(0, BONUS_Y, SCREEN_SIZE.x, 70), BONUS_FONT_SIZE, BONUS_COLOR)
	_setup_label(_counter, Rect2(0, 8, SCREEN_SIZE.x - 12, 24), COUNT_FONT_SIZE, COUNT_COLOR)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_setup_label(_hint, Rect2(0, HINT_Y, SCREEN_SIZE.x, 24), HINT_FONT_SIZE, COUNT_COLOR)
	_hint.text = HINT_TEXT
	_show_step_content(false)


## 확정된 결과에서 보여 줄 단계 목록을 만든다. 순서는 balance.json 피버 대상 순서(체리, 포도, 벨, 세븐).
## 피버가 없으면 빈 목록. (건너뛰기·연출과 상관없이 결과는 이 목록이 그대로 반영한다.)
static func build_steps(result: SpinResult, data: BalanceData) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for symbol: String in data.fever_symbols:
		if result.fever_triggers.has(symbol):
			steps.append({
				"kind": KIND_FEVER,
				"symbol": symbol,
				"name": data.symbol_names.get(symbol, symbol),
				"bonus": result.fever_bonuses[symbol],
			})
	# 5-C: 세븐 피버로 풀을 획득했으면 여기에 KIND_POOL 단계를 붙인다 (result.pool_won). 지금은 자리만 비워 둔다.
	return steps


## 한 단계가 차지하는 시간의 합 (단계 사이 간격 포함, 마지막 뒤 간격 없음)
static func total_seconds(steps_total: int, step_sec: float, gap_sec: float) -> float:
	if steps_total <= 0:
		return 0.0
	return steps_total * step_sec + (steps_total - 1) * gap_sec


## 연출 시작. 시간 값은 이번 스핀의 손맛 설정에서 받는다 (연출 중에는 바뀌지 않는다).
func play(steps: Array[Dictionary], step_sec: float, gap_sec: float, skip_lock_sec: float) -> void:
	if steps.is_empty():
		return
	_steps = steps
	_step_sec = step_sec
	_gap_sec = gap_sec
	_skip_lock_sec = skip_lock_sec
	_elapsed = 0.0
	_started_count = 0
	_finished_count = 0
	_playing = true
	visible = true
	_update()


func is_playing() -> bool:
	return _playing


func step_count() -> int:
	return _steps.size()


## 지금 단계 내용이 화면에 보이는 중인가 (단계 사이 간격에서는 false)
func is_showing_step() -> bool:
	return _playing and _step_index_at(_elapsed) >= 0


## 지금 보이는 단계 번호 (간격이면 -1)
func current_step() -> int:
	return _step_index_at(_elapsed) if _playing else -1


## 화면에 보이는 글자: { title, name, bonus }
func shown_texts() -> Dictionary:
	return { "title": _title.text, "name": _name.text, "bonus": _bonus.text }


func elapsed() -> float:
	return _elapsed


func advance(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	_update()


## 연출만 건너뛴다. 뜬 직후 skip_lock_sec 동안은 무시한다. 건너뛰었으면 true.
func skip() -> bool:
	if not _playing or _elapsed < _skip_lock_sec:
		return false
	_finish(true)
	return true


func _update() -> void:
	var total: float = total_seconds(_steps.size(), _step_sec, _gap_sec)
	var index: int = _step_index_at(_elapsed)
	# 지나간 단계의 시작·끝을 빠짐없이 알린다 (프레임이 튀어도 순서대로)
	while _started_count < _steps.size() and _started_count <= _passed_index():
		step_started.emit(_started_count)
		_started_count += 1
	while _finished_count < _started_count and _step_end(_finished_count) <= _elapsed:
		step_finished.emit(_finished_count)
		_finished_count += 1
	if _elapsed >= total:
		_finish(false)
		return
	_show_step_content(index >= 0)
	if index >= 0:
		_apply_step(index)
	_title.add_theme_color_override("font_color", TITLE_COLOR_A if int(_elapsed / TITLE_FLASH_SEC) % 2 == 0 else TITLE_COLOR_B)


func _finish(skipped: bool) -> void:
	# 건너뛰어도 아직 안 알린 단계의 시작·끝을 모두 알린다 (숫자 반영이 연출 여부와 무관하도록)
	while _started_count < _steps.size():
		step_started.emit(_started_count)
		_started_count += 1
	while _finished_count < _steps.size():
		step_finished.emit(_finished_count)
		_finished_count += 1
	_playing = false
	visible = false
	_show_step_content(false)
	finished.emit(skipped)


## 시각 t에 보여야 할 단계 번호. 간격이거나 범위 밖이면 -1.
func _step_index_at(t: float) -> int:
	var stride: float = _step_sec + _gap_sec
	if stride <= 0.0 or _steps.is_empty():
		return -1
	var index: int = int(t / stride)
	if index >= _steps.size():
		return -1
	return index if t - index * stride < _step_sec else -1


## 지금 시각까지 시작된 마지막 단계 번호 (간격 중이면 직전 단계)
func _passed_index() -> int:
	var stride: float = _step_sec + _gap_sec
	if stride <= 0.0:
		return _steps.size() - 1
	return mini(int(_elapsed / stride), _steps.size() - 1)


func _step_end(index: int) -> float:
	return index * (_step_sec + _gap_sec) + _step_sec


func _apply_step(index: int) -> void:
	var step: Dictionary = _steps[index]
	var style: Dictionary = SymbolStyle.get_style(step["symbol"])
	_banner_box.bg_color = style["bg"]
	_banner_box.border_color = Color("FFD700")
	_banner_box.set_border_width_all(3)
	_name.text = step["name"]
	_name.add_theme_color_override("font_color", style["fg"])
	_bonus.text = "BONUS +%d" % step["bonus"]
	_counter.text = "%d / %d" % [index + 1, _steps.size()] if _steps.size() > 1 else ""


func _show_step_content(show_content: bool) -> void:
	_title.visible = show_content
	_banner.visible = show_content
	_bonus.visible = show_content
	_counter.visible = show_content
	_hint.visible = _playing


func _setup_label(label: Label, rect: Rect2, font_size: int, color: Color) -> void:
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)

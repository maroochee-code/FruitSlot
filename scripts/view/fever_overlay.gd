class_name FeverOverlay
extends Control
## 피버 발동 연출: 화면 윗부분(하단 CREDIT/WIN/BET 줄 위까지)을 덮는 오버레이. 단계(step)를 차례로 보여 준다.
## 한 단계 = 심볼 하나의 "FEVER! 배너 / 심볼 칸 / 심볼 이름 / BONUS +금액". 단계 사이에는 빈 간격(배경만)이 있다.
## 이 클래스는 보여주기만 한다. 금액·순서는 확정된 SpinResult에서 그대로 받고, 건너뛰어도 숫자는 달라지지 않는다.
## 세븐 피버로 풀을 획득했으면 풀 획득 단계(kind = KIND_POOL)가 목록 맨 끝에 붙는다. 단계마다 보여 주는 시간이 다를 수 있다.
## 6-E: 배너·배경·심볼 칸·동전은 도트 그림(assets/ui)이고, 이름·금액은 갈무리14 글자다.
## 움직임(배경 프레임 번갈이·배너 색 번갈이·동전 회전)은 6-F에서 한다. 입력(마우스)은 화면 전체를 막는다.

signal step_started(index: int)
signal step_finished(index: int)
## 모든 단계가 끝났거나 건너뛰었을 때. skipped가 true면 건너뜀.
signal finished(skipped: bool)

const KIND_FEVER: StringName = &"fever"
const KIND_POOL: StringName = &"pool"

const SCREEN_SIZE: Vector2 = Vector2(640, 480)
const ART: int = SymbolStyle.ART_SCALE
## 그림이 덮는 영역 = 아트 138줄 = 640×414 (하단 표시창 y=414 바로 위까지)
const OVERLAY_SIZE: Vector2 = Vector2(640, 414)
const ART_WIDTH: int = 213
const TITLE_TEXT: String = "FEVER!"
const POOL_TITLE_TEXT: String = "POOL GET!"
const POOL_NAME_TEXT: String = "POOL"
## 그림 파일. 배경은 종류별 3프레임, 배너는 색 변형 a/b 2장 (번갈이는 6-F)
const BG_PATH: String = "res://assets/ui/%s_bg_%d.png"
const BANNER_PATH: String = "res://assets/ui/%s_banner_%s.png"
const BG_FRAME_COUNT: int = 3
const BANNER_VARIANTS: PackedStringArray = ["a", "b"]
## 배치 (아트 좌표, 213×138 영역 안. 화면 좌표 = 아트 × 3)
const BANNER_Y_ART: int = 10
const TILE_POS_ART: Vector2i = Vector2i(88, 44)
const NAME_Y_ART: int = 76
const NAME_H_ART: int = 16
const PLATE_RECT_ART: Rect2i = Rect2i(22, 96, 168, 28)
## 풀 단계의 동전 줄: 첫 동전 x, 간격, 개수, y (아트 좌표). 크기·회전은 6-F에서 조정한다.
const COIN_ROW_X_ART: int = 70
const COIN_ROW_STEP_ART: int = 16
const COIN_ROW_COUNT: int = 5
const COIN_ROW_Y_ART: int = 52
## 글자 크기는 갈무리 원래 크기의 정수배: 14(15px) ×3 = 45, 풀 금액은 ×4 = 60
const NAME_FONT_MULTIPLE: int = 3
const NAME_COLOR: Color = Color("f7e6b8")
const BONUS_FONT_MULTIPLE: int = 3
const POOL_BONUS_FONT_MULTIPLE: int = 4
const BONUS_COLOR: Color = Color("ffd23a")
const COUNT_FONT_MULTIPLE: int = 1
const COUNT_COLOR: Color = Color("8A8AA0")
const HINT_TEXT: String = "SPACE: 건너뛰기"
const HINT_FONT_MULTIPLE: int = 1
## 건너뛰기 힌트는 그림 영역 맨 아래 (390 + 24 = 414)
const HINT_Y: float = 390.0

var _steps: Array[Dictionary] = []
var _step_sec: float = 0.0
var _pool_sec: float = 0.0
var _gap_sec: float = 0.0
## 단계별 시작·끝 시각(초). play()에서 한 번 계산한다.
var _starts: PackedFloat64Array = PackedFloat64Array()
var _ends: PackedFloat64Array = PackedFloat64Array()
var _skip_lock_sec: float = 0.0
var _elapsed: float = 0.0
var _playing: bool = false
## 지금까지 시작/끝난 단계 수
var _started_count: int = 0
var _finished_count: int = 0

## 지금(또는 마지막으로) 보여 준 단계 종류, 배너가 읽히는 글자, 배경 프레임, 배너 색 변형
var _kind: StringName = KIND_FEVER
var _title_text: String = ""
var _bg_frame: int = 0
var _banner_variant: int = 0
## 재생 중 배경 프레임·배너 색이 번갈아 바뀌는 간격 (초). 0 이하면 움직이지 않는다 (기본, set_motion으로 켠다)
var _bg_frame_sec: float = 0.0
var _banner_flash_sec: float = 0.0
var _bg: TextureRect = TextureRect.new()
var _bg_textures: Dictionary = {}
var _banners: Dictionary = {}
var _banner_textures: Dictionary = {}
var _tile: TextureRect = TextureRect.new()
var _icon: TextureRect = TextureRect.new()
var _coin_row: Control = Control.new()
var _name: Label = Label.new()
var _plate: Panel = Panel.new()
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
	_build_art()
	_build_texts()
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
	# 세븐 피버로 풀을 획득했으면 맨 끝에 풀 획득 단계를 붙인다 (금액은 결과의 pool_won 그대로)
	if result.pool_won > 0:
		steps.append({
			"kind": KIND_POOL,
			"symbol": "",
			"name": POOL_NAME_TEXT,
			"bonus": result.pool_won,
		})
	return steps


## 단계 하나가 보이는 시간. 풀 획득 단계는 pool_sec, 피버 단계는 step_sec.
static func step_duration(step: Dictionary, step_sec: float, pool_sec: float) -> float:
	return pool_sec if step["kind"] == KIND_POOL else step_sec


## 모든 단계가 차지하는 시간의 합 (단계 사이 간격 포함, 마지막 뒤 간격 없음)
static func total_seconds(steps: Array[Dictionary], step_sec: float, gap_sec: float, pool_sec: float) -> float:
	if steps.is_empty():
		return 0.0
	var total: float = (steps.size() - 1) * gap_sec
	for step: Dictionary in steps:
		total += step_duration(step, step_sec, pool_sec)
	return total


## 연출 시작. 시간 값은 이번 스핀의 손맛 설정에서 받는다 (연출 중에는 바뀌지 않는다).
func play(steps: Array[Dictionary], step_sec: float, gap_sec: float, skip_lock_sec: float, pool_sec: float) -> void:
	if steps.is_empty():
		return
	_steps = steps
	_step_sec = step_sec
	_pool_sec = pool_sec
	_gap_sec = gap_sec
	_skip_lock_sec = skip_lock_sec
	_starts.clear()
	_ends.clear()
	var at: float = 0.0
	for step: Dictionary in _steps:
		_starts.append(at)
		at += step_duration(step, _step_sec, _pool_sec)
		_ends.append(at)
		at += _gap_sec
	_elapsed = 0.0
	_started_count = 0
	_finished_count = 0
	_playing = true
	visible = true
	_apply_motion()
	_update()


func is_playing() -> bool:
	return _playing


func step_count() -> int:
	return _steps.size()


## 단계 index의 내용 (kind / symbol / name / bonus). 테스트에서 화면이 받은 값을 읽을 때 쓴다.
func step_at(index: int) -> Dictionary:
	return _steps[index]


## 지금 단계 내용이 화면에 보이는 중인가 (단계 사이 간격에서는 false)
func is_showing_step() -> bool:
	return _playing and _step_index_at(_elapsed) >= 0


## 지금 보이는 단계 번호 (간격이면 -1)
func current_step() -> int:
	return _step_index_at(_elapsed) if _playing else -1


## 화면에 보이는 글자: { title, name, bonus }. title은 배너 그림이 읽히는 글자, name은 이름 줄 글자(풀 단계는 줄이 없어서 빈 글자).
func shown_texts() -> Dictionary:
	return { "title": _title_text, "name": _name.text if _name.visible else "", "bonus": _bonus.text }


## 배경 프레임·배너 색을 재생 시간(_elapsed)에 맞춰 번갈아 보이게 한다. 간격(초)은 feel.json의 fever_bg_frame_sec·fever_banner_flash_sec.
## 0 이하를 주면 그 항목은 움직이지 않는다. 화면 표시만 바꾸고 단계·시간·결과에는 영향이 없다. main과 테스트 메뉴가 play() 전에 부른다.
func set_motion(bg_frame_sec: float, banner_flash_sec: float) -> void:
	_bg_frame_sec = bg_frame_sec
	_banner_flash_sec = banner_flash_sec


## 배경 프레임 번호(0~2)를 바꾼다. 6-F의 움직임과 미리보기 씬이 쓴다.
func set_bg_frame(index: int) -> void:
	_bg_frame = posmod(index, BG_FRAME_COUNT)
	_bg.texture = _bg_textures[_kind][_bg_frame]


## 배너 색 변형(0 = a, 1 = b)을 바꾼다.
func set_banner_variant(index: int) -> void:
	_banner_variant = posmod(index, BANNER_VARIANTS.size())
	(_banners[_kind] as TextureRect).texture = _banner_textures[_kind][_banner_variant]


func elapsed() -> float:
	return _elapsed


func advance(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	_apply_motion()
	_update()


## 연출만 건너뛴다. 뜬 직후 skip_lock_sec 동안은 무시한다. 건너뛰었으면 true.
func skip() -> bool:
	if not _playing or _elapsed < _skip_lock_sec:
		return false
	_finish(true)
	return true


func _build_art() -> void:
	_bg.name = "BgFrame"
	_bg.size = OVERLAY_SIZE
	_setup_art(_bg)
	for kind: StringName in [KIND_FEVER, KIND_POOL]:
		var key: String = _asset_key(kind)
		var frames: Array[Texture2D] = []
		for i: int in BG_FRAME_COUNT:
			frames.append(load(BG_PATH % [key, i]) as Texture2D)
		_bg_textures[kind] = frames
		var variants: Array[Texture2D] = []
		for variant: String in BANNER_VARIANTS:
			variants.append(load(BANNER_PATH % [key, variant]) as Texture2D)
		_banner_textures[kind] = variants
		var banner: TextureRect = TextureRect.new()
		banner.name = "BannerFever" if kind == KIND_FEVER else "BannerPool"
		banner.texture = variants[0]
		banner.size = variants[0].get_size()
		var banner_art_width: int = int(banner.size.x) / ART
		banner.position = Vector2((ART_WIDTH - banner_art_width) / 2 * ART, BANNER_Y_ART * ART)
		_setup_art(banner)
		_banners[kind] = banner
	_bg.texture = _bg_textures[KIND_FEVER][0]
	_tile.name = "SymbolTile"
	_tile.texture = SymbolStyle.load_tile()
	_tile.position = Vector2(TILE_POS_ART) * ART
	_tile.size = _tile.texture.get_size() * ART
	_setup_art(_tile)
	_icon.name = "SymbolIcon"
	_icon.position = Vector2(SymbolStyle.SYMBOL_ART_OFFSET * ART)
	_setup_art(_icon, false)
	_tile.add_child(_icon)
	_coin_row.name = "CoinRow"
	_coin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_coin_row)
	for i: int in COIN_ROW_COUNT:
		var coin: TextureRect = TextureRect.new()
		coin.name = "Coin%d" % i
		coin.texture = CoinSheet.frame(i)
		coin.position = Vector2((COIN_ROW_X_ART + i * COIN_ROW_STEP_ART) * ART, COIN_ROW_Y_ART * ART)
		coin.size = Vector2(CoinSheet.FRAME_PX, CoinSheet.FRAME_PX)
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_coin_row.add_child(coin)


func _build_texts() -> void:
	_setup_label(_name, Rect2(0, NAME_Y_ART * ART, SCREEN_SIZE.x, NAME_H_ART * ART), UiFont.Face.LARGE, NAME_FONT_MULTIPLE, NAME_COLOR)
	_name.name = "NameLabel"
	_plate.name = "BonusPlate"
	_plate.position = Vector2(PLATE_RECT_ART.position * ART)
	_plate.size = Vector2(PLATE_RECT_ART.size * ART)
	_plate.add_theme_stylebox_override("panel", UiSkin.panel_box())
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	_setup_label(_bonus, Rect2(Vector2.ZERO, _plate.size), UiFont.Face.LARGE, BONUS_FONT_MULTIPLE, BONUS_COLOR)
	_bonus.name = "BonusLabel"
	_bonus.reparent(_plate, false)
	_setup_label(_counter, Rect2(0, 8, SCREEN_SIZE.x - 12, 24), UiFont.Face.BODY, COUNT_FONT_MULTIPLE, COUNT_COLOR)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_setup_label(_hint, Rect2(0, HINT_Y, SCREEN_SIZE.x, 24), UiFont.Face.BODY, HINT_FONT_MULTIPLE, COUNT_COLOR)
	_hint.text = HINT_TEXT


## 그림 노드 공통 설정: 클릭을 막지 않고, 정해 준 크기로 Nearest 확대 없이 그린다.
func _setup_art(rect: TextureRect, attach: bool = true) -> void:
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	if attach:
		add_child(rect)


static func _asset_key(kind: StringName) -> String:
	return "fever" if kind == KIND_FEVER else "pool"


## 재생 시간에 맞는 배경 프레임·배너 색 번호를 정한다 (실제 그림은 _apply_step이 적용). 재생이 끝나면 advance가 멈추므로 더는 바뀌지 않는다.
func _apply_motion() -> void:
	if _bg_frame_sec > 0.0:
		_bg_frame = posmod(int(_elapsed / _bg_frame_sec), BG_FRAME_COUNT)
	if _banner_flash_sec > 0.0:
		_banner_variant = posmod(int(_elapsed / _banner_flash_sec), BANNER_VARIANTS.size())


func _update() -> void:
	var total: float = _ends[_ends.size() - 1]
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
	if index >= 0:
		_apply_step(index)
	_show_step_content(index >= 0)


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
	for i: int in _starts.size():
		if t >= _starts[i] and t < _ends[i]:
			return i
	return -1


## 지금 시각까지 시작된 마지막 단계 번호 (간격 중이면 직전 단계)
func _passed_index() -> int:
	var passed: int = -1
	for i: int in _starts.size():
		if _starts[i] <= _elapsed:
			passed = i
	return passed


func _step_end(index: int) -> float:
	return _ends[index]


func _apply_step(index: int) -> void:
	var step: Dictionary = _steps[index]
	var is_pool: bool = step["kind"] == KIND_POOL
	_kind = KIND_POOL if is_pool else KIND_FEVER
	_title_text = POOL_TITLE_TEXT if is_pool else TITLE_TEXT
	set_bg_frame(_bg_frame)
	set_banner_variant(_banner_variant)
	if not is_pool:
		_icon.texture = SymbolStyle.load_icon(step["symbol"])
		if _icon.texture != null:
			_icon.size = _icon.texture.get_size() * ART
	_name.text = step["name"]
	var multiple: int = POOL_BONUS_FONT_MULTIPLE if is_pool else BONUS_FONT_MULTIPLE
	UiFont.apply(_bonus, UiFont.Face.LARGE, multiple)
	_bonus.text = ("POOL +%d" if is_pool else "BONUS +%d") % step["bonus"]
	_counter.text = "%d / %d" % [index + 1, _steps.size()] if _steps.size() > 1 else ""


## 단계 내용(배너·심볼 칸·동전·이름·금액 판·카운터)을 보이거나 숨긴다. 배경과 힌트는 연출 중이면 계속 보인다.
func _show_step_content(show_content: bool) -> void:
	_bg.visible = _playing
	for kind: StringName in _banners:
		(_banners[kind] as TextureRect).visible = show_content and kind == _kind
	_tile.visible = show_content and _kind == KIND_FEVER
	_coin_row.visible = show_content and _kind == KIND_POOL
	_name.visible = show_content and _kind == KIND_FEVER
	_plate.visible = show_content
	_counter.visible = show_content
	_hint.visible = _playing


func _setup_label(label: Label, rect: Rect2, face: UiFont.Face, multiple: int, color: Color) -> void:
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFont.apply(label, face, multiple)
	label.add_theme_color_override("font_color", color)
	add_child(label)

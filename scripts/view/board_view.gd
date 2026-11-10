class_name BoardView
extends Control
## 릴 뒤의 보드(바탕 + 외곽선 + 전구 링). 전구는 BulbPattern 규칙(대기/스핀/당첨/피버)으로 움직인다(6-F3a).
## 크기는 도트 아트 좌표(116×92)에 ART_SCALE(3)을 곱한 값이고, 전구는 아트 2×2 픽셀(그림 bulbs.png)이다.
## 아트 좌표: 보드 안쪽 칸 영역은 (4,4)에서 시작하고, 전구는 외곽선 안쪽에 한 줄로 돈다.
## 시간 0의 대기 모양은 6-B의 정적 모양(짝수 번호 켜짐)과 같다.

## 보드 크기 (아트 좌표)
const BOARD_ART_SIZE: Vector2i = Vector2i(116, 92)
const OUTLINE_ART: int = 1
const BULB_ART_SIZE: int = 2
## 전구 사이 간격 (아트 좌표). 가로·세로 전구 구간 길이가 이 값으로 나누어떨어져야 모서리가 맞는다.
const BULB_STEP_ART: int = 4
## 첫 전구 위치 (아트 좌표, 보드 왼쪽 위 기준)
const BULB_FIRST_ART: int = 1
const BOARD_COLOR: Color = Color("3a2a5c")
const OUTLINE_COLOR: Color = Color("2b1b3d")

## 시계 방향으로 도는 전구 목록. 각 항목은 아트 좌표(왼쪽 위 모서리).
var _bulbs: Array[Vector2i] = []
var _pattern: BulbPattern = BulbPattern.new()
var _mode: int = BulbPattern.Mode.IDLE
var _time: float = 0.0
var _states: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(BOARD_ART_SIZE * SymbolStyle.ART_SCALE)
	_bulbs = _make_bulb_ring()
	_states = _pattern.states_of(_mode, _bulbs.size(), _time)


## 전구 개수
func bulb_count() -> int:
	return _bulbs.size()


## 번호 index 전구의 아트 좌표 위치
func bulb_art_position(index: int) -> Vector2i:
	return _bulbs[index]


## 지금 켜져 있는가 (꺼짐이 아닌 모든 상태)
func bulb_is_lit(index: int) -> bool:
	return _states[index] != BulbSheet.STATE_OFF


## 지금 전구 상태 (BulbSheet.STATE_*)
func bulb_state(index: int) -> int:
	return _states[index]


func mode() -> int:
	return _mode


func apply_feel(feel: FeelConfig) -> void:
	_pattern.apply_feel(feel)


## 모드를 바꾸고 시간을 0부터 다시 센다.
func set_mode(new_mode: int) -> void:
	_mode = new_mode
	_time = 0.0
	_refresh()


## 시간을 delta초 진행한다. 전구 모양이 바뀔 때만 다시 그린다.
func advance(delta: float) -> void:
	_time += delta
	_refresh()


func _refresh() -> void:
	var next: PackedInt32Array = _pattern.states_of(_mode, _bulbs.size(), _time)
	if next != _states:
		_states = next
		queue_redraw()


func _draw() -> void:
	var scale_px: float = float(SymbolStyle.ART_SCALE)
	draw_rect(Rect2(Vector2.ZERO, size), OUTLINE_COLOR)
	var inner: Rect2 = Rect2(Vector2(OUTLINE_ART, OUTLINE_ART) * scale_px, size - Vector2(OUTLINE_ART * 2, OUTLINE_ART * 2) * scale_px)
	draw_rect(inner, BOARD_COLOR)
	for i: int in _bulbs.size():
		draw_texture(BulbSheet.frame(_states[i]), Vector2(_bulbs[i]) * scale_px)


func _make_bulb_ring() -> Array[Vector2i]:
	var last_x: int = BOARD_ART_SIZE.x - OUTLINE_ART - BULB_ART_SIZE
	var last_y: int = BOARD_ART_SIZE.y - OUTLINE_ART - BULB_ART_SIZE
	var ring: Array[Vector2i] = []
	for x: int in range(BULB_FIRST_ART, last_x + 1, BULB_STEP_ART):
		ring.append(Vector2i(x, BULB_FIRST_ART))
	for y: int in range(BULB_FIRST_ART + BULB_STEP_ART, last_y + 1, BULB_STEP_ART):
		ring.append(Vector2i(last_x, y))
	for x: int in range(last_x - BULB_STEP_ART, BULB_FIRST_ART - 1, -BULB_STEP_ART):
		ring.append(Vector2i(x, last_y))
	for y: int in range(last_y - BULB_STEP_ART, BULB_FIRST_ART, -BULB_STEP_ART):
		ring.append(Vector2i(BULB_FIRST_ART, y))
	return ring

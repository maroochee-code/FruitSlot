class_name BoardView
extends Control
## 릴 뒤의 보드(바탕 + 외곽선 + 전구 링). 6-B에서는 정지 상태로만 그린다.
## 크기는 도트 아트 좌표(116×92)에 ART_SCALE(3)을 곱한 값이고, 전구는 아트 2×2 픽셀이다.
## 아트 좌표: 보드 안쪽 칸 영역은 (4,4)에서 시작하고, 전구는 외곽선 안쪽에 한 줄로 돈다.

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
const BULB_ON_COLOR: Color = Color("ffe14d")
const BULB_OFF_COLOR: Color = Color("8a7a3a")

## 시계 방향으로 도는 전구 목록. 각 항목은 아트 좌표(왼쪽 위 모서리).
var _bulbs: Array[Vector2i] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(BOARD_ART_SIZE * SymbolStyle.ART_SCALE)
	_bulbs = _make_bulb_ring()


## 전구 개수
func bulb_count() -> int:
	return _bulbs.size()


## 번호 index 전구의 아트 좌표 위치
func bulb_art_position(index: int) -> Vector2i:
	return _bulbs[index]


## 켜짐/꺼짐 교대 (짝수 번호가 켜짐)
func bulb_is_lit(index: int) -> bool:
	return index % 2 == 0


func _draw() -> void:
	var scale_px: float = float(SymbolStyle.ART_SCALE)
	draw_rect(Rect2(Vector2.ZERO, size), OUTLINE_COLOR)
	var inner: Rect2 = Rect2(Vector2(OUTLINE_ART, OUTLINE_ART) * scale_px, size - Vector2(OUTLINE_ART * 2, OUTLINE_ART * 2) * scale_px)
	draw_rect(inner, BOARD_COLOR)
	for i: int in _bulbs.size():
		var color: Color = BULB_ON_COLOR if bulb_is_lit(i) else BULB_OFF_COLOR
		draw_rect(Rect2(Vector2(_bulbs[i]) * scale_px, Vector2(BULB_ART_SIZE, BULB_ART_SIZE) * scale_px), color)


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

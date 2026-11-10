class_name FrameBulbs
extends Control
## 프레임 가로 띠 위의 전구 소켓 18개(6-F3a). frame.png에 꺼진 모양으로 구워진 소켓 자리에 켜진 전구를 얹어 그린다.
## 소켓 좌표는 tools/gen_pixel_assets.py의 FRAME_BULB_SOCKETS와 같다 (테스트가 frame.png와 맞는지 확인한다).
## 모든 전구는 클릭을 막지 않고, 보드 링(BoardView)과 같은 규칙(BulbPattern)으로 움직인다.

## 소켓: 첫 x, 간격, 개수, y (아트 좌표). 한 소켓은 아트 2×2.
const FIRST_X_ART: int = 6
const STEP_ART: int = 8
const SOCKET_COUNT: int = 18
const Y_ART: int = 135

var _pattern: BulbPattern = BulbPattern.new()
var _mode: int = BulbPattern.Mode.IDLE
var _time: float = 0.0
var _states: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	name = "FrameBulbs"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_states = _pattern.states_of(_mode, SOCKET_COUNT, _time)


func socket_count() -> int:
	return SOCKET_COUNT


## 번호 index 소켓의 아트 좌표 (왼쪽 위 모서리)
func socket_art_position(index: int) -> Vector2i:
	return Vector2i(FIRST_X_ART + index * STEP_ART, Y_ART)


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


func advance(delta: float) -> void:
	_time += delta
	_refresh()


func _refresh() -> void:
	var next: PackedInt32Array = _pattern.states_of(_mode, SOCKET_COUNT, _time)
	if next != _states:
		_states = next
		queue_redraw()


func _draw() -> void:
	var scale_px: float = float(SymbolStyle.ART_SCALE)
	for i: int in SOCKET_COUNT:
		draw_texture(BulbSheet.frame(_states[i]), Vector2(socket_art_position(i)) * scale_px)

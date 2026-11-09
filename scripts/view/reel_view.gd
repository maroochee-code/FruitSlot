class_name ReelView
extends Control
## 릴 하나의 화면. 세로로 3개의 "칸 창"이 고정되어 있고, 각 창은 자기 칸 모양으로 잘라서 보여 준다.
## 창 하나 안에는 심볼 칸 2개(위/아래)가 걸쳐서 스크롤한다. 심볼은 창 밖으로 나가지 않는다.
## 보이는 심볼은 항상 balance.json 릴 스트립의 실제 순서다. (랜덤 심볼을 보여주지 않는다.)
## position의 정수부 = base, 소수부 = fraction 일 때, 줄 r(0~2)의 창은
##   위 칸 = 스트립[base + r]     (창 안 높이 -fraction × 칸 높이)
##   아래 칸 = 스트립[base + r + 1] (위 칸 바로 아래에 이어 붙음)
## 이다. 멈췄을 때(fraction 0) 위 칸이 창을 꽉 채우고 아래 칸은 창 밖에 있다.

## 위치 비교 허용 오차 (픽셀)
const POSITION_EPS: float = 0.01

var motion: ReelMotion

var _strip: PackedStringArray = PackedStringArray()
var _rows: int = 0
var _cell_height: float = 0.0
var _windows: Array[Control] = []
var _upper: Array[SymbolCell] = []
var _lower: Array[SymbolCell] = []
var _base: int = 0
var _bound: bool = false


## visible_rows: 칸 창 개수. 창은 위에서 아래로 gap 간격으로 놓인다.
func setup(strip: PackedStringArray, reel_motion: ReelMotion, cell_size: Vector2, gap: float, visible_rows: int) -> void:
	_strip = strip
	motion = reel_motion
	_rows = visible_rows
	_cell_height = cell_size.y
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(cell_size.x, visible_rows * cell_size.y + (visible_rows - 1) * gap)
	for r: int in visible_rows:
		var window: Control = _make_window(r, cell_size, Vector2(0.0, r * (cell_size.y + gap)))
		_upper.append(_add_symbol_cell(window, "Upper", cell_size))
		_lower.append(_add_symbol_cell(window, "Lower", cell_size))
		_windows.append(window)
	refresh()


## row 0~2 = 멈췄을 때의 윗줄·가운데·아랫줄 칸 (정지 상태에서 창을 채우는 위 칸)
func cell_at(row: int) -> SymbolCell:
	return _upper[row]


## 줄 row의 칸 창 (테스트용)
func window_at(row: int) -> Control:
	return _windows[row]


## motion.position에 맞춰 칸의 심볼과 스크롤 위치를 갱신한다. 창 자체는 움직이지 않는다.
func refresh() -> void:
	var position_now: float = motion.position
	var base: int = floori(position_now)
	var fraction: float = position_now - float(base)
	if not _bound or base != _base:
		_bound = true
		_base = base
		for r: int in _rows:
			_show_if_changed(_upper[r], _expected_symbol(base, r))
			_show_if_changed(_lower[r], _expected_symbol(base, r + 1))
	var upper_y: float = -fraction * _cell_height
	for r: int in _rows:
		_upper[r].position = Vector2(0.0, upper_y)
		_lower[r].position = Vector2(0.0, upper_y + _cell_height)


## 칸에 그려진 심볼이 모두 실제 스트립 순서와 맞는지 (테스트용)
func is_consistent() -> bool:
	var base: int = floori(motion.position)
	for r: int in _rows:
		if _upper[r].symbol_id != _expected_symbol(base, r):
			return false
		if _lower[r].symbol_id != _expected_symbol(base, r + 1):
			return false
	return true


## 모든 창에서 두 칸이 빈틈·겹침 없이 이어져 창 전체를 덮고 있는지, 창이 잘라서(clip) 보여 주는지 (테스트용)
func windows_are_sound() -> bool:
	for r: int in _rows:
		var window: Control = _windows[r]
		if not window.clip_contents:
			return false
		var upper_y: float = _upper[r].position.y
		var lower_y: float = _lower[r].position.y
		if upper_y > POSITION_EPS or upper_y <= -_cell_height - POSITION_EPS:
			return false
		if absf(lower_y - (upper_y + _cell_height)) > POSITION_EPS:
			return false
		if lower_y + _cell_height < _cell_height - POSITION_EPS:
			return false
	return true


func _show_if_changed(cell: SymbolCell, symbol_id: String) -> void:
	if cell.symbol_id != symbol_id:
		cell.show_symbol(symbol_id)


func _expected_symbol(base: int, offset: int) -> String:
	return _strip[posmod(base + offset, _strip.size())]


func _make_window(row: int, cell_size: Vector2, at: Vector2) -> Control:
	var window: Control = Control.new()
	window.name = "Window_%d" % row
	window.position = at
	window.size = cell_size
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(window)
	return window


func _add_symbol_cell(window: Control, cell_name: String, cell_size: Vector2) -> SymbolCell:
	var cell: SymbolCell = SymbolCell.new()
	cell.name = cell_name
	cell.size = cell_size
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(cell)
	return cell


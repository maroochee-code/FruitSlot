class_name ReelView
extends Control
## 릴 하나의 화면. ReelMotion의 position을 읽어 칸 6개를 움직여 그린다.
## 보이는 심볼은 항상 balance.json 릴 스트립의 실제 순서다. (랜덤 심볼을 보여주지 않는다.)
## 칸 n(0~5)은 스트립 번호 (floor(position) - 1 + n)를 그리고, 화면 높이는 (n - 1 - 소수부) 칸이다.
## 멈춰 있을 때(소수부 0) n=1~3이 윗줄·가운데·아랫줄이다.

const CELL_COUNT: int = 6
## 창 위의 첫 칸(n=0)이 멈췄을 때 윗줄(n=1) 바로 위에 오도록 하는 오프셋
const REST_ROW_OFFSET: int = 1

var motion: ReelMotion

var _strip: PackedStringArray = PackedStringArray()
var _cells: Array[SymbolCell] = []
var _pitch: float = 0.0
var _extension: float = 0.0
var _base: int = 0
var _bound: bool = false
var _top_shade: ColorRect
var _bottom_shade: ColorRect


## visible_rows: 창에 보이는 줄 수, extension: 창 위·아래로 더 보이는 높이(px)
func setup(strip: PackedStringArray, reel_motion: ReelMotion, cell_size: Vector2, gap: float, visible_rows: int, extension: float, shade_color: Color) -> void:
	_strip = strip
	motion = reel_motion
	_pitch = cell_size.y + gap
	_extension = extension
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var window_height: float = visible_rows * cell_size.y + (visible_rows - 1) * gap
	size = Vector2(cell_size.x, window_height + 2.0 * extension)
	for n: int in CELL_COUNT:
		var cell: SymbolCell = SymbolCell.new()
		cell.name = "Cell_%d" % n
		cell.size = cell_size
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cell)
		_cells.append(cell)
	_top_shade = _make_shade("TopShade", Rect2(0, 0, cell_size.x, extension), shade_color)
	_bottom_shade = _make_shade("BottomShade", Rect2(0, extension + window_height, cell_size.x, extension), shade_color)
	refresh()


## row 0~2 = 멈췄을 때의 윗줄·가운데·아랫줄 칸
func cell_at(row: int) -> SymbolCell:
	return _cells[row + REST_ROW_OFFSET]


## 회전 중에는 창 위아래의 덤 부분을 어둡게 가린다.
func set_spinning_look(on: bool) -> void:
	_top_shade.visible = on and _extension > 0.0
	_bottom_shade.visible = on and _extension > 0.0


## motion.position에 맞춰 칸의 심볼과 높이를 갱신한다.
func refresh() -> void:
	var position_now: float = motion.position
	var base: int = floori(position_now)
	var fraction: float = position_now - float(base)
	if not _bound or base != _base:
		_bound = true
		_base = base
		for n: int in CELL_COUNT:
			var symbol_id: String = _expected_symbol(base, n)
			if _cells[n].symbol_id != symbol_id:
				_cells[n].show_symbol(symbol_id)
	for n: int in CELL_COUNT:
		_cells[n].position = Vector2(0.0, _extension + (float(n - REST_ROW_OFFSET) - fraction) * _pitch)


## 칸에 그려진 심볼이 모두 실제 스트립 순서와 맞는지 (테스트용)
func is_consistent() -> bool:
	var base: int = floori(motion.position)
	for n: int in CELL_COUNT:
		if _cells[n].symbol_id != _expected_symbol(base, n):
			return false
	return true


func _expected_symbol(base: int, n: int) -> String:
	return _strip[posmod(base - REST_ROW_OFFSET + n, _strip.size())]


func _make_shade(node_name: String, rect: Rect2, color: Color) -> ColorRect:
	var shade: ColorRect = ColorRect.new()
	shade.name = node_name
	shade.position = rect.position
	shade.size = rect.size
	shade.color = color
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.visible = false
	add_child(shade)
	return shade

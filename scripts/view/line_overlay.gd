class_name LineOverlay
extends Control
## 라인 라벨(A~H + 베팅 수), 당첨 라인 선, 당첨 칸 강조를 맡는다.
## 라인의 칸 좌표와 종류는 balance.json(BalanceData.lines)에서 읽는다. 여기 있는 상수는 화면 설정이다.

const VERTICAL: String = "vertical"
const LABEL_SIZE: Vector2 = Vector2(34, 24)
const LABEL_FONT_SIZE: int = 12
const LABEL_STACK_GAP: float = 2.0
const SIDE_GAP: float = 6.0
const TOP_GAP: float = 4.0
const DIM_ALPHA: float = 0.25
const LINE_WIDTH: float = 4.0
const LINE_EXTEND: float = 20.0
const BLINK_CYCLES: int = 3
const BLINK_HALF_SEC: float = 0.25
const BLINK_LOW_ALPHA: float = 0.15
const LABEL_BG: Color = Color("14141C")
## 라인 순서(A→H)대로 쓰는 선 색
const LINE_PALETTE: Array[Color] = [
	Color("FF5050"), Color("50C8FF"), Color("FFE050"), Color("60E070"),
	Color("FF90FF"), Color("FFA040"), Color("A0A0FF"), Color("70FFE0"),
]

var _data: BalanceData
var _cells: Array[Array] = []
var _origin: Vector2 = Vector2.ZERO
var _cell_size: Vector2 = Vector2.ZERO
var _gap: float = 0.0
## 라인 순서별 라벨 목록 (가로·대각선은 양쪽 끝 2개, 세로는 위쪽 1개)
var _line_labels: Array[Array] = []
var _win_lines: Array[Line2D] = []
var _lit_cells: Array[SymbolCell] = []
var _tween: Tween


func setup(data: BalanceData, cells: Array[Array], origin: Vector2, cell_size: Vector2, gap: float) -> void:
	_data = data
	_cells = cells
	_origin = origin
	_cell_size = cell_size
	_gap = gap
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_labels()


## 라인별 베팅 수를 라벨에 반영한다. 0이면 어둡게.
func update_bets(line_bets: PackedInt32Array) -> void:
	for i: int in _data.line_count():
		for label: Label in _line_labels[i]:
			label.text = "%s %d" % [_data.lines[i].id, line_bets[i]]
			label.modulate.a = 1.0 if line_bets[i] > 0 else DIM_ALPHA


## 당첨 라인을 선으로 긋고 해당 칸을 강조한 뒤 깜빡인다. 깜빡임이 끝나면 선은 그대로 남는다.
func show_wins(wins: Array[LineWin]) -> void:
	clear_wins()
	for win: LineWin in wins:
		var index: int = _line_index(win.line_id)
		if index < 0:
			continue
		var line: LineDef = _data.lines[index]
		_add_win_line(line, LINE_PALETTE[index % LINE_PALETTE.size()])
		for cell_pos: Vector2i in line.cells:
			var cell: SymbolCell = _cells[cell_pos.x][cell_pos.y]
			if not _lit_cells.has(cell):
				_lit_cells.append(cell)
				cell.set_highlight(true)
	if _win_lines.is_empty():
		return
	_tween = create_tween()
	for i: int in BLINK_CYCLES:
		_tween.tween_method(_set_blink_alpha, 1.0, BLINK_LOW_ALPHA, BLINK_HALF_SEC)
		_tween.tween_method(_set_blink_alpha, BLINK_LOW_ALPHA, 1.0, BLINK_HALF_SEC)


func clear_wins() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	for line: Line2D in _win_lines:
		line.queue_free()
	_win_lines.clear()
	for cell: SymbolCell in _lit_cells:
		cell.set_highlight(false)
	_lit_cells.clear()


func win_line_count() -> int:
	return _win_lines.size()


func lit_cell_count() -> int:
	return _lit_cells.size()


## 테스트용: 라인 순서 index의 라벨 글자와 어두운지 여부
func label_text(line_index: int) -> String:
	return (_line_labels[line_index][0] as Label).text


func label_is_dim(line_index: int) -> bool:
	return (_line_labels[line_index][0] as Label).modulate.a < 1.0


func _set_blink_alpha(alpha: float) -> void:
	for line: Line2D in _win_lines:
		line.modulate.a = alpha
	for cell: SymbolCell in _lit_cells:
		cell.set_highlight_alpha(alpha)


func _line_index(line_id: String) -> int:
	for i: int in _data.line_count():
		if _data.lines[i].id == line_id:
			return i
	return -1


func _cell_rect(col: int, row: int) -> Rect2:
	var pos: Vector2 = _origin + Vector2(col * (_cell_size.x + _gap), row * (_cell_size.y + _gap))
	return Rect2(pos, _cell_size)


func _add_win_line(line: LineDef, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for cell_pos: Vector2i in line.cells:
		points.append(_cell_rect(cell_pos.x, cell_pos.y).get_center())
	var first_dir: Vector2 = (points[1] - points[0]).normalized()
	var last_dir: Vector2 = (points[-1] - points[-2]).normalized()
	points[0] = points[0] - first_dir * LINE_EXTEND
	points[-1] = points[-1] + last_dir * LINE_EXTEND
	var shape: Line2D = Line2D.new()
	shape.points = points
	shape.width = LINE_WIDTH
	shape.default_color = color
	shape.antialiased = true
	add_child(shape)
	_win_lines.append(shape)


## 가로·대각선은 시작 칸 높이의 왼쪽 + 끝 칸 높이의 오른쪽, 세로는 첫 칸 위쪽에 라벨을 둔다.
## 같은 높이에 여러 개면 위아래로 쌓는다.
func _build_labels() -> void:
	var groups: Dictionary = {}
	for i: int in _data.line_count():
		_line_labels.append([])
		var line: LineDef = _data.lines[i]
		if line.type == VERTICAL:
			_place_top_label(i, line)
		else:
			_add_to_group(groups, "L%d" % line.cells[0].y, i)
			_add_to_group(groups, "R%d" % line.cells[-1].y, i)
	for key: String in groups:
		_place_side_group(key, groups[key])


func _add_to_group(groups: Dictionary, key: String, line_index: int) -> void:
	if not groups.has(key):
		groups[key] = []
	groups[key].append(line_index)


func _place_top_label(line_index: int, line: LineDef) -> void:
	var rect: Rect2 = _cell_rect(line.cells[0].x, line.cells[0].y)
	var pos: Vector2 = Vector2(rect.get_center().x - LABEL_SIZE.x / 2.0, rect.position.y - LABEL_SIZE.y - TOP_GAP)
	_add_label(line_index, pos)


func _place_side_group(key: String, members: Array) -> void:
	var is_left: bool = key.begins_with("L")
	var row: int = int(key.substr(1))
	var last_col: int = _data.reel_count - 1
	var row_rect: Rect2 = _cell_rect(0, row)
	var x: float
	if is_left:
		x = _cell_rect(0, 0).position.x - SIDE_GAP - LABEL_SIZE.x
	else:
		x = _cell_rect(last_col, 0).end.x + SIDE_GAP
	var count: int = members.size()
	var total_height: float = count * LABEL_SIZE.y + (count - 1) * LABEL_STACK_GAP
	var y: float = row_rect.get_center().y - total_height / 2.0
	for member: int in members:
		_add_label(member, Vector2(x, y))
		y += LABEL_SIZE.y + LABEL_STACK_GAP


func _add_label(line_index: int, pos: Vector2) -> void:
	var color: Color = LINE_PALETTE[line_index % LINE_PALETTE.size()]
	var label: Label = Label.new()
	label.name = "LineLabel_%s_%d" % [_data.lines[line_index].id, _line_labels[line_index].size()]
	label.position = pos
	label.size = LABEL_SIZE
	label.text = "%s 0" % _data.lines[line_index].id
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = LABEL_BG
	box.border_color = color
	box.set_border_width_all(1)
	label.add_theme_stylebox_override("normal", box)
	add_child(label)
	_line_labels[line_index].append(label)

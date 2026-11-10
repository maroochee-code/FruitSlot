class_name BalanceData
extends RefCounted
## balance.json을 읽고 검사해서 보관한다. 모든 밸런스 수치는 여기서만 나온다.

const DEFAULT_PATH: String = "res://data/balance.json"

var version: String = ""
var reel_count: int = 0
var visible_rows: int = 0
var symbol_ids: PackedStringArray = PackedStringArray()
var symbol_names: Dictionary[String, String] = {}
var paytable: Dictionary[String, int] = {}
var reels: Array[PackedStringArray] = []
var lines: Array[LineDef] = []
var max_total_bet: int = 0
## AUTO: 한 판 WIN이 이 값 이상이면 AUTO를 끈다. 0이면 사용 안 함 (balance.json의 auto_spin.stop_on_win_at)
var auto_stop_on_win_at: int = 0

var fever_min_total_bet: int = 0
## 피버 대상 심볼 (balance.json 순서 유지)
var fever_symbols: PackedStringArray = PackedStringArray()
var fever_initial_counts: Dictionary[String, int] = {}
var fever_multipliers: Dictionary[String, int] = {}

var pool_initial: int = 0
var pool_contribution_rate: float = 0.0
var pool_min_total_bet: int = 0
var pool_award_on_fever: String = ""

## 검사에서 발견한 문제 목록. 비어 있어야 정상.
var errors: PackedStringArray = PackedStringArray()


## 파일에서 읽는다. 문제가 있으면 null을 돌려주고 에러를 출력한다.
static func load_from_file(path: String = DEFAULT_PATH) -> BalanceData:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("BalanceData: 파일을 읽을 수 없음 %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_error("BalanceData: JSON 형식 오류 %s %d행: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("BalanceData: 최상위가 객체가 아님 %s" % path)
		return null
	return from_dict(json.data)


## 사전(Dictionary)에서 만든다. 테스트에서 임의 데이터를 넣을 때도 쓴다.
static func from_dict(raw: Dictionary) -> BalanceData:
	var data: BalanceData = BalanceData.new()
	data._parse(raw)
	data._validate()
	if not data.errors.is_empty():
		for message: String in data.errors:
			push_error("BalanceData: " + message)
		return null
	return data


func symbol_count() -> int:
	return symbol_ids.size()


func line_count() -> int:
	return lines.size()


func _parse(raw: Dictionary) -> void:
	version = str(raw.get("version", ""))
	reel_count = int(raw.get("reel_count", 0))
	visible_rows = int(raw.get("visible_rows", 0))
	_parse_symbols(raw.get("symbols", []))
	_parse_paytable(raw.get("paytable", {}))
	_parse_reels(raw.get("reels", []))
	_parse_lines(raw.get("lines", []))
	var bet: Dictionary = raw.get("bet", {})
	max_total_bet = int(bet.get("max_total", 0))
	auto_stop_on_win_at = int(raw.get("auto_spin", {}).get("stop_on_win_at", 0))
	_parse_fever(raw.get("fever", {}))
	_parse_pool(raw.get("pool", {}))


func _parse_symbols(raw_symbols: Array) -> void:
	for entry: Variant in raw_symbols:
		var symbol: Dictionary = entry
		var id: String = str(symbol.get("id", ""))
		symbol_ids.append(id)
		symbol_names[id] = str(symbol.get("name", id))


func _parse_paytable(raw_paytable: Dictionary) -> void:
	for key: Variant in raw_paytable:
		paytable[str(key)] = int(raw_paytable[key])


func _parse_reels(raw_reels: Array) -> void:
	for raw_strip: Variant in raw_reels:
		var strip: PackedStringArray = PackedStringArray()
		for symbol: Variant in raw_strip:
			strip.append(str(symbol))
		reels.append(strip)


func _parse_lines(raw_lines: Array) -> void:
	for entry: Variant in raw_lines:
		var raw_line: Dictionary = entry
		var line: LineDef = LineDef.new()
		line.id = str(raw_line.get("id", ""))
		line.type = str(raw_line.get("type", ""))
		for raw_cell: Variant in raw_line.get("cells", []):
			var cell: Array = raw_cell
			line.cells.append(Vector2i(int(cell[0]), int(cell[1])))
		lines.append(line)


func _parse_fever(raw_fever: Dictionary) -> void:
	fever_min_total_bet = int(raw_fever.get("min_total_bet", 0))
	for entry: Variant in raw_fever.get("targets", []):
		var target: Dictionary = entry
		var symbol: String = str(target.get("symbol", ""))
		fever_symbols.append(symbol)
		fever_initial_counts[symbol] = int(target.get("initial_count", 0))
		fever_multipliers[symbol] = int(target.get("bonus_multiplier", 0))


func _parse_pool(raw_pool: Dictionary) -> void:
	pool_initial = int(raw_pool.get("initial", 0))
	pool_contribution_rate = float(raw_pool.get("contribution_rate", 0.0))
	pool_min_total_bet = int(raw_pool.get("min_total_bet", 0))
	pool_award_on_fever = str(raw_pool.get("award_on_fever", ""))


func _validate() -> void:
	if reel_count <= 0 or visible_rows <= 0:
		errors.append("reel_count / visible_rows는 1 이상이어야 함")
	if symbol_ids.is_empty():
		errors.append("symbols가 비어 있음")
	_validate_paytable()
	_validate_reels()
	_validate_lines()
	_validate_fever_and_pool()
	if auto_stop_on_win_at < 0:
		errors.append("auto_spin.stop_on_win_at(%d)은 0 이상이어야 함 (0 = 사용 안 함)" % auto_stop_on_win_at)
	if max_total_bet < line_count():
		errors.append("bet.max_total(%d)은 라인 수(%d) 이상이어야 함" % [max_total_bet, line_count()])


func _validate_paytable() -> void:
	for id: String in symbol_ids:
		if not paytable.has(id):
			errors.append("paytable에 %s 배당이 없음" % id)
	for id: String in paytable:
		if not symbol_ids.has(id):
			errors.append("paytable에 정의되지 않은 심볼 %s" % id)


func _validate_reels() -> void:
	if reels.size() != reel_count:
		errors.append("reels 개수(%d)가 reel_count(%d)와 다름" % [reels.size(), reel_count])
	for reel_index: int in reels.size():
		var strip: PackedStringArray = reels[reel_index]
		if strip.size() < visible_rows:
			errors.append("릴 %d 스트립이 보이는 행 수보다 짧음" % (reel_index + 1))
		for symbol: String in strip:
			if not symbol_ids.has(symbol):
				errors.append("릴 %d에 정의되지 않은 심볼 %s" % [reel_index + 1, symbol])


func _validate_lines() -> void:
	if lines.is_empty():
		errors.append("lines가 비어 있음")
	for line: LineDef in lines:
		if not LineDef.TYPES.has(line.type):
			errors.append("라인 %s의 type(%s)은 %s 중 하나여야 함" % [line.id, line.type, ", ".join(LineDef.TYPES)])
		if line.cells.size() < 2:
			errors.append("라인 %s의 칸이 2개 미만" % line.id)
		for cell: Vector2i in line.cells:
			if cell.x < 0 or cell.x >= reel_count or cell.y < 0 or cell.y >= visible_rows:
				errors.append("라인 %s의 칸 %s가 범위를 벗어남" % [line.id, cell])


func _validate_fever_and_pool() -> void:
	for symbol: String in fever_symbols:
		if not symbol_ids.has(symbol):
			errors.append("피버 대상에 정의되지 않은 심볼 %s" % symbol)
		if fever_initial_counts[symbol] <= 0:
			errors.append("피버 %s 초기 카운트는 1 이상이어야 함" % symbol)
	if pool_award_on_fever != "" and not fever_symbols.has(pool_award_on_fever):
		errors.append("pool.award_on_fever(%s)가 피버 대상이 아님" % pool_award_on_fever)
	if pool_contribution_rate < 0.0 or pool_contribution_rate > 1.0:
		errors.append("pool.contribution_rate는 0~1 사이여야 함")

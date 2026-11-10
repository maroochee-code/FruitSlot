extends Node
## 밸런스 시뮬레이션. 실행하면 BET별 통계·이론값(전수 계산)·베팅을 섞어 친 경우·밸런스 검사를 콘솔에 출력한다.
## 사용법: godot --headless --path . res://scenes/test/sim.tscn -- --spins=100000 --seed=12345 --bets=64,16,8
## 합격 판정은 이론값 기준이다. 시뮬레이션은 큰 당첨 한 방의 영향이 커서 10만 회 RTP도 약 ±1.9%p 흔들린다(교차 확인용).

## 기획서 10장 목표. 밸런스 수치가 아니라 검사 기준이다.
const TARGET_RTP_MIN: float = 92.0
const TARGET_RTP_MAX: float = 95.0
const TARGET_HIT_MIN: float = 25.0
const TARGET_HIT_MAX: float = 35.0
const TARGET_FEVER_MIN: float = 100.0
const TARGET_FEVER_MAX: float = 300.0
const TARGET_POOL_MIN: float = 2000.0
const TARGET_POOL_MAX: float = 5000.0
const LAST_ONE: int = 1

@export var spin_count: int = 100000
@export var rng_seed: int = 12345
## 차례로 돌릴 총 베팅 목록 (풀베팅 64, 중간 16, 피버·풀이 열리는 최소 8)
@export var bets: PackedInt32Array = [64, 16, 8]
## 베팅을 섞어 친 경우도 측정한다
@export var run_mixed: bool = true
## 화면 없이(--headless) 실행할 때만 끝나면 종료한다. 에디터·MCP 실행은 창을 열어 둔다.
@export var quit_when_headless: bool = true

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_read_args()
	var data: BalanceData = BalanceData.load_from_file()
	if data == null:
		push_error("sim: balance.json 로드 실패")
		_finish(1)
		return
	var started_ms: int = Time.get_ticks_msec()
	var theory: BalanceTheory = BalanceTheory.new(data)
	var rows: PackedStringArray = PackedStringArray()
	for bet: int in bets:
		rows.append(_run_bet(data, theory, bet))
	_print_summary(data, rows)
	if run_mixed:
		_print_mixed()
	_balance_check(data, theory)
	print("실행 시간      : %.2f초" % ((Time.get_ticks_msec() - started_ms) / 1000.0))
	_finish(1 if _failed > 0 else 0)


func _read_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var value: String = arg.get_slice("=", 1)
		if arg.begins_with("--spins="):
			spin_count = int(value)
		elif arg.begins_with("--seed="):
			rng_seed = int(value)
		elif arg.begins_with("--bets="):
			bets = PackedInt32Array()
			for text: String in value.split(",", false):
				bets.append(int(text))


## 같은 베팅으로 spin_count번 돌린 통계
func run_simulation(data: BalanceData, total_bet: int) -> SimStats:
	var logic: SlotLogic = SlotLogic.new(data, rng_seed)
	var stats: SimStats = SimStats.new(data)
	for i: int in spin_count:
		var result: SpinResult = logic.spin(total_bet)
		if result == null:
			break
		stats.record(result)
	return stats


## BET 하나: 시뮬레이션 보고서 + 이론값을 출력하고 요약표 한 줄을 돌려준다.
func _run_bet(data: BalanceData, theory: BalanceTheory, bet: int) -> String:
	var stats: SimStats = run_simulation(data, bet)
	var report: BalanceTheory.Report = theory.compute(bet)
	print(stats.build_report("SIM balance v%s / 시드 %d / BET %d" % [data.version, rng_seed, bet]))
	print(_theory_text(data, theory, report))
	print("")
	return "  %4d | %6.2f%% / %6.2f%% | %6.2f%% / %6.2f%% | %8s / %8s | %8s / %8s" % [
		bet, stats.rtp(), report.rtp, stats.hit_rate(), report.hit_rate,
		_spins_text(stats.fever_interval()), _spins_text(report.fever_interval),
		_spins_text(stats.pool_interval()), _spins_text(report.pool_interval)]


func _theory_text(data: BalanceData, theory: BalanceTheory, report: BalanceTheory.Report) -> String:
	var out: PackedStringArray = ["[이론값: 전수 계산, 같은 베팅으로 계속 칠 때]"]
	out.append("  RTP %.2f%% = 라인 %.2f + 피버 %.2f + 풀 %.2f / 히트 %.2f%%" % [
		report.rtp, report.line_rtp, report.fever_rtp, report.pool_rtp, report.hit_rate])
	var types: Dictionary[String, float] = theory.line_type_rtps(report.total_bet)
	out.append("  라인 RTP: 가로 %.2f / 세로 %.2f / 대각 %.2f" % [types["horizontal"], types["vertical"], types["diagonal"]])
	out.append("  피버 전체 평균 %s 스핀에 1회" % _spins_text(report.fever_interval))
	for symbol: String in data.fever_symbols:
		if report.fever_intervals.has(symbol):
			out.append("    %-7s : 평균 %8s 스핀에 1회 (RTP %5.2f%%)" % [
				symbol, _spins_text(report.fever_intervals[symbol]), report.fever_rtps[symbol]])
	out.append("  풀 평균 %s 스핀에 1회, 평균 획득액 %.0f" % [_spins_text(report.pool_interval), report.pool_average])
	return "\n".join(out)


func _print_summary(data: BalanceData, rows: PackedStringArray) -> void:
	print("==================== 요약 (balance v%s, %d회, 시드 %d) : 시뮬레이션 / 이론값 ====================" % [data.version, spin_count, rng_seed])
	print("   BET | RTP                | 히트 빈도          | 피버 간격(스핀)     | 풀 간격(스핀)")
	for row: String in rows:
		print(row)
	print("")


# ---------------------------------------------------------------- 베팅을 섞어 친 경우

## 보너스 기준(average / trigger)별로 같은 전략을 돌려 나란히 보여 준다. trigger는 비교용이며 파일은 바꾸지 않는다.
func _print_mixed() -> void:
	print("==================== 베팅을 섞어 친 경우 RTP (%d회, 시드 %d) ====================" % [spin_count, rng_seed])
	print("  전략                                         | average | trigger(비교용)")
	var labels: PackedStringArray = ["목록의 베팅을 한 판씩 번갈아", "첫 피버 심볼 1 남으면 최대, 평소 최소", "아무 피버 심볼 1 남으면 최대, 평소 최소"]
	for strategy: int in labels.size():
		print("  %-40s | %6.2f%% | %6.2f%%" % [
			labels[strategy], _mixed_rtp(BalanceData.FEVER_BASIS_AVERAGE, strategy), _mixed_rtp(BalanceData.FEVER_BASIS_TRIGGER, strategy)])
	print("")


func _mixed_rtp(basis: String, strategy: int) -> float:
	var data: BalanceData = BalanceData.load_from_file()
	data.fever_bonus_bet_basis = basis
	var logic: SlotLogic = SlotLogic.new(data, rng_seed)
	var stats: SimStats = SimStats.new(data)
	for i: int in spin_count:
		stats.record(logic.spin(_mixed_bet(data, logic, strategy, i)))
	return stats.rtp()


## 전략별 이번 판 베팅. 0 = 번갈아, 1 = 첫 피버 심볼만 노림, 2 = 깜빡이는 심볼 전부 노림
func _mixed_bet(data: BalanceData, logic: SlotLogic, strategy: int, index: int) -> int:
	if strategy == 0:
		return bets[index % bets.size()]
	var counts: Dictionary[String, int] = logic.get_fever_counts()
	for symbol: String in data.fever_symbols:
		if data.fever_initial_counts[symbol] > LAST_ONE and counts[symbol] == LAST_ONE:
			return data.max_total_bet
		if strategy == 1:
			break
	return data.fever_min_total_bet


# ---------------------------------------------------------------- 밸런스 검사 (이론값 기준)

func _balance_check(data: BalanceData, theory: BalanceTheory) -> void:
	print("==================== 밸런스 검사 (이론값, 기획서 10장 목표) ====================")
	var low: int = maxi(data.fever_min_total_bet, data.pool_min_total_bet)
	var lines: int = data.line_count()
	for bet: int in range(low, data.max_total_bet + 1):
		if bet % lines == 0:
			_check_range("BET %d RTP" % bet, theory.compute(bet).rtp, TARGET_RTP_MIN, TARGET_RTP_MAX, "%")
	var full: BalanceTheory.Report = theory.compute(data.max_total_bet)
	_check_range("히트 빈도", full.hit_rate, TARGET_HIT_MIN, TARGET_HIT_MAX, "%")
	_check_range("피버 발동 간격", full.fever_interval, TARGET_FEVER_MIN, TARGET_FEVER_MAX, "스핀")
	_check_range("풀 획득 간격", full.pool_interval, TARGET_POOL_MIN, TARGET_POOL_MAX, "스핀")
	_print_uneven_bets(data, theory, low)
	print("==================== BALANCE CHECK: %d 통과 / %d 실패 ====================" % [_passed, _failed])


## 라인마다 베팅이 고르지 않은 BET(라인 수의 배수가 아닌 값)은 참고로만 보여 준다 (판정 제외).
func _print_uneven_bets(data: BalanceData, theory: BalanceTheory, low: int) -> void:
	var outside: PackedStringArray = PackedStringArray()
	var top_bet: int = low
	var top_rtp: float = 0.0
	for bet: int in range(low, data.max_total_bet + 1):
		var rtp: float = theory.compute(bet).rtp
		if rtp > top_rtp:
			top_rtp = rtp
			top_bet = bet
		if bet % data.line_count() != 0 and (rtp < TARGET_RTP_MIN or rtp > TARGET_RTP_MAX):
			outside.append("%d(%.2f)" % [bet, rtp])
	print("  [참고·판정 제외] BET %d~%d 중 RTP 최고: BET %d = %.2f%%" % [low, data.max_total_bet, top_bet, top_rtp])
	print("  [참고·판정 제외] 라인 베팅이 고르지 않아 목표를 벗어나는 BET %d개: %s" % [outside.size(), ", ".join(outside)])


func _check_range(label: String, value: float, low: float, high: float, unit: String) -> void:
	var ok: bool = value >= low and value <= high
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("  [%s] %s %.2f%s (목표 %s~%s)" % ["PASS" if ok else "FAIL", label, value, unit, str(low), str(high)])


func _spins_text(interval: float) -> String:
	return "-" if interval <= 0.0 else "%.1f" % interval


func _finish(exit_code: int) -> void:
	if quit_when_headless and DisplayServer.get_name() == "headless":
		get_tree().quit(exit_code)

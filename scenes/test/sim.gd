extends Node
## 밸런스 시뮬레이션. 실행하면 통계를 콘솔에 출력하고 종료한다.

@export var spin_count: int = 100000
@export var rng_seed: int = 12345
## 풀베팅(8) 기준
@export var total_bet: int = 8
## 화면 없이(--headless) 실행할 때만 끝나면 종료한다. 에디터·MCP 실행은 창을 열어 둔다.
@export var quit_when_headless: bool = true


func _ready() -> void:
	var data: BalanceData = BalanceData.load_from_file()
	if data == null:
		push_error("sim: balance.json 로드 실패")
		_finish(1)
		return
	var started_ms: int = Time.get_ticks_msec()
	var stats: SimStats = run_simulation(data)
	var elapsed_ms: int = Time.get_ticks_msec() - started_ms
	var header: String = "SIM balance v%s / 시드 %d / BET %d" % [data.version, rng_seed, total_bet]
	print(stats.build_report(header))
	print("실행 시간      : %.2f초" % (elapsed_ms / 1000.0))
	_finish(0)


func run_simulation(data: BalanceData) -> SimStats:
	var logic: SlotLogic = SlotLogic.new(data, rng_seed)
	var stats: SimStats = SimStats.new(data)
	for i: int in spin_count:
		var result: SpinResult = logic.spin(total_bet)
		if result == null:
			break
		stats.record(result)
	return stats


func _finish(exit_code: int) -> void:
	if quit_when_headless and DisplayServer.get_name() == "headless":
		get_tree().quit(exit_code)

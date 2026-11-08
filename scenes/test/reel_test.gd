extends Node
## 릴 움직임 검증 (화면 없이): FeelConfig 읽기, ReelMotion, SpinController.
## STOP을 언제 어떤 순서로 누르든, 자동 정지든, 회전 중 START든 최종 정지 위치가 정해진 목표와 정확히 같은지 본다.

@export var motion_trials: int = 600
@export var controller_trials: int = 800

const TEST_SEED: int = 4242
const MAX_SIM_SEC: float = 40.0
const SPIKE_DT: float = 0.2
const SPIKE_CHANCE: float = 0.02
const DT_CHOICES: Array[float] = [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0]
const EPS: float = 1e-6

var _passed: int = 0
var _failed: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _strip_length: int = 32
var _file_feel: FeelConfig


func _ready() -> void:
	_rng.seed = TEST_SEED
	var data: BalanceData = BalanceData.load_from_file()
	_strip_length = data.reels[0].size()
	_file_feel = FeelConfig.load_from_file()
	_test_feel_config()
	_test_motion_random()
	_test_controller_random()
	_test_quick_stop_rules()
	_test_start_delay_and_speed()
	_test_auto_stop_schedule()
	_test_feel_snapshot_per_spin()
	print("==================== REEL TEST: %d 통과 / %d 실패 ====================" % [_passed, _failed])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", label)


## 프레임 간격 하나를 고른다 (30/60/144fps 또는 가끔 0.2초 튀는 프레임, 불규칙 간격)
func _next_dt(mode: int) -> float:
	if _rng.randf() < SPIKE_CHANCE:
		return SPIKE_DT
	if mode < DT_CHOICES.size():
		return DT_CHOICES[mode]
	return _rng.randf_range(0.002, 0.05)


## 값이 모두 범위 안인 무작위 손맛 설정 (설정 파일을 어떻게 고쳐도 목표에서 멈추는지 보려는 용도)
func _random_feel() -> FeelConfig:
	var raw: Dictionary = {}
	raw["spin_speed"] = _rng.randf_range(8.0, 60.0)
	raw["accel_time"] = 0.0 if _rng.randf() < 0.2 else _rng.randf_range(0.02, 1.0)
	raw["slide_cells"] = _rng.randf_range(0.6, 6.0)
	raw["slide_ease_power"] = _rng.randf_range(1.0, 6.0)
	raw["bounce_cells"] = 0.0 if _rng.randf() < 0.3 else _rng.randf_range(0.02, 0.6)
	raw["bounce_time"] = 0.0 if _rng.randf() < 0.2 else _rng.randf_range(0.02, 0.5)
	# 출발 지연은 자동 정지 시작(최소 0.5초)보다 짧게, 속도 배율은 범위 전체에서 고른다
	raw["reel_start_delay"] = [_rng.randf_range(0.0, 0.45), _rng.randf_range(0.0, 0.45), _rng.randf_range(0.0, 0.45)]
	raw["reel_speed_scale"] = [_rng.randf_range(0.5, 1.5), _rng.randf_range(0.5, 1.5), _rng.randf_range(0.5, 1.5)]
	raw["auto_stop_start"] = _rng.randf_range(0.5, 4.0)
	raw["auto_stop_interval"] = _rng.randf_range(0.0, 1.0)
	raw["quick_stop_interval"] = _rng.randf_range(0.0, 0.5)
	raw["start_lock_sec"] = _rng.randf_range(0.0, 0.6)
	raw["result_delay"] = 0.25
	return FeelConfig.from_dict(raw)


## STOP 요청 후 멈출 때까지 걸릴 수 있는 최대 시간 (가속 + 한 바퀴 + 감속 + 튕김 + 프레임 오차)
## speed는 그 릴의 실제 속도(칸/초). 릴별 배율이 있으면 가장 느린 릴 기준으로 넘긴다.
func _stop_bound(feel: FeelConfig, speed: float) -> float:
	var lap: float = float(_strip_length) / speed
	var decel: float = feel.slide_ease_power * (feel.slide_cells + feel.bounce_cells) / speed
	return feel.accel_time + lap + decel + feel.bounce_time + SPIKE_DT + 0.01


# ---------------------------------------------------------------- FeelConfig

func _test_feel_config() -> void:
	_check(_file_feel.errors.is_empty(), "data/feel.json: 모든 항목이 있고 범위 안 (문제: %s)" % ", ".join(_file_feel.errors))
	var defaults: FeelConfig = FeelConfig.from_dict({})
	_check(defaults.errors.size() == FeelConfig.SPECS.size() + FeelConfig.ARRAY_SPECS.size(), "빈 설정이면 모든 항목이 기본값으로 대체되고 문제로 기록됨")
	_check(_file_feel.reel_speed_scale == PackedFloat64Array([1.0, 0.95, 1.05]), "data/feel.json: 릴별 속도 배율 기본값 [1.0, 0.95, 1.05]")
	_check(_file_feel.reel_start_delay.size() == 3 and _file_feel.reel_start_delay[0] == 0.0, "data/feel.json: 릴별 출발 지연 3개, 릴1은 지연 없음")
	_check(not "half_row" in _file_feel and not FeelConfig.SPECS.has("half_row"), "half_row 항목이 사라짐")
	var array_bad: FeelConfig = FeelConfig.from_dict({"reel_start_delay": [0.1, 0.2], "reel_speed_scale": [1.0, 9.0, 1.0]})
	_check(array_bad.reel_start_delay == PackedFloat64Array(FeelConfig.ARRAY_SPECS["reel_start_delay"][0]), "릴 개수가 안 맞는 목록은 통째로 기본값")
	_check(array_bad.reel_speed_scale == PackedFloat64Array(FeelConfig.ARRAY_SPECS["reel_speed_scale"][0]), "목록 안에 범위 밖 값이 하나라도 있으면 통째로 기본값")
	var array_text: FeelConfig = FeelConfig.from_dict({"reel_start_delay": "빠르게", "reel_speed_scale": [1, "a", 1]})
	_check(array_text.errors.size() >= 2, "목록이 아니거나 숫자가 아닌 값은 문제로 기록됨")
	var array_good: FeelConfig = FeelConfig.from_dict({"reel_start_delay": [0, 0.3, 0.5], "reel_speed_scale": [1, 1.5, 0.5]})
	_check(array_good.reel_start_delay == PackedFloat64Array([0.0, 0.3, 0.5]) and array_good.reel_speed_scale == PackedFloat64Array([1.0, 1.5, 0.5]), "범위 안 목록(정수 포함)은 그대로 읽음")
	var too_late: FeelConfig = FeelConfig.from_dict({"auto_stop_start": 0.1, "reel_start_delay": [0.0, 0.1, 0.4]})
	_check(too_late.reel_start_delay == PackedFloat64Array([0.0, 0.0, 0.0]) and too_late.errors.size() > 0, "출발 지연이 자동 정지 시작보다 늦으면 지연을 쓰지 않고 문제로 기록 (기본 지연도 안 맞으면 0)")
	var slightly_late: FeelConfig = FeelConfig.from_dict({"auto_stop_start": 0.3, "reel_start_delay": [0.0, 0.1, 0.4]})
	_check(slightly_late.reel_start_delay == PackedFloat64Array([0.0, 0.08, 0.16]), "출발 지연이 너무 늦으면 기본 지연으로 대체")
	var bad: FeelConfig = FeelConfig.from_dict({"spin_speed": -5, "accel_time": "빠르게", "slide_cells": 0.1})
	_check(bad.spin_speed == FeelConfig.SPECS["spin_speed"][0], "범위 밖 spin_speed는 기본값")
	_check(bad.accel_time == FeelConfig.SPECS["accel_time"][0], "숫자가 아닌 accel_time은 기본값")
	_check(bad.slide_cells == FeelConfig.SPECS["slide_cells"][0], "범위 밖 slide_cells는 기본값")
	var good: FeelConfig = FeelConfig.from_dict({"spin_speed": 40, "bounce_cells": 0})
	_check(good.spin_speed == 40.0 and good.bounce_cells == 0.0, "범위 안 값(정수 포함)은 그대로 읽음")
	_check(_file_feel.slide_cells + _file_feel.bounce_cells < float(_strip_length), "감속 구간이 스트립 길이보다 짧음")


# ---------------------------------------------------------------- ReelMotion

func _test_motion_random() -> void:
	var wrong_stop: int = 0
	var early_stop: int = 0
	var too_slow: int = 0
	var teleport: int = 0
	var multi_signal: int = 0
	var never_stopped: int = 0
	for trial: int in motion_trials:
		var feel: FeelConfig = _file_feel if trial % 2 == 0 else _random_feel()
		var start_pos: int = _rng.randi_range(0, _strip_length - 1)
		var target: int = _rng.randi_range(0, _strip_length - 1)
		var motion: ReelMotion = ReelMotion.new(_strip_length, feel, start_pos)
		var stop_count: Array[int] = [0]
		motion.stopped.connect(func() -> void: stop_count[0] += 1)
		var speed_scale: float = _rng.randf_range(0.5, 1.5)
		motion.start(target, null, speed_scale)
		var speed: float = feel.spin_speed * speed_scale
		var press_time: float = _rng.randf_range(0.0, 5.0)
		var dt_mode: int = _rng.randi_range(0, DT_CHOICES.size())
		var time: float = 0.0
		var pressed_at: float = -1.0
		while time < MAX_SIM_SEC and motion.is_spinning():
			var dt: float = _next_dt(dt_mode)
			if pressed_at < 0.0 and time >= press_time:
				motion.request_stop()
				pressed_at = time
			var before: float = motion.position
			var phase_before: ReelMotion.Phase = motion.phase
			motion.advance(dt)
			time += dt
			if phase_before == ReelMotion.Phase.SPINNING or phase_before == ReelMotion.Phase.WAITING:
				if motion.phase == phase_before:
					var moved: float = fposmod(before - motion.position, float(_strip_length))
					if moved > speed * dt + EPS:
						teleport += 1
		if motion.is_spinning():
			never_stopped += 1
			continue
		if stop_count[0] != 1:
			multi_signal += 1
		if motion.position != float(target):
			wrong_stop += 1
		if pressed_at < 0.0 or time < pressed_at:
			early_stop += 1
		elif time - pressed_at > _stop_bound(feel, speed):
			too_slow += 1
	_check(never_stopped == 0, "ReelMotion: STOP을 누르면 반드시 멈춤 (안 멈춘 횟수 %d)" % never_stopped)
	_check(wrong_stop == 0, "ReelMotion: 최종 위치 == 목표 정확히 일치 (%d회 시도, 불일치 %d)" % [motion_trials, wrong_stop])
	_check(multi_signal == 0, "ReelMotion: stopped 신호가 정확히 1번 (어긋난 횟수 %d)" % multi_signal)
	_check(early_stop == 0, "ReelMotion: STOP 누르기 전에는 멈추지 않음 (%d)" % early_stop)
	_check(too_slow == 0, "ReelMotion: STOP 후 한 바퀴+감속 시간 안에 멈춤 (초과 %d)" % too_slow)
	_check(teleport == 0, "ReelMotion: 회전 중 한 프레임 이동량이 속도×시간을 넘지 않음 (순간이동 %d)" % teleport)


# ---------------------------------------------------------------- SpinController

func _test_controller_random() -> void:
	var wrong_stop: int = 0
	var signal_errors: int = 0
	var early_stop: int = 0
	var late_stop: int = 0
	var quick_mismatch: int = 0
	var never_done: int = 0
	var manual_reject: int = 0
	var delay_errors: int = 0
	var speed_errors: int = 0
	for trial: int in controller_trials:
		var feel: FeelConfig = _file_feel if trial % 2 == 0 else _random_feel()
		var motions: Array[ReelMotion] = []
		var targets: PackedInt32Array = PackedInt32Array()
		for i: int in 3:
			motions.append(ReelMotion.new(_strip_length, feel, _rng.randi_range(0, _strip_length - 1)))
			targets.append(_rng.randi_range(0, _strip_length - 1))
		var controller: SpinController = SpinController.new(motions, feel)
		var stop_times: Array[float] = [-1.0, -1.0, -1.0]
		var stop_counts: Array[int] = [0, 0, 0]
		var all_count: Array[int] = [0]
		var clock: Array[float] = [0.0]
		controller.reel_stopped.connect(func(index: int) -> void:
			stop_times[index] = clock[0]
			stop_counts[index] += 1)
		controller.all_stopped.connect(func() -> void: all_count[0] += 1)
		# 입력 계획: 릴마다 STOP을 누를 시각(없으면 -1), 회전 중 START를 누를 시각(없으면 -1)
		var manual_at: Array[float] = []
		for i: int in 3:
			manual_at.append(_rng.randf_range(0.0, 5.0) if _rng.randf() < 0.5 else -1.0)
		var quick_at: float = _rng.randf_range(0.0, 4.5) if _rng.randf() < 0.4 else -1.0
		var accepted_at: Array[float] = [INF, INF, INF]
		var quick_accepted_at: float = INF
		var dt_mode: int = _rng.randi_range(0, DT_CHOICES.size())
		controller.begin(targets)
		var departed_at: Array[float] = [-1.0, -1.0, -1.0]
		var time: float = 0.0
		var quick_done: bool = false
		while time < MAX_SIM_SEC and controller.is_active():
			var dt: float = _next_dt(dt_mode)
			var order: Array[int] = [0, 1, 2]
			order.shuffle()
			for i: int in order:
				if manual_at[i] >= 0.0 and time >= manual_at[i]:
					manual_at[i] = -1.0
					var could: bool = controller.can_stop(i)
					var ok: bool = controller.press_stop(i)
					if ok != could:
						manual_reject += 1
					if could and not controller.has_started(i):
						delay_errors += 1
					if ok:
						accepted_at[i] = time
			if quick_at >= 0.0 and not quick_done and time >= quick_at:
				quick_done = true
				var expected: bool = controller.can_quick_stop() and controller.elapsed() >= feel.start_lock_sec
				var got: bool = controller.press_quick_stop()
				if got != expected:
					quick_mismatch += 1
				if got:
					quick_accepted_at = time
			clock[0] = time + dt
			controller.advance(dt)
			time += dt
			for i: int in 3:
				if departed_at[i] < 0.0 and motions[i].is_spinning():
					departed_at[i] = time
		if controller.is_active():
			never_done += 1
			continue
		if all_count[0] != 1 or stop_counts != [1, 1, 1]:
			signal_errors += 1
		for i: int in 3:
			if motions[i].position != float(targets[i]) or motions[i].is_spinning():
				wrong_stop += 1
			var earliest: float = minf(minf(accepted_at[i], quick_accepted_at), feel.auto_stop_start + i * feel.auto_stop_interval)
			if stop_times[i] < earliest:
				early_stop += 1
			# 출발은 지연 시각 이후 첫 프레임에서만, 정지는 출발 이후에만
			var delay: float = feel.reel_start_delay[i]
			# (출발한 프레임에 곧바로 멈춘 극단적인 경우는 정지 시각을 출발 시각으로 본다)
			var departed: float = departed_at[i] if departed_at[i] >= 0.0 else stop_times[i]
			if departed < delay or departed > delay + SPIKE_DT + EPS or stop_times[i] < departed:
				delay_errors += 1
			if not is_equal_approx(motions[i].current_speed(), feel.spin_speed * feel.reel_speed_scale[i]):
				speed_errors += 1
		var slowest: float = feel.spin_speed * minf(minf(feel.reel_speed_scale[0], feel.reel_speed_scale[1]), feel.reel_speed_scale[2])
		var latest_request: float = feel.auto_stop_start + 2.0 * feel.auto_stop_interval
		if controller.elapsed() > latest_request + _stop_bound(feel, slowest) + SPIKE_DT:
			late_stop += 1
	_check(never_done == 0, "SpinController: 어떤 입력이든 결국 모든 릴이 멈춤 (안 멈춘 횟수 %d)" % never_done)
	_check(wrong_stop == 0, "SpinController: 모든 릴이 정해진 정지 위치에 정확히 섬 (%d회 스핀, 불일치 %d)" % [controller_trials, wrong_stop])
	_check(signal_errors == 0, "SpinController: reel_stopped 릴당 1번, all_stopped 1번 (어긋난 횟수 %d)" % signal_errors)
	_check(early_stop == 0, "SpinController: 요청(STOP·START·자동) 시각보다 먼저 멈추지 않음 (%d)" % early_stop)
	_check(late_stop == 0, "SpinController: 자동 정지 시각 + 최대 대기 안에 전부 멈춤 (%d)" % late_stop)
	_check(manual_reject == 0, "SpinController: can_stop과 press_stop 결과가 일치 (%d)" % manual_reject)
	_check(delay_errors == 0, "SpinController: 릴은 지연 시각 이후에 출발하고, 출발 전에는 STOP을 못 받으며, 정지는 출발 이후 (%d)" % delay_errors)
	_check(speed_errors == 0, "SpinController: 릴별 회전 속도 = spin_speed × 릴별 배율 (%d)" % speed_errors)
	_check(quick_mismatch == 0, "SpinController: 회전 중 START 수락 조건(잠금 시간·남은 릴)이 규칙과 일치 (%d)" % quick_mismatch)


## 회전 중 START 규칙: 잠금 안에서는 무시, 이후에는 남은 릴을 왼쪽부터 간격을 두고 차례로 정지, 두 번째 누름은 무시
func _test_quick_stop_rules() -> void:
	var feel: FeelConfig = FeelConfig.from_dict({
		"spin_speed": 26, "accel_time": 0.25, "slide_cells": 3, "slide_ease_power": 3,
		"bounce_cells": 0.15, "bounce_time": 0.14,
		"reel_start_delay": [0.0, 0.0, 0.0], "reel_speed_scale": [1.0, 1.0, 1.0],
		"auto_stop_start": 30, "auto_stop_interval": 0.4, "quick_stop_interval": 0.5,
		"start_lock_sec": 0.3, "result_delay": 0.25,
	})
	var motions: Array[ReelMotion] = []
	for i: int in 3:
		motions.append(ReelMotion.new(_strip_length, feel))
	var controller: SpinController = SpinController.new(motions, feel)
	var order: Array[int] = []
	controller.reel_stopped.connect(func(index: int) -> void: order.append(index))
	controller.begin(PackedInt32Array([5, 9, 20]))
	controller.advance(0.1)
	_check(not controller.press_quick_stop(), "시작 직후(잠금 시간 안)의 START는 무시")
	controller.advance(0.3)
	_check(controller.press_stop(1), "릴2를 먼저 STOP")
	_check(controller.press_quick_stop(), "잠금이 풀린 뒤 START는 받아들임")
	_check(not controller.press_quick_stop(), "회전 중 START를 또 눌러도 무시")
	var guard: int = 0
	while controller.is_active() and guard < 4000:
		controller.advance(1.0 / 60.0)
		guard += 1
	_check(not controller.is_active(), "회전 중 START 후 모든 릴이 멈춤")
	_check(motions[0].position == 5.0 and motions[1].position == 9.0 and motions[2].position == 20.0, "회전 중 START 후 정지 위치 = 목표")
	_check(order.size() == 3 and order[0] == 1, "먼저 누른 릴2가 가장 먼저 멈춤 (순서 %s)" % str(order))
	var left_before_right: bool = order.find(0) < order.find(2)
	_check(left_before_right, "남은 릴은 왼쪽(릴1)부터 차례로 정지 (순서 %s)" % str(order))


## 릴별 출발 지연·속도차를 정해진 값으로 하나씩 확인한다.
func _test_start_delay_and_speed() -> void:
	var feel: FeelConfig = FeelConfig.from_dict({
		"spin_speed": 26, "accel_time": 0.25, "auto_stop_start": 30, "start_lock_sec": 0.3,
		"reel_start_delay": [0.0, 0.2, 0.4], "reel_speed_scale": [1.0, 0.9, 1.1],
	})
	var motions: Array[ReelMotion] = []
	for i: int in 3:
		motions.append(ReelMotion.new(_strip_length, feel))
	var controller: SpinController = SpinController.new(motions, feel)
	var stop_times: Array[float] = [-1.0, -1.0, -1.0]
	var clock: Array[float] = [0.0]
	var all_count: Array[int] = [0]
	controller.reel_stopped.connect(func(index: int) -> void: stop_times[index] = clock[0])
	controller.all_stopped.connect(func() -> void: all_count[0] += 1)
	var start_counts: Array[int] = [0, 0, 0]
	controller.reel_started.connect(func(index: int) -> void: start_counts[index] += 1)
	controller.begin(PackedInt32Array([5, 9, 20]))
	_check(start_counts == [1, 0, 0], "reel_started: START 순간에는 릴1에 대해서만 한 번")
	_check(controller.has_started(0) and not controller.has_started(1) and not controller.has_started(2), "START 순간 지연 0인 릴1만 출발")
	_check(not controller.can_stop(1) and not controller.press_stop(1), "출발 전 릴2의 STOP은 받지 않음")
	_check(motions[1].position == 0.0 and not motions[1].is_spinning(), "출발 전 릴2는 움직이지 않음")
	clock[0] = 0.25
	controller.advance(0.25)
	_check(controller.has_started(1) and not controller.has_started(2), "0.25초: 릴2(지연 0.2) 출발, 릴3(지연 0.4)은 대기")
	# 릴2는 0.2초에 출발했으니 이번 프레임에서는 0.05초만 달린 것으로 계산된다 (가속 구간: 거리 = 속도/(2×가속시간) × t²)
	var speed2: float = 26.0 * 0.9
	var expected: float = fposmod(-speed2 / (2.0 * 0.25) * pow(0.05, 2.0), float(_strip_length))
	_check(absf(motions[1].position - expected) < EPS, "프레임 중간에 출발한 릴은 출발 순간부터의 시간만큼만 움직임 (%.5f vs %.5f)" % [motions[1].position, expected])
	_check(is_equal_approx(motions[0].current_speed(), 26.0) and is_equal_approx(motions[1].current_speed(), speed2), "릴1 속도 26, 릴2 속도 26×0.9")
	_check(controller.can_stop(1) and not controller.can_stop(2), "출발한 릴2는 STOP 가능, 대기 중인 릴3은 불가")
	clock[0] = 0.35
	controller.advance(0.1)
	_check(controller.press_quick_stop(), "릴3이 출발 전이어도 회전 중 START는 받아들임")
	_check(not controller.has_started(2), "릴3은 아직 출발 전 (0.35초)")
	var guard: int = 0
	while controller.is_active() and guard < 6000:
		clock[0] += 1.0 / 60.0
		controller.advance(1.0 / 60.0)
		guard += 1
	_check(not controller.is_active() and all_count[0] == 1, "출발 전 릴이 섞인 회전 중 START 뒤에도 모든 릴이 멈추고 all_stopped는 1번")
	_check(motions[0].position == 5.0 and motions[1].position == 9.0 and motions[2].position == 20.0, "출발 지연·속도차가 있어도 정지 위치 = 목표")
	_check(start_counts == [1, 1, 1], "reel_started: 릴마다 정확히 한 번")
	_check(stop_times[2] > 0.4,"릴3은 출발(0.4초) 전에 멈추지 않음 (%.2f초)" % stop_times[2])
	_check(is_equal_approx(motions[2].current_speed(), 26.0 * 1.1), "릴3 속도 26×1.1")


## 아무것도 누르지 않으면 START 기준 auto_stop_start 이후 왼쪽부터 간격을 두고 멈추기 시작한다.
func _test_auto_stop_schedule() -> void:
	var motions: Array[ReelMotion] = []
	for i: int in 3:
		motions.append(ReelMotion.new(_strip_length, _file_feel))
	var controller: SpinController = SpinController.new(motions, _file_feel)
	var times: Array[float] = [-1.0, -1.0, -1.0]
	var clock: Array[float] = [0.0]
	controller.reel_stopped.connect(func(index: int) -> void: times[index] = clock[0])
	controller.begin(PackedInt32Array([0, 11, 22]))
	var guard: int = 0
	while controller.is_active() and guard < 6000:
		clock[0] += 1.0 / 60.0
		controller.advance(1.0 / 60.0)
		guard += 1
	_check(times[0] >= _file_feel.auto_stop_start, "자동 정지: 릴1은 %.1f초 이후에 멈춤 (%.2f)" % [_file_feel.auto_stop_start, times[0]])
	_check(times[1] >= _file_feel.auto_stop_start + _file_feel.auto_stop_interval, "자동 정지: 릴2는 릴1 요청보다 간격만큼 뒤 이후")
	_check(times[2] >= _file_feel.auto_stop_start + 2.0 * _file_feel.auto_stop_interval, "자동 정지: 릴3은 가장 뒤 이후")
	_check(motions[0].position == 0.0 and motions[1].position == 11.0 and motions[2].position == 22.0, "자동 정지 후 위치 = 목표")


## 스핀마다 설정 한 벌: begin(stops, feel)로 받은 설정만 그 스핀에 쓰이고, 이전 설정은 영향이 없다.
func _test_feel_snapshot_per_spin() -> void:
	var slow: FeelConfig = FeelConfig.from_dict({ "auto_stop_start": 5.0, "auto_stop_interval": 1.0 })
	var fast: FeelConfig = FeelConfig.from_dict({ "auto_stop_start": 0.5, "auto_stop_interval": 0.1, "spin_speed": 60 })
	var motions: Array[ReelMotion] = []
	for i: int in 3:
		motions.append(ReelMotion.new(_strip_length, slow))
	var controller: SpinController = SpinController.new(motions, slow)
	var times: Array[float] = [-1.0, -1.0, -1.0]
	var clock: Array[float] = [0.0]
	controller.reel_stopped.connect(func(index: int) -> void: times[index] = clock[0])
	controller.begin(PackedInt32Array([1, 2, 3]), fast)
	var guard: int = 0
	while controller.is_active() and guard < 6000:
		clock[0] += 1.0 / 60.0
		controller.advance(1.0 / 60.0)
		guard += 1
	_check(times[2] < 5.0 and times[0] >= 0.5, "begin(stops, feel): 받은 설정(0.5초 자동 정지)이 그 스핀에 쓰임 (릴3 %.2f초)" % times[2])
	_check(motions[0].position == 1.0 and motions[1].position == 2.0 and motions[2].position == 3.0, "설정을 바꿔도 정지 위치 = 목표")
	clock[0] = 0.0
	for i: int in 3:
		times[i] = -1.0
	controller.begin(PackedInt32Array([4, 5, 6]), slow)
	guard = 0
	while controller.is_active() and guard < 6000:
		clock[0] += 1.0 / 60.0
		controller.advance(1.0 / 60.0)
		guard += 1
	_check(times[0] >= 5.0, "다음 스핀에 옛 설정(5초 자동 정지)을 주면 그대로 따름 (릴1 %.2f초)" % times[0])

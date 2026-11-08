class_name SpinController
extends RefCounted
## 스핀 한 번의 진행을 관리한다: 릴 3개 출발(릴별 시간차), STOP, 자동 정지, 회전 중 START(남은 릴 차례로 정지).
## 정지 위치(결과)는 begin()에 받은 값 그대로이며, 여기서는 "언제 출발하고 언제 멈추기 시작하느냐"만 정한다.
## 모든 시각은 START(begin) 기준이다. 아직 출발하지 않은 릴은 STOP을 받지 않고, 출발하자마자 예약된 정지를 처리한다.

signal reel_started(index: int)
signal reel_stopped(index: int)
signal all_stopped

var motions: Array[ReelMotion] = []

var _feel: FeelConfig
var _elapsed: float = 0.0
var _active: bool = false
var _quick_pressed: bool = false
## 릴별 STOP 요청 예약 시각 (START 기준). 없으면 INF
var _scheduled: PackedFloat64Array = PackedFloat64Array()
var _requested: Array[bool] = []
## 릴별 출발 시각 (START 기준)과 출발했는지
var _start_at: PackedFloat64Array = PackedFloat64Array()
var _started: Array[bool] = []
## 릴별 정지 위치 (begin에서 받은 값 그대로, 출발할 때 ReelMotion에 넘김)
var _stops: PackedInt32Array = PackedInt32Array()


func _init(reel_motions: Array[ReelMotion], feel: FeelConfig) -> void:
	motions = reel_motions
	_feel = feel
	for i: int in motions.size():
		_scheduled.append(INF)
		_requested.append(false)
		_start_at.append(0.0)
		_started.append(false)
		motions[i].stopped.connect(_on_motion_stopped.bind(i))


func is_active() -> bool:
	return _active


func elapsed() -> float:
	return _elapsed


## 이 릴이 이번 스핀에서 이미 출발했는지 (출발 지연 중이면 false)
func has_started(index: int) -> bool:
	return _started[index]


## 스핀 시작. stops는 릴별 정지 위치(START 때 로직이 정한 값).
## feel을 주면 이 스핀 전체가 그 설정 한 벌로만 움직인다 (스핀 도중 설정 교체 없음).
func begin(stops: PackedInt32Array, feel: FeelConfig = null) -> void:
	if feel != null:
		_feel = feel
	_elapsed = 0.0
	_active = true
	_quick_pressed = false
	_stops = stops.duplicate()
	for i: int in motions.size():
		_requested[i] = false
		_started[i] = false
		_scheduled[i] = _feel.auto_stop_start + i * _feel.auto_stop_interval
		_start_at[i] = _feel.reel_start_delay[i]
	_start_due_reels()


## 이 릴의 STOP을 지금 받을 수 있는지 (버튼 활성 조건). 출발 전에는 받지 않는다.
func can_stop(index: int) -> bool:
	return _active and not _requested[index] and _started[index] and motions[index].is_spinning()


## 회전 중 START를 지금 받을 수 있는지
func can_quick_stop() -> bool:
	if not _active or _quick_pressed:
		return false
	for i: int in motions.size():
		if not _requested[i]:
			return true
	return false


func press_stop(index: int) -> bool:
	if not can_stop(index):
		return false
	return _request(index)


## 회전 중 START: 아직 멈추라고 하지 않은 릴을 왼쪽부터 일정 간격으로 차례로 멈춘다.
## 시작 직후 잠금 시간 안이면 무시한다 (스페이스 연타 방지).
## 아직 출발 전인 릴도 같은 순서로 예약되며, 출발하는 즉시 정지 요청이 들어간다.
func press_quick_stop() -> bool:
	if not can_quick_stop() or _elapsed < _feel.start_lock_sec:
		return false
	_quick_pressed = true
	var order: int = 0
	for i: int in motions.size():
		if not _requested[i]:
			_scheduled[i] = minf(_scheduled[i], _elapsed + order * _feel.quick_stop_interval)
			order += 1
	return true


func advance(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	# 이번 프레임 안에서 릴이 실제로 움직인 시간 (이번 프레임에 출발한 릴은 출발 순간부터만)
	var run_time: PackedFloat64Array = PackedFloat64Array()
	for i: int in motions.size():
		run_time.append(delta)
		if not _started[i] and _start_at[i] <= _elapsed:
			run_time[i] = _elapsed - _start_at[i]
			_start_reel(i)
	for i: int in motions.size():
		if _started[i] and not _requested[i] and _scheduled[i] <= _elapsed:
			_request(i)
	for i: int in motions.size():
		if _started[i]:
			motions[i].advance(run_time[i])


func _start_due_reels() -> void:
	for i: int in motions.size():
		if not _started[i] and _start_at[i] <= _elapsed:
			_start_reel(i)


func _start_reel(index: int) -> void:
	_started[index] = true
	motions[index].start(_stops[index], _feel, _feel.reel_speed_scale[index])
	reel_started.emit(index)


func _request(index: int) -> bool:
	_requested[index] = true
	_scheduled[index] = INF
	return motions[index].request_stop()


func _on_motion_stopped(index: int) -> void:
	reel_stopped.emit(index)
	for i: int in motions.size():
		if not _started[i] or motions[i].is_spinning():
			return
	_active = false
	all_stopped.emit()

class_name SpinController
extends RefCounted
## 스핀 한 번의 진행을 관리한다: 릴 3개 시작, STOP, 자동 정지, 회전 중 START(남은 릴 차례로 정지).
## 정지 위치(결과)는 begin()에 받은 값 그대로이며, 여기서는 "언제 멈추기 시작하느냐"만 정한다.

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


func _init(reel_motions: Array[ReelMotion], feel: FeelConfig) -> void:
	motions = reel_motions
	_feel = feel
	for i: int in motions.size():
		_scheduled.append(INF)
		_requested.append(false)
		motions[i].stopped.connect(_on_motion_stopped.bind(i))


func is_active() -> bool:
	return _active


func elapsed() -> float:
	return _elapsed


## 스핀 시작. stops는 릴별 정지 위치(START 때 로직이 정한 값).
## feel을 주면 이 스핀 전체가 그 설정 한 벌로만 움직인다 (스핀 도중 설정 교체 없음).
func begin(stops: PackedInt32Array, feel: FeelConfig = null) -> void:
	if feel != null:
		_feel = feel
	_elapsed = 0.0
	_active = true
	_quick_pressed = false
	for i: int in motions.size():
		_requested[i] = false
		_scheduled[i] = _feel.auto_stop_start + i * _feel.auto_stop_interval
		motions[i].start(stops[i], _feel)


## 이 릴의 STOP을 지금 받을 수 있는지 (버튼 활성 조건)
func can_stop(index: int) -> bool:
	return _active and not _requested[index] and motions[index].is_spinning()


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
	for i: int in motions.size():
		if not _requested[i] and _scheduled[i] <= _elapsed:
			_request(i)
	for motion: ReelMotion in motions:
		motion.advance(delta)


func _request(index: int) -> bool:
	_requested[index] = true
	_scheduled[index] = INF
	return motions[index].request_stop()


func _on_motion_stopped(index: int) -> void:
	reel_stopped.emit(index)
	for motion: ReelMotion in motions:
		if motion.is_spinning():
			return
	_active = false
	all_stopped.emit()

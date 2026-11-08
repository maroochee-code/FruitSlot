class_name ReelMotion
extends RefCounted
## 릴 하나의 움직임 계산. 화면(Node)과 무관하고, advance(시간)만 부르면 굴러간다.
## position은 "윗줄에 보이는 스트립 번호(소수)"이고 회전 중에는 값이 줄어든다 (심볼이 아래로 흐름).
## 목표(target)는 START 순간 로직이 정한 정지 위치다. 이 클래스는 거기까지 가는 모양만 정하고,
## 마지막에는 항상 정확히 target으로 맞춘다. (결과를 바꾸지 않는다.)

signal stopped

enum Phase { IDLE, SPINNING, WAITING, DECEL, BOUNCE }

var phase: Phase = Phase.IDLE
var position: float = 0.0
var target: int = 0
var strip_length: int = 1

var _feel: FeelConfig
var _spin_time: float = 0.0
var _stop_requested: bool = false
var _phase_time: float = 0.0
var _decel_start: float = 0.0
var _decel_total: float = 0.0
var _decel_duration: float = 0.0


func _init(length: int, feel: FeelConfig, start_position: int = 0) -> void:
	strip_length = length
	_feel = feel
	position = float(posmod(start_position, length))
	target = posmod(start_position, length)


func is_spinning() -> bool:
	return phase != Phase.IDLE


func is_stop_requested() -> bool:
	return _stop_requested


## 회전 시작. new_target은 멈출 스트립 번호. feel을 주면 이 스핀부터 그 설정을 쓴다.
## 스핀이 진행되는 동안에는 설정이 바뀌지 않는다 (바꾸려면 다음 start에서).
func start(new_target: int, feel: FeelConfig = null) -> void:
	if feel != null:
		_feel = feel
	target = posmod(new_target, strip_length)
	_spin_time = 0.0
	_phase_time = 0.0
	_stop_requested = false
	phase = Phase.SPINNING


## STOP. 받아들여지면 true. 이미 요청했거나 회전 중이 아니면 false.
func request_stop() -> bool:
	if phase != Phase.SPINNING or _stop_requested:
		return false
	_stop_requested = true
	return true


func advance(delta: float) -> void:
	var left: float = delta
	var guard: int = 0
	while left > 0.0 and phase != Phase.IDLE and guard < 16:
		guard += 1
		match phase:
			Phase.SPINNING:
				left = _advance_spinning(left)
			Phase.WAITING:
				left = _advance_waiting(left)
			Phase.DECEL:
				left = _advance_decel(left)
			Phase.BOUNCE:
				left = _advance_bounce(left)
	if phase != Phase.IDLE:
		position = fposmod(position, float(strip_length))


## 가속 → 일정 속도. STOP이 요청돼 있고 최고 속도에 도달했으면 WAITING으로 넘어간다.
func _advance_spinning(left: float) -> float:
	if _spin_time < _feel.accel_time:
		var remaining: float = _feel.accel_time - _spin_time
		var step: float = minf(left, remaining)
		position -= _feel.spin_speed / (2.0 * _feel.accel_time) * (pow(_spin_time + step, 2.0) - pow(_spin_time, 2.0))
		_spin_time = _feel.accel_time if left >= remaining else _spin_time + step
		return left - step
	if _stop_requested:
		phase = Phase.WAITING
		return left
	position -= _feel.spin_speed * left
	_spin_time += left
	return 0.0


## 목표가 "감속 구간 길이"만큼 앞에 올 때까지 같은 속도로 더 흐른 뒤 감속을 시작한다.
## 이미 그 구간 안이면 한 바퀴 더 돈다. (그래야 항상 같은 길이로 미끄러진다.)
func _advance_waiting(left: float) -> float:
	var length: float = float(strip_length)
	var distance: float = fposmod(position - float(target), length)
	var to_go: float = distance - _feel.slide_cells
	if to_go < 0.0:
		to_go += length
	var wait: float = to_go / _feel.spin_speed
	if left < wait:
		position -= _feel.spin_speed * left
		return 0.0
	position = float(target) + _feel.slide_cells
	_decel_start = position
	_decel_total = _feel.slide_cells + _feel.bounce_cells
	_decel_duration = _feel.slide_ease_power * _decel_total / _feel.spin_speed
	_phase_time = 0.0
	phase = Phase.DECEL
	return left - wait


## 처음 속도를 이어받아 점점 느려지며 (목표 + 튕김 거리)까지 미끄러진다.
func _advance_decel(left: float) -> float:
	var remaining: float = _decel_duration - _phase_time
	var step: float = minf(left, remaining)
	_phase_time += step
	var progress: float = clampf(_phase_time / _decel_duration, 0.0, 1.0)
	position = _decel_start - _decel_total * (1.0 - pow(1.0 - progress, _feel.slide_ease_power))
	if left >= remaining:
		_phase_time = 0.0
		if _feel.bounce_cells > 0.0 and _feel.bounce_time > 0.0:
			position = float(target) - _feel.bounce_cells
			phase = Phase.BOUNCE
		else:
			_finish()
	return left - step


## 지나친 만큼 부드럽게 되돌아와 정확히 목표에 선다.
func _advance_bounce(left: float) -> float:
	var remaining: float = _feel.bounce_time - _phase_time
	var step: float = minf(left, remaining)
	_phase_time += step
	var progress: float = clampf(_phase_time / _feel.bounce_time, 0.0, 1.0)
	var eased: float = progress * progress * (3.0 - 2.0 * progress)
	position = float(target) - _feel.bounce_cells + _feel.bounce_cells * eased
	if left >= remaining:
		_finish()
	return left - step


func _finish() -> void:
	position = float(target)
	phase = Phase.IDLE
	_stop_requested = false
	stopped.emit()

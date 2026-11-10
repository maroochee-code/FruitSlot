class_name BulbPattern
extends RefCounted
## 전구 깜빡임 규칙(6-F3a). 모드와 시간, 전구 번호로 "그 전구가 지금 어떤 상태인지"만 계산하는 순수 규칙이다.
## 보드 링(BoardView)과 프레임 소켓(FrameBulbs)이 같은 규칙을 쓴다. 시간 값은 feel.json(bulb_*).
## 시간 0의 기본(대기) 모양은 6-B의 정적 모양(짝수 번호 켜짐)과 같다.

enum Mode { IDLE, SPIN, WIN, FEVER }

## 스핀 모드: 이 개수마다 하나씩 켜진 채 돈다
const SPIN_GROUP: int = 3

## 대기: 짝수/홀수가 번갈아 켜지는 주기 (초)
var idle_sec: float = 0.8
## 스핀: 켜진 전구가 한 칸 이동하는 시간 (초)
var spin_step_sec: float = 0.06
## 당첨: 전부 켜짐/꺼짐이 바뀌는 시간 (초)
var win_flash_sec: float = 0.12
## 피버: 노랑/빨강이 바뀌는 시간 (초)
var fever_sec: float = 0.2


func apply_feel(feel: FeelConfig) -> void:
	idle_sec = feel.bulb_idle_sec
	spin_step_sec = feel.bulb_spin_step_sec
	win_flash_sec = feel.bulb_win_flash_sec
	fever_sec = feel.bulb_fever_sec


## 모드가 시작된 뒤 time초가 지났을 때 index번 전구의 상태 (BulbSheet.STATE_*)
func state_of(mode: int, index: int, time: float) -> int:
	match mode:
		Mode.SPIN:
			var step: int = int(time / spin_step_sec)
			return BulbSheet.STATE_ON if posmod(index - step, SPIN_GROUP) == 0 else BulbSheet.STATE_OFF
		Mode.WIN:
			return BulbSheet.STATE_WHITE if _phase(time, win_flash_sec) == 0 else BulbSheet.STATE_OFF
		Mode.FEVER:
			return BulbSheet.STATE_ON if _phase(time, fever_sec) == 0 else BulbSheet.STATE_RED
		_:
			return BulbSheet.STATE_ON if posmod(index + _phase(time, idle_sec), 2) == 0 else BulbSheet.STATE_OFF


## 모든 전구(count개)의 상태 목록
func states_of(mode: int, count: int, time: float) -> PackedInt32Array:
	var states: PackedInt32Array = PackedInt32Array()
	states.resize(count)
	for i: int in count:
		states[i] = state_of(mode, i, time)
	return states


func _phase(time: float, half_sec: float) -> int:
	return int(time / half_sec) % 2

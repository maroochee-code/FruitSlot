class_name AutoSpin
extends RefCounted
## AUTO(자동 스핀) 상태. 화면과 무관한 순수 로직이다.
## 켜져 있는 동안 "판이 정산된 뒤 대기시간(gap_sec)이 지나면 다음 판을 시작"한다.
## 이 클래스는 언제 시작할지/멈출지만 판단한다. 결과(RNG)에는 관여하지 않는다 (시작은 GameState.start_spin이 한다).

## AUTO가 꺼진 이유
const REASON_USER: StringName = &"user"
const REASON_NO_CREDIT: StringName = &"no_credit"
const REASON_BIG_WIN: StringName = &"big_win"

## 켜져 있는가
var enabled: bool = false
## AUTO를 켠 뒤 시작한 판 수 (켤 때마다 0에서 다시 센다)
var spin_count: int = 0
## 정산 뒤 다음 판까지의 대기시간 (초). feel.json의 auto_spin_gap_sec를 화면이 넘겨 준다.
var gap_sec: float = 0.5
## 한 판 WIN이 이 값 이상이면 AUTO를 끈다. 0이면 사용 안 함. balance.json의 auto_spin.stop_on_win_at
var stop_on_win_at: int = 0

var _waiting: bool = false
var _gap_left: float = 0.0


func turn_on() -> void:
	enabled = true
	spin_count = 0
	_waiting = false


func turn_off() -> void:
	enabled = false
	_waiting = false
	_gap_left = 0.0


## 한 판 WIN(라인 + 피버 + 풀)이 정지 기준 이상인가
func is_big_win(payout: int) -> bool:
	return stop_on_win_at > 0 and payout >= stop_on_win_at


## 정산이 끝났다: 대기시간을 시작한다.
func begin_gap() -> void:
	_waiting = true
	_gap_left = gap_sec


func is_waiting() -> bool:
	return enabled and _waiting


## 시간을 delta초 진행한다. 대기시간이 끝나 다음 판을 시작할 때가 되면 true (한 번만).
func advance(delta: float) -> bool:
	if not is_waiting():
		return false
	_gap_left -= delta
	if _gap_left > 0.0:
		return false
	_waiting = false
	return true

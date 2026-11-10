class_name SettleShow
extends Control
## 정산 연출 (6-F3b). 당첨금이 정해진 뒤 화면 숫자만 천천히 보여 준다. 로직 값은 이미 최종값이다.
## - WIN 숫자가 0에서 payout까지 countup_sec 동안 올라간다.
## - 동전 n개가 WIN 칸에서 CREDIT 칸으로 포물선으로 날아가고, 도착할 때마다 CREDIT 숫자가 오른다.
##   동전 i는 카운트업이 (i+1)/n 만큼 진행된 시각에 출발하고 fly_sec 뒤에 도착한다.
##   마지막 동전이 나머지를 더해 CREDIT이 최종값과 정확히 맞는다.
## - finish_now()는 남은 연출을 건너뛰고 최종값을 바로 보여 준다 (소리 없음).
## 시각 연출만 맡는다. 크레딧·WIN 같은 게임 상태는 건드리지 않는다.

## 화면에 보여 줄 숫자가 바뀌었다
signal win_shown_changed(value: int)
signal credit_shown_changed(value: int)
## 카운트업 틱 / 동전 도착 (소리용)
signal tick
signal coin_landed
## 연출이 끝났다 (건너뛰기 포함, 한 번만)
signal finished

## 동전 포물선의 높이 (px)
const COIN_ARC_PX: float = 56.0
## 동전이 도는 그림 한 프레임의 시간 (초)
const COIN_FRAME_SEC: float = 0.06

var _active: bool = false
var _elapsed: float = 0.0
var _payout: int = 0
var _credit_base: int = 0
var _countup_sec: float = 1.0
var _fly_sec: float = 0.45
var _tick_sec: float = 0.05
var _coin_count: int = 0
var _landed: int = 0
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _win_shown: int = 0
var _credit_shown: int = 0
var _next_tick: float = 0.0
var _last_tick_win: int = 0
var _tick_total: int = 0
var _coins: Array[TextureRect] = []
var _frames: Array[AtlasTexture] = []


func _init() -> void:
	name = "SettleShow"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## 연출을 시작한다. 코인 수는 payout을 넘지 않게 줄인다 (동전 하나가 최소 1을 나른다).
func start(payout: int, credit_base: int, countup_sec: float, coin_count: int, fly_sec: float, tick_sec: float, from: Vector2, to: Vector2) -> void:
	_clear_coins()
	_payout = payout
	_credit_base = credit_base
	_countup_sec = maxf(0.001, countup_sec)
	_fly_sec = maxf(0.001, fly_sec)
	_tick_sec = maxf(0.001, tick_sec)
	_coin_count = clampi(coin_count, 1, maxi(1, payout))
	_landed = 0
	_from = from
	_to = to
	_elapsed = 0.0
	_win_shown = 0
	_credit_shown = credit_base
	_next_tick = _tick_sec
	_last_tick_win = 0
	_tick_total = 0
	_active = true
	visible = true
	_ensure_frames()
	for i: int in _coin_count:
		var coin: TextureRect = TextureRect.new()
		coin.name = "Coin%d" % i
		coin.size = Vector2(CoinSheet.FRAME_PX, CoinSheet.FRAME_PX)
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin.visible = false
		add_child(coin)
		_coins.append(coin)
	win_shown_changed.emit(_win_shown)
	credit_shown_changed.emit(_credit_shown)


func is_active() -> bool:
	return _active


## 연출 전체 시간 (초)
func total_sec() -> float:
	return _countup_sec + _fly_sec


func win_shown() -> int:
	return _win_shown


func credit_shown() -> int:
	return _credit_shown


## 지금까지 도착한 동전 수 (테스트용)
func landed_count() -> int:
	return _landed


func coin_count() -> int:
	return _coin_count


## 지금 화면에 보이는 (날아가는 중인) 동전 수 (테스트용)
func flying_count() -> int:
	var count: int = 0
	for coin: TextureRect in _coins:
		if coin.visible:
			count += 1
	return count


## 이번 연출에서 낸 틱 수 (테스트용)
func tick_count() -> int:
	return _tick_total


func credit_final() -> int:
	return _credit_base + _payout


## 동전 i의 출발 시각 / 도착 시각 (연출 시작 기준, 초)
func launch_time(i: int) -> float:
	return _countup_sec * float(i + 1) / float(_coin_count)


func land_time(i: int) -> float:
	return launch_time(i) + _fly_sec


## 동전 i가 나르는 크레딧. 마지막 동전이 나머지를 더한다.
func coin_share(i: int) -> int:
	var base: int = _payout / _coin_count
	if i == _coin_count - 1:
		return _payout - base * (_coin_count - 1)
	return base


func advance(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	_update_win()
	_update_coins()
	if _elapsed >= total_sec():
		_end(false)


## 남은 연출을 건너뛰고 최종값을 보여 준다. 연출 중이 아니면 아무것도 하지 않는다.
func finish_now() -> void:
	if _active:
		_end(true)


func _update_win() -> void:
	var progress: float = clampf(_elapsed / _countup_sec, 0.0, 1.0)
	var value: int = mini(_payout, int(float(_payout) * progress))
	if progress >= 1.0:
		value = _payout
	if value != _win_shown:
		_win_shown = value
		win_shown_changed.emit(_win_shown)
	if _elapsed >= _next_tick:
		_next_tick = _elapsed + _tick_sec
		if _win_shown > _last_tick_win:
			_last_tick_win = _win_shown
			_tick_total += 1
			tick.emit()


func _update_coins() -> void:
	for i: int in _coin_count:
		var coin: TextureRect = _coins[i]
		var t: float = (_elapsed - launch_time(i)) / _fly_sec
		if t < 0.0 or t >= 1.0:
			coin.visible = false
		else:
			coin.visible = true
			coin.position = _coin_position(t) - coin.size / 2.0
			coin.texture = _frames[int(_elapsed / COIN_FRAME_SEC + i) % _frames.size()]
	# 도착은 출발한 순서대로 일어난다 (시각이 i에 대해 단조 증가)
	while _landed < _coin_count and _elapsed >= land_time(_landed):
		_credit_shown += coin_share(_landed)
		_landed += 1
		credit_shown_changed.emit(_credit_shown)
		coin_landed.emit()


## 포물선: 직선으로 가면서 가운데에서 가장 높이 솟는다
func _coin_position(t: float) -> Vector2:
	var flat: Vector2 = _from.lerp(_to, t)
	return flat + Vector2(0.0, -COIN_ARC_PX * 4.0 * t * (1.0 - t))


func _end(skipped: bool) -> void:
	_active = false
	_clear_coins()
	visible = false
	if _win_shown != _payout:
		_win_shown = _payout
		win_shown_changed.emit(_win_shown)
	if _credit_shown != credit_final():
		_credit_shown = credit_final()
		credit_shown_changed.emit(_credit_shown)
	if skipped:
		_landed = _coin_count
	finished.emit()


func _clear_coins() -> void:
	for coin: TextureRect in _coins:
		remove_child(coin)
		coin.queue_free()
	_coins.clear()


func _ensure_frames() -> void:
	if not _frames.is_empty():
		return
	for i: int in CoinSheet.FRAME_COUNT:
		_frames.append(CoinSheet.frame(i))

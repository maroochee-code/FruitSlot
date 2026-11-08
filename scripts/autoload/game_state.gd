extends Node
## 전역 게임 상태(오토로드). 크레딧·베팅·마지막 당첨금을 관리하고 SlotLogic을 소유한다.
## 화면은 이 노드의 함수(insert_coin, raise_bet, start_spin)만 부르고, 값 변화는 시그널로 받는다.
## 화면이 이 변수들을 직접 바꾸면 안 된다. (class_name을 붙이면 오토로드 이름과 충돌하므로 붙이지 않는다.)

const ECONOMY_PATH: String = "res://data/economy.json"

const REASON_NO_CREDIT: StringName = &"no_credit"
const REASON_NO_BET: StringName = &"no_bet"
const REASON_BET_OVER_CREDIT: StringName = &"bet_over_credit"

signal credit_changed(credit: int)
signal bet_changed(total_bet: int, line_bets: PackedInt32Array)
signal win_changed(win: int)
signal coin_inserted(amount: int)
## 스핀 결과 확정. lowered_from은 베팅이 자동으로 낮아졌을 때의 직전 베팅(아니면 0)
signal spin_finished(result: SpinResult, lowered_from: int)
## 동작이 거절됨. reason은 REASON_* 중 하나
signal action_rejected(reason: StringName)

var credit: int = 0
var bet: int = 0
## 라인 A→H 순서의 라인별 베팅
var line_bets: PackedInt32Array = PackedInt32Array()
var last_win: int = 0
var coin_amount: int = 0
var ready_ok: bool = false

var _data: BalanceData
var _logic: SlotLogic


func _ready() -> void:
	var data: BalanceData = BalanceData.load_from_file()
	var economy: Dictionary = load_economy()
	if data == null or economy.is_empty():
		push_error("GameState: 데이터 로드 실패")
		return
	initialize(data, economy, int(Time.get_ticks_usec()))


## economy.json을 읽어 검사한다. 문제가 있으면 빈 사전을 돌려주고 에러를 출력한다.
static func load_economy(path: String = ECONOMY_PATH) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if text.is_empty() or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("GameState: %s 를 읽을 수 없음" % path)
		return {}
	var raw: Dictionary = json.data
	var coin: int = int(raw.get("coin_amount", 0))
	var start: int = int(raw.get("start_credit", -1))
	if coin <= 0 or start < 0:
		push_error("GameState: economy.json의 coin_amount는 1 이상, start_credit은 0 이상이어야 함")
		return {}
	return { "coin_amount": coin, "start_credit": start }


## 상태를 처음으로 되돌린다. 테스트에서는 원하는 데이터와 시드를 넣어 부른다.
func initialize(data: BalanceData, economy: Dictionary, rng_seed: int) -> void:
	_data = data
	_logic = SlotLogic.new(data, rng_seed)
	coin_amount = int(economy["coin_amount"])
	credit = int(economy["start_credit"])
	bet = 0
	line_bets = _logic.distribute_bet(0)
	last_win = 0
	ready_ok = true


## 화면이 처음 연결된 뒤 현재 값을 한 번 알려준다.
func refresh() -> void:
	credit_changed.emit(credit)
	bet_changed.emit(bet, line_bets)
	win_changed.emit(last_win)


func get_balance() -> BalanceData:
	return _data


func get_pool() -> int:
	return _logic.get_pool()


func get_fever_counts() -> Dictionary[String, int]:
	return _logic.get_fever_counts()


## BET 버튼이 의미 있는지 (크레딧이 있고, 올릴 수 있거나 최대에서 1로 돌아갈 수 있음)
func can_raise_bet() -> bool:
	if credit < 1:
		return false
	return bet >= _data.max_total_bet or bet + 1 <= credit


## MAX BET 목표값: min(최대 베팅, 현재 크레딧)
func max_bet_target() -> int:
	return mini(_data.max_total_bet, credit)


## MAX BET이 의미 있는지 (크레딧이 있고, 이미 목표값이 아님)
func can_max_bet() -> bool:
	return credit >= 1 and bet != max_bet_target()


func can_cancel_bet() -> bool:
	return bet >= 1


func can_start() -> bool:
	return bet >= 1 and bet <= credit


func insert_coin() -> void:
	credit += coin_amount
	coin_inserted.emit(coin_amount)
	credit_changed.emit(credit)


## BET +1. 최대에서 한 번 더 누르면 1로 돌아간다. 새 베팅이 크레딧을 넘으면 거절한다.
func raise_bet() -> bool:
	if credit < 1:
		action_rejected.emit(REASON_NO_CREDIT)
		return false
	var next_bet: int = bet + 1
	if next_bet > _data.max_total_bet:
		next_bet = 1
	elif next_bet > credit:
		action_rejected.emit(REASON_BET_OVER_CREDIT)
		return false
	_set_bet(next_bet)
	return true


## MAX BET. 베팅을 min(최대 베팅, 현재 크레딧)으로 한 번에 맞춘다. 라인 배분은 BET과 같다.
func max_bet() -> bool:
	if credit < 1:
		action_rejected.emit(REASON_NO_CREDIT)
		return false
	var target: int = max_bet_target()
	if bet == target:
		return false
	_set_bet(target)
	return true


## CANCEL. 베팅을 0으로 되돌린다. 크레딧은 START 때 차감되므로 변하지 않는다.
func cancel_bet() -> bool:
	if bet < 1:
		return false
	_set_bet(0)
	return true


## START. 크레딧에서 베팅을 차감하고 스핀한 뒤 당첨금을 더한다. 거절되면 null.
func start_spin() -> SpinResult:
	if bet < 1:
		action_rejected.emit(REASON_NO_CREDIT if credit < 1 else REASON_NO_BET)
		return null
	if bet > credit:
		action_rejected.emit(REASON_NO_CREDIT)
		return null
	credit -= bet
	credit_changed.emit(credit)
	_set_win(0)
	var result: SpinResult = _logic.spin(bet)
	if result == null:
		credit += bet
		credit_changed.emit(credit)
		return null
	credit += result.total_payout()
	credit_changed.emit(credit)
	_set_win(result.total_payout())
	var lowered_from: int = _lower_bet_to_credit()
	spin_finished.emit(result, lowered_from)
	return result


## 크레딧이 베팅보다 적으면 베팅을 크레딧만큼 낮춘다. 낮췄으면 직전 베팅, 아니면 0.
func _lower_bet_to_credit() -> int:
	if credit >= bet:
		return 0
	var old_bet: int = bet
	_set_bet(credit)
	return old_bet


func _set_bet(new_bet: int) -> void:
	bet = new_bet
	line_bets = _logic.distribute_bet(bet)
	bet_changed.emit(bet, line_bets)


func _set_win(amount: int) -> void:
	last_win = amount
	win_changed.emit(last_win)

extends Node
## 전역 게임 상태(오토로드). 크레딧·베팅·마지막 당첨금을 관리하고 SlotLogic을 소유한다.
## 화면은 이 노드의 함수(insert_coin, raise_bet, start_spin)만 부르고, 값 변화는 시그널로 받는다.
## 화면이 이 변수들을 직접 바꾸면 안 된다. (class_name을 붙이면 오토로드 이름과 충돌하므로 붙이지 않는다.)

const ECONOMY_PATH: String = "res://data/economy.json"
## economy.json 값의 허용 범위
const CREDIT_VALUE_MAX: int = 999999
const CONTINUE_MAX_LIMIT: int = 99

## 크레딧을 올리는 이유 (grant_credit). 당첨금은 정산 경로라서 여기에 없다.
const GRANT_START: StringName = &"start"
const GRANT_CONTINUE: StringName = &"continue"
const GRANT_TEST_COIN: StringName = &"test_coin"

const REASON_NO_CREDIT: StringName = &"no_credit"
const REASON_NO_BET: StringName = &"no_bet"
const REASON_BET_OVER_CREDIT: StringName = &"bet_over_credit"

signal credit_changed(credit: int)
signal bet_changed(total_bet: int, line_bets: PackedInt32Array)
signal win_changed(win: int)
signal coin_inserted(amount: int)
## 스핀 시작. 결과(정지 위치)는 이 순간 확정됐고, 크레딧에서 베팅만 차감된 상태다.
signal spin_started(result: SpinResult)
## 정산 완료(릴이 모두 멈춘 뒤). lowered_from은 베팅이 자동으로 낮아졌을 때의 직전 베팅(아니면 0)
signal spin_finished(result: SpinResult, lowered_from: int)
## 동작이 거절됨. reason은 REASON_* 중 하나
signal action_rejected(reason: StringName)
## AUTO가 켜지거나 꺼지거나, 켠 뒤 시작한 판 수(count)가 바뀜
signal auto_changed(enabled: bool, count: int)
## AUTO가 꺼진 이유 (AutoSpin.REASON_*). auto_changed 다음에 온다.
signal auto_stopped(reason: StringName)
## 크레딧이 올라갔다 (시작 지급·CONTINUE·개발용 COIN). reason은 GRANT_* 중 하나
signal credit_granted(amount: int, reason: StringName)
## 정산 뒤 크레딧이 0이 되어 GAME OVER 상태가 됐다 (AUTO 해제 알림 다음에 온다)
signal game_over
## NEW GAME으로 크레딧·POOL·피버 카운터·이어하기 횟수가 처음 상태로 돌아갔다 (화면이 오른쪽 패널을 다시 그리는 용도)
signal new_game_started

var credit: int = 0
var bet: int = 0
## 라인 A→H 순서의 라인별 베팅
var line_bets: PackedInt32Array = PackedInt32Array()
var last_win: int = 0
var coin_amount: int = 0
## 시작·NEW GAME 지급 크레딧 / CONTINUE 1회 지급 크레딧 / CONTINUE 최대 횟수 (economy.json)
var start_credit: int = 0
var continue_credit: int = 0
var continue_max: int = 0
## 남은 CONTINUE 횟수. NEW GAME에서 continue_max로 복구된다.
var continues_left: int = 0
## 개발 빌드인가. 내보낸 릴리즈 exe에서는 false. 테스트가 릴리즈 상황을 흉내 내려고 바꿔 넣을 수 있다.
var dev_build: bool = OS.is_debug_build()
## 테스트 모드 스위치. 지금은 항상 켜짐이고, 8-B에서 설정 화면이 이 값을 바꾼다.
var test_mode: bool = true
## 이번 판(NEW GAME 이후)의 기록. 메모리 집계만 하고 저장하지 않는다 (저장은 8단계).
var run_peak_credit: int = 0
var run_spins: int = 0
var run_continues_used: int = 0
## 개발용 COIN을 쓴 판인가 (최고 기록·통계에서 "테스트 판"으로 제외하는 표시)
var run_tainted: bool = false
var ready_ok: bool = false
## 릴이 도는 중(START ~ 정산 전). 이 동안 COIN/BET/MAX BET/CANCEL/START는 거절된다.
var spinning: bool = false

## AUTO가 켜져 있는가 (읽기 전용으로만 쓴다. 켜고 끄기는 toggle_auto / start_auto / stop_auto)
var auto_on: bool:
	get:
		return _auto.enabled

## AUTO 대기시간(초). 화면이 feel.json의 auto_spin_gap_sec를 스핀 시작 때 넘겨 준다.
var auto_gap_sec: float:
	get:
		return _auto.gap_sec
	set(value):
		_auto.gap_sec = value

var _data: BalanceData
## 정산 도중 AUTO가 꺼졌을 때, auto_stopped를 spin_finished 다음에 보내기 위해 이유를 잠시 들고 있는다.
var _deferred_stop_reason: StringName = &""
var _auto: AutoSpin = AutoSpin.new()
var _logic: SlotLogic
## START에서 확정됐지만 아직 정산하지 않은 결과
var _pending: SpinResult
## GAME OVER 상태인가 (정산에서 크레딧이 0이 되면 켜지고, CONTINUE·NEW GAME에서 꺼진다)
var _game_over: bool = false
## GAME OVER가 된 판의 베팅 (CONTINUE 뒤 복구용. 정산에서 베팅이 0으로 내려가기 전 값)
var _bet_at_game_over: int = 0


func _ready() -> void:
	var data: BalanceData = BalanceData.load_from_file()
	var economy: Dictionary = load_economy()
	if data == null or economy.is_empty():
		push_error("GameState: 데이터 로드 실패")
		return
	# 크레딧 0으로 대기한다. 시작 크레딧은 시작 화면(title.tscn)의 START가 new_game()을 불러 준다.
	initialize(data, economy, int(Time.get_ticks_usec()))


## economy.json을 읽어 검사한다. 문제가 있으면 빈 사전을 돌려주고 에러를 출력한다.
static func load_economy(path: String = ECONOMY_PATH) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if text.is_empty() or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("GameState: %s 를 읽을 수 없음" % path)
		return {}
	return economy_from_dict(json.data)


## 사전에서 economy 값을 꺼내 범위를 검사한다. 문제가 있으면 빈 사전을 돌려주고 에러를 출력한다.
static func economy_from_dict(raw: Dictionary) -> Dictionary:
	var coin: int = int(raw.get("coin_amount", 0))
	var start: int = int(raw.get("start_credit", 0))
	var cont: int = int(raw.get("continue_credit", 0))
	var cont_max: int = int(raw.get("continue_max", -1))
	var problems: PackedStringArray = PackedStringArray()
	if coin < 1:
		problems.append("coin_amount는 1 이상")
	if start < 1 or start > CREDIT_VALUE_MAX:
		problems.append("start_credit은 1~%d" % CREDIT_VALUE_MAX)
	if cont < 1 or cont > CREDIT_VALUE_MAX:
		problems.append("continue_credit은 1~%d" % CREDIT_VALUE_MAX)
	if cont_max < 0 or cont_max > CONTINUE_MAX_LIMIT:
		problems.append("continue_max는 0~%d" % CONTINUE_MAX_LIMIT)
	if not problems.is_empty():
		push_error("GameState: economy.json 값이 범위를 벗어남: " + ", ".join(problems))
		return {}
	return { "coin_amount": coin, "start_credit": start, "continue_credit": cont, "continue_max": cont_max }


## 상태를 처음으로 되돌린다. 테스트에서는 원하는 데이터와 시드를 넣어 부른다.
## 크레딧은 0으로 시작한다 (시작 크레딧은 new_game()이 grant_credit으로 준다).
func initialize(data: BalanceData, economy: Dictionary, rng_seed: int) -> void:
	_data = data
	_logic = SlotLogic.new(data, rng_seed)
	var gap: float = _auto.gap_sec
	_auto = AutoSpin.new()
	_auto.gap_sec = gap
	_auto.stop_on_win_at = data.auto_stop_on_win_at
	coin_amount = int(economy["coin_amount"])
	start_credit = int(economy["start_credit"])
	continue_credit = int(economy["continue_credit"])
	continue_max = int(economy["continue_max"])
	continues_left = continue_max
	credit = 0
	bet = 0
	line_bets = _logic.distribute_bet(0)
	last_win = 0
	spinning = false
	_pending = null
	_game_over = false
	_bet_at_game_over = 0
	_deferred_stop_reason = &""
	_reset_run_record()
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
	if spinning or auto_on or credit < 1:
		return false
	return bet >= _data.max_total_bet or bet + 1 <= credit


## MAX BET 목표값: min(최대 베팅, 현재 크레딧)
func max_bet_target() -> int:
	return mini(_data.max_total_bet, credit)


## MAX BET이 의미 있는지 (크레딧이 있고, 이미 목표값이 아님)
func can_max_bet() -> bool:
	return not spinning and not auto_on and credit >= 1 and bet != max_bet_target()


func can_cancel_bet() -> bool:
	return not spinning and not auto_on and bet >= 1


func can_start() -> bool:
	return not spinning and bet >= 1 and bet <= credit


## COIN을 쓸 수 있는가. 개발 빌드이고 테스트 모드가 켜져 있을 때만 true.
## 내보낸 릴리즈 빌드에서는 항상 false다 (8-B의 테스트 모드 스위치는 test_mode에 연결한다).
func coin_allowed() -> bool:
	return dev_build and test_mode


## 개발용 COIN. 쓸 수 없는 상태(회전 중, coin_allowed가 false)면 아무것도 하지 않는다.
## GAME OVER 중에 불려도 막지 않는다 (입력 잠금은 화면이 맡고, 크레딧이 생기면 grant_credit이 GAME OVER를 해제한다).
func insert_coin() -> void:
	if spinning or not coin_allowed():
		return
	coin_inserted.emit(coin_amount)
	grant_credit(coin_amount, GRANT_TEST_COIN)


## 크레딧이 올라가는 입구. 시작 지급·CONTINUE·개발용 COIN이 모두 여기를 거친다 (당첨금은 정산 경로).
## 개발용 COIN이면 이번 판에 "테스트 판" 표시를 남긴다.
## 크레딧이 0보다 커지면 GAME OVER 상태를 해제한다 (GAME OVER는 항상 "크레딧 0 + 진행 중인 판 없음"과 일치해야 한다).
func grant_credit(amount: int, reason: StringName) -> void:
	if amount <= 0:
		push_error("GameState.grant_credit: amount는 1 이상이어야 함 (%d)" % amount)
		return
	credit += amount
	if credit > 0:
		_game_over = false
	run_peak_credit = maxi(run_peak_credit, credit)
	if reason == GRANT_TEST_COIN:
		run_tainted = true
	credit_granted.emit(amount, reason)
	credit_changed.emit(credit)


## GAME OVER 상태인가 (정산에서 크레딧이 0이 된 뒤 CONTINUE·NEW GAME을 고르기 전까지)
func is_game_over() -> bool:
	return _game_over


func can_continue() -> bool:
	return _game_over and continues_left > 0


## CONTINUE: 이어하기 횟수를 하나 쓰고 continue_credit을 준다. POOL·피버 카운터는 그대로 두고,
## 베팅은 GAME OVER가 된 판의 베팅으로 되돌린다 (크레딧이 모자라면 크레딧 이내로).
func continue_game() -> bool:
	if not can_continue():
		return false
	continues_left -= 1
	run_continues_used += 1
	_game_over = false
	grant_credit(continue_credit, GRANT_CONTINUE)
	var restored: int = mini(_bet_at_game_over, credit)
	if restored >= 1:
		_set_bet(restored)
	return true


## NEW GAME(7-C의 START도 같은 함수): 크레딧을 start_credit으로 주고, POOL·피버 카운터·이어하기 횟수·기록을 처음으로 되돌린다.
## 베팅·WIN은 0, AUTO는 끈다. 난수 시드는 건드리지 않는다. 회전 중이면 거절한다.
func new_game() -> bool:
	if spinning:
		return false
	stop_auto(AutoSpin.REASON_USER)
	_logic.reset_state()
	_game_over = false
	_bet_at_game_over = 0
	continues_left = continue_max
	_reset_run_record()
	credit = 0
	if bet != 0:
		_set_bet(0)
	if last_win != 0:
		_set_win(0)
	new_game_started.emit()
	grant_credit(start_credit, GRANT_START)
	return true


func _reset_run_record() -> void:
	run_peak_credit = 0
	run_spins = 0
	run_continues_used = 0
	run_tainted = false


## BET +1. 최대에서 한 번 더 누르면 1로 돌아간다. 새 베팅이 크레딧을 넘으면 거절한다.
func raise_bet() -> bool:
	if spinning or auto_on:
		return false
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
	if spinning or auto_on:
		return false
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
	if spinning or auto_on or bet < 1:
		return false
	_set_bet(0)
	return true


## START 1단계. 크레딧에서 베팅을 차감하고 결과를 확정한다. 당첨금은 아직 더하지 않는다.
## 화면은 spin_started를 받아 릴을 돌리고, 모두 멈추면 settle_spin()을 부른다. 거절되면 null.
func start_spin() -> SpinResult:
	if spinning:
		return null
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
	_pending = result
	spinning = true
	spin_started.emit(result)
	return result


## START 2단계(정산). 릴이 모두 멈춘 뒤 부른다. 당첨금 합산, WIN 갱신, 베팅 자동 하향.
## 스핀 중이 아니면 null.
func settle_spin() -> SpinResult:
	if not spinning or _pending == null:
		return null
	var result: SpinResult = _pending
	_pending = null
	spinning = false
	credit += result.total_payout()
	run_spins += 1
	run_peak_credit = maxi(run_peak_credit, credit)
	credit_changed.emit(credit)
	_set_win(result.total_payout())
	_judge_auto_after_settle(result)
	var bet_before_lowering: int = bet
	var lowered_from: int = _lower_bet_to_credit()
	spin_finished.emit(result, lowered_from)
	if _deferred_stop_reason != &"":
		var reason: StringName = _deferred_stop_reason
		_deferred_stop_reason = &""
		auto_stopped.emit(reason)
	# GAME OVER 판정은 정산 순간에만, 로직 값(크레딧)으로 한다. 화면은 연출이 끝난 뒤에 띄운다.
	if credit <= 0:
		_bet_at_game_over = bet_before_lowering
		_game_over = true
		game_over.emit()
	return result


## 시작과 정산을 한 번에 한다 (릴 연출 없이 즉시 결과가 필요한 테스트용).
func play_spin() -> SpinResult:
	var result: SpinResult = start_spin()
	if result == null:
		return null
	return settle_spin()


## AUTO 켜기/끄기. 켤 수 없는 상태(베팅 없음, 크레딧 부족)면 거절 시그널만 보낸다.
func toggle_auto() -> void:
	if auto_on:
		stop_auto(AutoSpin.REASON_USER)
	else:
		start_auto()


## AUTO를 켤 수 있는가: 켜져 있으면 언제든 끌 수 있고, 꺼져 있으면 베팅이 1 이상이고
## (쉬는 중이면) 크레딧 이내일 때만 켠다. 회전 중에는 정산 때 크레딧을 다시 따진다.
func can_toggle_auto() -> bool:
	if auto_on:
		return true
	if spinning:
		return bet >= 1
	return can_start()


## 지금 AUTO가 센 판 수 (AUTO를 켠 뒤 시작한 판)
func auto_count() -> int:
	return _auto.spin_count


## AUTO를 켠다. 쉬는 중이면 바로 첫 판을 시작하고, 회전 중이면 정산 뒤 대기시간 후부터 이어진다.
func start_auto() -> bool:
	if auto_on:
		return false
	if not can_toggle_auto():
		action_rejected.emit(REASON_NO_CREDIT if credit < 1 else REASON_NO_BET if bet < 1 else REASON_NO_CREDIT)
		return false
	_auto.turn_on()
	auto_changed.emit(true, _auto.spin_count)
	if not spinning:
		_auto_start_spin()
	return true


## AUTO를 끈다. 진행 중인 판은 끊지 않고 그대로 정산되며, 다음 판만 시작하지 않는다.
## defer_notice: 정산 도중에 끄는 경우 true (auto_stopped를 spin_finished 뒤로 미룬다)
func stop_auto(reason: StringName, defer_notice: bool = false) -> void:
	if not auto_on:
		return
	_auto.turn_off()
	auto_changed.emit(false, _auto.spin_count)
	if defer_notice:
		_deferred_stop_reason = reason
	else:
		auto_stopped.emit(reason)


## 화면이 매 프레임 부른다. AUTO 대기시간이 끝나면 다음 판을 시작한다. (회전 중에는 아무것도 하지 않는다.)
func auto_advance(delta: float) -> void:
	if spinning or not _auto.advance(delta):
		return
	if bet < 1 or bet > credit:
		stop_auto(AutoSpin.REASON_NO_CREDIT)
		return
	_auto_start_spin()


## AUTO가 켜진 채 정산됐을 때: 큰 당첨이면 끄고, 크레딧이 베팅보다 적으면 끄고, 아니면 대기시간을 시작한다.
## 베팅 자동 하향보다 먼저 판단한다 (AUTO가 베팅을 몰래 바꾸지 않도록).
func _judge_auto_after_settle(result: SpinResult) -> void:
	if not auto_on:
		return
	if _auto.is_big_win(result.total_payout()):
		stop_auto(AutoSpin.REASON_BIG_WIN, true)
	elif credit < bet:
		stop_auto(AutoSpin.REASON_NO_CREDIT, true)
	else:
		_auto.begin_gap()


## AUTO가 새 판을 시작한다. 판 수를 먼저 올려서 spin_started를 받은 화면이 "AUTO N회"를 바로 맞게 보여 준다.
func _auto_start_spin() -> void:
	_auto.spin_count += 1
	auto_changed.emit(true, _auto.spin_count)
	if start_spin() == null:
		_auto.spin_count -= 1
		stop_auto(AutoSpin.REASON_NO_CREDIT)


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

class_name SpinResult
extends RefCounted
## 스핀 1회의 확정 결과. 화면은 이 값을 보여주기만 하고 바꾸지 않는다.

var total_bet: int = 0
## 라인 순서(A~H)대로의 라인별 베팅
var line_bets: PackedInt32Array = PackedInt32Array()
## 릴별 정지 위치 (윗줄에 보이는 스트립 인덱스)
var stops: PackedInt32Array = PackedInt32Array()
## grid[열][행] = 심볼 ID
var grid: Array[PackedStringArray] = []
var line_wins: Array[LineWin] = []
var line_payout: int = 0
## 이번 스핀에서 카운터가 줄어든 피버 심볼
var fever_hits: PackedStringArray = PackedStringArray()
## 이번 스핀에서 발동한 피버 심볼
var fever_triggers: PackedStringArray = PackedStringArray()
var fever_bonus: int = 0
## 발동한 피버 심볼별 보너스
var fever_bonuses: Dictionary[String, int] = {}
var pool_won: int = 0
## 스핀 후 상태 (화면 표시용 스냅샷)
var fever_counts_after: Dictionary[String, int] = {}
var pool_after: int = 0


func total_payout() -> int:
	return line_payout + fever_bonus + pool_won


func is_hit() -> bool:
	return not line_wins.is_empty()

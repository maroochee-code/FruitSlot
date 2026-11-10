class_name FeelConfig
extends RefCounted
## 릴 회전·정지 손맛 수치. 값은 data/feel.json에서 읽는다 (설명은 docs/feel.md).
## SPECS의 기본값은 파일이 없거나 값이 잘못됐을 때만 쓰는 안전장치다.

const DEFAULT_PATH: String = "res://data/feel.json"
## 키: [기본값, 최솟값, 최댓값]
const SPECS: Dictionary = {
	"spin_speed": [26.0, 1.0, 200.0],
	"accel_time": [0.25, 0.0, 5.0],
	"slide_cells": [3.0, 0.5, 12.0],
	"slide_ease_power": [3.0, 1.0, 8.0],
	"bounce_cells": [0.15, 0.0, 1.0],
	"bounce_time": [0.14, 0.0, 2.0],
	"auto_stop_start": [3.0, 0.0, 60.0],
	"auto_stop_interval": [0.4, 0.0, 10.0],
	"quick_stop_interval": [0.15, 0.0, 5.0],
	"start_lock_sec": [0.3, 0.0, 5.0],
	"result_delay": [0.25, 0.0, 5.0],
	"auto_spin_gap_sec": [0.5, 0.0, 10.0],
	"fever_overlay_sec": [2.0, 0.2, 10.0],
	"fever_step_gap": [0.3, 0.0, 5.0],
	"fever_skip_lock_sec": [0.4, 0.0, 5.0],
	"pool_overlay_sec": [3.0, 0.2, 10.0],
	"pool_yellow_from": [1000.0, 0.0, 1000000000.0],
	"pool_red_from": [1500.0, 0.0, 1000000000.0],
	"win_mid_ratio": [2.0, 0.1, 1000.0],
	"win_big_ratio": [10.0, 0.1, 1000.0],
	"sfx_volume_db": [0.0, -40.0, 6.0],
}
## 릴 수만큼 값이 들어가는 항목. 키: [기본값 목록, 최솟값, 최댓값]
const REEL_COUNT: int = 3
const ARRAY_SPECS: Dictionary = {
	"reel_start_delay": [[0.0, 0.08, 0.16], 0.0, 0.5],
	"reel_speed_scale": [[1.0, 0.95, 1.05], 0.5, 1.5],
}
## 출발 지연이 자동 정지 시각보다 크면 안전하게 쓸 값 (지연 없음)
const NO_DELAY: Array[float] = [0.0, 0.0, 0.0]

## 회전 속도 (칸/초)
var spin_speed: float = 26.0
## 속도가 붙는 시간 (초)
var accel_time: float = 0.25
## 감속 구간 길이 (칸)
var slide_cells: float = 3.0
## 감속 곡선의 꼬리 길이 (클수록 끝에서 천천히 미끄러짐)
var slide_ease_power: float = 3.0
## 정지 위치를 살짝 지나쳤다가 돌아오는 거리 (칸, 0이면 튕김 없음)
var bounce_cells: float = 0.15
## 튕겨 돌아오는 시간 (초)
var bounce_time: float = 0.14
## 릴별 출발 지연 (START 기준, 초). 릴1~3 순서
var reel_start_delay: PackedFloat64Array = PackedFloat64Array([0.0, 0.08, 0.16])
## 릴별 회전 속도 배율 (spin_speed에 곱함). 릴1~3 순서
var reel_speed_scale: PackedFloat64Array = PackedFloat64Array([1.0, 0.95, 1.05])
## 자동 정지: 첫 릴이 멈추기 시작하는 시각 (START 기준, 초)
var auto_stop_start: float = 3.0
## 자동 정지: 릴 사이 간격 (초)
var auto_stop_interval: float = 0.4
## 회전 중 START: 남은 릴이 차례로 멈추기 시작하는 간격 (초)
var quick_stop_interval: float = 0.15
## 스핀 시작 직후 START(스페이스) 재입력을 무시하는 시간 (초)
var start_lock_sec: float = 0.3
## 마지막 릴이 멈춘 뒤 정산·당첨 연출까지의 간격 (초)
var result_delay: float = 0.25
## AUTO: 한 판이 정산된 뒤 다음 판을 자동으로 시작하기까지의 대기시간 (초)
var auto_spin_gap_sec: float = 0.5
## 피버 오버레이: 심볼 하나를 보여 주는 시간 (초)
var fever_overlay_sec: float = 2.0
## 피버 오버레이: 심볼과 심볼 사이 빈 간격 (초)
var fever_step_gap: float = 0.3
## 피버 오버레이가 뜬 직후 이 시간 동안은 스페이스 건너뛰기를 무시 (스페이스 연타로 바로 넘어가는 것 방지, 초)
var fever_skip_lock_sec: float = 0.4
## 풀 획득 오버레이(POOL GET): 풀 금액을 보여 주는 시간 (초). 세븐 피버 단계 뒤에 한 번 나온다.
var pool_overlay_sec: float = 3.0
## POOL 숫자가 이 값 이상이면 노랑 (미만이면 주황)
var pool_yellow_from: float = 1000.0
## POOL 숫자가 이 값 이상이면 빨강 + 가벼운 깜빡임. pool_yellow_from보다 커야 한다.
var pool_red_from: float = 1500.0
## 당첨 효과음 기준: (총 지급 ÷ 총 베팅)이 이 값 이상이면 중, win_big_ratio 이상이면 대 (미만이면 소). 중 < 대여야 한다.
var win_mid_ratio: float = 2.0
var win_big_ratio: float = 10.0
## 효과음(SFX 버스) 볼륨 (dB, 0 = 원래 크기). 다음 스핀부터 적용
var sfx_volume_db: float = 0.0
## 파일에서 읽다가 문제가 있어 기본값으로 대체한 항목 설명
var errors: PackedStringArray = PackedStringArray()
## 파일을 읽고 JSON으로 해석하는 데 성공했는지 (항목별 범위 문제와는 별개)
var file_ok: bool = true


## report가 true면 문제를 경고로 남긴다. 실행 중 재로딩은 false로 읽고 화면에 안내한다.
static func load_from_file(path: String = DEFAULT_PATH, report: bool = true) -> FeelConfig:
	var config: FeelConfig = FeelConfig.new()
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if text.is_empty() or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		config.file_ok = false
		config.errors.append("%s 를 읽을 수 없어 기본값을 씁니다" % path)
	else:
		config._read(json.data)
	if report:
		for message: String in config.errors:
			push_warning("FeelConfig: " + message)
	return config


static func from_dict(raw: Dictionary) -> FeelConfig:
	var config: FeelConfig = FeelConfig.new()
	config._read(raw)
	return config


func _read(raw: Dictionary) -> void:
	for key: String in SPECS:
		var spec: Array = SPECS[key]
		var value: float = spec[0]
		if not raw.has(key):
			errors.append("%s 항목이 없어 기본값 %s 사용" % [key, value])
		else:
			var raw_value: Variant = raw[key]
			var is_number: bool = typeof(raw_value) == TYPE_FLOAT or typeof(raw_value) == TYPE_INT
			if is_number and float(raw_value) >= float(spec[1]) and float(raw_value) <= float(spec[2]):
				value = float(raw_value)
			else:
				errors.append("%s 값 %s 이(가) 범위(%s~%s)를 벗어나 기본값 %s 사용" % [key, raw_value, spec[1], spec[2], value])
		set(key, value)
	for key: String in ARRAY_SPECS:
		set(key, _read_array(raw, key))
	_check_delay_before_auto_stop()
	_check_pool_tiers()
	_check_win_tiers()


## 릴 수만큼의 숫자 목록을 읽는다. 개수가 다르거나 하나라도 범위 밖이면 목록 전체를 기본값으로 쓴다.
func _read_array(raw: Dictionary, key: String) -> PackedFloat64Array:
	var spec: Array = ARRAY_SPECS[key]
	var fallback: PackedFloat64Array = PackedFloat64Array(spec[0])
	if not raw.has(key):
		errors.append("%s 항목이 없어 기본값 %s 사용" % [key, fallback])
		return fallback
	var raw_value: Variant = raw[key]
	if typeof(raw_value) != TYPE_ARRAY or (raw_value as Array).size() != REEL_COUNT:
		errors.append("%s 은(는) 릴 %d개 분량의 숫자 목록이어야 해서 기본값 %s 사용" % [key, REEL_COUNT, fallback])
		return fallback
	var values: PackedFloat64Array = PackedFloat64Array()
	for item: Variant in raw_value:
		var is_number: bool = typeof(item) == TYPE_FLOAT or typeof(item) == TYPE_INT
		if not is_number or float(item) < float(spec[1]) or float(item) > float(spec[2]):
			errors.append("%s 값 %s 이(가) 범위(%s~%s)를 벗어나 기본값 %s 사용" % [key, raw_value, spec[1], spec[2], fallback])
			return fallback
		values.append(float(item))
	return values


## 출발 지연이 첫 자동 정지 시각 이상이면 "출발도 전에 정지"가 되므로 지연을 기본값(그래도 안 되면 0)으로 돌린다.
func _check_delay_before_auto_stop() -> void:
	if _longest_delay() < auto_stop_start:
		return
	errors.append("reel_start_delay 가 auto_stop_start(%s)보다 같거나 커서 기본값 사용" % auto_stop_start)
	reel_start_delay = PackedFloat64Array(ARRAY_SPECS["reel_start_delay"][0])
	if _longest_delay() >= auto_stop_start:
		reel_start_delay = PackedFloat64Array(NO_DELAY)


## 노랑 기준이 빨강 기준 이상이면 단계가 성립하지 않으므로 둘 다 기본값으로 돌린다.
func _check_pool_tiers() -> void:
	if pool_yellow_from < pool_red_from:
		return
	errors.append("pool_yellow_from(%s)가 pool_red_from(%s)보다 작아야 해서 둘 다 기본값 사용" % [pool_yellow_from, pool_red_from])
	pool_yellow_from = SPECS["pool_yellow_from"][0]
	pool_red_from = SPECS["pool_red_from"][0]


## 중 기준이 대 기준 이상이면 소/중/대가 성립하지 않으므로 둘 다 기본값으로 돌린다.
func _check_win_tiers() -> void:
	if win_mid_ratio < win_big_ratio:
		return
	errors.append("win_mid_ratio(%s)가 win_big_ratio(%s)보다 작아야 해서 둘 다 기본값 사용" % [win_mid_ratio, win_big_ratio])
	win_mid_ratio = SPECS["win_mid_ratio"][0]
	win_big_ratio = SPECS["win_big_ratio"][0]


func _longest_delay() -> float:
	var longest: float = 0.0
	for delay: float in reel_start_delay:
		longest = maxf(longest, delay)
	return longest

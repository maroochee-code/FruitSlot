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
	"half_row": [0.5, 0.0, 0.5],
	"auto_stop_start": [3.0, 0.0, 60.0],
	"auto_stop_interval": [0.4, 0.0, 10.0],
	"quick_stop_interval": [0.15, 0.0, 5.0],
	"start_lock_sec": [0.3, 0.0, 5.0],
	"result_delay": [0.25, 0.0, 5.0],
}

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
## 릴 창 위아래로 더 보이는 높이 (칸 높이 대비, 최대 0.5)
var half_row: float = 0.5
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

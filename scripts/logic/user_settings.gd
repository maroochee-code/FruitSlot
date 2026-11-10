class_name UserSettings
extends RefCounted
## 운영자 설정(8-A). 기본값은 res://data/*.json이 그대로 갖고 있고, 운영자가 바꾼 키만 user://settings.json에 저장해 그 위에 덮어쓴다.
## 화면·Node에 의존하지 않는다 (feel 값은 Object의 set/get으로만 다룬다). 밸런스(릴·배당·피버·풀)는 이 파일의 대상이 아니다.
## 안 바꾼 키는 feel.json·economy.json을 고치면 계속 반영되고, 바꾼 키는 저장된 값이 우선한다 (설정 화면에서 노랑으로 표시).

const FILE_NAME: String = "settings.json"
const VERSION: int = 1

const GROUP_FEEL: String = "feel"
const GROUP_ECONOMY: String = "economy"
const GROUP_AUTO: String = "auto"
const GROUP_AUDIO: String = "audio"

const KEY_BGM_ENABLED: String = "bgm_enabled"
const KEY_AUTO_STOP: String = "auto_stop_on_win_at"
const KEY_WIN_MID: String = "win_mid_ratio"
const KEY_WIN_BIG: String = "win_big_ratio"
## 당첨 중/대 기준 사이의 최소 간격 (중 < 대 규칙을 지키기 위함)
const RATIO_GAP: float = 0.1
const FLOAT_DECIMALS_STEP: float = 0.01
const CREDIT_VALUE_MAX: int = 999999
const AUTO_STOP_MAX: int = 999999999

## 키 → 그룹·범위·단계. 범위는 FeelConfig.SPECS / GameState.economy_from_dict / BalanceData와 같다 (settings_test가 확인).
## step = ←/→ 한 번, big = Shift를 누른 ←/→
const SPECS: Dictionary = {
	"sfx_volume_db": { "group": "feel", "min": -40.0, "max": 6.0, "step": 1.0, "big": 5.0 },
	"bgm_volume_db": { "group": "feel", "min": -40.0, "max": 6.0, "step": 1.0, "big": 5.0 },
	"bgm_enabled": { "group": "audio", "bool": true },
	"auto_stop_on_win_at": { "group": "auto", "int": true, "min": 0, "max": 999999999, "step": 1000, "big": 10000 },
	"auto_effect_scale": { "group": "feel", "min": 0.1, "max": 1.0, "step": 0.1, "big": 0.3 },
	"start_credit": { "group": "economy", "int": true, "min": 1, "max": 999999, "step": 100, "big": 1000 },
	"continue_credit": { "group": "economy", "int": true, "min": 1, "max": 999999, "step": 100, "big": 1000 },
	"continue_max": { "group": "economy", "int": true, "min": 0, "max": 99, "step": 1, "big": 5 },
	"coin_amount": { "group": "economy", "int": true, "min": 1, "max": 999999, "step": 10, "big": 100 },
	"countup_small_sec": { "group": "feel", "min": 0.05, "max": 10.0, "step": 0.1, "big": 0.5 },
	"countup_mid_sec": { "group": "feel", "min": 0.05, "max": 10.0, "step": 0.1, "big": 0.5 },
	"countup_big_sec": { "group": "feel", "min": 0.05, "max": 10.0, "step": 0.1, "big": 0.5 },
	"win_mid_ratio": { "group": "feel", "min": 0.1, "max": 1000.0, "step": 0.5, "big": 2.0 },
	"win_big_ratio": { "group": "feel", "min": 0.1, "max": 1000.0, "step": 1.0, "big": 10.0 },
}

## 저장 위치와 사용 여부. 헤드리스(테스트·시뮬레이션)에서는 기본으로 꺼져서 개발자 PC의 실제 설정 파일을 읽지도 쓰지도 않는다.
## 테스트가 저장·불러오기를 확인할 때는 configure(true, "user://settings_test/")처럼 격리 폴더를 쓴다.
static var enabled: bool = DisplayServer.get_name() != "headless"
static var storage_dir: String = "user://"
static var _active: UserSettings = null

## 바꾼 키만 들어 있다 (키 → 값)
var values: Dictionary = {}
## 읽다가 문제가 있어 무시·대체한 항목 설명
var errors: PackedStringArray = PackedStringArray()
var file_found: bool = false
## false면 파일은 있었지만 손상·버전 불명이라 전부 기본값으로 시작한 것
var file_ok: bool = true


## 사용 여부와 저장 폴더를 바꾸고 캐시를 비운다 (최고 기록 캐시도 함께).
static func configure(enable: bool, dir: String = "user://") -> void:
	enabled = enable
	storage_dir = dir
	_active = null
	HighScore.forget_active()


static func settings_path() -> String:
	return storage_dir.path_join(FILE_NAME)


## 지금 쓰는 설정. 꺼져 있으면(헤드리스) 빈 설정(= 전부 기본값)이다.
static func active() -> UserSettings:
	if _active == null:
		_active = load_from(settings_path()) if enabled else UserSettings.new()
	return _active


## 설정 화면의 "저장하고 닫기". 지금 쓰는 설정으로 삼고, 켜져 있으면 파일에도 쓴다. 파일 쓰기가 실패하면 false.
static func commit(settings: UserSettings) -> bool:
	_active = settings.duplicate_settings()
	if not enabled:
		return true
	return _active.save_to(settings_path())


static func keys() -> Array:
	return SPECS.keys()


static func group_of(key: String) -> String:
	return String(SPECS[key]["group"])


## 파일을 읽는다. 없으면 빈 설정, 손상·버전 불명이면 빈 설정 + file_ok=false(파일은 건드리지 않음), 범위 밖·모르는 키는 그 키만 버린다.
static func load_from(path: String) -> UserSettings:
	var settings: UserSettings = UserSettings.new()
	if not FileAccess.file_exists(path):
		return settings
	settings.file_found = true
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if text.is_empty() or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		settings.file_ok = false
		settings.errors.append("%s 를 읽을 수 없어 기본값을 씁니다" % path)
		return settings
	var raw: Dictionary = json.data
	var version: Variant = raw.get("version")
	var is_number: bool = typeof(version) == TYPE_INT or typeof(version) == TYPE_FLOAT
	if not is_number or int(version) != VERSION:
		settings.file_ok = false
		settings.errors.append("설정 파일 버전 %s 을(를) 알 수 없어 기본값을 씁니다" % [version])
		return settings
	var raw_values: Variant = raw.get("values")
	if typeof(raw_values) != TYPE_DICTIONARY:
		settings.file_ok = false
		settings.errors.append("values 항목이 없어 기본값을 씁니다")
		return settings
	for key: Variant in (raw_values as Dictionary):
		var name: String = str(key)
		if not SPECS.has(name):
			settings.errors.append("%s 은(는) 모르는 항목이라 무시" % name)
			continue
		var value: Variant = coerce(name, (raw_values as Dictionary)[key])
		if value == null:
			settings.errors.append("%s 값 %s 이(가) 범위를 벗어나 기본값 사용" % [name, (raw_values as Dictionary)[key]])
			continue
		settings.values[name] = value
	settings._check_win_tiers()
	return settings


## 값이 그 키의 형식·범위에 맞으면 형식에 맞춘 값을, 아니면 null을 돌려준다.
static func coerce(key: String, raw: Variant) -> Variant:
	if not SPECS.has(key):
		return null
	var spec: Dictionary = SPECS[key]
	if spec.has("bool"):
		return raw if typeof(raw) == TYPE_BOOL else null
	var is_number: bool = typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT
	if not is_number:
		return null
	var number: float = float(raw)
	if number < float(spec["min"]) or number > float(spec["max"]):
		return null
	if spec.has("int"):
		return int(number) if is_equal_approx(number, floorf(number)) else null
	return number


## 기본값(feel 객체·economy·AUTO 기준)을 키별로 모은 사전. feel은 Object의 get으로만 읽는다.
static func base_values(feel: Object, economy: Dictionary, auto_stop: int) -> Dictionary:
	var base: Dictionary = {}
	for key: String in SPECS:
		match group_of(key):
			GROUP_FEEL:
				base[key] = float(feel.get(key))
			GROUP_ECONOMY:
				base[key] = int(economy[key])
			GROUP_AUTO:
				base[key] = auto_stop
			_:
				base[key] = true
	return base


## 이 키를 한 단계(big이면 큰 단계) 움직인 새 값. 범위 끝이면 현재 값 그대로. current는 모든 키의 "지금 적용값" 사전이다.
## 당첨 중/대 기준은 서로를 넘지 못한다 (중 < 대).
static func step_value(key: String, current: Dictionary, direction: int, big: bool) -> Variant:
	var spec: Dictionary = SPECS[key]
	var now: Variant = current[key]
	if spec.has("bool"):
		return not bool(now)
	var amount: float = float(spec["big"] if big else spec["step"])
	var low: float = float(spec["min"])
	var high: float = float(spec["max"])
	if key == KEY_WIN_MID:
		high = minf(high, float(current[KEY_WIN_BIG]) - RATIO_GAP)
	elif key == KEY_WIN_BIG:
		low = maxf(low, float(current[KEY_WIN_MID]) + RATIO_GAP)
	var moved: float = clampf(float(now) + float(direction) * amount, low, high)
	if spec.has("int"):
		return int(roundf(moved))
	return snappedf(moved, FLOAT_DECIMALS_STEP)


func duplicate_settings() -> UserSettings:
	var copy: UserSettings = UserSettings.new()
	copy.values = values.duplicate()
	copy.errors = errors.duplicate()
	copy.file_found = file_found
	copy.file_ok = file_ok
	return copy


func has_value(key: String) -> bool:
	return values.has(key)


func get_or(key: String, fallback: Variant) -> Variant:
	return values.get(key, fallback)


## 범위·형식에 맞으면 넣고 true, 아니면 false (값은 그대로)
func set_value(key: String, raw: Variant) -> bool:
	var value: Variant = coerce(key, raw)
	if value == null:
		return false
	values[key] = value
	return true


func clear_value(key: String) -> void:
	values.erase(key)


## "기본값으로 되돌리기": 설정 값 전체를 지운다 (최고 기록은 별도 파일이라 그대로)
func clear_all() -> void:
	values.clear()


func is_empty() -> bool:
	return values.is_empty()


func bgm_enabled() -> bool:
	return bool(values.get(KEY_BGM_ENABLED, true))


## 덮어쓴 feel 키를 대상 객체(FeelConfig)에 넣는다. 중/대 기준이 어긋나면 둘 다 원래 값으로 되돌리고 false.
func apply_feel_values(target: Object) -> bool:
	var mid_before: Variant = target.get(KEY_WIN_MID)
	var big_before: Variant = target.get(KEY_WIN_BIG)
	for key: String in values:
		if group_of(key) == GROUP_FEEL:
			target.set(key, values[key])
	if float(target.get(KEY_WIN_MID)) >= float(target.get(KEY_WIN_BIG)):
		target.set(KEY_WIN_MID, mid_before)
		target.set(KEY_WIN_BIG, big_before)
		return false
	return true


## economy 기본값 위에 덮어쓴 값을 얹은 사전 (기본값 사전은 바꾸지 않는다)
func economy_values(base: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate()
	for key: String in values:
		if group_of(key) == GROUP_ECONOMY:
			merged[key] = values[key]
	return merged


func auto_stop_on_win_at(base: int) -> int:
	return int(values.get(KEY_AUTO_STOP, base))


## 임시 파일에 쓴 뒤 교체한다 (쓰다가 꺼져도 기존 파일이 반쯤 쓰인 채 남지 않게). 실패하면 false.
func save_to(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("UserSettings: %s 를 쓸 수 없음" % temp_path)
		return false
	file.store_string(JSON.stringify({ "version": VERSION, "values": values }, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path) == OK


## 중 기준이 대 기준 이상이면 두 값을 모두 버린다 (둘 다 파일에 있을 때)
func _check_win_tiers() -> void:
	if not (values.has(KEY_WIN_MID) and values.has(KEY_WIN_BIG)):
		return
	if float(values[KEY_WIN_MID]) < float(values[KEY_WIN_BIG]):
		return
	errors.append("win_mid_ratio가 win_big_ratio보다 작아야 해서 둘 다 기본값 사용")
	values.erase(KEY_WIN_MID)
	values.erase(KEY_WIN_BIG)

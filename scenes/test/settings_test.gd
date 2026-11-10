extends Node
## 운영자 설정(UserSettings)·최고 기록(HighScore) 테스트. 화면 없이 로직만 확인한다.
## 실행: godot --headless --path . res://scenes/test/settings_test.tscn
## 저장·불러오기는 개발자 PC의 실제 user://settings.json·highscore.json이 아니라 격리 폴더(user://settings_test/)만 쓴다.

const TEST_DIR: String = "user://settings_test/"
const DEFAULT_ECONOMY: Dictionary = { "coin_amount": 100, "start_credit": 3000, "continue_credit": 1000, "continue_max": 3 }

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	UserSettings.configure(false)
	_test_specs_match_game_ranges()
	_test_isolation_defaults()
	_test_coerce()
	_test_set_and_clear()
	_test_base_values_and_apply()
	_test_step_value()
	_test_win_ratio_rules()
	_test_file_missing()
	_test_save_and_load()
	_test_overwrite_save()
	_test_corrupt_and_version()
	_test_out_of_range_and_unknown()
	_test_commit_and_active()
	_test_highscore_rules()
	_test_highscore_file()
	_test_highscore_independent_of_settings()
	_clean_dir()
	UserSettings.configure(false)
	print("user:// 실제 위치: ", OS.get_user_data_dir())
	print("==================== SETTINGS TEST: %d 통과 / %d 실패 ====================" % [_passed, _failed])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", label)


func _clean_dir() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null or not dir.dir_exists("settings_test"):
		return
	var inner: DirAccess = DirAccess.open(TEST_DIR)
	for file_name: String in inner.get_files():
		inner.remove(file_name)
	dir.remove("settings_test")


func _write(file_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file: FileAccess = FileAccess.open(TEST_DIR + file_name, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _feel_base() -> FeelConfig:
	return FeelConfig.from_dict({})


func _base() -> Dictionary:
	return UserSettings.base_values(_feel_base(), DEFAULT_ECONOMY, 0)


# ---------------------------------------------------------------- 범위·키

## 설정 화면이 허용하는 범위가 게임이 실제로 받아들이는 범위와 같은지 (어긋나면 저장은 되는데 게임이 기본값으로 대체하게 됨)
func _test_specs_match_game_ranges() -> void:
	var same: bool = true
	var checked: int = 0
	for key: String in UserSettings.keys():
		if UserSettings.group_of(key) != UserSettings.GROUP_FEEL:
			continue
		var feel_spec: Array = FeelConfig.SPECS[key]
		var spec: Dictionary = UserSettings.SPECS[key]
		same = same and is_equal_approx(float(spec["min"]), float(feel_spec[1])) and is_equal_approx(float(spec["max"]), float(feel_spec[2]))
		checked += 1
	_check(same and checked == 8, "feel 키 8개의 범위가 FeelConfig.SPECS와 같음 (%d개 확인)" % checked)
	var economy_ok: bool = GameState.economy_from_dict({ "coin_amount": 1, "start_credit": 999999, "continue_credit": 999999, "continue_max": 99 }).size() == 4
	var economy_low: bool = GameState.economy_from_dict({ "coin_amount": 1, "start_credit": 1, "continue_credit": 1, "continue_max": 0 }).size() == 4
	var s: Dictionary = UserSettings.SPECS
	_check(economy_ok and economy_low and int(s["start_credit"]["max"]) == GameState.CREDIT_VALUE_MAX and int(s["continue_max"]["max"]) == GameState.CONTINUE_MAX_LIMIT, "economy 키의 범위가 GameState 로더와 같음")
	_check(int(s["start_credit"]["min"]) == 1 and int(s["continue_credit"]["min"]) == 1 and int(s["continue_max"]["min"]) == 0 and int(s["coin_amount"]["min"]) == 1, "economy 키의 최솟값(1/1/0/1)")
	_check(int(s["auto_stop_on_win_at"]["min"]) == 0 and UserSettings.group_of("auto_stop_on_win_at") == "auto", "AUTO 정지 기준은 0(사용 안 함) 이상")
	_check(UserSettings.keys().size() == 14 and not UserSettings.SPECS.has("balance") and not UserSettings.SPECS.has("pool_initial"), "설정 키는 14개, 밸런스 키는 없음")


func _test_isolation_defaults() -> void:
	_check(not UserSettings.enabled, "테스트에서는 설정 사용이 꺼져 있음 (실제 user:// 파일을 읽지 않음)")
	_check(UserSettings.active().is_empty() and UserSettings.active().bgm_enabled(), "꺼져 있으면 빈 설정(전부 기본값, BGM 켜짐)")
	var score: HighScore = HighScore.active()
	_check(score.path.is_empty() and score.best_peak_credit == 0, "꺼져 있으면 최고 기록은 파일 없이 메모리에만")
	score.submit(500, false)
	_check(score.best_peak_credit == 500 and score.path.is_empty(), "꺼진 상태의 기록은 메모리에만 쌓임 (path가 비어 파일을 쓰지 않음)")
	UserSettings.configure(false)
	_check(HighScore.active().best_peak_credit == 0, "configure가 최고 기록 캐시도 비움")


func _test_coerce() -> void:
	_check(UserSettings.coerce("sfx_volume_db", -3) == -3.0 and UserSettings.coerce("sfx_volume_db", 6.0) == 6.0 and UserSettings.coerce("sfx_volume_db", -40.0) == -40.0, "볼륨 범위 안 값 (경계 포함)")
	_check(UserSettings.coerce("sfx_volume_db", 6.5) == null and UserSettings.coerce("sfx_volume_db", -41) == null, "볼륨 범위 밖은 null")
	_check(UserSettings.coerce("sfx_volume_db", "3") == null and UserSettings.coerce("sfx_volume_db", true) == null and UserSettings.coerce("sfx_volume_db", null) == null, "숫자가 아닌 값은 null")
	_check(UserSettings.coerce("start_credit", 3000) == 3000 and typeof(UserSettings.coerce("start_credit", 3000.0)) == TYPE_INT, "정수 키는 정수로 돌려줌")
	_check(UserSettings.coerce("start_credit", 3000.5) == null and UserSettings.coerce("start_credit", 0) == null and UserSettings.coerce("start_credit", 1000000) == null, "정수 키: 소수·0·100만은 null")
	_check(UserSettings.coerce("continue_max", 0) == 0 and UserSettings.coerce("continue_max", 99) == 99 and UserSettings.coerce("continue_max", 100) == null and UserSettings.coerce("continue_max", -1) == null, "CONTINUE 횟수 0~99")
	_check(UserSettings.coerce("bgm_enabled", false) == false and UserSettings.coerce("bgm_enabled", 0) == null and UserSettings.coerce("bgm_enabled", "false") == null, "BGM 켜기/끄기는 true/false만")
	_check(UserSettings.coerce("nope", 1) == null, "모르는 키는 null")


func _test_set_and_clear() -> void:
	var s: UserSettings = UserSettings.new()
	_check(s.set_value("start_credit", 5000) and s.has_value("start_credit") and s.get_or("start_credit", 0) == 5000, "값 넣기")
	_check(not s.set_value("start_credit", 0) and s.get_or("start_credit", 0) == 5000, "범위 밖 값은 거절하고 이전 값 유지")
	s.set_value("bgm_enabled", false)
	_check(not s.bgm_enabled(), "BGM 끄기")
	s.clear_value("start_credit")
	_check(not s.has_value("start_credit") and s.get_or("start_credit", 3000) == 3000, "키 하나 지우면 기본값으로")
	var copy: UserSettings = s.duplicate_settings()
	copy.set_value("continue_max", 5)
	_check(not s.has_value("continue_max") and copy.has_value("continue_max"), "복사본을 바꿔도 원본은 그대로")
	s.clear_all()
	_check(s.is_empty() and s.bgm_enabled(), "기본값으로 되돌리기: 전부 지움")


func _test_base_values_and_apply() -> void:
	var base: Dictionary = _base()
	var feel: FeelConfig = _feel_base()
	_check(base.size() == 14 and base["sfx_volume_db"] == feel.sfx_volume_db and base["start_credit"] == 3000 and base["auto_stop_on_win_at"] == 0 and base["bgm_enabled"] == true, "기본값 사전: feel·economy·AUTO·BGM")
	var s: UserSettings = UserSettings.new()
	s.set_value("bgm_volume_db", -20.0)
	s.set_value("countup_big_sec", 4.0)
	s.set_value("start_credit", 777)
	s.set_value("auto_stop_on_win_at", 5000)
	var target: FeelConfig = _feel_base()
	_check(s.apply_feel_values(target) and target.bgm_volume_db == -20.0 and target.countup_big_sec == 4.0, "feel 키만 덮어씀")
	_check(target.sfx_volume_db == feel.sfx_volume_db and target.countup_small_sec == feel.countup_small_sec, "바꾸지 않은 feel 키는 feel 값 그대로 (feel.json 수정이 계속 반영됨)")
	var economy: Dictionary = s.economy_values(DEFAULT_ECONOMY)
	_check(economy["start_credit"] == 777 and economy["continue_credit"] == 1000 and economy["continue_max"] == 3 and economy["coin_amount"] == 100, "economy: 바꾼 키만 덮어씀")
	_check(DEFAULT_ECONOMY["start_credit"] == 3000, "기본 economy 사전은 바뀌지 않음")
	_check(s.auto_stop_on_win_at(0) == 5000 and UserSettings.new().auto_stop_on_win_at(1234) == 1234, "AUTO 정지 기준: 덮어쓰기 / 기본값")
	# feel.json이 바뀐 것처럼: 기본값이 달라져도 바꾸지 않은 키는 새 기본값을 따른다
	var other_feel: FeelConfig = FeelConfig.from_dict({ "sfx_volume_db": -7.0 })
	s.apply_feel_values(other_feel)
	_check(other_feel.sfx_volume_db == -7.0 and other_feel.bgm_volume_db == -20.0, "feel.json 값이 바뀌어도 안 바꾼 키는 새 값, 바꾼 키는 설정값")


func _test_step_value() -> void:
	var cur: Dictionary = _base()
	_check(UserSettings.step_value("sfx_volume_db", cur, -1, false) == cur["sfx_volume_db"] - 1.0, "SFX 볼륨 -1 dB")
	_check(UserSettings.step_value("sfx_volume_db", cur, 1, true) == minf(6.0, cur["sfx_volume_db"] + 5.0), "Shift: SFX 볼륨 +5 dB (최대 6에서 멈춤)")
	cur["sfx_volume_db"] = 6.0
	_check(UserSettings.step_value("sfx_volume_db", cur, 1, false) == 6.0, "최대에서 더 올려도 6")
	cur["sfx_volume_db"] = -40.0
	_check(UserSettings.step_value("sfx_volume_db", cur, -1, true) == -40.0, "최소에서 더 내려도 -40")
	_check(UserSettings.step_value("start_credit", _base(), 1, false) == 3100 and UserSettings.step_value("start_credit", _base(), 1, true) == 4000, "시작 크레딧 +100 / Shift +1,000")
	_check(UserSettings.step_value("continue_credit", _base(), -1, false) == 900 and UserSettings.step_value("continue_credit", _base(), -1, true) == 1, "CONTINUE 코인 -100 / Shift 1,000 아래는 1에서 멈춤")
	_check(UserSettings.step_value("coin_amount", _base(), 1, false) == 110 and UserSettings.step_value("coin_amount", _base(), 1, true) == 200, "COIN 지급량 +10 / Shift +100")
	_check(UserSettings.step_value("continue_max", _base(), 1, false) == 4 and UserSettings.step_value("continue_max", _base(), -1, true) == 0, "CONTINUE 횟수 +1 / Shift -5는 0에서 멈춤")
	_check(UserSettings.step_value("auto_stop_on_win_at", _base(), 1, false) == 1000 and UserSettings.step_value("auto_stop_on_win_at", _base(), -1, false) == 0, "AUTO 정지 기준 0 → +1,000, 0 아래로는 안 내려감")
	_check(UserSettings.step_value("bgm_enabled", _base(), 1, false) == false and UserSettings.step_value("bgm_enabled", { "bgm_enabled": false }, -1, false) == true, "BGM 켜기/끄기는 방향과 상관없이 반전")
	var f: Dictionary = _base()
	f["auto_effect_scale"] = 0.5
	_check(UserSettings.step_value("auto_effect_scale", f, 1, false) == 0.6 and UserSettings.step_value("auto_effect_scale", f, 1, true) == 0.8, "AUTO 연출 배율 +0.1 / Shift +0.3 (소수 오차 없음)")
	f["auto_effect_scale"] = 0.9
	_check(UserSettings.step_value("auto_effect_scale", f, 1, true) == 1.0, "AUTO 연출 배율 최대 1.0")
	f["countup_small_sec"] = 0.1
	_check(UserSettings.step_value("countup_small_sec", f, -1, false) == 0.05, "정산 연출 시간 최소 0.05")


func _test_win_ratio_rules() -> void:
	var cur: Dictionary = _base()
	cur["win_mid_ratio"] = 9.5
	cur["win_big_ratio"] = 10.0
	_check(UserSettings.step_value("win_mid_ratio", cur, 1, false) == 9.9 and UserSettings.step_value("win_mid_ratio", cur, 1, true) == 9.9, "당첨 중 기준은 대 기준 아래(간격 0.1)까지만 오름")
	cur["win_mid_ratio"] = 9.9
	_check(UserSettings.step_value("win_mid_ratio", cur, 1, false) == 9.9, "중 기준이 이미 대 기준 - 0.1이면 더 안 오름")
	cur["win_mid_ratio"] = 2.0
	cur["win_big_ratio"] = 2.1
	_check(UserSettings.step_value("win_big_ratio", cur, -1, true) == 2.1, "당첨 대 기준은 중 기준 + 0.1 아래로 안 내려감")
	# 파일에 중 ≥ 대가 저장돼 있으면 둘 다 버림
	_write("settings.json", JSON.stringify({ "version": 1, "values": { "win_mid_ratio": 20.0, "win_big_ratio": 5.0, "start_credit": 4000 } }))
	var loaded: UserSettings = UserSettings.load_from(TEST_DIR + "settings.json")
	_check(not loaded.has_value("win_mid_ratio") and not loaded.has_value("win_big_ratio") and loaded.get_or("start_credit", 0) == 4000 and not loaded.errors.is_empty(), "파일의 중 ≥ 대 기준은 둘 다 버리고 나머지는 유지")
	# 파일엔 한쪽만 있어도 feel.json 값과 어긋나면 되돌림
	var s: UserSettings = UserSettings.new()
	s.set_value("win_mid_ratio", 50.0)
	var target: FeelConfig = _feel_base()
	var mid: float = target.win_mid_ratio
	var big: float = target.win_big_ratio
	_check(not s.apply_feel_values(target) and target.win_mid_ratio == mid and target.win_big_ratio == big, "한쪽만 저장됐는데 feel 값과 어긋나면 둘 다 feel 값으로 되돌림")


# ---------------------------------------------------------------- 파일

func _test_file_missing() -> void:
	_clean_dir()
	var s: UserSettings = UserSettings.load_from(TEST_DIR + "settings.json")
	_check(s.is_empty() and not s.file_found and s.file_ok and s.errors.is_empty(), "파일이 없으면 빈 설정, 문제 없음")


func _test_save_and_load() -> void:
	var s: UserSettings = UserSettings.new()
	s.set_value("sfx_volume_db", -8.0)
	s.set_value("bgm_enabled", false)
	s.set_value("start_credit", 5000)
	s.set_value("auto_stop_on_win_at", 20000)
	s.set_value("countup_mid_sec", 1.5)
	_check(s.save_to(TEST_DIR + "settings.json"), "저장 성공 (폴더가 없어도 만듦)")
	_check(not FileAccess.file_exists(TEST_DIR + "settings.json.tmp"), "임시 파일은 남지 않음")
	var text: String = FileAccess.get_file_as_string(TEST_DIR + "settings.json")
	var json: JSON = JSON.new()
	_check(json.parse(text) == OK and int(json.data["version"]) == 1 and (json.data["values"] as Dictionary).size() == 5, "JSON 구조: version 1 + values 5개 (바꾼 키만)")
	var loaded: UserSettings = UserSettings.load_from(TEST_DIR + "settings.json")
	_check(loaded.file_found and loaded.file_ok and loaded.errors.is_empty(), "다시 읽기 성공")
	_check(loaded.get_or("sfx_volume_db", 0.0) == -8.0 and not loaded.bgm_enabled() and loaded.get_or("start_credit", 0) == 5000 and loaded.get_or("auto_stop_on_win_at", 0) == 20000 and loaded.get_or("countup_mid_sec", 0.0) == 1.5, "저장한 값이 그대로 돌아옴")
	_check(typeof(loaded.get_or("start_credit", 0)) == TYPE_INT and typeof(loaded.get_or("sfx_volume_db", 0.0)) == TYPE_FLOAT, "정수 키는 정수, 소수 키는 소수로 읽힘")
	_check(not loaded.has_value("bgm_volume_db") and not loaded.has_value("continue_credit"), "안 바꾼 키는 파일에 없음")


func _test_overwrite_save() -> void:
	var s: UserSettings = UserSettings.load_from(TEST_DIR + "settings.json")
	s.set_value("start_credit", 6000)
	s.clear_value("sfx_volume_db")
	_check(s.save_to(TEST_DIR + "settings.json"), "이미 있는 파일 위에 다시 저장 성공")
	var again: UserSettings = UserSettings.load_from(TEST_DIR + "settings.json")
	_check(again.get_or("start_credit", 0) == 6000 and not again.has_value("sfx_volume_db"), "덮어쓴 값이 반영되고 지운 키는 빠짐")
	again.clear_all()
	again.save_to(TEST_DIR + "settings.json")
	_check(UserSettings.load_from(TEST_DIR + "settings.json").is_empty(), "기본값으로 되돌린 뒤 저장하면 빈 설정")


func _test_corrupt_and_version() -> void:
	_write("settings.json", "{ 깨진 파일")
	var corrupt: UserSettings = UserSettings.load_from(TEST_DIR + "settings.json")
	_check(corrupt.is_empty() and corrupt.file_found and not corrupt.file_ok and not corrupt.errors.is_empty(), "손상된 파일: 전부 기본값, file_ok=false")
	_check(FileAccess.get_file_as_string(TEST_DIR + "settings.json") == "{ 깨진 파일", "손상된 파일은 읽기만 하고 건드리지 않음")
	_write("settings.json", "")
	_check(not UserSettings.load_from(TEST_DIR + "settings.json").file_ok, "빈 파일도 손상 취급")
	_write("settings.json", "[1, 2]")
	_check(not UserSettings.load_from(TEST_DIR + "settings.json").file_ok, "JSON이지만 사전이 아니면 손상 취급")
	_write("settings.json", JSON.stringify({ "version": 99, "values": { "start_credit": 5000 } }))
	var future: UserSettings = UserSettings.load_from(TEST_DIR + "settings.json")
	_check(future.is_empty() and not future.file_ok, "모르는 버전은 전부 기본값 (새 버전 파일을 잘못 해석하지 않음)")
	_write("settings.json", JSON.stringify({ "values": { "start_credit": 5000 } }))
	_check(not UserSettings.load_from(TEST_DIR + "settings.json").file_ok, "버전이 없으면 거절")
	_write("settings.json", JSON.stringify({ "version": 1 }))
	_check(not UserSettings.load_from(TEST_DIR + "settings.json").file_ok, "values가 없으면 거절")


func _test_out_of_range_and_unknown() -> void:
	_write("settings.json", JSON.stringify({ "version": 1, "values": {
		"sfx_volume_db": 99.0, "start_credit": 0, "continue_max": 2.5, "bgm_enabled": "yes",
		"bgm_volume_db": -10.0, "continue_credit": 1500, "pool_initial": 9999, "fever_cherry": 1 } }))
	var s: UserSettings = UserSettings.load_from(TEST_DIR + "settings.json")
	_check(s.file_ok and not s.has_value("sfx_volume_db") and not s.has_value("start_credit") and not s.has_value("continue_max") and not s.has_value("bgm_enabled"), "범위 밖·형식 틀린 값은 그 키만 기본값")
	_check(s.get_or("bgm_volume_db", 0.0) == -10.0 and s.get_or("continue_credit", 0) == 1500, "정상 값은 유지")
	_check(not s.has_value("pool_initial") and not s.has_value("fever_cherry"), "밸런스 키 등 모르는 키는 무시 (설정 파일로 밸런스를 바꿀 수 없음)")
	_check(s.errors.size() == 6, "무시·대체한 항목 6개가 기록됨 (%d)" % s.errors.size())


func _test_commit_and_active() -> void:
	_clean_dir()
	UserSettings.configure(true, TEST_DIR)
	_check(UserSettings.active().is_empty() and UserSettings.settings_path() == TEST_DIR + "settings.json", "켜짐 + 격리 폴더: 파일 없으면 빈 설정, 경로는 격리 폴더")
	var draft: UserSettings = UserSettings.active().duplicate_settings()
	draft.set_value("start_credit", 4500)
	_check(UserSettings.commit(draft), "commit 성공")
	_check(UserSettings.active().get_or("start_credit", 0) == 4500 and FileAccess.file_exists(TEST_DIR + "settings.json"), "commit 뒤 지금 설정이 바뀌고 파일도 저장됨")
	draft.set_value("start_credit", 9999)
	_check(UserSettings.active().get_or("start_credit", 0) == 4500, "commit 뒤 초안을 바꿔도 지금 설정은 그대로 (복사본)")
	UserSettings.configure(true, TEST_DIR)
	_check(UserSettings.active().get_or("start_credit", 0) == 4500, "다음 실행(다시 읽기)에서도 적용됨")
	UserSettings.configure(false)
	_check(UserSettings.active().is_empty(), "꺼두면 파일이 있어도 읽지 않음")
	var before: String = FileAccess.get_file_as_string(TEST_DIR + "settings.json")
	var other: UserSettings = UserSettings.new()
	other.set_value("start_credit", 1234)
	_check(UserSettings.commit(other) and FileAccess.get_file_as_string(TEST_DIR + "settings.json") == before, "꺼져 있으면 commit이 파일을 쓰지 않음 (메모리만)")
	UserSettings.configure(false)


# ---------------------------------------------------------------- 최고 기록

func _test_highscore_rules() -> void:
	var score: HighScore = HighScore.new()
	_check(score.best_peak_credit == 0, "처음 기록 0")
	_check(score.submit(5000, false) and score.best_peak_credit == 5000, "새 기록이면 갱신")
	_check(not score.submit(4000, false) and score.best_peak_credit == 5000, "더 작으면 갱신 안 함")
	_check(not score.submit(5000, false) and score.best_peak_credit == 5000, "같으면 갱신 안 함")
	_check(not score.submit(90000, true) and score.best_peak_credit == 5000, "테스트 판(run_tainted)은 더 커도 기록하지 않음")
	_check(score.submit(5001, false) and score.best_peak_credit == 5001, "테스트 판이 아니면 1만 커도 갱신")
	score.reset()
	_check(score.best_peak_credit == 0, "초기화하면 0")


func _test_highscore_file() -> void:
	_clean_dir()
	var path: String = TEST_DIR + "highscore.json"
	var score: HighScore = HighScore.load_from(path)
	_check(score.best_peak_credit == 0 and score.file_ok and not FileAccess.file_exists(path), "파일이 없으면 기록 0, 파일은 만들지 않음")
	score.submit(7777, false)
	_check(FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp"), "새 기록을 저장 (임시 파일 남지 않음)")
	var json: JSON = JSON.new()
	_check(json.parse(FileAccess.get_file_as_string(path)) == OK and int(json.data["version"]) == 1 and int(json.data["best_peak_credit"]) == 7777, "JSON 구조: version 1 + best_peak_credit")
	_check(HighScore.load_from(path).best_peak_credit == 7777, "다시 읽으면 같은 기록")
	score.submit(8000, false)
	score.submit(100, false)
	_check(HighScore.load_from(path).best_peak_credit == 8000, "더 작은 기록은 파일을 바꾸지 않음, 큰 기록은 덮어씀")
	var tainted_before: String = FileAccess.get_file_as_string(path)
	score.submit(99999, true)
	_check(FileAccess.get_file_as_string(path) == tainted_before, "테스트 판은 파일도 바꾸지 않음")
	score.reset()
	_check(HighScore.load_from(path).best_peak_credit == 0, "초기화가 파일에도 반영")
	_write("highscore.json", "{ 깨짐")
	var broken: HighScore = HighScore.load_from(path)
	_check(broken.best_peak_credit == 0 and not broken.file_ok, "손상된 기록 파일: 0으로 시작, file_ok=false")
	_write("highscore.json", JSON.stringify({ "version": 1, "best_peak_credit": -5 }))
	_check(not HighScore.load_from(path).file_ok, "음수 기록은 손상 취급")
	_write("highscore.json", JSON.stringify({ "version": 7, "best_peak_credit": 100 }))
	_check(not HighScore.load_from(path).file_ok and HighScore.load_from(path).best_peak_credit == 0, "모르는 버전은 기록 0")
	_write("highscore.json", JSON.stringify({ "version": 1, "best_peak_credit": 12.5 }))
	_check(not HighScore.load_from(path).file_ok, "소수 기록은 손상 취급")


func _test_highscore_independent_of_settings() -> void:
	_clean_dir()
	UserSettings.configure(true, TEST_DIR)
	var score: HighScore = HighScore.active()
	_check(score.path == TEST_DIR + "highscore.json", "켜짐: 최고 기록 파일도 격리 폴더 안")
	score.submit(4321, false)
	var settings: UserSettings = UserSettings.active().duplicate_settings()
	settings.set_value("start_credit", 2000)
	UserSettings.commit(settings)
	settings.clear_all()
	UserSettings.commit(settings)
	_check(HighScore.load_from(TEST_DIR + "highscore.json").best_peak_credit == 4321, "설정을 기본값으로 되돌려도 최고 기록은 남음 (파일 분리)")
	_check(UserSettings.load_from(TEST_DIR + "settings.json").is_empty(), "설정은 지워져 있음")
	UserSettings.configure(false)

class_name HighScore
extends RefCounted
## 최고 기록(8-A): 한 판(NEW GAME 이후)의 최고 크레딧(run_peak_credit)의 최댓값. user://highscore.json에 저장한다.
## 설정 파일과 분리해서 "설정 기본값으로 되돌리기"가 기록을 지우지 않는다. 테스트 판(run_tainted)은 기록하지 않는다.
## 화면·Node에 의존하지 않는다.

const FILE_NAME: String = "highscore.json"
const VERSION: int = 1

static var _active: HighScore = null

var best_peak_credit: int = 0
## 저장 파일 경로. 빈 문자열이면 메모리에만 둔다 (헤드리스 테스트)
var path: String = ""
## false면 파일이 손상·버전 불명이라 기록 0으로 시작한 것
var file_ok: bool = true


static func default_path() -> String:
	return UserSettings.storage_dir.path_join(FILE_NAME)


## 지금 쓰는 기록. UserSettings.enabled가 꺼져 있으면(헤드리스) 파일 없이 메모리에만 둔다.
static func active() -> HighScore:
	if _active == null:
		_active = load_from(default_path()) if UserSettings.enabled else HighScore.new()
	return _active


static func forget_active() -> void:
	_active = null


## 파일을 읽는다. 없거나 손상됐거나 값이 이상하면 기록 0 (손상이면 file_ok=false). 이 인스턴스는 이 경로에 저장한다.
static func load_from(file_path: String) -> HighScore:
	var score: HighScore = HighScore.new()
	score.path = file_path
	if not FileAccess.file_exists(file_path):
		return score
	var json: JSON = JSON.new()
	var text: String = FileAccess.get_file_as_string(file_path)
	if text.is_empty() or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		score.file_ok = false
		return score
	var raw: Dictionary = json.data
	var version: Variant = raw.get("version")
	var best: Variant = raw.get("best_peak_credit")
	var numbers: bool = (typeof(version) == TYPE_INT or typeof(version) == TYPE_FLOAT) and (typeof(best) == TYPE_INT or typeof(best) == TYPE_FLOAT)
	if not numbers or int(version) != VERSION or float(best) < 0.0 or not is_equal_approx(float(best), floorf(float(best))):
		score.file_ok = false
		return score
	score.best_peak_credit = int(best)
	return score


## 판이 끝났을 때(GAME OVER·창 닫기) 부른다. 테스트 판이거나 기존 기록 이하면 아무것도 하지 않고 false. 새 기록이면 저장하고 true.
func submit(peak_credit: int, tainted: bool) -> bool:
	if tainted or peak_credit <= best_peak_credit:
		return false
	best_peak_credit = peak_credit
	_save()
	return true


## 최고 기록 초기화 (운영자가 설정 화면에서 두 번 눌렀을 때)
func reset() -> void:
	best_peak_credit = 0
	_save()


func _save() -> bool:
	if path.is_empty():
		return true
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("HighScore: %s 를 쓸 수 없음" % temp_path)
		return false
	file.store_string(JSON.stringify({ "version": VERSION, "best_peak_credit": best_peak_credit }, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path) == OK

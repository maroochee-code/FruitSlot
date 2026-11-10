extends Node
## 6-F2 BGM 확인 씬: 메인↔피버 전환과 곡 끝 반복 이음새를 직접 들어 본다. 게임 규칙·결과와 무관하다.
## 실행: scenes/test/bgm_preview.tscn 을 열고 F6(현재 씬 실행). 헤드폰 권장.
## 전환·반복 시간과 볼륨은 data/feel.json 값을 쓴다 (고친 뒤 이 씬을 다시 실행하면 반영된다).

const JUMP_BEFORE_LOOP_SEC: float = 4.0
const VOLUME_STEP_DB: float = 3.0
const LOG_SHOWN: int = 6
const HELP_TEXT: String = "[BGM 확인] 시작하면 메인 BGM이 페이드인합니다\nM 메인 곡으로   F 피버 곡으로(메인은 멈춘 자리를 기억, 피버는 처음부터)\nJ 지금 곡을 반복 지점 %.0f초 전으로 이동 → 곡 끝 반복 이음새를 들어 보세요\nS 모두 끄기 / 다시 시작   -/= BGM 볼륨 3dB씩 (지금 %.0f dB)\n\n곡: %s   위치: %.1f / %.1f초   반복 지점: %.1f초\n음량 main %.2f / fever %.2f   재생기 %d개\n\n최근 요청:\n%s"
const HELP_RECT: Rect2 = Rect2(16, 16, 608, 440)

var _bgm: BgmPlayer
var _feel: FeelConfig
var _label: Label = Label.new()
var _volume_db: float = 0.0


func _ready() -> void:
	_feel = FeelConfig.load_from_file()
	_volume_db = _feel.bgm_volume_db
	_bgm = BgmPlayer.new()
	add_child(_bgm)
	_bgm.apply_feel(_feel)
	_bgm.start()
	_label.position = HELP_RECT.position
	_label.size = HELP_RECT.size
	_label.theme = UiSkin.make_theme()
	add_child(_label)
	print("[bgm_preview] M 메인 / F 피버 / J 반복 지점 앞으로 / S 끄기·켜기 / -,= 볼륨")


func _process(delta: float) -> void:
	_bgm.advance(delta)
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_M:
			_bgm.switch_to(BgmPlayer.TRACK_MAIN)
		KEY_F:
			_bgm.switch_to(BgmPlayer.TRACK_FEVER)
		KEY_J:
			var length: float = _bgm.track_length(_bgm.current_track())
			_bgm.seek(maxf(0.0, BgmPlayer.loop_point(length, _feel.bgm_loop_trim_sec) - JUMP_BEFORE_LOOP_SEC))
		KEY_S:
			if _bgm.current_track() == &"":
				_bgm.start()
			else:
				_bgm.stop_all()
		KEY_MINUS:
			_set_volume(_volume_db - VOLUME_STEP_DB)
		KEY_EQUAL:
			_set_volume(_volume_db + VOLUME_STEP_DB)


func _set_volume(db: float) -> void:
	_volume_db = clampf(db, -40.0, 6.0)
	var index: int = AudioServer.get_bus_index(SoundBank.BUS_BGM)
	AudioServer.set_bus_volume_db(index, _volume_db)


func _refresh() -> void:
	var track: StringName = _bgm.current_track()
	var length: float = _bgm.track_length(track)
	var recent: PackedStringArray = PackedStringArray()
	var requests: Array[StringName] = _bgm.requests()
	for i: int in range(maxi(0, requests.size() - LOG_SHOWN), requests.size()):
		recent.append(String(requests[i]))
	_label.text = HELP_TEXT % [JUMP_BEFORE_LOOP_SEC, _volume_db, String(track) if track != &"" else "(꺼짐)", maxf(0.0, _bgm.position_of(track)), length,
			BgmPlayer.loop_point(length, _feel.bgm_loop_trim_sec), _bgm.gain_of(BgmPlayer.TRACK_MAIN), _bgm.gain_of(BgmPlayer.TRACK_FEVER), _bgm.active_voices(), "\n".join(recent)]

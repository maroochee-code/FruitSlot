extends Node
## 6-F1 효과음 확인 씬: 키 하나에 소리 하나. 게임 규칙·결과·balance.json과 무관하다.
## 실행: scenes/test/sound_preview.tscn 을 열고 F6(현재 씬 실행). 헤드폰 권장.

const KEY_SOUNDS: Dictionary = {
	KEY_1: SoundBank.NAME_COIN,
	KEY_2: SoundBank.NAME_BET,
	KEY_3: SoundBank.NAME_CANCEL,
	KEY_4: SoundBank.NAME_START,
	KEY_5: SoundBank.NAME_REEL_STOP,
	KEY_6: SoundBank.NAME_WIN_SMALL,
	KEY_7: SoundBank.NAME_WIN_MID,
	KEY_8: SoundBank.NAME_WIN_BIG,
	KEY_9: SoundBank.NAME_FEVER_START,
	KEY_0: SoundBank.NAME_FEVER_END,
	KEY_P: SoundBank.NAME_POOL_GET,
	KEY_B: SoundBank.NAME_BUTTON,
	KEY_G: SoundBank.NAME_GAMEOVER,
}
const VOLUME_STEP_DB: float = 3.0
const HELP_TEXT: String = "[효과음 확인] 키 하나에 소리 하나\n1 coin  2 bet  3 cancel  4 start  5 reel_stop\n6 win_small  7 win_mid  8 win_big\n9 fever_start  0 fever_end  P pool_get\nB button  G gameover(파일만, 게임에는 아직 연결 안 함)\nL 릴 회전음(반복) 켜기/끄기   S 재생 중인 소리 끊기\n- / = SFX 볼륨 낮추기/높이기 (3dB씩)\n\n볼륨: %.0f dB"
const HELP_RECT: Rect2 = Rect2(16, 16, 608, 400)

var _bank: SoundBank
var _label: Label = Label.new()
var _volume_db: float = 0.0


func _ready() -> void:
	_bank = SoundBank.new()
	add_child(_bank)
	_label.position = HELP_RECT.position
	_label.size = HELP_RECT.size
	_label.theme = UiSkin.make_theme()
	add_child(_label)
	_refresh()
	print("[sound_preview] 키 1~0, P, B, G = 소리 / L = 회전음 / S = 끊기 / - = 볼륨")


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if KEY_SOUNDS.has(key.keycode):
		_bank.play(KEY_SOUNDS[key.keycode])
		return
	match key.keycode:
		KEY_L:
			if _bank.is_loop_on(SoundBank.NAME_REEL_SPIN):
				_bank.stop_loop(SoundBank.NAME_REEL_SPIN)
			else:
				_bank.play_loop(SoundBank.NAME_REEL_SPIN)
		KEY_S:
			_bank.cut_oneshots()
		KEY_MINUS:
			_set_volume(_volume_db - VOLUME_STEP_DB)
		KEY_EQUAL:
			_set_volume(_volume_db + VOLUME_STEP_DB)


func _set_volume(db: float) -> void:
	_volume_db = clampf(db, -40.0, 6.0)
	_bank.set_sfx_volume_db(_volume_db)
	_refresh()


func _refresh() -> void:
	_label.text = HELP_TEXT % _volume_db

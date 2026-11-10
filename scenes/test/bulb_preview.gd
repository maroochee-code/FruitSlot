extends Node
## 6-F3a 전구 확인 씬: 진짜 메인 화면에서 전구 모양(대기/스핀/당첨/피버)을 키로 바꿔 가며 본다. 게임 규칙·결과와 무관하다.
## 실행: scenes/test/bulb_preview.tscn 을 열고 F6(현재 씬 실행). 전구 속도는 data/feel.json의 bulb_* 값을 쓴다.
## 키: 1 대기 / 2 스핀 / 3 당첨 / 4 피버 (누르면 그 모양이 계속 반복된다)

const LEGEND_TEXT: String = "1 대기  2 스핀  3 당첨  4 피버"
const LEGEND_POS: Vector2 = Vector2(110, 2)

var _main: Control


func _ready() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	# 전구만 본다: 메인이 시작한 BGM은 끈다
	(_main.bgm_player() as BgmPlayer).stop_all()
	var legend: Label = Label.new()
	legend.text = LEGEND_TEXT
	legend.position = LEGEND_POS
	legend.theme = UiSkin.make_theme()
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(legend)
	print("[bulb_preview] ", LEGEND_TEXT)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_show(BulbPattern.Mode.IDLE)
		KEY_2:
			_show(BulbPattern.Mode.SPIN)
		KEY_3:
			_show(BulbPattern.Mode.WIN)
		KEY_4:
			_show(BulbPattern.Mode.FEVER)


func _show(mode: int) -> void:
	_main.board_view().set_mode(mode)
	_main.frame_bulbs().set_mode(mode)

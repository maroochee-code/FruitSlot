class_name BgmPlayer
extends Node
## BGM 재생기 (6-F2). 메인 곡(main)을 반복 재생하고, 피버 연출 때 피버 곡(fever)으로 전환했다가 돌아온다.
## - 곡 반복은 mp3 임포트 설정(loop)이 아니라 코드로 한다: 곡 끝 bgm_loop_trim_sec 전에 같은 곡을 처음부터 다시 틀면서
##   이전 소리를 bgm_loop_fade_sec 동안 줄인다. 곡 끝의 페이드아웃·무음과 겹쳐서 이음새가 안 들린다.
## - 메인 → 피버: 메인은 끄지 않고 일시정지(위치 기억)하고, 피버 곡은 매번 처음부터 튼다.
## - 피버 → 메인: 피버 곡은 줄이며 끄고, 메인은 멈춘 자리부터 이어서 튼다.
## - 소리 크기 변화는 등전력(equal-power) 곡선이다. 재생기마다 위치·음량을 코드에서 직접 세기 때문에
##   시간을 advance()로 흘려서 테스트할 수 있다 (실제 재생은 엔진이 같은 속도로 한다).
## - 요청은 재생 여부와 상관없이 기록에 남는다. 헤드리스(소리 장치 없음)에서는 실제 재생을 끈다.
## 곡 파일은 사용자가 Suno로 만든 것이다 (출처·조건: docs/credits.md).

const TRACK_MAIN: StringName = &"main"
const TRACK_FEVER: StringName = &"fever"
const TRACK_PATHS: Dictionary = {
	TRACK_MAIN: "res://assets/sounds/bgm_main.mp3",
	TRACK_FEVER: "res://assets/sounds/bgm_fever.mp3",
}
## 재생기 수: 메인, 피버, 반복 겹침, 여유 1
const VOICE_COUNT: int = 4
## 사실상 무음(dB)
const SILENT_DB: float = -80.0
const MIN_GAIN: float = 0.0001
const LOG_MAX: int = 256
## 요청 기록 이름
const LOG_START: String = "start:"
const LOG_SWITCH: String = "to:"
const LOG_LOOP: String = "loop:"
const LOG_STOP: StringName = &"stop"

enum After { NONE, PAUSE, STOP }


## 재생기 하나의 상태 (실제 AudioStreamPlayer + 코드가 세는 위치·음량)
class Voice:
	extends RefCounted
	var player: AudioStreamPlayer
	var track: StringName = &""
	## 곡 안에서 지금 위치(초). 일시정지 중에는 멈춰 있다.
	var pos: float = 0.0
	var paused: bool = false
	var gain: float = 0.0
	var fading: bool = false
	var fade_from: float = 0.0
	var fade_to: float = 0.0
	var fade_p: float = 0.0
	var fade_len: float = 0.0
	## 줄이는 전환이 끝났을 때 할 일 (After 값. 안쪽 클래스라 숫자 0 = NONE)
	var after: int = 0
	## 곡 끝 반복 겹침을 이미 시작했는지
	var loop_done: bool = false
	## 이번 advance()에서 막 만들어졌다면 true: 이번 프레임의 시간은 아직 세지 않는다 (큰 delta에서 페이드가 한 번에 끝나는 것 방지)
	var skip_tick: bool = false


## false면 요청·상태만 세고 실제로는 재생하지 않는다 (헤드리스 기본)
var playback_enabled: bool = SoundBank.default_playback_enabled()

var _streams: Dictionary[StringName, AudioStream] = {}
var _voices: Array[Voice] = []
var _primary: Dictionary[StringName, Voice] = {}
var _current: StringName = &""
var _requests: Array[StringName] = []
var _to_fever_sec: float = 0.3
var _to_main_sec: float = 1.0
var _loop_trim_sec: float = 2.0
var _loop_fade_sec: float = 1.0


func _init() -> void:
	name = "BgmPlayer"
	SoundBank.ensure_buses()
	for track: StringName in TRACK_PATHS:
		var path: String = TRACK_PATHS[track]
		if ResourceLoader.exists(path):
			_streams[track] = load(path) as AudioStream
		else:
			push_warning("BgmPlayer: BGM 파일이 없습니다: %s" % path)
	for i: int in VOICE_COUNT:
		var voice: Voice = Voice.new()
		voice.player = AudioStreamPlayer.new()
		voice.player.name = "Voice%d" % i
		voice.player.bus = SoundBank.BUS_BGM
		add_child(voice.player)
		_voices.append(voice)


## 곡 끝 반복을 시작하는 시각(초). 곡 길이에서 trim_sec를 뺀 값 (0 아래로는 안 내려감)
static func loop_point(length: float, trim_sec: float) -> float:
	return maxf(0.0, length - trim_sec)


## 시간에 따른 새 설정(전환·반복 시간, 볼륨)을 받는다. 진행 중인 전환에는 영향이 없고 다음 전환부터 적용된다.
func apply_feel(feel: FeelConfig) -> void:
	_to_fever_sec = feel.bgm_to_fever_sec
	_to_main_sec = feel.bgm_to_main_sec
	_loop_trim_sec = feel.bgm_loop_trim_sec
	_loop_fade_sec = feel.bgm_loop_fade_sec
	var index: int = AudioServer.get_bus_index(SoundBank.BUS_BGM)
	if index != -1:
		AudioServer.set_bus_volume_db(index, feel.bgm_volume_db)


## 게임 시작: 메인 곡을 페이드인으로 시작한다. 이미 시작했으면 아무것도 하지 않는다.
func start() -> void:
	if _current != &"":
		return
	_log(LOG_START + String(TRACK_MAIN))
	_begin(TRACK_MAIN, _to_main_sec)
	_current = TRACK_MAIN


## 곡을 바꾼다. 이미 그 곡이면 아무것도 하지 않는다.
## 메인 → 피버: 메인은 일시정지(위치 기억), 피버는 처음부터. 피버 → 메인: 피버는 끄고 메인은 이어서.
func switch_to(track: StringName) -> void:
	if _current == &"" or track == _current or not TRACK_PATHS.has(track):
		return
	_log(LOG_SWITCH + String(track))
	var seconds: float = _to_fever_sec if track == TRACK_FEVER else _to_main_sec
	var leaving: Voice = _primary.get(_current)
	if leaving != null:
		leaving.after = After.PAUSE if _current == TRACK_MAIN else After.STOP
		_fade(leaving, 0.0, seconds)
	if track == TRACK_MAIN:
		_resume_or_begin(TRACK_MAIN, seconds)
	else:
		_begin(track, seconds)
	_current = track


## 모두 끈다 (미리보기 씬이 BGM 없이 보고 싶을 때). 다시 start()하면 처음부터 시작한다.
func stop_all() -> void:
	_log(String(LOG_STOP))
	for voice: Voice in _voices:
		_release(voice)
	_primary.clear()
	_current = &""


## 미리보기용: 지금 곡의 위치를 옮긴다 (곡 끝 이음새를 바로 들어 볼 때)
func seek(seconds: float) -> void:
	var voice: Voice = _primary.get(_current)
	if voice == null:
		return
	voice.pos = seconds
	voice.loop_done = false
	if playback_enabled and voice.player.playing:
		voice.player.seek(seconds)


## 지금 틀고 있는(또는 틀어야 하는) 곡. 시작 전이면 빈 이름.
func current_track() -> StringName:
	return _current


## 그 곡의 주 재생기 음량 (0~1, 재생기가 없으면 0)
func gain_of(track: StringName) -> float:
	var voice: Voice = _primary.get(track)
	return voice.gain if voice != null else 0.0


## 그 곡의 주 재생기 위치(초). 없으면 -1
func position_of(track: StringName) -> float:
	var voice: Voice = _primary.get(track)
	return voice.pos if voice != null else -1.0


func is_paused(track: StringName) -> bool:
	var voice: Voice = _primary.get(track)
	return voice != null and voice.paused


## 곡을 쓰고 있는 재생기 수 (일시정지 중인 것 포함)
func active_voices() -> int:
	var count: int = 0
	for voice: Voice in _voices:
		if voice.track != &"":
			count += 1
	return count


func track_length(track: StringName) -> float:
	var stream: AudioStream = _streams.get(track)
	return stream.get_length() if stream != null else 0.0


func requests() -> Array[StringName]:
	return _requests


func clear_requests() -> void:
	_requests.clear()


## 시간을 delta초 진행한다: 위치, 전환 곡선, 곡 끝 반복. main.advance()가 부른다.
func advance(delta: float) -> void:
	for voice: Voice in _voices:
		if voice.track == &"":
			continue
		if voice.skip_tick:
			voice.skip_tick = false
			continue
		if not voice.paused:
			voice.pos += delta
		if voice.fading:
			_step_fade(voice, delta)
		_check_loop(voice)
		_apply_gain(voice)


func _begin(track: StringName, fade_sec: float) -> void:
	var voice: Voice = _alloc_voice()
	voice.track = track
	voice.pos = 0.0
	voice.paused = false
	voice.gain = 0.0
	voice.after = After.NONE
	voice.loop_done = false
	voice.player.stream = _streams.get(track)
	if playback_enabled and voice.player.stream != null:
		voice.player.stream_paused = false
		voice.player.play()
	_primary[track] = voice
	_fade(voice, 1.0, fade_sec)
	_apply_gain(voice)


## 메인 곡이 일시정지 중이면 이어서 틀고, 아니면(없거나 막 끄는 중) 처음부터 튼다.
func _resume_or_begin(track: StringName, fade_sec: float) -> void:
	var voice: Voice = _primary.get(track)
	if voice == null or voice.track == &"":
		_begin(track, fade_sec)
		return
	voice.after = After.NONE
	if voice.paused:
		voice.paused = false
		voice.player.stream_paused = false
	_fade(voice, 1.0, fade_sec)
	_apply_gain(voice)


func _fade(voice: Voice, target: float, seconds: float) -> void:
	voice.fade_from = voice.gain
	voice.fade_to = target
	voice.fade_p = 0.0
	voice.fade_len = seconds
	voice.fading = seconds > 0.0
	if not voice.fading:
		voice.gain = target
		_on_fade_done(voice)


func _step_fade(voice: Voice, delta: float) -> void:
	voice.fade_p = minf(1.0, voice.fade_p + delta / voice.fade_len)
	var angle: float = voice.fade_p * PI / 2.0
	voice.gain = voice.fade_from * cos(angle) + voice.fade_to * sin(angle)
	if voice.fade_p >= 1.0:
		voice.gain = voice.fade_to
		voice.fading = false
		_on_fade_done(voice)


## 줄이는 전환이 끝났을 때: 메인은 일시정지(위치 기억), 나머지는 정리
func _on_fade_done(voice: Voice) -> void:
	if voice.fade_to > 0.0:
		return
	if voice.after == After.PAUSE:
		voice.paused = true
		voice.player.stream_paused = true
	elif voice.after == After.STOP:
		_release(voice)


## 곡 끝 bgm_loop_trim_sec 전이 되면 같은 곡을 처음부터 다시 틀고 이전 소리를 줄인다.
func _check_loop(voice: Voice) -> void:
	if voice.paused or voice.loop_done or voice.after != After.NONE:
		return
	var length: float = track_length(voice.track)
	if length <= 0.0 or voice.pos < loop_point(length, _loop_trim_sec):
		return
	voice.loop_done = true
	var track: StringName = voice.track
	_log(LOG_LOOP + String(track))
	voice.after = After.STOP
	_fade(voice, 0.0, _loop_fade_sec)
	_begin(track, _loop_fade_sec)
	(_primary[track] as Voice).skip_tick = true


func _apply_gain(voice: Voice) -> void:
	if voice.track == &"":
		return
	voice.player.volume_db = maxf(SILENT_DB, linear_to_db(maxf(voice.gain, MIN_GAIN)))


func _release(voice: Voice) -> void:
	if voice.track != &"" and _primary.get(voice.track) == voice:
		_primary.erase(voice.track)
	voice.track = &""
	voice.paused = false
	voice.fading = false
	voice.gain = 0.0
	voice.pos = 0.0
	voice.after = After.NONE
	voice.skip_tick = false
	voice.player.stream_paused = false
	if voice.player.playing:
		voice.player.stop()


## 놀고 있는 재생기. 없으면 가장 조용한 재생기를 빼앗는다 (일시정지 중인 주 재생기는 빼앗지 않음).
func _alloc_voice() -> Voice:
	var quietest: Voice = null
	for voice: Voice in _voices:
		if voice.track == &"":
			return voice
		var keep: bool = voice.paused and _primary.get(voice.track) == voice
		if not keep and (quietest == null or voice.gain < quietest.gain):
			quietest = voice
	_release(quietest)
	return quietest


func _log(entry: String) -> void:
	_requests.append(StringName(entry))
	if _requests.size() > LOG_MAX:
		_requests.remove_at(0)

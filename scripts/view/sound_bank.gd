class_name SoundBank
extends Node
## 효과음 재생 도우미 (6-F1). 이름으로 소리를 요청하면 SFX 버스로 재생한다.
## - 여러 소리가 겹쳐도 끊기지 않게 재생기 여러 개(VOICES)를 돌려 쓴다. 모두 쓰는 중이면 가장 오래된 소리를 끊고 새 소리를 낸다.
## - 반복음(릴 회전)은 따로 켜고 끈다. 이미 켜져 있으면 다시 시작하지 않는다.
## - 요청은 재생 여부와 상관없이 기록에 남는다 (헤드리스 테스트가 "맞는 이름이 요청됐는지" 확인하는 용도).
## - 오디오 장치가 없어도(헤드리스) 에러 없이 동작한다.
## 소리 파일은 tools/gen_sounds.py로 합성한 것이다 (assets/sounds/*.wav).

const SOUND_DIR: String = "res://assets/sounds/"
const BUS_SFX: StringName = &"SFX"
const BUS_BGM: StringName = &"BGM"
const BUS_MASTER: StringName = &"Master"
## 동시에 재생할 수 있는 효과음 수
const VOICES: int = 8
## 요청 기록 최대 개수 (넘으면 오래된 것부터 버림)
const LOG_MAX: int = 256
const LOOP_SUFFIX_STOP: String = ":stop"
const CUT_MARK: StringName = &"cut"

## 연결하는 효과음 이름 (파일 이름과 같음). gameover는 GAME OVER 화면이 뜰 때 재생한다 (7-B).
const NAME_COIN: StringName = &"coin"
const NAME_BET: StringName = &"bet"
const NAME_CANCEL: StringName = &"cancel"
const NAME_START: StringName = &"start"
const NAME_REEL_SPIN: StringName = &"reel_spin"
const NAME_REEL_STOP: StringName = &"reel_stop"
const NAME_WIN_SMALL: StringName = &"win_small"
const NAME_WIN_MID: StringName = &"win_mid"
const NAME_WIN_BIG: StringName = &"win_big"
const NAME_FEVER_START: StringName = &"fever_start"
const NAME_FEVER_END: StringName = &"fever_end"
const NAME_POOL_GET: StringName = &"pool_get"
const NAME_BUTTON: StringName = &"button"
const NAME_GAMEOVER: StringName = &"gameover"
## 정산 카운트업 증가·동전 도착 (6-F3b)
const NAME_TICK: StringName = &"tick"
const ALL_NAMES: Array[StringName] = [
	NAME_COIN, NAME_BET, NAME_CANCEL, NAME_START, NAME_REEL_SPIN, NAME_REEL_STOP,
	NAME_WIN_SMALL, NAME_WIN_MID, NAME_WIN_BIG, NAME_FEVER_START, NAME_FEVER_END,
	NAME_POOL_GET, NAME_BUTTON, NAME_GAMEOVER, NAME_TICK,
]
## 반복해서 재생하는 소리
const LOOP_NAMES: Array[StringName] = [NAME_REEL_SPIN]
## 16bit 모노 한 샘플의 바이트 수 (반복 구간 계산용)
const BYTES_PER_SAMPLE: int = 2

## false면 요청만 기록하고 실제로는 재생하지 않는다. 헤드리스(화면·소리 장치 없음) 실행에서는 기본으로 꺼 둔다
## (더미 오디오에서 재생한 소리를 바로 정리하면 종료 때 "resources still in use" 경고가 남기 때문).
var playback_enabled: bool = default_playback_enabled()

var _streams: Dictionary[StringName, AudioStream] = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_order: PackedInt64Array = PackedInt64Array()
var _loops: Dictionary[StringName, AudioStreamPlayer] = {}
var _loop_on: Dictionary[StringName, bool] = {}
var _requests: Array[StringName] = []
var _tick: int = 0


func _init() -> void:
	name = "SoundBank"
	ensure_buses()
	_load_streams()
	for i: int in VOICES:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.name = "Voice%d" % i
		voice.bus = BUS_SFX
		add_child(voice)
		_voices.append(voice)
		_voice_order.append(0)
	for loop_name: StringName in LOOP_NAMES:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Loop_%s" % loop_name
		player.bus = BUS_SFX
		player.stream = _streams.get(loop_name)
		add_child(player)
		_loops[loop_name] = player
		_loop_on[loop_name] = false


## 실제 재생을 켤지의 기본값: 헤드리스가 아니면 켠다 (BgmPlayer도 같은 기준을 쓴다)
static func default_playback_enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## SFX / BGM 버스가 없으면 만든다 (둘 다 Master로 보냄). 8단계 설정 화면이 이 버스의 볼륨을 조절한다.
static func ensure_buses() -> void:
	for bus_name: StringName in [BUS_SFX, BUS_BGM]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, BUS_MASTER)


## 당첨 크기에 맞는 효과음 이름. 당첨이 없으면 빈 이름.
## 기준: (총 지급 ÷ 총 베팅)이 mid_ratio 이상이면 중, big_ratio 이상이면 대, 그보다 작으면 소.
static func win_sound_for(total_payout: int, total_bet: int, mid_ratio: float, big_ratio: float) -> StringName:
	if total_payout <= 0:
		return &""
	var ratio: float = float(total_payout) / float(maxi(1, total_bet))
	if ratio >= big_ratio:
		return NAME_WIN_BIG
	if ratio >= mid_ratio:
		return NAME_WIN_MID
	return NAME_WIN_SMALL


## 효과음 파일이 있는지 (테스트용)
static func sound_path(sound_name: StringName) -> String:
	return SOUND_DIR + "%s.wav" % sound_name


## 효과음(SFX 버스) 볼륨을 dB로 정한다.
func set_sfx_volume_db(db: float) -> void:
	var index: int = AudioServer.get_bus_index(BUS_SFX)
	if index != -1:
		AudioServer.set_bus_volume_db(index, db)


## 효과음 하나를 재생한다. 요청은 항상 기록한다.
func play(sound_name: StringName) -> void:
	_log(sound_name)
	if not playback_enabled:
		return
	var stream: AudioStream = _streams.get(sound_name)
	if stream == null:
		return
	var index: int = _pick_voice()
	_tick += 1
	_voice_order[index] = _tick
	_voices[index].stream = stream
	_voices[index].play()


## 반복음을 켠다. 이미 켜져 있으면 아무것도 하지 않는다.
func play_loop(sound_name: StringName) -> void:
	if not _loop_on.has(sound_name) or _loop_on[sound_name]:
		return
	_loop_on[sound_name] = true
	_log(sound_name)
	if playback_enabled and _loops[sound_name].stream != null:
		_loops[sound_name].play()


## 반복음을 끈다. 꺼져 있으면 아무것도 하지 않는다.
func stop_loop(sound_name: StringName) -> void:
	if not _loop_on.has(sound_name) or not _loop_on[sound_name]:
		return
	_loop_on[sound_name] = false
	_log(StringName(String(sound_name) + LOOP_SUFFIX_STOP))
	_loops[sound_name].stop()


func is_loop_on(sound_name: StringName) -> bool:
	return _loop_on.get(sound_name, false)


## 재생 중인 효과음(반복음 제외)을 모두 끊는다. 피버 연출을 건너뛸 때 쓴다.
func cut_oneshots() -> void:
	_log(CUT_MARK)
	for voice: AudioStreamPlayer in _voices:
		voice.stop()


## 지금까지의 요청 기록 (오래된 것이 앞)
func requests() -> Array[StringName]:
	return _requests


func clear_requests() -> void:
	_requests.clear()


## 지금 소리가 나고 있는 재생기 수 (테스트·디버그용)
func busy_voices() -> int:
	var count: int = 0
	for voice: AudioStreamPlayer in _voices:
		if voice.playing:
			count += 1
	return count


func _log(entry: StringName) -> void:
	_requests.append(entry)
	if _requests.size() > LOG_MAX:
		_requests.remove_at(0)


## 놀고 있는 재생기 번호. 모두 쓰는 중이면 가장 오래전에 시작한 것을 돌려준다(그 소리를 끊고 쓴다).
func _pick_voice() -> int:
	var oldest: int = 0
	for i: int in _voices.size():
		if not _voices[i].playing:
			return i
		if _voice_order[i] < _voice_order[oldest]:
			oldest = i
	return oldest


func _load_streams() -> void:
	for sound_name: StringName in ALL_NAMES:
		var path: String = sound_path(sound_name)
		if not ResourceLoader.exists(path):
			push_warning("SoundBank: 효과음 파일이 없습니다: %s" % path)
			continue
		var stream: AudioStream = load(path) as AudioStream
		if LOOP_NAMES.has(sound_name) and stream is AudioStreamWAV:
			stream = _make_loop(stream as AudioStreamWAV)
		_streams[sound_name] = stream


## 처음부터 끝까지 반복하도록 복사본을 만든다 (원본 파일 임포트 설정은 건드리지 않는다).
func _make_loop(source: AudioStreamWAV) -> AudioStreamWAV:
	var looped: AudioStreamWAV = source.duplicate() as AudioStreamWAV
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	looped.loop_end = looped.data.size() / BYTES_PER_SAMPLE
	return looped

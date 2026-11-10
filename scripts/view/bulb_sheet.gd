class_name BulbSheet
extends RefCounted
## 전구 그림 시트(6-F3a). 가로로 4상태: 꺼짐 / 노랑(켜짐) / 빨강 / 흰색. 한 칸은 아트 2×2 = 6×6 px.
## 그림은 tools/gen_pixel_assets.py가 만든 최종 크기다. 보드 링(BoardView)과 프레임 소켓(FrameBulbs)이 같이 쓴다.

const SHEET_PATH: String = "res://assets/ui/bulbs.png"
const STATE_OFF: int = 0
const STATE_ON: int = 1
const STATE_RED: int = 2
const STATE_WHITE: int = 3
const STATE_COUNT: int = 4
## 한 칸의 화면 크기 (아트 2 × 3)
const FRAME_PX: int = 6

static var _cache: Dictionary = {}


static func sheet() -> Texture2D:
	return load(SHEET_PATH) as Texture2D


## 상태(0 ~ STATE_COUNT-1)의 전구 그림
static func frame(state: int) -> AtlasTexture:
	var index: int = clampi(state, 0, STATE_COUNT - 1)
	if not _cache.has(index):
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = sheet()
		atlas.region = Rect2(index * FRAME_PX, 0, FRAME_PX, FRAME_PX)
		_cache[index] = atlas
	return _cache[index] as AtlasTexture

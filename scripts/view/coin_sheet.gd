class_name CoinSheet
extends RefCounted
## 당첨 동전 시트(6-E). 6프레임 가로 시트: 정면 → 옆면 → 뒷면 → 정면 (회전).
## 그림은 tools/gen_pixel_assets.py가 만든 최종 크기(아트 8×8 ×3 = 24×24)다.
## 동전 개수·속도·날아가는 연출은 6-F에서 정한다. 여기서는 프레임을 꺼내 주기만 한다.

const SHEET_PATH: String = "res://assets/ui/coin_sheet.png"
const FRAME_COUNT: int = 6
## 한 프레임의 화면 크기 (아트 8 × 3)
const FRAME_PX: int = 24


static func sheet() -> Texture2D:
	return load(SHEET_PATH) as Texture2D


## 프레임 번호(0 ~ FRAME_COUNT-1, 범위 밖은 순환)의 그림
static func frame(index: int) -> AtlasTexture:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = sheet()
	atlas.region = Rect2(posmod(index, FRAME_COUNT) * FRAME_PX, 0, FRAME_PX, FRAME_PX)
	return atlas

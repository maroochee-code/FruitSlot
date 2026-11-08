class_name SymbolStyle
extends RefCounted
## 심볼별 화면 표시 설정(바탕색, 글자색, 테두리, 글자). 밸런스 수치가 아니라 화면 설정이라 여기 둔다.

const DEFAULT_FONT_SIZE: int = 22
const TOP_FONT_SIZE: int = 56
const BORDER_NORMAL: Color = Color(0, 0, 0, 0.55)
const BORDER_GOLD: Color = Color("FFD700")
const UNKNOWN_BG: Color = Color("FF00FF")

## 심볼 그림 파일 경로 (한 곳에서 관리). 파일이 없으면 색 박스 + 글자로 표시한다.
## 그림을 만들면 이 폴더에 같은 이름으로 넣으면 된다. 다른 파일명을 쓰려면 아래 경로만 고친다.
const ICON_DIR: String = "res://assets/symbols/"
const ICON_PATHS: Dictionary = {
	"CHERRY": ICON_DIR + "cherry.png",
	"ORANGE": ICON_DIR + "orange.png",
	"MELON": ICON_DIR + "melon.png",
	"GRAPE": ICON_DIR + "grape.png",
	"BELL": ICON_DIR + "bell.png",
	"BAR": ICON_DIR + "bar.png",
	"SEVEN": ICON_DIR + "seven.png",
}

## 심볼 ID → 표시 정보. 7개 색 쌍 중 가장 가까운 쌍(체리-오렌지)의 색차(Lab ΔE)가 44.6임을 확인함.
const STYLES: Dictionary = {
	"CHERRY": { "bg": Color("D81B2C"), "fg": Color("FFFFFF"), "border": BORDER_NORMAL, "text": "체리" },
	"ORANGE": { "bg": Color("F57C00"), "fg": Color("000000"), "border": BORDER_NORMAL, "text": "오렌지" },
	"MELON": { "bg": Color("2E9E3E"), "fg": Color("FFFFFF"), "border": BORDER_NORMAL, "text": "수박" },
	"GRAPE": { "bg": Color("7B3FB5"), "fg": Color("FFFFFF"), "border": BORDER_NORMAL, "text": "포도" },
	"BELL": { "bg": Color("FFD21F"), "fg": Color("000000"), "border": BORDER_NORMAL, "text": "벨" },
	"BAR": { "bg": Color("E6E8EC"), "fg": Color("000000"), "border": BORDER_NORMAL, "text": "BAR" },
	"SEVEN": { "bg": Color("101010"), "fg": Color("FFD700"), "border": BORDER_GOLD, "text": "7", "font_size": TOP_FONT_SIZE },
}


static func get_style(symbol_id: String) -> Dictionary:
	if STYLES.has(symbol_id):
		return STYLES[symbol_id]
	return { "bg": UNKNOWN_BG, "fg": Color.BLACK, "border": BORDER_NORMAL, "text": symbol_id }


## 심볼 그림을 돌려준다. 경로가 없거나 파일이 없으면 null (색 박스 + 글자로 표시).
static func load_icon(symbol_id: String) -> Texture2D:
	var path: String = ICON_PATHS.get(symbol_id, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

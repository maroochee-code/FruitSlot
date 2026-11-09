class_name UiFont
extends RefCounted
## 갈무리(Galmuri) 도트 폰트. 도트 폰트는 "원래 픽셀 크기의 정수배"로 써야 또렷하다.
## 폰트 가져오기 설정(안티앨리어싱·힌팅·서브픽셀 끔)은 각 .ttf.import에 들어 있다. 출처·라이선스는 docs/credits.md.

enum Face { SMALL, BODY, LARGE }

const FONT_PATHS: Dictionary = {
	Face.SMALL: "res://assets/fonts/Galmuri9.ttf",
	Face.BODY: "res://assets/fonts/Galmuri11.ttf",
	Face.LARGE: "res://assets/fonts/Galmuri14.ttf",
}
## 각 폰트의 원래 픽셀 크기 (갈무리 공식 안내: 9 = 10px, 11 = 12px, 14 = 15px)
const NATIVE_SIZES: Dictionary = {
	Face.SMALL: 10,
	Face.BODY: 12,
	Face.LARGE: 15,
}


static func font(face: Face) -> Font:
	return load(FONT_PATHS[face]) as Font


## 글자 크기 = 원래 크기 × 배율 (정수배)
static func size_of(face: Face, multiple: int = 1) -> int:
	return int(NATIVE_SIZES[face]) * multiple


## 컨트롤(Label, Button 등)에 폰트와 크기(원래 크기 × 배율)를 지정한다.
static func apply(control: Control, face: Face, multiple: int = 1) -> void:
	control.add_theme_font_override("font", font(face))
	control.add_theme_font_size_override("font_size", size_of(face, multiple))

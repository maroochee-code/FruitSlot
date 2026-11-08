class_name LineDef
extends RefCounted
## 라인 하나의 정의 (balance.json "lines" 항목).

## 허용하는 라인 종류 (통계 분류용)
const TYPES: PackedStringArray = ["horizontal", "vertical", "diagonal"]

var id: String = ""
## TYPES 중 하나
var type: String = ""
## 칸 좌표 목록. x = 열(릴 번호), y = 행(0=윗줄)
var cells: Array[Vector2i] = []

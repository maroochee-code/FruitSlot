extends Node
## 화면 검증: main 씬에서 START를 여러 번 누르고, 화면 칸과 로직 결과가 매번 같은지 확인한다.

@export var spin_count: int = 200
@export var quit_when_headless: bool = true


func _ready() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var mismatches: int = 0
	var null_results: int = 0
	for i: int in spin_count:
		var result: SpinResult = main.do_spin()
		if result == null:
			null_results += 1
		elif not main.grid_matches_logic():
			mismatches += 1
	var passed: bool = mismatches == 0 and null_results == 0
	print("VIEW TEST: %d회 / 불일치 %d / 결과 없음 %d -> %s" % [spin_count, mismatches, null_results, "통과" if passed else "실패"])
	main.toggle_debug()
	main.toggle_debug()
	if quit_when_headless and DisplayServer.get_name() == "headless":
		get_tree().quit(0 if passed else 1)

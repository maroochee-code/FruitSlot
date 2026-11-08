# Godot MCP가 엔진을 찾지 못함

- **증상:** MCP 도구 실행 시 `spawn C:\Program Files\Godot\Godot.exe ENOENT`
- **원인:** MCP 설정의 `GODOT_PATH`가 `D:\GodotEngine\Godot_v4.7.2-stable_win64.exe`였는데, 이 경로는 실행 파일이 아니라 zip을 풀면서 생긴 **같은 이름의 폴더**였다. 경로 검사에 실패한 MCP가 기본 경로(`C:\Program Files\Godot`)로 대신 시도했다.
- **해결:** `GODOT_PATH`를 폴더 안의 실제 실행 파일로 수정 → Claude Code 재시작
  `D:/GodotEngine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`
- **관련 파일:** `C:\Users\maroochee\.claude.json` (프로젝트별 mcpServers.godot.env)

## 덧붙임: MCP가 출력을 못 받는 문제
- **증상:** 테스트 씬이 끝나자마자 `quit()`하면 `get_debug_output`이 "No active Godot process"를 돌려주고 출력이 사라짐
- **해결:** 테스트·시뮬레이션 씬은 headless 실행일 때만 자동 종료하고, MCP·에디터 실행에서는 창을 열어 둔다 (`stop_project`로 종료)
- **관련 파일:** `scenes/test/sim.gd`, `scenes/test/logic_test.gd`

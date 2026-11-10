"""maroochee slot 도트 리소스 생성기 (6-A).

실행: python tools/gen_pixel_assets.py   (Pillow 필요)
만드는 것:
  assets/symbols/*.png        큰 심볼 32x24 (7종)
  assets/ui/cell_tile.png     칸 타일 36x28
  assets/ui/icons/*.png       작은 아이콘 12x10 (BAR만 15x10)
  assets/ui/panel.png         패널 9-slice (6-C, 최종 크기 24x24 = 아트 8x8 x3, 모서리 6px)
  assets/ui/button_normal.png / button_pressed.png / button_disabled.png   버튼 3상태 9-slice (같은 규격)
  assets/ui/button_on.png     AUTO 켜짐 표시용 (같은 규격)
  assets/ui/line_label_a.png ~ _h.png   라인 라벨 33x21 (아트 11x7 x3)
  assets/ui/wallpaper_tile.png  마름모 벽지 타일 (6-D, 아트 16x16 -> 48x48)
  assets/ui/frame.png           기계 프레임 (6-D, 아트 213x160 -> 640x480, 가운데 투명)
  assets/ui/logo.png            maroochee slot 로고 (6-D, 아트 60x24 -> 180x72, 배경 투명)
  assets/_preview/6d_screen.png 6-D 전체 화면 근사 합성 (640x480)
  assets/_preview/sheet.png   위 전부를 x3 Nearest로 확대해 한 장에 (6-C 에셋은 이미 3배라 그대로 붙임)
규칙: 안티앨리어싱·그라데이션 없음(색은 팔레트 몇 가지만), 1px 외곽선, 왼쪽 위 밝게/오른쪽 아래 어둡게 2톤, 하이라이트 점.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUTLINE = (0x2B, 0x1B, 0x3D, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def rgb(hexstr: str):
    h = hexstr.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


# 색 이름 -> (밝은 톤, 어두운 톤)
TONES = {
    "red": (rgb("e8323c"), rgb("a81c2e")),
    "orange": (rgb("f59a23"), rgb("c8641a")),
    "green": (rgb("4cc24a"), rgb("2b8a3a")),
    "rind": (rgb("2f9a45"), rgb("1c6a34")),
    "pale": (rgb("e4f0b0"), rgb("b4cc80")),
    "flesh": (rgb("ff5a6e"), rgb("d03050")),
    "purple": (rgb("a45cd8"), rgb("6e34a0")),
    "gold": (rgb("ffd23a"), rgb("d09a14")),
    "navy": (rgb("3a4ca8"), rgb("24307a")),
    "brown": (rgb("a8702c"), rgb("744818")),
    "cream": (rgb("f7e6b8"), rgb("d9bd7a")),
}
SEED = rgb("3a1c1c")


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[CLEAR] * w for _ in range(h)]

    def inside(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def set(self, x, y, color):
        if self.inside(x, y):
            self.px[y][x] = color

    def part(self, mask, tone, outline=True, split=1.1):
        """마스크(칸 좌표 집합)를 2톤으로 칠하고 바깥에 1px 외곽선을 두른다."""
        if not mask:
            return
        light, dark = TONES[tone]
        xs = [p[0] for p in mask]
        ys = [p[1] for p in mask]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        bw, bh = max(1, x1 - x0), max(1, y1 - y0)
        if outline:
            for x, y in mask:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    q = (x + dx, y + dy)
                    if q not in mask:
                        self.set(q[0], q[1], OUTLINE)
        for x, y in mask:
            u, v = (x - x0) / bw, (y - y0) / bh
            self.set(x, y, dark if u + v > split else light)

    def dots(self, pts, color):
        for x, y in pts:
            self.set(x, y, color)

    def image(self):
        img = Image.new("RGBA", (self.w, self.h), CLEAR)
        for y in range(self.h):
            for x in range(self.w):
                img.putpixel((x, y), self.px[y][x])
        return img


def circle(cx, cy, r):
    out = set()
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                out.add((x, y))
    return out


def ellipse(cx, cy, rx, ry):
    out = set()
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1:
                out.add((x, y))
    return out


def rect(x0, y0, x1, y1):
    return {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)}


def line(x0, y0, x1, y1):
    out, dx, dy = set(), abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        out.add((x0, y0))
        if (x0, y0) == (x1, y1):
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy
    return out


def polygon(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    out = set()
    for y in range(min(ys), max(ys) + 1):
        for x in range(min(xs), max(xs) + 1):
            px, py, inside, j = x + 0.5, y + 0.5, False, len(points) - 1
            for i in range(len(points)):
                xi, yi = points[i]
                xj, yj = points[j]
                if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
                    inside = not inside
                j = i
            if inside:
                out.add((x, y))
    return out


def grow(mask):
    out = set(mask)
    for x, y in mask:
        out |= {(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)}
    return out


# ------------------------------------------------------------------ 큰 심볼 32x24

def big_cherry():
    c = Canvas(32, 24)
    c.part(line(10, 12, 15, 3) | line(22, 13, 16, 3), "brown", split=2)
    c.part(ellipse(23, 5, 4.5, 2.2) - {(x, y) for x in range(15) for y in range(24)}, "green")
    c.part(circle(10.5, 17, 6), "red")
    c.part(circle(22.5, 18, 6), "red")
    c.dots([(8, 15), (9, 14), (20, 16), (21, 15)], WHITE)
    return c


def big_orange():
    c = Canvas(32, 24)
    c.part(circle(16, 14, 9), "orange")
    c.part(ellipse(21, 4.5, 4.5, 2.2), "green")
    c.part({(15, 4), (16, 4), (16, 5)}, "brown", outline=False)
    c.dots([(12, 11), (13, 10)], WHITE)
    c.dots([(18, 14), (14, 17), (20, 18), (11, 15), (17, 20)], TONES["orange"][1])
    return c


def big_melon():
    c = Canvas(32, 24)
    half = lambda r, cy: {(x, y) for (x, y) in circle(16, cy, r) if y >= cy}
    c.part(half(14, 5), "rind", split=1.3)
    c.part(half(12, 6), "pale", outline=False, split=1.3)
    c.part(half(10, 7), "flesh", outline=False, split=1.3)
    c.dots([(11, 11), (16, 13), (21, 11), (14, 16), (19, 16)], SEED)
    c.dots([(7, 8), (8, 8)], WHITE)
    return c


def big_grape():
    c = Canvas(32, 24)
    c.part(line(16, 1, 16, 5), "brown", split=2)
    c.part(ellipse(22, 3.5, 4.5, 2.2), "green")
    for cx, cy in ((10, 8), (16, 8), (22, 8), (13, 13), (19, 13), (16, 18)):
        c.part(circle(cx, cy, 3.8), "purple")
        c.dots([(cx - 2, cy - 2)], WHITE)
    return c


def big_bell():
    c = Canvas(32, 24)
    half = [3, 5, 6, 7, 8, 8, 9, 9, 10, 10, 10, 11, 11, 12, 13, 14, 15]  # 행마다 가운데에서 좌우 폭
    mask = {(x, 3 + i) for i, w in enumerate(half) for x in range(16 - w, 16 + w)}
    c.part(circle(16, 3.0, 2.0), "gold")
    c.part(mask, "gold", split=1.0)
    c.part(circle(16, 21, 2.6), "gold")
    c.dots([(11, 7), (10, 9), (9, 11), (9, 12)], WHITE)
    c.dots([(8, 17), (9, 17)], TONES["gold"][1])
    return c


FONT_5x7 = {
    "B": ["1111.", "1...1", "1...1", "1111.", "1...1", "1...1", "1111."],
    "A": [".111.", "1...1", "1...1", "11111", "1...1", "1...1", "1...1"],
    "R": ["1111.", "1...1", "1...1", "1111.", "1.1..", "1..1.", "1...1"],
}
FONT_3x5 = {
    "B": ["110", "101", "110", "101", "110"],
    "A": ["010", "101", "111", "101", "101"],
    "R": ["110", "101", "110", "101", "101"],
}


def draw_text(c, text, font, x, y, color, gap=1):
    for ch in text:
        glyph = font[ch]
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    c.set(x + gx, y + gy, color)
        x += len(glyph[0]) + gap


def bar_plate(c, x0, y0, x1, y1):
    """남색 판 + 금색 테두리. 오른쪽·아래는 어두운 톤."""
    nl, nd = TONES["navy"]
    gl, gd = TONES["gold"]
    c.part(rect(x0, y0, x1, y1), "gold", split=1.0)
    for x in range(x0 + 1, x1):
        for y in range(y0 + 1, y1):
            c.set(x, y, nd if (x - x0) + (y - y0) > ((x1 - x0) + (y1 - y0)) * 0.55 else nl)


def big_bar():
    c = Canvas(32, 24)
    bar_plate(c, 1, 4, 30, 19)
    draw_text(c, "BAR", FONT_5x7, 7, 8, TONES["gold"][0])
    c.dots([(3, 6), (4, 6)], WHITE)
    return c


def big_seven():
    c = Canvas(32, 24)
    seven = polygon([(7, 3), (26, 3), (26, 8), (17, 21), (10, 21), (18, 9), (7, 9)])
    c.part(grow(seven), "gold", split=1.0)
    c.part(seven, "red", outline=False, split=1.0)
    c.dots([(9, 4), (10, 4), (9, 5)], WHITE)
    return c


# ------------------------------------------------------------------ 작은 아이콘 12x10 (처음부터 작게 찍음)

def small_cherry():
    c = Canvas(12, 10)
    c.part(line(3, 4, 7, 1) | line(8, 4, 7, 1), "brown", split=2)
    c.part({(8, 1), (9, 1), (10, 1), (9, 2)}, "green")
    c.part(circle(3.5, 6.5, 2.6), "red")
    c.part(circle(8.5, 7, 2.6), "red")
    c.dots([(2, 5), (7, 6)], WHITE)
    return c


def small_orange():
    c = Canvas(12, 10)
    c.part(circle(6, 6, 3.7), "orange")
    c.part({(7, 1), (8, 1), (9, 1), (8, 2)}, "green")
    c.dots([(4, 4), (5, 4)], WHITE)
    c.dots([(7, 7), (5, 8)], TONES["orange"][1])
    return c


def small_melon():
    c = Canvas(12, 10)
    half = lambda r, cy: {(x, y) for (x, y) in circle(6, cy, r) if y >= cy}
    c.part(half(5.8, 2), "rind", split=1.3)
    c.part(half(4.2, 3), "flesh", outline=False, split=1.3)
    c.dots([(4, 5), (6, 6), (8, 5)], SEED)
    return c


def small_grape():
    c = Canvas(12, 10)
    c.part(line(6, 0, 6, 1), "brown", split=2)
    c.part({(7, 0), (8, 0), (9, 0), (8, 1)}, "green")
    # 송이: 위 3개 / 가운데 2개 / 아래 1개 (구슬 지름 3, 서로 맞닿게)
    for cx, cy in ((3.5, 3.5), (6.5, 3.5), (9.5, 3.5), (5, 6), (8, 6), (6.5, 8.5)):
        c.part(circle(cx, cy, 1.6), "purple")
    c.dots([(3, 3), (6, 3)], WHITE)
    return c


def small_bell():
    c = Canvas(12, 10)
    half = [1, 3, 4, 4, 4, 5, 5]
    mask = {(x, 1 + i) for i, w in enumerate(half) for x in range(6 - w, 6 + w)}
    c.part(mask, "gold", split=1.0)
    c.part({(5, 8), (6, 8)}, "gold", split=2)
    c.dots([(3, 3), (3, 4)], WHITE)
    return c


def small_bar():
    c = Canvas(15, 10)
    bar_plate(c, 0, 0, 14, 9)
    draw_text(c, "BAR", FONT_3x5, 2, 2, TONES["gold"][0])
    return c


def small_seven():
    c = Canvas(12, 10)
    seven = polygon([(2, 1), (10, 1), (10, 3), (7, 9), (4, 9), (7, 4), (2, 4)])
    c.part(grow(seven) - {(x, 0) for x in range(12)} - {(x, 10) for x in range(12)}, "gold", split=1.0)
    c.part(seven, "red", outline=False, split=1.0)
    c.dots([(3, 2)], WHITE)
    return c


# ------------------------------------------------------------------ 칸 타일 36x28

def cell_tile():
    c = Canvas(36, 28)
    black, tan = (0, 0, 0, 255), TONES["cream"][1]
    cream = TONES["cream"][0]
    for y in range(28):
        for x in range(36):
            c.set(x, y, cream)
    for x in range(1, 35):  # 오른쪽·아래 탄색 안쪽 테두리 2px
        for t in (1, 2):
            c.set(x, 28 - 1 - t, tan)
    for y in range(1, 27):
        for t in (1, 2):
            c.set(36 - 1 - t, y, tan)
    for x in range(1, 33):  # 왼쪽·위 흰 하이라이트 1px
        c.set(x, 1, WHITE)
    for y in range(1, 25):
        c.set(1, y, WHITE)
    for x in range(36):
        c.set(x, 0, black)
        c.set(x, 27, black)
    for y in range(28):
        c.set(0, y, black)
        c.set(35, y, black)
    for x, y in ((0, 0), (35, 0), (0, 27), (35, 27)):  # 모서리 깎기
        c.set(x, y, CLEAR)
    for x, y in ((1, 1), (34, 1), (1, 26), (34, 26)):
        c.set(x, y, black)
    return c


# ------------------------------------------------------------------ 6-C UI 에셋 (최종 크기로 저장)

PANEL_ART = 8  # 아트 8x8 -> 24x24, 9-slice 모서리 2아트px = 6px
PANEL_FILL = rgb("1b1f4a")
PANEL_LIGHT = rgb("5f6fd0")
PANEL_DARK = rgb("0e1130")

# 버튼 상태: (면, 위·왼쪽 변, 아래·오른쪽 변)
BUTTON_STATES = {
    "normal": (rgb("3d4fb8"), rgb("7f8fee"), rgb("27338a")),
    "pressed": (rgb("2e3d96"), rgb("27338a"), rgb("7f8fee")),  # 베벨 반전
    "disabled": (rgb("2a2f5a"), rgb("3a4070"), rgb("1a1d3a")),
    "on": (rgb("e0a82e"), rgb("ffe38a"), rgb("a06a14")),  # AUTO 켜짐 (글자는 어두운 색)
}
LINE_COLORS = {
    "a": "ff5a5a", "b": "4fc3f7", "c": "ffd23a", "d": "4cd964",
    "e": "ff7ad9", "f": "ff9a1f", "g": "9b8cff", "h": "3ee0c8",
}
LABEL_BG = rgb("0e1130")


def bevel_box(w, h, fill, light, dark):
    """바깥 1px 외곽선 + 안쪽 1px 베벨(위·왼쪽 light, 아래·오른쪽 dark) + 면. 네 모서리는 비움."""
    c = Canvas(w, h)
    for y in range(h):
        for x in range(w):
            if x in (0, w - 1) or y in (0, h - 1):
                color = OUTLINE
            elif x == 1 or y == 1:
                color = light
            elif x == w - 2 or y == h - 2:
                color = dark
            else:
                color = fill
            c.set(x, y, color)
    c.set(w - 2, 1, dark)  # 베벨이 만나는 모서리는 어두운 쪽
    c.set(1, h - 2, dark)
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        c.set(x, y, CLEAR)
    return c


def panel_nine():
    return bevel_box(PANEL_ART, PANEL_ART, PANEL_FILL, PANEL_LIGHT, PANEL_DARK)


def button_nine(state):
    fill, light, dark = BUTTON_STATES[state]
    return bevel_box(PANEL_ART, PANEL_ART, fill, light, dark)


def line_label(color_hex):
    """11x7 아트: 라인 색 1px 테두리 + 어두운 바탕. 글자는 게임에서 그린다(베팅 수가 바뀌므로)."""
    c = Canvas(11, 7)
    border = rgb(color_hex)
    for y in range(7):
        for x in range(11):
            edge = x in (0, 10) or y in (0, 6)
            c.set(x, y, border if edge else LABEL_BG)
    for x, y in ((0, 0), (10, 0), (0, 6), (10, 6)):
        c.set(x, y, CLEAR)
    return c



# ------------------------------------------------------------------ 6-D 벽지·프레임·로고

ART_W, ART_H = 213, 160
SCREEN_W, SCREEN_H = 640, 480
WALL_DARK = rgb("1f6f8b")
WALL_LIGHT = rgb("2a86a6")
FRAME_FILL = rgb("1b1f4a")
FRAME_LIGHT = rgb("5f6fd0")
FRAME_DARK = rgb("0e1130")
BULB_OFF = rgb("8a7a3a")  # BoardView.BULB_OFF_COLOR와 같은 색 (꺼진 전구 자리)
WALL_TILE = 16  # 아트 px

# 프레임 배치 (아트 좌표, 기존 화면 요소 사이 틈. 끝 좌표 포함)
FRAME_BORDER = 2                         # 바깥 테두리 두께
BAND_H = (2, 134, 149, 137)              # 가로 띠: 버튼 줄 아래 ~ 하단 표시창 위 (x0, y0, x1, y1)
BAND_V = (148, 2, 149, 117)              # 세로 띠: 왼쪽 영역 ~ 오른쪽 패널 사이
# 6-F용 꺼진 전구 소켓 (아트 2x2의 왼쪽 위 좌표). 가로 띠 몸통 위에 8px 간격.
FRAME_BULB_SOCKETS = [(x, 135) for x in range(6, 146, 8)]


def wallpaper_tile():
    """16x16 청록 마름모 격자. 두 톤만 쓰고 중심 대칭이라 가장자리가 이어진다."""
    c = Canvas(WALL_TILE, WALL_TILE)
    half = WALL_TILE / 2
    for y in range(WALL_TILE):
        for x in range(WALL_TILE):
            inside = abs(x + 0.5 - half) + abs(y + 0.5 - half) < half
            c.set(x, y, WALL_LIGHT if inside else WALL_DARK)
    return c


def frame_art():
    """213x160 프레임. 바깥 테두리(2px) + 가로·세로 구분 띠 + 꺼진 전구 소켓. 나머지는 투명."""
    c = Canvas(ART_W, ART_H)
    # 바깥 테두리: 가장 바깥 1px 외곽선, 안쪽 1px 베벨(위·왼 밝게, 아래·오른 어둡게)
    for y in range(ART_H):
        for x in range(ART_W):
            inner = FRAME_BORDER <= x < ART_W - FRAME_BORDER and FRAME_BORDER <= y < ART_H - FRAME_BORDER
            if inner:
                continue
            outer = x in (0, ART_W - 1) or y in (0, ART_H - 1)
            if outer:
                c.set(x, y, OUTLINE)
            else:
                c.set(x, y, FRAME_LIGHT if (x == 1 or y == 1) else FRAME_DARK)
    # 가로 띠: 위아래 외곽선 1px, 가운데 2px 몸통
    x0, y0, x1, y1 = BAND_H
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            c.set(x, y, OUTLINE if y in (y0, y1) else FRAME_FILL)
    # 세로 띠: 왼쪽 1px 외곽선, 오른쪽 1px 밝은 줄
    x0, y0, x1, y1 = BAND_V
    for y in range(y0, y1 + 1):
        c.set(x0, y, OUTLINE)
        c.set(x1, y, FRAME_LIGHT)
    # 꺼진 전구 소켓 2x2
    for sx, sy in FRAME_BULB_SOCKETS:
        for dx in range(2):
            for dy in range(2):
                c.set(sx + dx, sy + dy, BULB_OFF)
    return c


def frame_final():
    """아트 x3 = 639x480, 오른쪽 1px(640번째 열)은 마지막 열을 복사해 채운다."""
    img = scaled(frame_art().image())
    out = Image.new("RGBA", (SCREEN_W, SCREEN_H), CLEAR)
    out.paste(img, (0, 0))
    out.paste(img.crop((img.width - 1, 0, img.width, img.height)), (img.width, 0))
    return out


# 로고 글자 (직접 찍은 비트맵). X = 찍는 점
GLYPHS_SMALL = {  # 5 x 5 (h만 5 x 7)
    "m": ["XXXX.", "X.X.X", "X.X.X", "X.X.X", "X.X.X"],
    "a": [".XXX.", "....X", ".XXXX", "X...X", ".XXXX"],
    "r": ["X.XX.", "XX..X", "X....", "X....", "X...."],
    "o": [".XXX.", "X...X", "X...X", "X...X", ".XXX."],
    "c": [".XXXX", "X....", "X....", "X....", ".XXXX"],
    "h": ["X....", "X....", "X.XX.", "XX..X", "X...X", "X...X", "X...X"],
    "e": [".XXX.", "X...X", "XXXXX", "X....", ".XXXX"],
}
GLYPHS_BIG = {  # 7 x 7
    "S": [".XXXXX.", "XX...XX", "XX.....", ".XXXXX.", ".....XX", "XX...XX", ".XXXXX."],
    "L": ["XX.....", "XX.....", "XX.....", "XX.....", "XX.....", "XXXXXXX", "XXXXXXX"],
    "O": [".XXXXX.", "XX...XX", "XX...XX", "XX...XX", "XX...XX", "XX...XX", ".XXXXX."],
    "T": ["XXXXXXX", "XXXXXXX", "..XXX..", "..XXX..", "..XXX..", "..XXX..", "..XXX.."],
}
LOGO_W, LOGO_H = 60, 24
LOGO_INNER = (2, 2, 57, 21)  # 패널 안쪽 영역 (아트, 끝 포함). 이 밖으로 글자가 나가면 안 된다.
LOGO_SMALL_Y = 4             # 작은 글자 줄의 위쪽 (키 7칸 기준, x높이 글자는 아래 맞춤)
LOGO_BIG_Y = 13
LOGO_GAP_SMALL = 1
LOGO_GAP_BIG = 2


def _text_mask(text, glyphs, y_top, height, gap):
    """글자들을 가운데 정렬로 찍은 점 집합."""
    widths = [len(glyphs[ch][0]) for ch in text]
    total = sum(widths) + gap * (len(text) - 1)
    x = (LOGO_W - total) // 2
    mask = set()
    for ch, w in zip(text, widths):
        rows = glyphs[ch]
        y_off = y_top + height - len(rows)  # 아래 맞춤
        for ry, row in enumerate(rows):
            for rx, v in enumerate(row):
                if v == "X":
                    mask.add((x + rx, y_off + ry))
        x += w + gap
    return mask


def _paint_text(c, mask, light, dark, split_y):
    """8방향 1px 외곽선을 두르고, split_y 위는 밝은 톤 / 아래는 어두운 톤으로 칠한다."""
    for x, y in mask:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q not in mask:
                    c.set(q[0], q[1], OUTLINE)
    for x, y in mask:
        c.set(x, y, light if y < split_y else dark)


def logo_art():
    c = Canvas(LOGO_W, LOGO_H)
    small = _text_mask("maroochee", GLYPHS_SMALL, LOGO_SMALL_Y, 7, LOGO_GAP_SMALL)
    big = _text_mask("SLOT", GLYPHS_BIG, LOGO_BIG_Y, 7, LOGO_GAP_BIG)
    _paint_text(c, small, TONES["cream"][0], TONES["cream"][1], LOGO_SMALL_Y + 5)
    _paint_text(c, big, TONES["gold"][0], TONES["gold"][1], LOGO_BIG_Y + 4)
    return c


def logo_bounds(c):
    """로고 그림에 실제로 칠해진 픽셀의 범위 (x0, y0, x1, y1)."""
    xs, ys = [], []
    for y in range(c.h):
        for x in range(c.w):
            if c.px[y][x][3] != 0:
                xs.append(x)
                ys.append(y)
    return min(xs), min(ys), max(xs), max(ys)


# ------------------------------------------------------------------ 6-D 전체 화면 근사 미리보기

def nine_slice(tex, w, h, margin=6):
    """9-slice를 Nearest로 늘려 w x h로 만든다 (Godot StyleBoxTexture 근사)."""
    tw, th = tex.size
    out = Image.new("RGBA", (w, h), CLEAR)
    xs_src = [(0, margin), (margin, tw - margin), (tw - margin, tw)]
    ys_src = [(0, margin), (margin, th - margin), (th - margin, th)]
    xs_dst = [(0, margin), (margin, w - margin), (w - margin, w)]
    ys_dst = [(0, margin), (margin, h - margin), (h - margin, h)]
    for (sy0, sy1), (dy0, dy1) in zip(ys_src, ys_dst):
        for (sx0, sx1), (dx0, dx1) in zip(xs_src, xs_dst):
            part = tex.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.NEAREST)
            out.alpha_composite(part, (dx0, dy0))
    return out


def preview_screen(wall, frame, logo, with_frame=True):
    """main.gd의 배치 상수대로 기존 요소를 올린 640x480 근사 화면. 반환: (이미지, 요소가 덮은 영역 마스크)"""
    scr = Image.new("RGBA", (SCREEN_W, SCREEN_H), WALL_DARK)
    for ty in range(0, SCREEN_H, wall.height):
        for tx in range(0, SCREEN_W, wall.width):
            scr.alpha_composite(wall, (tx, ty))
    if with_frame:
        scr.alpha_composite(frame, (0, 0))
    covered = Image.new("L", (SCREEN_W, SCREEN_H), 0)
    cd = ImageDraw.Draw(covered)
    d = ImageDraw.Draw(scr)
    d.fontmode = "1"
    f11 = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11.ttf"), 12)
    f9 = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri9.ttf"), 10)
    f24 = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11.ttf"), 24)

    def cover(x, y, w, h):
        cd.rectangle([x, y, x + w - 1, y + h - 1], fill=255)

    panel_tex = Image.open(ROOT / "assets/ui/panel.png").convert("RGBA")

    def panel(x, y, w, h):
        scr.alpha_composite(nine_slice(panel_tex, w, h), (x, y))
        cover(x, y, w, h)

    # 보드 (BoardView 근사)
    bx, by, bw, bh = 42, 36, 348, 276
    d.rectangle([bx, by, bx + bw - 1, by + bh - 1], fill=OUTLINE)
    d.rectangle([bx + 3, by + 3, bx + bw - 4, by + bh - 4], fill=rgb("3a2a5c"))
    last_x, last_y = 116 - 1 - 2, 92 - 1 - 2
    ring = [(x, 1) for x in range(1, last_x + 1, 4)] + [(last_x, y) for y in range(5, last_y + 1, 4)] \
        + [(x, last_y) for x in range(last_x - 4, 0, -4)] + [(1, y) for y in range(last_y - 4, 1, -4)]
    for i, (ax, ay) in enumerate(ring):
        col = rgb("ffe14d") if i % 2 == 0 else BULB_OFF
        d.rectangle([bx + ax * 3, by + ay * 3, bx + ax * 3 + 5, by + ay * 3 + 5], fill=col)
    cover(bx, by, bw, bh)
    # 칸 타일 + 심볼 (예시 배열)
    tile = Image.open(ROOT / "assets/ui/cell_tile.png").convert("RGBA")
    tile = tile.resize((tile.width * 3, tile.height * 3), Image.NEAREST)
    names = [["cherry", "seven", "bell"], ["grape", "bar", "melon"], ["orange", "cherry", "seven"]]
    for col in range(3):
        for row in range(3):
            x, y = 54 + col * 108, 48 + row * 84
            scr.alpha_composite(tile, (x, y))
            sym = Image.open(ROOT / f"assets/symbols/{names[row][col]}.png").convert("RGBA")
            scr.alpha_composite(sym.resize((sym.width * 3, sym.height * 3), Image.NEAREST), (x + 6, y + 6))
    # 라인 라벨 (왼쪽·오른쪽 3개씩 + 위 2개, 대략적인 위치)
    lab = [Image.open(ROOT / f"assets/ui/line_label_{k}.png").convert("RGBA") for k in "abcdefgh"]
    for i in range(3):
        for x in (6, 396):
            y = 90 + i * 23
            scr.alpha_composite(lab[i], (x, y))
            cover(x, y, 33, 21)
    for i, cx in enumerate((108, 270)):
        scr.alpha_composite(lab[3 + i], (cx - 16, 9))
        cover(cx - 16, 9, 33, 21)
    # 버튼 줄
    d.rectangle([6, 354, 449, 401], fill=FRAME_DARK)
    cover(6, 354, 444, 48)

    def button(x, y, w, h, text, state="normal"):
        tex = Image.open(ROOT / f"assets/ui/button_{state}.png").convert("RGBA")
        scr.alpha_composite(nine_slice(tex, w, h), (x, y))
        tw = d.textlength(text, font=f11)
        d.text((x + (w - tw) // 2, y + (h - 12) // 2 - 1), text, font=f11, fill=(255, 255, 255, 255))
        cover(x, y, w, h)

    for x, t in zip((15, 102, 189, 276, 363), ("CANCEL", "COIN", "START", "BET", "MAX BET")):
        button(x, 360, 81, 36, t)
    for col in range(3):
        button(60 + col * 108, 318, 96, 33, "STOP %d" % (col + 1))
    button(384, 318, 60, 33, "AUTO")
    # 오른쪽 패널
    panel(450, 9, 180, 72)
    scr.alpha_composite(logo, (450, 9))
    for (x, y, w, h, t) in ((450, 87, 180, 42, "POOL"), (450, 135, 180, 132, "FEVER"), (450, 273, 180, 138, "PAYTABLE")):
        panel(x, y, w, h)
        d.text((x + 9, y + 6), t, font=f9, fill=rgb("9aa0c8"))
    # 하단 표시창
    for (x, w, t, val, vc) in ((9, 150, "CREDIT", "100", "7dff9a"), (165, 264, "", "", "ffffff"),
                              (435, 96, "WIN", "0", "ffe14d"), (537, 93, "BET", "8", "ffffff")):
        panel(x, 414, w, 57)
        if t:
            d.text((x + 9, 420), t, font=f9, fill=rgb("9aa0c8"))
            vw = d.textlength(val, font=f24)
            d.text((x + w - 9 - vw, 434), val, font=f24, fill=rgb(vc))
    return scr, covered


def visible_wall_report(covered, frame):
    """벽지가 실제로 보이는 면적 (요소·프레임이 덮지 않은 곳)."""
    cov = covered.load()
    fr = frame.load()
    wall = 0
    for y in range(SCREEN_H):
        for x in range(SCREEN_W):
            if cov[x, y] == 0 and fr[x, y][3] == 0:
                wall += 1
    return wall, SCREEN_W * SCREEN_H


# ------------------------------------------------------------------ 저장·미리보기

BIG = {"cherry": big_cherry, "orange": big_orange, "melon": big_melon, "grape": big_grape,
       "bell": big_bell, "bar": big_bar, "seven": big_seven}
SMALL = {"cherry": small_cherry, "orange": small_orange, "melon": small_melon, "grape": small_grape,
         "bell": small_bell, "bar": small_bar, "seven": small_seven}
SCALE = 3


def scaled(img):
    return img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)


def main():
    (ROOT / "assets/symbols").mkdir(parents=True, exist_ok=True)
    (ROOT / "assets/ui/icons").mkdir(parents=True, exist_ok=True)
    (ROOT / "assets/_preview").mkdir(parents=True, exist_ok=True)
    bigs = {n: f().image() for n, f in BIG.items()}
    smalls = {n: f().image() for n, f in SMALL.items()}
    tile = cell_tile().image()
    for n, img in bigs.items():
        img.save(ROOT / f"assets/symbols/{n}.png")
    for n, img in smalls.items():
        img.save(ROOT / f"assets/ui/icons/{n}.png")
    tile.save(ROOT / "assets/ui/cell_tile.png")
    ui = {"panel": panel_nine().image()}
    for state in BUTTON_STATES:
        ui[f"button_{state}"] = button_nine(state).image()
    for key, hexa in LINE_COLORS.items():
        ui[f"line_label_{key}"] = line_label(hexa).image()
    ui_final = {n: scaled(img) for n, img in ui.items()}  # 최종 크기 = 아트 x3
    for n, img in ui_final.items():
        img.save(ROOT / f"assets/ui/{n}.png")

    pad = 12
    col_w = 36 * SCALE + pad
    sheet = Image.new("RGBA", (col_w * 7 + pad, 400), rgb("2a2a44"))
    d = ImageDraw.Draw(sheet)
    names = list(BIG)
    y_big, y_tile, y_small = 24, 24 + 24 * SCALE + 28, 24 + 24 * SCALE + 28 + 28 * SCALE + 28
    d.text((pad, 6), "BIG 32x24 (x3)", fill=(255, 255, 255, 255))
    d.text((pad, y_tile - 16), "ON TILE 36x28 (x3)", fill=(255, 255, 255, 255))
    d.text((pad, y_small - 16), "SMALL 12x10 / BAR 15x10 (x3)", fill=(255, 255, 255, 255))
    for i, n in enumerate(names):
        x = pad + i * col_w
        sheet.alpha_composite(scaled(bigs[n]), (x + 2 * SCALE, y_big))
        on_tile = tile.copy()
        on_tile.alpha_composite(bigs[n], (2, 2))
        sheet.alpha_composite(scaled(on_tile), (x, y_tile))
        sheet.alpha_composite(scaled(smalls[n]), (x + 10 * SCALE, y_small))
        d.text((x + 4, y_small + 10 * SCALE + 6), n, fill=(255, 255, 255, 255))
    base_h = y_small + 10 * SCALE + 24
    ui_h = 24 * SCALE + 70
    full = Image.new("RGBA", (sheet.width, base_h + ui_h), rgb("2a2a44"))
    full.alpha_composite(sheet.crop((0, 0, sheet.width, base_h)), (0, 0))
    d2 = ImageDraw.Draw(full)
    d2.text((pad, base_h), "6-C UI (final size: panel / button normal, pressed, disabled / line labels A-H)", fill=(255, 255, 255, 255))
    x = pad
    for n in ["panel", "button_normal", "button_pressed", "button_disabled", "button_on"]:
        full.alpha_composite(ui_final[n], (x, base_h + 20))
        x += ui_final[n].width + pad
    x = pad
    for key in LINE_COLORS:
        full.alpha_composite(ui_final[f"line_label_{key}"], (x, base_h + 20 + 24 * SCALE + 12))
        x += 33 + pad
    full.save(ROOT / "assets/_preview/sheet.png")
    print("done:", ROOT / "assets/_preview/sheet.png")

    # 6-D: 벽지·프레임·로고
    wall = scaled(wallpaper_tile().image())
    frame = frame_final()
    logo_c = logo_art()
    logo = scaled(logo_c.image())
    wall.save(ROOT / "assets/ui/wallpaper_tile.png")
    frame.save(ROOT / "assets/ui/frame.png")
    logo.save(ROOT / "assets/ui/logo.png")
    screen, covered = preview_screen(wall, frame, logo)
    screen.save(ROOT / "assets/_preview/6d_screen.png")
    bare, _ = preview_screen(wall, frame, logo, with_frame=False)
    bare.save(ROOT / "assets/_preview/6d_screen_no_frame.png")
    # 로고 x6 확대 미리보기: 패널 안쪽 영역(마젠타 선) 안에 들어오는지 확인용
    big = Image.new("RGBA", (LOGO_W * 6, LOGO_H * 6), PANEL_FILL)
    big.alpha_composite(logo_c.image().resize((LOGO_W * 6, LOGO_H * 6), Image.NEAREST))
    ix0, iy0, ix1, iy1 = LOGO_INNER
    ImageDraw.Draw(big).rectangle([ix0 * 6, iy0 * 6, (ix1 + 1) * 6 - 1, (iy1 + 1) * 6 - 1], outline=(255, 0, 255, 255))
    big.save(ROOT / "assets/_preview/6d_logo_x6.png")
    lb = logo_bounds(logo_c)
    inside = lb[0] >= ix0 and lb[1] >= iy0 and lb[2] <= ix1 and lb[3] <= iy1
    print("logo bounds (art):", lb, "inner:", LOGO_INNER, "OK" if inside else "OUT OF PANEL")
    wall_px, total = visible_wall_report(covered, frame)
    print("visible wallpaper px: %d / %d = %.1f%%" % (wall_px, total, wall_px * 100.0 / total))


if __name__ == "__main__":
    main()

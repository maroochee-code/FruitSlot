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
  assets/ui/fever_banner_a/b.png, pool_banner_a/b.png   FEVER! / POOL GET! 배너 (6-E, 색 변형 2개씩)
  assets/ui/fever_bg_0~2.png, pool_bg_0~2.png          방사형 줄무늬 배경 프레임 (6-E, 640x414)
  assets/ui/coin_sheet.png      당첨 동전 6프레임 가로 시트 (6-E, 아트 48x8 -> 144x24)
  assets/_preview/6e_*.png      6-E 연출 전체 화면 합성·배너/배경 모음·동전 x6
  assets/ui/bulbs.png           전구 상태 4개(꺼짐·노랑·빨강·흰색) 가로 시트 (6-F3a, 아트 8x2 -> 24x6)
  assets/_preview/6f_bulbs.png  전구 시트·소켓 줄 모드별 미리보기
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



# ------------------------------------------------------------------ 6-E 피버·풀 연출 아트 + 당첨 동전

import json
import math

OVERLAY_ART_H = 138                      # 연출이 덮는 높이 (아트). 하단 표시창(y=138~) 위까지. 640x414 px
OVERLAY_PX_H = OVERLAY_ART_H * 3
BG_FRAME_COUNT = 3
BG_RAYS = 20                              # 방사형 줄무늬 개수 (짝수)
BG_CENTER = (106.5, 60.0)                 # 아트 좌표. 배너·심볼 뒤에 오는 중심
BG_TONES = {
    "fever": (rgb("2a0a14"), rgb("3d1220")),   # 어두운 적갈색 두 톤 (글자·숫자가 잘 보이게 차이를 작게)
    "pool": (rgb("0f3320"), rgb("164a2e")),    # 어두운 녹색 두 톤
    "gameover": (rgb("0b0d1e"), rgb("141833")),  # 7-B: 어두운 남색 두 톤. 번쩍이지 않게 한 장만 쓰고 차이를 아주 작게
}
GOLD_MARK = rgb("d09a14")

FEVER_BANNER_SIZE = (120, 28)
POOL_BANNER_SIZE = (136, 28)
COIN_SIZE = 8
COIN_FRAMES = 6
COIN_WIDTHS = [8, 6, 4, 4, 4, 6]          # 정면 -> 옆면(프레임 3 = 납작한 옆면) -> 뒷면 -> 정면. 프레임 4·5는 좌우를 뒤집은 뒷면

# 연출 배치 (아트 좌표, 213x138 영역 안). 6-E-2에서 같은 값을 상수로 쓴다.
LAYOUT = {
    "banner_y": 10,       # 배너 위쪽
    "tile": (88, 44),     # 칸 타일(36x28) 왼쪽 위
    "name_y": 76,         # 심볼 이름 글자 줄 위쪽 (갈무리14 x3 = 15 아트)
    "plate": (22, 96, 168, 28),  # BONUS 판 x, y, 폭, 높이
    "hint_px_y": 390,     # 건너뛰기 힌트 (640x480 px 기준)
    "coin_row_y": 52,     # 풀 단계: 동전 줄 위쪽
}


def _r(x, y, w, h):
    return {(i, j) for i in range(x, x + w) for j in range(y, y + h)}


def glyph_mask(ch, w, h, t):
    """블록 글자 한 개의 점 집합 (0,0 기준, 크기 w x h, 획 두께 t)."""
    m = set()
    if ch == "F":
        m |= _r(0, 0, t, h) | _r(0, 0, w, t) | _r(0, (h - t) // 2 - 1, w - 3, t)
    elif ch == "E":
        m |= _r(0, 0, t, h) | _r(0, 0, w, t) | _r(0, (h - t) // 2 - 1, w - 2, t) | _r(0, h - t, w, t)
    elif ch == "V":
        sw = t + 1
        end = (w - sw) // 2
        for y in range(h):
            lx = int(round(y * end / (h - 1)))
            m |= {(x, y) for x in range(lx, lx + sw)} | {(x, y) for x in range(w - lx - sw, w - lx)}
    elif ch in ("R", "P"):
        bh = int(h * (0.58 if ch == "R" else 0.6))
        m |= _r(0, 0, t, h) | _r(0, 0, w - 1, t) | _r(0, bh - t, w - 1, t) | _r(w - 1 - t, 0, t, bh)
        if ch == "R":
            m -= _r(t, bh, w, h)  # 아래쪽은 왼쪽 세로 획만 남기고 다리를 따로 그린다
            m |= _r(0, bh, t, h - bh)
            for y in range(bh, h):
                k = (y - bh) / max(1, h - bh - 1)
                lx = int(round(3 + k * (w - t - 1 - 3)))
                m |= {(x, y) for x in range(lx, lx + t + 1) if x < w}
        else:
            m -= _r(t, bh, w, h)
            m |= _r(0, bh, t, h - bh)
    elif ch == "O":
        m |= _r(0, 0, t, h) | _r(w - t, 0, t, h) | _r(0, 0, w, t) | _r(0, h - t, w, t)
        m -= {(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)}
    elif ch == "L":
        m |= _r(0, 0, t, h) | _r(0, h - t, w, t)
    elif ch == "G":
        m |= _r(0, 0, t, h) | _r(0, 0, w, t) | _r(0, h - t, w, t) | _r(w - t, h // 2 - 1, t, h - (h // 2 - 1))
        m |= _r(w // 2 - 1, h // 2 - 1, w - (w // 2 - 1), t)
        m -= {(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)}
    elif ch == "T":
        m |= _r(0, 0, w, t) | _r((w - t) // 2, 0, t, h)
    elif ch == "!":
        m |= _r(0, 0, w, h - t - 3) | _r(0, h - t - 1, w, t + 1)
    elif ch == "A":  # 7-B: GAME OVER용. 양옆 세로 + 윗줄 + 가운데 가로 획, 윗 모서리는 둥글게
        m |= _r(0, 0, t, h) | _r(w - t, 0, t, h) | _r(0, 0, w, t) | _r(0, h // 2, w, t)
        m -= {(0, 0), (w - 1, 0)}
    elif ch == "M":  # 7-B: 양옆 세로 + 가운데로 모이는 V 대각
        m |= _r(0, 0, t, h) | _r(w - t, 0, t, h)
        reach = h * 0.6
        for y in range(int(reach) + 1):
            lx = t - 1 + int(round(y / reach * (w / 2 - t - 0.5)))
            m |= {(x, y) for x in range(lx, lx + 2)} | {(x, y) for x in range(w - lx - 2, w - lx)}
        m |= _r(w // 2 - 1, 0, 2, int(reach) + 2)
    return m


def block_text(text, w, h, t, gap, space_w, x0, y0):
    """글자들을 이어 붙인 점 집합과, 글자별 점 집합 목록, 전체 폭."""
    mask, letters = set(), []
    x = x0
    for i, ch in enumerate(text):
        if ch == " ":
            x += space_w + gap
            continue
        cw = 4 if ch == "!" else w
        g = {(gx + x, gy + y0) for gx, gy in glyph_mask(ch, cw, h, t)}
        letters.append(g)
        mask |= g
        x += cw + gap
    return mask, letters, x - gap - x0


def text_width(text, w, gap, space_w):
    total = 0
    for ch in text:
        total += (space_w if ch == " " else (4 if ch == "!" else w)) + gap
    return total - gap


def paint_mask(c, mask, color_fn):
    """8방향 1px 외곽선을 두르고 color_fn(x, y)로 칠한다."""
    for x, y in mask:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q not in mask and c.inside(*q):
                    c.set(q[0], q[1], OUTLINE)
    for x, y in mask:
        c.set(x, y, color_fn(x, y))


def highlight_letters(c, letters):
    """글자마다 왼쪽 위 안쪽에 하이라이트 점 1개."""
    for g in letters:
        x0 = min(x for x, _ in g)
        y0 = min(y for _, y in g)
        for q in ((x0 + 1, y0 + 1), (x0, y0 + 1), (x0 + 1, y0)):
            if q in g:
                c.set(q[0], q[1], WHITE)
                break


def flame_masks(w, h, flip):
    """불꽃 겉 모양과 속(밝은 심) 모양 (0,0 기준)."""
    outer, core = set(), set()
    base = w / 2 - 0.5
    for y in range(h):
        t = y / (h - 1)
        hw = base * (min(1.0, (t / 0.72)) ** 0.7) if t <= 0.72 else base * math.sqrt(max(0.0, 1 - ((t - 0.72) / 0.28) ** 2))
        sway = 1.6 * math.sin(t * math.pi) * (-1 if flip else 1)
        cx = w / 2 + sway
        for x in range(w):
            d = abs(x + 0.5 - cx)
            if d <= hw + 0.45:
                outer.add((x, y))
            if 0.42 < t < 0.95 and d <= hw * 0.5:
                core.add((x, y))
    return outer, core


def draw_flame(c, ox, oy, w, h, flip, light, dark):
    outer, core = flame_masks(w, h, flip)
    outer = {(x + ox, y + oy) for x, y in outer}
    core = {(x + ox, y + oy) for x, y in core}
    paint_mask(c, outer, lambda x, y: light if (x - ox) < w / 2 else dark)
    for x, y in core:
        c.set(x, y, TONES["gold"][0])


def sparkle(c, cx, cy):
    cream = TONES["cream"][0]
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        c.set(cx + dx, cy + dy, cream)
    for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
        c.set(cx + dx, cy + dy, TONES["cream"][1])
    c.set(cx, cy, WHITE)


def fever_banner(variant):
    """FEVER! 120x28. a = 주황→빨강 글자 + 빨간 불꽃 / b = 금색→주황 글자 + 주황 불꽃 (6-F에서 번갈아 깜빡임)."""
    face = (TONES["orange"][0], TONES["red"][0]) if variant == "a" else (TONES["gold"][0], TONES["orange"][0])
    fire = TONES["red"] if variant == "a" else TONES["orange"]
    w, h, t, gap = 14, 16, 3, 2
    c = Canvas(*FEVER_BANNER_SIZE)
    total = text_width("FEVER!", w, gap, 0)
    x0, y0 = (FEVER_BANNER_SIZE[0] - total) // 2, (FEVER_BANNER_SIZE[1] - h) // 2
    mask, letters, _ = block_text("FEVER!", w, h, t, gap, 0, x0, y0)
    split = y0 + int(h * 0.55)
    draw_flame(c, 3, 3, 12, 22, False, fire[0], fire[1])
    draw_flame(c, FEVER_BANNER_SIZE[0] - 3 - 12, 3, 12, 22, True, fire[0], fire[1])
    paint_mask(c, mask, lambda x, y: face[0] if y < split else face[1])
    highlight_letters(c, letters)
    return c


def pool_banner(variant):
    """POOL GET! 136x28. 초록 리본 위 글자. a = 금색 글자 / b = 연한 연두 글자."""
    face = TONES["gold"] if variant == "a" else TONES["pale"]
    ribbon = (rgb("4cc24a"), rgb("2b8a3a"))
    w, h, t, gap, space_w = 11, 14, 3, 2, 7
    W, H = POOL_BANNER_SIZE
    c = Canvas(W, H)
    rb = set()
    for y in range(4, 24):
        notch = 4 - abs(y - 13.5) * 0.45
        for x in range(W):
            if x >= notch and x < W - notch:
                rb.add((x, y))
    paint_mask(c, rb, lambda x, y: ribbon[0] if y < 14 else ribbon[1])
    total = text_width("POOL GET!", w, gap, space_w)
    x0, y0 = (W - total) // 2, (H - h) // 2
    mask, letters, _ = block_text("POOL GET!", w, h, t, gap, space_w, x0, y0)
    split = y0 + int(h * 0.55)
    paint_mask(c, mask, lambda x, y: face[0] if y < split else face[1])
    highlight_letters(c, letters)
    coin = coin_frame(0).image()
    c_img = c.image()
    c_img.alpha_composite(coin, (6, 10))
    c_img.alpha_composite(coin.transpose(Image.FLIP_LEFT_RIGHT), (W - 6 - COIN_SIZE, 10))
    sparkle_c = Canvas(W, H)
    sparkle_c.px = [[c_img.getpixel((x, y)) for x in range(W)] for y in range(H)]
    sparkle(sparkle_c, 28, 2)
    sparkle(sparkle_c, W - 29, 2)
    return sparkle_c


def coin_frame(i):
    """8x8 동전 한 프레임. 폭 COIN_WIDTHS[i]. 프레임 4, 5는 좌우를 뒤집은 뒷면."""
    c = Canvas(COIN_SIZE, COIN_SIZE)
    wd = COIN_WIDTHS[i]
    if i == 3:  # 납작한 옆면: 2px 폭의 금색 띠
        body = _r(3, 1, 2, 6)
        c.part(body, "gold", split=0.5)
        # 위아래 모서리는 외곽선만 남도록 part가 둘러 준다
    else:
        rx = (wd - 2) / 2 + (0.35 if wd == 4 else 0.0)
        ry = 2.4 if wd == 4 else 3.0
        body = set()
        for y in range(COIN_SIZE):
            for x in range(COIN_SIZE):
                if ((x + 0.5 - 4) / rx) ** 2 + ((y + 0.5 - 4) / ry) ** 2 <= 1.05:
                    body.add((x, y))
        c.part(body, "gold", split=1.15)
        if wd >= 6:
            xs = sorted({x for x, _ in body})
            mid = xs[len(xs) // 2 - 1]
            for y in (3, 4, 5):
                c.set(mid, y, GOLD_MARK)
            c.set(xs[0] + 1, 2, WHITE)
    img = c.image()
    if i >= 4:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
        c.px = [[img.getpixel((x, y)) for x in range(COIN_SIZE)] for y in range(COIN_SIZE)]
    return c


def coin_sheet():
    """6프레임 가로 시트 (48x8 아트)."""
    sheet = Image.new("RGBA", (COIN_SIZE * COIN_FRAMES, COIN_SIZE), CLEAR)
    for i in range(COIN_FRAMES):
        sheet.alpha_composite(coin_frame(i).image(), (i * COIN_SIZE, 0))
    return sheet


def burst_bg(kind, frame, rays=None):
    """방사형 줄무늬 배경 213x138 (아트). frame 0~2는 줄무늬가 1/3칸씩 돌아간 모양. 맨 오른쪽 1px 열은 복사."""
    rays = BG_RAYS if rays is None else rays
    dark, light = BG_TONES[kind]
    img = Image.new("RGBA", (ART_W, OVERLAY_ART_H), dark)
    cx, cy = BG_CENTER
    phase = frame / BG_FRAME_COUNT
    for y in range(OVERLAY_ART_H):
        for x in range(ART_W):
            ang = math.atan2(y + 0.5 - cy, x + 0.5 - cx) / (2 * math.pi) % 1.0
            idx = int(ang * rays + phase) % 2
            img.putpixel((x, y), light if idx == 0 else dark)
    return img


def bg_final(kind, frame, rays=None):
    """아트 x3 = 639x414 + 오른쪽 1px 복사 -> 640x414"""
    img = scaled(burst_bg(kind, frame, rays))
    out = Image.new("RGBA", (SCREEN_W, OVERLAY_PX_H), CLEAR)
    out.paste(img, (0, 0))
    out.paste(img.crop((img.width - 1, 0, img.width, img.height)), (img.width, 0))
    return out


def _symbol_names():
    data = json.load(open(ROOT / "data/balance.json", encoding="utf-8"))
    return {s["id"]: s["name"] for s in data["symbols"]}


def _text_img(text, size, color, mult):
    """갈무리 글자를 원래 크기에서 안티앨리어싱 없이 그린 뒤 mult배 Nearest로 키운다."""
    fnt = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri14.ttf"), size)
    img = Image.new("RGBA", (size * (len(text) + 2), size + 8), CLEAR)
    d = ImageDraw.Draw(img)
    d.fontmode = "1"
    d.text((1, 2), text, font=fnt, fill=color)
    box = img.getbbox()
    img = img.crop(box) if box else img
    return img.resize((img.width * mult, img.height * mult), Image.NEAREST)


def overlay_preview(base, kind, symbol, bonus, step_text, bg_idx, variant):
    """현재 화면(base) 위에 연출 한 장면을 합성한다. kind = fever / pool."""
    scr = base.copy()
    scr.alpha_composite(bg_final(kind, bg_idx), (0, 0))
    banner = (fever_banner if kind == "fever" else pool_banner)(variant).image()
    bx = (ART_W - banner.width) // 2
    scr.alpha_composite(scaled(banner), (bx * 3, LAYOUT["banner_y"] * 3))
    names = _symbol_names()
    if kind == "fever":
        tile = Image.open(ROOT / "assets/ui/cell_tile.png").convert("RGBA")
        sym = Image.open(ROOT / f"assets/symbols/{symbol.lower()}.png").convert("RGBA")
        tile.alpha_composite(sym, (2, 2))
        tx, ty = LAYOUT["tile"]
        scr.alpha_composite(scaled(tile), (tx * 3, ty * 3))
        name = names[symbol]
        plate_text = "BONUS +%d" % bonus
        mult = 3
    else:
        # 풀: 칸 타일 대신 동전 줄 (프레임 0~4를 차례로 보여 줌 = 6-F에서 회전)
        sheet = coin_sheet()
        for i in range(5):
            fr = sheet.crop((i * COIN_SIZE, 0, (i + 1) * COIN_SIZE, COIN_SIZE))
            scr.alpha_composite(scaled(fr), ((70 + i * 16) * 3, LAYOUT["coin_row_y"] * 3))
        name = "POOL"
        plate_text = "POOL +%d" % bonus
        mult = 4
    nimg = _text_img(name, 15, TONES["cream"][0], 3)
    scr.alpha_composite(nimg, ((SCREEN_W - nimg.width) // 2, LAYOUT["name_y"] * 3))
    px, py, pw, ph = LAYOUT["plate"]
    plate = nine_slice(Image.open(ROOT / "assets/ui/panel.png").convert("RGBA"), pw * 3, ph * 3)
    scr.alpha_composite(plate, (px * 3, py * 3))
    timg = _text_img(plate_text, 15, rgb("ffd23a"), mult)
    scr.alpha_composite(timg, (px * 3 + (pw * 3 - timg.width) // 2, py * 3 + (ph * 3 - timg.height) // 2))
    small = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11.ttf"), 12)
    d = ImageDraw.Draw(scr)
    d.fontmode = "1"
    hint = "SPACE: 건너뛰기"
    d.text(((SCREEN_W - d.textlength(hint, font=small)) // 2, LAYOUT["hint_px_y"]), hint, font=small, fill=rgb("8a8aa0"))
    cnt = step_text
    if cnt:
        d.text((SCREEN_W - 12 - d.textlength(cnt, font=small), 8), cnt, font=small, fill=rgb("8a8aa0"))
    fits = timg.width <= pw * 3 - 12 * 3
    return scr, fits


def build_6e(base):
    """6-E 에셋을 저장하고 미리보기를 만든다. base = 6-D 전체 화면 근사본."""
    ui = ROOT / "assets/ui"
    prev = ROOT / "assets/_preview"
    for v in ("a", "b"):
        scaled(fever_banner(v).image()).save(ui / f"fever_banner_{v}.png")
        scaled(pool_banner(v).image()).save(ui / f"pool_banner_{v}.png")
    for kind in ("fever", "pool"):
        for i in range(BG_FRAME_COUNT):
            bg_final(kind, i).save(ui / f"{kind}_bg_{i}.png")
    scaled(coin_sheet()).save(ui / "coin_sheet.png")
    p1, f1 = overlay_preview(base, "fever", "CHERRY", 88, "1 / 2", 0, "a")
    p2, f2 = overlay_preview(base, "fever", "SEVEN", 800, "2 / 2", 1, "b")
    p3, f3 = overlay_preview(base, "pool", "", 1523, "2 / 2", 0, "a")
    p4, f4 = overlay_preview(base, "pool", "", 1523, "2 / 2", 2, "b")
    p1.save(prev / "6e_fever.png")
    p2.save(prev / "6e_fever_seven_b.png")
    p3.save(prev / "6e_pool.png")
    p4.save(prev / "6e_pool_b.png")
    print("BONUS/POOL 금액 글자가 판 안에 들어감:", f1 and f2 and f3 and f4)
    # 배너·배경 프레임 한눈에 보기
    pad = 12
    sheet = Image.new("RGBA", (3 * 426 + 4 * pad, 120 * 3 + 2 * 276 + 5 * pad), rgb("2a2a44"))
    y = pad
    x = pad
    for v in ("a", "b"):
        sheet.alpha_composite(scaled(fever_banner(v).image()), (x, y))
        x += FEVER_BANNER_SIZE[0] * 3 + pad
    y += 28 * 3 + pad
    x = pad
    for v in ("a", "b"):
        sheet.alpha_composite(scaled(pool_banner(v).image()), (x, y))
        x += POOL_BANNER_SIZE[0] * 3 + pad
    y += 28 * 3 + pad
    for kind in ("fever", "pool"):
        x = pad
        for i in range(BG_FRAME_COUNT):
            bg = burst_bg(kind, i).resize((ART_W * 2, OVERLAY_ART_H * 2), Image.NEAREST)
            sheet.alpha_composite(bg, (x, y))
            x += 426 + pad
        y += 276 + pad
    sheet.crop((0, 0, sheet.width, y)).save(prev / "6e_overview.png")
    # 동전 시트 x6: 여러 바탕 위
    backs = [("panel", FRAME_FILL), ("wall dark", WALL_DARK), ("wall light", WALL_LIGHT),
             ("fever bg", BG_TONES["fever"][1]), ("pool bg", BG_TONES["pool"][1])]
    coin_img = Image.new("RGBA", (COIN_FRAMES * 56 + 20, len(backs) * 56 + 12), rgb("2a2a44"))
    cs = coin_sheet()
    for r, (_, col) in enumerate(backs):
        ImageDraw.Draw(coin_img).rectangle([6, 6 + r * 56, 6 + COIN_FRAMES * 56 + 7, 6 + r * 56 + 51], fill=col)
        for i in range(COIN_FRAMES):
            fr = cs.crop((i * COIN_SIZE, 0, (i + 1) * COIN_SIZE, COIN_SIZE)).resize((COIN_SIZE * 6, COIN_SIZE * 6), Image.NEAREST)
            coin_img.alpha_composite(fr, (10 + i * 56, 6 + r * 56 + 2))
    coin_img.save(prev / "6e_coin_x6.png")



# ------------------------------------------------------------------ 6-F3a 켜진 전구 시트

# 전구 상태: 이름, 면 색, 하이라이트 색 (아트 2x2의 왼쪽 위 한 점)
BULB_STATES = [
    ("off", "8a7a3a", "b0a25a"),
    ("on", "ffe14d", "fff7b8"),
    ("red", "ff4040", "ff9a9a"),
    ("white", "ffffff", "ffffff"),
]
BULB_ART = 2
BULB_PX = BULB_ART * 3


def bulb_sheet_art():
    """전구 상태 4개를 가로로 붙인 시트 (아트 8x2). 한 칸 2x2 = 점 4개, 왼쪽 위 한 점이 하이라이트."""
    c = Canvas(BULB_ART * len(BULB_STATES), BULB_ART)
    for i, (_, base, hi) in enumerate(BULB_STATES):
        for dx in range(BULB_ART):
            for dy in range(BULB_ART):
                c.set(i * BULB_ART + dx, dy, rgb(hi) if (dx, dy) == (0, 0) else rgb(base))
    return c


def _bulb_state(mode, index, t):
    """게임의 BulbPattern과 같은 규칙 (미리보기용). mode: idle / spin / win / fever"""
    idle_sec, spin_step, win_flash, fever_sec = 0.8, 0.06, 0.12, 0.2
    if mode == "idle":
        return 1 if (index + int(t / idle_sec)) % 2 == 0 else 0
    if mode == "spin":
        return 1 if (index - int(t / spin_step)) % 3 == 0 else 0
    if mode == "win":
        return 3 if int(t / win_flash) % 2 == 0 else 0
    return 1 if int(t / fever_sec) % 2 == 0 else 2


def build_6f3a():
    sheet = scaled(bulb_sheet_art().image())
    sheet.save(ROOT / "assets/ui/bulbs.png")
    # 미리보기(x2): 전구 4상태 + 프레임 가로 띠 위 소켓 18개(간격 8아트 = 24px)를 모드별로, 시간 두 장면씩
    s = 2
    pad = 12
    strip_w = 18 * 24 * s
    rows = [("state", 0.0)] + [(m, t) for m in ("idle", "spin", "win", "fever") for t in (0.0, 0.13)]
    row_h = BULB_PX * s + pad
    img = Image.new("RGBA", (strip_w + 160, pad + row_h * len(rows) + BULB_PX * s * 3 + 30), rgb("2a2a44"))
    d = ImageDraw.Draw(img)
    y = pad
    for mode, t in rows:
        if mode == "state":
            for i, (name, _, _) in enumerate(BULB_STATES):
                tile = sheet.crop((i * BULB_PX, 0, (i + 1) * BULB_PX, BULB_PX)).resize((BULB_PX * s * 3, BULB_PX * s * 3), Image.NEAREST)
                img.alpha_composite(tile, (pad + i * (BULB_PX * s * 3 + 12), y))
                d.text((pad + i * (BULB_PX * s * 3 + 12), y + BULB_PX * s * 3 + 2), name, fill=(255, 255, 255, 255))
            y += BULB_PX * s * 3 + pad + 14
            continue
        d.rectangle([pad, y - 4, pad + strip_w, y + BULB_PX * s + 4], fill=rgb("1b1f4a"))
        for i in range(18):
            st = _bulb_state(mode, i, t)
            tile = sheet.crop((st * BULB_PX, 0, (st + 1) * BULB_PX, BULB_PX)).resize((BULB_PX * s, BULB_PX * s), Image.NEAREST)
            img.alpha_composite(tile, (pad + 6 * s + i * 24 * s, y))
        d.text((pad + strip_w + 8, y), "%s t=%.2f" % (mode, t), fill=(255, 255, 255, 255))
        y += row_h
    img.crop((0, 0, img.width, y)).save(ROOT / "assets/_preview/6f_bulbs.png")
    print("6-F3a: bulbs.png", sheet.size)

# ------------------------------------------------------------------ 7-B GAME OVER 배너·배경

GAMEOVER_BANNER_SIZE = (152, 28)
GAMEOVER_BG_RAYS = 12                     # 줄무늬 개수 (짝수). 정지 화면이라 프레임은 0번 한 장
GAMEOVER_TEXT = "GAME OVER"
GAMEOVER_SLATE = (rgb("6a70a0"), rgb("3a3f68"))   # 리본 두 톤 (밝음, 어두움)
# 미리보기 배치 (아트 좌표, 213x138 영역 안. 화면 좌표 = 아트 x3). 7-B-3에서 같은 값을 상수로 쓴다.
GAMEOVER_LAYOUT = {
    "banner_y": 10,                 # 배너 위쪽
    "info": (22, 44, 168, 32),      # POOL·피버 카운터 패널 x, y, 폭, 높이
    "button_y": 84, "button_h": 18, "button_w": 80,
    "button_xs": (22, 111),         # CONTINUE, NEW GAME 왼쪽 x
    "left_y": 106,                  # 남은 횟수 글자 줄 위쪽
    "hint_px_y": 390,               # 조작 안내 (640x480 px 기준)
}


def gameover_banner():
    """GAME OVER 152x28. 어두운 슬레이트 리본 위 빨간 글자 (정지 그림 한 장)."""
    w, h, t, gap, space_w = 14, 16, 3, 2, 8
    W, H = GAMEOVER_BANNER_SIZE
    c = Canvas(W, H)
    rb = set()
    for y in range(4, 24):
        notch = 4 - abs(y - 13.5) * 0.45
        for x in range(W):
            if x >= notch and x < W - notch:
                rb.add((x, y))
    paint_mask(c, rb, lambda x, y: GAMEOVER_SLATE[0] if y < 14 else GAMEOVER_SLATE[1])
    total = text_width(GAMEOVER_TEXT, w, gap, space_w)
    x0, y0 = (W - total) // 2, (H - h) // 2
    mask, letters, _ = block_text(GAMEOVER_TEXT, w, h, t, gap, space_w, x0, y0)
    split = y0 + int(h * 0.55)
    paint_mask(c, mask, lambda x, y: TONES["red"][0] if y < split else TONES["red"][1])
    highlight_letters(c, letters)
    return c


def gameover_bg():
    """640x414 어두운 방사형 줄무늬 (정지)"""
    return bg_final("gameover", 0, GAMEOVER_BG_RAYS)


def _go_button(label_top, label_bottom, state, selected, x_art, base):
    """미리보기용 버튼 한 개. state = normal / disabled, selected면 AUTO ON 같은 금색 면."""
    L = GAMEOVER_LAYOUT
    px, py, pw, ph = x_art * 3, L["button_y"] * 3, L["button_w"] * 3, L["button_h"] * 3
    skin = "on" if selected else state
    box = nine_slice(Image.open(ROOT / f"assets/ui/button_{skin}.png").convert("RGBA"), pw, ph)
    base.alpha_composite(box, (px, py))
    if selected:
        color = rgb("2b1b3d")
    else:
        color = rgb("6b7099") if state == "disabled" else rgb("ffffff")
    top = _text_img(label_top, 15, color, 1)
    bottom = _text_img(label_bottom, 15, color if selected or state == "disabled" else rgb("ffd23a"), 1)
    gap = 6
    y = py + (ph - (top.height + gap + bottom.height)) // 2
    base.alpha_composite(top, (px + (pw - top.width) // 2, y))
    base.alpha_composite(bottom, (px + (pw - bottom.width) // 2, y + top.height + gap))


def gameover_preview(base, pool, counts, left, left_max, continue_credit, new_credit):
    """현재 화면(base) 위에 GAME OVER 장면을 합성한다. left = 남은 이어하기 횟수."""
    L = GAMEOVER_LAYOUT
    scr = base.copy()
    scr.alpha_composite(gameover_bg(), (0, 0))
    banner = gameover_banner().image()
    bx = (ART_W - banner.width) // 2
    scr.alpha_composite(scaled(banner), (bx * 3, L["banner_y"] * 3))
    # POOL·피버 카운터 패널
    ix, iy, iw, ih = L["info"]
    panel = nine_slice(Image.open(ROOT / "assets/ui/panel.png").convert("RGBA"), iw * 3, ih * 3)
    scr.alpha_composite(panel, (ix * 3, iy * 3))
    pimg = _text_img("POOL %s" % format(pool, ","), 15, rgb("ff9a1f"), 2)
    scr.alpha_composite(pimg, (ix * 3 + (iw * 3 - pimg.width) // 2, iy * 3 + 9))
    groups = []
    for sym, n in counts:
        icon = scaled(Image.open(ROOT / f"assets/ui/icons/{sym}.png").convert("RGBA"))
        txt = _text_img("×%d" % n, 15, TONES["cream"][0], 1)
        groups.append((icon, txt))
    gap_in, gap_out = 6, 30
    total = sum(i.width + gap_in + t.width for i, t in groups) + gap_out * (len(groups) - 1)
    x = ix * 3 + (iw * 3 - total) // 2
    y = iy * 3 + 54
    for icon, txt in groups:
        scr.alpha_composite(icon, (x, y))
        scr.alpha_composite(txt, (x + icon.width + gap_in, y + (icon.height - txt.height) // 2))
        x += icon.width + gap_in + txt.width + gap_out
    # 버튼 2개: 이어하기가 남았으면 CONTINUE가 선택(금색), 없으면 비활성 + NEW GAME 선택
    can = left > 0
    cx, nx = L["button_xs"]
    _go_button("CONTINUE", "+%s" % format(continue_credit, ","), "normal" if can else "disabled", can, cx, scr)
    _go_button("NEW GAME", "+%s" % format(new_credit, ","), "normal", not can, nx, scr)
    # 남은 횟수, 조작 안내
    small = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11.ttf"), 12)
    d = ImageDraw.Draw(scr)
    d.fontmode = "1"
    left_text = "CONTINUE 남은 횟수  %d / %d" % (left, left_max)
    d.text(((SCREEN_W - d.textlength(left_text, font=small)) // 2, L["left_y"] * 3 + 3), left_text, font=small, fill=TONES["cream"][0] if can else rgb("ff6a6a"))
    hint = "←  → 선택     SPACE / ENTER 결정"
    d.text(((SCREEN_W - d.textlength(hint, font=small)) // 2, L["hint_px_y"]), hint, font=small, fill=rgb("8a8aa0"))
    return scr


def build_7b(base, install=False):
    """7-B 그림을 만들고 미리보기를 저장한다. install=False면 assets/_preview에만 쓴다 (승인 전).
    install=True(7-B-3, 승인 뒤)면 assets/ui에도 gameover_banner.png / gameover_bg.png로 저장한다."""
    prev = ROOT / "assets/_preview"
    prev.mkdir(parents=True, exist_ok=True)
    banner = scaled(gameover_banner().image())
    bg = gameover_bg()
    banner.save(prev / "7b_gameover_banner.png")
    bg.save(prev / "7b_gameover_bg.png")
    if install:
        banner.save(ROOT / "assets/ui/gameover_banner.png")
        bg.save(ROOT / "assets/ui/gameover_bg.png")
    counts = [("cherry", 17), ("grape", 3), ("bell", 2), ("seven", 1)]
    gameover_preview(base, 1234, counts, 2, 3, 1000, 3000).save(prev / "7b_gameover.png")
    gameover_preview(base, 1234, counts, 0, 3, 1000, 3000).save(prev / "7b_gameover_no_continue.png")
    # 배너를 여러 바탕 위에 x1 / 배경 모음
    pad = 12
    backs = [("bg", BG_TONES["gameover"][1]), ("panel", FRAME_FILL), ("wall dark", WALL_DARK), ("wall light", WALL_LIGHT)]
    sheet = Image.new("RGBA", (banner.width + 2 * pad + 40, len(backs) * (banner.height + pad) + pad), rgb("2a2a44"))
    for r, (_, col) in enumerate(backs):
        ImageDraw.Draw(sheet).rectangle([pad, pad + r * (banner.height + pad), pad + banner.width + 39, pad + r * (banner.height + pad) + banner.height - 1], fill=col)
        sheet.alpha_composite(banner, (pad + 20, pad + r * (banner.height + pad)))
    sheet.save(prev / "7b_banner_backs.png")
    print("GAME OVER 배너:", banner.size, "/ 배경:", bg.size)


def build_7b_standalone(install=False):
    """6-D 화면 근사본을 새로 만들어 7-B만 생성한다 (다른 에셋은 건드리지 않는다)."""
    wall = scaled(wallpaper_tile().image())
    screen, _ = preview_screen(wall, frame_final(), scaled(logo_art().image()))
    build_7b(screen, install)


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
    # 6-E: 피버·풀 연출 아트 + 동전
    build_6e(screen)
    # 6-F3a: 켜진 전구 시트
    build_6f3a()
    # 7-B: GAME OVER 미리보기 (승인 전이라 assets/_preview에만 저장)
    build_7b(screen)


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "7b":
        # python tools/gen_pixel_assets.py 7b [install]  : 7-B 그림만 만든다. install은 승인 뒤 assets/ui에도 저장
        build_7b_standalone(install=len(sys.argv) > 2 and sys.argv[2] == "install")
    else:
        main()

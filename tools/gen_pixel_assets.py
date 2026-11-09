"""maroochee slot 도트 리소스 생성기 (6-A).

실행: python tools/gen_pixel_assets.py   (Pillow 필요)
만드는 것:
  assets/symbols/*.png        큰 심볼 32x24 (7종)
  assets/ui/cell_tile.png     칸 타일 36x28
  assets/ui/icons/*.png       작은 아이콘 12x10 (BAR만 15x10)
  assets/ui/panel.png         패널 9-slice (6-C, 최종 크기 24x24 = 아트 8x8 x3, 모서리 6px)
  assets/ui/button_normal.png / button_pressed.png / button_disabled.png   버튼 3상태 9-slice (같은 규격)
  assets/ui/line_label_a.png ~ _h.png   라인 라벨 33x21 (아트 11x7 x3)
  assets/_preview/sheet.png   위 전부를 x3 Nearest로 확대해 한 장에 (6-C 에셋은 이미 3배라 그대로 붙임)
규칙: 안티앨리어싱·그라데이션 없음(색은 팔레트 몇 가지만), 1px 외곽선, 왼쪽 위 밝게/오른쪽 아래 어둡게 2톤, 하이라이트 점.
"""
from pathlib import Path
from PIL import Image, ImageDraw

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
    for n in ["panel", "button_normal", "button_pressed", "button_disabled"]:
        full.alpha_composite(ui_final[n], (x, base_h + 20))
        x += ui_final[n].width + pad
    x = pad
    for key in LINE_COLORS:
        full.alpha_composite(ui_final[f"line_label_{key}"], (x, base_h + 20 + 24 * SCALE + 12))
        x += 33 + pad
    full.save(ROOT / "assets/_preview/sheet.png")
    print("done:", ROOT / "assets/_preview/sheet.png")


if __name__ == "__main__":
    main()

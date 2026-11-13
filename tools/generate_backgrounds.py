"""Generate the five Skywire backgrounds and their four style variants.

Run from the project root:
    python tools/generate_backgrounds.py

Art direction lives here:
- BG_PALETTES: base sky / terrain / accent colours for each background.
- STYLE_GRADES: per-background colour treatment for sky / sunset / night / gray.
The output files are `assets/visuals/backgrounds/<bg>_<style>.png`.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
from pathlib import Path
import math
import random

OUT = Path(__file__).resolve().parents[1] / "assets" / "visuals" / "backgrounds"
OUT.mkdir(parents=True, exist_ok=True)
S = 2
W, H = 1280 * S, 720 * S

BG_PALETTES = {
    "paradise": {"sky": ((104, 199, 239), (255, 239, 190)), "terrain": (68, 170, 137), "accent": (244, 154, 86)},
    "forest": {"sky": ((138, 207, 186), (232, 242, 199)), "terrain": (45, 108, 85), "accent": (220, 198, 128)},
    "snow": {"sky": ((39, 83, 130), (184, 214, 230)), "terrain": (211, 229, 240), "accent": (247, 211, 139)},
    "clouds": {"sky": ((96, 172, 224), (252, 219, 186)), "terrain": (102, 145, 104), "accent": (244, 176, 111)},
    "dream": {"sky": ((31, 20, 70), (118, 83, 141)), "terrain": (72, 91, 120), "accent": (188, 151, 225)},
}

# Per-background grade: image is multiplied by this colour, then an atmospheric layer is added.
STYLE_GRADES = {
    "paradise": {"sunset": (255, 176, 130), "night": (40, 61, 115), "gray": (130, 143, 153)},
    "forest": {"sunset": (239, 167, 116), "night": (31, 57, 82), "gray": (127, 147, 139)},
    "snow": {"sunset": (255, 184, 150), "night": (35, 65, 116), "gray": (147, 161, 176)},
    "clouds": {"sunset": (255, 175, 128), "night": (52, 82, 128), "gray": (146, 157, 167)},
    "dream": {"sunset": (250, 145, 150), "night": (29, 36, 82), "gray": (126, 135, 154)},
}
SUNSET_SKY = {
    "paradise": ((255, 111, 132), (255, 189, 99)),
    "forest": ((130, 75, 135), (255, 171, 92)),
    "snow": ((108, 78, 148), (255, 168, 130)),
    "clouds": ((255, 124, 126), (255, 190, 112)),
    "dream": ((255, 110, 156), (255, 193, 123)),
}
STYLES = ("sky", "sunset", "night", "gray")


def rgba(color, alpha=255):
    return (color[0], color[1], color[2], alpha)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(top, bottom):
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    for y in range(H):
        d.line((0, y, W, y), fill=lerp(top, bottom, y / (H - 1)))
    return im


def glow(im, center, radius, color, alpha=100):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for r in range(radius, 0, -max(1, radius // 30)):
        a = int(alpha * (1.0 - r / radius) ** 2)
        d.ellipse((center[0] - r, center[1] - r, center[0] + r, center[1] + r), fill=rgba(color, a))
    im.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius // 14)))


def cloud(im, cx, cy, sx, sy, color=(255, 255, 255), alpha=170):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(8):
        ox = (i - 3.5) * sx * 0.23
        oy = math.sin(i * 1.5) * sy * 0.18
        d.ellipse((cx + ox - sx * 0.29, cy + oy - sy * 0.5,
                   cx + ox + sx * 0.29, cy + oy + sy * 0.5), fill=rgba(color, alpha))
    im.alpha_composite(layer.filter(ImageFilter.GaussianBlur(sx * 0.006)))


def mountain(im, base_y, heights, color):
    d = ImageDraw.Draw(im)
    pts = [(0, H)]
    step = W / (len(heights) - 1)
    for i, h in enumerate(heights):
        pts.append((i * step, base_y - h))
    pts.append((W, H))
    d.polygon(pts, fill=rgba(color))


def hill(im, base_y, color):
    d = ImageDraw.Draw(im)
    d.ellipse((-260 * S, base_y - 130 * S, 720 * S, base_y + 300 * S), fill=rgba(color))
    d.ellipse((500 * S, base_y - 160 * S, 1540 * S, base_y + 320 * S), fill=rgba(color))


def pine(im, x, base, height, color, trunk=(43, 66, 49), snow=False):
    d = ImageDraw.Draw(im)
    w = height * 0.33
    d.rectangle((x - w * 0.07, base - height * 0.2, x + w * 0.07, base), fill=rgba(trunk))
    for layer in range(4):
        top = base - height * (0.36 + layer * 0.17)
        bottom = base - height * (0.08 + layer * 0.17)
        hw = w * (1.0 - layer * 0.17)
        d.polygon([(x, top), (x - hw, bottom), (x + hw, bottom)], fill=rgba(color))
        if snow:
            d.polygon([(x, top), (x - hw * 0.42, bottom - height * 0.03), (x + hw * 0.42, bottom - height * 0.03)],
                      fill=rgba((240, 248, 252), 185))


def broadleaf(im, x, base, height, canopy, trunk=(67, 54, 39)):
    d = ImageDraw.Draw(im)
    d.rectangle((x - height * 0.035, base - height * 0.45, x + height * 0.035, base), fill=rgba(trunk))
    for i in range(3):
        cy = base - height * (0.55 + i * 0.13)
        r = height * (0.23 - i * 0.045)
        d.ellipse((x - r, cy - r * 0.55, x + r, cy + r * 0.55), fill=rgba(canopy))


def ferris(im, cx, cy, radius, ink=(30, 64, 80)):
    d = ImageDraw.Draw(im)
    d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=rgba(ink), width=7 * S)
    for i in range(12):
        a = math.radians(i * 30)
        ex, ey = cx + math.cos(a) * radius, cy + math.sin(a) * radius
        d.line((cx, cy, ex, ey), fill=rgba(ink), width=3 * S)
        d.ellipse((ex - 9 * S, ey - 9 * S, ex + 9 * S, ey + 9 * S), fill=rgba((244, 178, 80)))
    d.line((cx, cy + radius, cx, cy + radius * 1.95), fill=rgba(ink), width=7 * S)
    d.line((cx - radius * 0.48, cy + radius * 1.9, cx + radius * 0.48, cy + radius * 1.9),
           fill=rgba(ink), width=6 * S)


def tent(im, x, base, width, height, canvas_a=(232, 108, 88), canvas_b=(255, 240, 207)):
    d = ImageDraw.Draw(im)
    peak = (x, base - height)
    left = (x - width * 0.5, base)
    right = (x + width * 0.5, base)
    d.polygon([left, peak, (x, base)], fill=rgba(canvas_a))
    d.polygon([peak, right, (x, base)], fill=rgba(canvas_b))
    d.line((x, base - height * 0.55, x, base), fill=rgba((80, 58, 44)), width=3 * S)
    d.line((x, base - height, x, base - height * 1.12), fill=rgba((80, 58, 44)), width=2 * S)


def balloon(im, x, y, radius, color):
    d = ImageDraw.Draw(im)
    d.ellipse((x - radius, y - radius * 1.2, x + radius, y + radius * 1.2), fill=rgba(color))
    d.polygon([(x - radius * 0.35, y + radius * 1.1), (x + radius * 0.35, y + radius * 1.1),
               (x + radius * 0.18, y + radius * 1.65), (x - radius * 0.18, y + radius * 1.65)],
              fill=rgba((97, 78, 61)))
    d.line((x, y + radius * 1.6, x, y + radius * 2.05), fill=rgba((70, 60, 50)), width=2 * S)


def island(im, x, y, scale, grass, rock, waterfall=False):
    d = ImageDraw.Draw(im)
    d.ellipse((x - scale, y - scale * 0.2, x + scale, y + scale * 0.2), fill=rgba(grass))
    d.polygon([
        (x - scale * 0.72, y + scale * 0.05), (x - scale * 0.4, y + scale * 0.52),
        (x - scale * 0.16, y + scale * 0.24), (x + scale * 0.02, y + scale * 0.68),
        (x + scale * 0.3, y + scale * 0.28), (x + scale * 0.58, y + scale * 0.5),
        (x + scale * 0.74, y + scale * 0.05),
    ], fill=rgba(rock))
    d.polygon([
        (x - scale * 0.5, y + scale * 0.1), (x - scale * 0.2, y + scale * 0.4),
        (x + scale * 0.05, y + scale * 0.18), (x + scale * 0.3, y + scale * 0.42),
        (x + scale * 0.55, y + scale * 0.1),
    ], fill=rgba(tuple(max(0, c - 18) for c in rock)))
    for i in range(3):
        pine(im, x - scale * 0.35 + i * scale * 0.3, y - scale * 0.02, scale * 0.34, grass)
    if waterfall:
        d.polygon([(x + scale * 0.12, y + scale * 0.12), (x + scale * 0.22, y + scale * 0.12),
                   (x + scale * 0.2, y + scale * 0.88), (x + scale * 0.08, y + scale * 0.82)],
                  fill=rgba((177, 224, 239), 170))
        glow(im, (int(x + scale * 0.15), int(y + scale * 0.7)), int(scale * 0.28), (190, 235, 245), 45)


def bushes(im, color, count=22):
    d = ImageDraw.Draw(im)
    for i in range(count):
        x = random.randint(0, W)
        y = random.randint(int(H * 0.86), H)
        r = random.randint(10, 26) * S
        d.ellipse((x - r, y - r * 0.55, x + r, y + r * 0.55), fill=rgba(color, 190))


def save(im, name):
    im.convert("RGB").resize((1280, 720), Image.LANCZOS).save(OUT / name, optimize=True)


def paradise():
    random.seed(11)
    pal = BG_PALETTES["paradise"]
    im = gradient(*pal["sky"]).convert("RGBA")
    glow(im, (1060 * S, 135 * S), 205 * S, (255, 236, 152), 100)
    for cx, cy, sx, sy, a in [(210, 150, 220, 60, 155), (650, 110, 180, 48, 130),
                              (920, 235, 200, 52, 145), (360, 315, 155, 42, 85)]:
        cloud(im, cx * S, cy * S, sx * S, sy * S, alpha=a)
    mountain(im, 472 * S, [95, 140, 75, 160, 110, 170, 82], (137, 208, 183))
    mountain(im, 540 * S, [100, 145, 190, 120, 175, 105, 155], (53, 166, 136))
    hill(im, 630 * S, (36, 127, 103))
    hill(im, 700 * S, (24, 104, 82))
    d = ImageDraw.Draw(im)
    # Fairground silhouettes: ferris wheel, coaster, tents and balloons.
    ferris(im, 770 * S, 292 * S, 108 * S)
    d.arc((70 * S, 520 * S, 550 * S, 710 * S), 198, 342, fill=rgba((32, 75, 88)), width=6 * S)
    for x in (180, 300, 420, 500):
        d.line((x * S, 615 * S, x * S, 678 * S), fill=rgba((32, 75, 88)), width=4 * S)
    tent(im, 240 * S, 575 * S, 105 * S, 118 * S)
    tent(im, 365 * S, 600 * S, 76 * S, 88 * S, (81, 145, 190), (245, 238, 210))
    tent(im, 525 * S, 615 * S, 62 * S, 70 * S, (242, 190, 94), (255, 244, 210))
    for x, y, r, c in [(620, 155, 15, (244, 139, 122)), (666, 128, 11, (250, 207, 109)),
                       (708, 173, 9, (116, 192, 221))]:
        balloon(im, x * S, y * S, r * S, c)
    # Foreground planting keeps the lower edge organic without hiding the track.
    bushes(im, (18, 91, 70), 34)
    for i in range(80):
        x, y = random.randint(0, W), random.randint(int(H * 0.76), H)
        r = random.randint(2, 5) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=rgba((250, 218, 133), 180))
    save(im, "paradise.png")


def forest():
    random.seed(22)
    pal = BG_PALETTES["forest"]
    im = gradient(*pal["sky"]).convert("RGBA")
    glow(im, (1040 * S, 80 * S), 180 * S, (255, 246, 198), 70)
    mountain(im, 480 * S, [110, 170, 95, 150, 120, 185, 80], (94, 155, 137))
    mountain(im, 555 * S, [80, 120, 160, 90, 140, 95, 155], (48, 111, 94))
    d = ImageDraw.Draw(im)
    d.ellipse((-200 * S, 570 * S, 1500 * S, 980 * S), fill=rgba((45, 112, 86)))
    # Winding path with soft grass edges.
    path = [(560 * S, H), (820 * S, H), (735 * S, 610 * S), (700 * S, 540 * S), (660 * S, 500 * S),
            (600 * S, 500 * S), (565 * S, 540 * S), (585 * S, 610 * S)]
    d.polygon(path, fill=rgba((205, 184, 128)))
    d.line([(560 * S, H), (585 * S, 610 * S), (565 * S, 540 * S), (600 * S, 500 * S)],
           fill=rgba((231, 215, 165), 180), width=9 * S, joint="curve")
    for x, h, c in [(75, 330, (28, 79, 63)), (205, 255, (33, 91, 71)), (360, 400, (24, 73, 58)),
                    (975, 420, (25, 77, 60)), (1135, 305, (30, 86, 66)), (1245, 245, (24, 73, 58))]:
        pine(im, x * S, 655 * S, h * S, c)
    for x, y, r, c in [(545, 585, 70, (52, 121, 88)), (765, 615, 58, (61, 137, 96)),
                       (885, 555, 62, (41, 105, 79))]:
        broadleaf(im, x * S, y * S, r * S, c)
    bushes(im, (25, 86, 66), 24)
    for i in range(34):
        x, y = random.randint(0, W), random.randint(int(H * 0.82), H)
        d.ellipse((x - 5 * S, y - 3 * S, x + 5 * S, y + 3 * S), fill=rgba((236, 224, 162), 140))
    save(im, "forest.png")


def snow():
    random.seed(33)
    pal = BG_PALETTES["snow"]
    im = gradient(*pal["sky"]).convert("RGBA")
    glow(im, (1040 * S, 120 * S), 150 * S, (240, 247, 255), 85)
    d = ImageDraw.Draw(im)
    for i in range(65):
        x, y = random.randint(0, W), random.randint(0, 500 * S)
        r = random.randint(1, 3) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=rgba((240, 248, 255), random.randint(110, 200)))
    mountain(im, 500 * S, [190, 250, 150, 280, 170, 240, 130, 210], (205, 225, 238))
    mountain(im, 570 * S, [100, 150, 200, 130, 180, 120, 170, 110], (150, 184, 205))
    d.ellipse((-250 * S, 580 * S, 700 * S, 980 * S), fill=rgba((226, 238, 246)))
    d.ellipse((500 * S, 600 * S, 1550 * S, 1000 * S), fill=rgba((210, 228, 240)))
    for x, h in [(110, 180), (260, 135), (520, 200), (820, 155), (1120, 215), (1230, 150)]:
        pine(im, x * S, 650 * S, h * S, (35, 75, 82), (48, 65, 73), snow=True)
    # A small cabin gives scale and warmth.
    d.polygon([(690 * S, 610 * S), (790 * S, 610 * S), (790 * S, 665 * S), (690 * S, 665 * S)], fill=rgba((105, 73, 58)))
    d.polygon([(675 * S, 612 * S), (740 * S, 575 * S), (805 * S, 612 * S)], fill=rgba((234, 239, 242)))
    d.rectangle((735 * S, 628 * S, 752 * S, 665 * S), fill=rgba((247, 198, 103)))
    save(im, "snow.png")


def clouds():
    random.seed(44)
    # High-altitude daylight: crisp white cloud banks over pale blue.
    im = gradient((157, 211, 239), (239, 249, 252)).convert("RGBA")
    glow(im, (1050 * S, 100 * S), 190 * S, (255, 250, 225), 65)
    for cx, cy, sx, sy, a in [(190, 130, 260, 76, 235), (610, 85, 240, 58, 225),
                              (970, 235, 290, 76, 220), (330, 350, 260, 60, 185)]:
        cloud(im, cx * S, cy * S, sx * S, sy * S, (255, 255, 255), a)
    # Large, readable cloud shelf with layered highlights.
    for i in range(7):
        cx = (-120 + i * 250) * S
        cy = (475 + (i % 2) * 42) * S
        cloud(im, cx, cy, (280 + (i % 3) * 50) * S, (74 + (i % 2) * 12) * S, (255, 255, 255), 235)
    for i in range(5):
        cx = (-60 + i * 340) * S
        cloud(im, cx, 650 * S, 300 * S, 54 * S, (228, 243, 249), 190)
    island(im, 350 * S, 405 * S, 145 * S, (147, 199, 184), (145, 170, 185), True)
    island(im, 930 * S, 362 * S, 118 * S, (137, 190, 174), (139, 164, 179), False)
    balloon(im, 780 * S, 180 * S, 34 * S, (255, 218, 160))
    balloon(im, 548 * S, 205 * S, 21 * S, (255, 171, 150))
    d = ImageDraw.Draw(im)
    # Small, crisp birds.
    for x, y in [(190, 165), (250, 140), (1110, 195)]:
        d.arc((x * S, y * S, (x + 24) * S, (y + 12) * S), 200, 340, fill=(70, 91, 105, 170), width=2 * S)
    save(im, "clouds.png")


def dream():
    random.seed(55)
    # A pink, candy-coloured children's dream; deliberately separate from clouds.
    im = gradient((255, 177, 202), (255, 231, 202)).convert("RGBA")
    d = ImageDraw.Draw(im)
    # Pastel rainbow behind the scene.
    rainbow = [(255, 167, 188), (255, 198, 145), (255, 236, 159), (177, 225, 194),
               (166, 213, 242), (201, 174, 236), (244, 176, 220)]
    for i, color in enumerate(rainbow):
        r = (560 - i * 18) * S
        points = []
        for degree in range(200, 341, 2):
            angle = math.radians(degree)
            points.append((600 * S + math.cos(angle) * r, 760 * S + math.sin(angle) * r))
        d.line(points, fill=rgba(color, 140), width=18 * S, joint="curve")
    glow(im, (1030 * S, 115 * S), 155 * S, (255, 245, 210), 80)
    for cx, cy, sx, sy, a in [(200, 135, 235, 68, 190), (620, 95, 200, 55, 175),
                              (940, 265, 250, 65, 175), (350, 355, 215, 50, 130)]:
        cloud(im, cx * S, cy * S, sx * S, sy * S, (255, 252, 249), a)
    # Soft candy hills.
    hill(im, 610 * S, (244, 160, 184))
    hill(im, 680 * S, (178, 210, 177))
    hill(im, 735 * S, (151, 193, 188))
    # Children's dream fairground: carousel/tent, balloons, sparkles.
    ferris(im, 810 * S, 355 * S, 88 * S, (167, 103, 130))
    tent(im, 245 * S, 610 * S, 105 * S, 105 * S, (246, 132, 151), (255, 246, 221))
    tent(im, 375 * S, 635 * S, 74 * S, 72 * S, (145, 190, 225), (255, 250, 232))
    for x, y, r, c in [(585, 165, 15, (255, 155, 169)), (635, 140, 11, (255, 211, 117)),
                       (680, 185, 9, (163, 207, 234))]:
        balloon(im, x * S, y * S, r * S, c)
    for i in range(80):
        x, y = random.randint(0, W), random.randint(0, int(H * 0.72))
        r = random.choice([1, 1, 2, 3]) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 250, 205, random.randint(130, 230)))
    # Little candy bushes and flowers.
    for i in range(36):
        x, y = random.randint(0, W), random.randint(int(H * 0.86), H)
        r = random.randint(5, 13) * S
        candy = random.choice([(255, 185, 194), (255, 219, 164), (194, 226, 195)])
        d.ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), fill=rgba(candy, 190))
    save(im, "dream.png")



def vertical_style(im, top, bottom):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for y in range(H):
        t = y / (H - 1)
        d.line((0, y, W, y), fill=rgba(lerp(top, bottom, t), int(lerp((top[3], bottom[3]), (0, 0), 0)[0] if False else 255)))
    return layer


def apply_style(bg, base, style):
    im = base.convert("RGBA").resize((W, H), Image.LANCZOS)
    if style == "sky":
        im = ImageEnhance.Color(im).enhance(1.05)
        im = ImageEnhance.Brightness(im).enhance(1.02)
    elif style == "sunset":
        # Dusk is a colour event, not a yellow film: darken the daylight,
        # then replace the upper atmosphere with a vivid magenta-to-orange wash.
        im = ImageEnhance.Brightness(im).enhance(0.86)
        im = ImageEnhance.Color(im).enhance(1.12)
        dusk = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        dd = ImageDraw.Draw(dusk)
        top_color, bottom_color = SUNSET_SKY[bg]
        for y in range(H):
            ratio = y / (H - 1)
            color = lerp(top_color, bottom_color, pow(ratio, 0.75))
            alpha = int(142 * (1.0 - ratio) + 42 * ratio)
            dd.line((0, y, W, y), fill=rgba(color, alpha))
        im.alpha_composite(dusk.filter(ImageFilter.GaussianBlur(16 * S)))
        im = ImageEnhance.Contrast(im).enhance(1.04)
        glow(im, (970 * S, 470 * S), 300 * S, (255, 175, 105), 55)
        glow(im, (970 * S, 470 * S), 120 * S, (255, 235, 185), 85)
        # Low warm haze across the horizon only.
        haze = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        hd = ImageDraw.Draw(haze)
        for i in range(7):
            y = int(H * (0.58 + i * 0.035))
            hd.rectangle((0, y, W, y + 18 * S), fill=(255, 183, 120, 16))
        im.alpha_composite(haze.filter(ImageFilter.GaussianBlur(12 * S)))
    elif style == "night":
        im = ImageEnhance.Brightness(im).enhance(0.56)
        im = ImageEnhance.Color(im).enhance(0.82)
        night = Image.new("RGBA", (W, H), rgba(STYLE_GRADES[bg]["night"], 255))
        im = Image.blend(im, night, 0.25)
        d = ImageDraw.Draw(im)
        for i in range(100):
            x, y = random.randint(0, W), random.randint(0, 470 * S)
            r = random.choice([1, 1, 2]) * S
            d.ellipse((x - r, y - r, x + r, y + r), fill=rgba((255, 244, 197), random.randint(105, 225)))
        d.ellipse((965 * S, 70 * S, 1065 * S, 170 * S), fill=rgba((248, 239, 214), 230))
        for i in range(12):
            x, y = random.randint(70 * S, 1210 * S), random.randint(500 * S, 690 * S)
            r = random.randint(2, 4) * S
            d.ellipse((x - r, y - r, x + r, y + r), fill=rgba((255, 207, 124), 200))
    else:
        gray = im.convert("L").convert("RGB")
        gray = ImageEnhance.Brightness(gray).enhance(1.05)
        gray = ImageEnhance.Contrast(gray).enhance(0.92)
        im = gray.convert("RGBA")
        haze = Image.new("RGBA", (W, H), rgba(STYLE_GRADES[bg]["gray"], 255))
        im = Image.blend(im, haze, 0.16)
        fog = Image.new("RGBA", (W, H), (220, 228, 234, 32))
        im.alpha_composite(fog)
    return im.convert("RGB").resize((1280, 720), Image.LANCZOS)


def main():
    paradise()
    forest()
    snow()
    clouds()
    dream()
    for bg in BG_PALETTES:
        base = Image.open(OUT / f"{bg}.png")
        for style in STYLES:
            apply_style(bg, base, style).save(OUT / f"{bg}_{style}.png", optimize=True)
    print(f"Generated {len(BG_PALETTES)} backgrounds in {OUT}")


if __name__ == "__main__":
    main()

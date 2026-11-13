"""Generate visible placeholder PNG textures used by scenes.

The game still has procedural drawing fallbacks. These PNGs make the scenes
editable without running the game (and can be replaced by final art later).

Run:
  python tools/generate_placeholder_art.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "assets" / "visuals"
OUTS = {
    "generated": BASE / "generated",
    "carts": BASE / "carts",
    "obstacles": BASE / "obstacles",
    "passengers": BASE / "passengers",
}
for folder in OUTS.values():
    folder.mkdir(parents=True, exist_ok=True)

INK = (27, 50, 72, 255)
RED = (244, 98, 92, 255)
YELLOW = (255, 210, 63, 255)
WHITE = (255, 255, 255, 255)
SKY = (181, 226, 241, 255)
STEEL = (212, 225, 234, 255)
BROWN = (155, 96, 54, 255)


def canvas(size):
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def save(image, name, folder="generated"):
    image.save(OUTS[folder] / name)


def cart():
    image, d = canvas((128, 96))
    d.rounded_rectangle((14, 26, 114, 82), radius=14, fill=RED, outline=INK, width=5)
    d.rectangle((18, 22, 110, 32), fill=YELLOW, outline=INK, width=4)
    d.rectangle((24, 38, 104, 52), fill=(224, 245, 255, 255), outline=INK, width=3)
    for x in (34, 58, 82):
        d.rectangle((x, 39, x + 16, 51), fill=SKY, outline=INK, width=2)
    d.line((64, 20, 64, 5), fill=INK, width=4)
    d.polygon([(64, 5), (92, 11), (64, 18)], fill=YELLOW, outline=INK)
    save(image, "cart.png", "carts")


def passenger():
    image, d = canvas((96, 128))
    d.ellipse((14, 10, 82, 82), fill=(255, 230, 196, 255), outline=INK, width=4)
    d.chord((20, 12, 76, 58), 180, 360, fill=(74, 47, 34, 255), outline=INK, width=3)
    d.ellipse((31, 43, 41, 53), fill=INK)
    d.ellipse((55, 43, 65, 53), fill=INK)
    d.arc((38, 49, 58, 66), 10, 170, fill=INK, width=3)
    d.rounded_rectangle((28, 78, 68, 120), radius=10, fill=(53, 174, 213, 255), outline=INK, width=4)
    d.line((50, 78, 50, 116), fill=(220, 248, 255, 255), width=3)
    d.line((13, 52, 27, 65), fill=(230, 120, 119, 255), width=3)
    d.ellipse((4, 38, 24, 58), fill=RED, outline=INK, width=3)
    save(image, "passenger.png", "passengers")


def bird():
    image, d = canvas((96, 96))
    d.ellipse((16, 28, 80, 78), fill=WHITE, outline=INK, width=4)
    d.polygon([(76, 52), (94, 46), (80, 60)], fill=YELLOW, outline=INK)
    d.polygon([(28, 30), (14, 8), (46, 22)], fill=(93, 190, 222, 255), outline=INK)
    d.polygon([(48, 22), (62, 4), (70, 28)], fill=(93, 190, 222, 255), outline=INK)
    d.ellipse((62, 43, 70, 51), fill=INK)
    d.line((30, 66, 22, 82), fill=YELLOW, width=4)
    d.line((42, 66, 38, 84), fill=YELLOW, width=4)
    save(image, "bird.png", "obstacles")


def storm():
    image, d = canvas((96, 96))
    d.ellipse((14, 20, 56, 58), fill=(102, 63, 130, 255), outline=INK, width=4)
    d.ellipse((34, 12, 82, 54), fill=(126, 79, 156, 255), outline=INK, width=4)
    d.ellipse((22, 38, 74, 72), fill=(95, 55, 121, 255), outline=INK, width=4)
    d.polygon([(48, 40), (34, 68), (48, 68), (40, 92), (68, 58), (52, 58)], fill=YELLOW, outline=INK)
    save(image, "storm.png", "obstacles")


def barrier():
    image, d = canvas((96, 96))
    d.rectangle((12, 32, 84, 76), fill=YELLOW, outline=INK, width=4)
    for x in range(16, 84, 18):
        d.polygon([(x, 34), (x + 8, 34), (x + 20, 74), (x + 12, 74)], fill=INK)
    d.rectangle((20, 80, 28, 92), fill=(90, 98, 105, 255))
    d.rectangle((68, 80, 76, 92), fill=(90, 98, 105, 255))
    save(image, "barrier.png", "obstacles")


def crate():
    image, d = canvas((96, 96))
    d.rectangle((12, 18, 84, 84), fill=BROWN, outline=INK, width=4)
    d.line((16, 22, 80, 80), fill=(102, 63, 35, 255), width=5)
    d.line((80, 22, 16, 80), fill=(102, 63, 35, 255), width=5)
    d.rectangle((8, 12, 88, 24), fill=(181, 120, 70, 255), outline=INK, width=3)
    save(image, "crate.png", "obstacles")


def fan():
    image, d = canvas((96, 96))
    d.ellipse((16, 16, 80, 80), fill=(82, 183, 171, 255), outline=INK, width=4)
    for angle in (0, 120, 240):
        import math
        a = math.radians(angle)
        cx = 48 + math.cos(a) * 18
        cy = 48 + math.sin(a) * 18
        d.ellipse((cx - 15, cy - 15, cx + 15, cy + 15), fill=(217, 246, 236, 255), outline=INK, width=2)
    d.ellipse((40, 40, 56, 56), fill=YELLOW, outline=INK, width=3)
    save(image, "fan.png", "obstacles")


def rail():
    image, d = canvas((64, 32))
    d.rectangle((0, 8, 63, 24), fill=(68, 87, 103, 255))
    d.rectangle((0, 9, 63, 14), fill=STEEL)
    d.rectangle((0, 19, 63, 23), fill=(41, 55, 69, 255))
    for x in range(4, 64, 16):
        d.rectangle((x, 4, x + 4, 28), fill=(232, 222, 183, 255))
    save(image, "rail.png")


def start_gate():
    image, d = canvas((160, 120))
    d.rectangle((12, 92, 148, 108), fill=(238, 207, 151, 255), outline=INK, width=4)
    d.polygon([(20, 54), (44, 28), (116, 28), (140, 54)], fill=RED, outline=INK, width=4)
    d.rectangle((28, 54, 40, 100), fill=(126, 81, 50, 255), outline=INK, width=3)
    d.rectangle((120, 54, 132, 100), fill=(126, 81, 50, 255), outline=INK, width=3)
    d.rectangle((58, 58, 102, 88), fill=(255, 246, 218, 255), outline=INK, width=3)
    d.text((67, 64), "START", fill=INK)
    save(image, "start_gate.png")


def finish_gate():
    image, d = canvas((160, 160))
    d.rectangle((70, 20, 76, 150), fill=(90, 98, 105, 255), outline=INK, width=3)
    d.rectangle((30, 10, 124, 64), fill=WHITE, outline=INK, width=4)
    for row in range(3):
        for col in range(6):
            if (row + col) % 2 == 0:
                d.rectangle((34 + col * 15, 14 + row * 16, 48 + col * 15, 28 + row * 16), fill=INK)
    d.line((12, 100, 148, 100), fill=YELLOW, width=6)
    save(image, "finish_gate.png")


if __name__ == "__main__":
    cart()
    passenger()
    bird()
    storm()
    barrier()
    crate()
    fan()
    rail()
    start_gate()
    finish_gate()
    print(", ".join(f"{name}: {len(list(folder.glob('*.png')))}" for name, folder in OUTS.items()))

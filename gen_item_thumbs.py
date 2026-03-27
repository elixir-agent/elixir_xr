#!/usr/bin/env python3
from PIL import Image, ImageDraw
import math

BASE = "/home/piacere/claude/vrex_server/priv/static/thumbs"

# アイテム名 → (背景グラデーション上, 下, アイコン色)
ITEMS = {
    "altar":       ((80, 40, 80),  (40, 20, 60),  (220, 180, 255), "祭壇"),
    "box":         ((60, 80, 100), (30, 50, 70),  (200, 220, 240), "BOX"),
    "button":      ((200, 60, 60), (140, 30, 30), (255, 200, 200), "START"),
    "campfire":    ((180, 80, 20), (100, 40, 10), (255, 200, 80),  "🔥"),
    "console":     ((20, 60, 80),  (10, 30, 50),  (80, 220, 255),  "CTRL"),
    "deck":        ((60, 100, 140),(30, 60, 100), (200, 230, 255), "DECK"),
    "earth_window":((10, 30, 80),  (0, 10, 40),   (80, 160, 255),  "EARTH"),
    "engawa":      ((120, 80, 40), (80, 50, 20),  (240, 200, 140), "縁側"),
    "gate":        ((60, 80, 60),  (30, 50, 30),  (160, 220, 160), "GATE"),
    "goal":        ((200, 160, 20),(140, 100, 10),(255, 240, 80),  "GOAL"),
    "info_board":  ((40, 80, 120), (20, 50, 80),  (180, 220, 255), "INFO"),
    "lantern":     ((80, 60, 20),  (50, 35, 10),  (255, 200, 80),  "灯籠"),
    "log":         ((80, 60, 40),  (50, 35, 20),  (200, 160, 100), "LOG"),
    "mirror":      ((60, 40, 100), (30, 20, 70),  (200, 180, 255), "鏡"),
    "mural":       ((100, 60, 40), (70, 35, 20),  (220, 180, 120), "壁画"),
    "music":       ((40, 20, 80),  (20, 10, 50),  (180, 140, 255), "♪"),
    "orb":         ((20, 60, 100), (10, 30, 70),  (100, 200, 255), "ORB"),
    "palm":        ((40, 100, 40), (20, 70, 20),  (100, 220, 100), "🌴"),
    "sakura":      ((200, 150, 180),(160,100,150),(255, 200, 220), "🌸"),
    "scoreboard":  ((20, 40, 80),  (10, 20, 50),  (160, 200, 255), "SCORE"),
    "scroll":      ((100, 80, 40), (70, 50, 20),  (220, 200, 140), "巻物"),
    "snowman":     ((180, 210, 240),(140,180,220),(240, 250, 255), "⛄"),
    "spacesuit":   ((20, 40, 60),  (10, 20, 40),  (140, 200, 240), "宇宙服"),
    "stone":       ((60, 50, 40),  (40, 30, 20),  (180, 170, 150), "石碑"),
    "target":      ((160, 40, 40), (100, 20, 20), (255, 160, 160), "的"),
    "throne":      ((80, 50, 20),  (50, 30, 10),  (220, 180, 80),  "王座"),
    "weapons":     ((60, 40, 20),  (40, 25, 10),  (200, 160, 80),  "⚔"),
    "well":        ((40, 60, 80),  (20, 40, 60),  (160, 200, 220), "井戸"),
}

W, H = 256, 256

def gradient_image(top, bot):
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        t = y / H
        r = int(top[0]*(1-t) + bot[0]*t)
        g = int(top[1]*(1-t) + bot[1]*t)
        b = int(top[2]*(1-t) + bot[2]*t)
        for x in range(W):
            px[x, y] = (r, g, b)
    return img

for fname, (top, bot, icon_color, label) in ITEMS.items():
    img = gradient_image(top, bot)
    draw = ImageDraw.Draw(img)

    # 円形アイコン背景
    cx, cy, r = W//2, H//2 - 10, 70
    draw.ellipse([(cx-r, cy-r), (cx+r, cy+r)], fill=(*icon_color, 100))
    draw.ellipse([(cx-r+3, cy-r+3), (cx+r-3, cy+r-3)], outline=(255,255,255), width=2)

    # ラベルテキスト
    draw.text((cx - len(label)*6, cy - 8), label, fill=(255, 255, 255))
    draw.text((W//2 - len(fname)*4, H - 30), fname, fill=(*icon_color,))

    path = f"{BASE}/{fname}.jpg"
    img.save(path, "JPEG", quality=85)
    print(f"  thumbs/{fname}.jpg")

print("Done!")

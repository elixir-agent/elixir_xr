#!/usr/bin/env python3
"""Generate placeholder media files for vrex_server."""

import struct, os
from PIL import Image, ImageDraw, ImageFont

BASE = "/home/piacere/claude/vrex_server/priv/static"

# ── 色定義 (skybox / loading 共通) ──────────────────────────────────────
THEMES = {
    "lobby":         {"sky": [(100,140,200),(50,80,150)],  "ground": (80,100,60)},
    "garden":        {"sky": [(180,210,240),(120,170,210)], "ground": (60,120,60)},
    "arena":         {"sky": [(20,20,40),(10,10,30)],       "ground": (60,40,20)},
    "space":         {"sky": [(5,5,20),(0,0,10)],           "ground": (20,20,40)},
    "ocean":         {"sky": [(10,30,80),(0,15,50)],        "ground": (0,60,100)},
    "ninja":         {"sky": [(60,80,60),(30,50,30)],       "ground": (40,60,40)},
    "oasis":         {"sky": [(200,160,80),(220,180,100)],  "ground": (210,190,120)},
    "snowpeak":      {"sky": [(200,220,240),(230,240,255)], "ground": (240,245,255)},
    "castle":        {"sky": [(80,60,120),(50,40,90)],      "ground": (100,80,60)},
    "cherry_blossom":{"sky": [(230,180,200),(200,150,180)],"ground": (180,230,160)},
    "starfield_360": {"sky": [(5,5,20),(0,0,10)],           "ground": (10,10,30)},
    "arena_night":   {"sky": [(15,15,30),(10,10,20)],       "ground": (50,30,10)},
    "deep_ocean":    {"sky": [(0,20,60),(0,10,40)],         "ground": (0,40,80)},
    "misty_mountains":{"sky":[(100,120,110),(70,90,80)],   "ground": (60,80,60)},
    "desert_stars":  {"sky": [(10,10,30),(5,5,20)],         "ground": (180,150,80)},
    "mountain_top":  {"sky": [(150,180,220),(180,210,240)], "ground": (230,235,245)},
    "fantasy_sky":   {"sky": [(80,40,120),(120,60,160)],    "ground": (60,100,60)},
}

def gradient_image(w, h, top_color, bot_color):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / h
        r = int(top_color[0] * (1-t) + bot_color[0] * t)
        g = int(top_color[1] * (1-t) + bot_color[1] * t)
        b = int(top_color[2] * (1-t) + bot_color[2] * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return img

def add_stars(img, count=200):
    px = img.load()
    w, h = img.size
    import random; random.seed(42)
    for _ in range(count):
        x, y = random.randint(0, w-1), random.randint(0, h//2)
        br = random.randint(180, 255)
        px[x, y] = (br, br, br)

def make_skybox(name, theme_key, w=2048, h=1024):
    theme = THEMES.get(theme_key, THEMES["lobby"])
    top, bot = theme["sky"][0], theme["sky"][1]
    img = gradient_image(w, h, top, bot)
    # 星空系は星を追加
    if theme["sky"][0][2] > theme["sky"][0][0]:  # 青/暗系
        add_stars(img, 400)
    draw = ImageDraw.Draw(img)
    draw.text((20, 20), f"SKYBOX: {name}", fill=(255,255,255,180))
    path = f"{BASE}/sky/{name}.jpg"
    img.save(path, "JPEG", quality=85)
    print(f"  sky/{name}.jpg")

def make_loading(name, theme_key, w=1280, h=720):
    theme = THEMES.get(theme_key, THEMES["lobby"])
    top, bot = theme["sky"][0], theme["ground"]
    img = gradient_image(w, h, top, bot)
    draw = ImageDraw.Draw(img)
    # 中央にワールド名
    draw.rectangle([(w//2-200, h//2-40), (w//2+200, h//2+40)], fill=(0,0,0,120))
    draw.text((w//2-180, h//2-20), f"Loading: {name}", fill=(255,255,255))
    path = f"{BASE}/loading/{name}.jpg"
    img.save(path, "JPEG", quality=85)
    print(f"  loading/{name}.jpg")

def make_thumbnail(name, theme_key, w=512, h=512):
    theme = THEMES.get(theme_key, THEMES["lobby"])
    top, bot = theme["sky"][0], theme["ground"]
    img = gradient_image(w, h, top, bot)
    draw = ImageDraw.Draw(img)
    draw.text((10, 10), name, fill=(255,255,255))
    path = f"{BASE}/thumbs/{name}.jpg"
    img.save(path, "JPEG", quality=85)
    print(f"  thumbs/{name}.jpg")

# ── 最小限の有効なMP3フレーム (無音) ────────────────────────────────────
# MPEG1 Layer3 128kbps 44100Hz Stereo
# フレームサイズ = 144 * 128000 / 44100 = 417 bytes
def make_silent_mp3(path, duration_frames=100):
    """Generate a minimal valid silent MP3 file."""
    # MP3フレームヘッダ: MPEG1, Layer3, 128kbps, 44100Hz, Stereo, no padding
    header = bytes([0xFF, 0xFB, 0x90, 0x00])
    frame_size = 417  # bytes per frame at 128kbps 44100Hz
    frame_data = header + bytes(frame_size - 4)  # silence (zeros)
    with open(path, 'wb') as f:
        # ID3v2タグ (最小限)
        f.write(b'ID3\x03\x00\x00\x00\x00\x00\x00')
        for _ in range(duration_frames):
            f.write(frame_data)
    print(f"  {os.path.relpath(path, BASE)}")

# ════════════════════════════════════════════════════════════════════════
print("=== Skybox images ===")
skyboxes = {
    "lobby_sky":        "lobby",
    "cherry_blossom":   "cherry_blossom",
    "arena_night":      "arena_night",
    "starfield_360":    "starfield_360",
    "deep_ocean":       "deep_ocean",
    "misty_mountains":  "misty_mountains",
    "desert_stars":     "desert_stars",
    "mountain_top":     "mountain_top",
    "fantasy_sky":      "fantasy_sky",
}
for name, theme in skyboxes.items():
    make_skybox(name, theme)

print("\n=== Loading images ===")
loadings = {
    "lobby":    "lobby",
    "garden":   "garden",
    "arena":    "arena",
    "space":    "space",
    "ocean":    "ocean",
    "ninja":    "ninja",
    "oasis":    "oasis",
    "snowpeak": "snowpeak",
    "castle":   "castle",
}
for name, theme in loadings.items():
    make_loading(name, theme)

print("\n=== Thumbnail images ===")
thumbs = {
    "lobby":   "lobby",
    "garden":  "garden",
    "arena":   "arena",
    "space":   "space",
    "ocean":   "ocean",
    "ninja":   "ninja",
    "oasis":   "oasis",
    "snowpeak":"snowpeak",
    "castle":  "castle",
}
for name, theme in thumbs.items():
    make_thumbnail(name, theme)

print("\n=== BGM (MP3) ===")
bgms = [
    "lobby_bgm", "zen_koto", "arena_battle", "space_ambient",
    "underwater_mystery", "ninja_drums", "desert_wind",
    "mountain_breeze", "fantasy_epic",
]
for name in bgms:
    make_silent_mp3(f"{BASE}/music/{name}.mp3", duration_frames=150)

print("\n=== Ambient (MP3) ===")
ambients = [
    "crowd", "birds_water", "crowd_cheer", "space_hum",
    "ocean_bubbles", "forest_night", "crickets", "wind_howl",
    "castle_ambience",
]
for name in ambients:
    make_silent_mp3(f"{BASE}/ambient/{name}.mp3", duration_frames=150)

print("\nDone!")

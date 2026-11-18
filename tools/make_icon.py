"""Draws the File Browser icon and writes FileBrowser.ico (16-256 px).

Design: a yellow folder with a white page in front of it; the page has a
blue band with "M" and a down arrow (the Markdown mark) and text lines.
Small sizes (16/24/32) leave out the lettering so they stay crisp.

Run:  python tools/make_icon.py
"""
import os
import struct
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_ICO = os.path.join(HERE, "..", "FileBrowser.ico")
OUT_PNG = os.path.join(HERE, "FileBrowser-256.png")

FOLDER_BACK = (224, 160, 32, 255)
FOLDER_FRONT = (250, 199, 72, 255)
FOLDER_EDGE = (190, 128, 20, 255)
PAGE = (255, 255, 255, 255)
PAGE_EDGE = (120, 130, 145, 255)
BAND = (32, 110, 210, 255)
LINE = (170, 180, 195, 255)
WHITE = (255, 255, 255, 255)

FONT_PATHS = [r"C:\Windows\Fonts\segoeuib.ttf", r"C:\Windows\Fonts\arialbd.ttf"]


def font(size):
    for p in FONT_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def draw(size, detailed):
    """Draw at 4x and scale down for smooth edges."""
    S = size * 4
    u = S / 64.0  # design grid: 64 units
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def r(x1, y1, x2, y2):
        return [x1 * u, y1 * u, x2 * u, y2 * u]

    edge = max(1, round(1.4 * u))
    # folder back with its tab
    d.rounded_rectangle(r(3, 10, 27, 20), radius=3 * u, fill=FOLDER_BACK, outline=FOLDER_EDGE, width=edge)
    d.rounded_rectangle(r(3, 15, 61, 57), radius=4 * u, fill=FOLDER_BACK, outline=FOLDER_EDGE, width=edge)

    # the page, tucked into the folder
    px1, py1, px2 = 12, 3, 52
    d.rounded_rectangle(r(px1, py1, px2, 50), radius=3 * u, fill=PAGE, outline=PAGE_EDGE, width=edge)
    band_bottom = 22
    d.rounded_rectangle(r(px1, py1, px2, band_bottom), radius=3 * u, fill=BAND)
    d.rectangle(r(px1, band_bottom - 4, px2, band_bottom), fill=BAND)
    if detailed:
        # "M" and a down arrow: the Markdown mark
        f = font(int(15 * u))
        d.text((17 * u, 12.8 * u), "M", font=f, fill=WHITE, anchor="lm")
        ax = 43
        d.rectangle(r(ax - 1.7, 6.5, ax + 1.7, 13.5), fill=WHITE)
        d.polygon([(ax - 6) * u, 12.5 * u, (ax + 6) * u, 12.5 * u, ax * u, 19.5 * u], fill=WHITE)
    # one text line just above the folder front
    d.rounded_rectangle(r(17, 25.5, 47, 28.5), radius=1.5 * u, fill=LINE)

    # folder front, slightly lighter, covering the lower part of the page
    d.rounded_rectangle(r(3, 31, 61, 59), radius=4 * u, fill=FOLDER_FRONT, outline=FOLDER_EDGE, width=edge)

    return img.resize((size, size), Image.LANCZOS)


def bmp_frame(img):
    """One icon frame as a 32-bit BMP (BITMAPINFOHEADER + BGRA + AND mask).

    Lazarus reads icon frames as bitmaps only; a PNG-compressed frame (what
    Pillow writes) makes the app fail at startup with "Bitmap with unknown
    compression"."""
    w, h = img.size
    px = img.load()
    header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    xor = bytearray()
    for y in range(h - 1, -1, -1):          # bottom-up rows
        for x in range(w):
            r_, g, b, a = px[x, y]
            xor += bytes((b, g, r_, a))
    row_bytes = ((w + 31) // 32) * 4        # 1 bpp, padded to 32 bits
    mask = bytearray()
    for y in range(h - 1, -1, -1):
        row = bytearray(row_bytes)
        for x in range(w):
            if px[x, y][3] == 0:            # fully transparent
                row[x // 8] |= 0x80 >> (x % 8)
        mask += row
    return header + bytes(xor) + bytes(mask)


def write_ico(path, images):
    frames = [bmp_frame(im) for im in images]
    out = struct.pack("<HHH", 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    for im, data in zip(images, frames):
        w, h = im.size
        out += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    with open(path, "wb") as f:
        f.write(out + b"".join(frames))


def main():
    sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
    images = [draw(s, detailed=s >= 40).convert("RGBA") for s in sizes]
    images[-1].save(OUT_PNG)
    write_ico(OUT_ICO, images)
    print("wrote", os.path.normpath(OUT_ICO))


if __name__ == "__main__":
    main()

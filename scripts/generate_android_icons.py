from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path("/Users/maxiao/Desktop/demo/douyinDownLoad/DouyinDownLoad")
RN_RES = ROOT / "react-native/android/app/src/main/res"
FLUTTER_RES = ROOT / "flutter/android/app/src/main/res"
SOURCE_DIR = ROOT / "scripts/generated_icons"

SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def diagonal_gradient(
    size: int,
    start: tuple[int, int, int],
    end: tuple[int, int, int],
) -> Image.Image:
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / max((size - 1) * 2, 1)
            color = tuple(int(start[i] * (1 - t) + end[i] * t) for i in range(3)) + (255,)
            px[x, y] = color
    return img


def rounded_rect_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def build_square_icon(size: int = 1024) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    radius = int(size * 0.18)
    border = max(4, size // 170)

    base_grad = diagonal_gradient(size, (116, 239, 228), (93, 188, 238))
    base_mask = rounded_rect_mask(size, radius)
    canvas.paste(base_grad, (0, 0), base_mask)

    draw = ImageDraw.Draw(canvas)
    top_h = int(size * 0.34)
    seam_y = top_h - border // 2

    top_mask = Image.new("L", (size, size), 0)
    top_draw = ImageDraw.Draw(top_mask)
    top_draw.rounded_rectangle((0, 0, size - 1, top_h + radius), radius=radius, fill=255)
    top_draw.rectangle((0, top_h, size - 1, size - 1), fill=0)

    top_layer = diagonal_gradient(size, (255, 255, 255), (204, 204, 204))
    stripe_draw = ImageDraw.Draw(top_layer)
    stripe_w = int(size * 0.17)
    skew = int(size * 0.08)
    for i in range(-1, 7):
        x0 = int(size * 0.18) + i * stripe_w
        poly = [
            (x0, 0),
            (x0 + stripe_w, 0),
            (x0 + stripe_w - skew, top_h),
            (x0 - skew, top_h),
        ]
        fill = (18, 18, 18, 255) if i % 2 == 0 else (250, 250, 250, 255)
        stripe_draw.polygon(poly, fill=fill)

    hinge = [
        (0, 0),
        (int(size * 0.18), 0),
        (int(size * 0.30), top_h * 0.48),
        (int(size * 0.18), top_h),
        (0, top_h),
    ]
    stripe_draw.polygon(hinge, fill=(18, 18, 18, 255))

    chevron_outer = [
        (int(size * 0.02), int(top_h * 0.18)),
        (int(size * 0.16), int(top_h * 0.18)),
        (int(size * 0.23), int(top_h * 0.48)),
        (int(size * 0.16), int(top_h * 0.80)),
        (int(size * 0.02), int(top_h * 0.80)),
        (int(size * 0.09), int(top_h * 0.48)),
    ]
    chevron_inner = [
        (int(size * 0.10), int(top_h * 0.18)),
        (int(size * 0.24), int(top_h * 0.18)),
        (int(size * 0.31), int(top_h * 0.48)),
        (int(size * 0.24), int(top_h * 0.80)),
        (int(size * 0.10), int(top_h * 0.80)),
        (int(size * 0.17), int(top_h * 0.48)),
    ]
    stripe_draw.polygon(chevron_outer, fill=(255, 255, 255, 255))
    stripe_draw.polygon(chevron_inner, fill=(18, 18, 18, 255))

    canvas.alpha_composite(Image.composite(top_layer, Image.new("RGBA", (size, size), (0, 0, 0, 0)), top_mask))

    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, outline=(0, 0, 0, 255), width=border)
    draw.line((0, seam_y, size, seam_y), fill=(0, 0, 0, 255), width=border)

    highlight = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.rounded_rectangle(
        (border * 2, border * 2, size - border * 2, int(size * 0.22)),
        radius=max(radius - border * 2, 1),
        fill=(255, 255, 255, 40),
    )
    highlight_draw.rounded_rectangle(
        (border * 2, top_h + border * 2, size - border * 2, size - border * 2),
        radius=max(radius - border * 2, 1),
        outline=(255, 255, 255, 38),
        width=max(2, border // 2),
    )
    canvas.alpha_composite(highlight)

    return canvas


def build_round_icon(square_icon: Image.Image) -> Image.Image:
    size = square_icon.size[0]
    padding = int(size * 0.07)
    icon = square_icon.resize((size - padding * 2, size - padding * 2), Image.Resampling.LANCZOS)
    circle = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    circle_mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(circle_mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    circle.paste(icon, (padding, padding), icon)
    alpha = ImageChops.multiply(circle.getchannel("A"), circle_mask)
    circle.putalpha(alpha)
    return circle


def write_icon_set(res_root: Path, square_icon: Image.Image, round_icon: Image.Image, include_round: bool) -> None:
    for density, px in SIZES.items():
        target_dir = res_root / density
        target_dir.mkdir(parents=True, exist_ok=True)
        square_icon.resize((px, px), Image.Resampling.LANCZOS).save(target_dir / "ic_launcher.png")
        if include_round:
            round_icon.resize((px, px), Image.Resampling.LANCZOS).save(target_dir / "ic_launcher_round.png")


def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    square = build_square_icon()
    round_icon = build_round_icon(square)
    square.save(SOURCE_DIR / "app_icon_square.png")
    round_icon.save(SOURCE_DIR / "app_icon_round.png")

    write_icon_set(RN_RES, square, round_icon, include_round=True)
    write_icon_set(FLUTTER_RES, square, round_icon, include_round=True)


if __name__ == "__main__":
    main()

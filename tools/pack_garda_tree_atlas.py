"""Authoring only (Python + Pillow + NumPy). Sources/commands: garda_forest/SOURCES.md.
Run 'base' before Blender build/bake; 'pack' after its front/side/top renders.
"""
import argparse
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'subagent-artifacts/garda-forest/tree-source'
ATLAS = ROOT / 'assets/environment/garda_forest/garda_broadleaf_atlas.png'


def padded(image, rectangles):
    """Bleed RGB into atlas gutters, then fill low-alpha canopy texels."""
    pixels = np.array(image)
    pixels[pixels[:, :, 3] < 128, :3] = 0
    rgb = Image.fromarray(pixels[:, :, :3])
    mask = Image.fromarray(np.where(pixels[:, :, 3] < 128, 255, 0).astype('uint8'))
    for _ in range(8):
        rgb = Image.composite(rgb.filter(ImageFilter.MaxFilter(3)), rgb, mask)
    pixels[:, :, :3] = np.array(rgb)
    for x, y, w, h in rectangles:
        tile = pixels[y:y+h, x:x+w]
        solid = tile[:, :, 3] > 224
        assert solid.any(), 'Empty foliage image'
        # Prevent black RGB from contaminating the distant alpha-tested mipmaps.
        tile[tile[:, :, 3] < 128, :3] = tile[solid, :3].mean(axis=0).astype('uint8')
    result = Image.fromarray(pixels)
    assert result.getchannel('A').tobytes() == image.getchannel('A').tobytes()
    return result


def build(phase, output, source=SOURCE):
    atlas = Image.new('RGBA', (2048, 2048))
    branch = Image.open(source / 'branchleaves.png').convert('RGBA')
    rgb = ImageEnhance.Color(ImageEnhance.Brightness(branch.convert('RGB')).enhance(2.05)).enhance(.65)
    rgb.putalpha(branch.getchannel('A'))
    atlas.paste(rgb.resize((1536, 394), Image.Resampling.LANCZOS), (0, 0))
    bark = Image.open(source / 'bark_brown_02_diff_1k.jpg').convert('RGBA')
    atlas.paste(bark.resize((256, 512), Image.Resampling.LANCZOS), (1792, 0))
    rectangles = [(0, 0, 1536, 394)]
    if phase == 'pack':
        for view, xy, size in [('front', (0, 512), 1024), ('side', (1024, 512), 1024), ('top', (0, 1536), 512)]:
            image = Image.open(source / (view + '.png')).convert('RGBA')
            atlas.paste(image.resize((size, size), Image.Resampling.LANCZOS), xy)
            rectangles.append((*xy, size, size))
    output.parent.mkdir(parents=True, exist_ok=True)
    padded(atlas, rectangles).save(output)
    print('GARDA ATLAS PASS', phase, output)


def pack_normals(output, source=SOURCE):
    atlas = Image.new('RGB', (2048, 2048), (128, 255, 128))
    for view, xy, size in [('front', (0, 512), 1024), ('side', (1024, 512), 1024), ('top', (0, 1536), 512)]:
        pixels = np.array(Image.open(source / (view + '_normal.png')).convert('RGBA'))
        # Blender Z-up -> glTF/Godot Y-up; this is object-space, not a tangent normal map.
        rgb = pixels[:, :, [0, 2, 1]].copy()
        rgb[:, :, 2] = 255 - rgb[:, :, 2]
        solid = pixels[:, :, 3] > 128
        rgb[~solid] = (128, 255, 128)
        atlas.paste(Image.fromarray(rgb).resize((size, size), Image.Resampling.LANCZOS), xy)
    atlas.save(output)
    print('GARDA NORMAL ATLAS PASS', output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['base', 'pack', 'check', 'normals'])
    parser.add_argument('--output', type=Path, default=ATLAS)
    parser.add_argument('--source', type=Path, default=SOURCE)
    args = parser.parse_args()
    if args.phase == 'normals':
        pack_normals(args.output if args.output != ATLAS else ATLAS.with_name('garda_broadleaf_normals.png'), args.source)
    elif args.phase == 'check':
        expected = Image.open(args.output).convert('RGBA')
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'atlas.png'
            build('base', path, args.source)
            base = Image.open(path).convert('RGBA')
            for box in [(0, 0, 1536, 394), (1792, 0, 2048, 512)]:
                assert base.crop(box).tobytes() == expected.crop(box).tobytes()
            build('pack', path, args.source)
            actual = Image.open(path).convert('RGBA')
            assert actual.size == expected.size and actual.tobytes() == expected.tobytes()
            pack_normals(path, args.source)
            expected_normals = Image.open(args.output.with_name('garda_broadleaf_normals.png')).convert('RGB')
            assert Image.open(path).tobytes() == expected_normals.tobytes()
        print('GARDA ATLAS REPRODUCTION PASS')
    else:
        build(args.phase, args.output, args.source)

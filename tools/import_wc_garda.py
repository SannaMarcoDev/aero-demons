"""Import Garda's existing WC Sync export without running WC or the editor bridge.
Requires the already-installed NumPy and Pillow. Never overwrites a destination.
Keeps the export's 4 m spacing in the archived data/manifest; garda_final.tscn
applies the 250 km horizontal extent via Terrain3D.vertex_spacing, without resampling.
For matching vertical proportions, use --height-scale 3.814697265625 and a new destination.
Usage: python tools/import_wc_garda.py --godot PATH_TO_GODOT
Check conversion only: python tools/import_wc_garda.py --check
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REGION = 1024


def pack_control(weights):
    """WC Bridge's stable top-two selection, vectorized; not a new distribution."""
    shape = weights.shape[:2]
    base = np.zeros(shape, dtype=np.uint32)
    overlay = base.copy()
    strongest = np.zeros(shape, dtype=np.uint16)
    second = strongest.copy()
    for index in range(weights.shape[2]):
        strength = weights[:, :, index].astype(np.uint16)
        first = strength > strongest
        other = ~first & (strength > second)
        overlay = np.where(first, base, np.where(other, index, overlay))
        second = np.where(first, strongest, np.where(other, strength, second))
        base = np.where(first, index, base)
        strongest = np.maximum(strongest, strength)
    blend = second.astype(np.uint32) * 255 // np.maximum(strongest + second, 1)
    return ((base << 27) | (overlay << 22) | (blend << 14)).astype('<u4')


def orient(array):
    # Same clockwise rotation as WC Bridge. WC tile Y increases bottom-to-top.
    return np.ascontiguousarray(np.rot90(array, -1))


def decode_heights(raw, low, high, height_scale=1.0):
    # Scale around sea level (Y=0), not around each tile's minimum.
    return ((low + raw.astype(np.float64) * ((high - low) / 65535.0))
            * height_scale).astype('<f4')


def check():
    cases = np.array([[[0, 0, 0], [255, 0, 0], [100, 100, 100],
                       [0, 10, 30], [3, 5, 4], [255, 255, 0]]], dtype=np.uint8)
    expected = [0, 0, (1 << 22) | (127 << 14),
                (2 << 27) | (1 << 22) | (63 << 14),
                (1 << 27) | (2 << 22) | (113 << 14),
                (1 << 22) | (127 << 14)]
    assert pack_control(cases).tolist() == [expected]
    assert orient(np.array([[1, 2], [3, 4]])).tolist() == [[3, 1], [4, 2]]
    raw = np.array([[0, 65535]], dtype='<u2')
    assert decode_heights(raw, 64, 128).tolist() == [[64.0, 128.0]]
    assert decode_heights(raw, -10, 100, 3.814697265625).tolist() == [
        [-38.14697265625, 381.4697265625]]
    print('WC CONVERSION CHECK PASS', flush=True)


def sha256(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--sync', type=Path,
                        default=Path.home() / 'Documents/World Creator/Sync')
    parser.add_argument('--destination', type=Path, default=ROOT / 'terrain/garda_final_wc')
    parser.add_argument('--height-scale', type=float, default=1.0,
                        help='Explicit vertical import scale around Y=0; original WC files stay untouched')
    args = parser.parse_args()
    if not np.isfinite(args.height_scale) or args.height_scale <= 0:
        parser.error('--height-scale must be finite and positive')
    check()
    if args.check:
        return
    if not args.godot or not args.godot.is_file():
        parser.error('--godot must point to the Godot executable')
    destination = args.destination.resolve()
    if destination.exists():
        parser.error('Destination exists; refusing to overwrite: ' + str(destination))
    xml = args.sync / 'bridge.xml'
    tree = ET.parse(xml)
    surface = tree.find('Surface').attrib
    textures = [node.attrib for node in tree.findall('.//TextureInfo')]
    # This deliberately handles this export, not arbitrary WC resampling/padding.
    assert tree.find('Project').get('Name') == 'lago di garda'
    assert int(surface['ResolutionX']) == int(surface['ResolutionY']) == 16384
    assert float(surface['Width']) == float(surface['Length']) == 65536
    assert int(surface['TileResolution']) == 4096
    assert int(surface['TilesX']) >= 4 and int(surface['TilesY']) >= 4
    assert len(textures) == 7 and all(not t.get('AlbedoFile') for t in textures)
    low, high = float(surface['MinHeight']), float(surface['MaxHeight'])
    assert np.isfinite([low, high]).all() and low < high
    tile_size = 4096
    files = [xml]
    for ty in range(4):
        for tx in range(4):
            files += [args.sync / f'heightmap_{tx}_{ty}.raw',
                      args.sync / f'colormap_{tx}_{ty}.png']
            files += [args.sync / f'splatmap_{s}_{tx}_{ty}.tga' for s in range(2)]
    assert all(f.is_file() for f in files), 'Incomplete WC Sync export'
    hashes = {f.name: sha256(f) for f in files}
    manifest = {'surface': surface, 'textures': textures, 'region_size': REGION,
                'vertex_spacing': 4.0, 'height_scale': args.height_scale,
                'destination': destination.as_posix(),
                'source_sha256': hashes, 'regions': [],
                'conversion': 'Native resolution; clockwise per WC tile; heights in meters '
                              'multiplied by height_scale around Y=0; '
                              'WC Bridge top-two splats; original RGBA colormap. '
                              'Neutral material tints because WC already baked them into colormap.'}
    with tempfile.TemporaryDirectory(prefix='wc-garda-') as temp:
        staging = Path(temp)
        for ty in range(4):
            for tx in range(4):
                raw_path = args.sync / f'heightmap_{tx}_{ty}.raw'
                assert raw_path.stat().st_size == tile_size * tile_size * 2
                raw = np.memmap(raw_path, mode='r', dtype='<u2', shape=(tile_size, tile_size))
                with Image.open(args.sync / f'colormap_{tx}_{ty}.png') as image:
                    assert image.size == (tile_size, tile_size) and image.mode == 'RGBA'
                    color = np.array(image)
                splats = []
                for s in range(2):
                    with Image.open(args.sync / f'splatmap_{s}_{tx}_{ty}.tga') as image:
                        assert image.size == (tile_size, tile_size) and image.mode == 'RGBA'
                        splats.append(np.array(image))
                for sy in range(0, tile_size, REGION):
                    for sx in range(0, tile_size, REGION):
                        crop = np.s_[sy:sy + REGION, sx:sx + REGION]
                        heights = orient(decode_heights(raw[crop], low, high, args.height_scale))
                        weights = np.concatenate([s[crop] for s in splats], axis=2)[:, :, :7]
                        control = orient(pack_control(weights))
                        colors = orient(color[crop])
                        rx = ty * 4 + (tile_size - sy - REGION) // REGION - 8
                        rz = tx * 4 + sx // REGION - 8
                        name = f'region_{rx}_{rz}.bin'
                        buffers = [a.tobytes() for a in (heights, control, colors)]
                        with (staging / name).open('xb') as out:
                            for data in buffers:
                                out.write(data)
                        manifest['regions'].append({
                            'file': name, 'location': [rx, rz],
                            'height_range': [float(heights.min()), float(heights.max())],
                            'map_sha256': [hashlib.sha256(data).hexdigest() for data in buffers]})
                del raw, color, splats
                print(f'Converted tile {tx},{ty} ({ty * 4 + tx + 1}/16)', flush=True)
        assert len({tuple(r['location']) for r in manifest['regions']}) == 256
        manifest_path = staging / 'manifest.json'
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        result = subprocess.run([
            str(args.godot.resolve()), '--headless', '--path', str(ROOT),
            '--script', 'res://tools/save_wc_regions.gd', '--quit-after', '2',
            '--log-file', str(staging / 'godot.log'), '--', str(manifest_path)],
            capture_output=True, text=True, timeout=900)
        print(result.stdout, end='')
        print(result.stderr, end='')
        assert result.returncode == 0 and 'WC REGION IMPORT PASS 256' in result.stdout, \
            'Godot import failed; partial destination retained, scene untouched'
        assert 'SCRIPT ERROR' not in result.stderr and 'ERROR:' not in result.stderr
        assert all(sha256(f) == hashes[f.name] for f in files), 'Source changed during import'
        (destination / 'import_manifest.json').write_text(
            json.dumps(manifest, indent=2), encoding='utf-8')
    print(f'WC IMPORT PASS: {destination}; 256 regions, source hashes unchanged', flush=True)


if __name__ == '__main__':
    main()

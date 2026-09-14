"""Import Utah's native WC export (EXR height + PNG colormap + 8-channel TGA splats)
into a new Terrain3D data directory, without running WC or the editor bridge.
Requires NumPy and Pillow. Never overwrites an existing destination.

The export is a single coherent 8192x8192 raster set covering the real WC
50000x50000 m terrain (the project's nominal 250 km geographic source is
distinct and not used here). True float32 meters, height_scale 1, spacing
50000/8192 = 6.103515625. All three raster types are rotated once 90 CW
(WC Bridge convention): source (x, y) -> world X=(8191-y-4096)*s,
Z=(x-4096)*s. Regions are 1024, locations -4..3 on both axes.

Usage: python tools/import_wc_utah_native.py --godot PATH_TO_GODOT
Check conversion only: python tools/import_wc_utah_native.py --check
Geographic placement: --geographic restores 250 km and the DEM datum using
WC's documented stamp range, without fitting or changing local WC geometry.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile

import numpy as np
from PIL import Image

from import_wc_utah import pack_control, orient, check as shared_check

ROOT = Path(__file__).resolve().parents[1]
REGION = 1024
SIZE = 8192
EXTENT = 50000.0
SPACING = EXTENT / SIZE
DEM_RANGE = (893.52, 3872.37)  # Source R16 normalization, utah_250km_info.txt.
STAMP_RANGE = (11.0, 3000.0)  # Verified against the archived WCR before conversion.
GEO_HEIGHT_SCALE = (DEM_RANGE[1] - DEM_RANGE[0]) / (STAMP_RANGE[1] - STAMP_RANGE[0])
GEO_HEIGHT_OFFSET = DEM_RANGE[0] - STAMP_RANGE[0] * GEO_HEIGHT_SCALE
EXPORT = Path(r'C:/Users/sanna/Documents/Codex/2026-09-14/new-chat/outputs/godot_validation_v1/native_export')
SPLATS = Path(r'C:/Users/sanna/Documents/Codex/2026-09-14/new-chat/outputs/splatmaps_8k')
LANDMARKS = Path(r'C:/Users/sanna/Documents/Codex/2026-09-14/new-chat/outputs/evidence/landmarks.json')
MASKS = EXPORT.parent.parent / 'masks'
MASK_NAMES = ['water', 'developed', 'wetlands', 'crops',
              'herbaceous_pasture', 'forest', 'shrub_scrub', 'bare_ground']
TEXTURE_NAMES = ['LC_water', 'LC_developed', 'LC_wetlands', 'LC_crops',
                 'LC_herbaceous_pasture', 'LC_forest', 'LC_shrub_scrub', 'LC_bare_ground']
# Detail textures already imported in the project, 2048 RGBA albedo+normal pairs.
# Water/developed/wetlands keep neutral baked maps: no appropriate detail and
# the landcover colormap carries their color at strength 1.
_T = 'res://textures/terrain/'
TEXTURE_FILES = {
    'LC_herbaceous_pasture': (_T + 'withered_grass_albedo_packed.png',
                              _T + 'withered_grass_normal_packed.png'),
    'LC_forest': (_T + 'rocks_ground_03_albedo_packed.png',
                  _T + 'rocks_ground_03_normal_packed.png'),
    'LC_shrub_scrub': (_T + 'withered_grass_albedo_packed.png',
                       _T + 'withered_grass_normal_packed.png'),
    'LC_bare_ground': (_T + 'sandy_gravel_02_albedo_packed.png',
                       _T + 'sandy_gravel_02_normal_packed.png'),
}
TEXTURE_TINTS = {'LC_shrub_scrub': (0.82, 0.76, 0.62, 1.0)}


def read_exr_r(path):
    """Minimal reader for a single-channel float32 scanline EXR.
    # ponytail: only this export's uncompressed R32 scanlines; use Godot's
    # native EXR loader if future exports use other channels or compression.
    Compressed files are rejected, never guessed at.
    """
    data = path.read_bytes()
    assert data[:4] == b'\x76\x2f\x31\x01', 'Not an EXR file'
    pos = 8
    channels = []
    compression = None
    height = width = None
    while True:
        end = data.index(b'\x00', pos)
        if end == pos:
            pos += 1
            break
        name = data[pos:end].decode(); pos = end + 1
        end = data.index(b'\x00', pos)
        atype = data[pos:end].decode(); pos = end + 1
        size = struct.unpack('<I', data[pos:pos + 4])[0]; pos += 4
        value = data[pos:pos + size]; pos += size
        if name == 'channels':
            cpos = 0
            while value[cpos] != 0:
                cend = value.index(b'\x00', cpos)
                cname = value[cpos:cend].decode()
                ptype = struct.unpack('<I', value[cend + 1:cend + 5])[0]
                channels.append((cname, ptype))
                cpos = cend + 17
        elif name == 'compression':
            compression = value[0]
        elif name == 'dataWindow':
            x0, y0, x1, y1 = struct.unpack('<4i', value)
            width, height = x1 - x0 + 1, y1 - y0 + 1
    assert channels == [('R', 2)], f'Expected single float32 R channel, got {channels}'
    assert compression == 0, f'Only uncompressed EXR supported, got compression={compression}'
    assert width == height == SIZE
    # Uncompressed scanlines: one 8-byte chunk offset per image row.
    offsets = struct.unpack(f'<{height}Q', data[pos:pos + height * 8])
    out = np.empty((height, width), dtype='<f4')
    for y in range(height):
        o = offsets[y]
        yc, psize = struct.unpack('<iI', data[o:o + 8])
        assert yc == y and psize == width * 4
        out[y] = np.frombuffer(data[o + 8:o + 8 + psize], dtype='<f4')
    return out


def sha256(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def read_splat(path):
    """TGA -> (SIZE, SIZE, 4) uint8 RGBA via Pillow.
    Pillow applies the TGA origin bit: these exports use descriptor 0x08
    (bottom-left origin), which a raw reader silently returns upside down."""
    with Image.open(path) as image:
        assert image.size == (SIZE, SIZE) and image.mode == 'RGBA'
        return np.asarray(image).copy()


def check():
    """Self-check: TGA origin handling and EXR compression rejection."""
    # Bottom-left origin TGA (descriptor 0x08, like the WC exports): the first
    # scanline in the file is the BOTTOM row, so a raw reader returns the image
    # upside down. Pillow (and Godot's TGA loader) present it top-row-first,
    # i.e. the vertical flip of the raw file order.
    pixels = bytes([255, 0, 0, 255] * 2 + [0, 0, 255, 255] * 2)  # BGRA
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, 2, 2, 32, 0x08)
    with tempfile.NamedTemporaryFile(suffix='.tga', delete=False) as tmp:
        tmp.write(header + pixels)
        tmp_path = Path(tmp.name)
    try:
        with Image.open(tmp_path) as image:
            arr = np.asarray(image).copy()
    finally:
        tmp_path.unlink()
    assert arr[0, 0].tolist() == [255, 0, 0, 255], 'bottom-left TGA not normalized'
    assert arr[1, 0].tolist() == [0, 0, 255, 255]
    # Top-left origin TGA (descriptor 0x28) must come back flipped relative to
    # the bottom-left file so both present the same visual orientation.
    header_tl = header[:-1] + b'\x28'
    with tempfile.NamedTemporaryFile(suffix='.tga', delete=False) as tmp:
        tmp.write(header_tl + pixels)
        tmp_path = Path(tmp.name)
    try:
        with Image.open(tmp_path) as image:
            arr = np.asarray(image).copy()
    finally:
        tmp_path.unlink()
    assert arr[0, 0].tolist() == [0, 0, 255, 255], 'top-left TGA not normalized'
    # A compressed EXR must be rejected, not silently mis-decoded.
    exr = bytearray(b'\x76\x2f\x31\x01\x02\x00\x00\x00')
    channel = b'R\x00' + struct.pack('<iB3xii', 2, 0, 1, 1) + b'\x00'
    exr += b'channels\x00chlist\x00' + struct.pack('<I', len(channel)) + channel
    exr += b'dataWindow\x00box2i\x00' + struct.pack('<I4i', 16, 0, 0, SIZE - 1, SIZE - 1)
    exr += b'compression\x00compression\x00' + struct.pack('<I', 1) + b'\x03'
    exr += b'\x00'
    with tempfile.NamedTemporaryFile(suffix='.exr', delete=False) as tmp:
        tmp.write(bytes(exr))
        tmp_path = Path(tmp.name)
    try:
        rejected = False
        try:
            read_exr_r(tmp_path)
        except AssertionError as error:
            rejected = 'compression=3' in str(error)
        assert rejected, 'compressed EXR not rejected'
    finally:
        tmp_path.unlink()
    # Datum restoration is the inverse of the stamp's normalization, not Y*5
    # and not a remap of the actual exported min/max (which would distort WC).
    restored = np.array(STAMP_RANGE) * GEO_HEIGHT_SCALE + GEO_HEIGHT_OFFSET
    assert np.allclose(restored, DEM_RANGE, atol=1e-9, rtol=0)
    assert 0.99 < GEO_HEIGHT_SCALE < 1.0 and 880 < GEO_HEIGHT_OFFSET < 885
    print('WC NATIVE CONVERSION CHECK PASS', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--godot', type=Path,
                        default=Path(r'C:\Users\sanna\Workspace\Godot\Godot_v4.7.1-stable_win64.exe'))
    parser.add_argument('--export', type=Path, default=EXPORT)
    parser.add_argument('--splats', type=Path, default=SPLATS)
    parser.add_argument('--geographic', action='store_true',
                        help='250 km horizontal extent; inverse WC stamp normalization to DEM datum')
    parser.add_argument('--destination', type=Path)
    args = parser.parse_args()
    shared_check()
    check()
    if args.check:
        return
    if not args.godot or not args.godot.is_file():
        parser.error('--godot must point to the Godot executable')
    destination = (args.destination or ROOT / 'terrain' / (
        'utah_landcover_250km' if args.geographic else 'utah_landcover_validation_v2')).resolve()
    extent = 250000.0 if args.geographic else EXTENT
    spacing = extent / SIZE
    height_scale = GEO_HEIGHT_SCALE if args.geographic else 1.0
    height_offset = GEO_HEIGHT_OFFSET if args.geographic else 0.0
    if destination.exists():
        parser.error('Destination exists; refusing to overwrite: ' + str(destination))

    exr_path = args.export / 'utah_height_m_8192.exr'
    png_path = args.export / 'utah_colormap_8192.png'
    native_manifest = json.loads((args.export / 'native_export_manifest.json').read_text())
    assert native_manifest['extent_m'] == [50000, 50000]
    assert native_manifest['resolution'] == [SIZE, SIZE]
    assert native_manifest['height']['use_true_height']
    assert not native_manifest['height']['normalize']
    assert native_manifest['height']['unit'] == 'meters'
    assert native_manifest['orientation']['tile_order'] == 'TopToBottom'
    assert all(not native_manifest['orientation'][key] for key in
               ('flip_x', 'flip_y', 'transpose', 'include_border_pixel'))
    files = [exr_path, png_path, args.splats / 'LC_splat_0_0_0.tga',
             args.splats / 'LC_splat_1_0_0.tga']
    if args.geographic:
        wcr = EXPORT.parent.parent / 'utah_landcover_v1.wcr'
        raw_path = ROOT / 'terrain/source/utah_250km/utah_250km_worldmachine.r16'
        info = ROOT / 'terrain/source/utah_250km/utah_250km_info.txt'
        project = json.loads(wcr.read_text(encoding='utf-8-sig'))
        layers = project['BiomeSettings']['TerrainLayers']['Items']
        assert len(layers) == 1 and layers[0]['$type'] == 'TerrainLayerStamp'
        stamp = layers[0]
        assert stamp['SetHeightRange'] and stamp['HeightRange'] == dict(zip(('Min', 'Max'), STAMP_RANGE))
        assert stamp['HeightScale'] == 1.0 and stamp['HeightOffset'] == 0.0
        assert Path(stamp['StampTexture'].split('<')[0]).resolve() == raw_path.resolve()
        assert stamp['Operation'] == 'Overwrite' and stamp['HeightBlending'] == 1.0
        assert '0=893.52 m, 65535=3872.37 m' in info.read_text(encoding='utf-8-sig')
        files += [wcr, raw_path, info]
    hashes = {f.name: sha256(f) for f in files}
    for name, recorded in native_manifest['sha256'].items():
        assert hashes[name] == recorded, f'Source {name} differs from native manifest'

    heights_src = read_exr_r(exr_path)
    assert np.isfinite(heights_src).all()
    hmin, hmax = float(heights_src.min()), float(heights_src.max())
    assert abs(hmin - native_manifest['height']['min_m']) < 0.01
    assert abs(hmax - native_manifest['height']['max_m']) < 0.01
    native_height_range = [hmin, hmax]
    calibration = None
    if args.geographic:
        raw = np.memmap(raw_path, mode='r', dtype='<u2', shape=(SIZE, SIZE))
        dem = DEM_RANGE[0] + raw[::16, ::16].astype(np.float64) * ((DEM_RANGE[1] - DEM_RANGE[0]) / 65535)
        residual = heights_src[::16, ::16].astype(np.float64) * height_scale + height_offset - dem
        calibration = {
            'method': 'inverse documented WC stamp normalization, not a fitted correction',
            'wc_stamp_range_m': STAMP_RANGE, 'r16_geographic_range_m': DEM_RANGE,
            'formula': 'Y = WC_EXR_R * height_scale + height_offset',
            'local_wc_shape_preserved': True, 'dem_replaced_geometry': False,
            'residual_sample_step_px': 16, 'residual_sample_count': int(residual.size),
            'residual_rmse_m': float(np.sqrt(np.mean(residual ** 2))),
            'residual_min_max_m': [float(residual.min()), float(residual.max())],
            'residual_abs_p99_m': float(np.percentile(np.abs(residual), 99)),
            'caveat': 'Geographic datum restored, not pixel-exact DEM geometry. '
                      'WC interpolation/processing remains; exact DEM fidelity needs a new WC export.'}
        del raw, dem, residual
    # Calculate in float64 then round once to the Terrain3D RF storage format.
    heights_world = (heights_src.astype(np.float64) * height_scale + height_offset).astype('<f4')
    hmin, hmax = float(heights_world.min()), float(heights_world.max())
    with Image.open(png_path) as image:
        assert image.size == (SIZE, SIZE) and image.mode == 'RGBA'
        colors_src = np.array(image)
    weights_src = np.concatenate([read_splat(args.splats / f'LC_splat_{s}_0_0.tga')
                                  for s in range(2)], axis=2)
    total = weights_src.astype(np.uint16).sum(axis=2)
    holes = int((total == 0).sum())
    top_two = np.sort(weights_src, axis=2)[:, :, -2:].astype(np.uint32)
    stats = {
        'weight_sum_range': [int(total.min()), int(total.max())],
        'holes': holes,
        'channel_nonzero': [int((weights_src[:, :, i] > 0).sum()) for i in range(8)],
        'top_two_weight_fraction': float((top_two.sum(axis=2) / np.maximum(total, 1)).mean()),
    }
    assert holes == 0, 'Export has holes'

    # Binary PNG masks are reference-only: report coverage agreement, never imported.
    mask_iou = {}
    if MASKS.is_dir():
        for i, name in enumerate(MASK_NAMES):
            mask_path = MASKS / f'{name}.png'
            if not mask_path.is_file():
                continue
            with Image.open(mask_path) as mask_image:
                mask = np.array(mask_image.convert('L')) > 0
            # Mask PNGs and Pillow-decoded splats are both north-up; no flip.
            exported = weights_src[:, :, i] >= 128
            union = (mask | exported).sum()
            mask_iou[name] = float((mask & exported).sum() / union) if union else 1.0
    # Orientation sanity: matches the handoff's verified IoU table (water 95.89%).
    if 'water' in mask_iou:
        assert mask_iou['water'] > 0.9, \
            f"Splat orientation regression: water IoU {mask_iou['water']:.4f}"

    mask_sources = {}
    if MASKS.is_dir():
        for name in MASK_NAMES:
            mask_path = MASKS / f'{name}.png'
            if mask_path.is_file():
                mask_sources[name] = {'path': str(mask_path),
                                      'sha256': sha256(mask_path)}
    landmarks = json.loads(LANDMARKS.read_text(encoding='utf-8-sig')) if LANDMARKS.is_file() else []
    manifest = {
        'producer': native_manifest['producer'],
        'geometry': ('WC geometry placed at geographic 250x250 km with the inverse '
                     'stamp normalization restoring the DEM datum; no local sculpting.' if args.geographic else
                     'Coherent WC 50000x50000 m export; nominal geographic 250x250 km not applied.'),
        'extent_m': [extent, extent], 'resolution': [SIZE, SIZE],
        'region_size': REGION, 'vertex_spacing': spacing,
        'height_scale': height_scale, 'height_offset': height_offset,
        'height_range_m': [hmin, hmax], 'native_height_range_m': native_height_range,
        'geographic_calibration': calibration,
        'transform': 'all raster types rotated once 90 CW; source (x,y) -> '
                     'world X=(8191-y-4096)*spacing, Z=(x-4096)*spacing',
        'inverse': 'x = Z/spacing + 4096, y = 8191 - (X/spacing + 4096)',
        'landmarks': [{'label': lm['label'], 'source_center': lm['center'],
                       'world_xz': [(SIZE - 1 - lm['center'][1] - SIZE // 2) * spacing,
                                    (lm['center'][0] - SIZE // 2) * spacing],
                       'source_height_m': float(heights_src[lm['center'][1], lm['center'][0]]),
                       'world_height_m': float(heights_world[lm['center'][1], lm['center'][0]])}
                      for lm in landmarks],
        'textures': [dict({'id': i, 'name': TEXTURE_NAMES[i], 'mask': MASK_NAMES[i],
                           'splat_file': f'LC_splat_{i // 4}_0_0.tga',
                           'channel': 'RGBA'[i % 4]},
                          **({'albedo': TEXTURE_FILES[TEXTURE_NAMES[i]][0],
                              'normal': TEXTURE_FILES[TEXTURE_NAMES[i]][1]}
                             if TEXTURE_NAMES[i] in TEXTURE_FILES else {}),
                          **({'albedo_color': TEXTURE_TINTS[TEXTURE_NAMES[i]]}
                             if TEXTURE_NAMES[i] in TEXTURE_TINTS else {}))
                     for i in range(8)],
        'geographic_source': {'crs': 'EPSG:32612',
                              'bounds_m': [410061.696, 4094204.958, 660061.696, 4344204.958],
                              'extent_m': [250000, 250000],
                              'world_scale_horizontal': extent / 250000.0},
        'decoding': 'Pillow normalizes TGA bottom-left origin to north-up rows; '
                    'this is file decoding, not a second authored transform. '
                    'EXR R32 uncompressed, PNG RGBA8, then one clockwise rotation for all maps.',
        'control_encoding': 'stable descending top-two, lower ID wins ties; '
                            'floor(255*w_second/(w_first+w_second)); '
                            '(base<<27)|(overlay<<22)|(blend<<14); all lower flags zero',
        'splat_stats': stats, 'mask_reference_iou': mask_iou,
        'destination': destination.as_posix(),
        'sources': {f.name: {'path': str(f), 'sha256': hashes[f.name]}
                    for f in files},
        'mask_sources': mask_sources,
        'source_sha256': hashes, 'regions': [],
        'no_resampling': True, 'auto_shader_flags': False,
        'conversion': 'Float32 meters after explicit height_scale and height_offset; '
                      'single 90 CW rotation; WC Bridge '
                      'top-two splat selection over all 8 channels; original '
                      'RGBA colormap; no resampling or authored distributions.'}

    heights = orient(heights_world)
    colors = orient(colors_src)
    control = orient(pack_control(weights_src))
    del heights_src, heights_world, colors_src, weights_src
    with tempfile.TemporaryDirectory(prefix='wc-utah-native-') as temp:
        staging = Path(temp)
        for ry in range(0, SIZE, REGION):
            for rx in range(0, SIZE, REGION):
                crop = np.s_[ry:ry + REGION, rx:rx + REGION]
                # rotated[i,j] = source[y=SIZE-1-j, x=i]; world X=(j-4096)*s,
                # Z=(i-4096)*s, so column block rx -> loc_x, row block ry -> loc_z.
                loc_x = rx // REGION - SIZE // REGION // 2
                loc_z = ry // REGION - SIZE // REGION // 2
                buffers = [a[crop].tobytes() for a in (heights, control, colors)]
                name = f'region_{loc_x}_{loc_z}.bin'
                with (staging / name).open('xb') as out:
                    for data in buffers:
                        out.write(data)
                h = heights[crop]
                manifest['regions'].append({
                    'file': name, 'location': [loc_x, loc_z],
                    'height_range': [float(h.min()), float(h.max())],
                    'map_sha256': [hashlib.sha256(data).hexdigest() for data in buffers]})
        assert len({tuple(r['location']) for r in manifest['regions']}) == 64
        assert all(-4 <= r['location'][0] <= 3 and -4 <= r['location'][1] <= 3
                   for r in manifest['regions'])
        manifest_path = staging / 'manifest.json'
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        result = subprocess.run([
            str(args.godot.resolve()), '--headless', '--path', str(ROOT),
            '--script', 'res://tools/save_wc_regions.gd', '--quit-after', '2',
            '--log-file', str(staging / 'godot.log'), '--', str(manifest_path)],
            capture_output=True, text=True, timeout=1800)
        print(result.stdout, end='')
        print(result.stderr, end='')
        assert result.returncode == 0 and 'WC REGION IMPORT PASS 64' in result.stdout, \
            'Godot import failed; partial destination retained, scene untouched'
        assert 'SCRIPT ERROR' not in result.stderr
        # Benign exit-time noise: Godot reports resources still in use while the
        # SceneTree script tears down after a successful import.
        noise = [line for line in result.stderr.splitlines()
                 if 'ERROR:' in line and 'resources still in use at exit' not in line]
        assert not noise, noise
        assert all(sha256(f) == hashes[f.name] for f in files), 'Source changed during import'
        (destination / 'import_manifest.json').write_text(
            json.dumps(manifest, indent=2), encoding='utf-8')
    print(f'WC NATIVE IMPORT PASS: {destination}; 64 regions, source hashes unchanged', flush=True)


if __name__ == '__main__':
    main()

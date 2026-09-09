"""Fetch CC0 PBR textures from Poly Haven and pack them into Terrain3D format.

For each texture:
- Downloads Diffuse, nor_gl, Rough, Displacement maps at 2K.
- Packs Albedo: RGB from Diffuse, A from Displacement (Height).
- Packs Normal: RGB from nor_gl (OpenGL tangent space), A from Roughness.
- Writes Godot .import files with mipmaps enabled and normal_map=0 (preserving alpha).
"""

import io
from pathlib import Path
import sys
import time
import requests
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST_DIR = ROOT / "textures" / "terrain"

TEXTURE_CONFIG = [
    {
        "slot": 0,
        "name": "Mountain Side",
        "asset_id": "cliff_side",
        "file_prefix": "cliff_side",
        "uv_scale": 0.4,
    },
    {
        "slot": 1,
        "name": "Gradient",
        "asset_id": "rocky_terrain_02",
        "file_prefix": "rocky_terrain_02",
        "uv_scale": 0.4,
    },
    {
        "slot": 2,
        "name": "Vegetation 01",
        "asset_id": "leafy_grass",
        "file_prefix": "leafy_grass",
        "uv_scale": 0.4,
    },
    {
        "slot": 3,
        "name": "Vegetation 02",
        "asset_id": "withered_grass",
        "file_prefix": "withered_grass",
        "uv_scale": 0.4,
    },
    {
        "slot": 4,
        "name": "Snow",
        "asset_id": "snow_02",
        "file_prefix": "snow_02",
        "uv_scale": 0.4,
    },
    {
        "slot": 5,
        "name": "Flow",
        "asset_id": "dry_river_pebbles",
        "file_prefix": "dry_river_pebbles",
        "uv_scale": 0.4,
    },
    {
        "slot": 6,
        "name": "Debris",
        "asset_id": "rocks_ground_03",
        "file_prefix": "rocks_ground_03",
        "uv_scale": 0.2,
    },
]

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{source_path}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def download_map(files_info: dict, map_key: str, resolution: str = "2k") -> Image.Image:
    """Find map url and download as PIL Image."""
    map_data = files_info.get(map_key, {}).get(resolution, {})
    if not map_data:
        # Fallback to 1k if 2k missing
        map_data = files_info.get(map_key, {}).get("1k", {})
        if not map_data:
            raise RuntimeError(f"Map {map_key} not available in {resolution} or 1k")

    fmt = "jpg" if "jpg" in map_data else list(map_data.keys())[0]
    url = map_data[fmt]["url"]

    for attempt in range(3):
        try:
            resp = requests.get(url, timeout=30)
            resp.raise_for_status()
            img = Image.open(io.BytesIO(resp.content))
            return img.convert("RGB")
        except Exception as e:
            if attempt == 2:
                raise
            time.sleep(2)


def main():
    DEST_DIR.mkdir(parents=True, exist_ok=True)
    target_size = (2048, 2048)

    print(f"Target directory: {DEST_DIR}")
    print(f"Starting fetch and pack for {len(TEXTURE_CONFIG)} terrain textures at {target_size[0]}x{target_size[1]}...")

    for config in TEXTURE_CONFIG:
        slot = config["slot"]
        name = config["name"]
        asset_id = config["asset_id"]
        prefix = config["file_prefix"]

        print(f"\n--- Processing Slot {slot}: {name} ({asset_id}) ---")
        api_url = f"https://api.polyhaven.com/files/{asset_id}"
        files_info = requests.get(api_url, timeout=20).json()

        albedo_path = DEST_DIR / f"{prefix}_albedo_packed.png"
        normal_path = DEST_DIR / f"{prefix}_normal_packed.png"

        # 1. Albedo + Displacement
        print(f"  Downloading Diffuse & Displacement...")
        diff_img = download_map(files_info, "Diffuse", "2k")
        disp_img = download_map(files_info, "Displacement", "2k")

        if diff_img.size != target_size:
            diff_img = diff_img.resize(target_size, Image.Resampling.LANCZOS)
        if disp_img.size != target_size:
            disp_img = disp_img.resize(target_size, Image.Resampling.LANCZOS)

        disp_gray = disp_img.convert("L")
        r, g, b = diff_img.split()
        albedo_packed = Image.merge("RGBA", (r, g, b, disp_gray))
        albedo_packed.save(albedo_path, "PNG", optimize=True)
        print(f"  Saved {albedo_path.name} ({albedo_path.stat().st_size // 1024} KB)")

        # 2. Normal + Roughness
        print(f"  Downloading nor_gl & Roughness...")
        nor_img = download_map(files_info, "nor_gl", "2k")
        rough_img = download_map(files_info, "Rough", "2k")

        if nor_img.size != target_size:
            nor_img = nor_img.resize(target_size, Image.Resampling.LANCZOS)
        if rough_img.size != target_size:
            rough_img = rough_img.resize(target_size, Image.Resampling.LANCZOS)

        rough_gray = rough_img.convert("L")
        nr, ng, nb = nor_img.split()
        normal_packed = Image.merge("RGBA", (nr, ng, nb, rough_gray))
        normal_packed.save(normal_path, "PNG", optimize=True)
        print(f"  Saved {normal_path.name} ({normal_path.stat().st_size // 1024} KB)")

        # 3. Create .import files
        for p in [albedo_path, normal_path]:
            import_file = Path(str(p) + ".import")
            res_path = f"res://textures/terrain/{p.name}"
            import_file.write_text(IMPORT_TEMPLATE.format(source_path=res_path), encoding="utf-8")

    print("\nAll textures downloaded and packed successfully!")


if __name__ == "__main__":
    main()

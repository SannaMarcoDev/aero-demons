#!/usr/bin/env python3
"""
Pack 2K PBR textures for Terrain3D.
Sources: ambientCG (CC0 1.0 Universal)
Slots:
  0: Rock030 (Cliff / Granite Rock)
  1: Ground037 (Alpine Meadow Grass)
  2: Ground110 (Mountain Scree / Talus)
  3: Ground048 (Forest Floor / Soil)
  4: Snow006 (Alpine Snow / Firn)

Generates:
  <id>_alb_ht.png  (RGB = Albedo, A = Displacement)
  <id>_nrm_rgh.png (RGB = NormalGL, A = Roughness)
  Plus matching Godot .import files
"""

import os
import zipfile
from pathlib import Path
from PIL import Image

TEXTURES = [
    ("rock030", "Rock030", 0),
    ("ground037", "Ground037", 1),
    ("ground110", "Ground110", 2),
    ("ground048", "Ground048", 3),
    ("snow006", "Snow006", 4),
]

TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
metadata={
"imported_formats": ["s3tc_bptc"],
"vram_texture": true
}

[deps]

source_file="$SOURCE_FILE"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def pack_all():
    raw_dir = Path("/tmp/ambientcg_raw")
    out_dir = Path("/home/marco-ubuntu/aero-demons/terrain/textures")
    out_dir.mkdir(parents=True, exist_ok=True)

    for prefix, asset_id, slot_id in TEXTURES:
        zip_path = raw_dir / f"{asset_id}_2K-PNG.zip"
        print(f"Processing slot {slot_id}: {asset_id} -> {prefix}...")

        with zipfile.ZipFile(zip_path, "r") as z:
            color_name = f"{asset_id}_2K-PNG_Color.png"
            disp_name = f"{asset_id}_2K-PNG_Displacement.png"
            norm_name = f"{asset_id}_2K-PNG_NormalGL.png"
            rough_name = f"{asset_id}_2K-PNG_Roughness.png"

            with z.open(color_name) as f:
                color_img = Image.open(f).convert("RGB")
            with z.open(disp_name) as f:
                disp_img = Image.open(f).convert("L")
            with z.open(norm_name) as f:
                norm_img = Image.open(f).convert("RGB")
            with z.open(rough_name) as f:
                rough_img = Image.open(f).convert("L")

            # Ensure 2048x2048
            target_size = (2048, 2048)
            if color_img.size != target_size:
                color_img = color_img.resize(target_size, Image.Resampling.LANCZOS)
            if disp_img.size != target_size:
                disp_img = disp_img.resize(target_size, Image.Resampling.LANCZOS)
            if norm_img.size != target_size:
                norm_img = norm_img.resize(target_size, Image.Resampling.LANCZOS)
            if rough_img.size != target_size:
                rough_img = rough_img.resize(target_size, Image.Resampling.LANCZOS)

            # Pack Albedo + Height (Displacement)
            r, g, b = color_img.split()
            alb_ht = Image.merge("RGBA", (r, g, b, disp_img))
            alb_path = out_dir / f"{prefix}_alb_ht.png"
            alb_ht.save(alb_path, format="PNG", optimize=True)

            # Pack Normal + Roughness
            nr, ng, nb = norm_img.split()
            nrm_rgh = Image.merge("RGBA", (nr, ng, nb, rough_img))
            nrm_path = out_dir / f"{prefix}_nrm_rgh.png"
            nrm_rgh.save(nrm_path, format="PNG", optimize=True)

            # Write .import files
            alb_res_path = f"res://terrain/textures/{prefix}_alb_ht.png"
            with open(out_dir / f"{prefix}_alb_ht.png.import", "w") as f:
                f.write(TEMPLATE.replace("$SOURCE_FILE", alb_res_path))

            nrm_res_path = f"res://terrain/textures/{prefix}_nrm_rgh.png"
            with open(out_dir / f"{prefix}_nrm_rgh.png.import", "w") as f:
                f.write(TEMPLATE.replace("$SOURCE_FILE", nrm_res_path))

            print(f"  Saved {alb_path.name} and {nrm_path.name} (2048x2048 RGBA)")

    print("All textures packed successfully!")


if __name__ == "__main__":
    pack_all()

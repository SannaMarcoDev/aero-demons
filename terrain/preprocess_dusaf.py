#!/usr/bin/env python3
"""
Valtellina DUSAF 7.0 GIS Preprocessing Pipeline
Reproducibly subsets Regione Lombardia DUSAF 7.0 (2021) vector data
and aligns it to the exact 24x24 region (6144x6144 vertex) Terrain3D grid.

Outputs:
  - terrain/valtellina_dusaf7_subset.gpkg (vector subset in EPSG:32632)
  - terrain/masks/valtellina_semantic_masks.npz (reusable 6144x6144 semantic masks)
  - terrain/masks/*.png (reusable 8-bit masks for forest, urban, water, agriculture)

Run with:
  /home/marco-ubuntu/.local/bin/uv run --with pyogrio,geopandas,rasterio,shapely,numpy,pillow python3 terrain/preprocess_dusaf.py
"""

import sys
import time
from pathlib import Path
import numpy as np
import geopandas as gpd
from shapely.geometry import box
from rasterio.transform import Affine
from rasterio.features import rasterize
from PIL import Image

# Exact 24x24 Terrain3D Grid definition
# 24 regions * 256 vertices = 6144 vertices
GRID_SIZE = 6144
VERTEX_SPACING = 5.0
TOTAL_EXTENT_METERS = GRID_SIZE * VERTEX_SPACING  # 30,720.0 m

# Geographic Center (Godot 0,0,0) in EPSG:32632
CENTER_EASTING = 559076.8694
CENTER_NORTHING = 5112431.2481

# Grid bounds in EPSG:32632
X_MIN_UTM = CENTER_EASTING - (TOTAL_EXTENT_METERS / 2.0)   # 543,716.8694
X_MAX_UTM = CENTER_EASTING + (TOTAL_EXTENT_METERS / 2.0)   # 574,436.8694
Y_MIN_UTM = CENTER_NORTHING - (TOTAL_EXTENT_METERS / 2.0)  # 5,097,071.2481
Y_MAX_UTM = CENTER_NORTHING + (TOTAL_EXTENT_METERS / 2.0)  # 5,127,791.2481

BBOX_30K = (X_MIN_UTM, Y_MIN_UTM, X_MAX_UTM, Y_MAX_UTM)
GRID_TRANSFORM = Affine(VERTEX_SPACING, 0.0, X_MIN_UTM, 0.0, -VERTEX_SPACING, Y_MAX_UTM)

# Semantic Category Mapping for DUSAF classes
# Class IDs in mask:
# 1 = Forest (31*)
# 2 = Agriculture (2*)
# 3 = Shrubland / Meadow (32*, 333, 411)
# 4 = Rock / Scree / Glacier (331, 332, 335)
# 5 = Urban / Infrastructure (1*)
# 6 = Water Bodies (5*)

def classify_dusaf(code_str: str) -> int:
    s = str(code_str).strip()
    if s.startswith("1"):
        return 5  # Urban
    elif s.startswith("2"):
        return 2  # Agriculture
    elif s.startswith("31"):
        return 1  # Forest
    elif s.startswith("32") or s == "333" or s.startswith("4"):
        return 3  # Shrubland / Meadow / Wetland
    elif s in ("331", "332", "335"):
        return 4  # Rock / Scree / Glacier
    elif s.startswith("5"):
        return 6  # Water
    elif s.startswith("3"):
        return 3  # Other semi-natural
    return 3      # Default fallback


def run_preprocessing(shp_path: Path, project_root: Path):
    print("=== Valtellina DUSAF 7.0 GIS Preprocessing ===")
    print(f"Input Shapefile: {shp_path}")
    print(f"Target Extent: {BBOX_30K} (EPSG:32632)")
    print(f"Target Raster Grid: {GRID_SIZE}x{GRID_SIZE} at {VERTEX_SPACING}m spacing")

    t0 = time.time()
    # 1. Read shapefile with spatial filter
    print("\n1. Reading shapefile within Valtellina bounding box...")
    gdf = gpd.read_file(shp_path, engine="pyogrio", bbox=BBOX_30K)
    print(f"   Loaded {len(gdf)} intersecting features in {time.time()-t0:.2f}s")

    # 2. Clip geometries exactly to the 30.72km grid boundary
    print("2. Clipping geometries to exact 30.72km boundary...")
    clip_box = box(*BBOX_30K)
    gdf_clipped = gpd.clip(gdf, clip_box)
    print(f"   {len(gdf_clipped)} features after clipping.")

    # 3. Export GeoPackage
    out_gpkg = project_root / "terrain" / "valtellina_dusaf7_subset.gpkg"
    print(f"3. Exporting vector GeoPackage to {out_gpkg}...")
    gdf_clipped.to_file(out_gpkg, layer="dusaf7_valtellina", driver="GPKG", engine="pyogrio")
    print(f"   Saved {out_gpkg.name} ({out_gpkg.stat().st_size / (1024*1024):.1f} MB)")

    # 4. Rasterize into semantic masks
    print("\n4. Rasterizing into semantic masks (6144x6144)...")
    t1 = time.time()

    gdf_clipped["sem_id"] = gdf_clipped["COD_TOT"].apply(classify_dusaf)

    # Sort geometries so smaller high-priority features (e.g. water, urban, roads) rasterize on top of large background polygons
    # Priority order: background (meadow/shrub=3, ag=2, forest=1, rock=4, urban=5, water=6)
    priority_order = {3: 1, 2: 2, 1: 3, 4: 4, 5: 5, 6: 6}
    gdf_clipped["prio"] = gdf_clipped["sem_id"].map(priority_order)
    gdf_sorted = gdf_clipped.sort_values("prio")

    shapes = [(geom, int(val)) for geom, val in zip(gdf_sorted.geometry, gdf_sorted["sem_id"])]
    semantic_grid = rasterize(
        shapes,
        out_shape=(GRID_SIZE, GRID_SIZE),
        transform=GRID_TRANSFORM,
        fill=3,  # default fallback is meadow/alpine
        dtype=np.uint8
    )
    print(f"   Rasterization finished in {time.time()-t1:.2f}s")

    # 5. Extract boolean/binary masks for each requested semantic layer
    print("\n5. Generating and saving reusable category masks...")
    masks_dir = project_root / "terrain" / "masks"
    masks_dir.mkdir(parents=True, exist_ok=True)

    mask_forest = (semantic_grid == 1).astype(np.uint8) * 255
    mask_agriculture = (semantic_grid == 2).astype(np.uint8) * 255
    mask_shrub_meadow = (semantic_grid == 3).astype(np.uint8) * 255
    mask_rock_glacier = (semantic_grid == 4).astype(np.uint8) * 255
    mask_urban = (semantic_grid == 5).astype(np.uint8) * 255
    mask_water = (semantic_grid == 6).astype(np.uint8) * 255

    # Save compact NPZ containing all reusable masks and metadata
    npz_path = masks_dir / "valtellina_semantic_masks.npz"
    np.savez_compressed(
        npz_path,
        semantic_grid=semantic_grid,
        forest=mask_forest,
        agriculture=mask_agriculture,
        shrub_meadow=mask_shrub_meadow,
        rock_glacier=mask_rock_glacier,
        urban=mask_urban,
        water=mask_water,
        grid_size=GRID_SIZE,
        vertex_spacing=VERTEX_SPACING,
        center_easting=CENTER_EASTING,
        center_northing=CENTER_NORTHING,
        bbox=BBOX_30K
    )
    print(f"   Saved compressed NPZ: {npz_path} ({npz_path.stat().st_size / (1024*1024):.1f} MB)")

    # Save preview/reusable 8-bit PNGs (downsampled 4x to 1536x1536 for lean disk storage and quick inspection)
    for name, mask_arr in [
        ("forest_mask.png", mask_forest),
        ("urban_mask.png", mask_urban),
        ("water_mask.png", mask_water),
        ("agriculture_mask.png", mask_agriculture),
        ("rock_glacier_mask.png", mask_rock_glacier)
    ]:
        img = Image.fromarray(mask_arr)
        img_preview = img.resize((1536, 1536), Image.Resampling.NEAREST)
        img_preview.save(masks_dir / name, optimize=True)
        print(f"   Saved mask preview: {name}")

    print(f"\nPreprocessing completed successfully in {time.time()-t0:.2f}s!")


if __name__ == "__main__":
    root = Path("/home/marco-ubuntu/aero-demons")
    raw_shp = Path("/tmp/dusaf7_raw/DUSAF7.shp")
    if not raw_shp.exists():
        print(f"Error: Raw shapefile not found at {raw_shp}")
        sys.exit(1)
    run_preprocessing(raw_shp, root)

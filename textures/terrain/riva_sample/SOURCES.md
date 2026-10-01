# Riva del Garda sample — data sources

Prototype map (`scenes/levels/riva_sample.tscn`): 10.24 × 10.24 km around Riva, Torbole
and Arco (UTM 32N centre 645120 E, 5082880 N), inside a 61 km context. World axes:
x = east, z = south, y = metres above sea level; lake surface at 65 m.

Rebuild: `node tools/terrain/fetch_riva_sample.cjs all` (needs `npm i --no-save sharp`
in `tools/`; cache in `tools/tiles/riva/`, sources in `terrain/source/riva_sample/`),
then `godot --headless --path . --script res://tools/terrain/build_riva_sample.gd` and
`godot --headless --path . --import`.

| Data | Use | Licence / attribution |
| --- | --- | --- |
| DTM LiDAR PAT 2014 (+2018), 0.5 m, Provincia autonoma di Trento (STEM/SIAT) | core heights, averaged to 2 m | CC BY 4.0 — © Provincia autonoma di Trento |
| Copernicus DEM GLO-30 | context heights, core edge blend | © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018, provided under COPERNICUS by the European Union and ESA |
| ESA WorldCover 10 m 2021 v200 | forest, scrub, bare rock, built-up, crop, water; context classes | CC BY 4.0 — © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium |
| OpenStreetMap (Overpass) | parcels, vineyards/orchards, buildings, roads, rivers, rock | ODbL — © OpenStreetMap contributors |
| Sentinel-2 cloudless 2016 (s2maps.eu), EOX IT Services GmbH | low-pass regional tint only | CC BY 4.0 — Sentinel-2 cloudless by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016) |

Later Sentinel-2 cloudless years are CC BY-NC-SA: do not switch to them for a commercial build.

Textures (lossless, mipmapped, alpha is data):

- `masks_a.png` RGBA: forest, vineyard/orchard, field, settlement (4 m/px over the core)
- `masks_b.png` RGBA: building footprint, road/rail, bare rock, water
- `masks_c.png` RGBA: parcel row angle (0..π), parcel/building seed, kind (orchard 1, vineyard 0.5), scrub
- `tint.png` RGB: blurred satellite colour / mean of its WorldCover class, 0.5 = mean (30 m/px, context extent)
- `context_albedo_*.png`: baked class palette with/without the tint for the context mesh

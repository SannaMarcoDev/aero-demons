# Riva del Garda sample — data sources

Prototype map (`scenes/levels/riva_sample.tscn`): 40.96 × 40.96 km of Terrain3D at 4 m around Riva, Torbole
and Arco (UTM 32N centre 645120 E, 5082880 N; Rovereto, Ledro, Malcesine, Tremosine), inside a 199.68 km context (Adamello,
Brenta, Verona, Brescia, the plain to the Po). World axes:
x = east, z = south, y = metres above sea level; lake surface at 65 m.

Rebuild: `node tools/terrain/fetch_riva_sample.cjs all` (needs `npm i --no-save sharp`
in `tools/`; cache in `tools/tiles/riva/`, sources in `terrain/source/riva_sample/`),
then `godot --headless --path . --script res://tools/terrain/build_riva_sample.gd` and
`godot --headless --path . --import`.

| Data | Use | Licence / attribution |
| --- | --- | --- |
| DTM LiDAR PAT 2014 (+2018), 0.5 m, Provincia autonoma di Trento (STEM/SIAT) | core heights in Trentino, averaged to 4 m | CC BY 4.0 — © Provincia autonoma di Trento |
| DTM LiDAR 5 m, Regione del Veneto (IDT2) | core heights in Veneto (Monte Baldo, Malcesine) | IODL 2.0 — Regione del Veneto |
| DTM 5 m (2015), Regione Lombardia (Geoportale, ImageServer `DTM5_RL_img`) | core heights in Lombardia (Tremosine, Tignale) | CC BY 4.0 — © Regione Lombardia |
| DBM LiDAR PAT 2014, 0.5 m (terrain + buildings), Provincia autonoma di Trento (STEM/SIAT) | building roof heights | CC BY 4.0 — © Provincia autonoma di Trento |
| Copernicus DEM GLO-30 | context heights, core edge blend | © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018, provided under COPERNICUS by the European Union and ESA |
| ESA WorldCover 10 m 2021 v200 | forest, scrub, bare rock, built-up, crop, water; context classes | CC BY 4.0 — © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium |
| Ortofoto PAT 2015 RGB, 20 cm, Provincia autonoma di Trento (WMS `ecw-rgb-2015`) | terrain albedo: 1 m around Riva, 2.5 m core, 8 m context (Trentino only) | CC BY 4.0 — © Provincia autonoma di Trento |
| Ortofoto AGEA 2024, served by Regione del Veneto (WMS `rv:ortofoto_agea_2024`) | terrain albedo in Veneto, 2.5 m core | CC BY 4.0 — AGEA |
| OpenStreetMap (Overpass) | parcels, vineyards/orchards, building footprints, roads, rivers, rock | ODbL — © OpenStreetMap contributors |
| Sentinel-2 cloudless 2016 (s2maps.eu), EOX IT Services GmbH | context albedo outside Trentino and beyond 61 km, colour-matched to the orthophoto | CC BY 4.0 — Sentinel-2 cloudless by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016) |

Later Sentinel-2 cloudless years are CC BY-NC-SA: do not switch to them for a commercial build. The Lombardia
orthophotos are copyright (not open): Lombardia uses Sentinel-2.

Photos (VRAM compressed, mipmapped):

- `photo_core.jpg` RGB: orthophoto, 1 m/px around Riva (±5.12 km, under the buildings); outside Trentino the wide photo
- `photo_wide.jpg` RGB: orthophoto, 2.5 m/px over the core (16384 px); AGEA in Veneto, the context photo elsewhere
- `photo_context.jpg` RGB: orthophoto, 8 m/px over 61.44 km; Sentinel-2 outside Trentino
- `photo_far.jpg` RGB: Sentinel-2, 25.6 m/px over the whole context (7800 px), the context photo in its centre

Data textures (lossless, mipmapped, alpha is data):

- `masks_a.png` RGBA: forest, vineyard/orchard, field, settlement (8 m/px over the core)
- `masks_b.png` RGBA: building footprint, road/rail, bare rock, water
- `context_cover.png` RGB: WorldCover bare rock, snow/ice, water weights (80 m/px, context extent)

Context only (no LiDAR/OSM): `node tools/terrain/fetch_riva_sample.cjs context` and `photo`, then the
Godot build with `-- --context`. The context (`resources/terrain/riva_sample_context.scn`) is 13 × 13 chunks of
15.36 km on the Copernicus 30 m grid, with 60/120/240 m cells by distance from the core, skirts, automatic LODs and
no shadows; only Lake Garda's basin gets the lake bed and the water plane. Earth curvature (`EarthCurvature` node,
`resources/shaders/earth_curvature.gdshaderinc`) bends terrain, context, buildings and water around the camera.

Core heights: PAT LiDAR > Veneto > Lombardia, ramped over 100 m at the Trentino border and into Copernicus over
300 m where the DTMs end; the outer 400 m of the core blend into the context. The PAT DTM download (`lidar` phase,
~6000 tiles) keeps 2 m block means per 500 m tile in `tools/tiles/riva/lidar/`.

Buildings (`resources/terrain/riva_sample_buildings.scn`, the whole core in 2.048 km chunks drawn up to 12 km):
`node tools/terrain/fetch_riva_sample.cjs buildings` (after `photo`, roof colours come from `photo_core.jpg`,
`photo_wide.jpg` outside it; the DBM tiles under the footprints, ~16 GB in `tools/tiles/riva/lidar_dbm/`, are
only needed for this step), then the Godot build with `-- --buildings` (bases from the saved Terrain3D regions). Each OSM footprint is
extruded; near-rectangular ones (4-20 m span) become their rectangle with a gable roof. The roof is the DBM
median inside the footprint, else OSM `height`/levels, else 7 m. Trees avoid `masks_b.r` (footprints).

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
| DBM LiDAR PAT 2014, 0.5 m (terrain + buildings), Provincia autonoma di Trento (STEM/SIAT) | building roof heights | CC BY 4.0 — © Provincia autonoma di Trento |
| Copernicus DEM GLO-30 | context heights, core edge blend | © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018, provided under COPERNICUS by the European Union and ESA |
| ESA WorldCover 10 m 2021 v200 | forest, scrub, bare rock, built-up, crop, water; context classes | CC BY 4.0 — © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium |
| Ortofoto PAT 2015 RGB, 20 cm, Provincia autonoma di Trento (WMS `ecw-rgb-2015`) | terrain albedo: 1 m core, 8 m context (Trentino only) | CC BY 4.0 — © Provincia autonoma di Trento |
| OpenStreetMap (Overpass) | parcels, vineyards/orchards, building footprints, roads, rivers, rock | ODbL — © OpenStreetMap contributors |
| Sentinel-2 cloudless 2016 (s2maps.eu), EOX IT Services GmbH | context albedo outside Trentino, colour-matched to the orthophoto | CC BY 4.0 — Sentinel-2 cloudless by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016) |

Later Sentinel-2 cloudless years are CC BY-NC-SA: do not switch to them for a commercial build.

Photos (VRAM compressed, mipmapped):

- `photo_core.jpg` RGB: orthophoto, 1 m/px over the core; outside Trentino the context photo
- `photo_context.jpg` RGB: orthophoto, 8 m/px over the context; Sentinel-2 outside Trentino

Data textures (lossless, mipmapped, alpha is data):

- `masks_a.png` RGBA: forest, vineyard/orchard, field, settlement (4 m/px over the core)
- `masks_b.png` RGBA: building footprint, road/rail, bare rock, water
- `context_cover.png` RGB: WorldCover bare rock, snow/ice, water weights (30 m/px, context extent)

Context only (no LiDAR/OSM): `node tools/terrain/fetch_riva_sample.cjs context` and `photo`, then the
Godot build with `-- --context`.

Buildings (`resources/terrain/riva_sample_buildings.res`, one mesh): `node
tools/terrain/fetch_riva_sample.cjs buildings` (after `photo`, roof colours come from `photo_core.jpg`),
then the Godot build with `-- --buildings` (bases from the saved Terrain3D regions). Each OSM footprint is
extruded; near-rectangular ones (4-20 m span) become their rectangle with a gable roof. The roof is the DBM
median inside the footprint, else OSM `height`/levels, else 7 m. Trees avoid `masks_b.r` (footprints).

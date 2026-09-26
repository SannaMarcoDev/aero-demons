# MilitaryAirport — Godot conversion

Source: `militaryairport_unity_v1.unitypackage` supplied by the project owner (FreshCan3D MilitaryAirport, Unity 2021.3 / HDRP).

- `scenes/AirbaseDemoMap.tscn`: airport layout, 2,338 placed prefabs, ground and 28,509 terrain foliage instances. Road/runway markings are supplied by the shared materials (no projected decals).
- `scenes/Overview.tscn`: original asset overview, 113 placed prefabs and 2,605 terrain foliage instances.
- `scenes/OutdoorsScene.tscn`: original empty lighting/camera starter scene.
- `scenes/SurfaceShowcase.tscn`: 29 separated, named surface prefabs at original scale (runways, roads, junctions, asphalt variants, parking, paving, islands, helideck and speed bump). No buildings, furniture or barriers; identical prefab aliases are omitted. Editable scene with the existing free-fly camera; this is a visual catalog, not a driving/collision test.
- `scenes/BuildingsShowcase.tscn`: 6 separate building/large-structure prefabs (hangar, building, gatehouse, watchtower and both silo assemblies), labeled at original scale.
- `scenes/PropsShowcase.tscn`: 64 remaining decoration props in 12 labeled categories: crates, barrels, pallets, storage, pipes, fuel lines, ordnance, fences, barriers, signs, access/security and lights. Excludes surfaces already shown above and vegetation. Both new catalogs reuse the free-fly camera and are editable directly in the scene tree.
- `prefabs/`: reusable converted Unity prefab meshes; `models/`: 107 converted FBX models plus two lower-detail foliage meshes; `textures/`: 86 art textures resized to a maximum of 2048 px.
- `model_import.gd` restores shared Godot materials and static collision to building/prop meshes on GLB import. `foliage/*.scn` contains chunked MultiMesh data converted from the Unity terrain instances; regenerate with `godot --headless --path . --script res://tools/build_military_foliage.gd`.

Open a scene and run **Current Scene** (F6), or use the FileSystem dock to instance a prefab. Click the game window for mouse look; WASD, Q/E for flight, Shift for speed and Esc to release/exit. The game's original main scene has not been changed.

The Unity HDRP ShaderGraphs, light/fog volumes, terrain splatmaps and baked lighting cannot be imported directly. This conversion uses Godot shared PBR materials, original image assets, alpha-cut foliage, a terrain grass texture and reconstructed road/runway masks. It retains the original layout, flat terrain footprint and vegetation placement; it is not a pixel-exact HDRP render. Foliage is GPU-instanced without individual collision; buildings and props have static mesh collision.

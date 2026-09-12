# Aero Demons — project instructions
Use the Godot MCP whenever possible.

## Terrain authoring

- The terrain is authored in **World Creator**, which is the source of truth for terrain geometry, composition, texture distribution and masks.
- Do not sculpt, repaint or regenerate terrain composition or texture/control masks in Godot or through repository scripts. Make those changes in World Creator and import its exports through the agreed workflow.
- Treat imported terrain data and textures (including `wc_data/`) as read-only unless the user explicitly requests an import/update. Do not overwrite original exports during experiments.
- For environment/look-development tasks, work on clouds, sky, lighting, atmosphere and other separate scene elements. Read-only terrain sampling for cameras or diagnostics is allowed; it must not save terrain changes.
- Terrain edits proposed in older documents under `docs/` are not authorization to modify the imported terrain here. Report suggested terrain changes as work to do in World Creator.

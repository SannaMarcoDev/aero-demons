# Aero Demons — project instructions
Use the Godot AI MCP whenever possible.

## Development loop

For implementation tasks, complete this loop; do not stop after writing files:

1. **Inspect:** read applicable instructions and `git status`; preserve existing user changes. Read affected scenes/scripts and trace callers, resource references and node paths before editing.
2. **Change minimally:** reuse existing patterns; fix the shared cause, not only the visible symptom. Avoid unrelated refactors and speculative features.
3. **Check:** inspect the diff and run `git diff --check`. Run relevant script/scene tests headlessly; add a small runnable regression check for new non-trivial logic. Fix failures introduced by the change and rerun affected checks.
4. **Exercise Godot:** for scene/runtime changes, open the delivered scene and launch affected playable scenes through Godot AI MCP (`autosave=false` to avoid saving unrelated editor state). Confirm `live` and inspect current-run logs, including editor logs for boot-time parse/load errors. A timeout alone is not failure; check subsequent status before retrying. Separate retained errors from current-run failures.
5. **Close cleanly:** stop test runs, review the final diff for unintended changes, and report changes, checks actually run and remaining warnings/blockers. If a check is unavailable, state why; never imply it passed.

Successful loading/startup verifies integration, not visual quality or gameplay. Validate those separately when affected or requested; do not claim them from a clean launch alone.

## Terrain authoring

- The terrain is authored in **World Creator**, which is the source of truth for terrain geometry, composition, texture distribution and masks.
- Do not sculpt, repaint or regenerate terrain composition or texture/control masks in Godot or through repository scripts. Make those changes in World Creator and import its exports through the agreed workflow.
- Treat imported terrain data and textures (including `wc_data/`) as read-only unless the user explicitly requests an import/update. Do not overwrite original exports during experiments.
- For environment/look-development tasks, work on clouds, sky, lighting, atmosphere and other separate scene elements. Read-only terrain sampling for cameras or diagnostics is allowed; it must not save terrain changes.
- Terrain edits proposed in older documents under `docs/` are not authorization to modify the imported terrain here. Report suggested terrain changes as work to do in World Creator.

# Aero Demons — project instructions
Use the Godot AI MCP whenever possible.

## Development loop

Do not write any tests.

For implementation tasks, complete this loop; do not stop after writing files:

1. **Inspect:** read applicable instructions and `git status`; preserve existing user changes. Read affected scenes/scripts and trace callers, resource references and node paths before editing.
2. **Change minimally:** reuse existing patterns; fix the shared cause, not only the visible symptom. Avoid unrelated refactors and speculative features.
3. **Check:** inspect the diff and run `git diff --check`. Run relevant script/scene tests headlessly; add a small runnable regression check for new non-trivial logic. Fix failures introduced by the change and rerun affected checks.
   - Run headless Godot tests with an explicit wall-clock deadline and cleanup of the exact spawned process tree on timeout/error; the outer tool timeout must leave enough time for cleanup.
   - A test passes only with an explicit completion marker, exit code 0 and no script/assertion errors; after interrupted runs, terminate only verified test-owned processes, never unrelated Godot/editor instances.
4. **Exercise Godot:** for scene/runtime changes, open the delivered scene and launch affected playable scenes through Godot AI MCP (`autosave=false` to avoid saving unrelated editor state). Confirm `live` and inspect current-run logs, including editor logs for boot-time parse/load errors. A timeout alone is not failure; check subsequent status before retrying. Separate retained errors from current-run failures.
5. **Close cleanly:** stop test runs, review the final diff for unintended changes, and report changes, checks actually run and remaining warnings/blockers. If a check is unavailable, state why; never imply it passed.

Successful loading/startup verifies integration, not visual quality or gameplay. Validate those separately when affected or requested; do not claim them from a clean launch alone.

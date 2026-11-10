# M11.1 Verification Notes

## Static packaging checks performed

- All 10 resource paths declared by `CardDatabase.DEFAULT_CARD_PATHS` exist.
- Exactly 10 card `.tres` resources are present: 3 `mvp`, 7 `phase1`.
- All card IDs are unique; card names, costs, content groups and effect IDs are present.
- All `preload("res://...")` targets used by the included GDScript test files exist in this package.
- Basic delimiter/file-integrity scan completed without mismatches.

## Runtime status

This package was not executed by Godot 4.7.2 in the packaging environment because the Godot executable is not available there. The included test suite must be run inside the user's Godot project using the PowerShell commands in `README_M11_1_VI.md`. Do not mark M11.1 PASS until the actual Godot output and exit code confirm it.

The static delimiter scan is not a substitute for the GDScript parser or runtime test suite.

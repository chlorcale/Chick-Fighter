# Chick Fighter — Project Instructions

## Project Overview
- Project: **Huyền Thoại Đá Gà – Chick Fighter**.
- Engine: Godot 4.7.x.
- Language: GDScript 2.0.
- Target: Windows PC, 2D pixel-art fighting game with a compact exploration/progression loop.
- Treat the actual Godot workspace as the source of truth for implementation status. Do not assume that an item is implemented just because an earlier report or screenshot mentions it.

## Sources of Truth
Read the relevant source before implementing or changing a system:
- `docs/design/Chick_Fighter_GDD_v1.0.docx` — game design, MVP scope, controls, combat values, progression, world and release criteria.
- `docs/technical/M1_InputFrame_Spec.md` — InputFrame architecture and M1 acceptance tests.
- `docs/technical/FSM_Damage_Ledger_Patch.md` — corrected Guard eligibility and Damage Ledger decisions.

If the files are stored under different paths, locate the actual files in the repository and use those paths. Do not create duplicate copies merely to match the paths above.

### Resolving Conflicts
- Preserve decisions explicitly marked **CONFIRMED**.
- Treat **OPEN**, **PROPOSED**, and **PLACEHOLDER** items as unresolved; do not silently turn them into confirmed design.
- Where the GDD and technical handoff disagree, document the conflict and avoid implementing the disputed feature until its owner decision is available.
- Do not infer chicken breed from the player slot. P1/P2 identity and chicken breed are independent.

## Confirmed Movement Presets
Use one shared movement configuration with breed presets; do not add per-fighter custom movement values without approval.

| Breed | Speed | Jump impulse | Gravity |
|---|---:|---:|---:|
| Gà nòi | 200 px/s | 600 px/s | 2000 px/s² |
| Gà tre | 260 px/s | 600 px/s | 2000 px/s² |

- The jump-height-by-weight formula was explicitly rejected. Do not reintroduce it.
- With Jump = 600 and Gravity = 2000, expected jump apex is approximately 90 px and total flight time is approximately 0.6 s.
- Do not normalize both breeds to Speed 200.

## MVP Scope and Priorities
Build the playable fighting loop before expanding life-simulation content.

MVP target:
- One compact map combining the house, communal yard, market stall and arena.
- Two selectable chicken breeds: Gà nòi and Gà tre.
- One Ao Làng arena.
- Light, Heavy and Special attacks; MVP Special is Cước Sấm.
- Three MVP cards: Cuồng Nộ, Mai Rùa and Gió Sông.
- One weapon: Dao chân.
- One equipment slot/item: head slot / Mào sắt.
- One NPC: Chú Tư; one shop; one three-round Ao Làng tournament.
- Complete the flow: spawn → talk to NPC → choose chicken → battle → use card → win → receive reward → upgrade → battle again.
- Online Versus 1v1 is required for the MVP release, but it is a separate milestone after Core Combat has been completed and regression-tested.

Do not expand into full life simulation, multiple regions, Olympic, Gà Chín Cựa progression, Escape Mode, rollback netcode or matchmaking unless the owner explicitly changes scope.

## Combat and Simulation Rules
- Run combat simulation at a fixed 60 Hz tick. Gameplay decisions must not depend on variable render-frame delta.
- Keep input, movement, facing/guard rules, fighter state, hit detection, damage/gauges, cards, AI and match flow as clearly separated responsibilities.
- Movement Controller is the sole owner of fighter velocity, gravity and `move_and_slide()`.
- Use the project's established node/script architecture when it is sound; inspect dependencies before refactoring.
- Use the GDD's Light/Heavy/Special frame data and gauge/card rules as the baseline. Treat values explicitly marked PLACEHOLDER as tunable, not immutable facts.
- Guard is directional: derive back/forward from the opponent's relative position. Do not add a dedicated permanent Block state or a standalone Block input bit unless the design is explicitly revised.
- Every transition to Blockstun or GuardBreak must first establish a valid, blockable hit and valid Guard intent. Apply the corrected FSM patch: attacking states do not transition to Blockstun/GuardBreak merely by guarding; retain hit reactions where the patch specifies them.
- DashTravel can guard only during a valid Backdash while Back remains held. Forward Dash cannot guard.
- JumpFall must not receive generic air guard. Backjump recognition remains an owner decision until explicitly resolved.
- Clash Rush, QTE, Time Stop and Damage Ledger extensions are not automatically part of the GDD MVP. Do not implement these based only on speculative handoff notes.
- For Path B excess-damage handling, preserve the confirmed HP floor rule from the technical patch. Do not queue or reapply discarded excess damage. Do not invent resurrection behavior for HP that was already zero before handoff.
- Keep unresolved timer ownership, hit-reaction settlement, event ordering, QTE timing, Special economy and other OPEN decisions documented.

## Input Architecture
- Separate physical keys, Godot Input Map actions and logical input bits.
- Both player mappings must produce the same logical input schema.
- Combat/FSM logic should consume logical input snapshots, not inspect physical key names directly.
- InputFrame is a tick-based data snapshot; preserve its deterministic held/pressed/released semantics and ScriptedInputSource determinism.
- M1's technical specification prohibits changing existing player scripts, battle scene, node script and `project.godot` during that milestone. Respect the active milestone's file-change boundary.
- The 11th `H` bit is unresolved relative to the 10-input GDD. Keep it neutral (`ACTION_H`) until the owner defines its meaning; do not bind it to Clash Rush or Time Stop by assumption.
- Do not implement long gameplay input buffering, double-tap recognition or leniency inside M1; those belong to the later input-buffer milestone.

## Implementation Workflow
1. Inspect the repository, current scene tree, scripts, Input Map, autoloads and project settings before changing anything.
2. Identify what is implemented, partially implemented, missing and broken. Cite exact file paths and scene/node names in the report.
3. Make a short implementation plan for the next incomplete milestone. Do not rewrite working systems merely to match a preferred architecture.
4. Implement one milestone or tightly related vertical slice at a time.
5. Validate GDScript parsing, run the relevant headless/unit tests and inspect Godot runtime errors.
6. For scene changes, use the Godot MCP scene/node tools and save the scene through the supported MCP workflow.
7. Review the diff for accidental changes, generated files, broken resource paths and changes outside the milestone scope.
8. Report changed/created/deleted files, tests and exact outcomes. Distinguish PASS, FAIL, BLOCKED and NOT RUN; never claim a test passed if it was not run.
9. Continue to the next milestone only after the current milestone's acceptance criteria pass or its blockers are explicitly documented.

## Project Safety and Change Control
- Preserve existing scenes, scripts, assets, node names, signal connections, resource paths and working behavior unless the task requires a deliberate change.
- Do not perform broad rewrites, mass renames, mass formatting or asset replacements without a concrete reason.
- Do not modify `.godot/` generated cache files.
- Do not delete `.uid` or `.import` metadata. When moving a resource, keep its corresponding metadata beside it and update references using Godot-aware tools.
- Do not edit `project.godot`, Input Map actions, autoload configuration or renderer settings unless the active milestone explicitly requires it and the owner-approved scope allows it.
- Before risky changes, inspect `git status` and preserve unrelated user modifications. Never discard or overwrite uncommitted user work.
- Do not commit, push, publish or export-release unless explicitly requested.
- Keep a concise change log for design deviations and explain why each deviation was necessary.

## Definition of Done
A milestone is complete only when:
- Its acceptance criteria are mapped to concrete tests or reproducible manual checks.
- Godot reports no new parser/runtime errors attributable to the change.
- Relevant tests pass, with their commands and results recorded.
- The relevant scene can be opened and run in the target Godot version.
- No unrelated project settings, input mappings, scenes or assets were modified.
- The final report accurately lists the changes and remaining OPEN decisions.

<!-- BEGIN:godot-mcp -->
## Godot (managed by godot-mcp; edit outside these markers)

- This is a Godot 4.7 project. Your training data may be older: use Godot 4 APIs and GDScript 2.0 syntax, never Godot 3.
- Use the `godot_*` MCP tools. Start with `godot_status`, then `godot_project_info` for the main scene, autoloads and input actions.
- Change scenes with the scene/node tools, not by hand-editing `.tscn` text. If the editor is open, edits there are undoable; save with `godot_scene_save`.
- Don't edit `.godot/` (generated cache). Keep `*.uid` and `*.import` files next to their resources when moving files.
- Check your work: `godot_run_start` (mode "process"), then `godot_run_output` with level "error".
<!-- END:godot-mcp -->

# 4D Construction Tool — Project Overview

> **⚠️ Status update**: this is the original pre-implementation vision doc. Phase 1 is complete, Phase 2 (collision detection) is complete except crane geometry, Phase 3 (the editor dock) is built, and all five features specified in `06_PLANNED_FEATURES.md` have shipped — see `README.md` for the current as-built picture. The "Current (Today)" section below describes the pre-Phase-1 starting point, not where the project is now.

## Vision

Transform Godot into a **production-ready 4D construction visualization and scheduling tool** — combining 3D geometry with a real time dimension that construction teams can use to:
- **Scrub through construction timelines** visually (like Navisworks or Synchro)
- **Inspect the building at any date** to detect schedule conflicts, spatial collisions, and workflow issues before they happen on-site
- **Export and share** visualization without requiring Godot installed (via distributed plugin or standalone builds)

This is a **plugin project**, not a one-off animation. The final deliverable is a reusable Godot add-on (.pck or addon directory) that construction managers can drop into any Godot 4 project and use out-of-the-box.

---

## Current State → End State

### Current (Today)
- Fixed sequential animation: `sequence_manager.gd` plays steps 1→2→3... automatically on startup
- No scrubbing, no date awareness, no collision checks
- JSON config controls animation order but not calendar dates
- Crane swings during playback but has no "parked" state

> **From-scratch note**: if this baseline does not exist yet, it must be built first — see **Milestone -1** in `02_ROADMAP_MILESTONES.md` (scene, part registry + metas, the 8 base animations, spatial grouping, crane). That foundation is ~20–30h of work on its own; the Phase 1 estimates below assume it already exists.

### End State (After This Initiative)
- **Scrubber UI**: timeline slider (date-based or step-based), Play/Pause, speed control
- **Instant state lookup**: ask "show me the building on March 15" and parts snap to their correct state without re-running tweens
- **Date-aware scheduling**: each construction action tied to real calendar dates; parts auto-bucket across multi-day windows with per-part stagger logic preserved
- **Collision detection** (Phase 2): warn if parts would occupy the same space
- **Plugin distribution**: packaged as a Godot addon that other projects can use
- **Editor authoring** (Phase 2): Godot EditorPlugin dock for timeline editing without leaving the editor

---

## Phased Approach

### Phase 1: Timeline Foundation (This Document)
**Goal**: Build the core 4D "engine" — date-aware scheduling + scrubbing, runtime UI only.

**Deliverables**:
- Refactored JSON schema with `start_date` + `duration_days` per action
- `Cadence` helper: shared stagger/duration math
- `ConstructionSchedule`: pure-logic date-range + per-part state-at-time computation
- `AnimationApplier.apply_instant()`: instant state without tweens
- `TimelineController`: virtual clock + scrub/play driver
- `TimelineUI`: runtime slider + transport controls
- Refactored `SequenceManager`: wires it all together

**Success Criteria** (Milestones, listed later):
- Slider scrub matches visual state of sequential playback at equivalent times
- Play/Pause produces identical motion to the original auto-play
- No leftover tweens/particles/crane state when scrubbing
- Parts bucket correctly across multi-day windows

**Not included**: collision detection, editor plugin, plugin packaging

---

### Phase 2: Collision & Spatial Analysis
**Goal**: Warn/fail if delicate parts would collide during installation.

**Planned approach**:
- Per-part `Area3D` collision volumes (or use existing collision geometry)
- Query collision state at each point during scrub — note: `Area3D.get_overlapping_bodies()` lags one physics tick behind teleported parts, so prefer synchronous `PhysicsDirectSpaceState3D.intersect_shape()` queries or plain AABB intersection math
- UI indicator (red timeline zone, warning overlay) for collision windows
- Optional: pause/revert animation on collision during Play

**Not included in Phase 1**.

> **✅ As-built (partial)**: shipped using exact shape-vs-shape queries — `PhysicsDirectSpaceState3D.intersect_shape()` against a convex-hull collision shape built per part (via raw `PhysicsServer3D` areas, not `Area3D` nodes) — not plain AABB. AABB was tried first but produces false-positive flags for diagonal/rotated members (e.g. bridge beams not aligned to X/Z), whose bounding box is much looser than their real footprint; exact shapes fixed that. `ConstructionSchedule.get_collisions()` checks only in-transit (`install`-mid-progress) parts against everything else, excludes commander/child sibling groups from flagging each other, and reports/dedups at the commander level. Delivered: live warning label, a live 3D collision marker (`CollisionVisualizer`) at the (AABB-approximated) overlap region, and a full-schedule scan (`TimelineController.scan_collisions()`) that paints red zones on the slider (`CollisionOverlay`). **Update**: pause-on-collision during Play and the hover tooltip are now both built too (Phase 2 is complete except one item). Pause-on-collision is a hard gate — `TimelineController._process()` stops playback the instant a collision is present and won't let Play advance past it until the schedule is actually fixed or the user manually scrubs through. The hover tooltip reads mouse position via coordinate conversion rather than input events, so it needed no `mouse_filter` change on the overlay. **Not built**: crane geometry isn't part of the collision system (only building parts are checked, not the crane arm/hook/rope — relevant if a second crane is ever added); deliberately deferred. See `README.md`'s "Collision detection" section for full detail.

---

### Phase 3: Editor Plugin & Authoring
**Goal**: Timeline editing inside Godot editor without Play mode, drag-to-reorder steps, visual schedule builder.

**Planned approach**:
- `EditorPlugin` dock (reuses `ConstructionSchedule` core from Phase 1, no rewrite)
- Inspector panels for action date/duration fields
- **Frequency-based duration entry**: an optional `units_per_day` field on an action
  (e.g. "2 columns/day") that derives `duration_days = ceil(unit_count / units_per_day)`
  instead of requiring the author to compute and type an explicit day count.
  `unit_count` is the number of installable units — commanders for a
  `commander_prefix` action, matching parts for a `target_prefix` action. Explicit
  `duration_days` always takes precedence if both are present, so this is purely a
  convenience on top of the existing schema, not a breaking change. Natural fit for
  the inspector panel above (a "rate" input next to the date field) rather than a
  Phase 1 JSON-only feature, since the whole point is avoiding hand-authored JSON math.
- Gizmo-based preview of part positions at current editor-scrub date
- Export/import schedule helpers

**Not included in Phase 1**.

> **In progress.** Built: the `EditorPlugin` dock (`addons/construction_4d_tool/`),
> which live-scrubs the real edited scene in the 3D viewport rather than a separate
> gizmo preview — satisfying this section's preview goal directly, not via gizmos; and
> `units_per_day` frequency-based duration entry, implemented exactly as sketched above
> (`ConstructionSchedule._resolve_duration_days()`), except it's a schedule-layer
> change rather than inspector-only, so it also works from plain JSON without the dock.
> Not yet built: inspector panels for `start_date`/`duration_days`/`units_per_day`, and
> export/import schedule helpers. See `README.md`'s "Phase 3" section for
> full detail.

---

### Phase 4: Plugin Distribution & Documentation
**Goal**: Package as a reusable Godot addon (.pck, GitHub releases, asset store).

**Planned deliverables**:
- `plugin.cfg` metadata
- Bundled with example construction sequence
- README: how to integrate into a new project
- Demo: step-by-step guide for authoring a schedule
- Sample .glb imports + completed `construction_steps.json`

**Not included in Phase 1**, but architectural decisions in Phase 1 must support this (no hardcoded paths, plugin-relative resource loading, etc.).

> **✅ As-built.** The prediction held exactly: because every core class (`Cadence`, `ConstructionSchedule`, `TimelineController`) is `RefCounted`/pure `Node` with no `EditorPlugin` dependency, the Phase 3 dock wraps them directly with no rewrite. It ships as a `Control` (`TimelineDock`), not an `EditorPlugin` — live in-editor scrubbing, a 15-column schedule inspector, CSV and Microsoft Project XML import/export, and camera keyframe capture. See `README.md`'s Phase 3 section.

---

## Outside the Phased Roadmap

A **free-fly spectator camera** (`free_look_camera.gd`) was added as a debugging/inspection convenience — left-click to capture the mouse, WASD + Q/E to fly, mouse to look, Escape to release. It's attached directly to the scene's `Camera3D` and is independent of `TimelineController`/parts/collisions; it doesn't fit any of Phases 1–4 above and wasn't planned in this doc.

**Formwork (encofrado)** is a third, and the current work — specified in `07_FORMWORK.md`,
built through step 3 of 6. It splits a `fill_up` action's window into forms going up and the
pour that follows, so a five-day element stops reading as a five-day pour. It fits none of
the phases above because it is neither timeline engine, nor clash detection, nor authoring
UI: it is a statement about what the animation is *depicting*, in the same family as the
per-action cadence work of `06_PLANNED_FEATURES.md` feature 4.

**IFC model input** is the other thing this doc never anticipated. Every phase above assumes parts arrive as a flat container of `.glb`-imported nodes, each holding its placement in its own transform. A model loaded through the GDIFC GDExtension (the third-party GDIFC addon) satisfies none of that: parts nest three levels deep, node transforms are identity with survey coordinates baked into mesh vertices, and names are IFC class + STEP id rather than schedulable prefixes. An adapter layer is required, and one core-plugin guard has to change. See `05_IFC_INTEGRATION.md` — it is a prerequisite for driving the timeline from IFC geometry at all, not an optional extra.

---

## Why This Phasing?

1. **Phase 1 is the foundation**: date-aware scheduling + instant state is the architectural core all others depend on. It's the highest-risk/highest-complexity piece and unblocks visual verification early.

2. **Phases 2–4 are extensions, not refactors**: they layer on top of Phase 1's core without changing its internals. This keeps iteration velocity high and risk low.

3. **Runtime-first, EditorPlugin-later**: Phase 1 builds runtime logic first (simpler, fewer Godot APIs to learn), then Phase 3 adds an `EditorPlugin` wrapper reusing the same logic. Avoids building a plugin upfront only to discover core logic needs reworking.

4. **Plugin distribution comes last**: we validate the tool is actually *useful* (Phases 1–3) before spending effort on packaging/marketing (Phase 4).

---

## Technical Constraints & Assumptions

### Godot Version
- **Target**: Godot 4.x (4.1+ for stability; tested on 4.2+)
- GDScript only (no C# bindings initially)

### Data Model
- Schedule data lives in JSON (`construction_steps.json` with extended schema)
- No database backend in Phase 1 (could add: Excel import, MS Project interop, later)

### Performance
- Assume < 500 parts in a single construction sequence (Phase 1 scope)
- Scrubbing should feel instant (< 50ms to recompute + re-render all parts)
- No streaming/LOD in Phase 1; all geometry loaded at startup

### Backwards Compatibility
- Phase 1 **must not break** existing `construction_steps.json` files (add optional `start_date`/`duration_days` fields with sensible defaults)
- Original sequential playback should remain usable as a fallback (though UI-driven now rather than auto-play)

### Crane Behavior
- During forward Play: crane swings normally (`swing()` behavior, built in Milestone -1)
- During scrub/jump: crane parks via `retract()` — a **new** method written in Milestone -1 (the original crane script has no parked state); only invoked on manual scrubs, never on Play-driven frame updates (documented limitation for Phase 1)
- Phase 2/3 *may* add smarter "chase" behavior to sync crane to scrubbed state, but not required

---

## File Structure After Phase 1

```
project-root/
├── docs/                              # New
│   ├── 00_4D_TOOL_OVERVIEW.md         # This file
│   ├── 01_ARCHITECTURE.md             # Detailed design
│   ├── 02_ROADMAP_MILESTONES.md       # Phases + milestones
│   ├── 03_PLUGIN_DISTRIBUTION.md      # How we package this
│   └── 04_API_REFERENCE.md            # Class/function contracts
├── sequence_manager.gd                # Refactored
├── animation_applier.gd               # Extended
├── spatial_grouper.gd                 # Unchanged
├── crane.gd                           # Unchanged
├── cadence.gd                         # New
├── construction_schedule.gd           # New
├── timeline_controller.gd             # New
├── timeline_ui.gd                     # New
├── timeline_ui.tscn                   # New
└── construction_steps.json            # Extended schema
```

---

## How This Becomes a Plugin (Spoiler: It's Already Designed For It)

### Phase 1 → Phase 3 Transition
All Phase 1 classes (`ConstructionSchedule`, `Cadence`, `TimelineController`) are written as **pure logic, no `EditorPlugin` dependencies**. This means:
- A Phase 3 `EditorPlugin.gd` can instantiate `ConstructionSchedule` and call `get_part_states()` directly
- The same `timeline_ui.gd` can be reused (or slightly modified) as the editor dock's UI
- No rewrite, only *wrapping* in plugin glue code

### Phase 4 Plugin Structure
```
addons/construction_4d_tool/
├── plugin.cfg
├── plugin.gd                          # EditorPlugin entry point
├── runtime/
│   ├── timeline_controller.gd
│   ├── timeline_ui.gd
│   ├── timeline_ui.tscn
│   └── ...
├── editor/
│   ├── timeline_dock.gd               # EditorPlugin dock
│   └── ...
├── core/
│   ├── construction_schedule.gd
│   ├── cadence.gd
│   └── spatial_grouper.gd
├── examples/
│   ├── demo_construction.tscn
│   ├── construction_steps.json
│   └── ...
└── README.md
```

Each class uses `res://` or relative paths (not absolute paths) so it works whether installed in the project root or in `addons/`.

---

## Success Criteria (High Level)

By end of Phase 1:
- ✅ Visual parity: scrubbed state matches sequential playback at any point
- ✅ Smooth playback: Play/Pause feels responsive, no stutters
- ✅ No state leaks: switching between Play and scrub leaves no artifacts
- ✅ Date bucketing: 21 parts over 3 days visually bucket as 7+7+7 correctly
- ✅ Backwards compatible: old JSON files work with sensible defaults
- ✅ Ready for plugin: no hardcoded paths, no Godot editor dependencies in core logic

---

## Next Steps

1. **Read** `01_ARCHITECTURE.md` for detailed system design
2. **Review** `02_ROADMAP_MILESTONES.md` for the step-by-step build sequence and testing criteria
3. **Start implementation** once team confirms each milestone's acceptance criteria

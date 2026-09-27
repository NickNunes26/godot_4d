# 4D Construction Tool — Plugin Distribution Strategy

> **Status**: the packaging vision (channels, install paths, versioning) is still forward planning. The addon layout below is now real as of 0.4.0 (see `09_GENERICIZATION.md`); the Phase 3/4 framing elsewhere in this doc predates that. Release channels (GitHub release, Asset Library) are not yet used.

## Vision: From Project to Reusable Plugin

The 4D Construction Tool is designed from the ground up to become a **reusable Godot add-on** that construction teams can drop into any Godot 4 project and use immediately — no hardcoding, no path hacks, no project-specific dependencies.

This document outlines:
1. How Phase 1–3 architecture supports plugin distribution
2. Step-by-step plugin packaging (Phase 4)
3. Distribution channels (GitHub releases, Godot Asset Store, etc.)
4. End-user documentation

---

## Current Architecture → Plugin-Ready

### Phase 1–3: Anti-Patterns to Avoid

To keep the door open for plugin distribution, Phase 1–3 must NOT do:

❌ **DON'T**:
- Hardcode asset paths like `/mnt/data/construction_steps.json` (use relative `res://`)
- Rely on global singletons or `get_tree().current_scene.find_child()`
- Store state in `autoload` scripts
- Assume a specific scene structure (e.g., "root must be named SequenceManager")
- Write to the user's filesystem outside `user://`

✅ **DO**:
- Use `res://` relative paths for all resources
- Pass dependencies explicitly (constructor args, `set_*()` methods)
- Keep classes as `RefCounted` or pure nodes with no auto-discovery
- Document required scene structure but allow customization
- Use `preload()` for internal resources

### Phase 1 Compliance Check

All Phase 1 code should:
- ✅ Load JSON from `res://` (configurable path in `SequenceManager`)
- ✅ Instantiate `TimelineUI` from `res://timeline_ui.tscn` (or parameter-driven)
- ✅ Pass `building_parts` as a constructor argument to `ConstructionSchedule`, not discovered from `get_tree()`
- ✅ No global state; all state owned by `TimelineController` (a node in the scene tree)

**Note**: When packaged as a plugin, `res://` will resolve to the plugin directory or the project root depending on how the plugin is installed. This is Godot's standard behavior and requires no special handling from us.

---

## Phase 4: Plugin Package Structure

### Target: Godot Addon (.pck) or Addon Directory

> **This layout is now real** (0.4.0): the addon is self-contained under `addons/construction_4d_tool/`. The tree below also lists a few files that were only ever planned (`docs/AUTHORING_GUIDE.md`, `docs/TROUBLESHOOTING.md`).

```
addons/construction_4d_tool/
├── plugin.cfg                          # Godot addon metadata
├── plugin.gd                           # EditorPlugin entry point (Phase 3)
├── core/
│   ├── cadence.gd
│   ├── construction_schedule.gd
│   ├── collision_query.gd              # ADDED (Phase 2)
│   ├── spatial_grouper.gd
│   └── animation_applier.gd
├── runtime/
│   ├── timeline_controller.gd
│   ├── timeline_ui.gd
│   ├── timeline_ui.tscn
│   ├── sequence_manager.gd             # ADDED -- scene root orchestrator
│   ├── collision_visualizer.gd         # ADDED (Phase 2)
│   ├── collision_overlay.gd            # ADDED (Phase 2)
│   ├── free_look_camera.gd             # ADDED (outside the roadmap)
│   ├── camera_track.gd                 # ADDED (feature 5)
│   ├── camera_driver.gd                # ADDED (feature 5)
│   ├── formwork_builder.gd             # ADDED (07_FORMWORK.md steps 2 + 4 + 7)
│   └── crane.gd
├── editor/
│   ├── timeline_editor_dock.gd         # Phase 3 only (shipped as timeline_dock.gd)
│   ├── timeline_editor_dock.tscn       # Phase 3 only (shipped as timeline_dock.tscn)
│   ├── schedule_inspector.gd           # Phase 3 only
│   ├── schedule_csv_io.gd              # ADDED (Phase 3)
│   ├── schedule_project_xml_io.gd      # ADDED (Phase 3)
│   └── project_xml_mapping_dialog.gd   # ADDED (Phase 3)
├── examples/
│   ├── demo_scene.tscn                 # Complete working example
│   ├── demo_construction.json           # Example JSON with annotations
│   ├── README_EXAMPLE.md                # Step-by-step guide for this example
│   └── Modelos/                         # Sample .glb files (subset)
├── docs/
│   ├── API.md                           # API reference
│   ├── AUTHORING_GUIDE.md               # How to create construction sequences
│   ├── TROUBLESHOOTING.md               # Common issues & fixes
│   └── PLUGIN_LICENSE.md                # License (MIT, Apache 2.0, etc.)
└── README.md                            # Plugin README (overview, installation, quick start)
```

### `plugin.cfg` Metadata

```ini
[plugin]
name = "Build4D"
description = "A timeline-based 4D construction visualization tool for Godot 4"
author = "Your Name/Organization"
version = "1.0.0"
script = "plugin.gd"
```

### `plugin.gd` Entry Point (Phase 3)

```gdscript
@tool
extends EditorPlugin

func _enter_tree():
  # Called when plugin is loaded
  # Create EditorPlugin dock for Phase 3
  var dock = preload("res://addons/construction_4d_tool/editor/timeline_editor_dock.tscn").instantiate()
  add_control_to_dock(DOCK_SLOT_LEFT_BR, dock)

func _exit_tree():
  # Called when plugin is unloaded
  # Clean up
  pass
```

---

## Distribution Channels

### Option 1: GitHub Release (Recommended for MVP)

1. **Create GitHub repo** (or folder in existing org)
   - `https://github.com/your-org/godot-construction-4d-tool`

2. **Release process**
   ```bash
   # After Phase 3 complete, in the plugin root:
   git tag v1.0.0
   git push origin v1.0.0
   # Then create a GitHub Release with:
   # - Name: "Build4D v1.0.0"
   # - Description: feature summary, known limitations, install instructions
   # - Attach: construction_4d_tool-1.0.0.zip (the addons/ directory, zipped)
   ```

3. **Installation for end-users**
   ```
   1. Download .zip from GitHub Release
   2. Extract to Godot project root (creates addons/ directory)
   3. Enable plugin in Project Settings → Plugins
   4. Restart Godot
   5. (If Phase 3 complete) EditorPlugin dock appears
   ```

### Option 2: Godot Asset Library

- The official plugin channel (https://godotengine.org/asset-library), browsable from inside the editor via the AssetLib tab
- Submissions are ZIP archives pointing at a git repo/tag; there is a human review process
- Higher visibility, but slower to publish
- Best for stable v1.0+ releases

### Option 3: Runtime `.pck` Resource Pack (NOT an editor-addon channel)

- `.pck` files are **runtime resource packs** loaded in an exported game via `ProjectSettings.load_resource_pack()` — Godot has no "install addon from .pck" editor flow, and `.pck` cannot deliver an `EditorPlugin`
- Only relevant if we later ship a standalone *viewer* application whose construction data/scenes are distributed as content packs
- For the editor plugin itself, distribution is always ZIP (Options 1–2)

---

## Installation Paths for End-Users

### Path A: Development Install (Source)
```
User downloads: construction_4d_tool-main.zip
Extracts to: MyProject/addons/construction_4d_tool/
Enable in: Project Settings → Plugins → "Build4D" → checkbox → Enable
Restart Godot
```
- Allows user to modify plugin code
- Useful for contributors

### Path B: Release Install (.zip)
```
User downloads: construction_4d_tool-1.0.0.zip
Extracts to: MyProject/
Enable in: Project Settings → Plugins
Restart Godot
```
- Cleaner, addon structure already correct
- Best for end-users

### Path C: In-Editor Install (Asset Library)
```
User opens: AssetLib tab inside the Godot editor
Searches: "Build4D"
Clicks: Download → Install (Godot extracts the ZIP into addons/)
Enable in: Project Settings → Plugins
```
- Simplest for end-users (never leaves the editor)
- Requires an accepted Asset Library submission (Option 2)

---

## Example Integration Walkthrough

### Scenario: Construction Manager Wants to Visualize a Project

**Step 1: Create a new Godot project**
- Open the Godot Project Manager → **New Project** → name it `MyConstruction`, pick a folder, Create & Edit
- (There is no CLI command for creating a project; the closest scriptable equivalent is creating a folder containing a minimal `project.godot` file and opening it with `godot -e --path <folder>`)

**Step 2: Install plugin**
- Download `construction_4d_tool-1.0.0.zip` from GitHub Release
- Extract into `MyConstruction/` → creates `MyConstruction/addons/construction_4d_tool/`
- Open project in Godot, enable plugin (Project Settings → Plugins → checkbox)
- Restart Godot

**Step 3: Import 3D models**
- Place `.glb` or `.fbx` files in `res://models/`
- Create a new scene, import models as children

**Step 4: Author construction sequence** (Phase 1)
- Create `construction_steps.json` in project root with actions + dates
- Create a scene with a `SequenceManager` node (or use the example scene from plugin)
- Attach the `sequence_manager.gd` script
- Point it to your `.json` and 3D models
- Hit Play

**Step 5: Edit timeline** (Phase 3)
- If Phase 3 complete: open EditorPlugin dock
- Drag timeline slider to see building state at any date
- Click Play to watch construction unfold

---

## Example JSON for End-Users

### `res://construction_steps.json` (Plugin Example)

```json
{
  "steps": [
    {
      "index": 1,
      "actions": [
        {
          "type": "install",
          "commander_prefix": "Col_",
          "child_prefixes": ["Rebar_Col"],
          "start_date": "2025-03-01",
          "duration_days": 1,
          "stagger": 1.02,
          "stagger_accel": 0.95,
          "stagger_min": 0.11,
          "dur": 1,
          "dur_accel": 0.95,
          "dur_min": 0.1,
          "comment": "Install pillar structures"
        }
      ]
    },
    {
      "index": 2,
      "actions": [
        {
          "type": "install",
          "commander_prefix": "Beam_",
          "child_prefixes": ["Rebar_Beam"],
          "start_date": "2025-03-02",
          "duration_days": 3,
          "stagger": 1.02,
          "stagger_accel": 0.90,
          "stagger_min": 0.11,
          "dur": 1,
          "dur_accel": 0.90,
          "dur_min": 0.1,
          "comment": "Install precast beams over 3 days (7 per day)"
        }
      ]
    }
  ]
}
```

---

## Pre-Plugin Considerations (Phase 1 Implementation)

### Paths & Resource Loading

```gdscript
# GOOD (plugin-safe):
var json_path = "res://construction_steps.json"
var file = FileAccess.open(json_path, FileAccess.READ)

# OR (configurable):
@export var construction_json_path: String = "res://construction_steps.json"
var file = FileAccess.open(construction_json_path, FileAccess.READ)

# BAD (hardcoded, not plugin-safe):
var file = FileAccess.open("/home/user/my-project/construction_steps.json", FileAccess.READ)
```

### Scene Dependencies

```gdscript
# GOOD (explicit wiring):
var schedule = ConstructionSchedule.new(sequence_data, building_parts, spatial_grouper)
var controller = TimelineController.new()
controller.set_schedule(schedule, building_parts, crane)

# BAD (implicit discovery, not plugin-safe):
var crane = get_tree().current_scene.find_child("crane", true, false)
var building_parts = get_tree().current_scene.find_child("Building", true, false).get_children()
```

### UI Instantiation

```gdscript
# GOOD (uses preload, works in plugin):
var ui = preload("res://timeline_ui.tscn").instantiate()
add_child(ui)

# BAD (assumes project structure):
var ui = load("res://UI/timeline_ui.tscn").instantiate()
```

---

## Versioning & Compatibility

### Semantic Versioning

- **1.0.0**: Phase 1 complete (timeline foundation)
- **1.1.0**: Phase 2 complete (collision detection)
- **2.0.0**: Phase 3 complete (EditorPlugin)
- **2.1.0**: Phase 4 complete (plugin distribution)

### Godot Compatibility

- **Minimum**: Godot 4.1 (stable, required for some APIs)
- **Tested**: Godot 4.2+
- **Known Incompatibilities**: Godot 3.x (GDScript syntax differs; would require port)

### Backwards Compatibility within 1.x

- JSON schema is extended, old files must work (fields are optional)
- Internal APIs may change (no stability guarantees before 2.0)
- Plugin releases match Godot major version (v1.x for Godot 4, v2.x for Godot 5 if needed)

---

## Documentation for Plugin Users

### README.md (for plugin root)

```markdown
# Build4D

A timeline-based 4D construction visualization plugin for Godot 4.

## Features

- 📅 **Date-aware scheduling**: tie construction actions to real calendar dates
- 🎬 **Timeline scrubber**: jump to any date and see the building state
- ⏯️ **Play/Pause**: watch construction unfold at custom speed
- 🏗️ **Spatial grouping**: automatically bucket parts across multi-day windows

## Installation

1. Download `construction_4d_tool-1.0.0.zip` from [GitHub Releases](https://github.com/...)
2. Extract into your Godot project root
3. Enable the plugin: Project Settings → Plugins → "Build4D" → checkbox
4. Restart Godot

## Quick Start

1. Create a scene with your 3D building models
2. Add a `SequenceManager` node and attach `sequence_manager.gd`
3. Create `construction_steps.json` with construction actions and dates
4. Hit Play to see the timeline UI and start scrubbing

## Documentation

- [API Reference](docs/API.md)
- [Authoring Guide](docs/AUTHORING_GUIDE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## License

MIT License (or Apache 2.0, GPL 3.0 — TBD)

## Support

Issues & PRs: [GitHub Issues](https://github.com/...)
```

### AUTHORING_GUIDE.md

```markdown
# How to Author a Construction Sequence

## 1. Prepare Your 3D Models

- Export as .glb or .fbx
- Ensure parts have meaningful names (e.g., `Col_1`, `Beam_2`)
- Parts should be positioned at their final installation location in the model

## 2. Create construction_steps.json

[Example structure with annotations]

## 3. Assign Animation Types

Each action specifies a `type`:
- `install`: lift from ground, slide horizontally, lower
- `scale_up`: appear and grow to full size
- `drop_in`: fall from above
- `fade_in` / `fade_out`: transparency animations
- etc.

## 4. Define Dates & Durations

Each action has:
- `start_date`: "YYYY-MM-DD"
- `duration_days`: how many calendar days

If you have 21 walls to install over 3 days:
- Godot auto-divides into 3 groups (7 walls/day)
- Preserves visual order (back-to-front, right-to-left)

[More detail]
```

---

## Phase 4 Checklist

- [x] Phase 1–3 milestones complete
- [x] README.md written
- [x] Example scene & JSON included
- [x] plugin.cfg metadata filled in
- [x] Tested on a clean Godot 4.6 project (headless)
- [x] `.gitignore` / `.gitattributes` set up, MIT licence added
- [ ] Repository created and initial commit pushed
- [ ] `docs/AUTHORING_GUIDE.md` and `docs/TROUBLESHOOTING.md` (planned, not written)
- [ ] Release tagged (`v0.4.0`) and published
- [ ] Asset Library submission (optional, can be later)

### Releasing a new version

1. Update `version` in `plugin.cfg` and add an entry to `docs/CHANGELOG.md`.
2. Run the tests in `tests/` (see the plugin `README.md`) and open the example scene.
3. Commit, then `git tag vX.Y.Z` and `git push origin main --tags`.
4. On GitHub, create a Release from the tag. The source ZIP GitHub attaches automatically is
   installable as-is: its contents extract to `addons/construction_4d_tool/` when placed in a
   project's `addons/` folder.

---

## Future: Cloud Distribution & SaaS

*Out of scope for Phase 1–4, but mentioned for context:*

Potential future (Phase 5+):
- Web-based timeline editor (not Godot-based) for non-technical users
- REST API to upload construction sequence, get visualization link
- Hosted viewer (no Godot required, just browser)

This is possible because the core logic (`ConstructionSchedule`, `Cadence`) is pure-GDScript and could be ported to other languages (Python, Node.js, Rust) if needed.

---

## Long-Term Vision

**Year 1 (2025)**: Phase 1–2 complete, plugin available on GitHub
**Year 2 (2026)**: Phase 3–4 complete, Godot Asset Library presence, growing user base
**Year 3+**: SaaS offering, collision detection mature, real-time collaboration features

But the foundation — this plugin architecture — supports all of these without fundamental rework.

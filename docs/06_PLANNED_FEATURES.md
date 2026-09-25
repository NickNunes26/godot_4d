# 4D Construction Tool — Planned Features (all built)

> **Status**: **all five are built.** Every section is kept for the reasoning that led to
> the design and points at `README.md` for what actually shipped; `README.md` is the
> as-built source of truth. One piece was deliberately deferred rather than built — feature
> 5's look-at camera targets, noted in its section and in `README.md`'s "Next features". Each section records what is *actually* in the codebase today —
> verified against the files, with line references — so the implementation doesn't start
> from guesses. `README.md` remains the as-built source of truth; when one of these
> ships, move its description there and leave a pointer here.

These five came from real production needs while driving a real IFC model
through the tool: three are about producing a **presentable video**, two are about
**authoring** a schedule that matches how the work is actually built.

| # | Feature | Kind | Rough size |
|---|---|---|---|
| 1 | ~~Calendar date instead of "Day 0.0"~~ | UI | **✅ BUILT** — see `README.md` |
| 2 | ~~Excluding parts from the animation~~ | Authoring | **✅ BUILT** — see `README.md` |
| 3 | ~~Movie Maker Mode auto-run~~ | Output | **✅ BUILT** — see `README.md` |
| 4 | ~~Per-action stagger control (pour vs. precast)~~ | Authoring | **✅ BUILT** — see `README.md` |
| 5 | ~~Camera keyframes by date~~ | Output | **✅ BUILT** — see `README.md` |

Suggested build order: **1 → 4 → 2 → 3 → 5.** 1 and 4 are small and immediately useful;
2 cleans up the JSON that 3 and 5 will both read; 3 must exist before 5 is testable, since
5 only applies in movie mode. **All five are done, and were built in exactly that order.**

---

## 1. Show a real calendar date, not "Day 0.0" — ✅ BUILT

> **Shipped.** Reads `mar 14/abr/2026 · día 0.0`. Implementation notes are in
> `README.md`'s "Calendar dates" section; the spec below is kept for the reasoning.
> The one deviation from the plan: the collision scan report and hover tooltip were
> updated too (they said `Day 3.10–3.40`), and `_describe_window()` is now the single
> formatter both the console report and the tooltip go through, instead of the two
> duplicating the same `%.2f` strings.

**Want**: the timeline reads `14/04/2026`, not `Day 0.0` — a schedule is discussed in
dates, and a relative day count means nothing to anyone reading it.

**Current state**: `timeline_ui.gd:169` —

```gdscript
func _format_day(day_num: float) -> String:
	# ConstructionSchedule normalizes day 0 to the earliest start_date rather
	# than exposing its epoch, so this shows a relative day count.
	return "Day %.1f" % day_num
```

That comment is **stale**. `ConstructionSchedule` has kept `_min_epoch` as instance state
since the Phase 3 inspector work, and already exposes exactly the needed conversion:

```gdscript
# construction_schedule.gd:533
func day_to_date_string(day: float) -> String:
	return format_epoch_as_date(_min_epoch + day * 86400.0)
```

`TimelineUI` already holds the schedule (`_schedule: ConstructionSchedule`,
`timeline_ui.gd:22`, assigned in `set_timeline_controller()`). So this is a change to one
function, with no new plumbing. The same fix covers the Phase 3 dock automatically, since
the dock embeds `timeline_ui.tscn` rather than drawing its own label.

**Design**
- `_format_day()` returns the date, with the day number kept as a secondary detail —
  e.g. `14/04/2026 · día 0`. The day number stays useful for cross-referencing collision
  scan output, which reports in days (`timeline_ui.gd:98`).
- **Guard the undated case**: `_min_epoch` is `0.0` when no action carries a resolvable
  `start_date`, which would render every day as 1970. Fall back to the current
  `Day %.1f` string when `_schedule` is null or `_min_epoch <= 0.0`.
- Also worth updating for consistency: the collision hover tooltip and scan report
  (`_describe_window()`, `timeline_ui.gd:164`) still say `Day 3.10–3.40`.

**Open decisions**
- Format: `14/04/2026` (Spanish convention) vs ISO `2026-04-14`. The inspector already
  ships cosmetic Spanish labels (`_TYPE_DISPLAY_NAMES`, `_HEADER_LABELS` — see
  `README.md`), so `dd/mm/yyyy` is the consistent choice.
- Include the weekday (`mar 14/04/2026`)? Useful for spotting weekend work, and cheap —
  `Time.get_datetime_dict_from_unix_time()` returns it.
- Keep the day number visible at all, or drop it entirely?

**Acceptance**: scrub to any position, the label shows the correct calendar date; a JSON
with no dates still renders without showing 1970.

---

## 2. Excluding parts that don't belong in the animation — ✅ BUILT

> **Shipped.** Both root-level lists exist, the `contexto_*` actions are gone (the
> action count drops accordingly), and the inspector flags zero-match rows and can remove them.
> Implementation notes are in `README.md`'s "Static and excluded geometry" section; the
> spec below is kept for the reasoning.
>
> The three open decisions below were all resolved as the leanings suggested — static
> geometry is still collision-checked (as a target only), excluded geometry is hidden
> rather than freed, and the generator emits the context zones as `static_prefixes`
> directly rather than as an optional migration.
>
> Two things the spec didn't anticipate:
> - **A merge rule was needed, not just carry-forward.** "Reads both lists and carries
>   them forward" is ambiguous once the generator also *produces* static entries of its
>   own. Newly-discovered zones are merged into the carried list, and **excluded wins over
>   static** — otherwise a prefix the author deliberately moved from static to excluded
>   silently reappears as static on the next re-import, which is the exact "lost on
>   re-import" failure this feature set out to remove.
> - **`initialize_parts()` was not idempotent**, which this feature made load-bearing: it
>   captures each part's `original_*` metas *from state it has already mutated*, so a
>   second run recorded the previous run's zero scale as the original. A part newly added
>   to `static_prefixes` correctly stopped being hidden and was still scaled to nothing.
>   It now restores from the metas before re-capturing, and clears `building_parts` first.

**Want**: stop junk geometry cluttering the schedule. Concretely: `#0
contexto_ZoneA_` is an action for parts that shouldn't be in the sequence at
all, and one of those parts has since been deleted from the scene outright.

**Current state** — three separate problems wearing one hat:

1. **A part in no action is invisible forever.** `sequence_manager.gd:139-140` sets
   `visible = false` and `scale = Vector3.ZERO` on *every* part unconditionally. Nothing
   ever turns a part back on except an action's own animation. This is why
   `IFCScheduleGenerator` emits `contexto_<zone>` actions at all — they exist purely to
   make unscheduled geometry visible, not because anyone wants them in the schedule.
2. **An action whose parts no longer exist is silently inert.** `target_prefix` matching
   just finds nothing. No warning, and the row keeps occupying the inspector.
3. **There is no way to say "this part isn't part of this project."** Deleting the node
   works but is destructive and lost on re-import.

**Design** — introduce **static context** as a first-class idea, which removes the need
for the fake `contexto_*` actions entirely:

- A `"static_prefixes": [...]` array at the **root** of `construction_steps.json`
  (sibling to `"steps"`). `SequenceManager.initialize_parts()` checks it and simply
  doesn't hide those parts — they're visible from the first frame, permanently, and never
  animate. That is what the `contexto_*` actions were faking, expressed directly.
- A `"excluded_prefixes": [...]` array, also at root, for geometry that should be
  **hidden for the whole run** (survey markers, imported clutter) without deleting it
  from the scene.
- `IFCScheduleGenerator` reads both lists off the **existing** JSON before regenerating
  and carries them forward, so re-importing a revised model never loses these decisions.
  This mirrors the self-healing persistence the Project XML mapping file already uses
  (see `README.md`).
- The inspector gets a per-row **remove** action, plus a warning marker on any row whose
  `target_prefix` currently matches **zero** parts in the scene — which directly surfaces
  problem 2 above.

**Why root-level lists rather than a flag on each action**: these describe *geometry*, not
*work*. An excluded part has no dates, no duration and no dependencies — modelling it as
an action means every consumer (CSV export, Project XML export, the topological sort) has
to special-case a row that isn't really a task. Keeping them out of `"steps"` means those
subsystems need no changes at all.

**Open decisions**
- Should `static_prefixes` entries still be collision-checked? A permanently-present
  abutment *should* probably still flag a clash against an in-transit beam. Leaning yes —
  they're real geometry, and `get_collisions()` only treats in-transit parts as movers
  anyway, so they'd participate as targets only.
- Does excluded geometry stay loaded (hidden) or get freed? Hidden is safer and
  reversible; freeing saves nothing meaningful at 65 parts.
- Should the generator auto-populate `static_prefixes` with today's `contexto_*` groups
  on first run, so existing output migrates cleanly?

**Acceptance**: `construction_steps.json` contains no `contexto_*` actions; unscheduled
geometry is still visible from day 0; re-running Generate 4D Schedule preserves both
lists; an action matching zero parts is visibly flagged.

---

## 3. Movie Maker Mode: run start-to-finish, skip clash detection — ✅ BUILT

> **Shipped.** Implementation notes are in `README.md`'s "Movie Maker Mode" section; the
> spec below is kept for the reasoning. All three open decisions were resolved by building
> them as configurable exports rather than picking one answer:
> - **Speed** is a target length (`movie_duration_sec`, default 60 s), not a
>   days-per-second value — the spec's own preferred option. A target the `[0.1, 10.0]`
>   speed range can't reach is warned about rather than silently delivered.
> - **The final frame is held** (`movie_end_hold_sec`, default 2 s) rather than hard-cut.
>   Counted in `delta`, not wall clock, so it stays exactly that many seconds *of video* —
>   using a real-time timer there would have discarded the determinism the spec's own
>   timing note asks to preserve.
> - **Free-fly is disabled** in movie mode. The spec said "yes if feature 5 is driving the
>   camera"; doing it now costs four lines, stops a stray keypress steering a recording,
>   and leaves the `Camera3D` free for feature 5 to take over.
>
> Two deviations:
> - **`TimelineUI` and `CollisionVisualizer` are never created**, rather than created and
>   hidden as the spec describes. Identical on screen, but both run a live
>   `get_collisions()` query every frame — a real per-frame cost on every written frame,
>   for output nobody sees. It also makes "skip the auto-scan" fall out for free instead of
>   needing its own flag, which is why `movie_mode` ended up on `TimelineController` only.
> - **`movie_mode_override`** was added and isn't in the spec. Without it the only way to
>   see what a recording does is to record one.

**Want**: trigger Godot's Movie Maker Mode and have the animation play automatically from
day 0 to the end, with no collision detection interfering, to record a clean video.

**Current state**: nothing detects movie mode. Two things would actively break a recording:

- `timeline_ui.gd:104-106` runs a **full-schedule collision scan** on the first
  `_process()` frame (`_auto_scanned`). That teleports every part through the entire date
  range via `apply_instant()` — expensive, and pointless for a recording.
- **Pause-on-collision is a hard gate.** `TimelineController._process()` stops playback
  the instant a live collision exists, and pressing Play again re-triggers it while the
  collision persists (`README.md`, "What's not built"). In movie mode this would freeze
  the video permanently at the first clash.

Playback also never starts on its own — it waits for the Play button, which no one is
there to press.

**Design**
- Detect with `Engine.get_write_movie_path() != ""` — verified present in Godot 4.6.2.
  Returns the output path when the editor is launched in Movie Maker Mode, empty
  otherwise. No project setting or manual flag needed.
- Introduce a `movie_mode` flag resolved once in `SequenceManager._ready()`, passed to
  `TimelineController`/`TimelineUI` rather than each querying `Engine` independently — so
  it can also be forced on for testing without actually recording.
- When active: reset to day 0, start playing immediately, **skip the auto-scan**, and
  **bypass the collision pause gate** (leave `get_collisions()` itself alone — it's the
  *reaction* that must be suppressed, not the query).
- Stop cleanly at the end of the schedule. Movie Maker writes frames until the app quits,
  so the run should `get_tree().quit()` once `current_day` passes the last day, otherwise
  the recording continues over a static final frame forever.
- Hide `TimelineUI` (slider, buttons, warning labels) — a recording shouldn't have the
  scrubber burned into it. The 3D `CollisionVisualizer` markers should be hidden too, for
  the same reason.

**Timing note**: Movie Maker drives `_process(delta)` with a **fixed synthetic delta**
derived from the target FPS, not real elapsed time. Playback that advances
`current_day += delta * speed` is therefore already deterministic and frame-rate
independent under recording — the video's length depends only on the speed setting, never
on how fast the machine renders. That's a property worth preserving in whatever this
touches.

**Open decisions**
- How is playback speed chosen for a recording? A 160-day schedule at the default
  1 day/sec is a 160-second video. Probably wants an explicit "target video length" or a
  movie-specific speed export, rather than reusing the interactive spinbox value.
- Quit automatically at the end, or hold the final frame for a couple of seconds first?
  A hard cut on the last frame usually looks abrupt.
- Should movie mode also disable the free-fly camera? Yes if feature 5 is driving the
  camera — see below.

**Acceptance**: launching with Movie Maker Mode produces a video that starts at day 0,
runs to the last day, never pauses at a clash, and has no UI in frame.

---

## 4. Per-action stagger: precast installs vs. concrete pours — ✅ BUILT

> **Shipped.** `batch` is documented, set automatically by the generator, and editable
> per row in the inspector's *Cadencia* column. Implementation notes are in `README.md`'s
> "Per-action cadence" section; the spec below is kept for the reasoning.
>
> Three deviations from the plan, all small:
> - The generator writes `batch` **explicitly on every action** rather than only on
>   multi-part ones. Its rule is `type not in (install, drop_in)`, evaluated per action —
>   part count doesn't enter into it, since `target_prefix` matching means the count can
>   change as parts are added without the authoring intent changing.
> - `stagger` got its own inspector column alongside the two-state choice, which resolves
>   the "is a mid-point wanted" open decision below — a progressive pour is a small
>   `stagger`, now reachable without hand-editing JSON.
> - `batch` absent still means `false`, so a schedule written before this existed keeps
>   staggering until regenerated or edited.

**Want**: precast parts should appear **one by one** (they're installed individually);
a concrete pour split into several meshes purely for modelling convenience should rise
**all at once**, because it's a single pour.

**This is the most important one of the five** — it's the difference between an animation
that represents the real construction method and one that just looks busy.

**Current state — a working `batch` flag already exists and is undocumented.**
`cadence.gd:21-25`:

```gdscript
if i < ordered_parts.size() - 1:
	if not action.get("batch", false):
		current_offset += current_stagger
		current_stagger = maxf(current_stagger * stagger_accel, stagger_min)
		current_dur = maxf(current_dur * dur_accel, dur_min)
```

With `"batch": true`, no offset ever accumulates: every part in the action gets
`offset_sec = 0` and an identical duration, so they all move together. That is exactly
the pour behaviour, already implemented. `Cadence.compute_timings()` is called from both
action paths (`construction_schedule.gd:126` for `commander_prefix`, `:192` for
`target_prefix`), so it applies to either kind.

The full set of existing per-action tuning fields, none of which appear in any doc:

| Field | Default | Effect |
|---|---|---|
| `batch` | `false` | `true` = all parts simultaneously (a single pour) |
| `stagger` | `0.75` | Delay between consecutive parts |
| `stagger_accel` | `1.0` | Multiplier applied to the delay after each part |
| `stagger_min` | `stagger` | Floor for the accelerating delay |
| `dur` | `1.0` | Per-part animation duration |
| `dur_accel` | `1.0` | Multiplier applied to duration after each part |
| `dur_min` | `dur` | Floor for the accelerating duration |

**So the work here is not "build stagger control" — it's surface it and set it correctly:**

- **Document** the table above in `README.md`'s Data model section, where every other
  action field is already described. Right now these are discoverable only by reading
  `cadence.gd`.
- **Expose it in the inspector**: a per-row control — a two-state choice reading
  *Simultáneo* / *Escalonado* (matching the inspector's existing cosmetic-Spanish
  convention), plus a stagger value enabled only in the staggered case.
- **Have `IFCScheduleGenerator` set it automatically**, since the animation type already implies it:
  - `fill_up` (slabs, footings, caps, lifts) → **pours** → `batch: true`
  - `drop_in` / `install` (segments, precast units) → staggered
  This matters immediately on any model where one id covers several meshes: those are exactly
  the "split for modelling convenience" cases, and by default they would stagger.

**Must verify during implementation**: that `batch` behaves identically in the
**instant/scrub** path, not just live tweens. Both route through `get_part_states()`
(the single source of truth — see `README.md`), and `Cadence` feeds both, so it should
hold, but a pour that rises together during Play and staggers while scrubbing would be a
subtle, ugly bug. Test by scrubbing slowly through such an action's window.
**Verified — it holds.** All four parts of a four-mesh action share the window `[73.0000..80.0000]` and
900 samples across it show zero divergence in reported progress; with `batch: false` they
spread from `[73.0000..75.1538]` to `[77.8462..80.0000]`.

### Resolved: grouping and batching are two different questions

The precast-column problem ("they need to stagger, and I need a way to group them")
dissolves once these are separated. **No new IFC metadata is required for either.**

**Grouping — which parts form one action.** element id is the default. A coarser group id, where a model has one, is another grouping level.

**Batching — do those parts move together.** Default `batch: true` when parts share an
element id, **except** when `type` is `install` or `drop_in`, which describe discrete
placement of a unit and therefore always stagger.

**So precast columns have two routes in, both using existing data:**
1. Each column carries its own element id → group that action at **group id** level,
   so all the columns land in one action, and their `install` type staggers them.
2. All columns share one element id → leave grouping alone; setting `type` to
   `install` (*Instalar* in the dropdown) triggers the exception and they stagger.

Either way `batch` stays an explicit, per-action field, so any case the defaults get wrong
is one toggle in the inspector and persists in the JSON. The schedule JSON is the
hand-refinable layer — that is what removes the need to add fields to the IFC.

### Rejected: inferring batch from geometry

The tempting heuristic is "contiguous pieces are one pour, separated pieces are discrete
units." Measured pairwise centre distances within each shared element id say it can't
work:

```
footing pair   n=2   gap 12 m   -- two genuinely separate footings
girder run     n=3   gap 19 m   -- three contiguous segments
```

The *separate* elements sit closer together than the *contiguous* ones, because element
size varies far more than the gaps between them. No distance threshold separates those two
cases, so this was dropped rather than shipped as a heuristic that fails silently on the
model it was written for.

**Open decisions**
- Is a mid-point wanted — a pour that fills progressively along its length rather than
  strictly all-at-once? `stagger` with a small value already approximates this.

  A model that is entirely cast in-situ batches every action; `install`/`drop_in` are what
  exempt a genuinely precast element from automatic batching.

**Acceptance**: a four-mesh pour's parts rise together; precast segments still
arrive one at a time; both behave the same scrubbing as playing.

---

## 5. Camera keyframes by date (movie mode only) — ✅ BUILT

> **Shipped**, as `camera_track.gd` (data + interpolation), `camera_driver.gd` (applies it
> to a `Camera3D`), the dock's **Capturar cámara** button, and
> `SequenceManager._start_camera_track()`. Implementation notes are in `README.md`'s
> "Camera keyframes" section; the spec below is kept for the reasoning.
>
> **The two remaining open decisions were resolved the same way cuts-vs-moves was — by
> supporting both explicitly**, since each costs one field:
> - **Hold time.** A keyframe means *arrive*: be here on this date, which is the standard
>   keyframe reading and what "on day X the camera is here" says literally. `hold_days`
>   (default 0) then covers the "stay from this date" reading.
> - **Dock preview** needed no new work. `movie_mode_override` from feature 3 already
>   plays the track against the scene's real camera without recording. Driving the
>   *editor* viewport camera while scrubbing would be the more integrated answer and was
>   rejected: it fights the authoring flow head-on, because the camera being positioned is
>   the same camera the preview would be moving.
>
> **Look-at targets are deliberately not built** — the spec's own "possibly a second
> increment", and not in the acceptance criteria. They need the driver to resolve part
> names to live positions every frame and reconcile that against the authored rotation.
> Recorded in `README.md`'s "Next features" as the one open piece.
>
> One thing the spec didn't cover: **`fov` is forward-filled** across keyframes that don't
> specify it. Without that, a track that pulls in to 30° pops back to the scene's own fov
> the instant it reaches any later keyframe — the preceding segment already interpolates
> toward the carried value, so the jump lands exactly on the keyframe and reads as a glitch.

**Want**: "on day X the camera is here, on day Y it's there" — so a recording can cut to a
close-up of a specific operation. **Interactive mode must keep the free-fly camera**, since
that's how clashes get inspected.

**Current state**: `free_look_camera.gd` is attached directly to the scene's `Camera3D`
and owns it completely — WASD/mouse, capture on click, Escape to release
(`README.md`, "Camera"). It's independent of `TimelineController` and knows nothing about
dates. There is no camera animation of any kind.

**Design**
- A camera track: an ordered list of keyframes, each a date (or day number) plus a camera
  `Transform3D`, and optionally `fov`.
- **Storage**: a separate `camera_track.json`, *not* a key inside
  `construction_steps.json`. The schedule file is regenerated wholesale from the IFC by
  `IFCScheduleGenerator`; camera work is hand-authored and must not be at risk from a
  regeneration. Keeping it in its own file removes that hazard entirely.
- **Authoring is the hard part** — hand-writing `Transform3D` literals is unusable. The
  workable flow reuses what the Phase 3 dock already does: scrub to a date in the dock,
  position the editor viewport camera, press **"Capture camera keyframe"**. The dock can
  read the viewport camera via `EditorInterface.get_editor_viewport_3d(0).get_camera_3d()`
  and write the keyframe with the currently previewed date. This matches how the rest of
  the dock works — do it visually, persist it to JSON.
- **Playback**: in movie mode only, a driver interpolates the camera between keyframes as
  `current_day` advances, and `free_look_camera.gd` is disabled (`set_process_input(false)`
  plus releasing mouse capture) so the two never fight over the same node. With no track
  present, movie mode leaves the camera exactly where the scene put it.
- Interpolation: `lerp` the origin and `slerp` the basis (via `Quaternion`), with easing
  in/out around each key so moves start and stop smoothly rather than changing velocity
  abruptly at every keyframe.

**Resolved — cuts vs. moves**: support both, default to the move. Between two keyframes
the camera eases in and out of a smooth interpolation; a keyframe carrying `"cut": true`
is jumped to instantly instead. Defaulting to the smooth move means a track authored with
no thought about this still looks deliberate rather than jarring, and `cut` is there for
the close-ups where a glide across the site would waste ten seconds of video. This costs
one boolean in the data model, so supporting both is cheaper than choosing wrong.

**Open decisions**
- **Look-at targets.** Much more useful than a fixed rotation: `"look_at": "<part name>"` keeps a
  part framed while it's built, and survives the model moving. Adds real complexity;
  possibly a second increment.
- **Hold time.** Does a keyframe mean "be here at this date" (arrive) or "stay here from
  this date"? These produce visibly different results and the authoring UI has to make it
  obvious which one is meant.
- Should the track be previewable in the dock without a full recording? Almost certainly
  yes, or authoring becomes guesswork — but it needs `@tool` on the driver.

**Acceptance**: a recorded video moves through the authored camera positions at the right
dates; running the scene normally leaves the free-fly camera completely unaffected.

---

## Cross-cutting notes

- **Features 3 and 5 are coupled**: camera keyframes only apply in movie mode, so 3's
  `movie_mode` flag is the switch 5 hangs off. ~~Build 3 first.~~ Done — 5 can now read
  `SequenceManager.movie_mode`, and `movie_mode_override` means a camera track is testable
  without recording. 3 also already disables free-fly, so the `Camera3D` is free for a
  driver to take over rather than the two fighting over the same node.
- ~~**Features 2 and 4 both change what `IFCScheduleGenerator` writes.**~~ Both done. As
  predicted, 2 deleted the `contexto_*` block that 4 had just added a `batch: true` to,
  so that hunk went away rather than being edited — the cost of having done them in two
  passes instead of one turned out to be a single discarded line.
- **None of these require a core rewrite.** ~~Consistent with the bet~~ **Confirmed** —
  `01_ARCHITECTURE.md` made this bet in Phase 1 and the Phase 3 dock supported it; all five
  features are now built and none of them touched the core. 1 and 4 were edits to existing
  functions, 2 added two root-level keys, 3 added a flag, and 5 is a genuinely new but
  self-contained subsystem that reads `current_day` and writes a `Camera3D` — exactly as
  predicted, it touches nothing else. The one thing the prediction missed is that features
  make latent bugs load-bearing: 2 required `initialize_parts()` to become idempotent,
  which nothing had needed before.
- **Nothing here addresses the dropped element** (`[GetMesh()] unexpected mesh type 31` —
  65 parts imported where the IFC describes 66; see `05_IFC_INTEGRATION.md`). A member
  missing from the model is missing from the video *and* from collision detection. That
  remains open and is worth resolving before a schedule is signed off against this model.

# 4D Construction Tool — Pour stream (chorro de hormigón)

> **Status: built 2026-08-21.** `README.md`'s "Concrete pour stream" section is the as-built
> description; this file keeps the reasoning, the same way `07_FORMWORK.md` does for formwork.

## The want

A `fill_up` action spawns a falling stream of concrete above the part it is pouring
(`AnimationApplier.fire_fill_up_particles()`). It was always on, always derived, and had no
knobs at all. The feedback was blunt: **disliked everywhere.**

Two things follow, and they are separable:

1. It must be **optional** — a project that doesn't want it should not have it.
2. It must be **adjustable** — particle size, count, emitter angle, how hard it is pushed,
   drop height, splash. "Disliked" is not "wrong"; a stream that reads badly at one scale can
   read well once retuned, and there is currently no way to find that out.

## Off by default *(resolved 2026-08-21, decision 1)*

Every other feature in this project defaults to prior behaviour — `formwork`, calendar dates,
per-action cadence and both geometry lists all leave an untouched JSON animating exactly as it
did. The pour stream deliberately **breaks that rule**: with no `pour_stream` block, there is
no stream.

The reason is that the feedback was about the default, not about a project. Keeping it on by
default would leave the disliked thing as what you get for doing nothing, and make "make it
optional" a task that isn't finished until someone remembers to switch it off in every
project. Off by default makes the quiet result the free one, and turns tuning into opt-in
experimentation rather than damage control.

This is a visible behaviour change and is called out as one: a recording made before this
change and re-made after it will differ. That is the intended outcome.

## Schema

A root-level `"pour_stream"` block, sibling of `steps` / `static_prefixes` /
`excluded_prefixes` / `formwork_defaults` — same placement and same reasoning as
`formwork_defaults`: it describes how the *project* renders a pour, not one task.

```jsonc
"pour_stream": {
  "enabled": true,        // default false -- absent means no stream at all
  "amount": 800,          // particles in the falling column
  "grain": 0.12,          // particle size in world metres; 0 = derive from the element
  "spread_deg": 8.0,      // emitter cone half-angle -- the fan of the column
  "speed": 2.0,           // initial downward velocity ("how hard it is pushed")
  "gravity": 9.8,         // fall acceleration
  "fall": 3.0,            // drop height above the fill surface; 0 = derive
  "streak": 3.0,          // grain-radii each particle is smeared along its velocity
  "splash_amount": 220,   // particles in the landing spread; 0 disables the splash
  "collide": true         // hide particles on contact with the element
}
```

Every field optional. **`grain` and `fall` accept `0` meaning "derive from the element"**,
which is the existing behaviour and stays the default: elements run from well under a metre to over twenty, and a camera framing one is much further away than a
camera framing the other, so a single fixed size reads wrong at one end or the other. A
non-zero value overrides that derivation with an absolute world-metre figure — which is what
someone tuning by eye on one element actually wants.

**No per-action override.** Unlike `formwork`, this is not a property of the work: the stream
is a rendering choice about what a pour looks like, and a project where two pours want
different particle counts is not a case anything has asked for. Adding it later is additive.

## Tuning lives in the dock *(resolved 2026-08-21, decision 2)*

A collapsible **Vertido (chorro de hormigón)** section above the schedule inspector, with a
control per field, writing the root block.

Particle appearance is judged by eye, not by argument. Every other JSON-only field in this
project (`board_width`, `formwork.model`, `stagger_accel`) is something you set once from a
number you already know; these are not — finding a good `spread_deg` means scrubbing to a
pour, looking, and nudging. JSON-only tuning makes each iteration an edit-file → restart-
preview cycle, which is slow enough that in practice nobody does more than one pass. That is
how the current values got shipped without anyone liking them.

The checkbox sits next to the existing formwork one, so "what does this project render" is one
place in the dock rather than two.

## What is deliberately not exposed

- **Colour / material.** The stream's shade ramp is a two-stop grey gradient
  (`_pour_shade_ramp()`); wet concrete is not one flat grey, and a colour picker for it is a
  materials question rather than a scheduling one — the same call `07_FORMWORK.md` made about
  the generic wood slab's plank texture.
- **The lifetime solve.** Particle lifetime is *derived* by solving `drop = v0·t + g·t²/2`, so
  a particle's life ends exactly at the surface it was aimed at. Exposing it would let someone
  set a value that makes the stream overshoot through the concrete or stop short in mid-air,
  and there is no reason to want either. It follows `speed`, `gravity` and `fall` instead.
- **Per-particle scale variation** (`scale_min`/`scale_max`) and the emission box shape. These
  exist so the column doesn't resolve into a grid of identical spheres; they are internal
  consequences of `grain`, not independent choices.

## Interactions with what already exists

| Subsystem | Effect |
|---|---|
| **Scrub** | None. The stream is live-play only and `apply_instant()` has always skipped it — a one-shot burst makes no sense at an arbitrary scrub position. See `README.md`, "Known limitations" |
| **Formwork** | The stream already follows the *pour* window rather than the action's, from build order step 1. A 5-day element streams for 1 day, not 5 |
| **Movie mode** | Nothing special; `TimelineController` fires the same call either way |
| **`TimelineController`** | `_detect_fill_up_actions()` calls `fire_fill_up_particles()`. With the stream off it must not build the emitter at all — not build it and hide it — since a `GPUParticles3D` plus a collision box per pour is real per-frame cost for something invisible |
| **CSV / Project XML** | Untouched. Both are scoped to per-action scheduling fields; this is a project-level rendering choice with no per-action form |
| **`IFCScheduleGenerator`** | Untouched. The block is root-level, and `read_existing()` already carries the root forward |

## Acceptance criteria

- A project with no `pour_stream` block shows no stream, and builds no particle nodes.
- `"pour_stream": {"enabled": true}` reproduces today's stream exactly, with every value
  derived as before.
- Each field changes the stream in the direction its name implies.
- `grain: 0` / `fall: 0` derive from the element; non-zero overrides absolutely.
- Turning it off mid-session removes existing particle nodes rather than leaving them running.
- Scrubbing still never spawns a stream, on or off.

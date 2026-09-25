# Example: a five-minute walkthrough

`demo.tscn` is a small building made of primitive boxes: a foundation, four columns, a slab
and two walls. `demo_steps.json` schedules them.

## In the editor (no Play needed)

1. Enable the plugin (Project Settings → Plugins).
2. Open `demo.tscn`. Open the **Construction 4D Tool** dock.
3. Press **Start Preview**, then drag the slider. The parts appear in schedule order.
4. Press **Stop Preview** when done. This restores every part to how the scene was saved.

## At runtime

Run `demo.tscn` (F6). A timeline bar appears at the top: slider, Play/Pause, speed, Reset.
Click in the viewport to fly (WASD + mouse, Shift sprints, Esc releases the mouse).

## What the schedule shows

| Action | Demonstrates |
|---|---|
| `Foundation` | `fill_up` (concrete pour), an explicit `start_date`, and a `formwork` block |
| `Columns` | `rise_up`, `depends_on` + `lag_days`, and `units_per_day` (duration derived) |
| `Slab` | `drop_in`, with the start date resolved from its dependency |
| `Walls` | `fade_in`, and `batch: true` (parts move together) |

Parts are matched by **name prefix**: `target_prefix: "Col_"` animates `Col_1`..`Col_4`.
The full field reference is in `docs/README.md` ("Data model").

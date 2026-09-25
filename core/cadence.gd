class_name Cadence

static func compute_timings(ordered_parts: Array, action: Dictionary, anim_duration: float, stagger_delay: float) -> Array:
	var timings = []
	var stagger_accel: float = action.get("stagger_accel", 1.0)
	var stagger_min: float = action.get("stagger_min", stagger_delay)
	var dur_accel: float = action.get("dur_accel", 1.0)
	var dur_min: float = action.get("dur_min", anim_duration)
	var current_stagger = action.get("stagger", stagger_delay)
	var current_dur = action.get("dur", anim_duration)
	var current_offset = 0.0

	for i in range(ordered_parts.size()):
		var part_name = ordered_parts[i]
		timings.append({
			"part_name": part_name,
			"offset_sec": current_offset,
			"duration_sec": current_dur
		})
		
		if i < ordered_parts.size() - 1:
			if not action.get("batch", false):
				current_offset += current_stagger
				current_stagger = maxf(current_stagger * stagger_accel, stagger_min)
				current_dur = maxf(current_dur * dur_accel, dur_min)

	return timings

class_name GSStatsHitzones
extends RefCounted
## The stats a game keeps per body zone, declared once so every game shares ids and breakdowns.
## [method declare] adds them to a schema; [method GSStatsEventFeed.report_hit] fills them. The zone
## is a breakdown axis, so the site reads hits, damage and kills per weapon and zone.

const HITS := &"hitzone_hits"
const DAMAGE := &"hitzone_damage"
const KILLS := &"hitzone_kills"
## Hits per weapon and side of the body (left, middle, right), the accuracy-spread view.
const SIDE_HITS := &"hitzone_side_hits"


## Declares the four stats on [param schema] unless already present; returns how many were added.
static func declare(schema: GSStatsSchema) -> int:
	var added := 0
	for spec in [
		[HITS, "Hits per zone", PackedStringArray(["weapon", "zone", "weapon_zone"])],
		[DAMAGE, "Damage per zone", PackedStringArray(["weapon", "zone", "weapon_zone"])],
		[KILLS, "Kills per zone", PackedStringArray(["weapon", "zone", "weapon_zone"])],
		[SIDE_HITS, "Hits per side", PackedStringArray(["weapon", "side", "weapon_side"])],
	]:
		if schema.has(spec[0]):
			continue
		var def := schema.define(spec[0], GSStatsDef.Kind.COUNTER, spec[1])
		def.breakdowns = spec[2]
		def.category = "hitzones"
		def.publish = true
		added += 1
	return added

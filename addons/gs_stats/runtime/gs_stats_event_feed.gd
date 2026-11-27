class_name GSStatsEventFeed
extends RefCounted
## Turns a game's own events into tracker records: the game supplies ids and an event source, never the shape.
## Batching stays in [GSStatsReporter]; other inputs add a [code]report_*[/code] method calling
## [method actor], so identity rules live in one place.

var tracker: GSStatsTracker
## [code]func(id: Variant) -> StringName[/code]: the stats key of a game-side id. Default is [code]StringName(str(id))[/code].
var key_of: Callable
## [code]func(id: Variant) -> String[/code]: a display name, or "" when unknown.
var name_of: Callable
## [code]func(id: Variant) -> bool[/code]. When unset the tracker's own flag for a begun player applies.
var is_bot: Callable
## [code]func() -> Dictionary[/code] merged under every event (map, mode); the tracker context fills what is missing.
var extra: Callable
## Hits, penetrations, wall passes and shot outcomes go through [method GSStatsTracker.record_later]: the
## game calls [method GSStatsTracker.apply_pending] once per tick and gets the same totals for a fraction of
## the cost per hit. Kills are always recorded at once.
var batched: bool = false

## Breakdowns past which the kept dims start over.
const DIMS_KEPT := 4096

## Cell tag -> read-only dims, so a repeated hit builds no dictionary or string.
var _dims: Dictionary = {}


func _init(tracker_: GSStatsTracker) -> void:
	tracker = tracker_


## Resolves an id to {key, name, bot}. A name equal to the key is no name: a bot's key is a storage id, and showing it as a name is wrong.
func actor(id: Variant) -> Dictionary:
	var key := _key(id)
	var label := str(name_of.call(id)) if name_of.is_valid() else ""
	if label == "" or label == String(key):
		label = str(tracker.session_info(key).get("name", "")) if tracker != null else ""
	if label == String(key):
		label = ""
	var bot := bool(is_bot.call(id)) if is_bot.is_valid() else false
	return {"key": key, "name": label, "bot": bot}


## The stats key of [param id]; [method actor] without the name and bot lookups a hit does not use.
func _key(id: Variant) -> StringName:
	return key_of.call(id) if key_of.is_valid() else StringName(str(id))


func _file(key: StringName, stat: StringName, value: float, dims: Dictionary, cell: String) -> bool:
	if batched:
		return tracker.record_later(key, stat, value, dims, cell)
	return tracker.record(key, stat, value, dims).ok


func _keep(cell: String, dims: Dictionary) -> Dictionary:
	dims.make_read_only()
	if _dims.size() >= DIMS_KEPT:
		_dims.clear()
	_dims[cell] = dims
	return dims


## Files one kill for the head-to-head table. Names given in [param meta] as killer_name / victim_name win; refused for world deaths and suicides.
func report_kill(killer: Variant, victim: Variant, weapon: String = "", meta: Dictionary = {}) -> bool:
	if tracker == null or killer == null or victim == null:
		return false
	var k := actor(killer)
	var v := actor(victim)
	if k["key"] == &"" or v["key"] == &"" or k["key"] == v["key"]:
		return false
	var data: Dictionary = extra.call() if extra.is_valid() else {}
	data.merge(meta, true)
	if str(data.get("killer_name", "")) in ["", String(k["key"])]:
		data["killer_name"] = k["name"]
	if str(data.get("victim_name", "")) in ["", String(v["key"])]:
		data["victim_name"] = v["name"]
	data["killer_bot"] = bool(data.get("killer_bot", k["bot"]))
	data["victim_bot"] = bool(data.get("victim_bot", v["bot"]))
	return tracker.record_kill(k["key"], v["key"], weapon, data)


## Files one landed hit by body zone (see [GSStatsHitzones]; the schema must declare them). [param side] is left/middle/right or "". World and self hits are refused.
func report_hit(shooter: Variant, victim: Variant, weapon: String, zone: StringName, amount: float = 0.0, killed: bool = false, side: StringName = &"") -> bool:
	if tracker == null or shooter == null or victim == null or zone == &"":
		return false
	var key := _key(shooter)
	if key == &"" or key == _key(victim):
		return false
	var wname := weapon if weapon != "" else "unknown"
	var cell := "h\n" + wname + "\n" + zone
	var dims: Variant = _dims.get(cell)
	if dims == null:
		# The joint axis is what lets the site show one weapon's zones; separate cells cannot be crossed.
		dims = _keep(cell, {"weapon": wname, "zone": String(zone), "weapon_zone": "%s.%s" % [wname, zone]})
	var ok := _file(key, GSStatsHitzones.HITS, 1.0, dims, cell)
	if amount > 0.0:
		ok = _file(key, GSStatsHitzones.DAMAGE, amount, dims, cell) and ok
	if killed:
		ok = _file(key, GSStatsHitzones.KILLS, 1.0, dims, cell) and ok
	if side != &"":
		var side_cell := cell + "\n" + side
		var side_dims: Variant = _dims.get(side_cell)
		if side_dims == null:
			var d: Dictionary = (dims as Dictionary).duplicate()
			d["side"] = String(side)
			d["weapon_side"] = "%s.%s" % [wname, side]
			side_dims = _keep(side_cell, d)
		ok = _file(key, GSStatsHitzones.SIDE_HITS, 1.0, side_dims, side_cell) and ok
	return ok


## Files one hit by a round that passed [param kind] (wall or body) first; see [GSStatsPenetration]. World and self hits are refused.
func report_penetration(shooter: Variant, victim: Variant, weapon: String, kind: StringName, amount: float = 0.0, killed: bool = false) -> bool:
	if tracker == null or shooter == null or victim == null or kind == &"":
		return false
	var key := _key(shooter)
	if key == &"" or key == _key(victim):
		return false
	var wname := weapon if weapon != "" else "unknown"
	var cell := "p\n" + wname + "\n" + kind
	var dims: Variant = _dims.get(cell)
	if dims == null:
		dims = _keep(cell, {"weapon": wname, "kind": String(kind)})
	var ok := _file(key, GSStatsPenetration.HITS, 1.0, dims, cell)
	if amount > 0.0:
		ok = _file(key, GSStatsPenetration.DAMAGE, amount, dims, cell) and ok
	if killed:
		ok = _file(key, GSStatsPenetration.KILLS, 1.0, dims, cell) and ok
	return ok


## Files one wall a round crossed: its [param cost] in power and one pass, by material and weapon-and-material (see [method GSStatsPenetration.declare_walls]). Refused for an unnamed material or a world shooter.
func report_wall_pass(shooter: Variant, weapon: String, material: StringName, cost: float) -> bool:
	if tracker == null or shooter == null or material == &"":
		return false
	var key := _key(shooter)
	if key == &"":
		return false
	var wname := weapon if weapon != "" else "unknown"
	var cell := "w\n" + wname + "\n" + material
	var dims: Variant = _dims.get(cell)
	if dims == null:
		dims = _keep(cell, {"material": String(material), "weapon_material": "%s.%s" % [wname, material]})
	var ok := _file(key, GSStatsPenetration.PASSES, 1.0, dims, cell)
	if cost > 0.0:
		ok = _file(key, GSStatsPenetration.COST, cost, dims, cell) and ok
	return ok


## Files one resolved shot: a pull of the trigger, and a hit when it met someone (see [method GSStatsShots.declare]). Refused for an unnamed shooter or when the schema lacks [constant GSStatsShots.SHOTS].
func report_shot_outcome(shooter: Variant, weapon: String, hit: bool) -> bool:
	if tracker == null or shooter == null or not tracker.schema.has(GSStatsShots.SHOTS):
		return false
	var key := _key(shooter)
	if key == &"":
		return false
	var wname := weapon if weapon != "" else "unknown"
	var cell := "s\n" + wname
	var dims: Variant = _dims.get(cell)
	if dims == null:
		dims = _keep(cell, {"weapon": wname})
	var ok := _file(key, GSStatsShots.SHOTS, 1.0, dims, cell)
	if hit:
		ok = _file(key, GSStatsShots.HITS, 1.0, dims, cell) and ok
	return ok


## Connects a resolved-shot signal (GameSpice Combat's `shot_resolved(shot)`) to [method report_shot_outcome]: the one line that gives any game accuracy.
## The shot is read by duck type (`attacker`, `weapon_id`, `hit_anyone()`), so GameSpice Stats names no GameSpice Combat class. Declare [method GSStatsShots.declare] in the schema before the tracker starts; returns false (and connects nothing) when it is missing.
## Players only: a shooter [member key_of] gives no key (a bot, an NPC, the world) files nothing.
func bind_shots(source: Signal) -> bool:
	if tracker == null or not tracker.schema.has(GSStatsShots.SHOTS):
		return false
	source.connect(func(shot: Object = null) -> void:
		# GSStatsDamage by path, not by name: it names this class back (a script loop stays in memory, Godot 4.7).
		var _n: int = load("res://addons/gs_stats/runtime/gs_stats_damage.gd").report_shot_outcome(self, shot))
	return true


## Connects a damage signal to [method report_penetration]. [param adapter] maps its arguments to {shooter, victim, weapon, kind, amount, killed}, or {} to skip the event.
func bind_penetrations(source: Signal, adapter: Callable) -> void:
	source.connect(func(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
		var e: Dictionary = adapter.call(a, b, c)
		if e.is_empty():
			return
		var _r := report_penetration(e.get("shooter"), e.get("victim"), str(e.get("weapon", "")), StringName(str(e.get("kind", ""))), float(e.get("amount", 0.0)), bool(e.get("killed", false))))


## Connects a damage signal to [method report_hit]. [param adapter] maps its arguments to {shooter, victim, weapon, zone, amount, killed, side}.
func bind_hits(source: Signal, adapter: Callable) -> void:
	source.connect(func(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
		var e: Dictionary = adapter.call(a, b, c)
		if e.is_empty():
			return
		var _r := report_hit(e.get("shooter"), e.get("victim"), str(e.get("weapon", "")), StringName(str(e.get("zone", ""))), float(e.get("amount", 0.0)), bool(e.get("killed", false)), StringName(str(e.get("side", "")))))


## Connects a kill signal. [param adapter] maps its arguments to {killer, victim, weapon, ...meta}; the signal's arity is the adapter's.
func bind_kills(source: Signal, adapter: Callable) -> void:
	source.connect(func(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
		var e: Dictionary = adapter.call(a, b, c)
		var meta := e.duplicate()
		for k in ["killer", "victim", "weapon"]:
			meta.erase(k)
		report_kill(e.get("killer"), e.get("victim"), str(e.get("weapon", "")), meta))

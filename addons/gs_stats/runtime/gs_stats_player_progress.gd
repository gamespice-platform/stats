class_name GSStatsPlayerProgress
extends Node

## What a round game keeps for each player: a [GSStatsTracker] over the game's schema, a [GSStatsEventFeed], a [GSStatsRank], and (when the game has achievements) a tracker linked to the stats, all filed under the player's durable key.
## The numbers, the achievements, the rank terms and when each is recorded are the game's: it extends this and overrides [method _make_schema], [method _make_catalogue] and [method _rank_terms], then calls [method record] from its own `on_*` handlers.
## GameSpice Achievements is never named: its classes load by path in [method setup], and are plain Objects here, so a game without it still parses this file. A stand-in (a body whose `is_bot` is true) is never counted.

const CHANNEL := "stats.progress"
const REPORT_INTERVAL := 60.0
const ACHIEVEMENT_TRACKER := "res://addons/gs_achievements/runtime/gs_achievement_tracker.gd"
const ACHIEVEMENT_LINK := "res://addons/gs_achievements/runtime/gs_achievement_stats_link.gd"
const ACHIEVEMENT_STORE_FILE := "res://addons/gs_achievements/store/gs_achievement_store_file.gd"
const ACHIEVEMENT_STORE_MEMORY := "res://addons/gs_achievements/store/gs_achievement_store_memory.gd"

signal earned(player_id: StringName, title: String, points: int)

var stats: GSStatsTracker = null

## The skill rank: weighted lifetime figures.
var rank: GSStatsRank = null

## Kills and hits by body zone, through gs-stats' event feed.
var feed: GSStatsEventFeed = null

## A GSAchievementTracker and its GSAchievementStatsLink, or null when the game declares no catalogue.
var achievements: Object = null
var link: Object = null

## The world's own dictionary of player bodies, shared (a reference, never a copy).
var players: Dictionary = {}

## `func(player_id: StringName) -> String`: the durable key to file this player under, or "" for none. Set by the module from gs-platform.
var durable_key_fn: Callable = Callable()

## Players present when this round began. Only they have played it.
var _in_round: Dictionary = {}

## World id -> the key their numbers are filed under, and back. Fixed at [method record]'s first reading for them.
var _keys: Dictionary = {}
var _ids: Dictionary = {}

var _report_timer: Timer


## One counter, gauge or best, declared with the unit and whether a player page shows it.
static func add_def(
	out: GSStatsSchema, id: StringName, kind: GSStatsDef.Kind, display: String,
	unit: String, publish: bool
) -> void:
	var def := GSStatsDef.make(id, kind, display)
	def.unit = unit
	def.publish = publish
	out.stats.append(def)


## What the game declares: its schema. Called once, by [method setup].
func _make_schema() -> GSStatsSchema:
	return GSStatsSchema.new()


## The achievement catalogue (a GSAchievementCatalogue) over the schema's numbers, or null for none.
func _make_catalogue() -> Object:
	return null


## The weighted terms of the rank: `[{"stat": "<id>", "weight": 1.0}, ...]`. Empty means no rank.
func _rank_terms() -> Array:
	return []


## The stat the rank files under.
func _rank_stat() -> StringName:
	return &"rank_score"


## What a log and an error call this game: "prophunt".
func _label() -> String:
	return "game"


## The body for a world id, or null. Override when bodies are not in [member players] by id.
func _body(player_id: StringName) -> Object:
	return players.get(player_id)


## The feed's callbacks, once it exists. The default keys it as [method _key] does.
func _setup_feed(target: GSStatsEventFeed) -> void:
	target.key_of = func(id: Variant) -> StringName: return _key(StringName(str(id)))


## A reading was filed: the game's chance to publish the rank, count a streak, and so on.
func _after_record(_player_id: StringName, _key_id: StringName, _stat: StringName, _filed: GSResult) -> void:
	pass


## Somebody left: the game drops what it holds per player.
func _on_leave(_player_id: StringName) -> void:
	pass


## Turns the backbone report on or off at run time (the family cvar `stats_report`); the cvar is registered after this tracker is built, so [method setup] alone cannot see it.
func set_reporting(on: bool) -> GSResult:
	if stats == null:
		return GSResult.fail(GSError.CODE_STATE, "There is no stats tracker.")

	if achievements != null:
		achievements.report_to_backbone = on

	if not on:
		stats.report_to_backbone = false
		return GSResult.success(false)

	stats.report_to_backbone = true
	stats.define_on_start = true

	if not stats.reporter.is_available():
		stats.report_to_backbone = false
		GSLog.warn(CHANNEL, "stats reporting needs a backbone client with STATS_WRITE; staying off")
		return GSResult.fail(GSError.CODE_STATE, "No backbone client to report stats through.")

	if _report_timer == null:
		_report_timer = Timer.new()
		_report_timer.name = "StatsReportTimer"
		_report_timer.wait_time = REPORT_INTERVAL
		_report_timer.autostart = true
		_report_timer.timeout.connect(func() -> void: stats.flush())
		add_child(_report_timer)

	return GSResult.success(true)


## [param directory] empty keeps achievement progress in memory. [param report] turns on the backbone report.
func setup(directory: String, report: bool) -> GSResult:
	stats = GSStatsTracker.new()
	stats.name = "Stats"
	stats.schema = _make_schema()
	stats.report_to_backbone = report
	stats.define_on_start = report
	add_child(stats)
	feed = GSStatsEventFeed.new(stats)
	_setup_feed(feed)
	_make_rank()

	var counted := stats.start()

	if not counted.ok:
		return counted.wrap("%s stats" % _label())

	var catalogue := _make_catalogue()

	if catalogue == null:
		return GSResult.success()

	return _make_achievements(catalogue, directory, report)


func _make_rank() -> void:
	var terms := _rank_terms()

	if terms.is_empty():
		return

	rank = GSStatsRank.new()
	rank.stat_id = _rank_stat()
	rank.terms = terms
	rank.record_fn = func(who: Variant, stat: StringName, value: float) -> void: record(StringName(str(who)), stat, value)
	rank.key_fn = func(who: Variant) -> StringName: return _key(StringName(str(who)))


func _make_achievements(catalogue: Object, directory: String, report: bool) -> GSResult:
	achievements = load(ACHIEVEMENT_TRACKER).new()
	achievements.name = "Achievements"
	achievements.catalogue = catalogue
	achievements.report_to_backbone = report
	# Not published: a server and a client in one process (every suite) would fight over one registry name, and the link below is handed the tracker directly.
	achievements.register_as = &""

	if directory != "":
		var file_store: Object = load(ACHIEVEMENT_STORE_FILE).new()
		file_store.directory = directory
		achievements.store = file_store
	else:
		achievements.store = load(ACHIEVEMENT_STORE_MEMORY).new()

	add_child(achievements)

	var awarded: GSResult = achievements.start()

	if not awarded.ok:
		return awarded.wrap("%s achievements" % _label())

	achievements.unlocked.connect(_on_unlocked)

	link = load(ACHIEVEMENT_LINK).new()
	link.name = "StatsLink"
	link.tracker = achievements
	link.stats = stats
	add_child(link)

	var linked: GSResult = link.start()
	return linked.wrap("%s's stats-to-achievements link" % _label())


## Files one reading for one person, and starts counting for them the first time.
## Begun lazily, on the first number, which keeps stand-ins out: a player is added before a bridge or client marks them one, so a join-time check would see every bot as a person.
## The memory and file stores load synchronously, so the tracker has them before the reading that follows.
func record(player_id: StringName, stat: StringName, value: float = 1.0) -> void:
	if stats == null:
		return

	var body := _body(player_id)

	if body == null or bool(body.get("is_bot")):
		return

	var key := _key(player_id)

	if not stats.has_player(key):
		_load_baseline(player_id)
		stats.begin(key, str(body.get("display_name")))
		_begin(key)

	var filed := stats.record(key, stat, value)

	if not filed.ok:
		# WARN: a number a player earned that nobody will ever see. It is a schema or a key that is wrong, and it only ever happens for a reason worth looking at.
		GSLog.warn(CHANNEL, "a reading was refused", {
			"player": String(player_id), "stat": String(stat), "why": filed.error.message,
		})

	_after_record(player_id, key, stat, filed)


## A landed hit by body zone, from a GameSpice Combat damage (duck-typed), filed under the world ids [param attacker] and [param victim]; a trace that met no hitbox has no zone.
func report_hit(attacker: StringName, victim: StringName, damage: Object) -> void:
	var group := StringName(damage.get("hit_group"))

	if feed == null or group == GSStatsDamage.GENERIC_GROUP or group == &"":
		return

	var context: Dictionary = damage.get("context")
	var side := StringName(str(context.get(GSStatsDamage.SIDE_KEY, "")))
	var _ok := feed.report_hit(attacker, victim, String(damage.get("weapon_id")), group,
		float(damage.get("health_lost")), bool(damage.get("lethal")), side)


## Files a kill for the head-to-head table.
func report_kill(killer: StringName, victim: StringName, weapon: String = "") -> void:
	if feed != null:
		var _ok := feed.report_kill(killer, victim, weapon)


## Reads the player's stored lifetime totals before this session's figures are flushed into the store (reading later would count them twice). The file store answers without suspending.
func _load_baseline(player_id: StringName) -> void:
	if rank != null and stats.store != null:
		rank.load_baseline(stats.store, player_id)


## Files the player's rank score on their lifetime baseline plus this session.
func publish_rank(player_id: StringName) -> void:
	if rank == null or rank.mode != GSStatsRank.MODE_WEIGHTED or stats == null or not stats.has_player(_key(player_id)):
		return
	var _s := rank.publish_lifetime(player_id, session_values(player_id), stats.schema)


## The key a player's numbers are filed under. Asked of [member durable_key_fn] once, then remembered.
func _key(player_id: StringName) -> StringName:
	if _keys.has(player_id):
		return _keys[player_id]

	var key := player_id

	if durable_key_fn.is_valid():
		var durable := str(durable_key_fn.call(player_id))

		if durable != "":
			key = StringName(durable)

	_keys[player_id] = key
	_ids[key] = player_id
	return key


## Loads somebody's lifetime progress. A statement call, never assigned: the tracker's `begin` is a coroutine, and this is the family's pattern for starting one from code that is not.
func _begin(player_id: StringName) -> void:
	if achievements == null:
		return

	var began: GSResult = await achievements.begin(String(player_id))

	if not began.ok:
		# WARN: this player will earn nothing this session, and they will not be told why.
		GSLog.warn(CHANNEL, "achievement progress could not be loaded", {
			"player": String(player_id), "why": began.error.message,
		})


## Saves somebody's progress as they go. See [method _begin].
func _end(player_id: StringName) -> void:
	if achievements == null:
		return

	var ended: GSResult = await achievements.end(String(player_id))

	if not ended.ok:
		GSLog.warn(CHANNEL, "achievement progress could not be saved", {
			"player": String(player_id), "why": ended.error.message,
		})


## Stops counting for somebody who left, and saves what they earned.
func leave(player_id: StringName) -> void:
	_in_round.erase(player_id)
	_on_leave(player_id)

	var key: StringName = _keys.get(player_id, player_id)
	_keys.erase(player_id)
	_ids.erase(key)

	if stats == null or not stats.has_player(key):
		return

	var _values := stats.end(key)
	if rank != null:
		rank.forget(player_id)
	if link != null:
		link.forget(String(key))
	_end(key)


func session_values(player_id: StringName) -> GSStatsValues:
	return stats.session_values(_keys.get(player_id, player_id)) \
		if stats != null else GSStatsValues.new()


## The key [param player_id]'s numbers are filed under. For a console command and a suite.
func filed_under(player_id: StringName) -> StringName:
	return _keys.get(player_id, player_id)


func _on_unlocked(player: String, achievement: Object) -> void:
	# INFO: what an admin keeps. "I did the thing and was not told" is answered here.
	GSLog.info(CHANNEL, "an achievement was unlocked", {
		"player": player, "achievement": String(achievement.id), "points": achievement.points,
	})
	# Back to the world's id: the world tells the player, and the world knows them by that.
	earned.emit(_ids.get(StringName(player), StringName(player)),
		achievement.display_name, achievement.points)


func describe() -> Dictionary:
	return {
		"tracking": stats.players().size() if stats != null else 0,
		"in_round": _in_round.size(),
		"achievements": achievements.catalogue.size() if achievements != null else 0,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	if stats != null:
		out.append_array(stats.describe_lines())

	if achievements != null:
		out.append_array(achievements.describe_lines())

	return out

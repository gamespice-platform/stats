extends Node
## Offline suite for GSStatsPlayerProgress. godot --headless --path . res://examples/progress_selftest.tscn

const KILLS := &"kills"
const BEST := &"best"

var _passed := 0
var _failed := 0


class Body:
	extends RefCounted
	var is_bot := false
	var display_name := "p"


class Game:
	extends GSStatsPlayerProgress
	var after: Array = []

	func _label() -> String:
		return "selftest"

	func _make_schema() -> GSStatsSchema:
		var out := GSStatsSchema.new()
		add_def(out, KILLS, GSStatsDef.Kind.COUNTER, "Kills", "kills", true)
		add_def(out, BEST, GSStatsDef.Kind.BEST, "Best", "kills", true)
		GSStatsRank.declare(out, &"rank_score", "Rank score")
		return out

	func _rank_terms() -> Array:
		return [{"stat": "kills", "weight": 2.0}]

	func _after_record(player_id: StringName, _key_id: StringName, stat: StringName, _filed: GSResult) -> void:
		after.append([player_id, stat])


func _ready() -> void:
	var g := Game.new()
	add_child(g)
	var set_up := g.setup("", false)
	_check(set_up.ok and g.stats != null and g.feed != null and g.rank != null, "setup builds stats, feed and rank")
	_check(g.achievements == null and g.link == null, "no catalogue, no achievements")

	var human := Body.new()
	var bot := Body.new()
	bot.is_bot = true
	g.players[&"a"] = human
	g.players[&"b"] = bot

	g.record(&"a", KILLS, 3.0)
	g.record(&"b", KILLS, 3.0)
	g.record(&"ghost", KILLS, 1.0)
	_check(g.stats.has_player(&"a") and not g.stats.has_player(&"b") and not g.stats.has_player(&"ghost"), "stand-ins and unknown ids are not counted")
	_check(is_equal_approx(g.session_values(&"a").get_value(KILLS), 3.0), "a reading is filed")
	_check(g.after.size() == 1 and g.after[0] == [&"a", KILLS], "_after_record runs once, for the counted reading")

	g.durable_key_fn = func(id: StringName) -> String: return "key-" + String(id)
	_check(g.filed_under(&"a") == &"a", "a key stays as first read")
	g.durable_key_fn = Callable()

	g.publish_rank(&"a")
	_check(g.stats.has_player(&"a") and g.describe()["tracking"] == 1, "describe counts the player")

	g.leave(&"a")
	_check(not g.stats.has_player(&"a"), "leave ends counting")

	var off := g.set_reporting(false)
	_check(off.ok and not g.stats.report_to_backbone, "reporting off is a success")

	print("progress_selftest: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", what)

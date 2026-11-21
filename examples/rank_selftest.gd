extends Node
## Offline suite for GSStatsRank. godot --headless --path . res://examples/rank_selftest.tscn

var _passed := 0
var _failed := 0
var _filed: Dictionary = {}


func _ready() -> void:
	var r := GSStatsRank.new()
	r.record_fn = func(p: Variant, s: StringName, v: float) -> void: _filed[p] = [s, v]

	_check(is_equal_approx(r.weighted({"kills": 10, "deaths": 4, "headshots": 2, "points": 500}), 10.0 - 2.0 + 1.0 + 5.0), "default weights")
	r.configure({"terms": [{"stat": "kills", "weight": 100.0, "per": "deaths", "cap": 300.0}], "scale": 2.0, "offset": 10.0})
	_check(is_equal_approx(r.weighted({"kills": 6, "deaths": 3}), (10.0 + 200.0) * 2.0), "ratio term, offset, scale")
	_check(is_equal_approx(r.weighted({"kills": 60, "deaths": 3}), (10.0 + 300.0) * 2.0), "cap clamps a term")
	_check(is_equal_approx(r.weighted({"kills": 5}), 20.0), "a zero divisor contributes nothing")

	r.configure({"min_stat": "kills", "min_value": 10.0})
	_check(is_nan(r.publish(1, {"kills": 5, "deaths": 1})) and not r.has_score({"kills": 5}) and not _filed.has(1), "withheld below the minimum")
	_check(r.publish(1, {"kills": 12, "deaths": 4}) > 0.0 and _filed[1][0] == &"rank_score", "published as rank_score")
	var neg := GSStatsRank.new()
	neg.record_fn = r.record_fn
	var neg_a := neg.publish(2, {"deaths": 4})
	var neg_b := neg.publish(3, {"deaths": 8})
	_check(neg_a < 0.0 and neg_b < neg_a and _filed[2][1] == roundf(neg_a) and not is_nan(neg_a), "a negative weighted score is published as is, and worse stays below less bad")
	_check(not is_nan(neg.score(2, {"deaths": 4})) and neg.has_score({"deaths": 4}), "a negative score is not mistaken for withheld")

	var scoped := GSStatsRank.new()
	scoped.configure_scoped({
		"default": {"mode": "weighted", "scale": 1.0},
		"apps": {"a": {"scale": 2.0}}, "servers": {"s1": {"mode": "elo", "elo_k": 40.0}},
	}, "a", "s1")
	_check(scoped.mode == &"elo" and scoped.scale == 2.0 and scoped.elo_k == 40.0, "server overrides app overrides default")
	var other := GSStatsRank.new()
	other.configure_scoped({"apps": {"a": {"scale": 2.0}}, "servers": {"s1": {"mode": "elo"}}}, "b", "s2")
	_check(other.mode == &"weighted" and other.scale == 1.0, "an unlisted app and server get the defaults")

	var c := GSStatsRank.new()
	_check(c.apply_cvar("elo") and c.mode == &"elo", "cvar selects elo")
	_check(c.apply_cvar("weighted:kills=2,deaths=-1") and c.terms.size() == 2 and c.mode == &"weighted", "cvar carries weights")
	_check(not c.apply_cvar("glicko") and c.mode == &"weighted", "an unknown mode is refused and changes nothing")

	var e := GSStatsRank.new()
	e.mode = GSStatsRank.MODE_ELO
	e.record_fn = r.record_fn
	_filed.clear()
	var moved := e.duel(1, 2)
	_check(is_equal_approx(moved, 12.0) and is_equal_approx(e.rating_of(1), 1012.0) and is_equal_approx(e.rating_of(2), 988.0), "equal ratings move k/2")
	_check(_filed[1][1] == 1012.0 and _filed[2][1] == 988.0, "both gauges filed")
	e.seed_rating(3, 1400.0)
	var upset := e.duel(2, 3)
	_check(upset > 12.0 and e.duel(3, 2) < 12.0, "beating a stronger player pays more")
	_check(e.duel(1, 1) == 0.0, "a suicide moves nothing")
	_check(e.score(1) == e.rating_of(1), "elo score is the rating")
	e.elo_floor = 990.0
	e.seed_rating(4, 991.0)
	var _m := e.duel(1, 4)
	_check(e.rating_of(4) == 990.0, "the floor holds")

	var sess := GSStatsValues.from_dictionary({"kills": 5.0, "deaths": 2.0})
	var combined := GSStatsRank.combine({"kills": 10.0, "deaths": 1.0}, sess)
	_check(combined["kills"] == 15.0 and combined["deaths"] == 3.0, "combine adds session to lifetime")

	var copy := GSStatsRank.new()
	copy.configure(JSON.parse_string(JSON.stringify(r.to_dictionary())))
	_check(copy.terms == r.terms and copy.min_value == 10.0, "config round-trips through JSON")
	var schema := GSStatsSchema.new()
	var def := GSStatsRank.declare(schema)
	_check(schema.find(&"rank_score") == def and def.publish and def.kind == GSStatsDef.Kind.GAUGE, "declare adds a published gauge")

	await _lifetime()
	await _file_store()

	print("rank_selftest: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", what)


func _lifetime() -> void:
	var schema := GSStatsSchema.new()
	schema.define(&"kills", GSStatsDef.Kind.COUNTER)
	schema.define(&"best_streak", GSStatsDef.Kind.BEST)
	var store := GSStatsStoreMemory.new()
	store.schema = schema
	var past := GSStatsValues.from_dictionary({"kills": 100.0, "best_streak": 9.0})
	await store.merge(&"p1", past.to_dictionary(), null, "P1")
	var r := GSStatsRank.new()
	r.configure({"terms": [{"stat": "kills", "weight": 1.0}, {"stat": "best_streak", "weight": 10.0}]})
	r.record_fn = func(p: Variant, s: StringName, v: float) -> void: _filed[p] = [s, v]
	var res: GSResult = await r.load_baseline(store, &"p1")
	var session := GSStatsValues.from_dictionary({"kills": 5.0, "best_streak": 4.0})
	_check(res.ok and r.baselines.has(&"p1"), "baseline loaded from a store")
	_check(r.publish_lifetime(&"p1", session, schema) == 105.0 + 90.0, "lifetime rank merges by kind (BEST keeps 9)")
	_check(_filed[&"p1"][1] == 195.0, "lifetime figure filed as the gauge")
	_check(r.publish_lifetime(&"new", session, schema) == 5.0 + 40.0, "no baseline ranks on the session alone")
	var merged := GSStatsRank.combine({"kills": 100.0, "best_streak": 9.0}, session, schema)
	_check(merged["kills"] == 105.0 and merged["best_streak"] == 9.0, "schema combine keeps the higher BEST")
	r.mode = GSStatsRank.MODE_ELO
	r.seed_baseline(&"e1", GSStatsValues.from_dictionary({"rank_score": 1300.0}))
	_check(r.rating_of(&"e1") == 1300.0, "elo rating seeded from the stored rank")

	var keyed := GSStatsRank.new()
	keyed.configure({"terms": [{"stat": "kills", "weight": 1.0}]})
	keyed.key_fn = func(who: Variant) -> StringName: return StringName("key-%s" % who)
	await store.merge(&"key-7", GSStatsValues.from_dictionary({"kills": 40.0}).to_dictionary(), null, "K")
	var kres: GSResult = await keyed.load_baseline(store, 7)
	_check(kres.ok and keyed.baselines.has(7), "load_baseline finds a baseline stored under the key_fn key")
	_check(keyed.publish_lifetime(7, GSStatsValues.from_dictionary({"kills": 2.0}), schema) == 42.0, "keyed lifetime rank adds the session")
	_check(GSStatsRank.new().store_key(7) == &"7", "store_key defaults to the player id")


func _file_store() -> void:
	var path := "user://rank_selftest_stats.json"
	DirAccess.remove_absolute(path)
	var schema := GSStatsSchema.new()
	schema.define(&"kills", GSStatsDef.Kind.COUNTER)
	schema.define(&"best_streak", GSStatsDef.Kind.BEST)
	var a := GSStatsStoreFile.new(path)
	a.schema = schema
	await a.merge(&"p1", {"kills": 10.0, "best_streak": 3.0}, null, "P1")
	await a.merge(&"p1", {"kills": 5.0, "best_streak": 2.0}, null, "P1")
	_check(a.writes == 0, "file store writes nothing inside a merge")
	a.finish()
	_check(a.writes == 1, "two merges are one write")
	var b := GSStatsStoreFile.new(path)
	b.schema = schema
	var res: GSResult = await b.values_for(&"p1")
	_check(res.ok and res.value.get_value(&"kills") == 15.0 and res.value.get_value(&"best_streak") == 3.0, "file store keeps totals across instances")
	await b.merge(&"p1", {"kills": 1.0}, null, "P1")
	b.finish()
	var c := GSStatsStoreFile.new(path)
	c.schema = schema
	res = await c.values_for(&"p1")
	_check(res.ok and res.value.get_value(&"kills") == 16.0, "file store keeps a merge once finished")
	var w := GSStatsStoreFile.new(path)
	w.schema = schema
	w.write_behind = false
	await w.merge(&"p1", {"kills": 1.0}, null, "P1")
	await w.merge(&"p1", {"kills": 1.0}, null, "P1")
	_check(w.writes == 2, "write_behind off writes through on every merge")
	var tick := GSStatsStoreFile.new(path)
	tick.schema = schema
	await tick.merge(&"p1", {"kills": 1.0}, null, "P1")
	await tick.merge(&"p2", {"kills": 1.0}, null, "P2")
	for _i in 200:
		await get_tree().process_frame
		if tick.writes > 0:
			break
	tick.finish()
	_check(tick.writes == 1, "a frame later the dirty file is written once, off the merge")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var bad := GSStatsStoreFile.new(path)
	bad.schema = schema
	res = await bad.values_for(&"p1")
	_check(not res.ok, "a corrupt file fails rather than reading as empty")
	res = await bad.merge(&"p1", {"kills": 1.0}, null, "P1")
	_check(not res.ok, "a corrupt file refuses a merge")
	DirAccess.remove_absolute(path)

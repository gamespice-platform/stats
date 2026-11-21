class_name GSStatsStoreMemory
extends GSStatsStore

## Lifetime values in a dictionary, lost on exit. For tests, a scratch server, and as the
## reference the SQL store is checked against.

## player id -> {"name": String, "values": GSStatsValues}
var _rows: Dictionary = {}


func _merge(
	player_id: StringName, incoming: GSStatsValues, p_schema: GSStatsSchema, player_name: String
) -> GSResult:
	if not _rows.has(player_id):
		_rows[player_id] = {"name": player_name, "values": GSStatsValues.new()}

	var row: Dictionary = _rows[player_id]
	if player_name != "":
		row["name"] = player_name

	# The rule, from the one place it is written.
	(row["values"] as GSStatsValues).merge_from(incoming, p_schema)

	# A copy: two callers holding the store's own set are two writers to it.
	return GSResult.success((row["values"] as GSStatsValues).duplicate_values())


func values_for(player_id: StringName) -> GSResult:
	var row: Variant = _rows.get(player_id)
	if not (row is Dictionary):
		return GSResult.success(GSStatsValues.new())
	return GSResult.success(((row as Dictionary)["values"] as GSStatsValues).duplicate_values())


func top(stat_key: StringName, limit: int = 10, offset: int = 0) -> GSResult:
	var ordering := _ordering(stat_key)
	if not ordering.ok:
		return ordering
	var ascending: bool = ordering.value

	var held: Array = []
	for id in _rows:
		var values: GSStatsValues = (_rows[id] as Dictionary)["values"]
		if values.has(stat_key):
			held.append({"player": String(id), "name": str((_rows[id] as Dictionary)["name"]), "value": values.get_value(stat_key)})

	# Ties broken by player id only so a page boundary is stable between two reads, the same
	# as the SQL store's ORDER BY; the rank below is what says they are tied.
	held.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["value"] == b["value"]:
			return a["player"] < b["player"]
		return a["value"] < b["value"] if ascending else a["value"] > b["value"]
	)

	for i in range(held.size()):
		if i > 0 and held[i]["value"] == held[i - 1]["value"]:
			held[i]["rank"] = held[i - 1]["rank"]
		else:
			held[i]["rank"] = i + 1

	var start := maxi(offset, 0)
	return GSResult.success(held.slice(start, start + maxi(limit, 0)))


func rank_of(stat_key: StringName, player_id: StringName) -> GSResult:
	var ordering := _ordering(stat_key)
	if not ordering.ok:
		return ordering
	var ascending: bool = ordering.value

	var row: Variant = _rows.get(player_id)
	if not (row is Dictionary) or not ((row as Dictionary)["values"] as GSStatsValues).has(stat_key):
		return GSResult.success(0)

	var mine := ((row as Dictionary)["values"] as GSStatsValues).get_value(stat_key)
	var ahead := 0
	for id in _rows:
		var values: GSStatsValues = (_rows[id] as Dictionary)["values"]
		if not values.has(stat_key):
			continue
		var theirs := values.get_value(stat_key)
		if (theirs < mine) if ascending else (theirs > mine):
			ahead += 1

	return GSResult.success(ahead + 1)


func remove_player(player_id: StringName) -> GSResult:
	return GSResult.success(_rows.erase(player_id))


func size() -> int:
	return _rows.size()


func clear() -> void:
	_rows.clear()


func describe() -> Dictionary:
	var out := super.describe()
	out["players"] = _rows.size()
	return out

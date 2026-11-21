class_name GSStatsStore
extends RefCounted

## Where a player's LIFETIME values live, on the server's side. Subclass point.
##
## [b]What this is for.[/b] The tracker counts a session and sends deltas to the backbone,
## which keeps the totals. A server with no backbone — a LAN, a community that has not
## linked an integration, a game still in development — had nowhere to keep a total at all:
## every number a player earned ended with their session. A store is that somewhere, fed by
## the same deltas at the same moment the reporter is, so a server with both keeps both and
## the two cannot drift apart by when they were told.
##
## [b]The merge rule is not written here.[/b] Every implementation folds a delta in with
## [method GSStatsDef.merge] — the addon's one rule, which the reporter and the backbone
## also follow. A store that spelled it again in SQL (`amount + ?`, `GREATEST`, `LEAST`) would
## be a fifth copy of the rule in a fourth language, and docs/design.md is explicit about what
## two copies disagreeing costs: a number that is wrong without anything having failed.
##
## [b]Everything returns a [GSResult] and every method may be a coroutine[/b]; always
## [code]await[/code]. The interesting implementations are remote.
##
## [b]Ordering comes from the kind.[/b] [method top] and [method rank_of] read the stat's
## definition in [member schema]: a [constant GSStatsDef.Kind.LOWEST] stat ranks ascending,
## every other kind descending. A tie shares a rank (1, 2, 2, 4).

## The definitions [method top] and [method rank_of] order by, and [method merge] falls back
## to when it is not handed one. The tracker sets it.
var schema: GSStatsSchema = null


## Folds [param values] into a player's lifetime totals, stat by stat, by each stat's kind.
## Returns the player's totals afterwards, as [GSStatsValues].
##
## [param values] is a [GSStatsValues] or a [Dictionary] of readings; a dictionary goes
## through [method GSStatsValues.from_dictionary], which drops anything that is not a finite
## number. A stat [param p_schema] does not declare is skipped: there is no rule to merge it
## by. [param player_name] is kept beside the values, for a ranking somebody reads.
##
## [b]On failure, [code]error.context["unapplied"][/code] says what did not land[/b], as a
## dictionary of readings, when a store applies stat by stat and failed part-way. A caller
## retrying the whole delta would otherwise add a counter twice. Absent means none of it.
func merge(
	player_id: StringName, values: Variant, p_schema: GSStatsSchema = null, player_name: String = ""
) -> GSResult:
	var rules := p_schema if p_schema != null else schema
	if rules == null:
		return GSResult.fail(GSError.CODE_STATE, "A stats store needs a schema to merge by.")
	if schema == null:
		schema = rules
	if String(player_id) == "":
		return GSResult.fail(GSError.CODE_INVALID, "A player needs an id.")

	var incoming: GSStatsValues = null
	if values is GSStatsValues:
		incoming = values
	elif values is Dictionary:
		incoming = GSStatsValues.from_dictionary(values)
	else:
		return GSResult.fail(GSError.CODE_INVALID, "Values are a GSStatsValues or a Dictionary.")

	# Only what the schema can merge, and only finite numbers. A GSStatsValues built by
	# record() is both already; one built by hand might not be.
	var known := GSStatsValues.new()
	for id in incoming.values:
		var reading := float(incoming.values[id])
		if rules.has(id) and is_finite(reading):
			known.values[id] = reading
	for key in incoming.cells:
		var reading := float(incoming.cells[key])
		if rules.has(StringName(str(key).split("|")[0])) and is_finite(reading):
			known.cells[str(key)] = reading

	return await _merge(player_id, known, rules, player_name)


## Every lifetime value a player holds. An empty set, never null, for a player with none.
func values_for(_player_id: StringName) -> GSResult:
	return GSResult.fail(GSError.CODE_UNSUPPORTED, "GSStatsStore.values_for() was not overridden.")


## One stat as a ranking, best first: an [Array] of
## [code]{"player": String, "name": String, "value": float, "rank": int}[/code].
func top(_stat_key: StringName, _limit: int = 10, _offset: int = 0) -> GSResult:
	return GSResult.fail(GSError.CODE_UNSUPPORTED, "GSStatsStore.top() was not overridden.")


## A player's rank on one stat; 0 when they hold no value for it. Absent is not an error.
func rank_of(_stat_key: StringName, _player_id: StringName) -> GSResult:
	return GSResult.fail(GSError.CODE_UNSUPPORTED, "GSStatsStore.rank_of() was not overridden.")


## Forgets everything a player holds. For moderation, and for a player who asks.
## Returns whether there was anything to forget.
func remove_player(_player_id: StringName) -> GSResult:
	return GSResult.fail(GSError.CODE_UNSUPPORTED, "GSStatsStore.remove_player() was not overridden.")


## The merge itself, after [method merge] has checked and filtered. Override.
func _merge(
	_player_id: StringName, _incoming: GSStatsValues, _schema: GSStatsSchema, _player_name: String
) -> GSResult:
	return GSResult.fail(GSError.CODE_UNSUPPORTED, "GSStatsStore._merge() was not overridden.")


## Whether lower is better for a stat, from its kind; an error for a stat nobody declared.
func _ordering(stat_key: StringName) -> GSResult:
	if schema == null:
		return GSResult.fail(GSError.CODE_STATE, "A stats store needs a schema to rank by.")
	var def := schema.find(stat_key)
	if def == null:
		# Not an empty ranking: a stat with no definition has no direction, and guessing
		# one renders a "fewest deaths" board upside down.
		return GSResult.fail(GSError.CODE_INVALID, "No such stat is declared.", String(stat_key))
	return GSResult.success(def.kind == GSStatsDef.Kind.LOWEST)


func describe() -> Dictionary:
	var script: Script = get_script()
	return {
		"implementation": String(script.get_global_name()) if script != null else "?",
		"schema": schema.size() if schema != null else 0,
	}


## Writes anything a store holds back and waits for it. A no-op for a store that writes through; the tracker calls it when it exits.
func finish() -> void:
	pass

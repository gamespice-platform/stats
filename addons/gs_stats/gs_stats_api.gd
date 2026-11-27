extends RefCounted

## GameSpice Stats's API level. The rule for bumping it is on [GSAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed.
# 2: GSStatsTracker.record_later(), apply_pending(), pending_players(); GSStatsValues.fold();
#    GSStatsEventFeed.batched (hits, penetrations, wall passes and shots held until the tick's apply).
const LEVEL := 2
const OLDEST := 1

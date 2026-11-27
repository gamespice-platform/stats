# History

Bugs worth recognising if they come back.

- **Every hit cost a full record.** A 31-bot server filed four to six `record()` calls per hit, each validating, merging into two value sets, formatting cell keys and emitting `recorded`. `GSStatsEventFeed.batched` now holds hits, penetrations, wall passes and shot outcomes through `GSStatsTracker.record_later()`, and the game calls `apply_pending()` once per tick; `GSStatsValues.fold()` adds the held readings in arrival order, so totals and cells match per-hit records to the last bit (the `held readings` section compares them). Only unbounded counters are held; anything a reading could be refused for is still recorded at once. API level 2 (`gs_stats_api.gd`).
- **A leave queued rows nothing would send.** With `report_to_backbone` off (the default), `end()` still checkpointed a leaving player's delta into the reporter's queue, which then held rows no flush would ever send, and the "will not be reported why=unpublished" warning fired on the first leave of every such server. `_checkpoint` now clears the delta and returns when reporting is off, and the `tracker` section asserts a leave queues nothing and warns about nothing.
- **Every number was lost at the end of every session** on a server with no backbone, because the totals lived only there. The store ([store](store.md)) is the answer.
- **Two servers writing one player at once** is the race the `revision` guard exists for; with the guard removed, the suite's `RacingDriver` fails, and both real databases lose races in the live scene while keeping exact totals.

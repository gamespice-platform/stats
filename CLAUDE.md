# GameSpice Stats

Per-player statistics a game declares once and reports to the TMC backbone in batches: counters, gauges, bests and lowests, keyed by a pseudonymous player id, filed under an app or a server integration, and optionally kept on the server in a store.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to stats. The reasoning is in [docs/](docs/README.md).

**The distributable is `addons/gs_stats/`.** It requires gs-core and gs-save (`ln -s ../../gs-save/addons/gs_save addons/gs_save`, gitignored; the file store lives there) (symlinked, `.gitignore`). gs-auth, gs-leaderboard and gs-sql are never named; gs-sql is linked only for the suites.

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/design.md](docs/design.md) | `GSStatsDef`, `GSStatsSchema`, `GSStatsValues`, `GSStatsTracker`, `GSStatsClient` |
| [docs/store.md](docs/store.md) | any `GSStatsStore`, `GSStatsSqlSchema` |
| [docs/backbone.md](docs/backbone.md) | `GSStatsReporter`, credentials, anything the site receives |
| [docs/history.md](docs/history.md) | the bugs, and how each looked |

## Layout

| Path | What |
| --- | --- |
| `addons/gs_stats/core/` | `GSStatsDef` (one stat; `merge()` is the rule), `GSStatsSchema` (every stat a game keeps; the wire shape of define), `GSStatsValues` (one player's values; refuses NaN) |
| `addons/gs_stats/net/` | `GSStatsReporter`: coalesces per player, batches, keeps its queue on failure |
| `addons/gs_stats/store/` | `GSStatsStore` (abstract; ordering from the kind), memory, SQL via GameSpice SQL, `GSStatsSqlSchema` |
| `addons/gs_stats/runtime/` | `GSStatsTracker` (the Node: begin/record/end per player, a timer, a final flush), `GSStatsClient` (a player reporting their own figures) |
| `examples/stats_selftest.tscn` | the suite; all offline |
| `examples/stats_sql_live.tscn` | the SQL store against real databases |

## Running and testing

- The family's two steps ([family CLAUDE.md](../../CLAUDE.md#validating-anything)), then `godot --headless --path . res://examples/stats_selftest.tscn`.
- Anything in the SQL store: `../gs-sql/tools/test_live.sh . res://examples/stats_sql_live.tscn` (SQLite always; Postgres and MySQL with `GS_SQL_PG_DSN` / `GS_SQL_MYSQL_DSN`).
- The backbone client is faked one level above HTTP (a class with `post_integration`), which is the seam the addon promises.
- **Add a case for any change to the merge rule, the coalescing or the queue**: there a bug is a wrong number, not a crash.

## Rules that bite

- The kind is the contract: `COUNTER` adds, `GAUGE` replaces, `BEST` keeps higher, `LOWEST` keeps lower; a first reading stands. A kind never changes; declare a new key. [design](docs/design.md#the-kind-is-the-whole-contract)
- The merge rule lives in `GSStatsDef.merge` and runs in the tracker, the reporter and the site; reports are deltas. Never spell it again, in SQL or anywhere. [design](docs/design.md#the-kind-is-the-whole-contract)
- `GSStats*`, never `GSStat*`, and never GameSpice Leaderboard's `GSStatSet`. [design](docs/design.md#what-this-is-and-what-it-is-not)
- `report_to_backbone = false` never touches the reporter. [design](docs/design.md#the-tracker)
- The tracker runs only where the integration credential is; never in a client build. Competitive figures stay on the tracker; `GSStatsClient` is a diary and cannot declare. [design](docs/design.md#two-surfaces-and-which-to-use)
- A store gets the same deltas at the same checkpoint as the reporter; assign it before `add_child`. [store](docs/store.md#fed-the-same-deltas-at-the-same-moment)
- The SQL store reads, folds with `merge`, and writes guarded by `revision`; a first value is a plain INSERT. [store](docs/store.md#the-rule-stays-in-one-place)
- A partial store failure names `unapplied`, and only that is re-queued, under newer checkpoints. [store](docs/store.md#a-partial-failure-names-what-did-not-land)
- Ranking direction comes from the kind; ties share a rank; ranking an undeclared stat is refused. [store](docs/store.md#ordering-comes-from-the-kind)
- The reporter coalesces per player, bounds by players dropping the oldest, keeps its queue on failure, and logs a 403 with `STATS_WRITE`. [backbone](docs/backbone.md#three-properties-each-the-answer-to-a-lost-report)
- `publish` is off by default per stat; unpublished or undeclared readings are skipped with one warning. [backbone](docs/backbone.md#three-properties-each-the-answer-to-a-lost-report)
- The player id is a scoped pseudonym; the reporter refuses an account-shaped uid before it leaves the process. [backbone](docs/backbone.md#the-player-id-is-a-pseudonym-and-the-reporter-enforces-it)
- v2 declarations add `type`, `min`/`max`, `max_rate`, up to four `breakdowns` (weapon, map, or a joint axis such as `weapon_zone`; cells are never crossed, so a joint axis is how one weapon's zones are shown), a derived stat (ratio, difference, sum, per_minute over two stored stats, never stored), display hints and `source` (server or client; the site refuses client submissions for server stats). A v1 declaration loads unchanged.
- Breakdown cells merge by the stat's own kind; `set_context` supplies axes a record omits, and `event()` runs `rules` (event to stat, `when`/`unless` tags, a value field or callback).
- With `log_events`, `drain_events()` returns append-only rows `{session, player, is_bot, stat, dims, value, t}`; sessions are first-class (`session_info`, `session_ended`). Bots (`begin` meta `is_bot` or `bot_check`) never carry a linked-user claim; `tmc_user` is kept only with `link_tmc_user`.
- The reporter posts `stats/v2/submit` (sessions, per-player `by` cells, frozen batch id resent unchanged). The tracker enforces `max_rate`; `GSStatsClient` refuses server-source stats; the SQL store has a `dim` column (key player, stat, dim). GameSpice Game and GameSpice Bot do not call the tracker yet, so they must pass `is_bot` in `begin` meta or set `bot_check`.
- The reporter sends a UUID batch id and resends an unacknowledged batch unchanged under it. Session ids go out as UUIDs (`GSStatsReporter.wire_session_id`: a UUID passes, anything else maps to a stable one). `examples/fixtures/gs_submit_v2.schema.json` mirrors the site validator and the selftest checks the real payload against it; refresh it when `gsstats/payload.ts` changes.

Deliberately not here: app-wide totals across servers, server-level figures, anti-cheat, a tracker in GameSpice Server. [design](docs/design.md#deliberately-not-here)

- Penetration stats: `GSStatsPenetration.declare(schema)` then `GSStatsEventFeed.report_penetration(...)` (or `bind_penetrations`).
- Wall cost stats (`penetration_cost`, `penetration_passes`, axes `material`, `weapon_material`): `GSStatsPenetration.declare_walls(schema)`, then `GSStatsDamage.report_shot(feed, shot)` from `shot_resolved` (reads GameSpice Combat's `shot.penetrations`, each with `material` and `cost`).
- One damage record to both: `GSStatsDamage.report(feed, damage)` files the zone hit and the wall/body/ricochet penetration from a `GSDamage` (duck-typed, no GameSpice Combat dependency).
- Per-zone hit stats: `GSStatsHitzones.declare(schema)` then `GSStatsEventFeed.report_hit(...)` (or `bind_hits`); a game supplies the damage event, never copies the recording.
- Per-player progress base: `GSStatsPlayerProgress` (extend it; override `_make_schema`, `_make_catalogue`, `_rank_terms`; call `record` from your `on_*` handlers). Never copy the key mapping, `record`, `leave` or `set_reporting` into a game. See [design](docs/design.md#per-player-progress-base).

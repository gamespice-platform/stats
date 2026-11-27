[![Stats - GameSpice addon](docs/banner.png)](https://moddingcommunity.com/a/13-gs-stats)

Per-player statistics a game declares once and reports in batches. Counters, gauges, bests and lowests are merged by a rule the game states, and filed to the TMC back end without a server ever handing over an account id.

GameSpice addon under the MIT licence, built with Claude Code, with a headless suite in `examples/stats_selftest.tscn`. The games in [Zee's Games](https://zeesgames.com) run on live servers built from GameSpice addons, and they report their player statistics through this one. Bug reports go to the [issue tracker](https://github.com/gamespice-platform/stats/issues).

State the merge rule once per stat (add, replace or keep the better) and every party applies it the same way: the server counting, the reporter batching and the site storing.

## Install

1. Get [Godot 4.7](https://godotengine.org/download).
2. Either use [GameSpice Bootstrap](https://github.com/gamespice-platform/bootstrap), which clones every project and links the addons, or copy `addons/gs_stats/` and [GameSpice Core](https://github.com/gamespice-platform/core)'s `addons/gs_core/` into your project and enable gs-stats in *Project > Project Settings > Plugins*.

GameSpice Core and [GameSpice Save](https://github.com/gamespice-platform/save) (copy its `addons/gs_save/` beside `gs_core`) are the dependencies. [GameSpice Auth](https://github.com/gamespice-platform/auth) is optional and supplies the two clients (`GSBackboneClient` for a server, `GSAuthClient` for a player).

## Use

```gdscript
var schema := GSStatsSchema.new()
schema.define(&"kills").publish = true
schema.define(&"top_speed", GSStatsDef.Kind.BEST, "Top speed").publish = true
schema.define(&"level", GSStatsDef.Kind.GAUGE)          # kept, never reported

var tracker := GSStatsTracker.new()
tracker.schema = schema
tracker.report_to_backbone = true
tracker.reporter.client = backbone      # gs-auth's GSBackboneClient
add_child(tracker)

tracker.begin(player_key, display_name) # the scoped key, never the account id
tracker.record(player_key, &"kills")
tracker.record(player_key, &"top_speed", 41.2)
tracker.end(player_key)                 # reports the last delta, forgets them
```

Every `report_interval` seconds (default 30) and once more on shutdown, the tracker sends each player's delta since the last report, such as `{"kills": 3, "top_speed": 41.2}`. The site merges each by its kind.

## Lifetime totals on the server

```gdscript
var store := GSStatsStoreSql.new(driver)   # any gs-sql driver; or GSStatsStoreMemory
await store.open()                          # creates or migrates its table
tracker.store = store                       # before add_child
```

Each reported delta is also merged into the store by the same rule, so a server with no back end still keeps every player's totals. The store answers `values_for(player)`, `top(stat, limit, offset)` (a `LOWEST` ascending, the rest descending, ties sharing a rank), `rank_of(stat, player)` and `remove_player(player)`.

`GSStatsStoreSql` speaks SQLite, PostgreSQL and MySQL/MariaDB through [GameSpice SQL](https://github.com/gamespice-platform/sql), without needing it to parse. Writes are guarded by a revision, so two servers sharing a table add up instead of overwriting. A failed write is kept for the next flush and never counts a counter twice.

## Player-reported stats

A player's own client can report its own figures with the player's token and no integration credential:

```gdscript
var mine := GSStatsClient.new()
mine.schema = schema
mine.client = auth_client        # gs-auth's GSAuthClient
add_child(mine)

mine.record(&"launches")
var held := await mine.fetch_mine()
```

Both land on the same rows. Keep anything competitive on the server; this is for a diary.

## Stat catalogue file

`tools/export_site_defs.gd` writes a game's published stats as the site's `gs-stat-defs` JSON, from the schema the game really builds, so the site owner imports it instead of retyping it. Run it from the game project with Godot headless as a script, passing `--source` (a script path), `--method` (the function returning the `GSStatsSchema`) and `--out`.

| Option | Does |
| --- | --- |
| `--check` | Writes nothing and exits 1 when the file on disk is stale. |
| `--game <id>` | Pins the site app id. Left out by default so one file imports anywhere. |

The file is `GSStatsSchema.to_site_defs()`. A scaled `difference` is skipped with a warning, because the site's diff ignores scale.

## Testing

Import the project once, then run `examples/stats_selftest.tscn` headless with Godot. `examples/stats_sql_live.tscn` runs the SQL store against real databases through `../gs-sql/tools/test_live.sh`. More in [docs/](docs/README.md).

## Used by

All of these games from Zee's Games vendor this addon:

- [Fatal Contact](https://zeesgames.com/fatal-contact)
- [Airdrift](https://zeesgames.com/airdrift)
- [Playlot](https://zeesgames.com/playlot)
- [Hungario](https://zeesgames.com/hungario)
- [Buses From Hell](https://zeesgames.com/buses-from-hell)
- [Smash Copter](https://zeesgames.com/smash-copter)
- [Zombie Zone](https://zeesgames.com/zombie-zone)
- [Hide n Seek](https://zeesgames.com/hide-n-seek)
- [Prop Hunt](https://zeesgames.com/prop-hunt)
- [Murder Mystery](https://zeesgames.com/murder-mystery)
- [Deathrun](https://zeesgames.com/deathrun)
- [Wipeout](https://zeesgames.com/wipeout)
- [Dangerous Delivery](https://zeesgames.com/dangerous-delivery)
- [Look At Me](https://zeesgames.com/look-at-me)

The whole collection is at [zeesgames.com](https://zeesgames.com).

## Licence

MIT licence, see [LICENSE](LICENSE). The only closed part of the [**GameSpice**](https://gamespice.net) platform is the web back end; you can use your own instead of GameSpice's.

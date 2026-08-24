# Changelog

All notable changes to Gen1ModMenu are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this mod uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-24

### Added

- **The mod manager, redrawn.** `MODS` is drawn by this mod instead of the
  engine: the mod list carries a status column and grouping rules, the detail
  and PENDING CHANGES screens size themselves to their contents, and the
  per-mod OPTIONS page lists eleven options at once instead of four.
- **A readable OPTIONS page.** Vanilla renders it through
  `src/ui/OptionRows.lua` as four bordered 20x4 boxes, label on one line and
  value on the next. Here each option is a single line — label left, value
  right — with the mod's name and version above them and a line below saying
  what the focused row accepts, read off the schema (`ON / OFF`, `1-8`,
  `UP TO 12 CHARS`).
- **Sorting and filtering.** `SORT BY` orders the list by `CATEGORY` (what
  the engine does, plus a stable order inside each group), `NAME`, `ENABLED`
  or `PROBLEMS`. `HIDE OFF` drops disabled mods and `ONLY W/OPTIONS` drops
  the ones with nothing to configure. Neither filter can hide Gen1ModMenu
  itself, because its own options page is where they are set.
- **`RESET DEFAULTS`** on every mod's options page, restoring each row to the
  value its author shipped. A `.` beside a value marks a row that differs
  from that default.
- **A mark legend** on the `ERRORS` tab whenever there is nothing wrong,
  spelling out `ON`, `OFF`, `STGD`, `ERR`, `BLKD` and `SKIP`.
- **`KEEP CURSOR`**, which reopens the manager on the row it was left on.
- A ROM-free headless test suite, including a tier that runs the renderer
  itself against the engine's real font and asserts every draw lands inside
  the box and spells only characters the Game Boy charmap carries. CI runs
  `modkit validate`, `lint`, `gen2check` and the suite on every push.

### Fixed

- **The OPTIONS page on Gold.** The engine draws it through
  `src/ui/OptionRows.lua`, which its own loader lists as Gen 1 only — it
  "paints Red's chrome over Gold's options screen, whose layout is one 18x16
  box rather than four 20x4 ones". Drawing the rows here rather than through
  it makes the page right on Gold as well.
- **A detail screen that ran off the bottom.** Vanilla starts the action rows
  at tile 11 and draws one per line, so a mod carrying all nine of them
  (`ENABLE`, `OPTIONS..`, `PERMISSIONS..`, the Gen 2 override, `FOR`, `GH`,
  `EXPERIMENTAL`, `VIEW ERROR..`, `BACK`) puts its last row at tile 19 of an
  18-tile screen. The rows are pinned to the bottom here and the description
  takes what is left.

### Notes

- Nothing about the manager's behaviour changes. Enabling and disabling,
  dependency closures, staged changes, apply-and-restart, profiles, the Gen 2
  override and safe mode are all still the engine's; this mod replaces the
  drawing and nothing else.
- `PRESENTATION: VANILLA` hands every screen straight back to the engine's
  own renderer, and a renderer that ever throws is demoted to it for the rest
  of the visit. On top of both, the engine's own `Screens.build` falls back
  to its builtin manager if this mod's screen cannot be constructed.

[0.1.0]: https://github.com/wild1walker/Gen1ModMenu/releases/tag/v0.1.0

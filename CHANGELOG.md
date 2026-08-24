# Changelog

All notable changes to Gen1ModMenu are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this mod uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-24

Redrawn again, this time in the game's own OPTION-screen idiom rather than in
one invented for the mod.

0.1.x fitted eleven rows on a screen by giving each one a single line to share
between a name and a value. It survived every guard and still read as a dense,
clipped table -- `Gen1AutoContin`, `PRESENTATI` -- because eighteen columns
minus a status word is not enough for either half.

### Changed

- **The mod list and the per-mod options page are drawn as framed cards**,
  using the same geometry `src/ui/OptionRows.lua` uses for `TEXT SPEED` and
  `BATTLE ANIMATION`: four full-width 20x4 boxes down the screen, the label on
  the first line inside each and its value indented on the second, the cursor
  in the margin beside the label. A card holds two whole lines, of 17 and 16
  glyphs, so nothing on either screen is cut short any more.
- **The mod list shows four mods at a time instead of eleven.** That is the
  price of the layout, and it is why the position counter, the sorts and the
  filters are all still there.
- **A card's second line carries the category on the left and the status on
  the right**, so category headings are gone -- a heading would have cost one
  of the four cards, and the sort still groups the list whether or not it says
  so out loud.
- **The `CHANGED` marker is a word again**, not a `.`; it is right-aligned on
  the value line, where a card has room for it.
- **The `ERRORS` tab stays plain lines in a framed window.** It is wrapped
  prose and a mark legend, and a card per line of a wrapped sentence would be
  absurd.

### Removed

- **Every control hint.** `A:OPEN SEL:TOGGLE`, `START:APPLY B:EXIT`,
  `L/R:CHANGE B:DONE` and the rest are gone. Each screen is A to choose, B to
  go back and the d-pad to move, the same as every other menu in the game, and
  two of the sixteen lines spent restating that were two the cards wanted more.

### Fixed

- **A notice and the caption shared a line.** The tabs and a message like
  `SAFE MODE ACTIVE` both wanted the bottom row; the tabs now stand down while
  a notice is up, rather than being painted over and only looking right by
  accident. Caught by the overlap guard added in 0.1.1.

## [0.1.1] - 2026-08-24

Layout fixes, from seeing 0.1.0 on a real screen. Three things were drawn on
top of each other and one was drawn off the end of its line, none of which the
0.1.0 suite could see: it asserted that every draw landed inside the box, and
all four of these did.

### Fixed

- **The position counter was drawn through the tab line.** `[MODS] PROF ERRS`
  is 16 glyphs of a 17-glyph run, so `2/16` landed on top of `ERRS` and the
  row read `E2R16`. The counter moves to the title line, beside `MOD MANAGER`.
- **The scroll arrow was drawn through the footer**, turning
  `A:OPEN SEL:TOGGLE` into `TOGGL`. The arrow is gone; the counter says where
  you are.
- **`START:APPLY B:EXIT` lost its last letter.** It is 18 glyphs and the box
  interior is 18 columns, but footers were drawn at column 2 — the column
  reserved for the row cursor, which a footer does not have. Footers now start
  at column 1, where the vanilla-length hints fit. `DECLARED BY AUTHOR,` lost
  its comma for the same reason.
- **`N MORE` on PENDING CHANGES** was drawn on the last staged mod's own
  `ON`/`OFF`. It gets its own line now.
- **The options page drew its scroll arrow on a rule.** The arrow is replaced
  by a position counter in the header, which takes the version's place only
  while the list actually scrolls.
- **Labels that could not fit beside their own values.** `PRESENTATION` is
  12 glyphs and `MODERN` is 6, which is 19 of the 17 a row has, so the row
  read `PRESENTATI`. It is now **`STYLE`**, and `ONLY W/OPTIONS` is
  **`WITH OPTIONS`**. Two legend meanings were one glyph over and are
  shortened: `NEEDS RESTART` to `RESTART`, `FAILED TO LOAD` to `LOAD FAILED`.
- **A choice row's help line ended on a dangling separator** —
  `CATEGORY / NAME /` — because it was cut by width. Whole values come off the
  end now, so the line always finishes on a real one.

### Changed

- **A mod that is enabled and running carries no mark.** A column reading `ON`
  down the whole screen is not information, and blanking it gives every name
  three more glyphs — the difference between `Gen1AutoContinue` and
  `Gen1AutoConti`. The marks are the exceptions, and they stand out now. This
  is the same rule the engine's own `glyphFor` uses, where a healthy mod
  answers a blank. The `ERRORS`-tab legend leads with what the absence means.

### Added

- **Three guards, each checked by breaking it on purpose.** Nothing may be
  drawn on top of anything else; every fixed string the screen says must fit
  the row it is drawn on (they are all in one `Skin.STRINGS` table now); and
  every option label must fit beside its own widest value. The first two
  reproduce the exact bugs above. A mod *name* is exempt — it is data and can
  be any length — but the suite asserts that when one cannot fit beside its
  mark, it is the name that gives way and the mark that survives.

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

[0.2.0]: https://github.com/wild1walker/Gen1ModMenu/releases/tag/v0.2.0
[0.1.1]: https://github.com/wild1walker/Gen1ModMenu/releases/tag/v0.1.1
[0.1.0]: https://github.com/wild1walker/Gen1ModMenu/releases/tag/v0.1.0

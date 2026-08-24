<p align="center">
  <a href="https://wild1walker.github.io/Gen1Wild/"><img src="docs/banner.png" alt="Gen1Wild" width="400"></a>
</p>

<h1 align="center">Gen1ModMenu</h1>

<p align="center">
  <a href="https://wild1walker.github.io/Gen1Wild/"><img src="docs/lineup.png" alt="Check out my other mods!" width="880"></a>
</p>

<p align="center">
  <b>The mod manager, made readable</b>
</p>

A UI mod for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp): it
redraws the in-game **MODS** screen. The mod list gets a status column,
sorting and filters; the per-mod **OPTIONS** page gets a help line and a
`CHANGED` marker — all in the same framed-card idiom the game's own OPTION
screen uses.

Works on Red, Blue, Yellow and Gold/Silver (mod api 2). Nothing about how the
manager *behaves* changes — enabling, dependency closures, staged changes,
apply-and-restart, profiles and safe mode are all still the engine's. This
mod draws them.

## Install

1. Download `gen1_mod_menu-<version>.zip` from
   [Releases](https://github.com/wild1walker/Gen1ModMenu/releases).
2. In the game: **MODS → Import mod .zip**, pick the file, enable
   Gen1ModMenu.

The manifest already carries `"github": "wild1walker/Gen1ModMenu"`, so the
launcher offers updates and other versions on its own.

## The look

Both list screens are drawn in the game's own **OPTION-screen idiom** — the
same geometry `src/ui/OptionRows.lua` uses for `TEXT SPEED` and
`BATTLE ANIMATION`: full-width framed cards down the screen, the label on the
first line inside each and its value indented on the second, the cursor in the
margin beside the label.

A card holds two whole lines, of 17 and 16 glyphs. That is what makes these
screens readable — every mod name and every option value is shown in full,
because neither has to share a row with the other.

```
+------------------+     +------------------+
| Gen1AutoContinue |     | SORT BY          |
|   QOL            |     |   CATEGORY       |
+------------------+     +------------------+
```

On the mod list the second line carries the mod's **category** on the left and
its **status** on the right. A mod that is enabled and running shows no status
at all — the column is for the exceptions:

| Status | Reads |
| --- | --- |
| *(blank)* | enabled and running |
| `OFF` | disabled |
| `STGD` | changed, waiting on a restart |
| `ERR` | failed to load |
| `BLKD` | a dependency is not satisfied |
| `SKIP` | enabled and fine, but not for this game |

The full word is always one A-press away, on the mod's own detail screen —
`ENABLED`, `DISABLED`, `FAILED`, `BLOCKED`, `NOT THIS GAME`.

**All three tabs** — `MODS`, `PROF` and `ERRS` — are drawn this way, and so
is a mod's options page.

The list is banded the way **Gen1BillsBox** bands its storage screen — a
header box across the top, the rows under it, and an info box at the bottom
naming what the cursor is on. Same geometry as that mod's own header: a
full-width three-tile box, the text a column inside it, and a value
right-aligned to x=144.

The header names the page you are on. Left and right move between `MODS`,
`PROFILES` and `ERRORS`, and **wrap** at both ends.

```
+------------------+
| MODS        5/12 |
+------------------+
+------------------+
| Gen1AutoContinue |
+------------------+
+------------------+
|>Gen1Dex      BLKD|
+------------------+
    ...
+------------------+
| UI       BLOCKED |
+------------------+
```

**A mod's options page wears the same three bands**: the header names the mod
being edited with the position count beside it, and the info box under the
cards carries the help line for whichever row the cursor is on.

```
+------------------+
| Gen1ModMenu  2/8 |
+------------------+
+------------------+
|>SORT BY          |
|   CATEGORY       |
+------------------+
    ...
+------------------+
| CATEGORY / NAME  |
+------------------+
```

A list row is one thing — a name — so it is a single-line box and four fit
between the bands. An option row is two things, a label and its value, so it
keeps the four-tile card the game's own OPTION screen uses, and three of
those fit.

The info box always names what the cursor is on: the focused mod's category
and its state in words on the list, the focused option's help line on an
options page. Anything else names itself there, which is also how a label too
long for its own line gets shown in full.

A mod's options page keeps its caption at the bottom instead, because that
line names the mod being edited — it says where you are rather than being
something you navigate — and it leaves room above it for the help line.

A row that carries no readable label — a profile saved without a name — draws
as `(NO NAME)` rather than as an empty box.

There are **no control hints**. Every screen here is A to choose, B to go
back and the d-pad to move, the same as every other menu in the game.

## The options page

On a mod's options page the second line is the value, with `CHANGED`
right-aligned against it on any row you have moved off the author's default.
Below the cards, a help line for whichever row the cursor is on, read straight
off the schema:

| Row type | Help line |
| --- | --- |
| toggle | `ON / OFF` |
| choice | every choice label, `ONCE / N BEEPS / VANILLA` |
| number | the range, `1-8`, and the step when it is not 1 |
| text | `UP TO 12 CHARS` |

The last card is **`RESET DEFAULTS`**, which puts every row back to what its
author shipped. That row is the *engine's* — `ManagerState:buildOptionRows`
appends it to every options page on its own. All this mod adds to it is the
help line.

There is no description field in the engine's option schema
(`docs/mod-option-schema.md` is `key`, `type`, `label`, `default`, `choices`,
`min`, `max`, `step`, `maxLen`, `visible_if`), so the help line says what the
row *accepts* rather than inventing prose the author never wrote.

## The list menu

**START** on the `MODS` tab opens a menu: the focused mod's `ENABLE` /
`DISABLE`, the four sort orders with the active one bracketed, and the two
filters showing their own state.

```
+-----------------+
| DISABLE         |
| BY CATEGORY     |
|[BY NAME]        |
| BY ENABLED      |
| BY PROBLEMS     |
| HIDE OFF: OFF   |
| W/OPTIONS: OFF  |
+-----------------+
```

**SELECT** applies staged changes — it is what `START` used to do, and it
reaches the same `APPLY & RESTART` screen by calling the engine's own
handler, so safe mode and the `NO CHANGES` notice behave exactly as before.

The two keys traded jobs because the manager has no spare ones: up and down
are the cursor, left and right the tabs, A opens and B goes back. Nothing was
lost in the trade — vanilla's `SELECT` quick-toggle is the menu's first row
and the cursor opens on it, so `START` then `A` is that same toggle one
keypress later.

Only on the `MODS` tab. `PROFILES` spends both keys itself (`START` deletes a
profile, `SELECT` renames one), the `ERRORS` tab keeps `START` as a second
way to `APPLY`, and the detail screen keeps `SELECT` for toggling the mod it
is showing.

## Outside the manager

Two smaller edits, both switched off by `STYLE: VANILLA` along with
everything else.

- **The START menu row reads `MOD MENU`.** The engine already puts a row
  there, gated on at least one mod being installed, and labels it `MODS` —
  this renames that row rather than adding a second one beside it. It is
  matched on the label the engine would have produced, so a translation mod
  that rewrote `MODS` is still recognised, and it is renamed at the default
  hook priority so Gen1MenuManager can still move, hide or pin it like any
  other row.
- **`CANCEL` is gone from the game's own OPTION screen.** It was never one of
  the rows — the engine appends it after the `ui.options.rows` hook and draws
  it as the fixed bottom line, which is what stops a mod from orphaning the
  exit. It is also not the only exit: **B and START both leave that menu**,
  with the same sound and the same pop. So the line goes back to the screen.

  The wrapper that does this never touches input. The engine's own update
  runs first and in full every frame; all that happens afterwards is that a
  cursor parked on the row that is no longer drawn gets moved onto one that
  is. A bug in there can misplace the cursor — it cannot take away the way
  out.

  **Gen 1 only.** Gold's options screen is a different screen
  (`Gen2OptionsMenu`) with a different layout — one 18×16 box rather than
  four 20×4 ones — so it is left alone rather than have Red's chrome painted
  over it.

## Options

All under **MODS → Gen1ModMenu → OPTIONS**.

- **STYLE** — `MODERN` or `VANILLA`. `VANILLA` hands every screen
  straight back to the engine's own renderer, and it is read on every frame,
  so the row takes effect without leaving the screen.
- **SORT BY** — `CATEGORY` (what the engine does, plus a stable order inside
  each group), `NAME`, `ENABLED`, or `PROBLEMS` — which floats errored and
  blocked mods to the top.
- **HIDE OFF** — drop disabled mods from the list.
- **WITH OPTIONS** — show only the mods that have something to configure.
- **HELP LINE** — what the info box under a mod's options shows: the focused
  row's help line, or its full label when off.
- **START ROW** — label the START menu's row `MOD MENU` instead of `MODS`.
- **HIDE CANCEL** — drop `CANCEL` from the game's own OPTION screen.
- **KEEP CURSOR** — reopen the manager on the row you left it on.

Neither filter can hide Gen1ModMenu itself. Both are set from its own options
page, and that page is reached through the list they filter.

## How it works, and how it gets out of the way

The engine's manager is `src/mods/ManagerState.lua`, and there is no hook on
it. What it does have is a screen id: `src/ui/Screens.lua` resolves
`"ManagerState"` out of the registry *before* falling back to its own
builtin, so registering that id replaces the screen on every route in — the
START menu, the OPTION screen, `F10`, and Gold's own push.

What this mod hands back is the engine's own instance with its draw methods
swapped. The thousand lines behind the screen — `resolveToggle`'s dependency
closure, staged changes, apply-and-restart, profiles, the Gen 2 override,
safe mode — are untouched, because a divergence there does not look like a
skin bug, it looks like a boot that no longer comes up. Reaching the builtin
means requiring it by name, which is the whole reason the manifest declares
`engine_internals`; nothing here patches engine code in place.

This is the one screen a player uses to switch off a mod that is
misbehaving, so there are three independent ways back to the vanilla one:

1. **`STYLE: VANILLA`**, read on every call.
2. **A renderer that throws** is logged once and demoted to the engine's own
   draw for the rest of the visit.
3. **`Screens.build` already pcalls a mod screen's `new`** and falls back to
   the builtin, so a mod that cannot construct its screen at all leaves the
   manager exactly as it was.

## What it does not touch

- **The launcher's mod-options screen** (`src/import/LauncherSettings.lua`)
  is a different screen, outside the game, where no mod is loaded. No mod can
  reskin it.
- **Link play** — `affects_link: false`. This only draws a menu.
- **Your saves** — the mod stores nothing in them. Its own settings are
  option rows, which is what lets them work on the title screen too, before a
  playthrough has been adopted.

## Layout

- `manifest.json` — identity, version, load order
- `main.lua` — the entry chunk; loads the modules below through `mod:read`
- `src/options.lua` — the option schema and the validating reader
- `src/rows.lua` — the list model: sorting, filtering, status words, help text
- `src/skin.lua` — the renderer
- `src/screen.lua` — registering the screen, and decorating the instance
- `tests/` — the headless suite (no ROM needed)

## Development

You need a [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) checkout.
Put this repo at `mods/gen1_mod_menu` inside it (a symlink is fine):

```sh
git clone https://github.com/wild1walker/Gen1ModMenu
ln -s "$PWD/Gen1ModMenu" path/to/gen1recomp/mods/gen1_mod_menu
```

Then, from the engine root:

```sh
python3 tools/modkit.py validate gen1_mod_menu      # manifest + real merge
python3 tools/modkit.py lint gen1_mod_menu          # no ROM-derived content
python3 tools/modkit.py gen2check mods/gen1_mod_menu
luajit mods/gen1_mod_menu/tests/gen1_mod_menu_test.lua
```

The suite is ROM-free: it merges into the engine's fixture dataset, so it
runs anywhere the engine checks out. `.github/workflows/ci.yml` runs exactly
those four commands on every push and pull request.

The last tier of the suite is worth knowing about. It runs the renderer for
real — every screen, against the engine's own `Font` and `Theme` over the
fixture data — with each draw recorded, and asserts two things about all of
them: that they land inside the box the screen is drawn in, and that they
spell only characters the Game Boy charmap carries. The charmap has no `+`,
`*`, `&`, `<`, `>` or `=`, and a character it does not carry is rendered as a
space, silently.

For the 10-minute loop, run the engine with `POKEPORT_DEV=1 love .` and press
`F5` to hot-reload after an edit.

## Releasing

Releases are cut by CI. To ship a version:

1. Bump `version` in `manifest.json`.
2. Add the matching `## <version>` section to `CHANGELOG.md` (CI fails if the
   two disagree).
3. Merge to `main`.

`.github/workflows/release.yml` then runs CI, resolves the version, packs
every mod file into `gen1_mod_menu-<version>.zip` with `manifest.json` at the
archive root, and publishes a GitHub Release with the zip and a
`sha256sums.txt`. Version resolution, first rule that applies:

1. the `version` input of a manual **Run workflow**,
2. `[release X.Y.Z]` anywhere in the commit message,
3. `manifest.json`'s own version, when it is ahead of every existing tag.

If none of the three apply, the run stops after CI and publishes nothing.
**A release is always a deliberate version bump.**

## Licence

MIT. See [LICENSE](LICENSE).

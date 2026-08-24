# Gen1Wild conventions

Written from Gen1ModMenu's build (2026-08-24) by reading Gen1SoundQOL 0.3.0,
Gen1MenuManager 0.2.2, Gen1ModernBag 1.9.1, the Gen1Wild index repo and
`bryanthaboi/gen1recomp@dev`. Nothing like this existed before, so everything
here was inferred from what the repos actually do rather than handed down.
Correct it where it is wrong; it is meant to be authoritative for the next
run of `/gen1wildmod`.

## Identity

- **Repo** `wild1walker/Gen1<Thing>` — PascalCase, no separator.
- **Mod id** snake_case with the `gen1_` prefix: `gen1_sound_qol`,
  `gen1_modern_bag`, `gen1_mod_menu`. The older mods (`Gen1MenuManager`,
  `Gen1Dex`, `Gen1BillsBox`) use the repo name as the id; the newer ones do
  not. Follow the newer ones.
- **Attribution is "Wild"** in anything public. `meta.json` carries
  `"author": "Wild"`; `mod.card` carries `"wild1walker"` as the contact
  handle. Commits land as `Claude <noreply@anthropic.com>`, same as every
  sibling — check `git config user.email` before the first commit anyway.
- Licence MIT, `Copyright (c) 2026 wild1walker`.

## File layout (Gen1SoundQOL's shape — the newest, and the one to copy)

```
manifest.json          identity, version, load order
main.lua               entry chunk; loads src/*.lua via mod:read + load
src/*.lua              one concern per file
mod.card               sharing metadata: summary, tags, differences, credits
README.md
CHANGELOG.md           Keep a Changelog + semver
LICENSE                MIT
.gitattributes         docs/ export-ignore  (and .gen1wild/ export-ignore)
.gitignore             dist/  *.zip  .DS_Store
.luarc.json            {"runtime.version":"LuaJIT","diagnostics.globals":["love"]}
.github/workflows/ci.yml
.github/workflows/release.yml
tests/<mod_id>_test.lua
docs/banner.png        the shared Gen1Wild wordmark, byte-identical everywhere
docs/lineup.png        this mod's ringed family strip, from the index repo
```

A mod's `require` is sandboxed, so its own files are loaded the supported
way: `mod:read(relative)` then `load(source, "@" .. mod.path .. "/" .. rel)`,
each step logging an attributed error rather than crashing. Copy
`main.lua`'s `loadModule` verbatim.

## manifest.json

Required-ish fields, in the order the siblings write them: `id`, `name`,
`version`, `api` (2), `entry`, `profile` (`content`), `category`,
`game_version` (`">=0.0.0-0 <2.0.0"`), `priority`, `affects_link`,
`permissions`, `dependencies`, `optional_dependencies`, `conflicts`,
`incompatible`, `games` (`["all"]`), `experimental`, `github`, `description`.

- `permissions` — `[]` wherever possible; the siblings say so in their
  READMEs. `engine_internals` is what any bare `src.*` require costs
  (`src/mods/Loader.lua` `scanRequire`), and it shows as
  "PATCHES ENGINE CODE" in the manager. Declare it honestly when you need it.
- `priority` — load order. Observed: 100 (SoundQOL), 500 (ModMenu),
  520 (ModernBag), 900 (MenuManager, which wants its menu hook outermost).

## Versioning and release

- Semver. The version lives in **two** places that must agree:
  `manifest.json` `version`, and a `## [x.y.z]` heading in `CHANGELOG.md`.
  CI fails the run if they disagree. The index repo's `meta.json` also has a
  `version`, but the feed resolves the real one from GitHub Releases, so it
  does not need bumping.
- Releases are cut by CI on **push to main**. `release.yml` calls `ci.yml`
  first, then resolves a version — dispatch input, then `[release X.Y.Z]` in
  the commit message, then `manifest.json` when it is ahead of every tag. If
  none apply the run publishes nothing and says so. **A release is always a
  deliberate version bump.**
- Artifact: `<mod_id>-<version>.zip` with `manifest.json` at the archive
  root, plus `sha256sums.txt`. Built from `git archive HEAD`, so
  `export-ignore` is what keeps art out of what players install.
- Never force-push, never retag, never clobber an existing release — the
  workflow refuses on its own.

## Merge style

Mostly direct commits on `main`, with occasional merge commits from
`claude/*` branches. A fast-forward from a working branch reads as the former
and is the safe default. No dangling branches.

## Code style

- A header comment on every file naming the **exact engine file, symbol or
  hook** it is built on, and why that seam and not another. Cite paths
  (`src/mods/ManagerState.lua`, `audio/low_health_alarm.asm`).
- Comments explain the *reasoning and the trap*, not the mechanics. Where a
  choice was forced, say what forced it.
- `pcall` around anything reaching engine state or player data; degrade to
  the vanilla behaviour and log once rather than repeatedly.
- Every knob is a row in `MODS > <Mod> > OPTIONS`, declared in a
  `src/options.lua` schema with a **validating reader** that falls back to
  the row default — a stored value can be an older version's vocabulary.
  Defaults are always the vanilla-preserving or safe answer.
- Row types the engine renders: `toggle`, `choice`, `number`, `text`. There
  is **no description field**; `visible_if` hides a row without changing its
  stored value.

## Drawing

- 20x18 tiles, 160x144 px. `mod.ui.Font` / `mod.ui.Theme`, resolved lazily so
  a headless loader never drags in the render stack. `Font.drawBox` panels,
  `Font.draw`, `Font.drawCode`, `Theme.cursor` / `cursorHollow` / `moreArrow`.
- **Measure in pixels, not glyph counts** (`Font.width`, `Font.split`,
  `Font.spansFitting`) — a font mod can ship proportional TTF glyphs. Cut on
  a glyph boundary; a plain `sub()` slices multi-byte characters in half.
- **The charmap has no `+ * ~ < > = & _ |`.** A character it does not carry
  renders as a space, silently. Test for it.
- `mod.save` is per playthrough and is rebound by `Game:adoptSave`. Anything
  reachable from the title screen must use `mod.options`, `mod.cache` or
  `mod.storage` instead.

## Tests

`tests/<mod_id>_test.lua`, run with `luajit` from an engine checkout with the
mod at `mods/<mod_id>`. `local T = require("tests.modkit")`; assertions are
`T.check` / `T.eq` / `T.same`; finish with `T.finish("<mod_id>")`. Tiers:

1. pure modules driven directly with a fake options reader;
2. the whole mod through `T.sdk.loadMod(MOD_DIR)`, asserting the manifest,
   the schema and the hook/registry wiring the way the game sees them;
3. **if the mod draws**, the renderer run for real against `T.fixtures.load()`
   plus the engine's `Font`/`Theme`, with every draw recorded, asserting both
   that it lands inside the box and that it spells only charmap characters.
   Break each guard on purpose once to prove it bites.

ROM-free throughout — the harness merges into the engine's fixture dataset.

Local loop, from an engine checkout:

```sh
python3 tools/modkit.py validate <mod_id>
python3 tools/modkit.py lint <mod_id>
python3 tools/modkit.py gen2check mods/<mod_id>
luajit mods/<mod_id>/tests/<mod_id>_test.lua
```

`luajit` is not installed by default in a fresh container: `apt-get install
-y luajit`. `make_lineup.py` needs `pip install Pillow`.

## Art — generated, never drawn by hand

Everything lives in the **index repo** (`wild1walker/Gen1Wild`):

- `tools/make_icons.py` — `mods/Wild@<id>/thumbnail.png`, 32x32 pixel art
  scaled 16x to 512x512, no resampling, no font, no disk reads, so a rebuild
  is byte-identical anywhere. Add a mod by writing one draw function and
  listing it in `ICONS`; a folder without one fails the run. Palette is fixed
  at the top of the file (`BG INK PANEL EDGE GREEN GREEN_D RED WHITE MUTED
  STEEL AMBER`) — GREEN is the house accent, AMBER and RED are the
  exceptions. Primitives: `px rect frame ellipse disc arc poly`, plus
  `polar`, `ball` and `arrow`.
  **Judge every icon at 54px**, the size the card shows: rounded shapes turn
  to mush and thin spikes read as stars.
- `tools/make_lineup.py` — `site/banners/lineup.png` and one
  `lineup-<Mod>.png` per mod with that mod ringed. Each mod repo carries its
  own as `docs/lineup.png`. **Adding a mod changes all of them**, because the
  strip gains a tile. Fetches Inter from Google Fonts into `tools/.cache/`.
- `docs/banner.png` is the shared wordmark, byte-identical in every repo —
  copy it, never regenerate it.

## Wiring a new mod into the index

In `wild1walker/Gen1Wild`:

1. `mods/Wild@<id>/meta.json` — required by the feed builder: `id`, `title`,
   `author`, `version`, `categories`, `repo`. Also carries `summary`, `tags`,
   `github`, `automatic_version_check`, `api`, `game_version`, `profile`,
   `affects_link`, `permissions`, `games`, `license`.
2. `mods/Wild@<id>/description.md` — the long-form page, structured like a
   sibling's.
3. A draw function in `tools/make_icons.py`, then run it.
4. `python3 tools/make_lineup.py`, and copy `lineup-<Mod>.png` into the mod
   repo as `docs/lineup.png`.
5. A row in the index `README.md` table, alphabetical by mod name, and the
   lineup image's `alt` text, which enumerates every mod.
6. **Do not commit `site/data/index.json`.** It is a pure function of `mods/`
   plus each mod's Releases; `index.yml` rebuilds and commits it on push,
   hourly, and on dispatch, with a token that can read the Releases API. A
   local build without one silently degrades every entry to a 403.

In the feed, top-level `version` is the `meta.json` value; the resolved
release is under `latest` (`latest.version`, `latest.zip`). A null
`download_url` at the top level is not a fault — there is no such field.

## Things that are not mods' to touch

- The **launcher's** own mod-options UI (`src/import/LauncherSettings.lua`)
  runs outside the game, where no mod is loaded.
- `src/ui/OptionRows.lua` is on the engine's `GEN1_ONLY_MODULES` list.

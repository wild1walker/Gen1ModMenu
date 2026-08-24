# Gen1ModMenu — build brief

Status: **awaiting `go`**. Nothing is built yet.
Written after Phase 0 (conventions) and Phase 2 (engine trace) of `/gen1wildmod`.

```
Mod:          Gen1ModMenu v0.1.0  (id: gen1_mod_menu)
Does:         Reskins the in-game mod manager so the mod page and the per-mod
              OPTIONS screen are readable — headers, value columns, help text,
              a legend for the status glyphs — and adds sorting and filtering
              to the mod list. No behaviour change: every toggle, dependency
              closure, profile and apply/restart stays the engine's.
```

## Verified engine facts (bryanthaboi/gen1recomp@dev)

- The screen is `src/mods/ManagerState.lua`, one stack state with six modes:
  `list` (MODS / PROFILES / ERRORS tabs), `detail`, `options`, `permissions`,
  `errors`, `apply`.
- **No hook exists for it.** The engine's hook list has `ui.start_menu.items`,
  `ui.pc.items`, `ui.options.rows`, `ui.title_menu.items` and nothing for the
  manager.
- Every route in is `Screens.push(game, "ManagerState")`:
  `src/ui/StartMenu.lua:158`, `src/ui/OptionsMenu.lua:532`,
  `src/core/Game.lua:772` (F10), `src/core/Game2.lua:452` (Gold).
- `src/core/StateStack.lua:32` emits `screen.pushed` with the constructed
  instance, after `enter()`. That is the interception point.
- `Screens.resolve` (`src/ui/Screens.lua`) prefers `game.data.screens` over the
  `BUILTIN.ManagerState` require, so `mod.content.screens:register`
  ("ManagerState", …) is the alternative mechanism. `Screens.build` degrades a
  mod screen whose `new` **throws** back to the builtin — but not one whose
  `draw` throws.
- `rowsForScreen()` recomputes from `self:modRows()` on every call and caches
  nothing, so patching `state.modRows` re-sorts the list and the cursor,
  activation and drawing all follow.
- `self.optionRows` holds the per-mod option rows built by `buildOptionRows`:
  `{ id, label, value = fn, step = fn, activate = fn }`.
- `require("src.mods.ManagerState")` is *allowed* by `Sandbox.moduleDenial`
  (only io/os/debug/package/ffi, `love.*`, `jit.*` and network modules are
  denied) but `Loader.scanRequire` attributes any bare `src.*` require to the
  `engine_internals` permission. Avoiding the require avoids the permission.
- **Gold bug:** `ManagerState:draw()` renders the options mode through
  `OptionRows.draw`, and `src.ui.OptionRows` is on the engine's own
  `GEN1_ONLY_MODULES` list — "paints Red's chrome over Gold's options screen,
  whose layout is one 18x16 box rather than four 20x4 ones". Drawing our own
  rows fixes this.
- **`mod.save` is unusable here.** The manager opens from the title screen with
  no save adopted; `loader.modSave` is rebound per playthrough by
  `Game:adoptSave`. Prefs must be `mod.options` rows or `mod.storage`.
- `mod.ui` exposes `Font`, `Theme` and the widgets without any engine require
  (`src/ui/ModUI.lua`), and `love.graphics` passes through the sandbox facade.

## Implementation (pending Q1)

Recommended: **decorate the live instance**, zero permissions.

    mod.events:on("screen.pushed", function(ev)
      local state = ev and ev.state
      if not state or state.screenId ~= "ManagerState" then return end
      -- wrap state.modRows for sort/filter; replace state.draw with ours
    end)

Alternatives considered: registering a replacement `ManagerState` screen
(total control, ~1,400 lines of toggle/profile/apply logic re-implemented and
kept in step); `require` + delegate (same coupling, plus `engine_internals`
and a "PATCHES ENGINE CODE" warning in the manager).

Every draw runs under pcall and falls back to the builtin renderer
permanently on first error, so a broken skin can never strand the player
outside the screen they need to disable it from.

```
Files:        manifest.json, main.lua, src/options.lua, src/skin.lua,
              src/rows.lua, mod.card, README.md, CHANGELOG.md, LICENSE,
              .gitattributes, .gitignore, .luarc.json,
              .github/workflows/{ci,release}.yml,
              tests/gen1_mod_menu_test.lua, docs/{banner,lineup}.png
Settings:     pending Q3/Q4/Q6 — at minimum PRESENTATION: MODERN/VANILLA
Interactions: Gen1MenuManager can hide the MODS row on the START menu; the
              OPTION-screen and F10 routes are unaffected. No overlap with
              Gen1ModernBag, Gen1SoundQOL, Gen1AutoSave.
Assets:       none in this repo. docs/banner.png and docs/lineup.png are
              generated in Gen1Wild (tools/make_lineup.py) from a 512x512
              mods/Wild@gen1_mod_menu/thumbnail.png (tools/make_icons.py).
Release:      branch claude/new-session-4fyaho -> merge to main ->
              release.yml runs ci.yml, resolves version from manifest.json,
              packs gen1_mod_menu-0.1.0.zip + sha256sums.txt, tags v0.1.0
Out of scope: the launcher's own mod-options UI (src/import/LauncherSettings)
              — mods are not loaded there, so it cannot be reskinned by one.
              No cheats, no behaviour change to enabling/disabling mods.
```

## Assumptions (to be confirmed or corrected)

- Mod id is `gen1_mod_menu`, matching the newest sibling convention
  (`gen1_sound_qol`, `gen1_modern_bag`) rather than Gen1MenuManager's
  PascalCase id.
- "Pretty UI decoration" means the Game Boy-native chrome every sibling uses —
  `Font.drawBox` panels, a title line, right-aligned status columns, footer
  button hints — not a non-native modern UI. 20x18 tiles, 160x144 px.
- `category: "UI"`, `profile: "content"`, `api: 2`, `affects_link: false`,
  `permissions: []`, `games: ["all"]`, `game_version: ">=0.0.0-0 <2.0.0"`.
- Licence MIT, matching Gen1SoundQOL and Gen1ModernBag.

## Open questions (Phase 3, unanswered)

1. Mechanism: decorate the live instance (recommended) or own replacement screen?
2. Reskin scope: options view only (recommended) / options + list / all six modes?
3. Which decorations (header bar, value column, help line, changed-marker,
   scroll indicator, category rules, glyph legend)?
4. Which QOL features (sort, filters, letter-jump, cursor memory,
   RESET TO DEFAULTS, an all-mods flat options view)?
5. Cover Gold as well (recommended) or Gen 1 only for v0.1.0?
6. Ship a PRESENTATION: MODERN/VANILLA row (recommended)?

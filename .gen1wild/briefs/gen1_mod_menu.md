# Gen1ModMenu — build brief

Status: **shipped as v0.1.0** — https://github.com/wild1walker/Gen1ModMenu/releases/tag/v0.1.0
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

## Decisions taken

1. **Mechanism** — a full replacement screen, per Wild. Registered in
   `Data.screens` under "ManagerState"; the instance handed back is the
   engine's own with its draw methods swapped, so the manager's logic stays
   the engine's. That costs `engine_internals` (reaching the builtin means
   requiring it by name) and the alternative -- reimplementing the toggle,
   profile and apply logic to avoid the permission -- was declined as the one
   place a divergence bricks boots rather than looking like a skin bug.
2. **Scope** — all six modes redrawn (list, detail, options, permissions,
   errors, apply). Forced by the mechanism: overriding `draw` means every
   mode is ours or it renders nothing. The confirm modal still goes to
   `Builtin.drawOverlay`.
3. **Decorations** — header bar with name and version, right-aligned value
   column, rules, help line, `.` changed-marker, scroll arrow and position
   counter, category headings with rules, and the mark legend on the ERRORS
   tab when it is otherwise empty.
4. **QOL** — four sort orders, two filters, RESET DEFAULTS, cursor memory.
   All set from this mod's own OPTIONS rows: the manager leaves no key free.
   Letter-jump was dropped (left/right are the tabs) and an all-mods flat
   options view deferred.
5. **Gold** — covered, and it fixes the OptionRows chrome bug there.
6. **Escape hatch** — `PRESENTATION: MODERN/VANILLA`, plus permanent demotion
   on a draw that throws, plus `Screens.build`'s own pcall.

## What shipped

- 165 checks, all four modkit gates green, artifact verified by extracting
  the built zip into an engine checkout and re-running everything.
- Two engine bugs fixed as a side effect: the OptionRows chrome on Gold, and
  vanilla's detail screen drawing its ninth action row at tile 19 of an
  18-tile screen.
- One bug caught by the suite's own charmap guard: a `+N` overflow marker on
  PENDING CHANGES, where the charmap has no `+`.
- Index wired: `mods/Wild@gen1_mod_menu/`, a cog icon in `make_icons.py`, all
  ten lineup strips regenerated, README row.

## Deferred

- An "ALL OPTIONS" view listing every installed mod's options in one flat
  list.
- The engine's own `APPLY & RESTART` label carries an `&`, which the charmap
  does not have, so it already draws as a gap. Not this mod's to fix.

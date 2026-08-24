-- Standalone:
--   luajit mods/gen1_mod_menu/tests/gen1_mod_menu_test.lua
-- from a Gen1Recomp checkout with this mod under mods/gen1_mod_menu.
--
-- Three tiers.  The list model is unit-driven as plain data.  The screen
-- decoration is then driven against a stand-in for the engine's
-- ManagerState -- the same method names, the same row shapes -- which is
-- what lets the sorting, the reset row, the scroll clamp and the vanilla
-- passthrough be asserted without a renderer or a ROM.  Finally the whole
-- mod is loaded through the real headless loader, so the manifest, the
-- option schema and the screen registration are asserted the way the game
-- would see them.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local script = (arg and arg[0]) or ""
local MOD_DIR = script:match("^(.*)/tests/[^/]+%.lua$") or "mods/gen1_mod_menu"

local Options = dofile(MOD_DIR .. "/src/options.lua")
local Rows = dofile(MOD_DIR .. "/src/rows.lua")
local Skin = dofile(MOD_DIR .. "/src/skin.lua")
local Screen = dofile(MOD_DIR .. "/src/screen.lua")

-- ------- the schema itself

do
  local seen = {}
  for _, row in ipairs(Options.schema) do
    T.check(type(row.key) == "string" and row.key ~= "", "every row has a key")
    T.check(not seen[row.key], "row key " .. tostring(row.key) .. " is unique")
    seen[row.key] = true
    T.check(row.type == "toggle" or row.type == "choice"
      or row.type == "number" or row.type == "text",
      row.key .. " uses a renderable row type")
    if row.type == "choice" then
      local legal = false
      for _, choice in ipairs(row.choices) do
        T.check(type(choice[1]) == "string", row.key .. " choice has a label")
        if choice[2] == row.default then legal = true end
      end
      T.check(legal, row.key .. "'s default is one of its own choices")
    end
    if row.visible_if then
      T.check(seen[row.visible_if.key] ~= nil,
        row.key .. "'s visible_if names a row declared before it")
    end
  end
  T.check(seen.presentation, "the way back to the vanilla screen has a row")
end

do -- PRESENTATION must never be hidden: it is the row that switches the mod
  -- off from inside the screen the mod draws
  for _, row in ipairs(Options.schema) do
    if row.key == "presentation" then
      T.eq(row.visible_if, nil, "PRESENTATION is visible unconditionally")
    end
  end
end

-- an options reader over a plain table, falling back to the shipped default
local function reader(overrides)
  overrides = overrides or {}
  local defaults = {}
  for _, row in ipairs(Options.schema) do defaults[row.key] = row.default end
  return function(key)
    local value = overrides[key]
    if value == nil then return defaults[key] end
    return value
  end
end

-- ------- the list model

local function entry(id, fields)
  local e = { id = id, name = id, category = "TOOL", state = "ON",
              hasOptions = true, mod = { id = id } }
  for key, value in pairs(fields or {}) do e[key] = value end
  return e
end

do -- state precedence follows ManagerState:glyphFor exactly
  T.eq(Rows.stateOf({ staged = true, enabled = false }), "STGD",
    "a staged change outranks everything")
  T.eq(Rows.stateOf({ enabled = false, errored = true }), "OFF",
    "a disabled mod reads OFF even when it also failed")
  T.eq(Rows.stateOf({ enabled = true, skipped = true, blocked = true }), "SKIP",
    "the wrong game outranks a blocked dependency")
  T.eq(Rows.stateOf({ enabled = true, blocked = true, errored = true }), "BLKD",
    "a blocked dependency outranks the error it causes")
  T.eq(Rows.stateOf({ enabled = true, errored = true }), "ERR", "then errors")
  T.eq(Rows.stateOf({ enabled = true }), "ON", "and a healthy mod is ON")
end

do -- every state has a gutter glyph, so a fall back to the engine's own
  -- drawRows still marks the rows it draws
  for _, state in ipairs(Rows.STATES) do
    T.check(type(Rows.glyphOf(state)) == "string",
      state .. " has a gutter glyph")
  end
end

local function labels(rows)
  local out = {}
  for _, row in ipairs(rows) do
    out[#out + 1] = (row.header and "# " or "") .. row.label
  end
  return out
end

do -- CATEGORY: the engine's grouping, plus a stable order inside each group
  local rows = Rows.arrange({
    entry("bravo", { category = "UI", name = "Bravo" }),
    entry("alpha", { category = "UI", name = "Alpha" }),
    entry("cesar", { category = "AUDIO", name = "Cesar" }),
  }, { sort = "category" })
  T.same(labels(rows), { "# AUDIO", "Cesar", "# UI", "Alpha", "Bravo" },
    "categories sort, and so do the mods inside them")
end

do -- NAME: one flat list, no headings
  local rows = Rows.arrange({
    entry("b", { name = "Bravo", category = "UI" }),
    entry("a", { name = "alpha", category = "AUDIO" }),
  }, { sort = "name" })
  T.same(labels(rows), { "alpha", "Bravo" },
    "name sorts case-insensitively across categories")
end

do -- two mods sharing a display name keep a stable order
  local rows = Rows.arrange({
    entry("zeta", { name = "Same" }), entry("alpha", { name = "Same" }),
  }, { sort = "name" })
  T.eq(rows[1].mod.id, "alpha", "the id breaks a name tie")
end

do -- ENABLED and PROBLEMS group by what the player is looking for
  local entries = {
    entry("on", { name = "On" }),
    entry("off", { name = "Off", state = "OFF" }),
    entry("bad", { name = "Bad", state = "ERR" }),
  }
  T.same(labels(Rows.arrange(entries, { sort = "enabled" })),
    { "# ENABLED", "Bad", "On", "# DISABLED", "Off" },
    "ENABLED splits the list in two")
  T.same(labels(Rows.arrange(entries, { sort = "status" })),
    { "# PROBLEMS", "Bad", "# RUNNING", "On", "# DISABLED", "Off" },
    "PROBLEMS floats what is wrong to the top")
end

do -- filters
  local entries = {
    entry("on", { name = "On" }),
    entry("off", { name = "Off", state = "OFF" }),
    entry("plain", { name = "Plain", hasOptions = false }),
  }
  T.same(labels(Rows.arrange(entries, { sort = "name", hide_disabled = true })),
    { "On", "Plain" }, "HIDE OFF drops the disabled mod")
  T.same(labels(Rows.arrange(entries, { sort = "name", only_options = true })),
    { "Off", "On" }, "ONLY W/OPTIONS drops the one with no schema")
end

do -- the filters can never hide the mod whose options page sets them
  local rows = Rows.arrange({
    entry("gen1_mod_menu", { name = "Gen1ModMenu", state = "OFF",
                            hasOptions = false }),
    entry("other", { name = "Other", state = "OFF" }),
  }, { sort = "name", hide_disabled = true, only_options = true },
  "gen1_mod_menu")
  T.same(labels(rows), { "Gen1ModMenu" },
    "the filters keep their own way back even when both would drop it")
end

do -- an empty result parks the cursor on a heading rather than on nothing
  local none = Rows.arrange({}, {})
  T.eq(none[1].header, true, "an empty list is a heading")
  T.eq(none[1].label, "NO MODS INSTALLED", "and says nothing is installed")
  local filtered = Rows.arrange({ entry("a", { state = "OFF" }) },
                                { hide_disabled = true }, "keep-nothing")
  T.eq(filtered[1].label, "NO MODS MATCH", "a filter that empties says so")
end

do -- an unknown sort falls back rather than returning nothing
  local rows = Rows.arrange({ entry("a", { name = "A" }) }, { sort = "nonsense" })
  T.eq(#rows, 2, "an unrecognised sort behaves like CATEGORY")
end

do -- the help line is read off the schema row; there is no description field
  T.eq(Rows.helpFor({ type = "toggle" }), "ON / OFF", "toggles say both values")
  T.eq(Rows.helpFor({ type = "choice", choices = { { "A", 1 }, { "B", 2 } } }),
    "A / B", "choices list their labels")
  T.eq(Rows.helpFor({ type = "number", min = 1, max = 8 }), "1-8",
    "numbers give their range")
  T.eq(Rows.helpFor({ type = "number", min = 0, max = 10, step = 5 }),
    "0-10 BY 5", "a step that is not 1 is spelled out")
  T.eq(Rows.helpFor({ type = "text", maxLen = 12 }), "UP TO 12 CHARS",
    "text rows give their budget")
  T.eq(Rows.helpFor(nil), nil, "and a missing row asks for nothing")
end

do
  T.eq(Rows.changed(5, 5), false, "a value equal to the default is unchanged")
  T.eq(Rows.changed(5, 6), true, "and one that differs is changed")
  T.eq(Rows.changed(nil, 6), false, "a row never touched is unchanged")
end

-- ------- the screen decoration
--
-- A stand-in for src/mods/ManagerState.lua: the method names the decoration
-- calls through to, and the row shapes it reads.

local function fakeManager(overrides)
  local calls = { draw = 0, update = 0 }
  local Builtin = {}
  Builtin.__index = Builtin
  function Builtin.modRows() return { { header = true, label = "VANILLA" } } end
  function Builtin.refresh() end
  function Builtin.enter() end
  function Builtin.draw() calls.draw = calls.draw + 1 end
  function Builtin.update() calls.update = calls.update + 1 end
  function Builtin.errorRows() return { { label = "NO ERRORS", inert = true } } end
  function Builtin.buildOptionRows(_, _, schema)
    local rows = {}
    for _, row in ipairs(schema) do
      rows[#rows + 1] = { id = row.key, label = row.label,
                          value = function() return "V" end }
    end
    return rows
  end
  function Builtin.updateOptions() end
  function Builtin.drawOverlay() end

  local state = setmetatable({
    screen = "list", tab = 1, cursor = 1, scroll = 1,
    status = { available = {
      { id = "alpha", name = "Alpha", category = "UI", enabled = true },
      { id = "bravo", name = "Bravo", category = "UI", enabled = false },
    } },
    written = {},
    notices = {},
  }, Builtin)
  function state.isStaged() return false end
  function state.runsHere() return true end
  function state.schemaFor() return { { key = "k", type = "toggle" } } end
  function state:optionValue(_, row)
    -- nil means "nothing stored", the way the engine's own optionValue reads
    -- it; a stored `false` is a value, not an absence
    local stored = self.written[row.key]
    if stored == nil then return row.default end
    return stored
  end
  function state:setOption(_, key, value) self.written[key] = value end
  function state:notify(text) self.notices[#self.notices + 1] = text end
  function state:snapCursor()
    local rows = self:modRows()
    if rows[self.cursor] and not rows[self.cursor].header then return end
    for i, row in ipairs(rows) do
      if not row.header then self.cursor = i return end
    end
    self.cursor = 1
  end
  for key, value in pairs(overrides or {}) do state[key] = value end
  return state, Builtin, calls
end

local modStub = { id = "gen1_mod_menu", ui = {},
  log = { warn = function() end, error = function() end,
          info = function() end } }

local function decorated(overrides, stateOverrides)
  local state, Builtin, calls = fakeManager(stateOverrides)
  Screen.decorate(modStub, Rows, Skin, reader(overrides), state, Builtin)
  return state, Builtin, calls
end

do -- MODERN arranges the list; VANILLA hands it straight back
  local modern = decorated({ sort = "name" })
  T.same(labels(modern:modRows()), { "Alpha", "Bravo" },
    "the modern list is this mod's own arrangement")

  local vanilla = decorated({ presentation = "vanilla" })
  T.same(labels(vanilla:modRows()), { "# VANILLA" },
    "VANILLA hands the list back to the engine untouched")
end

do -- and so does drawing
  local state, _, calls = decorated({ presentation = "vanilla" })
  state:draw()
  T.eq(calls.draw, 1, "VANILLA draws through the engine's own renderer")
end

do -- a renderer that throws is demoted for good rather than throwing again
  local state, _, calls = decorated()
  -- mod.ui has no Font in this harness, so the first modern draw throws
  state:draw()
  T.eq(calls.draw, 1, "a failed draw falls through to the engine's")
  state:draw()
  state:draw()
  T.eq(calls.draw, 3, "and every later frame goes straight there")
end

do -- the reset row is appended, and restores every default it is given
  local schema = {
    { key = "a", type = "toggle", label = "A", default = true },
    { key = "b", type = "number", label = "B", default = 3, min = 1, max = 8 },
  }
  local state = decorated()
  state.written.a = false
  state.written.b = 7
  local rows = state:buildOptionRows({ id = "target" }, schema)
  T.eq(#rows, 3, "the reset row is appended to the author's rows")
  T.eq(rows[3].label, "RESET DEFAULTS", "and it is last")
  T.eq(rows[1].changed, true, "a row holding a non-default value is marked")
  T.eq(rows[1].help, "ON / OFF", "and carries its help line")
  T.eq(rows[2].help, "1-8", "including the numeric range")

  rows[3].activate()
  T.eq(state.written.a, true, "resetting restores the first default")
  T.eq(state.written.b, 3, "and the second")
  T.eq(state.notices[1], "DEFAULTS RESTORED", "and says so")
end

do -- RESET ROW off leaves the author's rows exactly as the engine built them
  local state = decorated({ reset_row = false })
  local rows = state:buildOptionRows({ id = "t" },
    { { key = "a", type = "toggle", label = "A", default = true } })
  T.eq(#rows, 1, "no reset row when the option is off")
end

do -- the options page clamps its own scroll, for its own window size
  local state = decorated()
  state.screen = "options"
  state.optionRows = {}
  for i = 1, 20 do state.optionRows[i] = { id = i, label = "R" .. i } end
  state.cursor, state.scroll = 15, 0
  state:updateOptions({})
  T.eq(state.scroll, 4, "the cursor is pulled into an eleven-row window")
  state.cursor, state.scroll = 2, 8
  state:updateOptions({})
  T.eq(state.scroll, 1, "and back up again when it moves the other way")
end

do -- leaving the page must not re-clamp the list's scroll behind it
  local state = decorated()
  state.screen = "list"
  state.scroll, state.cursor = 6, 9
  state.optionRows = { { id = 1 } }
  state:updateOptions({})
  T.eq(state.scroll, 6, "a B press out of the options leaves the list alone")
end

do -- the ERRORS tab explains the marks when it has nothing else to say
  local state = decorated()
  local rows = state:errorRows(nil)
  T.eq(rows[1].header, true, "the legend opens with a heading")
  T.eq(#rows, 1 + #Rows.LEGEND, "and lists every mark")
  T.eq(rows[2].state, "ON", "each entry carries its mark")

  T.eq(#state:errorRows({ id = "one" }), 1,
    "a per-mod errors screen is left exactly as the engine built it")

  local vanilla = decorated({ presentation = "vanilla" })
  T.eq(#vanilla:errorRows(nil), 1, "and VANILLA never grows the legend")
end

do -- the cursor comes back where it was left
  local first = decorated({ sort = "name" })
  first.cursor, first.scroll, first.tab = 2, 1, 1
  first:update()
  local second = decorated({ sort = "name" })
  second:enter()
  T.eq(second.cursor, 2, "reopening the manager lands on the same row")

  local forgetful = decorated({ sort = "name", cursor_memory = false })
  forgetful.cursor = 1
  forgetful:enter()
  T.eq(forgetful.cursor, 1, "and KEEP CURSOR off starts at the top")
end

do -- the window the options page draws and the one it clamps to agree
  local state = decorated({ help_line = false })
  state.screen = "options"
  state.optionRows = {}
  for i = 1, 20 do state.optionRows[i] = { id = i } end
  state.cursor, state.scroll = 13, 0
  state:updateOptions({})
  T.eq(state.scroll, 1, "the help line gives its row back to the list")
end

-- ------- the renderer, actually run
--
-- Everything above proves the model.  This runs the drawing itself, against
-- the engine's real Font and Theme over the fixture dataset -- no ROM, no
-- window -- with every draw recorded so the geometry can be asserted rather
-- than eyeballed.  The suite reaches for engine modules here; the shipped
-- mod reaches for exactly one, and says so in its manifest.
--
-- The bound is the box interior: Font.drawBox(0, 0, 20, 18) owns tile row 0
-- and tile row 17, and column 0 and column 19.  Anything drawn outside that
-- is over the border or off the screen -- which is what vanilla's detail
-- screen does with its ninth action row, at tile 19 of an 18-tile screen.

local Fixtures = T.fixtures.load()
local RealFont = require("src.render.Font")
local RealTheme = require("src.ui.Theme")
RealFont.load(Fixtures)
RealTheme.load(Fixtures)

local LEFT, RIGHT, TOP, BOTTOM = 8, 152, 8, 128

-- Every character this screen draws has to exist in the Game Boy charmap.
-- It has no + * ~ < > = & _ | glyphs, and one it does not carry is rendered
-- as a space -- silently, which is how "+3" became "3" and stayed that way.
local Charmap = require("src.save_convert.data.charmap")

local function unspellable(text)
  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch ~= " " and Charmap.byToken[ch] == nil then return ch end
  end
  return nil
end

local function recordingFont()
  local marks = {}
  local proxy = {
    BORDER = RealFont.BORDER,
    split = RealFont.split, spansFitting = RealFont.spansFitting,
    width = RealFont.width, encode = RealFont.encode,
    advanceOf = RealFont.advanceOf, drawBox = RealFont.drawBox,
  }
  function proxy.draw(text, x, y)
    marks[#marks + 1] = { x = x, y = y, w = RealFont.width(text),
                          what = tostring(text) }
    return RealFont.draw(text, x, y)
  end
  function proxy.drawCode(code, x, y)
    marks[#marks + 1] = { x = x, y = y, w = RealFont.advanceOf(code),
                          what = "code " .. tostring(code) }
    return RealFont.drawCode(code, x, y)
  end
  return proxy, marks
end

-- a mod with every detail row the engine can produce, and a description far
-- longer than any window for it
local FAT = {
  id = "fat", name = "AVeryLongModNameIndeed", version = "10.20.30",
  category = "GAMEPLAY", profile = "content", enabled = true,
  permissions = { "engine_internals", "network" }, experimental = true,
  github = "wild1walker/Something", error = "it went wrong somewhere",
  description = string.rep("WORDS THAT KEEP GOING ", 40),
}

local function renderCase(name, screen, setup, overrides)
  local font, marks = recordingFont()
  local ui = { Font = font, Theme = RealTheme }
  local state, Builtin, calls = fakeManager()
  local renderMod = { id = "gen1_mod_menu", ui = ui, log = modStub.log }

  function state:rowsForScreen()
    if self.screen == "list" then
      if self.tab == 1 then return self:modRows() end
      if self.tab == 2 then
        return { { profile = { name = "PROFILE 1" }, label = "PROFILE 1",
                   glyph = "!" } }
      end
      return self:errorRows(nil)
    elseif self.screen == "detail" then
      return self:detailRows(self.currentMod)
    elseif self.screen == "errors" then
      return self:errorRows(self.currentMod)
    elseif self.screen == "permissions" then
      return { { inert = true, glyph = "!", label = "PATCHES ENGINE CODE" },
               { inert = true, glyph = "!", label = "USES THE NETWORK" } }
    elseif self.screen == "apply" then
      -- the engine's own literal is "APPLY & RESTART"; the charmap has no
      -- ampersand, so it already draws there as a space. Not this mod's to
      -- fix, and spelled out here so it does not trip the charmap guard.
      return { { label = "APPLY AND RESTART" }, { label = "DISCARD CHANGES" },
               { label = "BACK" } }
    end
    return {}
  end
  function state:detailRows()
    local rows = {}
    for _, label in ipairs({ "DISABLE", "OPTIONS..", "PERMISSIONS..",
                             "TRY HERE ANYWAY", "FOR RED/BLUE/YELLOW/GOLD",
                             "GH wild1walker/Something", "EXPERIMENTAL",
                             "VIEW ERROR..", "BACK" }) do
      rows[#rows + 1] = { label = label }
    end
    return rows
  end
  function state:stagedList() return self.staged or {} end

  Screen.decorate(renderMod, Rows, Skin, reader(overrides), state, Builtin)
  state.screen = screen
  if setup then setup(state) end
  state:draw()

  T.eq(calls.draw, 0, name .. ": the modern renderer drew it")
  local worst
  for _, mark in ipairs(marks) do
    if mark.x < LEFT or mark.x + mark.w > RIGHT
        or mark.y < TOP or mark.y > BOTTOM then
      worst = worst or mark
    end
  end
  T.check(worst == nil, name .. ": everything lands inside the box"
    .. (worst and (" (" .. worst.what .. " at " .. worst.x .. "," .. worst.y
        .. " w" .. worst.w .. ")") or ""))
  T.check(#marks > 0, name .. ": something was actually drawn")

  local bad, badText
  for _, mark in ipairs(marks) do
    if not mark.what:match("^code ") then
      local ch = unspellable(mark.what)
      if ch and not bad then bad, badText = ch, mark.what end
    end
  end
  T.check(bad == nil, name .. ": every character is in the charmap"
    .. (bad and (" (" .. bad .. " in " .. tostring(badText) .. ")") or ""))
  return marks
end

renderCase("list", "list")
renderCase("list/profiles", "list", function(s) s.tab = 2 end)
renderCase("list/errors", "list", function(s) s.tab = 3 end)
renderCase("list sorted by name", "list", nil, { sort = "name" })
renderCase("list with a notice", "list", function(s) s.notice = "SAFE MODE ACTIVE" end)

renderCase("list of one long name", "list", function(s)
  s.status.available = { { id = "x", name = "AnAbsurdlyLongModNameHere",
                           category = "SOMETHING RATHER LONG", enabled = true } }
end)

renderCase("empty list", "list", function(s) s.status.available = {} end)

renderCase("detail", "detail", function(s) s.currentMod = FAT end)
renderCase("detail scrolled", "detail", function(s)
  s.currentMod = FAT
  s.descScroll = 3
end)

renderCase("permissions", "permissions", function(s) s.currentMod = FAT end)
renderCase("errors", "errors", function(s) s.currentMod = FAT end)

renderCase("apply", "apply", function(s)
  s.staged = {}
  for i = 1, 25 do
    s.staged[i] = { id = "m" .. i, name = "Staged Mod " .. i,
                    enabled = i % 2 == 0 }
  end
end)
renderCase("apply with nothing staged", "apply")

do
  local schema = {}
  for i = 1, 25 do
    schema[i] = { key = "k" .. i, type = "number", label = "A LONGISH LABEL "
      .. i, default = 1, min = 1, max = 99 }
  end
  renderCase("options", "options", function(s)
    s.currentMod = FAT
    s.optionRows = s:buildOptionRows(FAT, schema)
    s.cursor, s.scroll = 14, 8
    s.written.k14 = 42
  end)
  renderCase("options without the help line", "options", function(s)
    s.currentMod = FAT
    s.optionRows = s:buildOptionRows(FAT, schema)
  end, { help_line = false })
  renderCase("options at the top", "options", function(s)
    s.currentMod = FAT
    s.optionRows = s:buildOptionRows(FAT, { schema[1] })
  end)
end

do -- an overlay still reaches the engine's own modal
  local font = recordingFont()
  local state, Builtin = fakeManager()
  local seen = 0
  Builtin.drawOverlay = function() seen = seen + 1 end
  function state:rowsForScreen() return self:modRows() end
  Screen.decorate({ id = "gen1_mod_menu", ui = { Font = font, Theme = RealTheme },
                    log = modStub.log }, Rows, Skin, reader(), state, Builtin)
  state.overlay = { kind = "confirm", lines = { "RESTART NOW?" }, index = 1 }
  state:draw()
  T.eq(seen, 1, "the confirm modal is still drawn by the engine")
end

-- ------- the whole mod through the real loader

local run = T.sdk.loadMod(MOD_DIR)
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local loader = run.loader
T.eq(run.mod.manifest.id, "gen1_mod_menu", "the manifest id is the mod id")

local schema = loader.optionSchemas.gen1_mod_menu
T.check(type(schema) == "table" and #schema == #Options.schema,
  "the entry chunk defined the option schema")

-- the registration the whole mod turns on: the id the engine resolves before
-- its own builtin (src/ui/Screens.lua), so every route into the manager --
-- the START menu, the OPTION screen, F10 and Gold -- lands here
local record = run.data.screens and run.data.screens.ManagerState
T.check(record ~= nil, "the mod registers the ManagerState screen id")
T.check(type(record) == "function"
  or (type(record) == "table" and type(record.new) == "function"),
  "and the record is a screen factory")

run.release()
T.finish("gen1_mod_menu")

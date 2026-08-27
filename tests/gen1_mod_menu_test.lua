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
    -- the engine appends this one itself, at the end of its own
    -- buildOptionRows; leaving it out of the stand-in is what let a second
    -- copy of it ship
    rows[#rows + 1] = { id = "__reset", label = "RESET DEFAULTS",
                        value = function() return "" end,
                        activate = function() end }
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
  function state:focusedRow() return self:rowsForScreen()[self.cursor] end
  function state:beginToggle(m) self.toggled = m end
  function Builtin.pressStart(self) self.applied = true end
  function Builtin.quickToggle(self) self.quickToggled = true end
  -- part of the surface being stood in for: the decoration clamps the list's
  -- scroll against it, because the engine's own clamp is sized for a window
  -- the cards no longer draw
  function state:rowsForScreen()
    if self.screen == "list" then
      if self.tab == 1 then return self:modRows() end
      if self.tab == 3 then return self:errorRows(nil) end
      return {}
    end
    return {}
  end
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

-- src/ui/Menu.lua's shape: new(game, items, opts) returning something the
-- caller pushes.  The suite drives the items rather than the widget.
local pushed
local FakeMenu = { new = function(game, items, opts)
  pushed = { items = items, opts = opts }
  return pushed
end }

local modStub = { id = "gen1_mod_menu", ui = { Menu = FakeMenu },
  log = { warn = function() end, error = function() end,
          info = function() end } }

local function labelsOf(items)
  local out = {}
  for i, item in ipairs(items) do out[i] = item.label end
  return out
end

local function findRow(items, label)
  for _, item in ipairs(items) do
    if item.label == label then return item end
  end
end

local function decorated(overrides, stateOverrides)
  local state, Builtin, calls = fakeManager(stateOverrides)
  Screen.decorate(modStub, Rows, Skin, Options, reader(overrides), state, Builtin)
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

do -- the author's rows are annotated, and nothing is added beside them
  local schema = {
    { key = "a", type = "toggle", label = "A", default = true },
    { key = "b", type = "number", label = "B", default = 3, min = 1, max = 8 },
  }
  local state = decorated()
  state.written.a = false
  state.written.b = 7
  local rows = state:buildOptionRows({ id = "target" }, schema)
  T.eq(rows[1].changed, true, "a row holding a non-default value is marked")
  T.eq(rows[1].help, "ON / OFF", "and carries its help line")
  T.eq(rows[2].help, "1-8", "including the numeric range")
  T.eq(rows[#rows].id, "__reset", "the engine's reset row is still last")
  T.eq(rows[#rows].help, "PUT BACK THE AUTHOR'S VALUES",
    "and it gets a help line like the rest")
end

-- RESET DEFAULTS is the ENGINE's row: src/mods/ManagerState.lua appends one
-- at the end of its own buildOptionRows.  0.1.0 through 0.3.0 appended a
-- second one beside it, because this mod was written without reading that
-- function to its end.  Nothing in the suite noticed -- the two carried
-- different ids, sat inside the box, overlapped nothing and spelled only
-- charmap characters.  What told them apart on screen is that they read the
-- same, so that is what is asserted here.
do
  local state = decorated()
  local rows = state:buildOptionRows({ id = "t" },
    { { key = "a", type = "toggle", label = "A", default = true } })
  local seen = {}
  for _, row in ipairs(rows) do
    local label = tostring(row.label)
    T.check(not seen[label], "no two option rows read '" .. label .. "'")
    seen[label] = true
  end
end

do -- the options page clamps its own scroll, for its own window size
  local state = decorated()
  state.screen = "options"
  state.optionRows = {}
  for i = 1, 20 do state.optionRows[i] = { id = i, label = "R" .. i } end
  state.cursor, state.scroll = 15, 0
  state:updateOptions({})
  T.eq(state.scroll, 15 - Skin.OPT_COUNT, "the cursor is pulled into the cards")
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

do -- the ERRORS tab is the engine's own rows, untouched
  local state = decorated()
  T.eq(#state:errorRows(nil), 1, "nothing is added to the tab's rows")
  T.eq(state:errorRows(nil)[1].label, "NO ERRORS",
    "and a clean install still just says so")
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

do -- the window the options page draws and the one it clamps to agree, and
  -- the help line no longer costs a row -- it sits outside the cards
  for _, help in ipairs({ true, false }) do
    local state = decorated({ help_line = help })
    state.screen = "options"
    state.optionRows = {}
    for i = 1, 20 do state.optionRows[i] = { id = i } end
    state.cursor, state.scroll = 13, 0
    state:updateOptions({})
    T.eq(state.scroll, 13 - Skin.OPT_COUNT,
      "the options page clamps to the cards with help " ..
      (help and "on" or "off"))
  end
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

local LEFT, RIGHT = 8, 152

-- Rows 0 and 17 belong to a border on every screen this mod draws: the
-- framed ones have their window's, and the banded ones have their header
-- box's top and their info box's bottom.  So text lives on rows 1 to 16,
-- everywhere, and one bound covers the lot.
--
-- 0.6.0 loosened this to allow rows 0 and 17 while the list wore a bare
-- title bar and the options page a bare caption.  Neither is bare any more,
-- and the loosened bound let a notice be drawn onto the info box's border.
local TOP, BOTTOM = 8, 128

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

-- Every fixed string the screen says has to fit the row it is drawn on.
-- Overlap does not catch this: an overlong footer is silently cut to width by
-- fit(), so it stays inside the box, overlaps nothing, and simply loses its
-- last letter. That is how "START:APPLY B:EXIT" shipped as "...B:EXI".

do
  local function fits(text, budget, where)
    T.check(RealFont.width(text) <= budget,
      where .. ' fits its row: "' .. text .. '" is '
      .. RealFont.width(text) .. "px of " .. budget)
  end
  local checked = 0
  for key, value in pairs(Skin.STRINGS.line) do
    if type(value) == "string" then
      fits(value, Skin.LINE_BUDGET, "line." .. key)
      checked = checked + 1
    else
      for i, one in ipairs(value) do
        fits(one, Skin.LINE_BUDGET, "line." .. key .. "[" .. i .. "]")
        checked = checked + 1
      end
    end
  end
  -- the state words, which the info band under the list and the detail
  -- screen both draw; every mark this mod can produce must have one
  for _, mark in ipairs(Rows.STATES) do
    local word = Skin.STRINGS.states[mark]
    T.check(word ~= nil, mark .. " has a word to spell it out with")
    fits(word, Skin.LINE_BUDGET, "states." .. mark)
    checked = checked + 1
  end

  T.check(next(Skin.STRINGS.footer) == nil,
    "no control hints are left to measure")
  T.check(checked >= 10, "the whole chrome vocabulary was measured")
end

-- A label and its own widest value share one 17-glyph row, with a glyph of
-- gap between them. When they do not fit, pair() shortens the LABEL -- so the
-- row still looks tidy and simply says the wrong thing ("ONLY W/OPTION",
-- "PRESENTATI"). Nothing above catches that, so the pairs are measured here.

do
  local GAP = 8
  local function pairFits(label, value, where)
    local need = RealFont.width(label) + GAP + RealFont.width(value or "")
    T.check(need <= Skin.LINE_BUDGET,
      where .. ' fits beside its value: "' .. label .. '" + "'
      .. tostring(value) .. '" is ' .. need .. "px of " .. Skin.LINE_BUDGET)
  end

  -- A card gives the label and the value a line each, so they no longer
  -- compete for one row: the label gets the whole first line, and the value
  -- shares the second with the CHANGED marker right-aligned against it.
  local VALUE_BUDGET = Skin.LINE_BUDGET - 8 - RealFont.width(Skin.STRINGS.line.changed)
  for _, row in ipairs(Options.schema) do
    T.check(RealFont.width(row.label) <= Skin.LINE_BUDGET,
      "option " .. row.key .. "'s label fits its own line")
    local widest = ""
    if row.type == "toggle" then
      widest = "OFF"
    elseif row.type == "choice" then
      for _, choice in ipairs(row.choices) do
        if #tostring(choice[1]) > #widest then widest = tostring(choice[1]) end
      end
    elseif row.type == "number" then
      widest = tostring(row.max or row.default)
    end
    T.check(RealFont.width(widest) <= VALUE_BUDGET,
      "option " .. row.key .. "'s widest value fits beside the marker")
  end

  -- the reset row this mod adds to every OTHER mod's page, which has no value
  T.check(RealFont.width("RESET DEFAULTS") <= Skin.LINE_BUDGET,
    "the reset row fits its line")

  -- A mod NAME is data, not chrome: it can be any length, and a long one
  -- beside a four-glyph mark genuinely does not fit. What must hold is which
  -- half gives way -- pair() shortens the label and keeps the value, so the
  -- mark survives intact and it is the name that gets clipped. That is
  -- asserted against the real renderer below, not here.
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
        -- what ManagerState:profileRows builds: a row per saved profile,
        -- labelled p.name -- including one saved without a name, which is
        -- the row that came out as an empty card -- then the actions
        local out = {}
        -- self.profiles when a case sets it, so a fixture can make this tab
        -- long enough to scroll; the default pair otherwise, one of them the
        -- unnamed profile that came out as an empty card
        if self.profiles then
          for i, p in ipairs(self.profiles) do
            out[i] = { profile = p, label = p.name, glyph = "!" }
          end
        else
          out[1] = { profile = { name = "PROFILE 1" }, label = "PROFILE 1",
                     glyph = "!" }
          out[2] = { profile = { name = "" }, label = "" }
        end
        out[#out + 1] = { saveAs = true, label = "SAVE CURRENT AS.." }
        out[#out + 1] = { exportProfile = true, label = "EXPORT.." }
        out[#out + 1] = { importProfile = true, label = "IMPORT.." }
        out[#out + 1] = { adhoc = true, label = "[AD-HOC] (LIVE)" }
        return out
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

  Screen.decorate(renderMod, Rows, Skin, Options, reader(overrides), state, Builtin)
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

  -- Nothing may be drawn on top of anything else.  Staying inside the box is
  -- not enough on its own: the first build passed the bounds check while
  -- painting the position counter through "ERRS", the scroll arrow through
  -- "SEL:TOGGLE", and "N MORE" through a staged mod's own ON.  Two draws on
  -- the same text row whose pixel spans meet is the whole test.
  local clash
  for i = 1, #marks do
    for j = i + 1, #marks do
      local a, b = marks[i], marks[j]
      if a.y == b.y and a.w > 0 and b.w > 0
          and a.x < b.x + b.w and b.x < a.x + a.w then
        clash = clash or (a.what .. " over " .. b.what .. " at row "
          .. (a.y / 8))
      end
    end
  end
  T.check(clash == nil, name .. ": nothing overlaps"
    .. (clash and (" (" .. clash .. ")") or ""))
  return marks
end

renderCase("list", "list")
renderCase("list/profiles", "list", function(s) s.tab = 2 end)
renderCase("list/errors", "list", function(s) s.tab = 3 end)
renderCase("list sorted by name", "list", nil, { sort = "name" })
renderCase("list with a notice", "list", function(s) s.notice = "SAFE MODE ACTIVE" end)

-- ------- the more-arrow
--
-- The count in the header says where you are; the arrow says there is more
-- below, which is the question asked before pressing down.  It lives in the
-- bottom-right interior cell -- column 18, row 16 -- on all three tabs and on
-- an options page, so the fixtures below are about it being there when the
-- list runs on, gone when it does not, and never sharing its cell.
local ARROW_X, ARROW_Y = 18 * 8, 16 * 8

local function arrowIn(marks)
  local code = "code " .. tostring(RealTheme.moreArrow)
  for _, m in ipairs(marks) do
    if m.what == code and m.x == ARROW_X and m.y == ARROW_Y then return true end
  end
  return false
end

local function manyMods(n)
  local out = {}
  for i = 1, n do
    out[i] = { id = "m" .. i, name = "Gen1LongishModName" .. i,
               category = "UI", enabled = true }
  end
  return out
end

do -- a list that runs on says so, on every tab
  T.check(arrowIn(renderCase("list with more below", "list", function(s)
    s.status.available = manyMods(12)
  end)), "the MODS tab draws the arrow when the list runs past the screen")

  T.check(arrowIn(renderCase("profiles with more below", "list", function(s)
    s.tab = 2
    s.profiles = {}
    for i = 1, 12 do s.profiles[i] = { name = "PROFILE " .. i } end
  end)), "and so does the PROFILES tab, whose fifth row it shares a line with")
end

do -- and a list that does not, does not
  T.check(not arrowIn(renderCase("list with nothing below", "list",
    function(s) s.status.available = manyMods(2) end)),
    "a list that fits draws no arrow")

  local tail = renderCase("list scrolled to the end", "list", function(s)
    s.status.available = manyMods(6)
    s.cursor, s.scroll = 6, 3
  end)
  T.check(not arrowIn(tail), "and neither does one scrolled to its last row")
end

do -- the arrow's cell is held back rather than painted over
  -- A label wide enough to want that cell is the whole point of the fixture:
  -- a bottom row that yields nothing is not a test of a row yielding a
  -- column.  So this measures the label rather than merely finding one, and
  -- pins that it is the row which gives way, the same way a mod name gives
  -- way to its mark.
  local marks = renderCase("long bottom row under the arrow", "list",
    function(s)
      s.tab = 2
      s.profiles = {}
      for i = 1, 12 do
        s.profiles[i] = { name = "A LONG PROFILE NAME " .. i }
      end
    end)

  -- Every visible row here carries the same shape of label, so the rows above
  -- are the control: they show what one of these is allowed to reach when it
  -- is not sharing its line with the arrow.
  local onArrow, elsewhere = 0, 0
  for _, m in ipairs(marks) do
    if not m.what:match("^code ") then
      if m.y == ARROW_Y then
        onArrow = math.max(onArrow, m.x + m.w)
      elseif m.what:match("^A LONG PROFILE") then
        elsewhere = math.max(elsewhere, m.x + m.w)
      end
    end
  end

  T.check(arrowIn(marks), "a long bottom row still gets the arrow")
  T.check(onArrow > 0, "and the row really does carry a label")
  T.check(onArrow <= ARROW_X, "which stops at the arrow's column rather than "
    .. "running under it")
  T.check(elsewhere > ARROW_X,
          "while the same label a row up runs past that column, so the "
          .. "bottom row gave the column up rather than never wanting it")
end

renderCase("list of one long name", "list", function(s)
  s.status.available = { { id = "x", name = "AnAbsurdlyLongModNameHere",
                           category = "SOMETHING RATHER LONG", enabled = true } }
end)

renderCase("empty list", "list", function(s) s.status.available = {} end)

do -- a name too long to sit beside its mark clips the NAME, never the mark
  local marks = renderCase("long name with a mark", "list", function(s)
    s.status.available = { { id = "x", name = "AnAbsurdlyLongModName",
                             category = "UI", enabled = false } }
  end, { sort = "name" })
  local sawMark, sawWholeName = false, false
  for _, m in ipairs(marks) do
    if m.what == "OFF" then sawMark = true end
    if m.what == "AnAbsurdlyLongModName" then sawWholeName = true end
  end
  T.check(sawMark, "the mark is drawn in full beside a name that cannot fit")
  T.check(not sawWholeName, "and it is the name that gives way, not the mark")
end

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
  -- a notice on a banded screen has one line it can take, and taking two of
  -- them is how a notice and a caption ended up stacked in 0.2.0
  renderCase("options with a notice", "options", function(s)
    s.currentMod = FAT
    s.optionRows = s:buildOptionRows(FAT, schema)
    s.notice = "SAFE MODE ACTIVE"
  end)
end

do -- an overlay still reaches the engine's own modal
  local font = recordingFont()
  local state, Builtin = fakeManager()
  local seen = 0
  Builtin.drawOverlay = function() seen = seen + 1 end
  function state:rowsForScreen() return self:modRows() end
  Screen.decorate({ id = "gen1_mod_menu", ui = { Font = font, Theme = RealTheme },
                    log = modStub.log }, Rows, Skin, Options, reader(), state,
                  Builtin)
  state.overlay = { kind = "confirm", lines = { "RESTART NOW?" }, index = 1 }
  state:draw()
  T.eq(seen, 1, "the confirm modal is still drawn by the engine")
end

-- A card is a whole framed box, so a row with no readable label comes out as
-- an empty one -- which is what a profile saved without a name looked like on
-- the PROFILES tab.  The engine builds those rows (ManagerState:profileRows
-- labels each one p.name), so the renderer is where it has to be caught.
do
  local marks = renderCase("a row with no name", "list", function(s)
    s.tab = 2
  end)
  local said = false
  for _, m in ipairs(marks) do
    if m.what == Skin.STRINGS.line.unnamed then said = true end
  end
  T.check(said, "an unnamed row says so rather than drawing an empty card")
end

-- Left and right move between the three tabs, and wrap at both ends. The
-- engine's clampIndex already does this (i < 1 answers n, i > n answers 1),
-- and none of the decoration touches adjustOrTab -- asserted so that stays
-- true rather than taken on trust.
do
  local state, Builtin = fakeManager()
  function Builtin.adjustOrTab(self, dir)
    local n = 3
    local i = self.tab + dir
    if i < 1 then i = n elseif i > n then i = 1 end
    self.tab = i
  end
  Screen.decorate(modStub, Rows, Skin, Options, reader(), state, Builtin)

  state.tab = 3
  state:adjustOrTab(1)
  T.eq(state.tab, 1, "right from the last tab wraps to the first")
  state:adjustOrTab(-1)
  T.eq(state.tab, 3, "and left from the first wraps back to the last")
  state.tab = 1
  state:adjustOrTab(1)
  T.eq(state.tab, 2, "and an ordinary step is an ordinary step")
end

-- The info band earns its place on the MODS tab, where it says the two
-- things a row has no room for: the mod's category, and its state in words.
-- On PROFILES and ERRORS the row already carries its whole text, so a band
-- there could only read it back -- which is what it did, and what a fifth
-- row is worth more than.
do
  T.eq(Skin.rowCountFor(1), 4, "the MODS tab keeps four rows and its band")
  T.eq(Skin.rowCountFor(2), 5, "PROFILES spends the band's rows on a fifth row")
  T.eq(Skin.rowCountFor(3), 5, "and so does ERRORS")
end

do -- nothing on the PROFILES tab is drawn twice
  local marks = renderCase("profiles, no echo", "list", function(s)
    s.tab = 2
  end)
  local counted = {}
  for _, m in ipairs(marks) do
    if not m.what:match("^code ") then
      counted[m.what] = (counted[m.what] or 0) + 1
    end
  end
  T.eq(counted["PROFILE 1"], 1,
    "the focused row is not read back underneath itself")
  T.check(counted["IMPORT.."] == 1,
    "and the fifth row is on screen, where the band used to be")
end

do -- while the MODS tab still says what a row cannot
  local marks = renderCase("mods, band says more", "list", function(s)
    s.status.available = { { id = "x", name = "Gen1Dex", category = "UI",
                             enabled = true, state = "blocked_dependency" } }
  end, { sort = "name" })
  local said = {}
  for _, m in ipairs(marks) do said[m.what] = true end
  T.check(said["UI"], "the band names the focused mod's category")
  T.check(said["BLOCKED"], "and spells its state out in a word")
  T.check(said["BLKD"], "while the row keeps the short mark")
end

-- ------- START and SELECT on the mod list

local function listMenu(overrides)
  pushed = nil
  local state = decorated(overrides or { sort = "name" })
  state.game = { stack = { push = function() end } }
  state.cursor = 1
  state:pressStart()
  return state, pushed
end

do -- START opens the menu, with the focused mod's toggle first
  local state, menu = listMenu()
  T.check(menu ~= nil, "START opens a menu instead of going to APPLY")
  T.eq(state.applied, nil, "and does not apply on the way")
  T.eq(menu.items[1].label, "DISABLE",
    "the focused mod's toggle is the first row")

  menu.items[1].onSelect()
  T.check(state.toggled ~= nil, "and it is the engine's own beginToggle")
end

do -- a disabled mod offers to enable it instead
  local state, menu = listMenu()
  state.status.available[1].enabled = false
  pushed = nil
  state.cursor = 1
  state:pressStart()
  T.eq(pushed.items[1].label, "ENABLE", "a disabled mod reads ENABLE")
  state.status.available[1].enabled = true
end

do -- every sort is offered, and the active one is bracketed
  local _, menu = listMenu({ sort = "name" })
  local labels = labelsOf(menu.items)
  T.check(findRow(menu.items, "[BY NAME]"), "the active sort is bracketed")
  T.check(findRow(menu.items, "BY CATEGORY"), "and the others are not")
  T.check(findRow(menu.items, "BY ENABLED"), "every choice is offered")
  T.check(findRow(menu.items, "BY PROBLEMS"), "including PROBLEMS")
  T.eq(#labels, 1 + 4 + 2,
    "the toggle, the four sorts and the two filters, and nothing else")
end

do -- picking a sort writes it through the engine's own setOption
  local state, menu = listMenu({ sort = "name" })
  state.cursor = 3
  findRow(menu.items, "BY PROBLEMS").onSelect()
  T.eq(state.written.sort, "status", "the chosen sort is stored")
  T.eq(state.cursor, 1, "and the cursor goes back to the top of the list")
end

do -- the filters are toggles that show their own state
  local state, menu = listMenu()
  T.check(findRow(menu.items, "HIDE OFF: OFF"), "a filter shows its state")
  findRow(menu.items, "HIDE OFF: OFF").onSelect()
  T.eq(state.written.hide_disabled, true, "and selecting it turns it on")

  local _, on = listMenu({ hide_disabled = true })
  T.check(findRow(on.items, "HIDE OFF: ON"), "and it reads ON once it is")
end

-- APPLY & RESTART is what ManagerState:pressStart reaches, and it is the only
-- route there.  START no longer goes to it on this tab, so SELECT must.
do
  local state = decorated()
  state.game = { stack = { push = function() end } }
  state:quickToggle()
  T.eq(state.applied, true, "SELECT applies")
  T.eq(state.quickToggled, nil, "rather than quick-toggling")
end

do -- the other tabs keep both keys exactly as the engine has them
  for _, tab in ipairs({ 2, 3 }) do
    local state = decorated()
    state.tab = tab
    state.game = { stack = { push = function() end } }
    pushed = nil
    state:pressStart()
    T.eq(pushed, nil, "tab " .. tab .. " keeps vanilla START")
    T.eq(state.applied, true, "which is the engine's own")
    state:quickToggle()
    T.eq(state.quickToggled, true, "and vanilla SELECT")
  end
end

do -- and so does STYLE: VANILLA
  local state = decorated({ presentation = "vanilla" })
  state.game = { stack = { push = function() end } }
  pushed = nil
  state:pressStart()
  T.eq(pushed, nil, "VANILLA leaves START alone")
  state:quickToggle()
  T.eq(state.quickToggled, true, "and SELECT with it")
end

do -- a row that is not a mod offers no toggle, and does not crash
  local state = decorated({ sort = "name", hide_disabled = true,
                            only_options = true })
  state.status.available = {}
  state.game = { stack = { push = function() end } }
  pushed = nil
  state:pressStart()
  T.check(pushed ~= nil, "the menu still opens on an empty list")
  T.eq(pushed.items[1].label, "BY CATEGORY",
    "and leads with the sorts, having no mod to toggle")
end

-- ------- the two menus outside the manager

local Menus = dofile(MOD_DIR .. "/src/menus.lua")

-- a stand-in for the engine's hook bus: one chain, called the way
-- src/mods/Hooks.lua calls it
local function hookBus()
  local chain = {}
  return {
    wrap = function(_, name, fn) chain[name] = fn end,
    call = function(name, vanilla, ...)
      if not chain[name] then return vanilla(...) end
      return chain[name](vanilla, ...)
    end,
  }
end

-- The START menu is left entirely alone: its row is the engine's own, it
-- reads MODS, and this mod no longer wraps the hook that builds it.  Asserted
-- rather than assumed, because a rename is a one-line thing to add back.
do
  local bus = hookBus()
  local optionsMod = {
    ui = {}, log = modStub.log,
    content = { screens = { register = function() end } },
  }
  optionsMod.hooks = bus
  Menus.install(optionsMod, Skin, reader())
  T.check(Menus.installStartRow == nil,
          "there is no START menu installer left to call")
  local items = { { label = "POKEDEX" }, { label = "MODS" },
                  { label = "QUIT" } }
  local out = bus.call("ui.start_menu.items",
                       function(_, list) return list end, {}, items)
  T.eq(#out, 3, "no row is added to the START menu")
  T.eq(out[2].label, "MODS", "and the engine's own row keeps its label")
end

-- The OPTION screen's cursor, with CANCEL no longer drawn.  The engine's own
-- update is what handles input, including B and START; this only asserts
-- where the cursor ends up afterwards, because that is all the decoration
-- does -- the exit is never in its hands.
do
  local registered
  local optionsMod = {
    ui = {}, log = modStub.log,
    content = { screens = { register = function(_, id, record)
      registered = { id = id, record = record }
    end } },
  }
  T.check(Menus.installOptionsScreen(optionsMod, Skin, reader()),
    "the OPTION screen is registered")
  T.eq(registered.id, "OptionsMenu", "under the engine's own screen id")

  -- the builtin this stands in for: three rows, and an update that moves the
  -- index the way src/ui/OptionsMenu.lua does, CANCEL included
  local Builtin = {}
  Builtin.__index = Builtin
  local ROWS = { { label = "A" }, { label = "B" }, { label = "C" } }
  function Builtin.new(game)
    return setmetatable({ game = game, rows = ROWS, index = 1, scroll = 0 },
                        Builtin)
  end
  function Builtin.draw() end
  function Builtin.update(self, dir)
    local cancelRow = #self.rows + 1
    if dir == "up" then
      self.index = self.index > 1 and self.index - 1 or cancelRow
    elseif dir == "down" then
      self.index = self.index < cancelRow and self.index + 1 or 1
    end
  end

  -- drive the decoration over that stand-in
  local state = Builtin.new({})
  local decorate = registered.record.new
  -- the real factory requires the engine module; here the behaviour under
  -- test is the wrapper, so it is applied to the stand-in directly
  local saved = package.loaded["src.ui.OptionsMenu"]
  package.loaded["src.ui.OptionsMenu"] = Builtin
  state = decorate({})
  package.loaded["src.ui.OptionsMenu"] = saved

  state.index = 1
  state:update("up")
  T.eq(state.index, #ROWS, "up from the first row lands on the last, not CANCEL")

  state.index = #ROWS
  state:update("down")
  T.eq(state.index, 1, "down from the last row wraps to the first")

  state.index = 2
  state:update("down")
  T.eq(state.index, 3, "and an ordinary move is left alone")
end

-- The same screen once the engine groups it.  src/ui/OptionsMenu.lua keeps two
-- lists: `rows`, the flat one the ui.options.rows hook built, and `view`, the
-- one on screen, where a group of members is replaced by a single opener.  The
-- cursor indexes `view`, and the engine's own draw takes `self.view or
-- self.rows` -- so a decoration reading `rows` draws one list under a cursor
-- counting the other, and MODS (ninth in the view) hides thirtieth in a list
-- nobody is looking at.
do
  local registered
  local optionsMod = {
    ui = {}, log = modStub.log,
    content = { screens = { register = function(_, id, record)
      registered = { id = id, record = record }
    end } },
  }
  -- a Skin that records what it was asked to draw rather than drawing it
  local drawn
  local spySkin = setmetatable({
    drawPlainRows = function(_, _, rows) drawn = rows end,
  }, { __index = Skin })
  T.check(Menus.installOptionsScreen(optionsMod, spySkin, reader()),
    "the OPTION screen is registered over a grouped engine")

  -- flat is longer than the view, which is the whole point: eight of its rows
  -- are inside groups and reach the screen as three openers
  local FLAT, VIEW = {}, {}
  for i = 1, 12 do FLAT[i] = { label = "FLAT" .. i } end
  for i = 1, 5 do VIEW[i] = { label = "VIEW" .. i } end

  local Builtin = {}
  Builtin.__index = Builtin
  function Builtin.new(game)
    return setmetatable({ game = game, rows = FLAT, view = VIEW,
                          index = 1, scroll = 0 }, Builtin)
  end
  function Builtin.draw() end
  -- the engine moves the cursor over the view, CANCEL sitting past its end
  function Builtin.update(self, dir)
    local cancelRow = #(self.view or self.rows) + 1
    if dir == "down" then
      self.index = self.index < cancelRow and self.index + 1 or 1
    end
  end

  local saved = package.loaded["src.ui.OptionsMenu"]
  package.loaded["src.ui.OptionsMenu"] = Builtin
  local state = registered.record.new({})
  package.loaded["src.ui.OptionsMenu"] = saved

  state.index = #VIEW
  state:update("down")
  T.eq(state.index, 1,
    "down off the last visible row wraps, measured against the view")

  state.index = 2
  state:draw()
  T.eq(drawn, VIEW, "and the screen draws the view, not the flat list")
  T.eq(#drawn, #VIEW, "which is the shorter of the two")
end

-- Rows that ask for the top.  The engine lays out the rows its own ORDER names
-- first and appends the rest, so a row added through the ui.options.rows hook
-- cannot reach the front however it anchors itself.  `top = true` asks; this
-- lifts them, in the order they already had, and leaves the flat list alone.
do
  local registered
  local optionsMod = {
    ui = {}, log = modStub.log,
    content = { screens = { register = function(_, id, record)
      registered = { id = id, record = record }
    end } },
  }
  -- hide_cancel OFF: the hoist is the list's order, not its drawing, so it
  -- must not depend on whether CANCEL is being hidden
  T.check(Menus.installOptionsScreen(optionsMod, Skin,
    reader({ hide_cancel = false })), "registered with HIDE CANCEL off")

  local FLAT = { { id = "textSpeed" } }
  local VIEW = {
    { id = "group.speed", label = "SPEED" },
    { id = "mods", label = "MODS" },
    { id = "Gen1MenuManager", label = "MENU MANAGER", top = true },
    { id = "controls", label = "CONTROLS" },
  }
  local Builtin = {}
  Builtin.__index = Builtin
  function Builtin.new(game)
    return setmetatable({ game = game, rows = FLAT, view = VIEW,
                          index = 1, scroll = 0 }, Builtin)
  end
  function Builtin.draw() end
  function Builtin.update() end

  local saved = package.loaded["src.ui.OptionsMenu"]
  package.loaded["src.ui.OptionsMenu"] = Builtin
  local state = registered.record.new({})
  package.loaded["src.ui.OptionsMenu"] = saved

  T.eq(state.view[1].label, "MENU MANAGER", "the row that asked is first")
  T.eq(state.view[2].label, "SPEED", "and the rest keep their own order")
  T.eq(state.view[3].label, "MODS", "including MODS")
  T.eq(state.view[4].label, "CONTROLS", "and the platform rows behind it")
  T.eq(#state.view, #VIEW, "no row is lost or gained")
  T.eq(state.rows, FLAT, "the flat list the hook built is untouched")
end

do -- the scroll clamp that replaces OptionRows.clampScroll
  T.eq(Skin.clampPlainScroll(1, 0, 9), 0, "the top of the list needs no scroll")
  T.eq(Skin.clampPlainScroll(9, 0, 9), 9 - Skin.CARDS,
    "the bottom pulls the window down to it")
  T.eq(Skin.clampPlainScroll(2, 6, 9), 1, "and moving back up pulls it up")
  T.eq(Skin.clampPlainScroll(1, 0, 2), 0, "a list shorter than the window sits still")
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

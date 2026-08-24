-- Registering the screen, and decorating the instance the engine builds.
--
-- src/ui/Screens.lua resolves a screen id out of Data.screens before falling
-- back to its builtin table, and it stamps `screenId` on whatever comes
-- back, so the F10 toggle in src/core/Game.lua still recognises the
-- instance.  It also pcalls a mod factory's `new` and degrades to the
-- builtin if it throws -- which is the outermost of this mod's three ways
-- back to the vanilla screen.
--
-- Every substitution below lands on ONE instance, built fresh on each push.
-- Nothing is written back to the engine's module table, so a failure here
-- cannot outlive the screen it happened on.

local Screen = {}

-- Where the cursor was the last time the list was open, for the length of
-- this session.  Not persisted: ManagerState:goBack already restores the
-- cursor within a visit through its own backStack, and what this adds is the
-- next visit.  Deliberately not per-save -- the manager opens from the title
-- screen, before Game:adoptSave has bound a playthrough to write to.
local memory = {}

local function decorate(mod, Rows, Skin, opt, state, Builtin)
  local R = Skin.newRenderer(mod, Rows, opt, Builtin)
  local LIST_ROWS = Skin.LIST_ROWS
  local broken = false
  local warned = {}
  local optionsCache = nil

  -- Read on every call rather than latched at construction, so PRESENTATION
  -- takes effect on the next frame -- the row is on this mod's own options
  -- page, which is drawn by the thing it switches off.
  local function modern()
    return not broken and opt("presentation") == "modern"
  end

  local function warnOnce(key, fmt, ...)
    if warned[key] then return end
    warned[key] = true
    mod.log:warn(fmt, ...)
  end

  -- ------- the mod list: sorting and filtering

  -- Whether each mod has an options page.  schemaFor can COMPILE a schema
  -- file for a mod that shipped one without runtime rows, so this is worth
  -- exactly one pass -- and modRows runs a few times a frame.  Dropped on
  -- refresh, and rebuilt on demand so switching the filter on while the list
  -- is open does not need one.
  local function optionsMap(self)
    if optionsCache then return optionsCache end
    local map = {}
    for _, m in ipairs(self.status and self.status.available or {}) do
      local ok, schema = pcall(self.schemaFor, self, m)
      map[m.id] = (ok and schema ~= nil) or false
    end
    optionsCache = map
    return map
  end

  local function entriesFor(self)
    local wantOptions = opt("only_options")
    local hasOptions = wantOptions and optionsMap(self) or nil
    local entries = {}
    for _, m in ipairs(self.status and self.status.available or {}) do
      entries[#entries + 1] = {
        mod = m,
        id = m.id,
        name = m.name or m.id,
        category = m.category or "OTHER",
        state = R.stateOf(self, m),
        hasOptions = hasOptions and hasOptions[m.id] or false,
      }
    end
    return entries
  end

  state.modRows = function(self)
    if not modern() then return Builtin.modRows(self) end
    local ok, rows = pcall(function()
      return Rows.arrange(entriesFor(self), {
        sort = opt("sort"),
        hide_disabled = opt("hide_disabled"),
        only_options = opt("only_options"),
      }, mod.id)
    end)
    if ok and type(rows) == "table" and #rows > 0 then return rows end
    warnOnce("modRows", "the mod list could not be arranged (%s) -- "
      .. "keeping the engine's order", tostring(rows))
    return Builtin.modRows(self)
  end

  state.refresh = function(self)
    optionsCache = nil
    return Builtin.refresh(self)
  end

  -- ------- the per-mod options page

  local function decorateOptions(self, m, schema, rows)
    local byKey = {}
    for _, row in ipairs(schema) do
      if type(row) == "table" and type(row.key) == "string" then
        byKey[row.key] = row
      end
    end
    for _, row in ipairs(rows) do
      local source = byKey[row.id]
      if source then
        row.help = Rows.helpFor(source)
        -- optionValue answers the row default when nothing is stored, so
        -- this is "differs from what the author shipped" either way
        row.changed = Rows.changed(self:optionValue(m.id, source),
                                   source.default)
      end
    end

    if opt("reset_row") and #rows > 0 then
      rows[#rows + 1] = {
        id = "gen1_mod_menu:reset",
        label = "RESET DEFAULTS",
        help = "PUT BACK THE AUTHOR'S VALUES",
        activate = function()
          for _, source in ipairs(schema) do
            if type(source) == "table" and type(source.key) == "string"
                and source.default ~= nil then
              -- setOption is the engine's only writer: it stages the value,
              -- persists it and emits mod.options_changed, so a mod watching
              -- its own rows hears a reset the same as a hand edit
              self:setOption(m.id, source.key, source.default)
            end
          end
          -- visible_if rows can appear or vanish with the values that drive
          -- them, so the list is rebuilt rather than repainted
          self.optionRows = self:buildOptionRows(m, schema)
          self.cursor = math.max(1, math.min(self.cursor, #self.optionRows))
          self:notify("DEFAULTS RESTORED")
        end,
      }
    end
    return rows
  end

  state.buildOptionRows = function(self, m, schema)
    local rows = Builtin.buildOptionRows(self, m, schema)
    if not modern() or type(rows) ~= "table" then return rows end
    local ok, decorated = pcall(decorateOptions, self, m, schema, rows)
    if ok and type(decorated) == "table" then return decorated end
    warnOnce("optionRows", "the options page could not be annotated (%s) -- "
      .. "showing the rows plain", tostring(decorated))
    return rows
  end

  -- The engine clamps this page with OptionRows.clampScroll, which is sized
  -- for the four 20x4 boxes vanilla draws.  This page shows eleven rows, so
  -- it owns its own clamp.  Scroll is 0-based here, the way ManagerState:goTo
  -- and OptionRows.draw both treat it.
  local function clampOptionScroll(cursor, scroll, total, visible)
    scroll = scroll or 0
    if cursor <= scroll then return math.max(0, cursor - 1) end
    if cursor > scroll + visible then return cursor - visible end
    local tail = math.max(0, total - visible)
    if scroll > tail then return tail end
    return scroll
  end

  state.updateOptions = function(self, input)
    local result = Builtin.updateOptions(self, input)
    -- B leaves the page through goBack, which restores the LIST's scroll;
    -- re-clamping it here would corrupt it
    if modern() and self.screen == "options" then
      local rows = self.optionRows or {}
      self.scroll = clampOptionScroll(self.cursor, self.scroll, #rows,
                                      R.optionWindow())
    end
    return result
  end

  -- ------- the ERRORS tab, when there is nothing wrong

  state.errorRows = function(self, m)
    local rows = Builtin.errorRows(self, m)
    if not modern() or m ~= nil then return rows end
    if #rows ~= 1 or rows[1].label ~= "NO ERRORS" then return rows end
    -- An otherwise empty tab is where someone wondering what STGD or BLKD
    -- means will look, and it costs nothing to answer there.
    local legend = { { header = true, label = "NO ERRORS" } }
    for _, entry in ipairs(Rows.LEGEND) do
      legend[#legend + 1] = { inert = true, label = entry[2], state = entry[1] }
    end
    return legend
  end

  -- ------- cursor memory

  state.enter = function(self)
    Builtin.enter(self)
    if not (modern() and opt("cursor_memory") and memory.cursor) then return end
    self.tab = memory.tab or self.tab
    self.cursor = memory.cursor
    self.scroll = memory.scroll or 1
    -- the remembered row may be gone, or may now be a group heading
    self:snapCursor()
    if self.cursor < self.scroll then self.scroll = self.cursor end
    if self.cursor > self.scroll + LIST_ROWS - 1 then
      self.scroll = self.cursor - LIST_ROWS + 1
    end
    if self.scroll < 1 then self.scroll = 1 end
  end

  state.update = function(self)
    local result = Builtin.update(self)
    if self.screen == "list" then
      memory.tab, memory.cursor, memory.scroll = self.tab, self.cursor, self.scroll
    end
    return result
  end

  -- ------- drawing

  state.draw = function(self)
    if not modern() then return Builtin.draw(self) end
    local ok, err = pcall(R.draw, self)
    if ok then return end
    broken = true
    mod.log:error("the mod menu failed to draw (%s) -- the engine's own "
      .. "manager takes over for the rest of this visit", tostring(err))
    return Builtin.draw(self)
  end

  return state
end

Screen.decorate = decorate

function Screen.install(mod, Rows, Skin, opt)
  local ok, err = pcall(function()
    mod.content.screens:register("ManagerState", {
      new = function(game)
        -- Required here rather than at load: this runs only in a real game,
        -- and a failure is caught by Screens.build's own pcall, which then
        -- builds the engine's manager instead.
        local got, Builtin = pcall(require, "src.mods.ManagerState")
        if not got or type(Builtin) ~= "table"
            or type(Builtin.new) ~= "function" then
          mod.log:error("the engine's mod manager could not be loaded (%s) "
            .. "-- leaving the screen alone", tostring(Builtin))
          error("gen1_mod_menu: no builtin manager to decorate", 0)
        end
        return decorate(mod, Rows, Skin, opt, Builtin.new(game), Builtin)
      end,
    })
  end)
  if not ok then
    mod.log:error("the mod menu screen could not be registered (%s) -- the "
      .. "manager stays vanilla", tostring(err))
    return false
  end
  return true
end

return Screen

-- The two edits outside the mod manager itself: the START menu's row, and
-- the CANCEL line on the game's own OPTION screen.
--
-- Both are gated on STYLE, so putting that row back on VANILLA puts the
-- whole mod back -- these included -- rather than only its drawing.

local Menus = {}

-- Not through Strings: there is no catalog key for it, and Strings.lookup
-- answers with the source when a translation has nothing to say, so passing
-- it through would buy nothing and read as though it might.  A translation
-- mod that wants this word can rewrite the row like any other label.
local START_LABEL = "MOD MENU"

-- src/ui/OptionRows.lua VISIBLE, which is also this mod's card count.
local function active(opt, key)
  return opt("presentation") == "modern" and opt(key)
end

-- ------- the START menu
--
-- The engine already puts a row here, gated on at least one discovered mod
-- (src/ui/StartMenu.lua) -- a condition this mod satisfies by existing -- so
-- the work is renaming that row rather than adding a second one beside it.
-- Matched on the label the engine would have produced, so a translation mod
-- that rewrote MODS is still recognised.
--
-- Wrapped at the default priority, not outermost: Gen1MenuManager takes
-- priority 1000 to arrange this list after everyone has finished appending
-- to it, and a row renamed here is a row it can then move, hide or leave
-- alone like any other.
function Menus.installStartRow(mod, opt)
  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local built = nextFn(game, items)
    if type(built) ~= "table" then return built end
    if not active(opt, "start_row") then return built end

    local ok, err = pcall(function()
      local vanilla = "MODS"
      local got, Strings = pcall(require, "src.core.Strings")
      if got and Strings then
        local said, text = pcall(Strings, "MODS")
        if said and type(text) == "string" then vanilla = text end
      end
      for _, row in ipairs(built) do
        if row.label == vanilla then
          row.label = START_LABEL
          return
        end
      end
      -- No row to rename: a build that gates the engine's own differently
      -- should still have a way in from here.
      built[#built + 1] = {
        label = START_LABEL,
        onSelect = function() mod.ui.push(game, "ManagerState") end,
      }
    end)
    if not ok then
      mod.log:warn("the START menu row was left alone: %s", tostring(err))
    end
    return built
  end)
end

-- ------- the game's OPTION screen
--
-- CANCEL is not one of the rows: src/ui/OptionsMenu.lua appends it after the
-- ui.options.rows hook and draws it as OptionRows' fixed bottom line, which
-- is what stops a mod from orphaning the exit.  It is also not the only exit
-- -- B and START both leave, with the same sound and the same pop -- so what
-- it costs is a line of the screen for a second way out of a menu every
-- other menu in the game leaves with B.
--
-- Removing it means owning this screen's drawing, which is why the update
-- wrapper below never touches input.  The engine's own update runs first and
-- in full, every time; all that happens afterwards is that a cursor parked
-- on the row that is no longer drawn gets moved onto one that is.  A bug in
-- here can misplace the cursor.  It cannot take away the way out.
function Menus.installOptionsScreen(mod, Skin, opt)
  local ok, err = pcall(function()
    mod.content.screens:register("OptionsMenu", {
      new = function(game, ...)
        local got, Builtin = pcall(require, "src.ui.OptionsMenu")
        if not got or type(Builtin) ~= "table"
            or type(Builtin.new) ~= "function" then
          mod.log:error("the engine's OPTION screen could not be loaded (%s) "
            .. "-- leaving it alone", tostring(Builtin))
          error("gen1_mod_menu: no builtin options menu to decorate", 0)
        end
        local state = Builtin.new(game, ...)
        local broken = false

        local function on()
          return not broken and active(opt, "hide_cancel")
        end

        state.update = function(self, dt)
          local before = self.index
          local result = Builtin.update(self, dt)
          if not on() then return result end
          local rows = self.rows or {}
          local n = #rows
          -- CANCEL is index n+1 and is no longer drawn, so the cursor is put
          -- back on a row that is: wrapping to the top if it arrived going
          -- down, and to the last row if it arrived going up, which is what
          -- the visible rows do between themselves.
          if n > 0 and (self.index or 1) > n then
            self.index = (before == n) and 1 or n
            self.scroll = Skin.clampPlainScroll(self.index, self.scroll, n)
          end
          return result
        end

        state.draw = function(self)
          if not on() then return Builtin.draw(self) end
          local drew, drawErr = pcall(Skin.drawPlainRows, mod.ui, self.game,
            self.rows or {}, self.index, self.scroll or 0)
          if drew then return end
          broken = true
          mod.log:error("the OPTION screen failed to draw (%s) -- the "
            .. "engine's own takes it back, CANCEL and all", tostring(drawErr))
          return Builtin.draw(self)
        end

        return state
      end,
    })
  end)
  if not ok then
    mod.log:error("the OPTION screen was left alone (%s)", tostring(err))
    return false
  end
  return true
end

function Menus.install(mod, Skin, opt)
  Menus.installStartRow(mod, opt)
  return Menus.installOptionsScreen(mod, Skin, opt)
end

return Menus

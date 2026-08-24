-- The screen itself.
--
-- The engine's mod manager is src/mods/ManagerState.lua: one stack state
-- with six modes -- list (MODS/PROFILES/ERRORS tabs), detail, options,
-- permissions, errors and apply -- and no hook anywhere on it.  What it does
-- have is a registry entry: src/ui/Screens.lua resolves an id out of
-- Data.screens BEFORE falling back to the builtin module, so registering
-- "ManagerState" replaces the screen for every route in -- the START menu,
-- the OPTION screen, F10, and Gold's own push in src/core/Game2.lua.
--
-- What is replaced here is the DRAWING, and only the drawing.  The manager's
-- logic -- ManagerState.resolveToggle's dependency closure, staged changes,
-- apply-and-restart, profiles, safe mode, the Gen 2 override -- is a
-- thousand lines where a divergence does not look like a skin bug, it looks
-- like a boot that no longer comes up.  So this builds the engine's own
-- instance and hands back that object with its draw methods swapped, which
-- is why the mod declares `engine_internals`: reaching the builtin means
-- requiring it by name, and src/mods/Loader.lua attributes any bare `src.*`
-- require to that permission.  Nothing here patches engine code in place;
-- the substitutions land on one instance, built fresh on every push.
--
-- Two independent ways back to the vanilla screen, because this is the one
-- screen a player uses to switch off a mod that is misbehaving:
--
--   * PRESENTATION: VANILLA, read on every call, so the row takes effect on
--     the next frame without leaving the screen; and
--   * a renderer that throws is logged once and permanently demoted to the
--     engine's own draw for the life of the instance.
--
-- On top of both, src/ui/Screens.lua already pcalls a mod screen's `new` and
-- falls back to the builtin, so a failure in here cannot strand anyone
-- outside the screen they need to fix it from.

local Skin = {}

-- The 20x18 tile screen, with the box border owning row 0 and row 17.
local COLS = 20
local CURSOR_X = 8         -- tile column 1
local LABEL_X = 16         -- tile column 2
local EDGE_X = 152         -- one past the last interior column
local RULE_FROM, RULE_TO = 1, 18

-- LIST_ROWS must stay 11: ManagerState:moveCursor clamps self.scroll to a
-- window of exactly that many rows, and adjustOrTab pages by it.  Drawing a
-- different number would let the cursor walk out of sight.
local LIST_TOP, LIST_ROWS = 4, 11

Skin.LIST_ROWS = LIST_ROWS

-- The options page sets its own window, so it also has to do its own clamp
-- (see clampOptionScroll): the engine's is OptionRows.clampScroll, sized for
-- the four 20x4 boxes vanilla draws.  Options scroll is 0-based here, the
-- way ManagerState:goTo and OptionRows.draw both treat it; every other mode
-- counts from 1.
local OPT_TOP = 3

-- ------- drawing helpers
--
-- Everything measures in pixels rather than glyph counts.  A font mod can
-- ship proportional TTF glyphs (Font.advanceOf answers 5px for those, 11 for
-- double-width kana), so a budget counted in tiles would overflow the box on
-- exactly the installs least able to afford it.

local function fit(Font, text, budget)
  text = tostring(text or "")
  if budget <= 0 then return "" end
  local spans = Font.split(text)
  local shown = Font.spansFitting(spans, budget)
  if shown >= #spans then return text end
  if shown <= 0 then return "" end
  -- cut on a glyph boundary: POKeDEX is seven glyphs across eight bytes, so
  -- a plain sub() can slice a character in half
  return text:sub(1, spans[shown].to)
end

local function rightAt(Font, text, edge, y)
  text = tostring(text or "")
  if text == "" then return edge end
  local x = edge - Font.width(text)
  Font.draw(text, x, y)
  return x
end

local function rule(Font, y, from, to)
  local code = (Font.BORDER and Font.BORDER.h) or 0x7A
  for col = from or RULE_FROM, to or RULE_TO do
    Font.drawCode(code, col * 8, y * 8)
  end
end

-- label on the left, value on the right, and the label yields when the two
-- would collide.  One line per row is the whole point of the mod: vanilla
-- spends a bordered 20x4 box per option and fits four on a screen.
local function pair(Font, label, value, y, gap)
  local py = y * 8
  local valueX = EDGE_X
  if value and value ~= "" then
    valueX = rightAt(Font, value, EDGE_X, py)
  end
  local budget = valueX - LABEL_X - (gap or 8)
  Font.draw(fit(Font, label, budget), LABEL_X, py)
end

-- ------- the renderer

local function newRenderer(mod, Rows, opt, Builtin)
  local Font, Theme

  local function toolkit()
    -- resolved on first draw, not at load: mod.ui loads its widgets lazily so
    -- a headless loader never drags the render stack in, and this mod is
    -- loaded by that same headless loader in its own test suite
    Font = Font or mod.ui.Font
    Theme = Theme or mod.ui.Theme
    return Font, Theme
  end

  local R = {}

  function R.optionWindow()
    -- the help line gives its row back when it is switched off
    return opt("help_line") and 11 or 12
  end

  -- ------- one row of a list

  local function drawCursor(state, index, y)
    if index == state.cursor then
      Font.drawCode(Theme.cursor, CURSOR_X, y * 8)
    end
  end

  -- A group heading: the label, then the rule running out to the right
  -- margin.  The cursor never lands here (ManagerState:moveCursor skips
  -- headers), so it reads as a divider rather than a choice.
  local function drawHeader(label, y)
    local text = fit(Font, label, EDGE_X - LABEL_X - 24)
    Font.draw(text, LABEL_X, y * 8)
    local from = math.floor((LABEL_X + Font.width(text)) / 8) + 1
    rule(Font, y, from, RULE_TO)
  end

  -- ------- list

  function R.drawList(state)
    local rows = state:rowsForScreen()
    local TABS = { "[MODS] PROF ERRS", "MODS [PROF] ERRS", "MODS PROF [ERRS]" }
    Font.draw(TABS[state.tab] or TABS[1], LABEL_X, 2 * 8)

    -- position, so a long list says where in itself you are
    local total, ordinal = 0, 0
    for i, row in ipairs(rows) do
      if not row.header then
        total = total + 1
        if i == state.cursor then ordinal = total end
      end
    end
    if total > 0 then
      rightAt(Font, ordinal .. "/" .. total, EDGE_X, 2 * 8)
    end

    rule(Font, 3)

    local last = math.min(#rows, (state.scroll or 1) + LIST_ROWS - 1)
    local y = LIST_TOP
    for i = state.scroll or 1, last do
      local row = rows[i]
      if row.header then
        drawHeader(row.label, y)
      else
        pair(Font, row.label, row.state, y)
        drawCursor(state, i, y)
      end
      y = y + 1
    end
    if #rows > last then
      Font.drawCode(Theme.moreArrow, 18 * 8, (LIST_TOP + LIST_ROWS) * 8)
    end

    if state.tab == 1 then
      R.footer(state, "A:OPEN SEL:TOGGLE", "START:APPLY B:EXIT")
    elseif state.tab == 2 then
      R.footer(state, "A:APPLY SEL:RENAME", "START:DELETE")
    else
      R.footer(state, "UP/DOWN:SCROLL")
    end
  end

  -- ------- detail
  --
  -- The action rows are pinned to the bottom and the description takes
  -- whatever is left, so a mod carrying every row it can (ENABLE, OPTIONS,
  -- PERMISSIONS, the Gen 2 override, FOR, GH, EXPERIMENTAL, VIEW ERROR,
  -- BACK) still fits.  Vanilla draws that ninth row at tile 19, off the
  -- bottom of a screen that ends at 17.

  function R.drawDetail(state)
    local m = state.currentMod
    if not m then return end
    local rows = state:rowsForScreen()

    pair(Font, m.name or m.id, m.version and ("v" .. m.version) or nil, 1)
    rule(Font, 2)

    local words = { STGD = "STAGED", OFF = "DISABLED", ERR = "FAILED",
                    BLKD = "BLOCKED", SKIP = "NOT THIS GAME", ON = "ENABLED" }
    local state_ = R.stateOf(state, m)
    pair(Font, words[state_] or state_,
         (m.category or "OTHER") .. "/" .. (m.profile or "content"), 3)

    local actionTop = math.max(5, 17 - #rows)
    local descTop, descBottom = 4, actionTop - 2
    local lines = R.wrap(m.error and ("FAILED: " .. m.error)
      or (m.note and ("SKIPPED: " .. m.note)) or m.description or "", 16)
    local visible = descBottom - descTop + 1
    for i = 1, visible do
      local line = lines[(state.descScroll or 1) + i - 1]
      if not line then break end
      Font.draw(line, LABEL_X, (descTop + i - 1) * 8)
    end
    if (state.descScroll or 1) + visible <= #lines then
      Font.drawCode(Theme.moreArrow, 18 * 8, descBottom * 8)
    end

    rule(Font, actionTop - 1)
    for i, row in ipairs(rows) do
      local y = actionTop + i - 1
      if y <= 16 then
        Font.draw(fit(Font, row.label, EDGE_X - LABEL_X), LABEL_X, y * 8)
        drawCursor(state, i, y)
      end
    end
  end

  -- ------- permissions / errors

  function R.drawSimple(state, title, line1, line2)
    Font.draw(title, LABEL_X, 1 * 8)
    rule(Font, 2)
    local rows = state:rowsForScreen()
    local top, window = 3, 11
    local last = math.min(#rows, (state.scroll or 1) + window - 1)
    local y = top
    for i = state.scroll or 1, last do
      local row = rows[i]
      if row.header then
        drawHeader(row.label, y)
      elseif row.state then
        -- the mark legend: the same right-hand column the list uses, in the
        -- same place, so the two read as one thing
        pair(Font, row.label, row.state, y)
      else
        local x = LABEL_X
        if row.glyph and row.glyph ~= " " then
          Font.draw(row.glyph, LABEL_X, y * 8)
          x = LABEL_X + 16
        end
        Font.draw(fit(Font, row.label, EDGE_X - x), x, y * 8)
      end
      if not (row.inert or row.header) then drawCursor(state, i, y) end
      y = y + 1
    end
    if #rows > last then
      Font.drawCode(Theme.moreArrow, 18 * 8, (top + window) * 8)
    end
    R.footer(state, line1, line2)
  end

  -- ------- apply

  function R.drawApply(state)
    Font.draw("PENDING CHANGES", LABEL_X, 1 * 8)
    rule(Font, 2)
    local staged = state:stagedList()
    local rows = state:rowsForScreen()
    local actionTop = math.max(5, 17 - #rows)

    local y = 3
    if #staged == 0 then
      Font.draw("NO CHANGES", LABEL_X, y * 8)
    end
    for i = 1, math.min(#staged, actionTop - 4) do
      local m = staged[i]
      pair(Font, m.name or m.id, m.enabled and "ON" or "OFF", y)
      y = y + 1
    end
    local hidden = #staged - (actionTop - 4)
    if hidden > 0 then
      -- "N MORE", not "+N": the Game Boy charmap has no + glyph (nor * ~ < >
      -- & =), and a character it does not carry is drawn as a space
      rightAt(Font, hidden .. " MORE", EDGE_X, (y - 1) * 8)
    end

    rule(Font, actionTop - 1)
    for i, row in ipairs(rows) do
      local ry = actionTop + i - 1
      if ry <= 16 then
        Font.draw(fit(Font, row.label, EDGE_X - LABEL_X), LABEL_X, ry * 8)
        drawCursor(state, i, ry)
      end
    end
  end

  -- ------- the per-mod options page
  --
  -- The one screen this mod exists for.  Vanilla renders it through
  -- src/ui/OptionRows.lua: four bordered 20x4 boxes, label on one line and
  -- value on the next, four options visible at a time and nothing else on
  -- screen.  Here each option is one line -- label left, value right -- so
  -- eleven fit, with the mod's name above them and a line below saying what
  -- the focused row accepts.
  --
  -- OptionRows is also on the engine's own GEN1_ONLY_MODULES list
  -- (src/mods/Loader.lua): it "paints Red's chrome over Gold's options
  -- screen, whose layout is one 18x16 box rather than four 20x4 ones".
  -- Drawing the rows here rather than through it is what makes this page
  -- right on Gold as well.

  function R.drawOptions(state)
    local m = state.currentMod
    local rows = state.optionRows or {}
    local window = R.optionWindow()

    pair(Font, (m and (m.name or m.id)) or "OPTIONS",
         m and m.version and ("v" .. m.version) or nil, 1)
    rule(Font, 2)

    local scroll = state.scroll or 0
    for slot = 1, window do
      local i = scroll + slot
      local row = rows[i]
      if not row then break end
      local y = OPT_TOP + slot - 1
      local value = ""
      if row.value then
        local ok, text = pcall(row.value, state.game)
        value = ok and tostring(text or "") or ""
      end
      -- the changed marker sits outside the value so a numeric value is
      -- never read as one digit longer than it is
      local edge = EDGE_X
      if row.changed then
        Font.draw(".", (RULE_TO - 1) * 8, y * 8)
        edge = EDGE_X - 16
      end
      local valueX = edge
      if value ~= "" then valueX = rightAt(Font, value, edge, y * 8) end
      Font.draw(fit(Font, row.label, valueX - LABEL_X - 8), LABEL_X, y * 8)
      drawCursor(state, i, y)
    end
    if #rows > scroll + window then
      Font.drawCode(Theme.moreArrow, 18 * 8, (OPT_TOP + window) * 8)
    end

    if opt("help_line") then
      rule(Font, 14)
      local row = rows[state.cursor]
      local help = row and row.help
      if row and row.changed then
        help = (help and (help .. " ") or "") .. ".CHANGED"
      end
      if help then Font.draw(fit(Font, help, EDGE_X - LABEL_X), LABEL_X, 15 * 8) end
      R.footer(state, nil, "A/LEFT-RIGHT B:DONE")
    else
      rule(Font, 15)
      R.footer(state, nil, "A/LEFT-RIGHT B:DONE")
    end
  end

  -- ------- shared

  function R.footer(state, line1, line2)
    if state.notice then
      Font.draw(fit(Font, state.notice, EDGE_X - LABEL_X), LABEL_X, 16 * 8)
      return
    end
    if line1 then
      Font.draw(fit(Font, line1, EDGE_X - LABEL_X), LABEL_X, 15 * 8)
    end
    if line2 then
      Font.draw(fit(Font, line2, EDGE_X - LABEL_X), LABEL_X, 16 * 8)
    end
  end

  -- ManagerState's own wrap, which is file-local there.  Word wrap at a
  -- column budget, one list of lines per paragraph.
  function R.wrap(text, width)
    local lines = {}
    for paragraph in tostring(text or ""):gmatch("[^\n]+") do
      local line = ""
      for word in paragraph:gmatch("%S+") do
        if line == "" then
          line = word
        elseif #line + 1 + #word <= width then
          line = line .. " " .. word
        else
          lines[#lines + 1] = line
          line = word
        end
      end
      if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
  end

  -- The state word for one mod, from the same facts ManagerState:glyphFor
  -- reads.  isStaged and runsHere are methods, so this needs the instance.
  function R.stateOf(state, m)
    return Rows.stateOf({
      staged = state:isStaged(m),
      enabled = m.enabled and true or false,
      skipped = m.state == "wrong_generation" or not state:runsHere(m),
      blocked = m.state == "blocked_dependency",
      errored = m.error ~= nil,
    })
  end

  function R.draw(state)
    toolkit()
    if state.screen == "options" then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      Font.drawBox(0, 0, COLS, 18)
      love.graphics.setColor(0, 0, 0, 1)
      R.drawOptions(state)
      love.graphics.setColor(1, 1, 1, 1)
      -- the confirm/notice modal stays the engine's: it is a centred box with
      -- its own cursor index, and nothing about it is unreadable
      if state.overlay then Builtin.drawOverlay(state) end
      return
    end

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 0, COLS, 18)
    love.graphics.setColor(0, 0, 0, 1)

    if state.screen == "list" then
      Font.draw(state.banner or "MOD MANAGER", LABEL_X, 1 * 8)
      R.drawList(state)
    elseif state.screen == "detail" then
      R.drawDetail(state)
    elseif state.screen == "permissions" then
      R.drawSimple(state, "PERMISSIONS", "DECLARED BY AUTHOR,", "NOT ENFORCED")
    elseif state.screen == "errors" then
      R.drawSimple(state, "ERRORS", "UP/DOWN:SCROLL B:BACK")
    elseif state.screen == "apply" then
      R.drawApply(state)
    end

    love.graphics.setColor(1, 1, 1, 1)
    if state.overlay then Builtin.drawOverlay(state) end
  end

  return R
end

Skin.newRenderer = newRenderer

return Skin

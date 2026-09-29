-- The live viewport, and the one size everything else is a multiple of.
-- Kept identical in minit-template-defold and minit-sample-defold.
--
-- WHY NOT A DESIGN RESOLUTION. The Minit app gives a game a slot of roughly
-- 2:3 -- much wider relative to its height than a phone screen -- because the
-- game sits between the app's own header and its toolbar. A game drawn against
-- a fixed design width paints a fraction of that slot and leaves a band down
-- one side, and you cannot see it in a desktop browser at a phone viewport.
-- So the render script projects 0..window_width by 0..window_height and this
-- module rebuilds the layout from window.get_size() whenever it changes.
--
-- INPUT MAPPING, measured against a release wasm bundle in Chrome:
--   * window.get_size() returns BACKBUFFER pixels (1170x2532, not 960x1480).
--   * action.x/action.y, and every action.touch[i].x/y, are the normalised
--     position times the game.project display size -- a stretch mapping that
--     ignores the real aspect ratio. They are NOT backbuffer pixels, and touch
--     entries carry no per-finger screen_x.
-- Hence to_world(): divide out the display size, multiply by the window.

local M = {}

local DISPLAY_W = sys.get_config_int("display.width", 960)
local DISPLAY_H = sys.get_config_int("display.height", 1480)

M.width, M.height = 0, 0
M.unit = 0          -- the one size everything else is a multiple of

--- Convert an input action's coordinates into world (backbuffer) pixels.
function M.to_world(x, y)
    return x / DISPLAY_W * M.width, y / DISPLAY_H * M.height
end

--- Poll the window and rebuild if it changed. Returns true when it did.
function M.refresh()
    local w, h = window.get_size()
    if w <= 0 or h <= 0 or (w == M.width and h == M.height) then return false end
    M.width, M.height = w, h

    -- Tracks the narrow axis but is capped against height, so a very wide slot
    -- does not blow the art up past what fits vertically.
    M.unit = math.min(w / 9, h / 18)
    return true
end

return M

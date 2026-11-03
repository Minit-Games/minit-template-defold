-- Window size and tap-to-world conversion for a camera component.
-- Kept identical in minit-template-defold and minit-sample-defold.
--
-- INPUT MAPPING, measured against a release wasm bundle in Chrome:
--   * window.get_size() returns BACKBUFFER pixels (1170x2532, not 960x1480).
--   * action.x/action.y, and every action.touch[i].x/y, are the normalised
--     position times the game.project display size -- a stretch mapping that
--     ignores the real aspect ratio. They are NOT backbuffer pixels, and touch
--     entries carry no per-finger screen_x.
-- Hence to_world(): divide out the display size, multiply by the window, then
-- let the camera map backbuffer pixels to world.

local M = {}

local DISPLAY_W = sys.get_config_int("display.width", 960)
local DISPLAY_H = sys.get_config_int("display.height", 1480)

-- Backbuffer size and unit, filled by refresh(). They stay 0 until you call
-- refresh() (e.g. at the top of update), so call it first if you use them.
M.width, M.height = 0, 0
M.unit = 0          -- the one size everything else is a multiple of

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

-- Reads the window without touching M.width/M.height, so refresh() stays the
-- only writer and its return value stays truthful.
local function window_size()
    local w, h = window.get_size()
    if w > 0 and h > 0 then return w, h end
end

-- depth (both functions): distance from the camera plane along its forward
-- axis, in world units. Leave it nil for an orthographic camera. For a
-- perspective camera pass the distance to the plane you want, e.g. 800 for a
-- camera 800 units in front of z = 0; with 0 every point lands on the camera.

--- Convert an input action's coordinates into world coordinates through the
--- given camera (nil: the last enabled camera). Returns x, y, z.
function M.to_world(x, y, camera_url, depth)
    -- Before the window has a size there is no backbuffer to map through.
    local w, h = window_size()
    if not w then return x, y, 0 end
    local px, py = x / DISPLAY_W * w, y / DISPLAY_H * h
    local p = camera.screen_to_world(vmath.vector3(px, py, depth or 0), camera_url)
    return p.x, p.y, p.z
end

--- The world area the camera shows: left, bottom, width, height. For a
--- perspective camera this is the area on the plane at depth, assuming the
--- camera looks straight down -z.
function M.visible_rect(camera_url, depth)
    local w, h = window_size()
    if not w then return 0, 0, DISPLAY_W, DISPLAY_H end
    local d = depth or 0
    local bl = camera.screen_to_world(vmath.vector3(0, 0, d), camera_url)
    local tr = camera.screen_to_world(vmath.vector3(w, h, d), camera_url)
    return bl.x, bl.y, tr.x - bl.x, tr.y - bl.y
end

return M

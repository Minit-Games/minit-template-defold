-- Thin wrappers over the generic quad, 9-slice and label prototypes.
--
-- The whole interface is world-space sprites and labels rather than a .gui
-- scene. Defold's GUI positions nodes against a fixed design resolution and
-- reconciles the difference with per-node adjust modes; this game deliberately
-- has no design resolution, so a GUI would mean fighting the one system that
-- assumes one. Sprites and labels share the world's coordinate space, which is
-- backbuffer pixels, and so need no reconciliation at all.

local M = {}

local factories = {}

function M.init(quad_factory, text_factory, bar_factory)
    factories.quad = quad_factory
    factories.text = text_factory
    factories.bar = bar_factory
end

local Node = {}
Node.__index = Node

function Node:pos(x, y, z)
    self.x, self.y = x, y
    self.z = z or self.z
    go.set_position(vmath.vector3(x, y, self.z), self.url)
    return self
end

function Node:scale(sx, sy)
    go.set_scale(vmath.vector3(sx, sy or sx, 1), self.url)
    return self
end

function Node:rotate(deg)
    go.set(self.url, "euler.z", deg)
    return self
end

function Node:tint(c)
    go.cancel_animations(self.target, self.is_text and "color" or "tint")
    go.set(self.target, self.is_text and "color" or "tint", c)
    return self
end

function Node:outline(c)
    if self.is_text then go.set(self.target, "outline", c) end
    return self
end

function Node:text(str)
    if self.is_text then label.set_text(self.target, str) end
    return self
end

--- Resize a 9-sliced node. Its corners keep their radius at any size, which
--- scaling cannot do -- a scaled rounded rect is an ellipse.
function Node:size(w, h)
    go.set(self.target, "size", vmath.vector3(w, h, 0))
    return self
end

function Node:anim(name)
    if not self.is_text then sprite.play_flipbook(self.target, name) end
    return self
end

function Node:show(visible)
    if visible == self.visible then return self end
    self.visible = visible
    msg.post(self.target, visible and "enable" or "disable")
    return self
end

--- Animate any property of the underlying component.
function Node:animate(prop, to, easing, duration, delay, complete)
    go.animate(self.target, prop, go.PLAYBACK_ONCE_FORWARD, to,
               easing or go.EASING_OUTQUAD, duration or 0.2, delay or 0, complete)
    return self
end

function Node:animate_go(prop, to, easing, duration, delay, complete)
    go.animate(self.url, prop, go.PLAYBACK_ONCE_FORWARD, to,
               easing or go.EASING_OUTQUAD, duration or 0.2, delay or 0, complete)
    return self
end

function Node:cancel(prop)
    go.cancel_animations(self.url, prop)
    return self
end

local function make(kind, z)
    local id = factory.create(factories[kind], vmath.vector3(0, 0, z or 0))
    local is_text = kind == "text"
    local node = setmetatable({
        url = msg.url(nil, id, nil),
        target = msg.url(nil, id, is_text and "l" or "s"),
        is_text = is_text,
        x = 0, y = 0, z = z or 0,
        visible = true,
    }, Node)
    return node
end

--- An alpha-blended sprite.
function M.quad(anim, z) return make("quad", z):anim(anim) end

--- A 9-sliced sprite, sized rather than scaled.
function M.bar(anim, z) return make("bar", z):anim(anim) end

--- A distance-field label. Scale it freely; it stays crisp.
--- The outline colour is baked into main/text.go; override with :outline().
function M.text(str, z)
    return make("text", z):text(str or "")
end

return M

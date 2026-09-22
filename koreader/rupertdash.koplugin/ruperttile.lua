--[[--
A focusable, pressable block.

Focus draws a black ring around the content rather than inverting it, so a
black tile stays black and the design reads the same whether or not it holds
the ring. A press arrives as a tap at the centre of the widget, which is how
FocusManager delivers the 5-way's centre button.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local Tile = InputContainer:extend{
    content = nil,
    callback = nil,
    radius = 14,
}

function Tile:init()
    self.ring = FrameContainer:new{
        bordersize = 3,
        color = Blitbuffer.COLOR_WHITE,
        padding = 2,
        margin = 0,
        radius = self.radius,
        self.content,
    }
    self[1] = self.ring
    self.dimen = Geom:new{ x = 0, y = 0, w = self.ring:getSize().w, h = self.ring:getSize().h }
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Tile:onFocus()
    self.ring.color = Blitbuffer.COLOR_BLACK
    return true
end

function Tile:onUnfocus()
    self.ring.color = Blitbuffer.COLOR_WHITE
    return true
end

function Tile:onTapSelect()
    if self.callback then
        UIManager:nextTick(self.callback)
    end
    return true
end

return Tile

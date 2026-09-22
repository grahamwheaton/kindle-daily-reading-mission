--[[--
The Big Read: the weekly story where every page ends in a choice.

The Kindle renders this itself rather than reading a book, because the story
branches. A page is a picture (sometimes), a paragraph or two, and two choices
mapped to the physical page-turn buttons: the one on the left of the Kindle
takes the left choice, the one on the right takes the right choice. The 5-way
works too, for anyone who expects it to.

Progress is written after every choice, so putting it down and coming back
continues on the same page. Choices stick: there is no going back, which is
what makes them feel like decisions.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local JSON = require("json")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local State = require("rupertstate")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Tile = require("ruperttile")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE

local ARROW_LEFT = "\u{E74C}"
local ARROW_RIGHT = "\u{E753}"
local ICON_TROPHY = "\u{EC37}"

local function bold(size) return Font:getFace("NotoSans-Bold.ttf", size) end
local function regular(size) return Font:getFace("NotoSans-Regular.ttf", size) end
local function symbols(size) return Font:getFace("nerdfonts/symbols.ttf", size) end

local BigRead = FocusManager:extend{
    covers_fullscreen = true,
    story = nil,
    node_id = nil,
}

--- Load the story the sync downloaded, or nil with a reason.
function BigRead.load()
    local path = State.BIGREAD_DIR .. "/story.json"
    local file = io.open(path, "r")
    if not file then return nil, "No Big Read yet. A new one arrives each week." end
    local text = file:read("*a")
    file:close()
    local ok, story = pcall(JSON.decode, text)
    if not ok or type(story) ~= "table" or type(story.nodes) ~= "table" then
        logger.warn("rupertdash: Big Read could not be read", story)
        return nil, "This week's Big Read could not be opened."
    end
    story.id = State.bigReadId()
    return story
end

function BigRead:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }

    -- The physical page-turn buttons are the choices. Both names for each
    -- side, because the Kindle reports them differently in each orientation.
    self.key_events.ChooseLeft = { { "LPgFwd" }, event = "Choose", args = 1 }
    self.key_events.ChooseLeftBack = { { "LPgBack" }, event = "Choose", args = 1 }
    self.key_events.ChooseRight = { { "RPgFwd" }, event = "Choose", args = 2 }
    self.key_events.ChooseRightBack = { { "RPgBack" }, event = "Choose", args = 2 }
    self.key_events.Leave = { { "Home" } }
    self.key_events.LeaveBack = { { "Back" } }

    self.node_id = self.node_id or self.story.start
    self:build()
end

function BigRead:node()
    return self.story.nodes[self.node_id]
end

function BigRead:build()
    local node = self:node()
    if not node then
        logger.warn("rupertdash: Big Read node missing", self.node_id)
        self.node_id = self.story.start
        node = self:node()
    end

    local W, H = self.dimen.w, self.dimen.h
    local margin = 16
    local inner_w = W - 2 * margin

    local header = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = 4 },
        TextWidget:new{ text = self.story.title, face = bold(17), max_width = inner_w },
        VerticalSpan:new{ width = 4 },
        LineWidget:new{ dimen = Geom:new{ w = inner_w, h = 2 }, background = BLACK },
    }

    local choices = node.choices
    local ending = node.ending
    local bottom = ending and self:buildEnding(inner_w, ending) or self:buildChoices(inner_w, choices)
    local body_h = H - 2 * margin - header:getSize().h - bottom:getSize().h - 16

    local body = VerticalGroup:new{ align = "left" }
    if node.image then
        local path = State.BIGREAD_DIR .. "/" .. node.image
        if lfs.attributes(path, "mode") == "file" then
            local native = ImageWidget:new{ file = path, file_do_cache = false, scale_factor = 1 }
            local size = native:getSize()
            native:free()
            local scale = math.min(inner_w / size.w, (body_h * 0.45) / size.h)
            table.insert(body, CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = math.floor(size.h * scale) },
                ImageWidget:new{ file = path, file_do_cache = false, scale_factor = scale },
            })
            table.insert(body, VerticalSpan:new{ width = 12 })
        end
    end
    table.insert(body, TextBoxWidget:new{
        text = node.text,
        face = regular(26),
        width = inner_w,
        line_height = 0.3,
        height = body_h - (node.image and math.floor(body_h * 0.45) + 12 or 0),
        height_adjust = true,
        height_overflow_show_ellipsis = true,
    })

    self[1] = FrameContainer:new{
        width = W,
        height = H,
        bordersize = 0,
        padding = 0,
        padding_left = margin,
        padding_right = margin,
        background = WHITE,
        VerticalGroup:new{
            align = "left",
            header,
            VerticalSpan:new{ width = 10 },
            body,
            -- The choices sit at the bottom, under the hardware buttons that
            -- pick them, however short the page is.
            VerticalSpan:new{ width = math.max(6, body_h - body:getSize().h + 6) },
            bottom,
        },
    }
end

--- The two choices, side by side, labelled with the button that picks them.
function BigRead:buildChoices(width, choices)
    local gap = 10
    local button_w = math.floor((width - gap) / 2)
    local row = HorizontalGroup:new{ align = "top" }
    self.layout = { {} }
    for index, choice in ipairs(choices) do
        local arrow = index == 1 and ARROW_LEFT or ARROW_RIGHT
        local hint = index == 1 and "LEFT BUTTON" or "RIGHT BUTTON"
        local content = FrameContainer:new{
            width = button_w - 10,
            height = 118,
            bordersize = 2,
            radius = 10,
            padding = 8,
            VerticalGroup:new{
                align = "center",
                HorizontalGroup:new{
                    align = "center",
                    TextWidget:new{ text = arrow, face = symbols(20) },
                    HorizontalSpan:new{ width = 6 },
                    TextWidget:new{ text = hint, face = bold(13) },
                },
                VerticalSpan:new{ width = 6 },
                TextBoxWidget:new{
                    text = choice.text,
                    face = bold(19),
                    width = button_w - 36,
                    alignment = "center",
                    height = 62,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                },
            },
        }
        local tile = Tile:new{
            content = content,
            radius = 12,
            callback = function() self:choose(index) end,
        }
        if index == 2 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        table.insert(row, tile)
        table.insert(self.layout[1], tile)
    end
    self.selected = { x = 1, y = 1 }
    if self.layout[1][1] then self.layout[1][1]:onFocus() end
    return row
end

function BigRead:buildEnding(width, ending)
    self.layout = { {} }
    local content = FrameContainer:new{
        width = width - 10,
        height = 118,
        bordersize = 2,
        radius = 10,
        padding = 8,
        background = WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = width - 30, h = 98 },
            VerticalGroup:new{
                align = "center",
                HorizontalGroup:new{
                    align = "center",
                    TextWidget:new{ text = ICON_TROPHY, face = symbols(26) },
                    HorizontalSpan:new{ width = 8 },
                    TextWidget:new{ text = ending, face = bold(20), max_width = width - 80 },
                },
                VerticalSpan:new{ width = 8 },
                TextWidget:new{ text = "Press either button to finish", face = regular(15) },
            },
        },
    }
    local tile = Tile:new{ content = content, radius = 12, callback = function() self:finish(ending) end }
    table.insert(self.layout[1], tile)
    self.selected = { x = 1, y = 1 }
    tile:onFocus()
    return tile
end

function BigRead:choose(index)
    local node = self:node()
    if node.ending then
        self:finish(node.ending)
        return
    end
    local choice = node.choices and node.choices[index]
    if not choice or not self.story.nodes[choice.next] then return end
    self.node_id = choice.next
    State.saveBigReadProgress(self.story.id, self.node_id)
    self:build()
    UIManager:setDirty(self, "ui")
end

function BigRead:onChoose(index)
    self:choose(index)
    return true
end

function BigRead:finish(ending)
    State.recordBigRead(self.story.id, self.story.title, ending)
    State.saveBigReadProgress(self.story.id, self.story.start)
    UIManager:close(self)
    UIManager:show(InfoMessage:new{ text = ending .. "\n\nYou finished this week's Big Read." })
end

function BigRead:onLeave()
    UIManager:close(self)
    return true
end

BigRead.onLeaveBack = BigRead.onLeave

function BigRead:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

return BigRead

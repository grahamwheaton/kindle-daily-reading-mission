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
local ProgressWidget = require("ui/widget/progresswidget")
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

-- Reaching an ending is only a finish if it looks like reading rather than
-- button-mashing: a Big Read is at least a handful of pages and a few minutes.
local MIN_PAGES = 5
local MIN_SECONDS = 90

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
    self.opened_at = os.time()
    self.pages_turned = 0
    self:build()
end

function BigRead:node()
    return self.story.nodes[self.node_id]
end

--[[ How far through he is.

A branching story has no single length, so measure the journey still to run:
the fewest pages between here and any ending. Counting backwards from the
endings gives that for every page at once. He starts at the full distance and
an ending is nought, so the bar is honest about the way out, not about how much
of the whole story he has seen -- which he never will, since he only walks one
branch. ]]
function BigRead:distancesToEnding()
    if self.distances then return self.distances end
    local distances, queue = {}, {}
    for node_id, node in pairs(self.story.nodes) do
        if node.ending then
            distances[node_id] = 0
            table.insert(queue, node_id)
        end
    end
    -- Walk outwards from the endings: a page is one step further out than the
    -- nearest page it can reach.
    local index = 1
    while index <= #queue do
        local target = queue[index]
        index = index + 1
        for node_id, node in pairs(self.story.nodes) do
            if distances[node_id] == nil and node.choices then
                for _, choice in ipairs(node.choices) do
                    if choice.next == target then
                        distances[node_id] = distances[target] + 1
                        table.insert(queue, node_id)
                        break
                    end
                end
            end
        end
    end
    self.distances = distances
    return distances
end

function BigRead:progress()
    local distances = self:distancesToEnding()
    local total = distances[self.story.start]
    local remaining = distances[self.node_id]
    if not total or total == 0 or not remaining then return 0 end
    local done = (total - remaining) / total
    return math.max(0, math.min(1, done))
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
        VerticalSpan:new{ width = 6 },
        ProgressWidget:new{
            width = inner_w,
            height = 10,
            percentage = self:progress(),
            bordersize = 1,
            radius = 2,
        },
    }

    local choices = node.choices
    local ending = node.ending
    local bottom = ending and self:buildEnding(inner_w, ending) or self:buildChoices(inner_w, choices)
    local body_h = H - 2 * margin - header:getSize().h - bottom:getSize().h - 16

    local body = VerticalGroup:new{ align = "left" }
    local picture_h = 0
    if node.image then
        local path = State.BIGREAD_DIR .. "/" .. node.image
        -- A picture that will not decode must cost him the picture, not the
        -- story: one arrived truncated from the writer before the build
        -- learned to check.
        local ok, picture, height = pcall(function()
            local native = ImageWidget:new{ file = path, file_do_cache = false, scale_factor = 1 }
            local size = native:getSize()
            native:free()
            local scale = math.min(inner_w / size.w, (body_h * 0.45) / size.h)
            return ImageWidget:new{ file = path, file_do_cache = false, scale_factor = scale },
                math.floor(size.h * scale)
        end)
        if ok and picture then
            picture_h = height + 12
            table.insert(body, CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = height },
                picture,
            })
            table.insert(body, VerticalSpan:new{ width = 12 })
        elseif lfs.attributes(path, "mode") == "file" then
            logger.warn("rupertdash: Big Read picture would not open", node.image, picture)
        end
    end
    table.insert(body, TextBoxWidget:new{
        text = node.text,
        face = regular(26),
        width = inner_w,
        line_height = 0.3,
        height = body_h - picture_h,
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
    -- No ring to begin with. Highlighting one choice would say it is already
    -- picked, when in fact either button takes its own side. The ring appears
    -- only if he reaches for the 5-way instead.
    self.selected = { x = 1, y = 1 }
    self.ring_shown = false
    return row
end

--- The 5-way brings the ring out, on the side he pushed.
function BigRead:onFocusMove(args)
    local dx = args and args[1] or 0
    local choices = self:node().choices
    if not choices or #choices == 0 then return true end
    local index
    if not self.ring_shown then
        index = dx < 0 and 1 or 2
    else
        index = self.selected.x + (dx > 0 and 1 or -1)
        if index < 1 then index = 1 end
        if index > #choices then index = #choices end
    end
    for position, tile in ipairs(self.layout[1]) do
        if position == index then tile:onFocus() else tile:onUnfocus() end
    end
    self.selected = { x = index, y = 1 }
    self.ring_shown = true
    UIManager:setDirty(self, "fast")
    return true
end

--- The centre button does nothing until the ring is out: with no choice
--- highlighted there is nothing for it to confirm.
function BigRead:onPress()
    if not self.ring_shown then
        return self:onFocusMove({ -1, 0 })
    end
    return FocusManager.onPress(self)
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
    -- One thing to press here, so the ring is not ambiguous.
    self.ring_shown = true
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
    self.pages_turned = (self.pages_turned or 0) + 1
    State.saveBigReadProgress(self.story.id, self.node_id)
    self:build()
    UIManager:setDirty(self, "ui")
end

function BigRead:onChoose(index)
    self:choose(index)
    return true
end

function BigRead:finish(ending)
    local seconds = os.time() - (self.opened_at or os.time())
    local pages = self.pages_turned or 0
    if pages >= MIN_PAGES and seconds >= MIN_SECONDS then
        State.recordBigRead(self.story.id, self.story.title, ending, pages, seconds)
    else
        logger.info("rupertdash: Big Read ending reached in", seconds, "s over", pages,
            "pages; not recording it as read")
    end
    -- Either way the story starts again from the beginning next time.
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

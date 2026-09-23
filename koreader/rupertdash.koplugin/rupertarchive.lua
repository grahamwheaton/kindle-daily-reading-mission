--[[--
Previous missions, as cover thumbnails he can recognise.

A list of titles means nothing to a seven-year-old who remembers the picture,
so this shows the covers, six to a page, each marked finished or not. The
5-way walks the grid; the side buttons page through older missions; Back or
Home returns to the dashboard.
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
local LineWidget = require("ui/widget/linewidget")
local State = require("rupertstate")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Tile = require("ruperttile")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE

local ICON_LOGO = "\u{E2A6}"
local ICON_DONE = "\u{E82B}"     -- check
local COLUMNS = 3
local ROWS = 2

local function bold(size) return Font:getFace("NotoSans-Bold.ttf", size) end
local function regular(size) return Font:getFace("NotoSans-Regular.ttf", size) end
local function symbols(size) return Font:getFace("nerdfonts/symbols.ttf", size) end

local Archive = FocusManager:extend{
    missions = nil,     -- { { id, title, file }, ... }, newest first
    on_open = nil,      -- called with the mission's file
    covers_fullscreen = true,
    page = 1,
}

function Archive:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.key_events.Close = { { "Back" } }
    self.key_events.CloseHome = { { "Home" } }
    self.key_events.NextPageRight = { { "RPgFwd" }, event = "ChangePage", args = 1 }
    self.key_events.NextPageLeft = { { "LPgFwd" }, event = "ChangePage", args = 1 }
    self.key_events.PrevPageRight = { { "RPgBack" }, event = "ChangePage", args = -1 }
    self.key_events.PrevPageLeft = { { "LPgBack" }, event = "ChangePage", args = -1 }
    self:build()
end

function Archive:pageCount()
    return math.max(1, math.ceil(#self.missions / (COLUMNS * ROWS)))
end

function Archive:build()
    local W, H = self.dimen.w, self.dimen.h
    local margin = 10
    local inner_w = W - 2 * margin

    local header = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = 6 },
        TextWidget:new{ text = "PREVIOUS MISSIONS", face = bold(28) },
        VerticalSpan:new{ width = 6 },
        LineWidget:new{ dimen = Geom:new{ w = inner_w, h = 2 }, background = BLACK },
    }

    local gap = 10
    local cell_w = math.floor((inner_w - (COLUMNS - 1) * gap) / COLUMNS)
    local footer_h = 30
    local grid_h = H - 2 * margin - header:getSize().h - footer_h - 8
    local cell_h = math.floor((grid_h - (ROWS - 1) * gap) / ROWS)

    local first = (self.page - 1) * COLUMNS * ROWS + 1
    local grid = VerticalGroup:new{ align = "left" }
    self.layout = {}
    self.tiles = {}
    for row = 1, ROWS do
        local line = HorizontalGroup:new{ align = "top" }
        local layout_row = {}
        for column = 1, COLUMNS do
            local mission = self.missions[first + (row - 1) * COLUMNS + column - 1]
            if column > 1 then table.insert(line, HorizontalSpan:new{ width = gap }) end
            if mission then
                local tile = self:buildTile(mission, cell_w, cell_h)
                table.insert(line, tile)
                table.insert(layout_row, tile)
                table.insert(self.tiles, tile)
            else
                table.insert(line, HorizontalSpan:new{ width = cell_w })
            end
        end
        table.insert(grid, line)
        table.insert(grid, VerticalSpan:new{ width = gap })
        if #layout_row > 0 then table.insert(self.layout, layout_row) end
    end

    local pages = self:pageCount()
    local footer = TextWidget:new{
        text = pages > 1 and string.format("Page %d of %d   -   side buttons for more", self.page, pages)
            or "Press Back to return",
        face = regular(15),
    }

    self.selected = { x = 1, y = 1 }
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
            VerticalSpan:new{ width = 8 },
            grid,
            footer,
        },
    }
    if self.tiles[1] then self.tiles[1]:onFocus() end
end

function Archive:buildTile(mission, width, height)
    local done = State.isCompleted(mission.id)
    local label_h = 78
    local image_h = height - label_h - 10

    local cover_file = State.coverFor(mission.file, mission.id)
    local picture
    if cover_file then
        local native = ImageWidget:new{ file = cover_file, file_do_cache = false, scale_factor = 1 }
        local size = native:getSize()
        native:free()
        local scale = math.min((width - 16) / size.w, image_h / size.h)
        picture = ImageWidget:new{ file = cover_file, file_do_cache = false, scale_factor = scale }
    else
        picture = TextWidget:new{ text = ICON_LOGO, face = symbols(60) }
    end

    local status = done
        and HorizontalGroup:new{
            align = "center",
            TextWidget:new{ text = ICON_DONE, face = symbols(18) },
            HorizontalSpan:new{ width = 4 },
            TextWidget:new{ text = "Completed", face = bold(14) },
        }
        or TextWidget:new{ text = "Not completed", face = regular(14), fgcolor = Blitbuffer.gray(0.45) }

    local content = FrameContainer:new{
        width = width - 10,
        height = height - 10,
        bordersize = 2,
        radius = 10,
        padding = 4,
        VerticalGroup:new{
            align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = width - 22, h = image_h }, picture },
            VerticalSpan:new{ width = 4 },
            TextBoxWidget:new{
                text = mission.title,
                face = bold(15),
                width = width - 22,
                alignment = "center",
                height = 42,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            },
            CenterContainer:new{ dimen = Geom:new{ w = width - 22, h = 22 }, status },
        },
    }
    return Tile:new{
        content = content,
        radius = 12,
        callback = function()
            -- Completion is written by the reader after the book closes. The
            -- archive's status labels were built before opening the book, so
            -- discard this screen and rebuild them on the next visit.
            UIManager:close(self)
            if self.on_open then self.on_open(mission.file) end
        end,
    }
end

function Archive:onChangePage(direction)
    local page = self.page + direction
    if page < 1 or page > self:pageCount() then return true end
    self.page = page
    self:build()
    UIManager:setDirty(self, "ui")
    return true
end

function Archive:onClose()
    UIManager:close(self)
    return true
end

Archive.onCloseHome = Archive.onClose

function Archive:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

return Archive

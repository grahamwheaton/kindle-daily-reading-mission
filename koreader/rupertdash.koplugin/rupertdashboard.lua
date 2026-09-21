--[[--
Rupert's Reading Missions dashboard for the Kindle 4 (600x800, 5-way pad).

Mission details come from /mnt/us/rupert-mission/launcher.properties, which
the sync script downloads with each mission. Optional keys (all may be
missing): subtitle, blurb, mission, tag1..tag4 as "icon|text" where icon is
one of terrain, wrench, book, star.

The cover is /mnt/us/rupert-mission/cover.png when present, otherwise the
cover embedded in the mission book.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

local STATE_DIR = "/mnt/us/rupert-mission"
local MISSION_FILE = "/mnt/us/documents/RupertsMission.mobi"
local PROPERTIES_FILE = STATE_DIR .. "/launcher.properties"
local COVER_FILE = STATE_DIR .. "/cover.png"
local ARCHIVE_DIR = STATE_DIR .. "/archive"

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local BUTTON_GRAY = Blitbuffer.gray(0.70)

-- Material Design glyphs in KOReader's bundled nerdfonts/symbols.ttf.
local ICON = {
    logo = "\u{E2A6}",
    fire = "\u{E937}",
    book = "\u{E7BD}",
    compass = "\u{E88A}",
    chart = "\u{E827}",
    trophy = "\u{EC37}",
    cog = "\u{F013}",
    wifi = "\u{ECA8}",
    wifi_off = "\u{ECA9}",
    battery_charging = "\u{E783}",
    play = "\u{EB09}",
    terrain = "\u{EC08}",
    wrench = "\u{ECB6}",
    star = "\u{EBCD}",
}

local function bold(size) return Font:getFace("NotoSans-Bold.ttf", size) end
local function regular(size) return Font:getFace("NotoSans-Regular.ttf", size) end
local function symbols(size) return Font:getFace("nerdfonts/symbols.ttf", size) end

local function text(str, face, color, max_width)
    return TextWidget:new{ text = str, face = face, fgcolor = color or BLACK, max_width = max_width }
end

local function readProperties(path)
    local props = {}
    local f = io.open(path, "r")
    if not f then return props end
    for line in f:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key then props[key] = value end
    end
    f:close()
    return props
end

local function archivedMissions()
    local missions = {}
    if lfs.attributes(ARCHIVE_DIR, "mode") ~= "directory" then return missions end
    for name in lfs.dir(ARCHIVE_DIR) do
        local id = name:match("^(.+)%.mobi$")
        if id then
            local props = readProperties(ARCHIVE_DIR .. "/" .. id .. ".properties")
            table.insert(missions, { id = id, title = props.title or id, file = ARCHIVE_DIR .. "/" .. name })
        end
    end
    table.sort(missions, function(a, b) return a.id > b.id end)
    return missions
end

-- Calibre's MOBI output does not always carry a cover record (EXTH 201), so
-- take the first image record from the Palm database instead. Cached in tmpfs.
local function extractMobiImage(path, cache_base)
    for _, ext in ipairs({ "jpg", "png", "gif" }) do
        if lfs.attributes(cache_base .. "." .. ext, "mode") == "file" then
            return cache_base .. "." .. ext
        end
    end
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local function u16(o) local a, b = data:byte(o + 1, o + 2) return a * 256 + b end
    local function u32(o) local a, b, c, d = data:byte(o + 1, o + 4) return ((a * 256 + b) * 256 + c) * 256 + d end
    if #data < 78 or data:sub(61, 68) ~= "BOOKMOBI" then return nil end
    local count = u16(76)
    local offsets = {}
    for i = 0, count - 1 do offsets[i] = u32(78 + 8 * i) end
    offsets[count] = #data
    local first = u32(offsets[0] + 16 + 92)
    if first >= count then return nil end
    for i = first, count - 1 do
        local magic = data:sub(offsets[i] + 1, offsets[i] + 4)
        local ext = (magic:sub(1, 3) == "\255\216\255" and "jpg")
            or (magic == "\137PNG" and "png")
            or (magic:sub(1, 3) == "GIF" and "gif")
        if ext then
            local out = cache_base .. "." .. ext
            local w = io.open(out, "wb")
            if not w then return nil end
            w:write(data:sub(offsets[i] + 1, offsets[i + 1]))
            w:close()
            return out
        end
    end
    return nil
end

local function batteryIcon()
    local ok, powerd = pcall(function() return Device:getPowerDevice() end)
    if not ok or not powerd then return "\u{E778}" end
    if powerd:isCharging() then return ICON.battery_charging end
    local level = powerd:getCapacity() or 100
    if level >= 95 then return "\u{E778}" end
    -- battery-10 .. battery-90 are consecutive codepoints from U+E779.
    return require("util").unicodeCodepointToUtf8(0xE779 + math.max(0, math.floor(level / 10) - 1))
end

local function wifiIcon()
    local ok, on = pcall(function() return require("ui/network/manager"):isWifiOn() end)
    return (ok and on == false) and ICON.wifi_off or ICON.wifi
end

--[[ A focusable, pressable block. Focus draws a black ring around it; the
     block keeps its own colours so the design reads the same either way. ]]
local Tile = InputContainer:extend{
    content = nil,
    callback = nil,
}

function Tile:init()
    self.ring = FrameContainer:new{
        bordersize = 3,
        color = WHITE,
        padding = 2,
        margin = 0,
        radius = 14,
        self.content,
    }
    self[1] = self.ring
    self.dimen = Geom:new{ x = 0, y = 0, w = self.ring:getSize().w, h = self.ring:getSize().h }
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Tile:onFocus()
    self.ring.color = BLACK
    return true
end

function Tile:onUnfocus()
    self.ring.color = WHITE
    return true
end

function Tile:onTapSelect()
    if self.callback then
        UIManager:nextTick(self.callback)
    end
    return true
end

local Dashboard = FocusManager:extend{
    file_manager = nil,
    covers_fullscreen = true,
}

function Dashboard:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.props = readProperties(PROPERTIES_FILE)
    self.archive = archivedMissions()

    self.key_events.ExitToKindle = { { "Home" } }
    self.key_events.ShowSettings = { { "Menu" } }
    self.key_events.IgnoreBack = { { "Back" } }
    self.key_events.PageDown = { { { "RPgFwd", "LPgFwd" } }, event = "FocusMove", args = { 0, 1 } }
    self.key_events.PageUp = { { { "RPgBack", "LPgBack" } }, event = "FocusMove", args = { 0, -1 } }

    local W, H = self.dimen.w, self.dimen.h
    local M = 10
    local inner_w = W - 2 * M

    local status = self:buildStatusBar(inner_w)
    local header = self:buildHeader(inner_w)
    local main_h = H - M - status:getSize().h - header:getSize().h - 18
    local right_w = 170
    local left_w = inner_w - right_w - 6

    self.start_tile = self:buildMissionCard(left_w, main_h)
    local right, tiles = self:buildRightColumn(right_w, main_h)
    self.tiles = tiles

    -- Start is layout[y][1] on every row, so Left from any tile returns to it;
    -- onFocusMove below handles the rest.
    self.layout = {}
    for i, tile in ipairs(tiles) do
        self.layout[i] = { self.start_tile, tile }
    end
    self.selected = { x = 1, y = 1 }
    self.last_tile_row = 1

    self[1] = FrameContainer:new{
        width = W,
        height = H,
        padding = 0,
        padding_left = M,
        padding_right = M,
        bordersize = 0,
        background = WHITE,
        VerticalGroup:new{
            align = "left",
            status,
            VerticalSpan:new{ width = 8 },
            header,
            VerticalSpan:new{ width = 10 },
            HorizontalGroup:new{
                align = "top",
                self.start_tile,
                HorizontalSpan:new{ width = 6 },
                right,
            },
        },
    }
    self.start_tile:onFocus()
end

function Dashboard:buildStatusBar(width)
    local date = os.date("%a %d %b %Y"):upper()
    local left = HorizontalGroup:new{
        align = "center",
        text(wifiIcon(), symbols(22)),
        HorizontalSpan:new{ width = 14 },
        text("RUPERT", bold(17)),
    }
    local right = HorizontalGroup:new{
        align = "center",
        text(date, bold(17)),
        HorizontalSpan:new{ width = 12 },
        text(batteryIcon(), symbols(24)),
    }
    local h = 34
    return VerticalGroup:new{
        OverlapGroup:new{
            dimen = Geom:new{ w = width, h = h },
            LeftContainer:new{ dimen = Geom:new{ w = width, h = h }, left },
            RightContainer:new{ dimen = Geom:new{ w = width, h = h }, right },
        },
        LineWidget:new{ dimen = Geom:new{ w = width, h = 2 }, background = BLACK },
    }
end

function Dashboard:buildHeader(width)
    local logo_w = 112
    local title_w = width - 4 - 22 - logo_w - 14
    local title = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{ text = "RUPERT'S\nREADING MISSIONS", face = bold(36), width = title_w, line_height = 0 },
        VerticalSpan:new{ width = 6 },
        text("REAL STORIES. BIG IDEAS. FURTHER ADVENTURES.", bold(13)),
    }
    return FrameContainer:new{
        width = width,
        bordersize = 2,
        radius = 12,
        padding = 8,
        padding_left = 14,
        HorizontalGroup:new{
            align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = logo_w, h = 100 }, text(ICON.logo, symbols(104)) },
            HorizontalSpan:new{ width = 14 },
            title,
        },
    }
end

function Dashboard:buildMissionCard(width, height)
    local p = self.props
    local pad = 12
    local cw = width - 2 * pad - 4 - 10 -- inner width, less card border and the tile ring
    local number = p.mission or tostring(#self.archive + 1)

    local top_row = OverlapGroup:new{
        dimen = Geom:new{ w = cw, h = 22 },
        LeftContainer:new{ dimen = Geom:new{ w = cw, h = 22 }, text("[TODAY'S MISSION]", regular(15)) },
        RightContainer:new{ dimen = Geom:new{ w = cw, h = 22 }, text("[MISSION #" .. number .. "]", regular(15)) },
    }

    local title = TextBoxWidget:new{
        text = (p.title or "No mission yet"):upper(),
        face = bold(34),
        width = cw,
        line_height = 0,
    }
    local subtitle = TextBoxWidget:new{
        text = (p.subtitle or p.type or ""):upper(),
        face = bold(15),
        width = cw,
    }

    local button_h = 66
    local button = FrameContainer:new{
        width = cw,
        height = button_h,
        bordersize = 0,
        radius = 12,
        background = BUTTON_GRAY,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = cw, h = button_h },
            HorizontalGroup:new{
                align = "center",
                text("START MISSION", bold(32), WHITE),
                HorizontalSpan:new{ width = 14 },
                text(ICON.play, symbols(30), WHITE),
            },
        },
    }

    local fixed = 22 + 10 + title:getSize().h + 6 + subtitle:getSize().h + 12 + 14 + button_h
    local body_h = height - 2 * pad - 4 - 10 - fixed
    local body = self:buildMissionBody(cw, body_h)

    local card = FrameContainer:new{
        width = width - 10,
        height = height - 10,
        bordersize = 2,
        radius = 12,
        padding = pad,
        VerticalGroup:new{
            align = "left",
            top_row,
            VerticalSpan:new{ width = 4 },
            LineWidget:new{ dimen = Geom:new{ w = cw, h = 2 }, background = BLACK },
            VerticalSpan:new{ width = 4 },
            title,
            VerticalSpan:new{ width = 6 },
            subtitle,
            VerticalSpan:new{ width = 12 },
            body,
            -- Keep the button pinned to the bottom whatever the body's height.
            VerticalSpan:new{ width = 14 + math.max(0, body_h - body:getSize().h) },
            button,
        },
    }
    -- The whole card is the Start target: pressing anywhere on it starts.
    return Tile:new{ content = card, callback = function() self:startMission() end }
end

function Dashboard:buildMissionBody(width, height)
    local p = self.props
    local image_w = math.floor(width * 0.54)
    local gap = 12
    local side_w = width - image_w - gap

    local cover_file = COVER_FILE
    if lfs.attributes(cover_file, "mode") ~= "file" then
        local ok, found = pcall(extractMobiImage, MISSION_FILE,
            "/var/tmp/rupert-cover-" .. (p.id or "current"):gsub("[^%w-]", "_"))
        cover_file = ok and found or nil
        if not ok then logger.warn("rupertdash: cover extraction failed", found) end
    end
    local cover
    if cover_file then
        -- Scale to fit ourselves: with scale_factor = 0 the widget takes the
        -- whole box and centres the picture, which would not top-align.
        local native = ImageWidget:new{ file = cover_file, file_do_cache = false, scale_factor = 1 }
        local size = native:getSize()
        native:free()
        local scale = math.min(image_w / size.w, height / size.h)
        cover = ImageWidget:new{ file = cover_file, file_do_cache = false, scale_factor = scale }
    else
        cover = CenterContainer:new{
            dimen = Geom:new{ w = image_w, h = height },
            text(ICON.logo, symbols(120)),
        }
    end

    local side = VerticalGroup:new{ align = "left" }
    if p.blurb and p.blurb ~= "" then
        table.insert(side, TextBoxWidget:new{
            text = p.blurb,
            face = regular(15),
            width = side_w,
            height = math.floor(height * 0.55),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        })
        table.insert(side, VerticalSpan:new{ width = 14 })
    end
    local tags = {}
    for i = 1, 4 do
        local icon, label = (p["tag" .. i] or ""):match("^(%w+)|(.+)$")
        if icon and ICON[icon] then table.insert(tags, { ICON[icon], label }) end
    end
    if #tags == 0 then
        tags = { { ICON.book, "~5 min read" } }
    end
    for _, tag in ipairs(tags) do
        table.insert(side, HorizontalGroup:new{
            align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = 34, h = 34 }, text(tag[1], symbols(26)) },
            HorizontalSpan:new{ width = 8 },
            TextBoxWidget:new{ text = tag[2], face = regular(15), width = side_w - 42 },
        })
        table.insert(side, VerticalSpan:new{ width = 8 })
    end

    return HorizontalGroup:new{
        align = "top",
        CenterContainer:new{ dimen = Geom:new{ w = image_w, h = cover:getSize().h }, cover },
        HorizontalSpan:new{ width = gap },
        side,
    }
end

function Dashboard:buildRightColumn(width, height)
    local streak = tonumber(self.props.streak) or 0
    local streak_h = 136
    local streak_box = FrameContainer:new{
        width = width - 10,
        height = streak_h - 10,
        bordersize = 2,
        radius = 12,
        padding = 4,
        CenterContainer:new{
            dimen = Geom:new{ w = width - 22, h = streak_h - 22 },
            VerticalGroup:new{
                align = "center",
                text("STREAK", bold(16)),
                HorizontalGroup:new{
                    align = "center",
                    text(ICON.fire, symbols(40)),
                    HorizontalSpan:new{ width = 8 },
                    text(tostring(streak), bold(44)),
                },
                text(streak == 1 and "DAY" or "DAYS", bold(16)),
            },
        },
    }
    -- Pad to the same outer size as a Tile so the columns line up.
    local streak_wrap = FrameContainer:new{ bordersize = 0, padding = 5, streak_box }

    local entries = {
        { ICON.book, "PREVIOUS MISSIONS", function() self:showPrevious() end },
        { ICON.compass, "FACT FILES", function() self:comingSoon("Fact Files") end },
        { ICON.chart, "MY PROGRESS", function() self:showProgress() end },
        { ICON.trophy, "UNLOCKS", function() self:comingSoon("Unlocks") end },
        { ICON.cog, "SETTINGS", function() self:onShowSettings() end },
    }
    local gap = 4
    local tile_h = math.floor((height - streak_h - gap * #entries) / #entries)
    local column = VerticalGroup:new{ align = "left", streak_wrap }
    local tiles = {}
    for _, e in ipairs(entries) do
        local w, h = width - 10, tile_h - 10
        local block = FrameContainer:new{
            width = w,
            height = h,
            bordersize = 0,
            radius = 12,
            padding = 0,
            background = BLACK,
            LeftContainer:new{
                dimen = Geom:new{ w = w, h = h },
                HorizontalGroup:new{
                    align = "center",
                    HorizontalSpan:new{ width = 8 },
                    CenterContainer:new{ dimen = Geom:new{ w = 40, h = 40 }, text(e[1], symbols(34), WHITE) },
                    HorizontalSpan:new{ width = 8 },
                    TextBoxWidget:new{ text = e[2], face = bold(16), width = w - 62, fgcolor = WHITE, bgcolor = BLACK },
                },
            },
        }
        local tile = Tile:new{ content = block, callback = e[3] }
        table.insert(tiles, tile)
        table.insert(column, VerticalSpan:new{ width = gap })
        table.insert(column, tile)
    end
    return column, tiles
end

-- D-pad: Start is the left column; tiles form the right column.
function Dashboard:onFocusMove(args)
    local dx, dy = args[1], args[2]
    local x, y = self.selected.x, self.selected.y
    if x == 1 then
        if dx > 0 then
            return self:focusTo(2, self.last_tile_row)
        end
        return true
    end
    if dx < 0 then
        self.last_tile_row = y
        return self:focusTo(1, y)
    end
    if dy ~= 0 then
        local n = #self.tiles
        return self:focusTo(2, (y - 1 + dy) % n + 1)
    end
    return true
end

function Dashboard:focusTo(x, y)
    local current = self:getFocusItem()
    local target = self.layout[y][x]
    if current and current ~= target then current:onUnfocus() end
    self.selected = { x = x, y = y }
    if x == 2 then self.last_tile_row = y end
    target:onFocus()
    UIManager:setDirty(self, "fast")
    return true
end

function Dashboard:openBook(file)
    UIManager:close(self)
    require("apps/reader/readerui"):showReader(file)
end

function Dashboard:startMission()
    if lfs.attributes(MISSION_FILE, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{ text = "Today's mission hasn't arrived yet. Check back soon!" })
        return
    end
    self:openBook(MISSION_FILE)
end

function Dashboard:showPrevious()
    local items = {}
    for _, m in ipairs(self.archive) do
        table.insert(items, {
            text = m.title,
            mandatory = m.id,
            callback = function() self:openBook(m.file) end,
        })
    end
    if #items == 0 then
        UIManager:show(InfoMessage:new{ text = "Your finished missions will appear here." })
        return
    end
    local menu
    menu = Menu:new{
        title = "Previous missions",
        item_table = items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

function Dashboard:showProgress()
    local streak = tonumber(self.props.streak) or 0
    UIManager:show(InfoMessage:new{
        text = string.format("Missions completed: %d\nCurrent streak: %d day%s",
            #self.archive + 1, streak, streak == 1 and "" or "s"),
    })
end

function Dashboard:comingSoon(name)
    UIManager:show(InfoMessage:new{ text = name .. " are coming soon!" })
end

function Dashboard:onShowSettings()
    local dialog
    dialog = ButtonDialog:new{
        title = "Settings",
        buttons = {
            { { text = "Refresh", callback = function()
                UIManager:close(dialog)
                self:refresh()
            end } },
            { { text = "Open file browser", callback = function()
                UIManager:close(dialog)
                UIManager:close(self)
            end } },
            { { text = "Exit to Kindle", callback = function()
                UIManager:close(dialog)
                self:onExitToKindle()
            end } },
        },
    }
    UIManager:show(dialog)
    return true
end

function Dashboard:refresh()
    UIManager:close(self)
    UIManager:show(Dashboard:new{ file_manager = self.file_manager }, "full")
end

function Dashboard:onExitToKindle()
    UIManager:close(self)
    if self.file_manager then
        self.file_manager:onClose()
    end
    return true
end

function Dashboard:onIgnoreBack()
    return true
end

function Dashboard:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

return Dashboard

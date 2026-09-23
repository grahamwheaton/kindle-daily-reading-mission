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
local ConfirmBox = require("ui/widget/confirmbox")
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
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local State = require("rupertstate")
local Tile = require("ruperttile")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

local MISSION_FILE = State.MISSION_FILE
local COVER_FILE = State.COVER_FILE
local ARCHIVE_DIR = State.ARCHIVE_DIR

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local BUTTON_GRAY = Blitbuffer.gray(0.70)

-- Material Design glyphs in KOReader's bundled nerdfonts/symbols.ttf.
local ICON = {
    logo = "\u{E2A6}",
    fire = "\u{E937}",
    book = "\u{E7BD}",
    compass = "\u{E88A}",
    bigread = "\u{E7BA}",
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

local readProperties = State.readProperties

-- Today's mission is on the dashboard already, and the archived copy of it is
-- the version it replaced, so leave it out of previous missions.
local function archivedMissions(current_id)
    local missions = {}
    if lfs.attributes(ARCHIVE_DIR, "mode") ~= "directory" then return missions end
    for name in lfs.dir(ARCHIVE_DIR) do
        local id = name:match("^(.+)%.mobi$")
        if id and id ~= current_id then
            local props = readProperties(ARCHIVE_DIR .. "/" .. id .. ".properties")
            table.insert(missions, { id = id, title = props.title or id, file = ARCHIVE_DIR .. "/" .. name })
        end
    end
    table.sort(missions, function(a, b) return a.id > b.id end)
    return missions
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


local Dashboard = FocusManager:extend{
    file_manager = nil,
    covers_fullscreen = true,
}

--- Show the dashboard unless it is already up.
-- Closing a book does not always build a new file manager -- KOReader reuses
-- the existing one, and then the plugin is not re-created -- so the reader
-- asks for the dashboard itself on the way out.
function Dashboard.showIfNeeded(file_manager)
    if Dashboard.instance then return end
    UIManager:show(Dashboard:new{ file_manager = file_manager }, "full")
end

function Dashboard:init()
    Dashboard.instance = self
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.props = readProperties(State.PROPERTIES_FILE)
    self.finished_today = State.isCompleted(self.props.id)
    self.archive = archivedMissions(self.props.id)

    self.key_events.ExitToKindle = { { "Home" } }
    self.key_events.ShowSettings = { { "Menu" } }
    self.key_events.IgnoreBack = { { "Back" } }
    -- The side page-turn buttons walk the tiles, one binding per key.
    self.key_events.PageDownRight = { { "RPgFwd" }, event = "FocusMove", args = { 0, 1 } }
    self.key_events.PageDownLeft = { { "LPgFwd" }, event = "FocusMove", args = { 0, 1 } }
    self.key_events.PageUpRight = { { "RPgBack" }, event = "FocusMove", args = { 0, -1 } }
    self.key_events.PageUpLeft = { { "LPgBack" }, event = "FocusMove", args = { 0, -1 } }

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
    self:focusMissionCard()
end

--- Put the ring on the mission card and nowhere else.
-- Belt and braces: the card is the first thing he should be able to press, and
-- the ring drifted to the first tile once, so the visible state is asserted
-- rather than assumed.
function Dashboard:focusMissionCard()
    for _, tile in ipairs(self.tiles) do
        tile:onUnfocus()
    end
    self.selected = { x = 1, y = 1 }
    self.last_tile_row = 1
    self.start_tile:onFocus()
end

function Dashboard:onShow()
    self:focusMissionCard()
    -- And again once everything else showing this screen has had its turn:
    -- something claims the first tile during show, and the ring has to be on
    -- the mission card, which is what the centre button should start.
    UIManager:nextTick(function()
        self:focusMissionCard()
        UIManager:setDirty(self, "fast")
    end)
    return false
end

function Dashboard:buildStatusBar(width)
    local date = os.date("%a %d %b %Y"):upper()
    local left = HorizontalGroup:new{
        align = "center",
        text(wifiIcon(), symbols(22)),
        HorizontalSpan:new{ width = 14 },
        text("RUPERT  v26", bold(17)),
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
                text(self.finished_today and "READ AGAIN" or "START MISSION", bold(32), WHITE),
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

    local cover_file = State.coverFor(MISSION_FILE, p.id)
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
    -- What was actually read. The published number is only a fallback until
    -- the device has any history of its own.
    local streak = State.streak(self.props.id)
    if State.completedCount() == 0 then
        streak = tonumber(self.props.streak) or 0
    end
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
                text("POINTS: " .. State.points(), bold(16)),
            },
        },
    }
    -- Pad to the same outer size as a Tile so the columns line up.
    local streak_wrap = FrameContainer:new{ bordersize = 0, padding = 5, streak_box }

    local entries = {
        { ICON.bigread, self:bigReadLabel(), function() self:openBigRead() end },
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

--- The tile says where he is in this week's story.
function Dashboard:bigReadLabel()
    local id = State.bigReadId()
    if not id then return "BIG READ" end
    if State.bigReadFinished(id) then return "BIG READ  \u{E82B}" end
    return State.bigReadProgress(id) and "BIG READ - CARRY ON" or "BIG READ - NEW"
end

function Dashboard:openBigRead()
    local BigRead = require("rupertbigread")
    local story, problem = BigRead.load()
    if not story then
        UIManager:show(InfoMessage:new{ text = problem })
        return
    end
    UIManager:show(BigRead:new{
        story = story,
        node_id = State.bigReadProgress(story.id),
    }, "full")
end

function Dashboard:showPrevious()
    if #self.archive == 0 then
        UIManager:show(InfoMessage:new{ text = "Your finished missions will appear here." })
        return
    end
    local Archive = require("rupertarchive")
    UIManager:show(Archive:new{
        missions = self.archive,
        on_open = function(file) self:openBook(file) end,
    }, "full")
end

function Dashboard:showProgress()
    local streak = State.streak(self.props.id)
    local finished = State.completedCount()
    UIManager:show(InfoMessage:new{
        text = string.format("Points: %d\nDaily missions: %d x 1\nBig Reads: %d x 3\nStreak: %d day%s\nToday's mission: %s",
            State.points(), finished, State.bigReadCompletedCount(),
            streak, streak == 1 and "" or "s",
            self.finished_today and "finished" or "not finished yet"),
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
            { { text = "Reboot Kindle", callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = "Reboot the Kindle now? Your reading position will be saved.",
                    ok_text = "Reboot",
                    ok_callback = function()
                        -- KOReader does not advertise its built-in reboot action on
                        -- Kindle 4. Use the device's own reboot command after saving.
                        Device:saveSettings()
                        UIManager:nextTick(function()
                            os.execute("sync; /sbin/reboot")
                        end)
                    end,
                })
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
    if Dashboard.instance == self then
        Dashboard.instance = nil
    end
    UIManager:setDirty(nil, "full")
end

return Dashboard

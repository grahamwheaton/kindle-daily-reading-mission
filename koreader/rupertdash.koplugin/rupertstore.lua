-- A small game storefront designed for the Kindle 4's greyscale screen.
-- Catalog is generated from ActionNotes; each request has one ledger file.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local LineWidget = require("ui/widget/linewidget")
local State = require("rupertstate")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Tile = require("ruperttile")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")

local BLACK, WHITE = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
local function bold(size) return Font:getFace("NotoSans-Bold.ttf", size) end
local function regular(size) return Font:getFace("NotoSans-Regular.ttf", size) end
local Store = FocusManager:extend{ covers_fullscreen = true }
function Store:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Device.screen:getWidth(), h = Device.screen:getHeight() }
    self.key_events.Close = { { "Back" }, { "Home" } }
    self.key_events.NextPage = { { "RPgFwd" }, { "LPgFwd" }, event = "ChangePage", args = 1 }
    self.key_events.PrevPage = { { "RPgBack" }, { "LPgBack" }, event = "ChangePage", args = -1 }
    self.page = 1
    self:build()
end

function Store:onChangePage(direction)
    local pages = math.max(1, math.ceil(#State.getUnlocks() / 2))
    local page = math.max(1, math.min(pages, self.page + direction))
    if page ~= self.page then
        self.page = page
        self:build()
        UIManager:setDirty(self, "full")
    end
    return true
end

function Store:purchase(item)
    if State.unlockPurchased(item.id) then
        UIManager:show(InfoMessage:new{ text = "Already requested. Ask your parent about the purchase." })
    elseif State.availablePoints() < item.cost then
        UIManager:show(InfoMessage:new{
            text = string.format("You need %d more points to unlock this.", item.cost - State.availablePoints()),
        })
    else
        UIManager:show(ConfirmBox:new{
            text = string.format("Spend %d points on %s? This sends a request to your parent. It does not buy the DLC automatically.", item.cost, item.title),
            ok_text = "Spend points",
            ok_callback = function()
                local ok, err = State.purchaseUnlock(item.id)
                if ok then
                    UIManager:close(self)
                    UIManager:show(InfoMessage:new{ text = "Unlock requested! Ask your parent to buy the DLC. The request backs up on the next sync." })
                else
                    UIManager:show(InfoMessage:new{ text = err })
                end
            end,
        })
    end
end

function Store:buildCard(item, width)
    local image_w, image_h = 230, 230
    local picture
    if item.image and lfs.attributes(item.image, "mode") == "file" then
        local native = ImageWidget:new{ file = item.image, file_do_cache = false, scale_factor = 1 }
        local size = native:getSize()
        native:free()
        local scale = math.min(image_w / size.w, image_h / size.h)
        picture = ImageWidget:new{ file = item.image, file_do_cache = false, scale_factor = scale }
    else
        picture = TextWidget:new{ text = "REWARD", face = bold(17) }
    end
    local details_w = width - image_w - 40
    local status = State.unlockPurchased(item.id) and "REQUESTED"
        or (State.availablePoints() >= item.cost and "READY TO UNLOCK" or "KEEP READING")
    local card = FrameContainer:new{
        width = width - 10,
        height = 272,
        bordersize = 2,
        radius = 12,
        padding = 8,
        HorizontalGroup:new{
            align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = image_w, h = image_h }, picture },
            HorizontalSpan:new{ width = 12 },
            VerticalGroup:new{
                align = "left",
                TextBoxWidget:new{ text = item.title, face = bold(23), width = details_w },
                VerticalSpan:new{ width = 18 },
                TextWidget:new{ text = item.cost .. " POINTS", face = bold(22) },
                TextWidget:new{ text = string.format("GBP %.2f reward", item.pounds), face = regular(16) },
                VerticalSpan:new{ width = 18 },
                TextBoxWidget:new{ text = status, face = bold(16), width = details_w },
            },
        },
    }
    return Tile:new{ content = card, callback = function() self:purchase(item) end }
end

function Store:build()
    local W, H = self.dimen.w, self.dimen.h
    local margin, inner_w = 10, W - 20
    local list = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = 10 },
        TextWidget:new{ text = "UNLOCK STORE", face = bold(32) },
        VerticalSpan:new{ width = 8 },
        LineWidget:new{ dimen = Geom:new{ w = inner_w, h = 2 }, background = BLACK },
        VerticalSpan:new{ width = 18 },
        TextWidget:new{ text = State.availablePoints() .. " POINTS AVAILABLE", face = bold(23) },
        TextWidget:new{ text = "5 points = GBP 1  |  Read to earn more", face = regular(17) },
        VerticalSpan:new{ width = 14 },
        TextWidget:new{ text = "REWARDS", face = bold(18) },
        VerticalSpan:new{ width = 12 },
    }
    local items = State.getUnlocks()
    self.layout = {}
    for index = (self.page - 1) * 2 + 1, math.min(self.page * 2, #items) do
        local item = items[index]
        local tile = self:buildCard(item, inner_w)
        table.insert(list, tile)
        table.insert(list, VerticalSpan:new{ width = 12 })
        table.insert(self.layout, { tile })
    end
    if #items == 0 then
        table.insert(list, TextWidget:new{ text = "No rewards available yet.", face = regular(19) })
    end
    table.insert(list, TextWidget:new{
        text = string.format("Page %d/%d  |  Page keys for more  |  Back", self.page, math.max(1, math.ceil(#items / 2))),
        face = regular(15),
    })
    self[1] = FrameContainer:new{
        width = W, height = H, bordersize = 0, padding = 0,
        padding_left = margin, padding_right = margin, background = WHITE, list,
    }
    if self.layout[1] then self.layout[1][1]:onFocus() end
end

function Store:onClose()
    UIManager:close(self)
    return true
end

function Store:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

return Store

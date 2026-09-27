-- Two-choice comprehension cards shown when a daily book reaches its end.
-- Physical left/right page buttons choose the matching answer; the 5-way
-- selects a side and its centre confirms it.
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local JSON = require("json")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Tile = require("ruperttile")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local State = require("rupertstate")
local Screen = Device.screen

local Quiz = FocusManager:extend{ covers_fullscreen = true }
local function face(size) return Font:getFace("NotoSans-Bold.ttf", size) end
local function normal(size) return Font:getFace("NotoSans-Regular.ttf", size) end

function Quiz.load(id)
    if not id or not id:match("^%d%d%d%d%-%d%d%-%d%d$") then return nil end
    local f = io.open(State.STATE_DIR .. "/quizzes/" .. id .. ".json", "r")
    if not f then return nil end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    return ok and type(data) == "table" and type(data.questions) == "table"
        and #data.questions > 0 and data or nil
end

function Quiz:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.index, self.score, self.selected_side = 1, 0, 1
    self.key_events.LeftPage = { { "LPgFwd" }, event = "Choose", args = 1 }
    self.key_events.LeftPageBack = { { "LPgBack" }, event = "Choose", args = 1 }
    self.key_events.RightPage = { { "RPgFwd" }, event = "Choose", args = 2 }
    self.key_events.RightPageBack = { { "RPgBack" }, event = "Choose", args = 2 }
    self.key_events.SelectLeft = { { "Left" }, event = "Select", args = 1 }
    self.key_events.SelectRight = { { "Right" }, event = "Select", args = 2 }
    self.key_events.Leave = { { "Back" } }
    self.key_events.LeaveHome = { { "Home" } }
    self:build()
end

function Quiz:build()
    local w, h = self.dimen.w, self.dimen.h
    local question = self.data.questions[self.index]
    if not question then return end
    local answer_w = math.floor((w - 42) / 2)
    local answers = {}
    for i = 1, 2 do
        local answer = FrameContainer:new{
            width = answer_w, height = 160, bordersize = self.selected_side == i and 5 or 2,
            radius = 10, padding = 10,
            TextBoxWidget:new{
                text = (i == 1 and "LEFT  |  " or "RIGHT  |  ") .. question.choices[i],
                face = face(21), width = answer_w - 30, height = 125,
                height_adjust = true, height_overflow_show_ellipsis = true,
            },
        }
        answers[i] = Tile:new{ content = answer, callback = function() self:onChoose(i) end }
    end
    self.layout = { answers }
    self.selected = { x = self.selected_side, y = 1 }
    self[1] = FrameContainer:new{
        width = w, height = h, bordersize = 0, padding = 16,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = string.format("MISSION QUESTIONS  %d / %d", self.index, #self.data.questions), face = face(20) },
            VerticalSpan:new{ width = 65 },
            TextBoxWidget:new{ text = question.text, face = face(29), width = w - 36, height = 220,
                height_adjust = true, height_overflow_show_ellipsis = true },
            VerticalSpan:new{ width = 65 },
            HorizontalGroup:new{ align = "center", answers[1], HorizontalSpan:new{ width = 10 }, answers[2] },
            VerticalSpan:new{ width = 40 },
            TextWidget:new{ text = "Left or right page button to answer", face = normal(17) },
        },
    }
end

function Quiz:onSelect(side)
    self.selected_side = side
    self:build()
    UIManager:setDirty(self, "ui")
    return true
end

function Quiz:onChoose(side)
    local question = self.data.questions[self.index]
    if not question then return true end
    if question.correct == side then self.score = self.score + 1 end
    self.index = self.index + 1
    if self.index > #self.data.questions then
        local path = State.STATE_DIR .. "/quiz-results"
        require("libs/libkoreader-lfs").mkdir(path)
        local f = io.open(path .. "/" .. self.id .. ".json.part", "w")
        if f then
            f:write(JSON.encode({ mission = self.id, correct = self.score,
                total = #self.data.questions, finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ") }), "\n")
            f:close()
            os.rename(path .. "/" .. self.id .. ".json.part", path .. "/" .. self.id .. ".json")
        end
        UIManager:close(self)
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
            text = string.format("Questions finished!  %d out of %d", self.score, #self.data.questions),
        })
    else
        self.selected_side = 1
        self:build()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function Quiz:onLeave() UIManager:close(self); return true end
Quiz.onLeaveHome = Quiz.onLeave
return Quiz

--[[--
Shows the mission dashboard over the file manager when KOReader was started
by Rupert's Reader (open-current.sh sets RUPERT_DASHBOARD=1). Closing a book
returns to the file manager, which re-creates this plugin and so shows the
dashboard again. Started any other way, KOReader behaves normally.

In the reader it records when a mission is finished, which is what the streak
counts and what the uploader reports.
--]]

local Dashboard = require("rupertdashboard")
local Reading = require("rupertreading")
local State = require("rupertstate")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

-- Paging to the very end is the normal finish, but closing a book a page or
-- two short is still a read story to a seven-year-old.
local FINISHED_FRACTION = 0.95

-- A streak is worth nothing if opening the book earns it. Reaching the end was
-- once logged six seconds after launch with nobody holding the Kindle, most
-- likely a repeating page-turn key, so finishing also has to look like reading.
local MIN_SECONDS = 45
local MIN_PAGE_TURNS = 3

local RupertDash = WidgetContainer:extend{
    name = "rupertdash",
    is_doc_only = false,
}

function RupertDash:init()
    if self.ui.document then
        self.opened_at = os.time()
        self.page_turns = 0
        return
    end
    if os.getenv("RUPERT_DASHBOARD") ~= "1" then return end
    Reading.apply()
    UIManager:nextTick(function()
        UIManager:show(Dashboard:new{ file_manager = self.ui }, "full")
    end)
end

function RupertDash:countPageTurn()
    if self.page_turns then
        self.page_turns = self.page_turns + 1
    end
end

-- Both fire on open as well as on a turn, hence MIN_PAGE_TURNS above 1.
RupertDash.onPageUpdate = RupertDash.countPageTurn
RupertDash.onPosUpdate = RupertDash.countPageTurn

function RupertDash:looksRead()
    local seconds = os.time() - (self.opened_at or os.time())
    return seconds >= MIN_SECONDS and (self.page_turns or 0) >= MIN_PAGE_TURNS,
        string.format("%ds, %d page updates", seconds, self.page_turns or 0)
end

function RupertDash:recordFinished(reason)
    if not self.ui.document then return end
    local id = State.missionIdForFile(self.ui.document.file)
    if not id then return end
    local read, detail = self:looksRead()
    if not read then
        logger.info("rupertdash: ignoring", reason, "for", id, "--", detail)
        return
    end
    local title = self.ui.doc_props and self.ui.doc_props.display_title
    if State.recordCompletion(id, title) then
        logger.info("rupertdash: mission", id, "finished", reason, "--", detail)
    end
end

-- Do not return true from either: other handlers (the end-of-book dialog,
-- settings flushing) still need these events.
function RupertDash:onEndOfBook()
    self:recordFinished("end of book")
end

function RupertDash:onCloseDocument()
    local percent = self.ui.doc_settings and self.ui.doc_settings:readSetting("percent_finished")
    if percent and percent >= FINISHED_FRACTION then
        self:recordFinished(string.format("closed at %d%%", percent * 100))
    end
end

return RupertDash

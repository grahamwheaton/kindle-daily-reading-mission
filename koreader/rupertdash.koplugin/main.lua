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
        self.last_page = nil
        return
    end
    if os.getenv("RUPERT_DASHBOARD") ~= "1" then return end
    Reading.apply()
    UIManager:nextTick(function()
        Dashboard.showIfNeeded(self.ui)
    end)
end

--- Back to the dashboard when a mission is put down, rather than to
--- KOReader's file browser. The file manager may be reused rather than
--- rebuilt, in which case the plugin is not re-created and nothing else would
--- bring the dashboard back.
function RupertDash:onCloseWidget()
    if not self.opened_at or os.getenv("RUPERT_DASHBOARD") ~= "1" then return end
    UIManager:scheduleIn(0.5, function()
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance then
            Dashboard.showIfNeeded(FileManager.instance)
        end
    end)
end

-- PageUpdate carries the visible page number for both MOBI/crengine and
-- paged documents. Record a finished book when its final pages are displayed;
-- EndOfBook fires only after an extra forward press beyond the final page.
function RupertDash:onPageUpdate(page)
    if not self.ui.document or type(page) ~= "number" then return end
    if self.last_page and self.last_page ~= page then
        self.page_turns = (self.page_turns or 0) + 1
    end
    self.last_page = page
    local total = self.ui.document:getPageCount()
    if not total or total <= 0 or page / total < FINISHED_FRACTION then return end
    local read = self:looksRead()
    if read then
        self:recordFinished("reached final pages")
    elseif (self.page_turns or 0) >= MIN_PAGE_TURNS and not self.finish_check_scheduled then
        self.finish_check_scheduled = true
        local file = self.ui.document.file
        local remaining = math.max(0, MIN_SECONDS - (os.time() - (self.opened_at or os.time())))
        UIManager:scheduleIn(remaining, function()
            if self.ui.document and self.ui.document.file == file
                and self.last_page and self.ui.document:getPageCount() > 0
                and self.last_page / self.ui.document:getPageCount() >= FINISHED_FRACTION then
                self:recordFinished("read final pages")
            end
        end)
    end
end

-- A completed book from before this fix may already have its progress saved
-- by KOReader but no Rupert completion record. Reconcile it on reopening.
function RupertDash:onReaderReady()
    if not self.ui.document then return end
    local percent = self.ui.doc_settings and self.ui.doc_settings:readSetting("percent_finished")
    if percent and percent >= FINISHED_FRACTION then
        local id = State.missionIdForFile(self.ui.document.file)
        if id then
            local title = self.ui.doc_props and self.ui.doc_props.display_title
            State.recordCompletion(id, title)
        end
    end
end

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

return RupertDash

--[[--
Shows the mission dashboard over the file manager when KOReader was started
by Rupert's Reader (open-current.sh sets RUPERT_DASHBOARD=1). Closing a book
returns to the file manager, which re-creates this plugin and so shows the
dashboard again. Started any other way, KOReader behaves normally.
--]]

local Dashboard = require("rupertdashboard")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local RupertDash = WidgetContainer:extend{
    name = "rupertdash",
    is_doc_only = false,
}

function RupertDash:init()
    if os.getenv("RUPERT_DASHBOARD") ~= "1" or self.ui.document then
        return
    end
    UIManager:nextTick(function()
        UIManager:show(Dashboard:new{ file_manager = self.ui }, "full")
    end)
end

return RupertDash

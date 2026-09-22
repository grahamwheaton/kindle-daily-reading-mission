--[[--
Shared state for Rupert's Reading Missions: where things live, what has been
read, and the streak.

Completions are keyed by mission ID (the publisher's date), never by the
Kindle's clock, which is not trusted -- the same reason the sync compares
published IDs rather than dates. A completion is one file per mission in
completed/, so recording is atomic and a half-written file cannot corrupt the
history. The uploader marks what it has sent with a matching .sent file.
--]]

local lfs = require("libs/libkoreader-lfs")

local State = {
    STATE_DIR = "/mnt/us/rupert-mission",
    MISSION_FILE = "/mnt/us/documents/RupertsMission.mobi",
}
State.PROPERTIES_FILE = State.STATE_DIR .. "/launcher.properties"
State.COVER_FILE = State.STATE_DIR .. "/cover.png"
State.ARCHIVE_DIR = State.STATE_DIR .. "/archive"
State.COMPLETED_DIR = State.STATE_DIR .. "/completed"

function State.readProperties(path)
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

--- The mission ID a document belongs to, or nil if it is not a mission.
function State.missionIdForFile(file)
    if not file then return nil end
    local archived = file:match("^" .. State.ARCHIVE_DIR:gsub("%-", "%%-") .. "/(%d%d%d%d%-%d%d%-%d%d)%.mobi$")
    if archived then return archived end
    if file == State.MISSION_FILE then
        return State.readProperties(State.PROPERTIES_FILE).id
    end
    return nil
end

function State.isCompleted(id)
    return id ~= nil and lfs.attributes(State.COMPLETED_DIR .. "/" .. id .. ".json", "mode") == "file"
end

--- Record a finished mission. Returns true the first time only.
function State.recordCompletion(id, title)
    if not id or State.isCompleted(id) then return false end
    lfs.mkdir(State.COMPLETED_DIR)
    local path = State.COMPLETED_DIR .. "/" .. id .. ".json"
    local f = io.open(path .. ".part", "w")
    if not f then return false end
    f:write(string.format('{"mission":"%s","title":"%s","finished_at":"%s"}\n',
        id, (title or ""):gsub('"', "'"), os.date("!%Y-%m-%dT%H:%M:%SZ")))
    f:close()
    os.remove(path)
    return os.rename(path .. ".part", path) and true or false
end

local function previousDay(id)
    local year, month, day = id:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then return nil end
    local stamp = os.time{ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }
    return os.date("%Y-%m-%d", stamp - 86400)
end

--- Consecutive missions finished, counting back from the current one. Today
--- not being read yet does not break the streak, it just does not add to it.
function State.streak(current_id)
    if not current_id then return 0 end
    local id = current_id
    if not State.isCompleted(id) then
        id = previousDay(id)
    end
    local count = 0
    while id and State.isCompleted(id) do
        count = count + 1
        id = previousDay(id)
    end
    return count
end

function State.completedCount()
    local count = 0
    if lfs.attributes(State.COMPLETED_DIR, "mode") ~= "directory" then return 0 end
    for name in lfs.dir(State.COMPLETED_DIR) do
        if name:match("%.json$") then count = count + 1 end
    end
    return count
end

return State

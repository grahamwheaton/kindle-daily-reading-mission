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
local logger = require("logger")

local State = {
    STATE_DIR = "/mnt/us/rupert-mission",
    MISSION_FILE = "/mnt/us/documents/RupertsMission.mobi",
}
State.PROPERTIES_FILE = State.STATE_DIR .. "/launcher.properties"
State.COVER_FILE = State.STATE_DIR .. "/cover.png"
State.ARCHIVE_DIR = State.STATE_DIR .. "/archive"
State.COMPLETED_DIR = State.STATE_DIR .. "/completed"
-- The weekly Big Read: the sync unpacks it here, and finishing one is recorded
-- separately from the daily streak.
State.BIGREAD_DIR = State.STATE_DIR .. "/bigread"
State.BIGREAD_ID_FILE = State.STATE_DIR .. "/bigread-id"
State.BIGREAD_PROGRESS = State.STATE_DIR .. "/bigread-progress"
State.BIGREAD_COMPLETED_DIR = State.STATE_DIR .. "/completed-bigread"
State.UNLOCKS_DIR = State.STATE_DIR .. "/unlocks"

State.UNLOCKS = {
    { id = "snowrunner-season-16-high-voltage", title = "SnowRunner: Season 16 - High Voltage", pounds = 5, cost = 25 },
}

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

--- A cover for a mission book: the published cover.png for today's mission,
--- otherwise the picture inside the book. Nil when it has none.
-- Cached by size as well as ID, because a corrected mission keeps its ID but
-- changes the book.
function State.coverFor(file, id)
    if file == State.MISSION_FILE and lfs.attributes(State.COVER_FILE, "mode") == "file" then
        return State.COVER_FILE
    end
    local size = lfs.attributes(file, "size")
    if not size then return nil end
    local key = "/var/tmp/rupert-cover-" .. tostring(id or "current"):gsub("[^%w-]", "_") .. "-" .. size
    local ok, found = pcall(extractMobiImage, file, key)
    if not ok then
        logger.warn("rupertdash: cover extraction failed", found)
        return nil
    end
    return found
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

local function completionCount(directory)
    local count = 0
    if lfs.attributes(directory, "mode") ~= "directory" then return 0 end
    for name in lfs.dir(directory) do
        if name:match("%.json$") then count = count + 1 end
    end
    return count
end

function State.completedCount()
    return completionCount(State.COMPLETED_DIR)
end

function State.bigReadCompletedCount()
    return completionCount(State.BIGREAD_COMPLETED_DIR)
end

-- Completion records are the ledger. Re-reading a book cannot award points
-- twice, because each mission or Big Read ID has only one completion file.
function State.points()
    return State.completedCount() + 3 * State.bigReadCompletedCount()
end

function State.unlockPurchased(id)
    return id ~= nil and id:match("^[%w-]+$") ~= nil
        and lfs.attributes(State.UNLOCKS_DIR .. "/" .. id .. ".json", "mode") == "file"
end

function State.spentPoints()
    local spent = 0
    for _, item in ipairs(State.UNLOCKS) do
        if State.unlockPurchased(item.id) then spent = spent + item.cost end
    end
    return spent
end

function State.availablePoints()
    return math.max(0, State.points() - State.spentPoints())
end

-- A purchase is a request for the parent to buy the reward. One record per
-- catalog ID prevents a second charge and lets the reporter back it up.
function State.purchaseUnlock(id)
    local item
    for _, candidate in ipairs(State.UNLOCKS) do
        if candidate.id == id then item = candidate; break end
    end
    if not item then return false, "Unknown unlock" end
    if State.unlockPurchased(id) then return false, "Already unlocked" end
    if State.availablePoints() < item.cost then return false, "Not enough points yet" end
    lfs.mkdir(State.UNLOCKS_DIR)
    local path = State.UNLOCKS_DIR .. "/" .. id .. ".json"
    local f = io.open(path .. ".part", "w")
    if not f then return false, "Could not save the unlock" end
    f:write(string.format('{"unlock":"%s","title":"%s","points":%d,"pounds":%d,"requested_at":"%s","status":"requested"}\n',
        item.id, item.title, item.cost, item.pounds, os.date("!%Y-%m-%dT%H:%M:%SZ")))
    f:close()
    if not os.rename(path .. ".part", path) then
        os.remove(path .. ".part")
        return false, "Could not save the unlock"
    end
    return true
end

local function trimmed(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line and line:gsub("%s", "") or nil
end

function State.bigReadId()
    return trimmed(State.BIGREAD_ID_FILE)
end

--- Where he is in this week's story, or nil to start at the beginning.
function State.bigReadProgress(id)
    local props = State.readProperties(State.BIGREAD_PROGRESS)
    if props.id ~= id then return nil end
    return props.node
end

function State.saveBigReadProgress(id, node_id)
    if not id or not node_id then return end
    local f = io.open(State.BIGREAD_PROGRESS, "w")
    if not f then return end
    f:write(string.format("id=%s\nnode=%s\nsaved_at=%s\n",
        id, node_id, os.date("!%Y-%m-%dT%H:%M:%SZ")))
    f:close()
end

function State.bigReadFinished(id)
    return id ~= nil
        and lfs.attributes(State.BIGREAD_COMPLETED_DIR .. "/" .. id .. ".json", "mode") == "file"
end

--- Record a finished Big Read, with the ending he reached. Kept apart from the
--- daily completions so the streak stays a count of daily missions.
function State.recordBigRead(id, title, ending, pages, seconds)
    if not id then return false end
    lfs.mkdir(State.BIGREAD_COMPLETED_DIR)
    local path = State.BIGREAD_COMPLETED_DIR .. "/" .. id .. ".json"
    local f = io.open(path .. ".part", "w")
    if not f then return false end
    local function clean(value) return (value or ""):gsub('"', "'") end
    -- pages and seconds travel with it: how he got to the ending is the
    -- interesting part when we look back at a week of these.
    f:write(string.format(
        '{"bigread":"%s","title":"%s","ending":"%s","pages":%d,"seconds":%d,"finished_at":"%s"}\n',
        id, clean(title), clean(ending), pages or 0, seconds or 0,
        os.date("!%Y-%m-%dT%H:%M:%SZ")))
    f:close()
    os.remove(path)
    return os.rename(path .. ".part", path) and true or false
end

return State

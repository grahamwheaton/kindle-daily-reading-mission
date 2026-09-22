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

function State.completedCount()
    local count = 0
    if lfs.attributes(State.COMPLETED_DIR, "mode") ~= "directory" then return 0 end
    for name in lfs.dir(State.COMPLETED_DIR) do
        if name:match("%.json$") then count = count + 1 end
    end
    return count
end

return State

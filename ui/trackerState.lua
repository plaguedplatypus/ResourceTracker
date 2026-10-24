local catalog = require("catalog/resourceCatalog")
local sessionStats = require("Core/sessionStats")
local persistence = require("Core/persistence")

local trackerState = {}
-- This module is the single owner of saved tracker state. UI and event modules
-- call its functions instead of changing counts or settings directly.
local data = { items = {}, order = 0, settings = {}, session = { days = {} } }
local accountId
local ready = false
local waitingSettings = {}
-- A revision redraws changed data; a generation means login or logout has
-- replaced the whole record, so panels must also clear their selection.
local revision = 0
local generation = 0
-- The client does not expose Lua's standard clock. Logic events run at 50 Hz,
-- providing the elapsed time used for sessions and items-per-hour calculations.
local elapsed = 0
-- Chat messages include a Unix timestamp. It anchors elapsed time to a UTC day
-- when chat access is available.
local epochOffset

-- Convert a Unix day to a Gregorian date without relying on the unavailable
-- Lua os library. Daily history intentionally displays the UTC calendar day.
local function dayKey(timestamp)
    local days = timestamp // 86400
    local z = days + 719468
    local era = (z >= 0 and z or z - 146096) // 146097
    local doe = z - era * 146097
    local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    local year = yoe + era * 400
    local dayOfYear = doe - (365 * yoe + yoe // 4 - yoe // 100)
    local monthPart = (5 * dayOfYear + 2) // 153
    local day = dayOfYear - (153 * monthPart + 2) // 5 + 1
    local month = monthPart + (monthPart < 10 and 3 or -9)
    year = year + (month <= 2 and 1 or 0)
    return string.format("%04d-%02d-%02d", year, month, day)
end

-- Use a temporary Today bucket until chat supplies a UTC timestamp.
local function currentDay()
    if epochOffset then
        return dayKey(math.floor(epochOffset + elapsed))
    end
    -- Inventory-only gains are held in this temporary bucket until a chat
    -- timestamp lets the tracker place them in the current calendar day.
    return "Today"
end

-- Show the session start in UTC, matching the calendar used by daily history.
local function formatTime(timestamp)
    local seconds = timestamp % 86400
    return string.format("%02d:%02d:%02d UTC", seconds // 3600,
        (seconds // 60) % 60, seconds % 60)
end

-- A revision tells docked UI panels to redraw after persisted state changes.
local function save()
    persistence.save(data, accountId)
    revision = revision + 1
end

-- Load the character record after its tracking ID arrives and start a login session.
function trackerState.open(id)
    if ready and accountId == id then return end
    local loaded = persistence.load(id)
    for name, value in pairs(waitingSettings) do
        loaded.settings[name] = value
    end
    data, accountId, ready = loaded, id, true
    -- A gain recorded before the first chat timestamp uses the temporary
    -- Today key. If the timestamp arrived before this record opened, move the
    -- temporary data into the dated entry now.
    local movedToday = currentDay() ~= "Today"
        and sessionStats.moveDay(data.session, "Today", currentDay())
    -- The client opens this record after entering the game, which establishes
    -- a new login session even before the first tracked resource is gathered.
    sessionStats.start(data.session, elapsed, currentDay())
    generation = generation + 1
    local changed = next(waitingSettings) ~= nil or movedToday
    waitingSettings = {}
    if changed then
        save()
    else
        revision = revision + 1
    end
end

-- End the login session and clear account data when leaving the game.
function trackerState.unload()
    if ready then
        -- Persist completed daily totals without carrying this login's session
        -- into the next game-state transition.
        sessionStats.close(data.session)
        persistence.save(data, accountId)
    end
    data = { items = {}, order = 0, settings = {}, session = { days = {} } }
    accountId, ready, waitingSettings = nil, false, {}
    elapsed, epochOffset = 0, nil
    generation = generation + 1
    revision = revision + 1
end

-- Counting waits for the character record before writing gathered resources.
function trackerState.isReady()
    return ready
end

-- Chat rewards and backpack observations share one row when they identify
-- the same resource and source.
local function ensure(definition, source)
    local itemKey = catalog.makeKey(definition.skill, definition.name, source)
    local item = data.items[itemKey]
    if not item then
        item = {
            name = definition.name,
            skill = definition.skill,
            source = source,
            count = 0,
            order = 0
        }
        data.items[itemKey] = item
    end
    return item
end

-- Automatic gains advance both persistent counts and session history.
function trackerState.recordAuto(updates)
    if not ready then return end
    local changed = false
    for _, update in ipairs(updates) do
        if update.amount > 0 then
            local item = ensure(update, update.source)
            item.count = item.count + update.amount
            if update.itemId then
                item.itemId = update.itemId
            end
            data.order = data.order + 1
            item.order = data.order
            changed = true
        end
    end
    if changed then
        -- Manual corrections only update an item count. Session totals represent
        -- automatic gathering events, so they are recorded only on this path.
        sessionStats.record(data.session, updates, elapsed, currentDay())
        save()
    end
end

-- Manual count corrections affect the resource row, but not gathered totals.
function trackerState.setCount(itemKey, value)
    local item = data.items[itemKey]
    if item and item.count ~= value then
        item.count = value
        data.order = data.order + 1
        item.order = data.order
        save()
    end
end

-- A cleared goal is stored as nil so the row returns to count-only display.
function trackerState.setGoal(itemKey, goal)
    local item = data.items[itemKey]
    if item and item.goal ~= goal then
        item.goal = goal
        save()
    end
end

-- Remove a tracked row without changing the recorded session or daily gains.
function trackerState.remove(itemKey)
    if not data.items[itemKey] then return end
    data.items[itemKey] = nil
    save()
end

-- The dock reads this shared table when it draws catalogued resource rows.
function trackerState.getItems()
    return data.items
end

-- The dock and Manage Plugins settings read the same saved preferences.
function trackerState.getSettings()
    return data.settings
end

-- Add a live active interval and a UTC start time to the current report.
function trackerState.getSession()
    local report = sessionStats.current(data.session, elapsed)
    if report.startedAt and epochOffset then
        report.started = formatTime(math.floor(epochOffset + report.startedAt))
    end
    return report
end

-- Supply newest-first day labels for the history picker.
function trackerState.getSessionDays()
    return sessionStats.days(data.session)
end

-- Keep a saved temporary Today record addressable. It is normally moved to
-- its UTC date when chat provides a timestamp, but the picker must still
-- display it if a prior client session left one behind.
function trackerState.getSessionDay(key)
    return sessionStats.day(data.session, key, elapsed, currentDay())
end

-- Clearing day summaries leaves the current login session running.
function trackerState.clearHistory()
    if not ready then return end
    sessionStats.clearDays(data.session)
    save()
end

-- Logic ticks provide elapsed time when Lua's standard clock is unavailable.
function trackerState.tick()
    if ready then elapsed = elapsed + 0.02 end
end

-- Anchor elapsed ticks to the chat timestamp and date any temporary Today data.
function trackerState.observeTime(timestamp)
    if type(timestamp) ~= "number" or timestamp <= 0 then return end
    local previousDay = currentDay()
    -- Keep the elapsed timer monotonic while correcting its calendar anchor from
    -- the most recent game-message timestamp.
    epochOffset = timestamp - elapsed
    local updatedDay = currentDay()
    -- Only the undated bucket can be reassigned. A dated bucket is history,
    -- even when a new chat timestamp crosses midnight.
    if ready and previousDay == "Today"
        and sessionStats.moveDay(data.session, previousDay, updatedDay) then
        save()
    end
end

-- Keep edits made before the tracking ID arrives, then persist them on open.
function trackerState.setSetting(name, value)
    if data.settings[name] == value then return end
    data.settings[name] = value
    if not ready then
        waitingSettings[name] = value
        revision = revision + 1
        return
    end
    save()
end

-- The UI compares revisions to redraw changed data without rebuilding every tick.
function trackerState.getRevision()
    return revision
end

-- A generation change tells panels to discard selections from another login.
function trackerState.getGeneration()
    return generation
end

return trackerState

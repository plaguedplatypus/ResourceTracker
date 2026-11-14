local catalog = require("catalog/resourceCatalog")
local sessionStats = require("Core/sessionStats")
local persistence = require("Core/persistence")

local trackerState = {}
-- This module is the single owner of saved tracker state. UI and event modules
-- call its functions instead of changing counts or settings directly.
local data = { items = {}, ports = {}, order = 0, settings = {}, session = { days = {} } }
local accountId
local ready = false
local trackedId
local linkedName
local waitingSettings = {}
-- A revision redraws changed data; a generation means login or logout has
-- replaced the whole record, so panels must also clear their selection.
local revision = 0
local generation = 0
local portsObserved = false
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

-- Link both identifiers to one record. Gaining tracking permission while a
-- name-only session is open keeps that same record and its active session.
function trackerState.open(id, name)
    local idText = id and tostring(id)
    if ready and trackedId == idText and linkedName == name then return end
    local account, linked = persistence.resolve(idText, name)
    if not account then return end
    if ready and accountId == account then
        trackedId, linkedName = idText, linked and name or nil
        return
    end
    if ready then
        sessionStats.close(data.session)
        persistence.save(data, accountId)
    end
    local loaded = persistence.load(account)
    for name, value in pairs(waitingSettings) do
        loaded.settings[name] = value
    end
    data, accountId, trackedId, linkedName, ready = loaded, account, idText,
        linked and name or nil, true
    portsObserved = false
    -- A gain recorded before the first chat timestamp uses the temporary
    -- Today key. If the timestamp arrived before this record opened, move the
    -- temporary data into the dated entry now.
    local movedToday = currentDay() ~= "Today"
        and sessionStats.moveDay(data.session, "Today", currentDay())
    -- A saved open session belongs to the previous login. The first tracked
    -- gain after this login establishes the new session's start time.
    sessionStats.close(data.session)
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
    data = { items = {}, ports = {}, order = 0, settings = {}, session = { days = {} } }
    portsObserved = false
    accountId, ready, trackedId, linkedName, waitingSettings = nil, false, nil, nil, {}
    elapsed, epochOffset = 0, nil
    generation = generation + 1
    revision = revision + 1
end

-- Counting waits for the character record before writing gathered resources.
function trackerState.isReady()
    return ready
end

function trackerState.getAccount()
    return accountId
end

-- Restore a copy for this character; the source profile keeps its own record.
function trackerState.restoreProfile(account, target)
    if not ready or accountId ~= target or account == accountId
        or not persistence.exists(account) then return false end
    local loaded = persistence.load(account)
    sessionStats.close(loaded.session)
    if not persistence.save(loaded, accountId) then return false end
    data = loaded
    portsObserved = false
    generation = generation + 1
    revision = revision + 1
    return true
end

-- Clear every character's records and links before the current session can
-- save its old in-memory state back into the database.
function trackerState.clearAllData()
    if not persistence.clearAll() then return false end
    data = { items = {}, ports = {}, order = 0, settings = {}, session = { days = {} } }
    portsObserved = false
    accountId, ready, trackedId, linkedName, waitingSettings = nil, false, nil, nil, {}
    elapsed, epochOffset = 0, nil
    generation = generation + 1
    revision = revision + 1
    return true
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

-- Ship rewards have fixed Ports rows, including before the first inventory gain.
function trackerState.ensureShipReward(name)
    if not ready then return end
    local definition = catalog.find(name, "ports")
    local itemKey = catalog.makeKey("ports", definition.name)
    if not data.items[itemKey] then
        ensure(definition)
        save()
    end
    return data.items[itemKey]
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

-- A pin changes display order without changing the resource's recent order.
function trackerState.setPinned(itemKey, pinned)
    local item = data.items[itemKey]
    if item and item.pinned ~= pinned then
        item.pinned = pinned or nil
        save()
    end
end

-- Remove a tracked row without changing the recorded session or daily gains.
function trackerState.remove(itemKey)
    if not data.items[itemKey] then return end
    data.items[itemKey] = nil
    save()
end

-- Clear one skill's tracker rows. Ports keeps game-owned stock and resets its
-- resource and ship-reward gains while leaving other saved item fields intact.
-- Session and daily history stay intact in either case.
function trackerState.clearSkill(skill)
    if not ready then return end
    if skill == "ports" then
        local changed = false
        for _, item in pairs(data.ports) do
            if item.gained ~= 0 then
                item.gained = 0
                changed = true
            end
        end
        for _, item in pairs(data.items) do
            if item.skill == "ports" and item.count ~= 0 then
                item.count = 0
                changed = true
            end
        end
        if changed then save() end
        return
    end
    local changed = false
    for itemKey, item in pairs(data.items) do
        if item.skill == skill then
            data.items[itemKey] = nil
            changed = true
        end
    end
    if changed then save() end
end

-- The dock reads this shared table when it draws catalogued resource rows.
function trackerState.getItems()
    return data.items
end

-- Ports displays its current stock separately from gathered item counts.
-- A complete panel read updates all stocks together; only later increases
-- during this login count as gains. Spending and the daily Chimes drop to
-- 200,000 never subtract from gains. Hard-capped stock can hide rewards that
-- produce no visible increase (999,999 resources; 250 trade goods).
function trackerState.observePorts(amounts)
    if not ready then return false end
    local changed = false
    for name, amount in pairs(amounts) do
        local item = data.ports[name]
        if not item then
            item = { owned = amount, gained = 0 }
            data.ports[name] = item
            changed = true
        elseif item.owned ~= amount then
            if portsObserved and item.owned and amount > item.owned then
                item.gained = item.gained + amount - item.owned
            end
            item.owned = amount
            changed = true
        end
    end
    portsObserved = true
    if changed then save() end
    return changed
end

function trackerState.getPorts()
    return data.ports
end

-- A stock goal tracks observed gains, not the game's owned stock. It may be
-- chosen before the first valid stock reading arrives from the client.
function trackerState.setPortGoal(name, goal)
    if not ready then return end
    local item = data.ports[name]
    if not item then
        if not goal then return end
        data.ports[name] = { gained = 0, goal = goal }
        save()
    elseif item.goal ~= goal then
        item.goal = goal
        save()
    end
end

function trackerState.resetPort(name)
    local item = data.ports[name]
    if item and item.gained ~= 0 then
        item.gained = 0
        save()
    end
end

-- The dock and settings window read the same saved preferences.
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

-- A manual boundary clears only this session. The next tracked gain starts
-- another report, while daily history and the main tracker keep their totals.
function trackerState.newSession()
    if not ready then return end
    if sessionStats.reset(data.session, elapsed) then save() end
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

-- Keep edits made before a character record opens, then persist them on open.
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

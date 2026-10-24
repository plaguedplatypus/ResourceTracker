local catalog = require("catalog/resourceCatalog")

local stats = {}
-- A pause stops active-time accumulation. The first gain after login starts
-- a session, and logout ends it through the native game-state event.
local pauseSeconds = 30

-- Session and daily tables use the same resource key as the main tracker.
local function addItem(items, update)
    local key = catalog.makeKey(update.skill, update.name)
    local item = items[key]
    if not item then
        item = { name = update.name, skill = update.skill, count = 0 }
        items[key] = item
    end
    item.count = item.count + update.amount
end

-- Create a day only when the first tracked gain reaches it.
local function day(data, key)
    local entry = data.days[key]
    if not entry then
        entry = { activeSeconds = 0, items = {} }
        data.days[key] = entry
    end
    return entry
end

-- Idle time after the pause threshold never contributes to items per hour.
local function activeSince(current, timestamp)
    return math.min(pauseSeconds, math.max(0, timestamp - current.lastGainAt))
end

-- Store completed active time on each gain.
-- The currently open interval is added only while building a report, so it does not need constant saves.
local function settle(data, timestamp)
    local current = data.current
    if not current then return end
    local seconds = activeSince(current, timestamp)
    current.activeSeconds = current.activeSeconds + seconds
    local entry = day(data, current.day)
    entry.activeSeconds = entry.activeSeconds + seconds
end

-- Start at the first tracked gain so idle time after login is excluded.
function stats.start(data, timestamp, dayKey)
    data.current = {
        startedAt = timestamp,
        lastGainAt = nil,
        activeSeconds = 0,
        items = {},
        day = dayKey
    }
end

-- Automatic gains populate both the current session and its day summary.
function stats.record(data, updates, timestamp, dayKey)
    data.days = data.days or {}
    local current = data.current
    if not current then
        stats.start(data, timestamp, dayKey)
        current = data.current
    elseif current.lastGainAt then
        settle(data, timestamp)
    end
    current.lastGainAt = timestamp
    current.day = dayKey

    local today = day(data, dayKey)
    for _, update in ipairs(updates) do
        if update.amount > 0 then
            addItem(current.items, update)
            addItem(today.items, update)
        end
    end
end

-- Reports are sorted by quantity first, with a stable readable name order.
local function itemList(items)
    local result = {}
    for _, item in pairs(items or {}) do result[#result + 1] = item end
    -- Rank the largest gains first, then use the name for stable ties.
    table.sort(result, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name:lower() < b.name:lower()
    end)
    return result
end

-- Session and day totals include each resource's recorded quantity.
local function total(items)
    local count = 0
    for _, item in pairs(items or {}) do count = count + item.count end
    return count
end

-- The UI adds up to 30 seconds after the most recent gain without writing every client tick to PersistentDB.
function stats.current(data, timestamp)
    local current = data.current
    if not current then
        return { status = "Idle", activeSeconds = 0, total = 0, items = {} }
    end
    if not current.lastGainAt then
        return {
            startedAt = current.startedAt,
            status = "Idle",
            activeSeconds = 0,
            total = 0,
            items = {}
        }
    end
    local activeSeconds = current.activeSeconds + activeSince(current, timestamp)
    local sinceGain = timestamp - current.lastGainAt
    return {
        startedAt = current.startedAt,
        status = sinceGain >= pauseSeconds and "Paused" or "Active",
        activeSeconds = activeSeconds,
        total = total(current.items),
        items = itemList(current.items)
    }
end

-- The history picker presents recorded days from newest to oldest.
function stats.days(data)
    local result = {}
    for key in pairs(data.days or {}) do result[#result + 1] = key end
    -- ISO date keys sort in reverse lexicographic order for newest first.
    table.sort(result, function(a, b) return a > b end)
    return result
end

-- Keep the current gathering session alive while discarding saved day totals.
function stats.clearDays(data)
    data.days = {}
end

-- Only today's open session can add unpersisted active time to a daily view.
function stats.day(data, key, timestamp, currentDay)
    local entry = (data.days or {})[key] or { activeSeconds = 0, items = {} }
    local activeSeconds = entry.activeSeconds
    local current = data.current
    -- An active interval exists only after the first tracked gain.
    if current and current.lastGainAt and key == currentDay then
        activeSeconds = activeSeconds + activeSince(current, timestamp)
    end
    return { activeSeconds = activeSeconds, total = total(entry.items), items = itemList(entry.items) }
end

-- Before a chat timestamp arrives, gains use the temporary Today bucket.
-- Move that bucket into the dated record once the client provides a time.
function stats.moveDay(data, from, to)
    if from == to then return false end
    local old = data.days and data.days[from]
    if not old then return false end
    local target = day(data, to)
    target.activeSeconds = target.activeSeconds + old.activeSeconds
    for _, item in pairs(old.items) do
        addItem(target.items, { name = item.name, skill = item.skill, amount = item.count })
    end
    data.days[from] = nil
    if data.current and data.current.day == from then
        data.current.day = to
    end
    return true
end

-- Logout ends the session. Daily history is retained separately.
function stats.close(data)
    data.current = nil
end

return stats

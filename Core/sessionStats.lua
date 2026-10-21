local catalog = require("catalog/resourceCatalog")

local stats = {}
-- A pause stops active-time accumulation, but login and logout define the
-- session itself because the native client provides those game-state events.
local pauseSeconds = 30

local function addItem(items, update)
    -- Session and daily tables use the same resource key as the main tracker.
    local key = catalog.makeKey(update.skill, update.name)
    local item = items[key]
    if not item then
        item = { name = update.name, skill = update.skill, count = 0 }
        items[key] = item
    end
    item.count = item.count + update.amount
end

local function day(data, key)
    -- Create a day only when the first tracked gain reaches it.
    local entry = data.days[key]
    if not entry then
        entry = { activeSeconds = 0, items = {} }
        data.days[key] = entry
    end
    return entry
end

local function activeSince(current, timestamp)
    -- Idle time after the pause threshold never contributes to items per hour.
    return math.min(pauseSeconds, math.max(0, timestamp - current.lastGainAt))
end

local function settle(data, timestamp)
    -- Store completed active time on each gain. The currently open interval is
    -- added only while building a report, so it does not need constant saves.
    local current = data.current
    if not current then return end
    local seconds = activeSince(current, timestamp)
    current.activeSeconds = current.activeSeconds + seconds
    local entry = day(data, current.day)
    entry.activeSeconds = entry.activeSeconds + seconds
end

function stats.start(data, timestamp, dayKey)
    -- Start at login even before the first resource gain. lastGainAt stays nil
    -- until then so idle login time is never counted as gathering activity.
    data.current = {
        startedAt = timestamp,
        lastGainAt = nil,
        activeSeconds = 0,
        items = {},
        day = dayKey
    }
end

function stats.record(data, updates, timestamp, dayKey)
    -- Automatic gains populate both the current session and its day summary.
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

local function itemList(items)
    -- Reports are sorted by quantity first, with a stable readable name order.
    local result = {}
    for _, item in pairs(items or {}) do result[#result + 1] = item end
    table.sort(result, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name:lower() < b.name:lower()
    end)
    return result
end

local function total(items)
    local count = 0
    for _, item in pairs(items or {}) do count = count + item.count end
    return count
end

function stats.current(data, timestamp)
    -- The UI adds up to 30 seconds after the most recent gain without writing
    -- every client tick to PersistentDB.
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

function stats.days(data)
    local result = {}
    for key in pairs(data.days or {}) do result[#result + 1] = key end
    table.sort(result, function(a, b) return a > b end)
    return result
end

function stats.clearDays(data)
    -- Keep the current gathering session alive while discarding saved day totals.
    data.days = {}
end

function stats.day(data, key, timestamp, currentDay)
    -- Only today's open session can add unpersisted active time to a daily view.
    local entry = (data.days or {})[key] or { activeSeconds = 0, items = {} }
    local activeSeconds = entry.activeSeconds
    local current = data.current
    -- A session exists from login, but it has no active interval until its
    -- first resource gain establishes lastGainAt.
    if current and current.lastGainAt and key == currentDay then
        activeSeconds = activeSeconds + activeSince(current, timestamp)
    end
    return { activeSeconds = activeSeconds, total = total(entry.items), items = itemList(entry.items) }
end

function stats.moveDay(data, from, to)
    -- Before a chat timestamp arrives, gains use the temporary Today bucket.
    -- Move that bucket into the dated record once the client provides a time.
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

function stats.close(data)
    -- Login and logout bound a session. Daily history is retained separately.
    data.current = nil
end

return stats

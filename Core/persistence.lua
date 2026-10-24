local persistence = {}
-- Keep all tracker data under one stable record name per character.
local storageName = "resourceTrackerV1"

-- Namespace saved data per account so characters do not share tracker totals.
local function storageKey(accountId)
    return storageName .. ":" .. tostring(accountId)
end

-- Persistent data is an external boundary, so reject malformed counts,
-- goals, item IDs, and ordering values before using them in the UI.
local function nonNegativeInteger(value)
    return type(value) == "number" and value >= 0 and value % 1 == 0
end

-- Start from a complete empty shape. Saved fields are copied in only after
-- validation so an invalid record cannot prevent the tracker from loading.
function persistence.load(accountId)
    local saved = PersistentDB:GetStructuredData(storageKey(accountId))
    local data = { items = {}, order = 0, settings = {}, session = { days = {} } }
    if type(saved) ~= "table" then
        return data
    end

    if nonNegativeInteger(saved.order) then
        data.order = saved.order
    end
    if type(saved.settings) == "table" then
        local settings = saved.settings
        data.settings.category = type(settings.category) == "string" and settings.category or "all"
        data.settings.group = type(settings.group) == "string" and settings.group or "all"
        data.settings.sort = (settings.sort == "name" or settings.sort == "count")
            and settings.sort or "recent"
        data.settings.showIcons = settings.showIcons ~= false
        data.settings.showGoals = settings.showGoals ~= false
        if type(settings.hiddenSkills) == "table" then
            data.settings.hiddenSkills = {}
            for skill, hidden in pairs(settings.hiddenSkills) do
                if type(skill) == "string" and hidden == true then
                    data.settings.hiddenSkills[skill] = true
                end
            end
        end
    end
    if type(saved.session) == "table" then
        -- Session history is tracker-owned structured data. 
        -- It is retained as recorded so its item lists and active-time totals remain together.
        data.session = saved.session
    end

    if type(saved.items) == "table" then
        -- Item records are checked field by field because they are displayed
        -- directly in the docked tracker and can be manually edited by players.
        for itemKey, item in pairs(saved.items) do
            if type(itemKey) == "string" and type(item) == "table"
                and type(item.name) == "string" and type(item.skill) == "string"
                and nonNegativeInteger(item.count) then
                data.items[itemKey] = {
                    name = item.name,
                    skill = item.skill,
                    source = type(item.source) == "string" and item.source or nil,
                    itemId = nonNegativeInteger(item.itemId) and item.itemId or nil,
                    count = item.count,
                    goal = nonNegativeInteger(item.goal) and item.goal > 0 and item.goal or nil,
                    order = nonNegativeInteger(item.order) and item.order or 0
                }
            end
        end
    end
    if type(saved.ids) == "table" then
        -- Older records stored a second ID-to-item map. 
        -- Keep any ID missing from its item row, then save only the row on the next data change.
        for id, itemKey in pairs(saved.ids) do
            local itemId = tonumber(id)
            local item = type(itemKey) == "string" and data.items[itemKey]
            if item and not item.itemId and nonNegativeInteger(itemId) then
                item.itemId = itemId
            end
        end
    end
    return data
end

-- Save the complete state together so counts, settings, and history stay in sync.
function persistence.save(data, accountId)
    return PersistentDB:SetStructuredData(storageKey(accountId), data)
end

return persistence

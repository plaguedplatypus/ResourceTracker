local persistence = {}
-- Keep one local record per character, reachable by ID or linked name.
local storageName = "resourceTrackerV1"

-- Namespace saved data per account so characters do not share tracker totals.
local function storageKey(accountId)
    return storageName .. ":" .. tostring(accountId)
end

-- An ID is the preferred lookup. If this character started with no tracking
-- permission, link that name-only record to the ID without moving its data.
function persistence.resolve(id, name)
    if id then
        local idAlias = storageName .. ":lookup:id:" .. id
        local linked = PersistentDB:GetStructuredData(idAlias)
        if type(linked) ~= "table" or type(linked.account) ~= "string" then linked = nil end
        local account = linked and linked.account
        if not account then
            account = "id:" .. id
            if name and PersistentDB:CheckExists(storageKey("name:" .. name)) then
                account = "name:" .. name
            end
        end
        local nameAlias = storageName .. ":lookup:name:" .. name
        local nameLinked = PersistentDB:SetString(nameAlias, account)
        local idLinked = PersistentDB:SetStructuredData(idAlias,
            { account = account, name = name })
        -- A renamed character must not leave its old name pointing at this save.
        if nameLinked and idLinked and linked and type(linked.name) == "string"
            and linked.name ~= name then
            local oldAlias = storageName .. ":lookup:name:" .. linked.name
            if PersistentDB:GetString(oldAlias) == account then
                PersistentDB:Delete(oldAlias)
            end
        end
        return account, nameLinked and idLinked
    end
    if name then
        return PersistentDB:GetString(storageName .. ":lookup:name:" .. name) or "name:" .. name, true
    end
end

-- List saved records, not lookup links, so the settings picker shows each
-- character profile once even when it has both a name and tracking ID.
function persistence.profiles()
    local profiles, names = {}, {}
    local recordPrefix = storageName .. ":"
    local idPrefix = storageName .. ":lookup:id:"
    PersistentDB:IterateEntries(function(key, value)
        if key:sub(1, #idPrefix) == idPrefix and type(value) == "table"
            and type(value.account) == "string" and type(value.name) == "string" then
            names[value.account] = value.name
            names[key:sub(#idPrefix + 1)] = value.name
        elseif key:sub(1, #recordPrefix) == recordPrefix and type(value) == "table"
            and type(value.items) == "table" then
            local account = key:sub(#recordPrefix + 1)
            -- Older saves used the bare numeric tracking ID as their key.
            if account:sub(1, 3) == "id:" or account:sub(1, 5) == "name:"
                or account:match("^%-?%d+$") then
                local count = 0
                for _, item in pairs(value.items) do
                    if type(item) == "table" and type(item.count) == "number" then
                        count = count + item.count
                    end
                end
                profiles[#profiles + 1] = { account = account, count = count }
            end
        end
        return false
    end)
    for _, profile in ipairs(profiles) do
        profile.name = names[profile.account]
            or profile.account:match("^name:(.+)$") or "Unknown character"
    end
    table.sort(profiles, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.account < b.account
    end)
    return profiles
end

function persistence.exists(accountId)
    return PersistentDB:CheckExists(storageKey(accountId))
end

function persistence.clearAll()
    return PersistentDB:Clear()
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
    local data = { items = {}, ports = {}, order = 0, settings = {}, session = { days = {} } }
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
        data.settings.showArtefacts = settings.showArtefacts ~= false
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
                    pinned = item.pinned == true or nil,
                    order = nonNegativeInteger(item.order) and item.order or 0
                }
            end
        end
    end
    if type(saved.ports) == "table" then
        -- Ports stock is read from game variables; saved values are the last
        -- complete observation and the positive changes seen by this plugin.
        for name, item in pairs(saved.ports) do
            if type(name) == "string" and type(item) == "table"
                and (item.owned == nil or nonNegativeInteger(item.owned))
                and nonNegativeInteger(item.gained) then
                data.ports[name] = {
                    owned = item.owned,
                    gained = item.gained,
                    goal = nonNegativeInteger(item.goal) and item.goal > 0
                        and item.goal or nil
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

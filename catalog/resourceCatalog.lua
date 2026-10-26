local materials = require("catalog/archaeology/materials")
local artefacts = require("catalog/archaeology/artefacts")
local finds = require("catalog/archaeology/finds")
local mining = require("catalog/mining")
local woodcutting = require("catalog/woodcutting")
local fishing = require("catalog/fishing")
local serenSpirit = require("catalog/serenSpirit")

local catalog = {}
-- Skill files own resource definitions. Build name and alias lookups for chat,
-- item ID lookups for backpack gains, and groups for the skill filters.
local byName = {}
local byId = {}
local groupsBySkill = {}

-- These entries drive the tracker tabs and the order in which players see them.
local categories = {
    { id = "all", label = "All" },
    { id = "mining", label = "Mining" },
    { id = "woodcutting", label = "Woodcutting" },
    { id = "fishing", label = "Fishing" },
    { id = "archaeology", label = "Archaeology" },
    { id = "farming", label = "Farming" },
    { id = "invention", label = "Invention" },
    { id = "divination", label = "Divination" },
    { id = "hunter", label = "Hunter" },
    { id = "seren", label = "Spirits" }
}

-- Dig sites follow their first Archaeology level instead of their names.
-- Keep this order separate from group labels and resource definitions.
local archaeologyOrder = {
    ["Kharid-et"] = 1,
    ["Infernal Source"] = 2,
    ["Everlight"] = 3,
    ["Moonrise"] = 4,
    ["Senntisten"] = 5,
    ["Stormguard"] = 6,
    ["Daemonheim"] = 7,
    ["Warforge"] = 8,
    ["Orthen"] = 9
}

-- Game messages, inventory names, and catalog entries use slightly different
-- punctuation and spacing. Use one form for all catalog and tracker keys.
function catalog.normalize(name)
    local cleaned = name:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    cleaned = cleaned:gsub("[%.,;:]+$", "")
    -- Woodcutting chat can name the tree while inventory names the logs.
    local normalized = cleaned:gsub(" tree logs$", " logs")
    return normalized
end

-- Register a resource under its display name, ID, and known chat aliases.
local function add(name, skill, groups, itemId, spriteId, artefact, aliases)
    local normalized = catalog.normalize(name)
    assert(not byName[normalized], "Duplicate resource: " .. name)
    local definition = {
        name = name,
        skill = skill,
        groups = {},
        itemId = itemId or nil,
        spriteId = spriteId or nil,
        artefact = artefact or nil
    }
    for _, group in ipairs(groups) do
        definition.groups[group] = true
        groupsBySkill[skill] = groupsBySkill[skill] or {}
        groupsBySkill[skill][group] = true
    end
    byName[normalized] = definition
    for _, alias in ipairs(aliases or {}) do
        local aliasName = catalog.normalize(alias)
        assert(not byName[aliasName], "Duplicate resource alias: " .. alias)
        byName[aliasName] = definition
    end
    if itemId then
        assert(not byId[itemId], "Duplicate resource ID: " .. itemId)
        byId[itemId] = definition
    end
end

for name, entry in pairs(materials) do
    add(name, "archaeology", entry.sites, entry.id)
end
for name, itemId in pairs(finds) do
    add(name, "archaeology", { "Rare finds" }, itemId)
end
for site, names in pairs(artefacts) do
    for _, name in ipairs(names) do
        add(name, "archaeology", { site }, nil, nil, true)
    end
end
local grouped = {
    mining = mining,
    woodcutting = woodcutting,
    fishing = fishing,
    farming = require("catalog/farming"),
    invention = require("catalog/invention"),
    divination = require("catalog/divination"),
    hunter = require("catalog/hunter")
}
for skill, sections in pairs(grouped) do
    for group, entries in pairs(sections) do
        for name, value in pairs(entries) do
            if skill == "invention" then
                add(name, skill, { group }, nil, value)
            elseif type(value) == "table" then
                add(name, skill, { group }, value.id, nil, nil, value.aliases)
            else
                add(name, skill, { group }, value)
            end
        end
    end
end

-- Add only gifts absent from the skill catalogs above. Their empty group list
-- keeps the Spirits tab free of a group picker; salvage uses its icon lookup.
for name, itemId in pairs(serenSpirit) do
    add(name, "seren", {}, itemId)
end

-- Inventory deltas use object IDs, which avoid ambiguous display names.
function catalog.findById(itemId)
    return byId[itemId]
end

-- Resolve chat names with the skill hint when multiple resources share a name.
function catalog.find(name, skillHint)
    local normalized = catalog.normalize(name)
    if normalized == "" then
        return nil
    end
    if skillHint == "seren" then
        -- The Seren chat message confirms the gift even when it is not a
        -- gathering resource. Keep known item IDs for their icons.
        local known = byName[normalized]
        return { name = known and known.name or name, skill = "seren", groups = {},
            itemId = known and known.itemId or nil }
    end
    local known = byName[normalized]
    if known and (not skillHint or known.skill == skillHint) then
        return known
    end
    if normalized:find("(damaged)", 1, true) then
        -- Damaged artefacts include a variable condition suffix. Match the
        -- longest catalogued artefact prefix to retain its excavation site.
        local base = normalized:gsub("%s*%(damaged%)$", "")
        local matchedName
        local matched
        for prefix, definition in pairs(byName) do
            if definition.artefact and base:sub(1, #prefix) == prefix
                and (not matchedName or #prefix > #matchedName) then
                matchedName = prefix
                matched = definition
            end
        end
        return {
            name = name,
            skill = "archaeology",
            groups = matched and matched.groups or {},
            artefact = true
        }
    end
    -- Catch messages can omit "Raw" even though the backpack item includes it.
    if skillHint == "fishing" then
        local raw = byName["raw " .. normalized]
        return raw and raw.skill == "fishing" and raw or nil
    end
    if skillHint == "farming" or skillHint == "invention" or skillHint == "archaeology"
        or skillHint == "mining" or skillHint == "woodcutting" then
        return nil
    end
    return nil
end

-- Source distinguishes rewards such as Seren gifts from ordinary skill gains.
function catalog.makeKey(skill, name, source)
    return (source or skill) .. ":" .. catalog.normalize(name)
end

-- Keep tab order stable across panel rebuilds.
function catalog.getCategories()
    return categories
end

-- Divination has no subgroup picker; other skills start with All groups.
function catalog.getGroups(skill)
    if skill == "divination" then return { "all" } end
    local result = { "all" }
    for group in pairs(groupsBySkill[skill] or {}) do
        result[#result + 1] = group
    end
    -- Sites follow level order, while catch-all finds sit after ordinary groups.
    local function order(group)
        if group == "all" then return 0 end
        if group == "Rare finds" or group:lower():match("^other") then return 100 end
        if skill == "archaeology" then return archaeologyOrder[group] or 90 end
        return 1
    end
    table.sort(result, function(a, b)
        local first, second = order(a), order(b)
        if first ~= second then return first < second end
        return a < b
    end)
    return result
end

return catalog

local data = require("catalog/catalogData")

local catalog = {}
local byName = {}
local options = {}

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

function catalog.normalize(name)
    -- Game messages, inventory names, and catalog entries use slightly different
    -- punctuation and spacing. Use one form for all catalog and tracker keys.
    local cleaned = name:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    cleaned = cleaned:gsub("[%.,;:]+$", "")
    -- Woodcutting chat can name the tree while inventory names the logs.
    local normalized = cleaned:gsub(" tree logs$", " logs")
    return normalized
end

local function add(name, skill, group)
    -- A resource can belong to several groups, especially Archaeology sites.
    local normalized = catalog.normalize(name)
    local definition = byName[normalized]
    if definition then
        if group then
            definition.groups[group] = true
        end
        return
    end
    definition = { name = name, skill = skill, groups = {} }
    if group then
        definition.groups[group] = true
    end
    byName[normalized] = definition
    options[skill] = options[skill] or {}
    options[skill][#options[skill] + 1] = definition
end

-- Archaeology has two display sections but shares the same site filters.
for site, items in pairs(data.archaeology.materials) do
    for _, name in ipairs(items) do
        add(name, "archaeology", site)
    end
end
for site, items in pairs(data.archaeology.artefacts) do
    for _, name in ipairs(items) do
        add(name, "archaeology", site)
        byName[catalog.normalize(name)].artefact = true
    end
end
for skill, groups in pairs(data) do
    if skill ~= "archaeology" then
        for group, items in pairs(groups) do
            for _, name in ipairs(items) do
                add(name, skill, group)
            end
        end
    end
end

local miningWords = { "limestone", "essence", "clay", "sandstone", "granite", "calcified" }
local woodcuttingWords = {
    "logs", "bird's nest", "crystal geode", "bamboo", "timber", "eternal magic tree branch",
    "petrified roots", "petrified bark", "petrified knot", "chima moss"
}
local fishNames = {
    "shrimp", "anchovies", "trout", "salmon", "tuna", "lobster", "swordfish", "shark",
    "monkfish", "rocktail", "sailfish", "manta ray", "sea turtle", "jellyfish", "cavefish",
    "catfish", "bass", "cod", "herring", "mackerel", "pike", "crayfish"
}

local function hasWord(name, word)
    return name == word or name:sub(1, #word + 1) == word .. " "
        or name:sub(-#word - 1) == " " .. word
        or name:find(" " .. word .. " ", 1, true) ~= nil
end

function catalog.find(name, skillHint)
    local normalized = catalog.normalize(name)
    if normalized == "" then
        return nil
    end
    if skillHint == "seren" then
        -- Seren rewards can contain many items, so preserve their provided name.
        return { name = name, skill = "seren", groups = {} }
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
    -- Direct gathering messages already identify their skill. Their item names
    -- may be absent from the finite resource list, so keep that classification.
    if skillHint == "fishing" or skillHint == "woodcutting" then
        return { name = name, skill = skillHint, groups = {} }
    end
    if skillHint == "farming" or skillHint == "invention" or skillHint == "archaeology" then
        return nil
    end
    if normalized:sub(-4) == " ore" then
        return { name = name, skill = "mining", groups = {} }
    end
    for _, word in ipairs(miningWords) do
        if hasWord(normalized, word) then
            return { name = name, skill = "mining", groups = {} }
        end
    end
    for _, word in ipairs(woodcuttingWords) do
        if hasWord(normalized, word) then
            return { name = name, skill = "woodcutting", groups = {} }
        end
    end
    if normalized:sub(1, 4) == "raw " then
        local fish = normalized:sub(5)
        for _, namePart in ipairs(fishNames) do
            if fish == namePart or fish:sub(-#namePart) == namePart then
                return { name = name, skill = "fishing", groups = {} }
            end
        end
    end
    if normalized:sub(1, 8) == "leaping " or normalized == "algae" then
        return { name = name, skill = "fishing", groups = {} }
    end
    return nil
end

function catalog.makeKey(skill, name, source)
    return (source or skill) .. ":" .. catalog.normalize(name)
end

function catalog.getCategories()
    return categories
end

function catalog.getGroups(skill)
    if skill == "divination" then return { "all" } end
    local groups = {}
    for _, definition in ipairs(options[skill] or {}) do
        for group in pairs(definition.groups) do
            groups[group] = true
        end
    end
    local result = { "all" }
    for group in pairs(groups) do
        result[#result + 1] = group
    end
    table.sort(result, function(a, b)
        if a == "all" then return true end
        if b == "all" then return false end
        return a < b
    end)
    return result
end

return catalog

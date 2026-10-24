local catalog = require("catalog/resourceCatalog")

local chatParser = {}

local function clean(text)
    -- Game messages can contain colour tags and inconsistent whitespace.
    return text:gsub("<[^>]*>", ""):gsub("%s+", " "):gsub("^%s+", "")
        :gsub("%s+$", "")
end

local function amount(text)
    local digits = text:gsub(",", "")
    local number = tonumber(digits)
    if number and number > 0 and number % 1 == 0 then
        return number
    end
    return nil
end

local function update(name, quantity, skill, source)
    name = name:gsub("[%s%.!,]+$", "")
    local definition = catalog.find(name, skill)
    if not definition or not quantity or quantity <= 0 then
        return nil
    end
    -- Chat rewards use the catalog ID for their icon because no item ID is observed.
    return { name = definition.name, skill = definition.skill, amount = quantity,
        source = source, itemId = definition.itemId }
end

local function splitEntries(text, skill, source)
    -- Multi-reward lines separate entries with a comma followed by another N x prefix.
    -- Require spacing after a separator so a thousands comma stays in the amount.
    local separated = text:gsub(",%s+([%d,]+)%s*x%s+", "\n%1 x ")
    local result = {}
    for part in separated:gmatch("[^\n]+") do
        local digits, name = part:match("^%s*([%d,]+)%s*x%s+(.+)%s*$")
        local entry = digits and update(name, amount(digits), skill, source) or nil
        if not entry then
            return nil
        end
        result[#result + 1] = entry
    end
    return #result > 0 and result or nil
end

local function parseInvention(text)
    -- Invention sends both single rewards and comma-separated material batches.
    local payload = text:match("^Materials gained:%s*(.+)$")
        or text:match("^Your Scavenging perk adds:%s*(.+)$")
        or text:match("^Your Leagues? Scavenging perk finds:?%s*(.+)$")
    if payload then
        if payload:match(",%s*$") then
            return nil
        end
        return splitEntries(payload, "invention")
    end
    local digits, name = text:match("^You receive%s+([%d,]+)%s+(.+)$")
    if digits then
        local entry = update(name, amount(digits), "invention")
        return entry and { entry } or nil
    end
    return nil
end

local function parseSpirit(text)
    -- Only Seren spirit gifts belong to the tracker spirit category.
    local payload = text:match("^The Seren spirit gifts you:%s*(.+)$")
    if not payload then
        return nil
    end
    payload = payload:gsub("%s+The gift is sent to your bank%.?$", "")
    return splitEntries(payload, "seren", "seren-spirit")
end

local function parseFarming(text)
    -- Farming skillcape rewards arrive noted, so chat owns the gain.
    local digits, name = text:match(
        "^Your Farming skillcape perk harvested and noted%s+([%d,]+)%s*x%s+(.+)$")
    if not digits then
        digits, name = text:match(
            "^Your Farming skillcape perk instantly harvests and notes%s+([%d,]+)%s*x%s+(.+)$")
    end
    if digits then
        local entry = update(name, amount(digits), "farming")
        return entry and { entry } or nil
    end
    return nil
end

local function parseTransport(text)
    -- Bank, metal-bank, and material-storage messages.
    -- "The logs are magically escorted to your bank" omits the log type and quantity.
    local destination, payload = text:match("^You transport to your ([^:]+):%s*(.+)$")
    if not destination then
        destination, payload = text:match(
            "^Your League relic transports the following item to your ([^:]+):%s*(.+)$")
    end
    if not destination then
        -- Boon of Crondis uses this bank-delivery wording for any gathering skill.
        destination, payload = text:match("sent it to your ([^:]+):%s*(.+)$")
    end
    if not destination then
        destination, payload = text:match("transports your items to your ([^:]+):%s*(.+)$")
    end
    if not destination then
        return nil
    end
    local hint
    local lowerDestination = destination:lower()
    local metalBank = lowerDestination:find("metal bank", 1, true) ~= nil
    if metalBank then
        hint = "mining"
    elseif lowerDestination:find("material storage", 1, true) then
        hint = "archaeology"
    elseif not lowerDestination:find("bank", 1, true) then
        return nil
    end
    if payload:match("^[%d,]+%s*x%s+") then
        return splitEntries(payload, hint), metalBank, false, destination
    end
    local entry = update(payload, 1, hint)
    -- Some transport perks omit quantity; a transmitted metal-bank delta can supply it.
    return entry and { entry } or nil, metalBank, metalBank, destination
end

local function parseArchaeology(text)
    -- Artefact names include "(damaged)" and are grouped by the catalog.
    local name = text:match("^You find:%s*(.+%(damaged%))[%.!]?$", 1)
        or text:match("^You find some%s+([^%.!]+)[%.!]$")
    if not name then
        return nil
    end
    local entry = update(name, 1, "archaeology")
    return entry and { entry } or nil
end

local function parseDirect(text)
    -- Direct gathering messages identify the item for a nearby inventory change.
    local name = text:match("^You get some%s+([^%.!]+)[%.!]")
        or text:match("^You find an?%s+(enchanted bird's nest)[%.!]")
        or text:match("^You find an?%s+(bird's nest)[%.!]")
        or text:match("^You find an?%s+(eternal magic tree branch)[%.!]")
    if name then
        local known = catalog.find(name)
        if not known or known.skill ~= "woodcutting" then
            return nil
        end
        local entry = update(name, 1, "woodcutting")
        return entry and { entry } or nil
    end
    name = text:match("^You catch an?%s+([^%.!]+)%.")
        or text:match("^You catch some%s+([^%.!]+)%.")
    if name then
        local known = catalog.find(name)
        if known and known.skill ~= "fishing" then
            return nil
        end
        local entry = update(name, 1, "fishing")
        return entry and { entry } or nil
    end
    return nil
end

function chatParser.parse(rawText)
    -- Test the specific message formats first. Unrecognised chat is discarded.
    local text = clean(rawText)
    -- The bank-transport line already includes the delivered Scraps bonus.
    -- Its separate perk notice must not create another resource gain.
    if text:lower():find("scraps perk", 1, true) then return nil end
    local entries = parseSpirit(text)
    if entries then return { method = "spirit", entries = entries } end
    entries = parseInvention(text)
    if entries then return { method = "invention", entries = entries } end
    entries = parseFarming(text)
    if entries then return { method = "farming", entries = entries } end
    local metalBank, unknownAmount, destination
    entries, metalBank, unknownAmount, destination = parseTransport(text)
    if entries then
        return { method = "remote", entries = entries,
            metalBank = metalBank, unknownAmount = unknownAmount,
            destination = destination, message = text }
    end
    entries = parseArchaeology(text)
    if entries then return { method = "archaeology", entries = entries } end
    entries = parseDirect(text)
    if entries then return { method = "direct", entries = entries } end
    return nil
end

return chatParser

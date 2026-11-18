local catalog = require("catalog/resourceCatalog")

local resourceRow = {}
resourceRow.skillIcons = {
    all = id.Sprite.RS3_ICON_POH_TRUNK_ALL,
    mining = id.Sprite.STATICONS_HIGH_RES_CLEAN_12,
    woodcutting = id.Sprite.STATICONS_HIGH_RES_CLEAN_17,
    fishing = id.Sprite.STATICONS_HIGH_RES_CLEAN_14,
    archaeology = id.Sprite.SKILL_ICON_ARCHAEOLOGY_52PX_0,
    farming = id.Sprite.STATICONS_HIGH_RES2_CLEAN_2,
    invention = id.Sprite.SKILL_ICON_INVENTION_52PX_0,
    divination = id.Sprite.STATICONS_HIGH_RES2_CLEAN_14,
    hunter = id.Sprite.STATICONS_HIGH_RES2_CLEAN_5,
    ports = id.Sprite.AIF_POP_ANCHOR_ICON_0
}
local colour = {
    normal = Vector4.new(0.96, 0.88, 0.72, 1),
    count = Vector4.new(1, 1, 1, 1),
    goal = Vector4.new(0.40, 0.85, 0.48, 1),
    rare = Vector4.new(0.88, 0.42, 0.38, 1),
    uncommon = Vector4.new(0.90, 0.63, 0.23, 1),
    ancient = Vector4.new(0.34, 0.78, 0.77, 1),
    seren = Vector4.new(0.47, 0.90, 0.97, 1)
}
resourceRow.goalColour = colour.goal
local iconIds = {}

-- Use the same font and alignment for tracker labels.
function resourceRow.label(owner, value, x, y, width, height, tint, right)
    local component = ui.Text.new(owner)
    component:SetPos(x, y)
    component:SetSize(width, height)
    component.content = value
    component.font = id.Font.MUSEO_SANS_15PT_REGULAR
    component.colour = tint or colour.normal
    component.maxLines = 1
    if right then component.alignHorizontal = ui.AlignMode.BOTTOMRIGHT end
    component.clickthrough = true
    return component
end

local label = resourceRow.label

-- Keep item names readable after catalog normalization.
local function capitalize(name)
    return name:gsub("^%l", string.upper)
end

-- RuneScape item counts are whole numbers even when stored as Lua numbers.
function resourceRow.formatCount(value)
    return string.format("%.0f", value)
end

-- Confirm the config object name before using its ID for a chat-only reward.
local function configId(configName, name)
    -- The config may not define every item name seen in chat.
    local ok, obj = pcall(function() return config.Obj[configName] end)
    if ok and obj and catalog.normalize(obj.name) == name then return obj.id end
end

-- Backpack gains provide an object ID.
-- Chat rewards use a catalogued ID or a cached exact-name config lookup.
local function iconId(item)
    if item.itemId then return item.itemId end
    local definition = catalog.find(item.name, item.skill)
    if definition and definition.itemId then return definition.itemId end
    local name = catalog.normalize(item.name)
    if iconIds[name] == nil then
        local configName = item.name:upper():gsub("[^A-Z0-9]+", "_")
        local found = configId(configName, name)
        if not found then
            -- Salvage configs put the type first and the size last.
            -- Look up the config name because salvage IDs are scattered.
            local size, shape, metal = name:match("^(%a+) (%a+) (%a+) salvage$")
            if size then
                configName = shape:upper() .. "_SALVAGE_" .. metal:upper()
                    .. "_" .. size:upper()
                found = configId(configName, name)
            end
        end
        -- Config names often match item names, but only an exact display-name
        -- match is safe for a chat reward that supplies no object ID.
        iconIds[name] = found or false
    end
    return iconIds[name] or nil
end

-- Highlight special reward sources without changing their displayed names.
local function nameColour(item)
    if item.skill == "seren" then
        return colour.seren
    end
    if item.skill == "invention" then
        local definition = catalog.find(item.name, item.skill)
        local groups = definition and definition.groups or {}
        if groups.ancient then return colour.ancient end
        if groups.rare then return colour.rare end
        if groups.uncommon then return colour.uncommon end
    end
    return colour.normal
end

-- Apply the visibility settings shared by the dock and overlay.
function resourceRow.isVisible(item, definition, hiddenSkills, showArtefacts)
    return item.skill ~= "ports" and not hiddenSkills[item.skill]
        and (showArtefacts ~= false or not (definition and definition.artefact))
end

local function addIcon(row, item)
    local definition = item.skill == "invention" and catalog.find(item.name, item.skill)
    local spriteId = definition and definition.spriteId
    local objectId
    if not spriteId then objectId = iconId(item) end
    if spriteId or objectId then
        local icon = ui.Sprite.new(row)
        icon:SetPos(2, 2)
        icon:SetSize(18, 18)
        if spriteId then
            icon.spriteID = spriteId
        else
            icon:SetAssociatedObject(objectId)
            icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        end
        icon.clickthrough = true
    else
        -- Some chat rewards have neither an object ID nor a material sprite.
        local skillIcon = resourceRow.skillIcons[item.skill]
        local serenImage
        if item.skill == "seren" and Plugin.resources then
            serenImage = Plugin.resources.seren or Plugin.resources["seren.png"]
        end
        if skillIcon or serenImage then
            local icon = ui.Sprite.new(row)
            if skillIcon then
                icon:SetPos(3, 3)
                icon:SetSize(16, 16)
                icon.spriteID = skillIcon
            else
                icon:SetPos(4, 2)
                icon:SetSize(14, 18)
                icon.sprite = serenImage
            end
            icon.clickthrough = true
        else
            label(row, "•", 3, 0, 16, 20)
        end
    end
end

-- Draw the icon, name and count. Return the name bounds for the dock tooltip.
function resourceRow.draw(row, item, settings, rowWidth, options)
    local iconWidth = settings.showIcons == false and 2 or 20
    local count = item.count
    if settings.showIcons ~= false then addIcon(row, item) end
    local showGain = settings.showGainPlus ~= false and count > 0
    local countText = resourceRow.formatCount(count)
    local numberWidth = utils.CalcTextWidth(id.Font.MUSEO_SANS_15PT_REGULAR, countText)
    local plusWidth = showGain
        and utils.CalcTextWidth(id.Font.MUSEO_SANS_15PT_REGULAR, "+") + 2 or 0
    local countWidth = math.max(49,
        numberWidth + plusWidth + 2)
    local name = capitalize(item.name)
    local pinned = options.showPin and item.pinned
    local pinWidth = pinned and 16 or 0
    local nameWidth = math.max(1, rowWidth - iconWidth - countWidth - pinWidth - 8)
    local nameX = iconWidth + 3
    local nameLabel = label(row, name, nameX, 1, nameWidth, 21, nameColour(item))
    if pinned then
        local pin = ui.Sprite.new(row)
        pin:SetPos(rowWidth - countWidth - 19, 4)
        pin:SetSize(14, 14)
        pin.spriteID = id.Sprite.ACHIEVEMENT_ICON_PIN_14PX_0
        pin.clickthrough = true
    end
    local countLabel = label(row, countText, rowWidth - countWidth - 3, 1,
        countWidth, 21, colour.count, true)
    local plusLabel
    if showGain then
        plusLabel = label(row, "+", rowWidth - numberWidth - plusWidth - 3, 1,
            plusWidth, 21, colour.goal, true)
    end
    if options.shadow then
        -- Client 951-1 supports the default text shadow but lacks the shadowRGBA setter.
        nameLabel.isShadowed = true
        countLabel.isShadowed = true
        if plusLabel then plusLabel.isShadowed = true end
    end
    return name, nameX, nameWidth
end

return resourceRow

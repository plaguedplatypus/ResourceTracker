local catalog = require("catalog/resourceCatalog")
local state = require("ui/trackerState")
local itemEditor = require("ui/itemEditor")

local ports = {}

-- These are the resource labels in the game's Ports panel, reading each row
-- from left to right as shown by the two-column Resources display.
local groups = {
    { id = "resources", title = "PORTS RESOURCES", names = {
        "Chimes", "Bamboo", "Gunpowder", "Black slate", "Cherrywood",
        "Jade", "Stainless Steel", "Terracotta", "Azure"
    }, varPrefix = "POP_PORT_RESOURCE_" },
    { id = "trade", title = "TRADE GOODS", names = {
        "Ancient Bones", "Plate", "Spices", "Lacquer", "Chi",
        "Eastern Pearls", "Koi Scales"
    }, varPrefix = "POP_REWARD_RESOURCE_" },
    { id = "ships", title = "SHIP REWARDS", names = {
        "Gemstone kaseki", "Tengu tsuba"
    } }
}
-- Ports uses its own cargo sprites rather than backpack object icons.
local sprites = {
    ["Chimes"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_0,
    ["Bamboo"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_1,
    ["Black slate"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_2,
    ["Stainless Steel"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_3,
    ["Gunpowder"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_4,
    ["Cherrywood"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_5,
    ["Jade"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_6,
    ["Ancient Bones"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_7,
    ["Plate"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_8,
    ["Spices"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_9,
    ["Lacquer"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_10,
    ["Chi"] = id.Sprite.AIF_POP_CARGO_ICONS_34X34_11,
    ["Koi Scales"] = id.Sprite.AIF_POP_EXP_CARGO_ICONS_34X34_35,
    ["Eastern Pearls"] = id.Sprite.AIF_POP_EXP_CARGO_ICONS_34X34_36,
    ["Terracotta"] = id.Sprite.AIF_POP_EXP_CARGO_ICONS_34X34_37,
    ["Azure"] = id.Sprite.AIF_POP_EXP_CARGO_ICONS_34X34_38
}
local normal = Vector4.new(0.96, 0.88, 0.72, 1)
local countColour = Vector4.new(1, 1, 1, 1)
local titleColour = Vector4.new(0.95, 0.78, 0.43, 1)
local goalColour = Vector4.new(0.40, 0.85, 0.48, 1)
local selectedOutline = Vector4.new(0.82, 0.61, 0.25, 1)
local selected, shownGeneration

local function outlineEdge(owner, x, y, width, height)
    local edge = ui.Rectangle.new(owner)
    edge:SetPos(x, y)
    edge:SetSize(width, height)
    edge.fill = true
    edge.colour = selectedOutline
    edge.clickthrough = true
end

local function text(owner, value, x, y, width, height, colour, right)
    local label = ui.Text.new(owner)
    label:SetPos(x, y)
    label:SetSize(width, height)
    label.content = value
    label.font = id.Font.MUSEO_SANS_15PT_REGULAR
    label.colour = colour or normal
    label.maxLines = 1
    label.clickthrough = true
    if right then label.alignHorizontal = ui.AlignMode.BOTTOMRIGHT end
    return label
end

local function formatCount(value)
    local digits = string.format("%.0f", value)
    return digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Read all sixteen together so a missing client value cannot shift labels.
local function readVars()
    -- Wait for the player's Ports save instead of treating login defaults as
    -- real zero stock. These variables remain readable with the panel closed.
    if var.VarPlayer.POP_OWNED.value ~= 1 then return nil end
    local values = {}
    for _, section in ipairs(groups) do
        if section.varPrefix then
            for index = 1, #section.names do
                local config = var.VarPlayer[section.varPrefix .. index]
                local amount = config and config.value
                if type(amount) ~= "number" or amount < 0 or amount % 1 ~= 0 then
                    return nil
                end
                values[#values + 1] = amount
            end
        end
    end
    return values
end

-- establish stock before it can count increases as gains
-- Ship returns appear as gains when the game updates these variables.
function ports.poll()
    if not state.isReady() then return end
    local amounts = readVars()
    if not amounts then return end
    local named = {}
    local index = 1
    for _, section in ipairs(groups) do
        if section.varPrefix then
            for _, name in ipairs(section.names) do
                named[name] = amounts[index]
                index = index + 1
            end
        end
    end
    state.observePorts(named)
end

function ports.clearSelection()
    selected = nil
end

function ports.draw(view, group, settings, attachNameTip, editContext, revealSelected)
    local generation = state.getGeneration()
    if shownGeneration ~= generation then
        ports.clearSelection()
        shownGeneration = generation
    end
    if group ~= "resources" and group ~= "trade" and group ~= "ships" then
        group = "all"
    end
    local showIcons = settings.showIcons ~= false
    local showGoals = settings.showGoals ~= false
    local queue, redraw = editContext.queue, editContext.redraw
    local items = state.getItems()
    local stock = state.getPorts()
    local visible = {}
    for _, section in ipairs(groups) do
        if group == "all" or group == section.id then
            visible[#visible + 1] = section
        end
    end
    local ownedHeight = itemEditor.ownedHeight
    local height = 4 + #visible * 18
    local selectedVisible = false
    for _, section in ipairs(visible) do
        for _, name in ipairs(section.names) do
            local item = section.id == "ships"
                and items[catalog.makeKey("ports", name)] or stock[name]
            height = height + (showGoals and item and item.goal and 39 or 23)
            if name == selected then
                selectedVisible = true
                height = height + itemEditor.height
                    + (section.id == "ships" and 0 or ownedHeight)
            end
        end
    end
    if not selectedVisible then ports.clearSelection() end
    local scroll = view.scrollY
    view.content:DeleteAll()
    view:SetContentHeight(height)
    local width = view.contentWidth - 4
    local y = 2
    local selectedBottom
    for _, section in ipairs(visible) do
        -- Match the Artefacts section heading used by the other tracker tabs.
        local header = ui.Rectangle.new(view.content)
        header:SetPos(2, y)
        header:SetSize(width, 17)
        header.fill = true
        header.colour = Vector4.new(0, 0, 0, 0.35)
        header.clickthrough = true
        local border = ui.Rectangle.new(view.content)
        border:SetPos(2, y + 16)
        border:SetSize(width, 1)
        border.fill = true
        border.colour = Vector4.new(0.72, 0.48, 0.18, 1)
        border.clickthrough = true
        local heading = text(view.content, section.title, 6, y, width - 10, 16, titleColour)
        heading.font = id.Font.CINZEL_13PT_BOLD
        y = y + 18
        for index, name in ipairs(section.names) do
            local shipReward = section.id == "ships"
            local itemKey = shipReward and catalog.makeKey("ports", name)
            local item = shipReward and items[itemKey] or stock[name]
            local hasGoal = showGoals and item and item.goal
            local baseHeight = hasGoal and 39 or 23
            local expanded = selected == name
            local row = ui.Layer.new(view.content, 200 + (index - 1) % 32)
            row:SetPos(2, y)
            row:SetSize(width, baseHeight)
            local background = ui.Rectangle.new(row)
            background:SetSize(width, baseHeight)
            background.fill = true
            background.colour = expanded and Vector4.new(0.10, 0.085, 0.06, 0.7)
                or (index % 2 == 0 and Vector4.new(0, 0, 0, 0.2)
                    or Vector4.new(0, 0, 0, 0.4))
            background.clickthrough = true
            local objectId = shipReward and (item and item.itemId
                or catalog.find(name, "ports").itemId)
            local spriteId = showIcons and (sprites[name]
                or (shipReward and id.Sprite.AIF_POP_ANCHOR_ICON_0))
            local hasIcon = showIcons and (spriteId or objectId)
            local nameX = hasIcon and 23 or 5
            if hasIcon then
                local icon = ui.Sprite.new(row)
                icon:SetPos(2, 2)
                icon:SetSize(18, 18)
                if objectId then
                    icon:SetAssociatedObject(objectId)
                    icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
                else
                    icon.spriteID = spriteId
                end
                icon.clickthrough = true
            end
            local gained = item and formatCount(shipReward and item.count or item.gained)
                or (shipReward and "0" or "-")
            local countWidth = math.max(49,
                utils.CalcTextWidth(id.Font.MUSEO_SANS_15PT_REGULAR, gained) + 2)
            local nameWidth = math.max(1, width - nameX - countWidth - 8)
            text(row, name, nameX, 1, nameWidth, 21)
            attachNameTip(row, name, nameX, nameWidth)
            text(row, gained, width - countWidth - 3, 1,
                countWidth, 21, countColour, true)
            if hasGoal then
                local count = shipReward and item.count or item.gained
                local percent = math.min(100, count / item.goal * 100)
                text(row, string.format("%s / %s (%.0f%%)", gained,
                    formatCount(item.goal), percent), nameX, 20,
                    width - nameX - 5, 14, goalColour)
            end
            local function toggle()
                queue(function()
                    if selected == name then
                        selected = nil
                    else
                        if shipReward then state.ensureShipReward(name) end
                        selected = name
                    end
                    itemEditor.reset()
                    redraw()
                end)
                return true
            end
            row:Subscribe(ui.Hook.ONCLICK, toggle)
            local rowHeight = baseHeight
            if expanded then
                local editor = itemEditor.draw(view.content, y + rowHeight, width,
                    editContext, {
                        goal = item and item.goal,
                        setGoal = function(goal)
                            if shipReward then
                                state.setGoal(itemKey, goal)
                            else
                                state.setPortGoal(name, goal)
                            end
                        end,
                        reset = function()
                            if shipReward then
                                state.setCount(itemKey, 0)
                            else
                                state.resetPort(name)
                            end
                        end,
                        close = ports.clearSelection
                    })
                outlineEdge(editor, 0, 0, 1, itemEditor.height)
                outlineEdge(editor, width - 1, 0, 1, itemEditor.height)
                rowHeight = rowHeight + itemEditor.height
                if shipReward then
                    outlineEdge(editor, 0, itemEditor.height - 1, width, 1)
                else
                    -- The game-owned amount sits below the goal and reset controls.
                    local owned = item and item.owned
                    local cap = section.id == "trade" and 250
                        or (name == "Chimes" and 200000 or 999999)
                    local detailText = "Owned: " .. (owned and formatCount(owned) or "-")
                    if owned == cap then detailText = detailText .. " (MAX)" end
                    local detail = itemEditor.drawOwned(view.content,
                        y + rowHeight, width, detailText, toggle)
                    outlineEdge(detail, 0, 0, 1, ownedHeight)
                    outlineEdge(detail, width - 1, 0, 1, ownedHeight)
                    outlineEdge(detail, 0, ownedHeight - 1, width, 1)
                    rowHeight = rowHeight + ownedHeight
                end
                -- The row is raised above the scroll content, so its outline
                -- must be drawn inside that layer to keep every edge bright.
                outlineEdge(row, 0, 0, width, 1)
                outlineEdge(row, 0, 0, 1, baseHeight)
                outlineEdge(row, width - 1, 0, 1, baseHeight)
                selectedBottom = y + rowHeight
            end
            y = y + rowHeight
        end
    end
    if revealSelected and selectedBottom and selectedBottom > scroll + view.root.height then
        scroll = selectedBottom - view.root.height + 3
    end
    view:SetScrollPosition(scroll)
end

return ports

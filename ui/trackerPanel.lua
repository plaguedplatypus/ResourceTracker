local catalog = require("catalog/resourceCatalog")
local state = require("ui/trackerState")
local session = require("ui/session")

local panel = {}
-- The dock panel owns presentation and click handling. Saved resources and
-- settings remain in trackerState so reloads and settings use one data source.
local categories = catalog.getCategories()
local sorts = { "recent", "name", "count" }
local sortLabels = { recent = "Recent", name = "A-Z", count = "Count" }
local icons = {
    mining = id.Sprite.STATICONS_HIGH_RES_CLEAN_12,
    woodcutting = id.Sprite.STATICONS_HIGH_RES_CLEAN_17,
    fishing = id.Sprite.STATICONS_HIGH_RES_CLEAN_14,
    archaeology = id.Sprite.SKILL_ICON_ARCHAEOLOGY_52PX_0,
    farming = id.Sprite.STATICONS_HIGH_RES2_CLEAN_2,
    invention = id.Sprite.SKILL_ICON_INVENTION_52PX_0,
    divination = id.Sprite.STATICONS_HIGH_RES2_CLEAN_14,
    hunter = id.Sprite.STATICONS_HIGH_RES2_CLEAN_5
}
local colour = {
    normal = Vector4.new(0.96, 0.88, 0.72, 1),
    count = Vector4.new(1, 1, 1, 1),
    goal = Vector4.new(0.40, 0.85, 0.48, 1),
    selectedOutline = Vector4.new(0.82, 0.61, 0.25, 0.95),
    rare = Vector4.new(0.88, 0.42, 0.38, 1),
    uncommon = Vector4.new(0.90, 0.63, 0.23, 1),
    ancient = Vector4.new(0.34, 0.78, 0.77, 1),
    seren = Vector4.new(0.47, 0.90, 0.97, 1)
}
local parent, root, list, selected
local tabOffset, shownCategory = 0, nil
local draft, armed = "", nil
local pending = {}
local tabTips = {}
local editControls = {}
local editTooltipContexts = {}
local iconIds = {}
local shownRevision, shownSettings, shownWidth, shownHeight = -1, "", 0, 0
local shownGeneration = -1
local marquee
local marqueeOverflowWidth = 42

-- PrettyUI click callbacks run in PrettyUI's context. Save from our Logic event.
function panel.queue(action)
    pending[#pending + 1] = action
end

-- Apply queued PrettyUI clicks during Logic, where saved state can be changed.
function panel.flushActions()
    if #pending == 0 then return false end
    local actions = pending
    pending = {}
    for _, action in ipairs(actions) do action() end
    return true
end

-- Long names advance one character at a time while hovered. Keeping this
-- local to one label avoids redrawing the list or animating ordinary rows.
function panel.tick()
    if not marquee then return end
    if not root or root.parent ~= parent then
        marquee = nil
        return
    end
    marquee.elapsed = marquee.elapsed + 0.02
    if marquee.pause > 0 then
        marquee.pause = marquee.pause - 0.02
        return
    end
    if marquee.elapsed < 0.14 then return end
    marquee.elapsed = 0
    marquee.offset = marquee.offset + marquee.direction
    if marquee.offset >= marquee.last then
        marquee.offset, marquee.direction, marquee.pause = marquee.last, -1, 0.7
    elseif marquee.offset <= 1 then
        marquee.offset, marquee.direction, marquee.pause = 1, 1, 0.7
    end
    marquee.label.content = marquee.text:sub(marquee.offset)
end

-- Scroll only labels that overflow the available row width.
local function startMarquee(label, text, width)
    local last = 1
    for offset = 2, #text do
        if utils.CalcTextWidth(id.Font.MUSEO_SANS_15PT_REGULAR, text:sub(offset)) <= width then
            last = offset
            break
        end
    end
    if last > 1 then
        marquee = { label = label, text = text, last = last, offset = 1,
            direction = 1, elapsed = 0, pause = 0.7 }
    end
end

-- Restore the complete name when the pointer leaves its row.
local function stopMarquee(label, text)
    if marquee and marquee.label == label then marquee = nil end
    label.content = text
end

-- Use the same font and alignment for tracker labels.
local function label(owner, value, x, y, width, height, tint, right)
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

-- Keep item names readable after catalog normalization.
local function capitalize(name)
    return name:gsub("^%l", string.upper)
end

-- RuneScape item counts are whole numbers even when stored as Lua numbers.
local function formatCount(value)
    return string.format("%.0f", value)
end

-- Confirm the config object name before using its ID for a chat-only reward.
local function configId(configName, name)
    -- The config may not define every item name seen in chat.
    local ok, obj = pcall(function() return config.Obj[configName] end)
    if ok and obj and catalog.normalize(obj.name) == name then return obj.id end
end

-- Backpack gains provide an object ID. Chat rewards use a catalogued ID
-- or a cached exact-name config lookup.
local function iconId(item)
    if item.itemId then return item.itemId end
    local definition = catalog.find(item.name, item.skill)
    if definition and definition.itemId then return definition.itemId end
    local name = catalog.normalize(item.name)
    if iconIds[name] == nil then
        local configName = item.name:upper():gsub("[^A-Z0-9]+", "_")
        local found = configId(configName, name)
        if not found then
            -- Salvage configs put the type first and the size last. Their IDs
            -- are scattered, so use the config name rather than an ID range.
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

-- Item controls accept only whole, non-negative game quantities.
local function amountFrom(field, allowZero)
    local amount = tonumber(field:GetText())
    if amount and amount % 1 == 0 and amount >= (allowZero and 0 or 1) then
        return amount
    end
end

-- Editor controls and tooltip contexts belong to a specific rendered row.
local function clearEditor()
    for _, editor in ipairs(editTooltipContexts) do
        prettyui.Tooltip.unregisterContext(editor)
    end
    editTooltipContexts = {}
    for _, control in ipairs(editControls) do control:Destroy() end
    editControls = {}
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

-- Turn catalog group IDs into readable picker labels.
local function groupLabel(group)
    if group == "all" then return "All groups" end
    return (group:gsub("(%l)(%u)", "%1 %2"):gsub("^%l", string.upper))
end

-- A sole visible skill becomes the selected tab, with no redundant All tab.
local function selection(settings)
    local hidden = settings.hiddenSkills or {}
    local onlySkill
    local multiple = false
    for _, entry in ipairs(categories) do
        if entry.id ~= "all" and not hidden[entry.id] then
            if onlySkill then multiple = true; break end
            onlySkill = entry.id
        end
    end
    -- With one visible skill, All would show the same resources. Show that
    -- skill as the active tab without changing the player's saved selection.
    local category = not multiple and onlySkill or (settings.category or "all")
    if hidden[category] then category = "all" end
    local group = settings.group or "all"
    if category ~= (settings.category or "all") or category == "divination" then
        group = "all"
    end
    return category, group, not multiple and onlySkill ~= nil
end

-- Apply player visibility, skill, and group choices before sorting rows.
local function itemsFor(settings)
    local items = {}
    local hidden = settings.hiddenSkills or {}
    local category, group = selection(settings)
    for itemKey, item in pairs(state.getItems()) do
        local definition = catalog.find(item.name, item.skill)
        if not hidden[item.skill] and (category == "all" or item.skill == category)
            and (group == "all" or (definition and definition.groups[group])) then
            items[#items + 1] = {
                itemKey = itemKey,
                item = item,
                artefact = definition and definition.artefact == true
            }
        end
    end
    -- Preserve a predictable row order when counts or names tie.
    table.sort(items, function(a, b)
        if category == "archaeology" and a.artefact ~= b.artefact then
            return not a.artefact
        end
        if settings.sort == "count" then
            local aCount, bCount = a.item.count, b.item.count
            if aCount ~= bCount then return aCount > bCount end
        elseif settings.sort ~= "name" and a.item.order ~= b.item.order then
            return a.item.order > b.item.order
        end
        return a.item.name:lower() < b.item.name:lower()
    end)
    return items
end

-- A compact comparison determines whether the panel needs a full rebuild.
local function signature(settings)
    local parts = { settings.category or "all", settings.group or "all",
        settings.sort or "recent", tostring(settings.showIcons ~= false),
        tostring(settings.showGoals ~= false) }
    for _, category in ipairs(categories) do
        parts[#parts + 1] = tostring((settings.hiddenSkills or {})[category.id] == true)
    end
    return table.concat(parts, "\0")
end

local drawRows

-- Reserve the same vertical space for every expanded resource editor.
local function editorHeight()
    return 47
end

-- The editor is rendered inside the selected row rather than opening a
-- separate window, so it remains close to the resource being changed.
local function drawEditor(owner, itemKey, item, y, width)
    local height = editorHeight()
    local editor = ui.Layer.new(owner)
    editor:SetPos(2, y)
    editor:SetSize(width, height)
    local background = ui.Rectangle.new(editor)
    background:SetSize(width, height)
    background.fill = true
    background.colour = Vector4.new(0.10, 0.085, 0.06, 0.7)
    background.clickthrough = true

    -- List children are clipped by the dock. Put editor tooltips in the game
    -- area instead. xyGlobal does not include a scroll view's current offset,
    -- so calculate from the list viewport and subtract its scroll position.
    local tooltipParent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) or root
    -- Convert editor-local positions to game-area coordinates after scrolling.
    prettyui.Tooltip.registerContext(editor, tooltipParent, function(target)
        local listPos = list.root.xyGlobal
        local parentPos = tooltipParent.xyGlobal
        return listPos.x + (editor.x or 0) + (target.x or 0) - parentPos.x,
            listPos.y + (editor.y or 0) + (target.y or 0) - list.scrollY - parentPos.y
    end)
    editTooltipContexts[#editTooltipContexts + 1] = editor

    -- Place editor control tips through the registered game-area context.
    local function attachTip(button, text)
        prettyui.Tooltip.attach(button, editor, { text = text, placement = "right" })
    end

    local innerWidth = width - 8
    local field = prettyui.TextField.new(editor, {
        x = 4, y = 3, width = innerWidth, height = 21,
        text = draft, placeholder = "Count or goal",
        filterMode = ui.InputFieldFilterMode.NUMBERS_AS_TEXT, maxLength = 12,
        -- Keep unfinished input local until a count or goal action is chosen.
        onChange = function(_, _, value) draft = value end
    })
    editControls[#editControls + 1] = field

    -- Create a PrettyUI action icon and attach its editor tooltip.
    local function addIcon(sprite, tip, action, x, disabled)
        local button = prettyui.SpriteButton.new(editor, sprite, action, {
            x = x, y = 27, size = 16, disabled = disabled
        })
        editControls[#editControls + 1] = button
        attachTip(button.root, tip)
        return button
    end

    -- Use plugin images for actions without a suitable built-in sprite.
    local function addImageIcon(resource, tip, action, x, disabled, highlighted)
        local button = ui.Layer.new(editor)
        button:SetPos(x, 27)
        button:SetSize(16, 16)
        button.clickthrough = disabled == true
        local image = Plugin.resources and
            (Plugin.resources[resource] or Plugin.resources[resource .. ".png"])
        if image and not image.loaded then image:Load() end
        if image and image.loaded then
            local icon = ui.Sprite.new(button)
            icon:SetSize(16, 16)
            icon.sprite = image
            if highlighted then icon.colour = Vector4.new(1, 0.18, 0.12, 1) end
            icon.clickthrough = true
        else
            label(button, "?", 0, 0, 16, 16)
        end
        if not disabled then
            -- Match PrettyUI button behavior for the plugin image control.
            button:Subscribe(ui.Hook.ONCLICK, function()
                action()
                return true
            end)
        end
        editControls[#editControls + 1] = button
        attachTip(button, tip)
        return button
    end

    -- Validate the entered amount before queueing a saved-state change.
    local function change(method, allowZero)
        local amount = amountFrom(field, allowZero)
        if not amount then return end
        -- Apply the validated edit after PrettyUI has finished its callback.
        panel.queue(function()
            state[method](itemKey, amount)
            draft, armed = "", nil
        end)
    end

    -- Manual count corrections do not add to the gathering session.
    addIcon("PENCIL", "Set count from the entered number", function()
        change("setCount", true)
    end, 4)
    -- A goal is display-only and leaves the gathered count intact.
    addIcon("STAR", "Set goal from the entered number", function()
        change("setGoal", false)
    end, 24)
    -- Clear the goal without removing the tracked resource.
    addImageIcon("clear_goal", "Clear goal", function()
        -- Defer the saved goal edit until Logic.
        panel.queue(function() state.setGoal(itemKey, nil); armed = nil end)
    end, 44, item.goal == nil)

    -- Reset and remove arm on the first click and apply on the second.
    -- Selecting another row clears the armed action.
    addImageIcon("reset_count", "Reset count (click twice)", function()
        if armed == "reset" then
            -- The confirmed reset changes only this resource's current count.
            panel.queue(function()
                state.setCount(itemKey, 0)
                selected, draft, armed = nil, "", nil
            end)
        else
            -- First click arms the reset and redraws its highlighted control.
            panel.queue(function()
                armed = "reset"
                drawRows(state.getSettings(), true)
            end)
        end
    end, width - 40, false, armed == "reset")
    -- Removing a row requires the same two-click confirmation as reset.
    addImageIcon("delete_item", "Remove resource (click twice)", function()
        if armed == "remove" then
            -- The confirmed action removes the row from saved tracker state.
            panel.queue(function()
                state.remove(itemKey)
                selected, draft, armed = nil, "", nil
            end)
        else
            -- First click arms removal without changing saved data.
            panel.queue(function()
                armed = "remove"
                drawRows(state.getSettings(), true)
            end)
        end
    end, width - 20, false, armed == "remove")
end

-- Keep PrettyUI's scroll view alive. Recreating it during a server update
-- can collide with its nested dynamic layers before the client releases
-- the old viewport. Delete only the resource rows instead.
drawRows = function(settings, revealSelected)
    if not root or root.parent ~= parent or not list or not list.root then
        return false
    end
    marquee = nil
    clearEditor()
    local scroll = list.scrollY
    local height = list.root.height
    list.content:DeleteAll()
    local entries = itemsFor(settings)
    local showArtefactSection = selection(settings) == "archaeology"
    local hasArtefacts = false
    for _, entry in ipairs(entries) do
        if entry.artefact then
            hasArtefacts = true
            break
        end
    end
    local contentHeight = 4
    local artefactHeaderAdded = false
    for _, entry in ipairs(entries) do
        if showArtefactSection and entry.artefact and not artefactHeaderAdded then
            contentHeight = contentHeight + 18
            artefactHeaderAdded = true
        end
        contentHeight = contentHeight +
            ((settings.showGoals ~= false and entry.item.goal) and 35 or 23)
        if selected == entry.itemKey then contentHeight = contentHeight + editorHeight() end
    end
    list:SetContentHeight(contentHeight)
    local rowWidth, rowY = list.contentWidth - 4, 2
    if #entries == 0 then
        label(list.content, state.isReady() and "No resources gathered yet."
            or "Waiting for account data...", 6, 6, rowWidth - 8, 20)
    end
    local selectedBottom
    artefactHeaderAdded = false
    for index, entry in ipairs(entries) do
        if showArtefactSection and hasArtefacts and entry.artefact and not artefactHeaderAdded then
            local header = ui.Rectangle.new(list.content)
            header:SetPos(2, rowY)
            header:SetSize(rowWidth, 17)
            header.fill = true
            header.colour = Vector4.new(0, 0, 0, 0.35)
            header.clickthrough = true
            local border = ui.Rectangle.new(list.content)
            border:SetPos(2, rowY + 16)
            border:SetSize(rowWidth, 1)
            border.fill = true
            border.colour = Vector4.new(0.72, 0.48, 0.18, 1)
            border.clickthrough = true
            local title = label(list.content, "ARTEFACTS", 6, rowY, rowWidth - 10, 16,
                Vector4.new(0.95, 0.78, 0.43, 1))
            title.font = id.Font.CINZEL_13PT_BOLD
            rowY = rowY + 18
            artefactHeaderAdded = true
        end
        local itemKey, item = entry.itemKey, entry.item
        local count = item.count
        local hasGoal = settings.showGoals ~= false and item.goal ~= nil
        local rowHeight = hasGoal and 35 or 23
        local row = ui.Layer.new(list.content)
        row:SetPos(2, rowY)
        row:SetSize(rowWidth, rowHeight)
        local background = ui.Rectangle.new(row)
        background:SetSize(rowWidth, rowHeight)
        background.fill = true
        background.colour = selected == itemKey and Vector4.new(0.10, 0.085, 0.06, 0.7)
            or (index % 2 == 0 and Vector4.new(0, 0, 0, 0.2)
                or Vector4.new(0, 0, 0, 0.4))
        background.clickthrough = true
        local iconWidth = settings.showIcons == false and 2 or 20
        if settings.showIcons ~= false then
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
                local skillIcon = icons[item.skill]
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
        local countText = formatCount(count)
        local countWidth = math.max(49,
            utils.CalcTextWidth(id.Font.MUSEO_SANS_15PT_REGULAR, countText) + 2)
        local name = capitalize(item.name)
        local nameWidth = math.max(1, rowWidth - iconWidth - countWidth - 8)
        local nameLabel = label(row, name, iconWidth + 3, 1, nameWidth, 21,
            nameColour(item))
        local namePixels = utils.CalcTextWidth(id.Font.MUSEO_SANS_15PT_REGULAR, name)
        if namePixels > nameWidth + marqueeOverflowWidth then
            -- Start scrolling an overflowing name only while its row is hovered.
            row:Subscribe(ui.Hook.ONMOUSEOVER, function()
                startMarquee(nameLabel, name, nameWidth)
                return true
            end)
            -- Restore the full name as soon as the pointer leaves.
            row:Subscribe(ui.Hook.ONMOUSELEAVE, function()
                stopMarquee(nameLabel, name)
                return true
            end)
        end
        label(row, countText, rowWidth - countWidth - 3, 1,
            countWidth, 21, colour.count, true)
        if hasGoal then
            local percent = math.min(100, count / item.goal * 100)
            label(row, string.format("%s / %s (%.0f%%)", formatCount(count),
                formatCount(item.goal), percent),
                iconWidth + 3, 20, rowWidth - iconWidth - 8, 14, colour.goal)
        end
        -- Select or collapse the resource's inline count and goal editor.
        row:Subscribe(ui.Hook.ONCLICK, function()
            -- Redraw the rows after the selection state changes.
            panel.queue(function()
                if selected == itemKey then
                    selected = nil
                else
                    selected = itemKey
                end
                draft, armed = "", nil
                if list then drawRows(state.getSettings(), true) end
            end)
            return true
        end)
        if selected == itemKey then
            drawEditor(list.content, itemKey, item, rowY + rowHeight, rowWidth)
            rowHeight = rowHeight + editorHeight()
            -- The editor is a sibling beneath the row, so draw its selection
            -- outline last around both regions to keep the active item clear.
            local outline = ui.Rectangle.new(list.content)
            outline:SetPos(2, rowY)
            outline:SetSize(rowWidth, rowHeight)
            outline.fill = false
            outline.outlineThickness = 1
            outline.colour = colour.selectedOutline
            outline.clickthrough = true
            selectedBottom = rowY + rowHeight
        end
        rowY = rowY + rowHeight
    end
    if revealSelected and selectedBottom and selectedBottom > scroll + height then
        scroll = selectedBottom - height + 3
    end
    list:SetScrollPosition(scroll)
end

-- Opening or closing the ribbon can replace the Plugin Hub content layer
-- before the next Logic refresh. Those components were already destroyed
-- by the client, so do not try to rebuild rows inside their old parent.
local function forgetUi()
    if root then prettyui.Tooltip.unregisterContext(root) end
    selected, draft, armed, marquee = nil, "", nil, nil
    tabTips, editControls, editTooltipContexts = {}, {}, {}
    list, root = nil, nil
end

-- PrettyUI views own their children. Destroy the view before its root layer.
local function destroyUi()
    if list and not list.root then
        forgetUi()
        return
    end
    marquee = nil
    clearEditor()
    for _, tip in ipairs(tabTips) do tip:Destroy() end
    tabTips = {}
    if root then prettyui.Tooltip.unregisterContext(root) end
    if list then list:Destroy(); list = nil end
    if root then root:Destroy(); root = nil end
end

-- Rebuild when the dock changes size or a display-setting change affects
-- layout. Ordinary count changes redraw only the rows in panel.refresh.
local function build()
    if not parent or not ui.Interfaces:GetInterface(parent.interfaceID) then return end
    destroyUi()
    local width, height = parent.width, parent.height
    root = ui.Layer.new(parent)
    root:SetSize(width, height)
    -- Brother Where Art Thou uses this top layer for tips outside its dock.
    -- Map each tab's position into that layer so PrettyUI can choose whichever
    -- side has room while keeping the hovered icon visible.
    local tooltipParent = ui.Interfaces:GetComponent(
        id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) or root
    -- Tab tips use top-layer coordinates so they can extend past the dock.
    prettyui.Tooltip.registerContext(root, tooltipParent, function(target)
        local rootPos = root.xyGlobal
        local parentPos = tooltipParent.xyGlobal
        return rootPos.x + (target.x or 0) - parentPos.x,
            rootPos.y + (target.y or 0) - parentPos.y
    end)
    local settings = state.getSettings()
    local hidden = settings.hiddenSkills or {}
    local current, activeGroup, singleSkill = selection(settings)
    local visible = {}
    for _, entry in ipairs(categories) do
        if (entry.id == "all" and not singleSkill)
            or (entry.id ~= "all" and not hidden[entry.id]) then
            visible[#visible + 1] = entry
        end
    end
    local tabWidth, tabHeight = 28, 29
    -- Reserve one fixed tab for the separate session window. Skill tabs still
    -- scroll, but the report button stays reachable at every panel width.
    local slots = math.max(1, math.floor((width - 60) / tabWidth))
    local maxOffset = math.max(0, #visible - slots)
    tabOffset = math.min(tabOffset, maxOffset)
    -- Keep the chosen skill in view when the category or panel width changes.
    if current ~= shownCategory or width ~= shownWidth then
        for index, entry in ipairs(visible) do
            if entry.id == current then
                tabOffset = math.min(math.max(tabOffset, index - slots), index - 1)
                break
            end
        end
    end
    shownCategory = current
    -- Show tab paging arrows only when enabled skills exceed the dock width.
    local function addArrow(name, x, step)
        local button = ui.Layer.new(root)
        button:SetPos(x, 3)
        button:SetSize(14, tabHeight)
        local image = Plugin.resources and
            (Plugin.resources[name] or Plugin.resources[name .. ".png"])
        if image and not image.loaded then image:Load() end
        if image and image.loaded then
            local arrow = ui.Sprite.new(button)
            arrow:SetPos(1, 4)
            arrow:SetSize(12, 20)
            arrow.sprite = image
            arrow.clickthrough = true
        else
            -- Use text while an optional arrow image has not loaded yet.
            local arrow = label(button, step < 0 and "<" or ">", 0, 0, 14, tabHeight)
            arrow.alignHorizontal = ui.AlignMode.CENTRE
            arrow.alignVertical = ui.AlignMode.CENTRE
        end
        -- Page the skill strip within the current visible-tab bounds.
        button:Subscribe(ui.Hook.ONCLICK, function()
            if (step < 0 and tabOffset > 0) or (step > 0 and tabOffset < maxOffset) then
                -- Rebuild tab positions after a page step.
                panel.queue(function() tabOffset = tabOffset + step; build() end)
            end
            return true
        end)
    end
    -- Only show an arrow when tabs are available beyond that edge.
    if tabOffset > 0 then addArrow("left", 1, -1) end
    if tabOffset < maxOffset then addArrow("right", width - 15, 1) end
    local sessionTab = ui.Layer.new(root)
    sessionTab:SetPos(16, 3)
    sessionTab:SetSize(tabWidth, tabHeight)
    local sessionBackground = ui.Sprite.new(sessionTab)
    sessionBackground:SetSize(tabWidth, tabHeight)
    sessionBackground.spriteID = prettyui.Sprites.ICON_TAB.inactive
    sessionBackground.clickthrough = true
    -- Show the session tab's hover sprite without hiding its icon.
    sessionTab:Subscribe(ui.Hook.ONMOUSEOVER, function()
        sessionBackground.spriteID = prettyui.Sprites.ICON_TAB.hovered
        return true
    end)
    -- Restore the idle sprite when the pointer leaves the session tab.
    sessionTab:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        sessionBackground.spriteID = prettyui.Sprites.ICON_TAB.inactive
        return true
    end)
    -- Open the separate report window from the dock tab.
    sessionTab:Subscribe(ui.Hook.ONCLICK, function()
        -- Create or show the report during Logic.
        panel.queue(function() session.open(panel.queue) end)
        return true
    end)
    tabTips[#tabTips + 1] = prettyui.Tooltip.attach(sessionTab, root,
        "Session and daily history")
    local sessionIcon = ui.Sprite.new(sessionTab)
    sessionIcon:SetPos(2, 2)
    sessionIcon:SetSize(24, 24)
    sessionIcon.spriteID = id.Sprite.STONEMENUSIDEICONS_15
    sessionIcon.clickthrough = true
    for index = tabOffset + 1, math.min(#visible, tabOffset + slots) do
        local entry = visible[index]
        local skill = entry.id
        local x, y = 44 + (index - tabOffset - 1) * tabWidth, 3
        -- Sprite components cannot own children; the layer holds the tab
        -- background, skill icon, and optional text.
        local tab = ui.Layer.new(root)
        tab:SetPos(x, y)
        tab:SetSize(tabWidth, tabHeight)
        local background = ui.Sprite.new(tab)
        background:SetSize(tabWidth, tabHeight)
        background.clickthrough = true
        local active = current == skill
        background.spriteID = active and prettyui.Sprites.ICON_TAB.active
            or prettyui.Sprites.ICON_TAB.inactive
        -- Keep the active skill highlighted while hovering other tabs.
        tab:Subscribe(ui.Hook.ONMOUSEOVER, function()
            if not active then background.spriteID = prettyui.Sprites.ICON_TAB.hovered end
            return true
        end)
        -- Return inactive tabs to their resting sprite.
        tab:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            background.spriteID = active and prettyui.Sprites.ICON_TAB.active
                or prettyui.Sprites.ICON_TAB.inactive
            return true
        end)
        -- Choosing a skill returns its group picker to All groups.
        tab:Subscribe(ui.Hook.ONCLICK, function()
            -- Save both tab and group choices in one Logic action.
            panel.queue(function()
                state.setSetting("category", skill)
                state.setSetting("group", "all")
            end)
            return true
        end)
        tabTips[#tabTips + 1] = prettyui.Tooltip.attach(tab, root, entry.label)
        if icons[skill] then
            local icon = ui.Sprite.new(tab)
            icon:SetPos(2, 2)
            icon:SetSize(24, 24)
            icon.spriteID = icons[skill]
            icon.clickthrough = true
        elseif skill == "seren" then
            local image = Plugin.resources and
                (Plugin.resources.seren or Plugin.resources["seren.png"])
            if image then
                local icon = ui.Sprite.new(tab)
                icon:SetPos(4, 2)
                icon:SetSize(19, 24)
                icon.sprite = image
                icon.clickthrough = true
            else
                label(tab, "✦", 2, 2, 24, 24)
            end
        else
            local all = label(tab, "ALL", 0, 2, tabWidth, 24)
            all.alignHorizontal = ui.AlignMode.CENTRE
            all.alignVertical = ui.AlignMode.CENTRE
        end
    end
    local controlY = 35
    local sortWidth = 68
    local sort = settings.sort or "recent"
    -- Cycle the order used by the visible resource rows.
    prettyui.SimpleButton.new(root, sortLabels[sort], function()
        -- Persist the next sort mode before the panel rebuilds.
        panel.queue(function()
            for index, name in ipairs(sorts) do
                if name == sort then
                    state.setSetting("sort", sorts[index % #sorts + 1])
                    break
                end
            end
        end)
    end, { x = 4, y = controlY, width = sortWidth, height = 22 })
    local groups = catalog.getGroups(current)
    if #groups > 1 then
        local group = activeGroup
        prettyui.SimpleButton.new(root, groupLabel(group),
            -- Step through the selected skill's catalog groups.
            function()
                -- Save the next group during Logic for a consistent row redraw.
                panel.queue(function()
                    for index, name in ipairs(groups) do
                        if name == group then
                            if settings.category ~= current then
                                state.setSetting("category", current)
                            end
                            state.setSetting("group", groups[index % #groups + 1])
                            break
                        end
                    end
                end)
            end, { x = sortWidth + 8, y = controlY, height = 22,
                width = width - sortWidth - 12 })
    end
    local listY = controlY + 25
    list = prettyui.SimpleView.new(root, { x = 2, y = listY,
        width = width - 4, height = math.max(1, height - listY - 2),
        scrollStep = 24 })
    drawRows(settings)
    shownWidth, shownHeight = width, height
    shownSettings, shownRevision = signature(settings), state.getRevision()
    shownGeneration = state.getGeneration()
end

-- ContentLayerReady can replace the Plugin Hub's whole content interface.
function panel.onReady(event)
    if root and root.parent ~= event.component then forgetUi() end
    parent = event.component
    build()
end

-- Rebuild for layout changes and redraw rows for ordinary count updates.
function panel.refresh()
    if not parent or not ui.Interfaces:GetInterface(parent.interfaceID) then
        forgetUi()
        return
    end
    if not root or root.parent ~= parent or not list or not list.root then
        -- ContentLayerReady will build against the replacement ribbon interface.
        forgetUi()
        return
    end
    -- A new account or game state replaces the full data set and clears selection.
    if shownGeneration ~= state.getGeneration() then
        selected = nil
        build()
        return
    end
    if not root or parent.width ~= shownWidth or parent.height ~= shownHeight then
        build()
        return
    end
    local revision = state.getRevision()
    if revision == shownRevision then return end
    local settings = state.getSettings()
    if signature(settings) ~= shownSettings then
        build()
    else
        drawRows(settings)
        shownRevision = revision
    end
end

-- Release PrettyUI elements and pending actions when the plugin unloads.
function panel.destroy()
    pending = {}
    marquee = nil
    destroyUi()
    parent = nil
end

return panel

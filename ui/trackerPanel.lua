-- Mounts one tracker page in the PrettyUI dock or the native Plugin Hub.
local catalog = require("catalog/resourceCatalog")
local state = require("ui/trackerState")
local session = require("ui/session")
local settingsPanel = require("ui/settingsPanel")
local manageSettings = require("ui/manageSettings")
local ribbonToggle = require("ui/ribbonToggle")
local ports = require("ui/ports")
local itemEditor = require("ui/itemEditor")
local resourceRow = require("ui/resourceRow")
local compactTooltip = require("ui/compactTooltip")

local panel = {}
local categories = catalog.getCategories()
local sorts = { "recent", "name", "count" }
local sortLabels = { recent = "Recent", name = "A-Z", count = "Count" }
local icons = resourceRow.skillIcons
local label, formatCount = resourceRow.label, resourceRow.formatCount
local selectedOutline = Vector4.new(0.82, 0.61, 0.25, 0.95)
local warningColour = Vector4.new(1, 0.76, 0.36, 1)
local rowOptions = { showPin = true }
local dock, dockCategory, dockId
local hubContent, hubPage, hubLauncher, wasUsingHub
local hubPageCategory, hubPageId
local parent, root, list, selected
local classic
local requestedTabOffset, shownCategory = 0, nil
local pending = {}
local tabTips = {}
local tooltipLayer
local nameAnchor, nameTip
local groupMenu, menuCover
local shownRevision, shownSettings, shownWidth, shownHeight = -1, "", 0, 0
local shownGeneration = -1
local shownOwned

-- A game UI rebuild can remove our controls before PrettyUI releases its page.
local function hasUi()
    return parent and root and list and list.root
        and ui.Interfaces:GetInterface(parent.interfaceID)
        and root.parent == parent
        and parent:GetChild(root.categoryID, root.dynamicID) == root
        and root:GetChild(list.root.categoryID, list.root.dynamicID) == list.root
end

-- PrettyUI click callbacks run in PrettyUI's context. Save from our Logic event.
function panel.queue(action)
    pending[#pending + 1] = action
end

-- Apply queued PrettyUI clicks during Logic, where saved state can be changed.
function panel.flushActions()
    -- PrettyUI raises the Classic sidebar each Logic event. Keep the scroll
    -- capture above it so the thumb remains draggable outside the sidebar.
    if classic and tooltipLayer and list and list.scrollbarVisible
        and ui.Interfaces:GetInterface(tooltipLayer.interfaceID) then
        tooltipLayer:MoveToFront()
    end
    if #pending == 0 then return false end
    local actions = pending
    pending = {}
    for _, action in ipairs(actions) do action() end
    return true
end

local function formatOwned(value)
    if value == nil then return "-" end
    local digits = formatCount(value)
    return digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Invention materials are stored as VarPlayers rather than in a container.
-- Third-age components retain their older Ancient config name in the game.
local function readMaterialOwned(name)
    local normalized = catalog.normalize(name)
    local varName = normalized == "third-age components"
        and "INVENT_MATERIAL_ANCIENT_COMPONENTS"
        or "INVENT_MATERIAL_" .. normalized:upper():gsub("[^A-Z0-9]+", "_")
    local config = var.VarPlayer[varName]
    local amount = config and config.value
    if type(amount) == "number" and amount >= 0 and amount % 1 == 0 then
        return amount
    end
end

-- Keep the full name above its clipped label as the list scrolls.
local function positionNameTip(row, nameX, nameWidth)
    if not nameTip or not hasUi() then return end
    local ok, tipX, tipY = pcall(function()
        local viewPos = list.root.xyGlobal
        local overlayPos = tooltipLayer.xyGlobal
        return viewPos.x + row.x + nameX + nameWidth / 2 - overlayPos.x,
            viewPos.y + row.y - list.scrollY - overlayPos.y
    end)
    if not ok then return end
    tipX = math.max(0, math.min(tipX - nameTip.width / 2,
        tooltipLayer.width - nameTip.width))
    nameAnchor:SetPos(tipX, tipY + 3)
    return true
end

-- The skill and Ports lists use the same hover treatment for clipped names.
local function attachNameTip(row, name, nameX, nameWidth)
    if utils.CalcTextWidth(id.Font.MUSEO_SANS_15PT_REGULAR, name) <= nameWidth then
        return
    end
    row:Subscribe(ui.Hook.ONMOUSEOVER, function()
        if nameTip then
            nameTip.options.width, nameTip.options.height = compactTooltip.measure(name)
            nameTip:SetText(name)
            if positionNameTip(row, nameX, nameWidth) then compactTooltip.show(nameTip) end
        end
        return true
    end)
    row:Subscribe(ui.Hook.ONMOUSEREPEAT, function()
        if positionNameTip(row, nameX, nameWidth) then nameTip:Show() end
        return true
    end)
    row:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if nameTip then nameTip:Hide() end
        return true
    end)
end

-- Turn catalog group IDs into readable picker labels.
local function groupLabel(group)
    if group == "all" then return "All groups" end
    if group == "resources" then return "Ports Resources" end
    if group == "trade" then return "Trade Goods" end
    if group == "ships" then return "Ship Rewards" end
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
    local hasVisibleTabs = onlySkill ~= nil
    return category, group, hasVisibleTabs and not multiple, hasVisibleTabs
end

-- Apply player visibility, skill, and group choices before sorting rows.
local function itemsFor(settings)
    local items = {}
    local hidden = settings.hiddenSkills or {}
    local category, group = selection(settings)
    for itemKey, item in pairs(state.getItems()) do
        local definition = catalog.find(item.name, item.skill)
        if resourceRow.isVisible(item, definition, hidden, settings.showArtefacts)
            and (category == "all" or item.skill == category)
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
        if (a.item.pinned == true) ~= (b.item.pinned == true) then
            return a.item.pinned == true
        end
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
        tostring(settings.showGoals ~= false), tostring(settings.showArtefacts ~= false),
        tostring(settings.showGainPlus ~= false) }
    for _, category in ipairs(categories) do
        parts[#parts + 1] = tostring((settings.hiddenSkills or {})[category.id] == true)
    end
    return table.concat(parts, "\0")
end

local drawRows

-- Reserve the same vertical space for every expanded resource editor.
local editorHeight = itemEditor.height

local function outlineEdge(owner, x, y, width, height)
    local edge = ui.Rectangle.new(owner)
    edge:SetPos(x, y)
    edge:SetSize(width, height)
    edge.fill = true
    edge.colour = selectedOutline
    edge.clickthrough = true
end

-- Keep PrettyUI's scroll view alive. Recreating it during a server update
-- can collide with its nested dynamic layers before the client releases
-- the old viewport. Delete only the resource rows instead.
drawRows = function(settings, revealSelected)
    if not hasUi() then
        return false
    end
    itemEditor.clear()
    if nameTip then nameTip:Hide() end
    shownOwned = nil
    local current, activeGroup, _, hasVisibleTabs = selection(settings)
    if not hasVisibleTabs then
        ports.clearSelection()
        list.content:DeleteAll()
        local warningHeight = 54
        list:SetContentHeight(warningHeight + 12)
        local warning = label(list.content, "All tabs are hidden.<br>Enable a tab in Settings.",
            6, 6, math.max(1, list.contentWidth - 12), warningHeight, warningColour)
        warning.maxLines = 0
        list:SetScrollPosition(0)
        return true
    end
    local editContext = {
        root = root, list = list, tooltipLayer = tooltipLayer,
        queue = panel.queue,
        redraw = function() drawRows(state.getSettings(), true) end,
        isCurrent = function(expectedRoot, expectedList)
            return root == expectedRoot and list == expectedList
        end
    }
    if current == "ports" then
        selected = nil
        ports.draw(list, activeGroup, settings, attachNameTip, editContext,
            revealSelected)
        return true
    end
    ports.clearSelection()
    local scroll = list.scrollY
    local height = list.root.height
    list.content:DeleteAll()
    local entries = itemsFor(settings)
    local showArtefactSection = current == "archaeology"
    local contentHeight = 4
    local artefactHeaderAdded = false
    for _, entry in ipairs(entries) do
        if showArtefactSection and entry.artefact and not entry.item.pinned
            and not artefactHeaderAdded then
            contentHeight = contentHeight + 18
            artefactHeaderAdded = true
        end
        contentHeight = contentHeight + resourceRow.getHeight(entry.item, settings)
        if selected == entry.itemKey then
            contentHeight = contentHeight + editorHeight
                + (entry.item.skill == "invention" and itemEditor.ownedHeight or 0)
        end
    end
    list:SetContentHeight(contentHeight)
    local rowWidth, rowY = list.contentWidth - 4, 2
    if #entries == 0 then
        label(list.content, state.isReady() and "No resources to display."
            or "Waiting for account data...", 6, 6, rowWidth - 8, 20)
    end
    local selectedBottom
    artefactHeaderAdded = false
    for index, entry in ipairs(entries) do
        if showArtefactSection and entry.artefact
            and not entry.item.pinned and not artefactHeaderAdded then
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
        local rowHeight = resourceRow.getHeight(item, settings)
        -- Nonzero categories have a small ID range. Spread large saved
        -- lists across categories so row labels cannot exhaust the dock UI.
        local row = ui.Layer.new(list.content, 200 + (index - 1) % 32)
        row:SetPos(2, rowY)
        row:SetSize(rowWidth, rowHeight)
        if selected == itemKey then
            local background = ui.Rectangle.new(row)
            background:SetSize(rowWidth, rowHeight)
            background.fill = true
            background.colour = Vector4.new(0.10, 0.085, 0.06, 0.7)
            background.clickthrough = true
        end
        local name, nameX, nameWidth = resourceRow.draw(row, item, settings, rowWidth, rowOptions)
        attachNameTip(row, name, nameX, nameWidth)
        -- Select or collapse the resource's inline count and goal editor.
        local function toggle()
            -- Redraw the rows after the selection state changes.
            panel.queue(function()
                if selected == itemKey then
                    selected = nil
                else
                    selected = itemKey
                end
                itemEditor.reset()
                if list then drawRows(state.getSettings(), true) end
            end)
            return true
        end
        row:Subscribe(ui.Hook.ONCLICK, toggle)
        if selected == itemKey then
            local editor = itemEditor.draw(list.content, rowY + rowHeight,
                rowWidth, editContext, {
                    goal = item.goal, pinned = item.pinned,
                    setCount = function(amount) state.setCount(itemKey, amount) end,
                    setGoal = function(goal) state.setGoal(itemKey, goal) end,
                    pin = function() state.setPinned(itemKey, not item.pinned) end,
                    reset = function() state.setCount(itemKey, 0) end,
                    remove = function() state.remove(itemKey) end,
                    close = function() selected = nil end
                })
            -- Each edge draws over its own fill; the raised row would cover
            -- the top of an outline attached to the scroll content.
            outlineEdge(row, 0, 0, rowWidth, 1)
            outlineEdge(row, 0, 0, 1, rowHeight)
            outlineEdge(row, rowWidth - 1, 0, 1, rowHeight)
            outlineEdge(editor, 0, 0, 1, editorHeight)
            outlineEdge(editor, rowWidth - 1, 0, 1, editorHeight)
            rowHeight = rowHeight + editorHeight
            if item.skill == "invention" then
                shownOwned = readMaterialOwned(item.name)
                local detail = itemEditor.drawOwned(list.content,
                    rowY + rowHeight, rowWidth,
                    "Owned: " .. formatOwned(shownOwned), toggle)
                outlineEdge(detail, 0, 0, 1, itemEditor.ownedHeight)
                outlineEdge(detail, rowWidth - 1, 0, 1, itemEditor.ownedHeight)
                outlineEdge(detail, 0, itemEditor.ownedHeight - 1, rowWidth, 1)
                rowHeight = rowHeight + itemEditor.ownedHeight
            else
                outlineEdge(editor, 0, editorHeight - 1, rowWidth, 1)
            end
            selectedBottom = rowY + rowHeight
        end
        rowY = rowY + rowHeight
    end
    if revealSelected and selectedBottom and selectedBottom > scroll + height then
        scroll = selectedBottom - height + 3
    end
    list:SetScrollPosition(scroll)
end

-- Clear references when the client has already removed the dock controls.
local function forgetUi()
    if root then prettyui.Tooltip.unregisterContext(root) end
    -- Even after logout removes the viewport, PrettyUI still owns its capture
    -- and scroll registration. Release those before destroying the overlay.
    if list and list.root and not ui.Interfaces:GetInterface(list.root.interfaceID) then
        list:Destroy()
    end
    if nameTip then nameTip:Destroy() end
    nameAnchor, nameTip = nil, nil
    if tooltipLayer and ui.Interfaces:GetInterface(tooltipLayer.interfaceID) then
        tooltipLayer:Destroy()
    end
    tooltipLayer = nil
    selected = nil
    shownOwned = nil
    itemEditor.forget()
    tabTips = {}
    groupMenu, menuCover = nil, nil
    list, root = nil, nil
end

-- Remove the picker before its dock layer is rebuilt or destroyed.
local function closeGroupMenu()
    if groupMenu then groupMenu:Destroy(); groupMenu = nil end
    if menuCover then menuCover:Destroy(); menuCover = nil end
end

-- PrettyUI views own their children. Destroy the view before its root layer.
local function destroyUi()
    if list and not list.root then
        forgetUi()
        return
    end
    closeGroupMenu()
    itemEditor.clear()
    for _, tip in ipairs(tabTips) do tip:Destroy() end
    tabTips = {}
    if root then prettyui.Tooltip.unregisterContext(root) end
    if list then list:Destroy(); list = nil end
    if nameTip then nameTip:Destroy() end
    nameAnchor, nameTip = nil, nil
    if tooltipLayer then tooltipLayer:Destroy(); tooltipLayer = nil end
    if root then root:Destroy(); root = nil end
end

local function releasePage(pageCleared)
    if not pageCleared and hasUi() then destroyUi() else forgetUi() end
    selected = nil
    ports.clearSelection()
    itemEditor.reset()
    parent, classic = nil, nil
end

-- Create the menu after the resource view so it covers that view's scrollbar.
-- The existing button remains the visible picker; the list supplies scrolling.
local function openGroupMenu(groups, current, activeGroup, x, y, width)
    local panelRoot = root
    local panelWidth, panelHeight = root.width, root.height
    local menuWidth = math.min(panelWidth - 8, math.max(width, 180))
    local menuHeight = math.min(#groups * 22 + 2,
        math.max(46, panelHeight - y - 4))
    local entries = {}
    for index, group in ipairs(groups) do
        entries[index] = {
            label = groupLabel(group), id = index,
            backgroundColour = group == activeGroup and 0x4A3D32FF or nil
        }
    end
    -- Catch outside clicks without letting the covered tracker rows act on them.
    menuCover = ui.Layer.new(root)
    menuCover:SetSize(panelWidth, panelHeight)
    local outside = ui.Rectangle.new(menuCover)
    outside:SetSize(panelWidth, panelHeight)
    outside.fill = true
    outside.colour = Vector4.new(0, 0, 0, 0.001)
    outside:Subscribe(ui.Hook.ONCLICK, function()
        panel.queue(function()
            if root == panelRoot then closeGroupMenu() end
        end)
        return false
    end)
    groupMenu = prettyui.List.new(menuCover, {
        categoryID = "auto",
        x = math.min(x, panelWidth - menuWidth - 4), y = y,
        width = menuWidth, height = menuHeight, entryHeight = 22,
        entries = entries,
        onChange = function(_, index, selectedEntry)
            if not selectedEntry then return end
            panel.queue(function()
                if root ~= panelRoot then return end
                closeGroupMenu()
                if state.getSettings().category ~= current then
                    state.setSetting("category", current)
                end
                state.setSetting("group", groups[index])
            end)
        end
    })
    menuCover:MoveToFront()
end

-- Rebuild when the dock changes size or a display-setting change affects layout.
-- Ordinary count changes redraw only the rows in panel.refresh.
local function build()
    if not parent or not ui.Interfaces:GetInterface(parent.interfaceID) then return end
    local width, height = parent.width, parent.height
    if width <= 4 or height <= 0 then return end
    destroyUi()
    -- PrettyUI's scroll views and popup list need a category-zero mount.
    root = ui.Layer.new(parent)
    root:SetSize(width, height)
    -- Tips can extend beyond the dock, and the scrollbar needs a capture
    -- layer that spans the screen when it is dragged in Classic layout.
    local tooltipParent = ui.Interfaces:GetComponent(
        id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) or root
    tooltipLayer = ui.Layer.new(tooltipParent)
    tooltipLayer:SetSize(0, 0, 1, 1)
    tooltipLayer.clickthrough = true
    tooltipParent = tooltipLayer
    local contextRoot = root
    -- Tab tips use top-layer coordinates so they can extend past the dock.
    prettyui.Tooltip.registerContext(root, tooltipParent, function(target)
        -- A pending PrettyUI callback may outlive this particular dock layer.
        if root ~= contextRoot then return 0, 0 end
        local ok, x, y = pcall(function()
            local rootPos = contextRoot.xyGlobal
            local parentPos = tooltipParent.xyGlobal
            return rootPos.x + (target.x or 0) - parentPos.x,
                rootPos.y + (target.y or 0) - parentPos.y
        end)
        if ok then
            -- Centre each tip over its tab, then shift it at the screen edge.
            for _, tip in ipairs(tabTips) do
                if tip.target == target then
                    x = x + (target.width - tip.width) / 2
                    x = math.max(0, math.min(x, tooltipParent.width - tip.width))
                    y = y + 3
                    break
                end
            end
            return x, y
        end
        return 0, 0
    end, prettyui.Tooltip.getContext(parent))
    local settings = state.getSettings()
    local hidden = settings.hiddenSkills or {}
    local current, activeGroup, singleSkill, hasVisibleTabs = selection(settings)
    local visible = {}
    if hasVisibleTabs then
        for _, entry in ipairs(categories) do
            if (entry.id == "all" and not singleSkill)
                or (entry.id ~= "all" and not hidden[entry.id]) then
                visible[#visible + 1] = entry
            end
        end
    else
        visible[1] = { id = "easterEgg" }
    end
    local tabWidth, tabHeight = 28, 29
    local inset = classic and 3 or 0
    local tabY = 3 + inset
    -- Continue the tabs' lower edge across unused space in a wide dock.
    local tabEdge = ui.Rectangle.new(root)
    tabEdge:SetPos(0, tabY + tabHeight)
    tabEdge:SetSize(width, 1)
    tabEdge.fill = true
    tabEdge.colour = Vector4.new(0.49, 0.39, 0.22, 1)
    tabEdge.clickthrough = true
    -- The Hub has its own bottom-right Settings button.
    local showSettingsTab = parent ~= hubPage
    local tabLeft, tabRight = (showSettingsTab and 72 or 44) + inset, width - 15
    -- Keep one pixel clear of the right arrow while fitting as many tabs as possible.
    local slots = math.max(1, math.floor((tabRight - tabLeft - 1) / tabWidth))
    local maxOffset = math.max(0, #visible - slots)
    -- A wider panel can show earlier tabs without losing the player's scroll position.
    local tabOffset = math.min(requestedTabOffset, maxOffset)
    -- Bring a newly selected skill into view. Resizing keeps the current scroll position.
    if current ~= shownCategory then
        for index, entry in ipairs(visible) do
            if entry.id == current then
                tabOffset = math.min(math.max(tabOffset, index - slots), index - 1)
                requestedTabOffset = tabOffset
                break
            end
        end
    end
    shownCategory = current
    -- Show tab paging arrows only when enabled skills exceed the dock width.
    local function addArrow(name, x, step)
        local button = ui.Layer.new(root)
        button:SetPos(x, tabY)
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
                panel.queue(function()
                    if root ~= contextRoot or not hasUi() then return end
                    requestedTabOffset = tabOffset + step
                    build()
                end)
            end
            return true
        end)
    end
    -- Only show an arrow when tabs are available beyond that edge.
    if tabOffset > 0 then addArrow("left", tabLeft - 14, -1) end
    if tabOffset < maxOffset then addArrow("right", tabRight, 1) end
    local function addWindowTab(x, sprite, tooltip, open)
        local tab = ui.Layer.new(root)
        tab:SetPos(x, tabY)
        tab:SetSize(tabWidth, tabHeight)
        local background = ui.Sprite.new(tab)
        background:SetSize(tabWidth, tabHeight)
        background.spriteID = prettyui.Sprites.ICON_TAB.inactive
        background.clickthrough = true
        tab:Subscribe(ui.Hook.ONMOUSEOVER, function()
            background.spriteID = prettyui.Sprites.ICON_TAB.hovered
            return true
        end)
        tab:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            background.spriteID = prettyui.Sprites.ICON_TAB.inactive
            return true
        end)
        tab:Subscribe(ui.Hook.ONCLICK, function()
            panel.queue(function()
                -- PrettyUI may release the page before this click reaches Logic.
                if root == contextRoot and hasUi() then open(panel.queue) end
            end)
            return true
        end)
        tabTips[#tabTips + 1] = compactTooltip.attach(tab, root, tooltip)
        local icon = ui.Sprite.new(tab)
        icon:SetPos(2, 2)
        icon:SetSize(24, 24)
        icon.spriteID = sprite
        icon.clickthrough = true
    end
    addWindowTab(1 + inset, id.Sprite.STONEMENUSIDEICONS_15, "Session and Daily History", session.open)
    if showSettingsTab then
        addWindowTab(29 + inset, id.Sprite.RS3_ICON_GROUPING_SYSTEM_RANK_1, "Open Settings", settingsPanel.open)
    end
    -- Keep the arrow gap in wide docks; centre the tabs only when paging.
    local tabStart = tabLeft
    if maxOffset > 0 then
        tabStart = tabLeft + math.floor((tabRight - tabLeft - slots * tabWidth) / 2)
    end
    for index = tabOffset + 1, math.min(#visible, tabOffset + slots) do
        local entry = visible[index]
        local skill = entry.id
        local isEasterEgg = skill == "easterEgg"
        local x = tabStart + (index - tabOffset - 1) * tabWidth
        -- Sprite components cannot own children; the layer holds the tab
        -- background, skill icon, and optional text.
        local tab = ui.Layer.new(root)
        tab:SetPos(x, tabY)
        tab:SetSize(tabWidth, tabHeight)
        local background = ui.Sprite.new(tab)
        background:SetSize(tabWidth, tabHeight)
        background.clickthrough = true
        local active = current == skill
        background.spriteID = active and prettyui.Sprites.ICON_TAB.active
            or prettyui.Sprites.ICON_TAB.inactive
        if isEasterEgg then
            tab.clickthrough = true
        else
            -- Keep the active skill highlighted while hovering other tabs.
            tab:Subscribe(ui.Hook.ONMOUSEOVER, function()
                if not active then background.spriteID = prettyui.Sprites.ICON_TAB.hovered end
                return true
            end)
            tab:Subscribe(ui.Hook.ONMOUSELEAVE, function()
                background.spriteID = active and prettyui.Sprites.ICON_TAB.active
                    or prettyui.Sprites.ICON_TAB.inactive
                return true
            end)
            -- Choosing a skill returns its group picker to All groups.
            tab:Subscribe(ui.Hook.ONCLICK, function()
                panel.queue(function()
                    if root ~= contextRoot or not hasUi() then return end
                    state.setSetting("category", skill)
                    state.setSetting("group", "all")
                end)
                return true
            end)
            tabTips[#tabTips + 1] = compactTooltip.attach(tab, root, entry.label)
        end
        local sprite = isEasterEgg and id.Sprite.EASTER24_EGG_HUNT_RIBBON_ICON or icons[skill]
        if sprite then
            local icon = ui.Sprite.new(tab)
            icon:SetPos(1, 1)
            icon:SetSize(25, 27)
            icon.spriteID = sprite
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
        elseif skill == "ports" then
            local icon = label(tab, "P", 2, 2, 24, 24)
            icon.alignHorizontal = ui.AlignMode.CENTRE
            icon.alignVertical = ui.AlignMode.CENTRE
        end
    end
    local controlY = 35 + inset
    local sortWidth = 68
    local sort = settings.sort or "recent"
    if hasVisibleTabs and current ~= "ports" then
        -- Ports follows the game's fixed resource order, so it has no sort button.
        prettyui.SimpleButton.new(root, sortLabels[sort], function()
            panel.queue(function()
                if root ~= contextRoot or not hasUi() then return end
                for index, name in ipairs(sorts) do
                    if name == sort then
                        state.setSetting("sort", sorts[index % #sorts + 1])
                        break
                    end
                end
            end)
        end, { categoryID = "auto", x = 4, y = controlY, width = sortWidth, height = 22 })
    end
    local groups = catalog.getGroups(current)
    if hasVisibleTabs and #groups > 1 then
        local group = activeGroup
        local groupX = current == "ports" and 4 or sortWidth + 8
        local groupWidth = width - groupX - 4
        local panelRoot = root
        prettyui.SimpleButton.new(root, groupLabel(group),
            -- Open the site's menu below this unchanged button appearance.
            function()
                panel.queue(function()
                    if root ~= panelRoot or not hasUi() then return end
                    if groupMenu then
                        closeGroupMenu()
                    else
                        openGroupMenu(groups, current, group, groupX,
                            controlY + 22, groupWidth)
                    end
                end)
            end, { categoryID = "auto", x = groupX, y = controlY, height = 22,
                width = groupWidth })
    end
    local listY = hasVisibleTabs and controlY + 25 or controlY
    list = prettyui.SimpleView.new(root, { categoryID = "auto", x = 2, y = listY,
        width = width - 4, height = math.max(1, height - listY - 2),
        scrollStep = 24 })
    nameAnchor = ui.Layer.new(tooltipLayer)
    nameAnchor:SetSize(0, 0)
    nameAnchor.hidden = true
    nameTip = compactTooltip.attach(nameAnchor, tooltipLayer, "")
    drawRows(settings)
    shownWidth, shownHeight = width, height
    shownSettings, shownRevision = signature(settings), state.getRevision()
    shownGeneration = state.getGeneration()
end

local function releaseDock()
    local oldDock = dock
    dock, dockCategory, dockId = nil, nil, nil
    if oldDock then oldDock:Destroy() end
end

-- PrettyUI keeps dock placement under its stable ID and mounts a fresh
-- content page when the ribbon or a dock group selects this tracker.
local function updateDock()
    local area = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    -- GetInterface can return a fresh Lua handle while the same game area
    -- stays loaded. Keep the panel and its drag while its root is still mounted.
    if dock and (not area or not dock.root or area:GetChild(dockCategory, dockId) ~= dock.root) then
        releaseDock()
    end
    if dock or not area or area.width == 0 or area.height == 0 then return end
    -- Share the same bundled icon with the native Plugin Hub ribbon.
    local resources = Plugin.resources
    local tabIcon = resources and (resources.ribbon or resources["ribbon.png"])
    if tabIcon and not tabIcon.loaded then tabIcon:Load() end
    dock = prettyui.NisPanel.new(area, {
        categoryID = "auto",
        id = "resource-tracker:main",
        tabText = "Resource Tracker",
        tabIcon = tabIcon and tabIcon.loaded and tabIcon or id.Sprite.CHILD_TAB_ICON_NOTES,
        width = 310, height = 400,
        minWidth = 160, minHeight = 130,
        scrollable = false,
        buildContent = function(view)
            parent = view.content
            classic = prettyui.IsClassicUI()
            return releasePage
        end
    })
    dockCategory, dockId = dock.root.categoryID, dock.root.dynamicID
end

-- The Hub clears its shared content when another plugin opens. Our child
-- layer confirms that the active page is still owned by Resource Tracker.
local function hasHubPage()
    return hubPage and ui.Interfaces:GetInterface(hubContent.interfaceID)
        and hubContent:GetChild(hubPageCategory, hubPageId) == hubPage
end

local function hasVisibleHubTracker()
    return hasHubPage() and hubPage.visibleGlobal and parent == hubPage
        and state.getSettings().useNestedPanel ~= true
end

local function releaseHubPage()
    ribbonToggle.restore()
    manageSettings.detach()
    local mounted = hasHubPage()
    if hubPage and parent == hubPage then
        local pageCleared = not mounted
        releasePage(pageCleared)
    end
    if mounted then
        if hubLauncher then hubLauncher:Destroy() end
        hubPage:Destroy()
    end
    hubContent, hubPage, hubLauncher = nil, nil, nil
    hubPageCategory, hubPageId = nil, nil
end

local function updateHost()
    if hubPage and not hasHubPage() then releaseHubPage() end
    if not Player.IsAvailable() then
        releaseDock()
        releaseHubPage()
        wasUsingHub = nil
        return
    end

    local settings = state.getSettings()
    if settings.useNestedPanel ~= true then
        wasUsingHub = true
        releaseDock()
        if hubLauncher then hubLauncher:Destroy(); hubLauncher = nil end
        parent = hubPage
        local visibleTracker = hasVisibleHubTracker()
        if visibleTracker then
            manageSettings.sync(panel.queue, hasVisibleHubTracker, settingsPanel.open)
        else
            manageSettings.detach()
        end
        if visibleTracker and settings.hidePluginHubRibbon == true then
            ribbonToggle.hide(hubContent)
        else
            ribbonToggle.restore()
        end
        return
    end

    ribbonToggle.restore()
    manageSettings.detach()
    if hubPage and parent == hubPage then releasePage() end
    updateDock()
    if dock and wasUsingHub then
        wasUsingHub = nil
        dock:Show()
    end
    if hubPage and hubPage.width > 12 and not hubLauncher then
        -- The manifest's Hub icon is always present, so use it as a launcher
        -- while the tracker is hosted by PrettyUI.
        local page = hubPage
        hubLauncher = prettyui.SimpleButton.new(page, "Open docked tracker", function()
            panel.queue(function()
                if page ~= hubPage or not hasHubPage()
                    or state.getSettings().useNestedPanel ~= true then return end
                if dock then dock:Show() end
            end)
        end, { categoryID = "auto", x = 6, y = 6, width = math.min(page.width - 12, 170), height = 22 })
    end
end

function panel.onHubReady(event)
    releaseHubPage()
    hubContent = event.component
    hubPage = ui.Layer.new(hubContent)
    hubPageCategory, hubPageId = hubPage.categoryID, hubPage.dynamicID
    hubPage:SetSize(0, 0, 1, 1)
    panel.refresh()
end

-- Rebuild for layout changes and redraw rows for ordinary count updates.
function panel.refresh()
    -- A tab can be cleared while this panel is closed; discard its old editor selection.
    if selected and not state.getItems()[selected] then
        selected = nil
        itemEditor.reset()
    end
    updateHost()
    if not parent then return end
    if not hasUi() then
        if root then forgetUi() end
        build()
        return
    end
    -- A new account or game state replaces the full data set and clears selection.
    if shownGeneration ~= state.getGeneration() then
        selected = nil
        build()
        return
    end
    if parent.width ~= shownWidth or parent.height ~= shownHeight then
        build()
        return
    end
    local revision = state.getRevision()
    if revision == shownRevision then
        local item = selected and state.getItems()[selected]
        if item and item.skill == "invention"
            and readMaterialOwned(item.name) ~= shownOwned then
            drawRows(state.getSettings())
        end
        return
    end
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
    releaseDock()
    releaseHubPage()
    wasUsingHub = nil
end

return panel

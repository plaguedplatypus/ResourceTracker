local catalog = require("catalog/resourceCatalog")
local decisions = require("Core/counting")
local persistence = require("Core/persistence")
local state = require("ui/trackerState")

local settingsPanel = {}
-- Keep the settings form in its own window so the ribbon button can open it.
local window, root, view, queue
local headingTips = {}
local isOpen = false
local armedSkill, profileAction, selectedAccount, profileError, needsBuild
local shownGeneration = -1

local titleColour = Vector4.new(0.95, 0.75, 0.38, 1)
local confirmColour = 0xFF6254FF

-- Keep settings section headings consistent with the tracker theme.
local function title(owner, content, x, y, width)
    local value = ui.Text.new(owner)
    value:SetPos(x, y)
    value:SetSize(width, 18)
    value.content = content
    value.font = id.Font.CINZEL_13PT_BOLD
    value.colour = titleColour
    value.alignVertical = ui.AlignMode.CENTRE
    value.maxLines = 1
    value.clickthrough = true
end

local function titleWithInfo(owner, content, x, y, width, help)
    title(owner, content, x, y, width)
    local icon = ui.Sprite.new(owner)
    local iconX = x + utils.CalcTextWidth(id.Font.CINZEL_13PT_BOLD, content) + 7
    icon:SetPos(iconX, y + 1)
    icon:SetSize(14, 14)
    icon.spriteID = id.Sprite.RS3_ICON_INFO
    headingTips[#headingTips + 1] = prettyui.Tooltip.attach(icon, owner, {
        categoryID = "auto", text = help, placement = "above", maxWidth = 280
    })
    return iconX
end

-- Release the hover hooks while their heading sprites are still mounted.
local function destroyHeadingTips()
    for _, tip in ipairs(headingTips) do tip:Destroy() end
    headingTips = {}
end

local function note(owner, content, x, y, width)
    local value = ui.Text.new(owner)
    value:SetPos(x, y)
    value:SetSize(width, 18)
    value.content = content
    value.font = id.Font.MUSEO_SANS_15PT_REGULAR
    value.colour = Vector4.new(0.85, 0.78, 0.67, 1)
    value.alignVertical = ui.AlignMode.CENTRE
    value.maxLines = 1
    value.clickthrough = true
    return value
end

-- Lay out visible skill tabs and display settings in the available panel size.
local function build()
    needsBuild = false
    local generation = state.getGeneration()
    if shownGeneration ~= generation then
        profileAction, selectedAccount, profileError = nil, nil, nil
        shownGeneration = generation
    end
    destroyHeadingTips()
    if view then view:Destroy(); view = nil end
    if root then root:Destroy() end
    local width, height = window.viewport.width, window.viewport.height
    -- Inherit category zero so the nested view can use PrettyUI's allocator.
    root = ui.Layer.new(window.content)
    root:SetSize(width, height)
    local bottomY = height - 85
    view = prettyui.SimpleView.new(root, {
        categoryID = "auto",
        x = 2, y = 2, width = width - 4, height = math.max(1, bottomY - 6)
    })

    local settings = state.getSettings()
    local choices = {}
    local hidden = settings.hiddenSkills or {}
    for _, category in ipairs(catalog.getCategories()) do
        if category.id ~= "all" then
            choices[#choices + 1] = {
                text = category.label, value = category.id, selected = not hidden[category.id]
            }
        end
    end
    local displayChoices = {
        { text = "Show item icons", value = "showIcons", selected = settings.showIcons ~= false },
        { text = "Show goals", value = "showGoals", selected = settings.showGoals ~= false },
        -- RuneScape text tags tint only the sign, matching the resource rows.
        { text = "Show <col=66D97A>+</col> on gains", value = "showGainPlus",
            selected = settings.showGainPlus ~= false },
        { text = "Show Artefacts", value = "showArtefacts",
            selected = settings.showArtefacts ~= false },
        { text = "Show recent items overlay", value = "showOverlay",
            selected = settings.showOverlay == true },
        { text = "Show overlay backdrop", value = "showOverlayBackdrop",
            selected = settings.showOverlayBackdrop == true }
    }
    local usingNestedPanel = settings.useNestedPanel == true
    local hubChoices = {
        { text = "Use PrettyUI Side Bar", value = "useNestedPanel",
            selected = usingNestedPanel },
        { text = "Hide Plugin Hub ribbon", value = "hidePluginHubRibbon",
            selected = settings.hidePluginHubRibbon == true, disabled = usingNestedPanel }
    }
    local controlsY = 24
    local rowsY = controlsY + #displayChoices * 22 + 4
    local opacityY = rowsY + 24
    local hintY = opacityY + 46
    local hubTitleY = math.max(controlsY + #choices * 22, hintY + 22) + 6
    local hubControlsY = hubTitleY + 20
    -- Reserve the scrollbar gutter before sizing either column.
    view:SetContentHeight(hubControlsY + #hubChoices * 22 + 4)
    local leftX, gap = 6, 16
    local columnWidth = math.floor((view.contentWidth - leftX * 2 - gap) / 2)
    local rightX = leftX + columnWidth + gap

    local clearWidth = 100
    local choiceWidth = columnWidth - clearWidth - 6
    local divider = ui.Rectangle.new(view.content)
    divider:SetPos(leftX + columnWidth + gap // 2, 4)
    divider:SetSize(1, controlsY + #choices * 22 - 4)
    divider.fill = true
    divider.colour = Vector4.new(0.72, 0.48, 0.18, 0.55)
    divider.clickthrough = true

    title(view.content, "VISIBLE TABS", leftX, 4, columnWidth)
    prettyui.CheckboxButton.new(view.content, choices, {
        categoryID = "auto",
        x = leftX, y = controlsY, width = choiceWidth,
        -- Hiding the current skill also resets the selected tab and group.
        onChange = function(_, _, skill, selected)
            -- Copy the hidden-skill set so other settings retain their values.
            queue(function()
                local nextHidden = {}
                for name, value in pairs(state.getSettings().hiddenSkills or {}) do
                    nextHidden[name] = value
                end
                if selected then
                    nextHidden[skill] = nil
                else
                    nextHidden[skill] = true
                end
                state.setSetting("hiddenSkills", nextHidden)
                if not selected and state.getSettings().category == skill then
                    state.setSetting("category", "all")
                    state.setSetting("group", "all")
                end
                armedSkill, profileAction, needsBuild = nil, nil, true
            end)
        end
    })
    for index, choice in ipairs(choices) do
        local skill = choice.value
        prettyui.SimpleButton.new(view.content,
            armedSkill == skill and "Confirm"
                or (skill == "ports" and "Reset gains" or "Clear"), function()
                -- Ports stock comes from the game, so its action resets only
                -- observed gains; other skills remove their tracked rows.
                queue(function()
                    if armedSkill == skill then
                        state.clearSkill(skill)
                        armedSkill = nil
                    else
                        armedSkill = skill
                    end
                    profileAction = nil
                    needsBuild = true
                end)
            end, { categoryID = "auto", x = leftX + choiceWidth + 6,
                y = controlsY + (index - 1) * 22, width = clearWidth, height = 20 })
    end

    -- PrettyUI callbacks queue persistent setting edits for Logic.
    local function changeDisplay(_, _, name, selected)
        queue(function()
            if state.getGeneration() ~= generation then return end
            if name == "hidePluginHubRibbon" and state.getSettings().useNestedPanel == true then return end
            state.setSetting(name, selected)
            armedSkill, profileAction, needsBuild = nil, nil, true
        end)
    end

    title(view.content, "DISPLAY", rightX, 4, columnWidth)
    prettyui.CheckboxButton.new(view.content, displayChoices, {
        categoryID = "auto",
        x = rightX, y = controlsY, width = columnWidth,
        onChange = changeDisplay
    })
    local rowLimits = persistence.overlayRows
    local rows = settings.overlayRows or rowLimits.default
    local function adjustRows(step)
        queue(function()
            local current = state.getSettings().overlayRows or rowLimits.default
            local nextRows = math.max(rowLimits.min, math.min(rowLimits.max, current + step))
            state.setSetting("overlayRows", nextRows)
            armedSkill, profileAction, needsBuild = nil, nil, true
        end)
    end
    note(view.content, "Overlay rows", rightX, rowsY + 1, 96)
    prettyui.SimpleButton.new(view.content, "-", function() adjustRows(-1) end,
        { categoryID = "auto", x = rightX + 97, y = rowsY, width = 28, height = 20,
            disabled = rows == rowLimits.min })
    local rowCount = note(view.content, tostring(rows), rightX + 127, rowsY + 1, 26)
    rowCount.alignHorizontal = ui.AlignMode.CENTRE
    prettyui.SimpleButton.new(view.content, "+", function() adjustRows(1) end,
        { categoryID = "auto", x = rightX + 155, y = rowsY, width = 28, height = 20,
            disabled = rows == rowLimits.max })

    local opacityLimits = persistence.overlayBackdropOpacity
    local opacity = settings.overlayBackdropOpacity or opacityLimits.default
    note(view.content, "Backdrop opacity", rightX, opacityY, columnWidth - 42)
    local opacityValue = note(view.content, opacity .. "%", rightX + columnWidth - 42, opacityY, 42)
    opacityValue.alignHorizontal = ui.AlignMode.BOTTOMRIGHT
    local pendingOpacity
    view:AddSlider({
        categoryID = "auto",
        x = rightX, y = opacityY + 20, width = columnWidth,
        min = opacityLimits.min, max = opacityLimits.max, value = opacity,
        disabled = settings.showOverlayBackdrop ~= true,
        onChange = function(_, value)
            opacityValue.content = value .. "%"
            local queued = pendingOpacity ~= nil
            pendingOpacity = value
            if queued then return end
            queue(function()
                local latest = pendingOpacity
                pendingOpacity = nil
                if state.getGeneration() == generation then
                    state.setSetting("overlayBackdropOpacity", latest)
                end
            end)
        end
    })
    note(view.content, "Shift+drag to move.", rightX, hintY, columnWidth)

    local hubHeading = prettyui.IsClassicUI() and "CLASSIC MODE SETTINGS" or "PLUGIN HUB"
    titleWithInfo(view.content, hubHeading, leftX, hubTitleY, columnWidth,
        "Resource Tracker opens in the game's Plugin Hub by default.<br><br>"
        .. "Turn on *Use PrettyUI Side Bar* to use PrettyUI's sidebar in Classic layout or dock the tracker in Modern layout.<br><br>"
        .. "While using the Plugin Hub, toggle *Hide Plugin Hub ribbon* to show or hide its ribbon.")
    prettyui.CheckboxButton.new(view.content, hubChoices, {
        categoryID = "auto",
        x = leftX, y = hubControlsY, width = view.contentWidth - leftX * 2,
        onChange = changeDisplay
    })

    local separator = ui.Rectangle.new(root)
    separator:SetPos(8, bottomY - 5)
    separator:SetSize(width - 16, 1)
    separator.fill = true
    separator.colour = Vector4.new(0.72, 0.48, 0.18, 0.55)
    separator.clickthrough = true

    local ready = state.isReady()
    local target = state.getAccount()
    local profiles = persistence.profiles()
    local characterName = state.getCharacterName()
    local entries = { {
        text = characterName and ("Current: " .. characterName) or "Current",
        id = 1, account = target
    } }
    local selectedIndex = 1
    for _, profile in ipairs(profiles) do
        if profile.account ~= target then
            local index = #entries + 1
            -- Keep labels inside the native ComboBox without showing tracking IDs.
            entries[index] = {
                text = string.format("%s - %.0f items", profile.name, profile.count),
                id = index, account = profile.account
            }
            if selectedAccount == profile.account then selectedIndex = index end
        end
    end
    local account = entries[selectedIndex].account
    local isCurrent = account == target
    if selectedAccount ~= account and profileAction ~= "deleteAll" then
        profileAction = nil
    end
    selectedAccount = account

    local infoX = titleWithInfo(root, "SAVED PROFILES", 8, bottomY + 2, width - 16,
        "Saved Profiles - are shared by characters on this device.<br><br>"
        .. "*Current* is this character's active save.<br><br>"
        .. "*Copy Profile* replaces this character's save with a copy of the selected profile.<br><br>"
        .. "*Delete Profile* permanently removes the selected save.")
    local actionWidth, actionGap = 120, 8
    local deleteX = width - 8 - actionWidth
    local copyX = deleteX - actionGap - actionWidth
    local pickerY = bottomY + 23
    prettyui.ComboBox.new(root, {
        categoryID = "auto",
        x = 8, y = pickerY, width = copyX - actionGap - 8, height = 22,
        entries = entries, selectedID = selectedIndex,
        maxVisibleEntries = 2, disabled = not ready or #entries == 1,
        onChange = function(_, entryId)
            selectedAccount = entries[entryId] and entries[entryId].account
            profileAction, profileError, needsBuild = nil, nil, true
        end
    })

    local function addProfileAction(action, label, confirmLabel, x, apply)
        local enabled = ready and (action == "delete" or not isCurrent)
        local confirming = profileAction == action
        prettyui.SimpleButton.new(root, confirming and confirmLabel or label, function()
            if not enabled or selectedAccount ~= account then return end
            profileError = nil
            if confirming then
                if profileAction ~= action then return end
                profileAction = nil
                queue(function()
                    if state.getGeneration() ~= generation or selectedAccount ~= account then return end
                    if apply(account, target) then
                        if action == "delete" and isCurrent then decisions.discardPending() end
                        selectedAccount = nil
                    else
                        profileError = "Could not " .. action .. " the selected profile."
                    end
                    needsBuild = true
                end)
            else
                armedSkill, profileAction, needsBuild = nil, action, true
            end
        end, { categoryID = "auto", x = x, y = pickerY, width = actionWidth, height = 22,
            colour = confirming and confirmColour or nil, disabled = not enabled })
    end
    addProfileAction("copy", "Copy Profile", "Confirm Copy", copyX, state.restoreProfile)
    addProfileAction("delete", "Delete Profile", "Confirm Delete", deleteX, state.deleteProfile)

    local allWidth = 154
    local allX = width - 8 - allWidth
    local allY = pickerY + 30
    local confirmingAll = profileAction == "deleteAll"
    local profileNote = profileError
        or profileAction == "copy" and "Replace this character's save with a copy."
        or profileAction == "delete" and (isCurrent and "Reset this character's save."
            or "Permanently delete the selected save.")
        or not ready and "Waiting for this character's save."
    if profileNote then
        local noteX = infoX + 24
        note(root, profileNote, noteX, bottomY + 2, width - noteX - 8)
    end

    note(root, "Delete every saved profile on this device.", 8, allY + 2, allX - actionGap - 8)
    prettyui.SimpleButton.new(root,
        confirmingAll and "Confirm Delete All" or "Delete All Data", function()
            if confirmingAll then
                if profileAction ~= "deleteAll" then return end
                profileAction = nil
                queue(function()
                    if state.clearAllData() then
                        decisions.discardPending()
                        selectedAccount = nil
                    end
                    armedSkill, needsBuild = nil, true
                end)
            else
                armedSkill, profileAction, profileError, needsBuild = nil, "deleteAll", nil, true
            end
        end, { categoryID = "auto", x = allX, y = allY, width = allWidth, height = 22,
            colour = confirmingAll and confirmColour or nil })
end

-- Reopen the same movable window so its position and size survive closing it.
function settingsPanel.open(actionQueue)
    queue = actionQueue
    if not window then
        -- The plugin layer has its own ID namespace, avoiding game-area collisions.
        local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        if not parent then return end
        window = prettyui.Window.new(parent, {
            categoryID = "auto",
            title = "Resource Tracker settings",
            x = -305, y = -200, xAnchor = 0.5, yAnchor = 0.5,
            width = 600, height = 460,
            resizable = false,
            -- Let players move the Settings window in the fixed Classic layout.
            respectInterfaceLock = false,
            scrollable = false,
            onClose = function() isOpen = false end
        })
    end
    armedSkill, profileAction, selectedAccount, profileError = nil, nil, nil, nil
    needsBuild = true
    isOpen = true
    window:Show()
    settingsPanel.refresh()
end

-- Reflow the form after settings edits or a window resize.
function settingsPanel.refresh()
    if not isOpen or not window then return end
    if not ui.Interfaces:GetInterface(window.interfaceID) then
        settingsPanel.destroy()
        return
    end
    if needsBuild or not view or shownGeneration ~= state.getGeneration()
        or root.width ~= window.viewport.width
        or root.height ~= window.viewport.height then build() end
end

-- Destroy the form before its window when the plugin unloads.
function settingsPanel.destroy()
    destroyHeadingTips()
    if view then view:Destroy() end
    if root and window and ui.Interfaces:GetInterface(window.interfaceID) then root:Destroy() end
    if window then window:Destroy() end
    window, root, view, queue, armedSkill, profileAction, selectedAccount,
        profileError, needsBuild = nil, nil, nil, nil, nil, nil, nil, nil, nil
    shownGeneration = -1
    isOpen = false
end

return settingsPanel

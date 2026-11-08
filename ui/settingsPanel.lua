local catalog = require("catalog/resourceCatalog")
local decisions = require("Core/counting")
local persistence = require("Core/persistence")
local state = require("ui/trackerState")

local settingsPanel = {}
-- Keep the settings form in its own window so the ribbon button can open it.
local window, root, view, queue, profileTip
local isOpen = false
local armedSkill, armedRestore, armedAll, selectedAccount, needsBuild
local shownGeneration = -1

local titleColour = Vector4.new(0.95, 0.75, 0.38, 1)

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
end

-- Lay out visible skill tabs and display settings in the available panel size.
local function build()
    needsBuild = false
    shownGeneration = state.getGeneration()
    if profileTip then profileTip:Destroy(); profileTip = nil end
    if view then view:Destroy(); view = nil end
    if root then root:Destroy() end
    local width, height = window.viewport.width, window.viewport.height
    -- Reuse this ID after each redraw instead of consuming the shared category 0 IDs.
    root = ui.Layer.new(window.content, 187, 0)
    root:SetSize(width, height)
    local bottomY = height - 110
    view = prettyui.SimpleView.new(root, {
        x = 2, y = 2, width = width - 4, height = math.max(1, bottomY - 6)
    })

    local settings = state.getSettings()
    local width = view.contentWidth
    local leftX, gap = 6, 16
    local columnWidth = math.floor((width - leftX * 2 - gap) / 2)
    local rightX = leftX + columnWidth + gap
    local controlsY = 24

    local choices = {}
    local hidden = settings.hiddenSkills or {}
    for _, category in ipairs(catalog.getCategories()) do
        if category.id ~= "all" then
            choices[#choices + 1] = {
                text = category.label, value = category.id, selected = not hidden[category.id]
            }
        end
    end
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
                armedSkill, armedRestore, armedAll, needsBuild = nil, false, false, true
            end)
        end
    })
    for index, choice in ipairs(choices) do
        local skill = choice.value
        prettyui.SimpleButton.new(view.content,
            armedSkill == skill and "Confirm" or "Clear", function()
                -- First click arms this skill; the second removes only its rows.
                queue(function()
                    if armedSkill == skill then
                        state.clearSkill(skill)
                        armedSkill = nil
                    else
                        armedSkill = skill
                    end
                    armedRestore, armedAll = false, false
                    needsBuild = true
                end)
            end, { x = leftX + choiceWidth + 6,
                y = controlsY + (index - 1) * 22, width = clearWidth, height = 20 })
    end

    title(view.content, "DISPLAY", rightX, 4, columnWidth)
    prettyui.CheckboxButton.new(view.content, {
        { text = "Show item icons", value = "showIcons", selected = settings.showIcons ~= false },
        { text = "Show goals", value = "showGoals", selected = settings.showGoals ~= false },
        { text = "Show Artefacts", value = "showArtefacts",
            selected = settings.showArtefacts ~= false }
    }, {
        x = rightX, y = controlsY, width = columnWidth,
        -- PrettyUI callbacks queue persistent setting edits for Logic.
        onChange = function(_, _, name, selected)
            queue(function()
                state.setSetting(name, selected)
                armedSkill, armedRestore, armedAll, needsBuild = nil, false, false, true
            end)
        end
    })
    view:SetContentHeight(math.max(view.root.height, controlsY + #choices * 22 + 4))

    local separator = ui.Rectangle.new(root)
    separator:SetPos(8, bottomY - 5)
    separator:SetSize(width - 16, 1)
    separator.fill = true
    separator.colour = Vector4.new(0.72, 0.48, 0.18, 0.55)
    separator.clickthrough = true

    -- Only data records appear here; copying one leaves the source character alone.
    local profiles = persistence.profiles()
    local entries = {}
    local selectedIndex = 1
    for _, profile in ipairs(profiles) do
        if profile.account ~= state.getAccount() then
            local index = #entries + 1
            -- Keep labels inside the native ComboBox without showing tracking IDs.
            entries[index] = {
                text = string.format("%s - %.0f items", profile.name, profile.count),
                id = index, account = profile.account
            }
            if selectedAccount == profile.account then selectedIndex = index end
        end
    end
    local hasProfiles = #entries > 0
    local canRestore = hasProfiles and state.isReady()
    if hasProfiles then
        selectedAccount = entries[selectedIndex].account
    else
        entries[1] = { text = "No other saved profiles", id = 1 }
        selectedAccount, armedRestore = nil, false
    end

    title(root, "SAVED PROFILES", 8, bottomY + 2, width - 16)
    local info = ui.Sprite.new(root)
    info:SetPos(8 + utils.CalcTextWidth(id.Font.CINZEL_13PT_BOLD,
        "SAVED PROFILES") + 7, bottomY + 3)
    info:SetSize(14, 14)
    info.spriteID = id.Sprite.RS3_ICON_INFO
    profileTip = prettyui.Tooltip.attach(info, root, {
        text = "*Saved profiles* - are shared by characters on this device.<br><br>"
            .. "This character's active save is not listed.<br><br>"
            .. "Use this to recover saved data if your usual profile fails to load.<br><br>"
            .. "*Use profile* - copies the selected profile's counts, goals, settings, and history over this character's save.",
        placement = "above", maxWidth = 280
    })
    local actionWidth = 160
    local actionX = width - actionWidth - 8
    prettyui.ComboBox.new(root, {
        x = 8, y = bottomY + 23, width = actionX - 16, height = 22,
        entries = entries, selectedID = selectedIndex,
        maxVisibleEntries = 2, disabled = not canRestore,
        onChange = function(_, entryId)
            selectedAccount = entries[entryId] and entries[entryId].account
            armedRestore, armedAll, needsBuild = false, false, true
        end
    })
    prettyui.SimpleButton.new(root,
        armedRestore and "Confirm replace" or "Use profile", function()
            if not selectedAccount then return end
            if armedRestore then
                local account = selectedAccount
                local target = state.getAccount()
                queue(function()
                    if state.restoreProfile(account, target) then selectedAccount = nil end
                    armedRestore, needsBuild = false, true
                end)
            else
                armedRestore, armedAll, needsBuild = true, false, true
            end
        end, { x = actionX, y = bottomY + 23, width = actionWidth,
            height = 22, disabled = not canRestore })
    local profileNote = not state.isReady() and "Waiting for this character's save."
        or hasProfiles and "Replace this character's data with a copy of the selected profile."
        or "No other saved profiles found on this device."
    note(root, profileNote, 8, bottomY + 48, width - 16)

    note(root, "Delete all saved character profiles on this device.",
        8, bottomY + 78, actionX - 16)
    prettyui.SimpleButton.new(root,
        armedAll and "Confirm delete" or "Delete all data", function()
            if armedAll then
                queue(function()
                    if state.clearAllData() then
                        decisions.discardPending()
                        selectedAccount = nil
                    end
                    armedSkill, armedRestore, armedAll, needsBuild = nil, false, false, true
                end)
            else
                armedRestore, armedAll, needsBuild = false, true, true
            end
        end, { x = actionX, y = bottomY + 76, width = actionWidth, height = 22 })
end

-- Reopen the same movable window so its position and size survive closing it.
function settingsPanel.open(actionQueue)
    queue = actionQueue
    if not window then
        local gameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
        if not gameArea then return end
        window = prettyui.Window.new(gameArea, {
            title = "Resource Tracker settings",
            x = -305, y = -200, xAnchor = 0.5, yAnchor = 0.5,
            width = 610, height = 400,
            resizable = true, minWidth = 500, minHeight = 330,
            scrollable = false,
            onClose = function() isOpen = false end
        })
    end
    armedSkill, armedRestore, armedAll, selectedAccount = nil, false, false, nil
    needsBuild = true
    isOpen = true
    window:Show()
    settingsPanel.refresh()
end

-- Reflow the form after settings edits or a window resize.
function settingsPanel.refresh()
    if not isOpen or not window then return end
    if not ui.Interfaces:GetInterface(window.content.interfaceID) then
        if profileTip then profileTip:Destroy(); profileTip = nil end
        window, root, view, armedSkill, armedRestore, armedAll, selectedAccount, needsBuild =
            nil, nil, nil, nil, nil, nil, nil, nil
        isOpen = false
        return
    end
    if needsBuild or not view or shownGeneration ~= state.getGeneration()
        or root.width ~= window.viewport.width
        or root.height ~= window.viewport.height then build() end
end

-- Destroy the form before its window when the plugin unloads.
function settingsPanel.destroy()
    if profileTip then profileTip:Destroy() end
    if view then view:Destroy() end
    if root then root:Destroy() end
    if window then window:Destroy() end
    window, root, view, queue, profileTip, armedSkill, armedRestore, armedAll,
        selectedAccount, needsBuild = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    shownGeneration = -1
    isOpen = false
end

return settingsPanel

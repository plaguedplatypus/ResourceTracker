local catalog = require("catalog/resourceCatalog")
local state = require("ui/trackerState")

local settingsPanel = {}
-- Keep the settings form in its own window so the ribbon button can open it.
local window, root, view, queue
local isOpen = false
local armedSkill, needsBuild

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

-- Lay out visible skill tabs and display settings in the available panel size.
local function build()
    needsBuild = false
    if view then view:Destroy(); view = nil end
    if root then root:Destroy() end
    local width, height = window.viewport.width, window.viewport.height
    -- Reuse this ID after each redraw instead of consuming the shared category 0 IDs.
    root = ui.Layer.new(window.content, 187, 0)
    root:SetSize(width, height)
    view = prettyui.SimpleView.new(root, {
        x = 2, y = 2, width = width - 4, height = math.max(1, height - 4)
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
                armedSkill, needsBuild = nil, true
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
                armedSkill, needsBuild = nil, true
            end)
        end
    })
    view:SetContentHeight(math.max(view.root.height, controlsY + #choices * 22 + 4))
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
    armedSkill = nil
    needsBuild = true
    isOpen = true
    window:Show()
    settingsPanel.refresh()
end

-- Reflow the form after settings edits or a window resize.
function settingsPanel.refresh()
    if not isOpen or not window then return end
    if not ui.Interfaces:GetInterface(window.content.interfaceID) then
        window, root, view, armedSkill, needsBuild = nil, nil, nil, nil, nil
        isOpen = false
        return
    end
    if needsBuild or not view or root.width ~= window.viewport.width
        or root.height ~= window.viewport.height then build() end
end

-- Destroy the form before its window when the plugin unloads.
function settingsPanel.destroy()
    if view then view:Destroy() end
    if root then root:Destroy() end
    if window then window:Destroy() end
    window, root, view, queue, armedSkill, needsBuild = nil, nil, nil, nil, nil, nil
    isOpen = false
end

return settingsPanel

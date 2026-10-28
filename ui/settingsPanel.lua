local catalog = require("catalog/resourceCatalog")
local state = require("ui/trackerState")
local trackerPanel = require("ui/trackerPanel")

local settingsPanel = {}
-- Manage Plugins owns this layer, so keep settings here and use the separate
-- session window for reports that the player may want to move or resize.
local parent, root, view
local armedSkill, needsBuild

local titleColour = Vector4.new(0.95, 0.75, 0.38, 1)

-- Keep Manage Plugins section headings consistent with the tracker theme.
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
    root = ui.Layer.new(parent)
    root:SetSize(parent.width, parent.height)
    view = prettyui.SimpleView.new(root, {
        x = 2, y = 2, width = parent.width - 4, height = math.max(1, parent.height - 4)
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
            trackerPanel.queue(function()
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
                trackerPanel.queue(function()
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
            trackerPanel.queue(function()
                state.setSetting(name, selected)
                armedSkill, needsBuild = nil, true
            end)
        end
    })
    view:SetContentHeight(view.root.height)
end

-- Manage Plugins supplies a fresh content layer when its page opens.
function settingsPanel.onReady(event)
    parent = event.component
    armedSkill = nil
    build()
end

-- Reflow controls when Manage Plugins changes size.
function settingsPanel.refresh()
    if not view then return end
    if not ui.Interfaces:GetInterface(parent.interfaceID) then
        parent, root, view, armedSkill, needsBuild = nil, nil, nil, nil, nil
        return
    end
    if needsBuild or parent.width ~= root.width or parent.height ~= root.height then build() end
end

-- Destroy the view before the layer that owns it.
function settingsPanel.destroy()
    if view then view:Destroy() end
    if root then root:Destroy() end
    parent, root, view, armedSkill, needsBuild = nil, nil, nil, nil, nil
end

return settingsPanel

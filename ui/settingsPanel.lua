local catalog = require("catalog/resourceCatalog")
local state = require("ui/trackerState")
local trackerPanel = require("ui/trackerPanel")

local settingsPanel = {}
-- Manage Plugins owns this layer, so keep settings here and use the separate
-- session window for reports that the player may want to move or resize.
local parent, root, view

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

-- Lay out display settings and visible skill tabs in the available panel size.
local function build()
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
    local controlsY = 48

    title(view.content, "RESOURCE TRACKER SETTINGS", leftX, 4, width - leftX * 2)
    title(view.content, "DISPLAY", leftX, 28, columnWidth)
    prettyui.CheckboxButton.new(view.content, {
        { text = "Show item icons", value = "showIcons", selected = settings.showIcons ~= false },
        { text = "Show goals", value = "showGoals", selected = settings.showGoals ~= false }
    }, {
        x = leftX, y = controlsY, width = columnWidth,
        -- PrettyUI callbacks queue persistent setting edits for Logic.
        onChange = function(_, _, name, selected)
            -- Save the chosen display option in the tracker state.
            trackerPanel.queue(function() state.setSetting(name, selected) end)
        end
    })

    local choices = {}
    local hidden = settings.hiddenSkills or {}
    for _, category in ipairs(catalog.getCategories()) do
        if category.id ~= "all" then
            choices[#choices + 1] = {
                text = category.label, value = category.id, selected = not hidden[category.id]
            }
        end
    end
    title(view.content, "VISIBLE TABS", rightX, 28, columnWidth)
    prettyui.CheckboxButton.new(view.content, choices, {
        x = rightX, y = controlsY, width = columnWidth,
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
            end)
        end
    })
    view:SetContentHeight(view.root.height)
end

-- Manage Plugins supplies a fresh content layer when its page opens.
function settingsPanel.onReady(event)
    parent = event.component
    build()
end

-- Reflow controls when Manage Plugins changes size.
function settingsPanel.refresh()
    if not view then return end
    if not ui.Interfaces:GetInterface(parent.interfaceID) then
        parent, root, view = nil, nil, nil
        return
    end
    if parent.width ~= root.width or parent.height ~= root.height then build() end
end

-- Destroy the view before the layer that owns it.
function settingsPanel.destroy()
    if view then view:Destroy() end
    if root then root:Destroy() end
    parent, root, view = nil, nil, nil
end

return settingsPanel

local manageSettings = {}
local buttonRoot, tipLayer

-- The Plugin Hub footer stays loaded after our ribbon page closes.
function manageSettings.detach()
    if buttonRoot then
        pcall(function() prettyui.Tooltip.unregisterContext(buttonRoot) end)
        if ui.Interfaces:GetInterface(buttonRoot.interfaceID) then
            pcall(function() buttonRoot:Destroy() end)
        end
        buttonRoot = nil
    end
    if tipLayer then
        if ui.Interfaces:GetInterface(tipLayer.interfaceID) then
            pcall(function() tipLayer:Destroy() end)
        end
        tipLayer = nil
    end
end

-- The caller supplies its own settings window; the Hub has no direct-open API.
function manageSettings.attach(queue, active, openSettings)
    manageSettings.detach()
    local footer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_PLUGIN_CONTENT__BUTTON_LAYER)
    if not footer then return end

    -- Separate categories avoid the shared game layer's category 0 ID limit.
    buttonRoot = ui.Layer.new(footer, 185)
    buttonRoot:SetPos(-28, 0, 1, 0)
    buttonRoot:SetSize(24, 24)
    local top = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) or buttonRoot
    tipLayer = ui.Layer.new(top, 186)
    tipLayer:SetSize(0, 0, 1, 1)
    tipLayer.clickthrough = true

    local currentButton, tipParent = buttonRoot, tipLayer
    local tipText = "Open Settings"
    local font = config.Font.MUSEO_SANS_11PT_REGULAR
    local tipWidth = font:GetStringWidth(tipText, false) + 16
    local tipHeight = font:GetStringHeightAndLineCount(tipText, tipWidth - 16,
        font.baseline, false, false, false) + 10
    -- Centre the tip over the button, shifting it at the screen edge.
    prettyui.Tooltip.registerContext(buttonRoot, tipLayer, function(target)
        if buttonRoot ~= currentButton then return 0, 0 end
        local targetPos, tipPos = target.xyGlobal, tipParent.xyGlobal
        local x = targetPos.x - tipPos.x + (target.width - tipWidth) / 2
        return math.max(0, math.min(x, tipParent.width - tipWidth)),
            targetPos.y - tipPos.y + 3
    end)
    local button = prettyui.SimpleButton.new(buttonRoot, id.Sprite.RS3_ICON_GROUPING_SYSTEM_RANK_1,
        function()
            queue(function()
                -- Ignore a click queued just before another plugin takes this page.
                if buttonRoot ~= currentButton or not active() then return end
                openSettings(queue)
            end)
        end, { width = 24, height = 24, iconSize = 24,
            tooltip = { text = tipText, placement = "above", boundsMargin = 0,
                width = tipWidth, height = tipHeight } })
    -- Match the Hub icons despite PrettyUI's 16px inset for a 24px button.
    button.content:SetPos(0, 0)
    button.content:SetSize(24, 24)
    button.tooltip.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    button.tooltip.label.alignVertical = ui.AlignMode.CENTRE
end

return manageSettings

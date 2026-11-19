local compactTooltip = require("ui/compactTooltip")

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

    buttonRoot = ui.Layer.new(footer)
    buttonRoot:SetPos(-28, 0, 1, 0)
    buttonRoot:SetSize(24, 24)
    local top = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) or buttonRoot
    tipLayer = ui.Layer.new(top)
    tipLayer:SetSize(0, 0, 1, 1)
    tipLayer.clickthrough = true

    local currentButton, tipParent = buttonRoot, tipLayer
    local tip
    -- Centre the tip over the button, shifting it at the screen edge.
    prettyui.Tooltip.registerContext(buttonRoot, tipLayer, function(target)
        if buttonRoot ~= currentButton then return 0, 0 end
        local targetPos, tipPos = target.xyGlobal, tipParent.xyGlobal
        local tipWidth = tip.width
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
        end, { categoryID = "auto", width = 24, height = 24, iconSize = 24 })
    -- Match the Hub icons despite PrettyUI's 16px inset for a 24px button.
    button.content:SetPos(0, 0)
    button.content:SetSize(24, 24)
    tip = compactTooltip.attach(button.root, buttonRoot, "Open Settings")
end

return manageSettings

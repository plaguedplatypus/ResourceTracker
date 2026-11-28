-- Mounts Resource Tracker's Settings cog in the native Plugin Hub footer.
local compactTooltip = require("ui/compactTooltip")

local manageSettings = {}
local buttonRoot, buttonCategory, buttonId, tipLayer, tipInterfaceId

local function getFooter()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_PLUGIN_CONTENT__BUTTON_LAYER)
end

local function isMounted(footer)
    return buttonRoot and footer and footer:GetChild(buttonCategory, buttonId) == buttonRoot
end

-- The shared footer can outlive our page or be replaced independently of it.
function manageSettings.detach()
    if not buttonRoot then return end
    if isMounted(getFooter()) then
        prettyui.Tooltip.unregisterContext(buttonRoot)
        buttonRoot:Destroy()
    else
        -- The old tooltip target may already have been retired with the footer.
        pcall(prettyui.Tooltip.unregisterContext, buttonRoot)
    end
    if tipLayer and ui.Interfaces:GetInterface(tipInterfaceId) then tipLayer:Destroy() end
    buttonRoot, buttonCategory, buttonId, tipLayer, tipInterfaceId = nil, nil, nil, nil, nil
end

function manageSettings.sync(queue, active, openSettings)
    local footer = getFooter()
    if isMounted(footer) then return end
    manageSettings.detach()
    if not footer then return end

    local owner = ui.Layer.new(footer)
    if not owner then return end
    buttonRoot = owner
    buttonCategory, buttonId = owner.categoryID, owner.dynamicID
    owner:SetPos(-28, 0, 1, 0)
    owner:SetSize(24, 24)

    local button = prettyui.SimpleButton.new(owner, id.Sprite.RS3_ICON_GROUPING_SYSTEM_RANK_1,
        function()
            queue(function()
                if buttonRoot == owner and isMounted(getFooter()) and active() then openSettings(queue) end
            end)
        end, { categoryID = "auto", width = 24, height = 24, iconSize = 24 })
    -- Match the native footer's icon size within the PrettyUI button.
    button.content:SetPos(0, 0)
    button.content:SetSize(24, 24)

    local top = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if not top then return end
    local overlay = ui.Layer.new(top)
    if not overlay then return end
    tipLayer = overlay
    tipInterfaceId = overlay.interfaceID
    overlay:SetSize(0, 0, 1, 1)
    overlay.clickthrough = true

    local tip
    -- Use the screen layer so the footer does not clip the hover text.
    prettyui.Tooltip.registerContext(owner, overlay, function(target)
        if buttonRoot ~= owner then return 0, 0 end
        local targetPos, overlayPos = target.xyGlobal, overlay.xyGlobal
        local x = targetPos.x - overlayPos.x + (target.width - tip.width) / 2
        return math.max(0, math.min(x, overlay.width - tip.width)), targetPos.y - overlayPos.y + 3
    end)
    tip = compactTooltip.attach(button.root, owner, "Open Settings")
end

return manageSettings

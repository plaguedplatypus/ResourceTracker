-- This injects a toggle button onto the Button Layer of the plugin hub to hide the ribbon icons 
-- and give that space back to the plugin.
local toggle = {}
-- The Hub owns the ribbon and footer. The plugin owns only eyeRoot and tipLayer.
local content, ribbon, eyeRoot, tipLayer
-- Save the Hub's layout values so closing the page restores its resize anchors.
local contentPos, contentSize
local hidden = false

-- The footer outlives this plugin's page, so remove our button on every rebuild.
local function removeButton()
    if eyeRoot then
        -- PrettyUI puts the tip outside eyeRoot; unregister it before deleting
        -- the button. The Hub may already have destroyed either component.
        pcall(function() prettyui.Tooltip.unregisterContext(eyeRoot) end)
        if ui.Interfaces:GetInterface(eyeRoot.interfaceID) then
            pcall(function() eyeRoot:Destroy() end)
        end
        eyeRoot = nil
    end
    if tipLayer then
        if ui.Interfaces:GetInterface(tipLayer.interfaceID) then
            pcall(function() tipLayer:Destroy() end)
        end
        tipLayer = nil
    end
end

-- Hiding the strip alone leaves its height reserved by the Plugin Hub. Its
-- content layer must move up and grow; moving only a child gets clipped.
local function resizeContent()
    local pos, size = contentPos, contentSize
    local extra = hidden and ribbon.height or 0
    content:SetPos(pos.x, pos.y - extra,
        pos.xParentPc, pos.yParentPc, pos.xSelfPc, pos.ySelfPc)
    content:SetSize(size.width, size.height + extra,
        size.widthParentPc, size.heightParentPc)
end

-- A redraw replaces the footer button, but keeps the ribbon's current state.
function toggle.detach()
    removeButton()
end

-- Restore the native strip and content layout when our page is no longer active.
function toggle.close()
    removeButton()
    if hidden and ribbon then
        -- The Hub can replace these native components before our next Logic tick.
        pcall(function() ribbon.hidden = false end)
        pcall(function()
            hidden = false
            resizeContent()
        end)
    end
    content, ribbon, contentPos, contentSize = nil, nil, nil, nil
    hidden = false
end

-- queue runs UI clicks during Logic; active checks that this plugin's page is
-- still open; redraw rebuilds its content after the available height changes.
function toggle.attach(parent, queue, active, redraw)
    -- Keep the first layout snapshot across ordinary redraws, including while
    -- the ribbon is hidden. A new ContentLayerReady parent starts a new page.
    if content ~= parent then
        toggle.close()
        content = parent
        contentPos, contentSize = ui.Pos.new(parent.position), ui.Size.new(parent.size)
    else
        removeButton()
    end
    -- Use the Hub's footer, but leave its built-in buttons alone.
    ribbon = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_PLUGIN_CONTENT__PLUGIN_BUTTONS_LAYER)
    local footer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_PLUGIN_CONTENT__BUTTON_LAYER)
    if not ribbon or not footer then return end

    -- Use separate categories so shared game layers do not exhaust category 0.
    eyeRoot = ui.Layer.new(footer, 183)
    eyeRoot:SetPos(4, 0)
    eyeRoot:SetSize(24, 24)
    -- Render the hover text above the dock so the footer does not clip it.
    local top = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) or eyeRoot
    tipLayer = ui.Layer.new(top, 184)
    tipLayer:SetSize(0, 0, 1, 1)
    tipLayer.clickthrough = true
    local buttonRoot = eyeRoot
    local tipParent = tipLayer
    local tipText = hidden and "Show Plugin Ribbon" or "Hide Plugin Ribbon"
    local font = config.Font.MUSEO_SANS_11PT_REGULAR
    local tipWidth = font:GetStringWidth(tipText, false) + 16
    local tipHeight = font:GetStringHeightAndLineCount(tipText, tipWidth - 16,
        font.baseline, false, false, false) + 10
    -- Centre the tip over the eye and keep it close to the footer button.
    prettyui.Tooltip.registerContext(eyeRoot, tipLayer, function(target)
        if eyeRoot ~= buttonRoot then return 0, 0 end
        local targetPos, tipPos = target.xyGlobal, tipParent.xyGlobal
        local x = targetPos.x - tipPos.x + (target.width - tipWidth) / 2
        return math.max(0, math.min(x, tipParent.width - tipWidth)),
            targetPos.y - tipPos.y + 3
    end)
    -- Bright eye means the ribbon is shown; dark eye means it is hidden.
    local button = prettyui.SimpleButton.new(eyeRoot,
        hidden and id.Sprite.RS3_ICON_WARDROBE_EFFECTS_24PX_4
            or id.Sprite.RS3_ICON_WARDROBE_EFFECTS_24PX_0,
        function()
            queue(function()
                -- A queued click may run after another plugin replaces this page.
                if eyeRoot ~= buttonRoot or not active() then return end
                hidden = not hidden
                ribbon.hidden = hidden
                resizeContent()
                redraw()
            end)
        end, { width = 24, height = 24, iconSize = 24,
            tooltip = { text = tipText, placement = "above", boundsMargin = 0,
                width = tipWidth, height = tipHeight } })
    -- PrettyUI caps the icon at 16px in this button; match the Hub's 24px icons.
    button.content:SetPos(0, 0)
    button.content:SetSize(24, 24)
    -- Match the game's compact hover text; PrettyUI handles vertical placement.
    button.tooltip.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    button.tooltip.label.alignVertical = ui.AlignMode.CENTRE
end

return toggle

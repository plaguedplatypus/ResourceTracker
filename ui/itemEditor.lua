local itemEditor = { height = 47, ownedHeight = 24 }
local draft, armed = "", nil
local controls, tooltipContexts = {}, {}

-- The editor is rebuilt when a row changes; release its PrettyUI controls and
-- tooltip context before the scroll content is deleted.
function itemEditor.clear()
    for _, layer in ipairs(tooltipContexts) do
        prettyui.Tooltip.unregisterContext(layer)
    end
    tooltipContexts = {}
    for _, control in ipairs(controls) do control:Destroy() end
    controls = {}
end

function itemEditor.reset()
    draft, armed = "", nil
end

-- The Hub may destroy its old layer before our next Logic event.
function itemEditor.forget()
    itemEditor.reset()
    controls, tooltipContexts = {}, {}
end

local function amountFrom(field, allowZero)
    local amount = tonumber(field:GetText())
    if amount and amount % 1 == 0 and amount >= (allowZero and 0 or 1) then
        return amount
    end
end

-- Normal resources supply every action. Ports supplies goal and reset only.
-- The editor owns the shared layout while each tab owns its saved values.
function itemEditor.draw(owner, y, width, context, options)
    local layer = ui.Layer.new(owner)
    layer:SetPos(2, y)
    layer:SetSize(width, itemEditor.height)
    local background = ui.Rectangle.new(layer)
    background:SetSize(width, itemEditor.height)
    background.fill = true
    background.colour = Vector4.new(0.10, 0.085, 0.06, 0.7)
    background.clickthrough = true

    -- Scroll offsets are absent from xyGlobal, so place tooltips using the
    -- current viewport position. Ignore callbacks from a replaced Hub panel.
    local root, list, overlay = context.root, context.list, context.tooltipLayer
    local tips = {}
    prettyui.Tooltip.registerContext(layer, overlay, function(target)
        if not context.isCurrent(root, list) then return 0, 0 end
        local ok, x, y = pcall(function()
            local listPos, overlayPos = list.root.xyGlobal, overlay.xyGlobal
            return listPos.x + (layer.x or 0) + (target.x or 0) - overlayPos.x,
                listPos.y + (layer.y or 0) + (target.y or 0) - list.scrollY - overlayPos.y
        end)
        if not ok then return 0, 0 end
        local tip = tips[target]
        if tip then
            x = x + (target.width - tip.width) / 2
            x = math.max(0, math.min(x, overlay.width - tip.width))
            y = y + 3
        end
        return x, y
    end)
    tooltipContexts[#tooltipContexts + 1] = layer

    local function attachTip(button, text)
        tips[button] = context.tip(button, layer, text)
    end

    local field = prettyui.TextField.new(layer, {
        x = 4, y = 3, width = width - 8, height = 21,
        text = draft, placeholder = options.setCount and "Count or goal" or "goal",
        filterMode = ui.InputFieldFilterMode.NUMBERS_AS_TEXT, maxLength = 12,
        onChange = function(_, _, value) draft = value end
    })
    controls[#controls + 1] = field

    local function addIcon(sprite, tip, action, x, disabled, size)
        size = size or 16
        local button = prettyui.SpriteButton.new(layer, sprite, action, {
            x = x, y = 35 - size / 2, size = size, disabled = disabled
        })
        controls[#controls + 1] = button
        attachTip(button.root, tip)
        return button
    end

    local function change(action, allowZero)
        local amount = amountFrom(field, allowZero)
        if not amount then return end
        context.queue(function()
            action(amount)
            itemEditor.reset()
        end)
    end

    if options.setCount then
        addIcon("PENCIL", "Set count from the entered number", function()
            change(options.setCount, true)
        end, 4)
    end
    local goalX = options.setCount and 24 or 4
    addIcon("STAR", "Set goal from the entered number", function()
        change(options.setGoal, false)
    end, goalX)
    addIcon("ERASER", "Clear goal", function()
        context.queue(function()
            options.setGoal(nil)
            armed = nil
        end)
    end, goalX + 20, options.goal == nil)

    if options.pin then
        local pin = ui.Sprite.new(layer)
        pin:SetPos(64, 27)
        pin:SetSize(16, 16)
        pin.spriteID = id.Sprite.ACHIEVEMENT_ICON_PIN_14PX_0
        pin:Subscribe(ui.Hook.ONCLICK, function()
            context.queue(options.pin)
            return true
        end)
        controls[#controls + 1] = pin
        attachTip(pin, options.pinned and "Unpin resource" or "Pin resource to top")
    end

    local resetX = options.remove and width - 42 or width - 22
    local resetTip = options.setCount and "Reset count (click twice)"
        or "Reset gains (click twice)"
    local reset = addIcon("REFRESH", resetTip, function()
        if armed == "reset" then
            context.queue(function()
                options.reset()
                options.close()
                itemEditor.reset()
            end)
        else
            context.queue(function()
                armed = "reset"
                context.redraw()
            end)
        end
    end, resetX, false, 20)
    if armed == "reset" then reset.root.colour = Vector4.new(1, 0.18, 0.12, 1) end

    if options.remove then
        local remove = addIcon("TRASH", "Remove resource (click twice)", function()
            if armed == "remove" then
                context.queue(function()
                    options.remove()
                    options.close()
                    itemEditor.reset()
                end)
            else
                context.queue(function()
                    armed = "remove"
                    context.redraw()
                end)
            end
        end, width - 22, false, 20)
        if armed == "remove" then remove.root.colour = Vector4.new(1, 0.18, 0.12, 1) end
    end
    return layer
end

-- Stock and Invention material balances sit below the editable controls.
function itemEditor.drawOwned(owner, y, width, value, onClick)
    local detail = ui.Layer.new(owner)
    detail:SetPos(2, y)
    detail:SetSize(width, itemEditor.ownedHeight)
    local background = ui.Rectangle.new(detail)
    background:SetSize(width, itemEditor.ownedHeight)
    background.fill = true
    background.colour = Vector4.new(0.10, 0.085, 0.06, 0.7)
    background.clickthrough = true
    if onClick then detail:Subscribe(ui.Hook.ONCLICK, onClick) end
    local label = ui.Text.new(detail)
    label:SetPos(6, 1)
    label:SetSize(width - 12, 20)
    label.content = value
    label.font = id.Font.MUSEO_SANS_15PT_REGULAR
    label.colour = Vector4.new(0.96, 0.88, 0.72, 1)
    label.maxLines = 1
    label.clickthrough = true
    return detail
end

return itemEditor

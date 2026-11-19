local compactTooltip = {}

function compactTooltip.measure(text)
    if text == "" then return 21, 21 end
    local font = config.Font.MUSEO_SANS_11PT_REGULAR
    local width = math.max(21, math.min(240, font:GetStringWidth(text, false) + 16))
    local height = font:GetStringHeightAndLineCount(text, width - 16,
        font.baseline, false, false, false) + 10
    return width, height
end

function compactTooltip.show(tip)
    -- PrettyUI retains native tooltip parts once a caller customizes the label.
    local label = tip.label
    if not label then return end
    label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    label.alignVertical = ui.AlignMode.CENTRE
    tip:Show()
end

function compactTooltip.attach(target, parent, text)
    local width, height = compactTooltip.measure(text)
    return prettyui.Tooltip.attach(target, parent, {
        categoryID = "auto", text = text, placement = "above", boundsMargin = 0,
        width = width, height = height
    }, { onMouseOver = compactTooltip.show })
end

return compactTooltip

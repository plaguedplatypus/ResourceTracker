-- Hides the native Hub ribbon while Resource Tracker owns the visible Hub page.
local ribbonToggle = {}
local hiddenLayout

local function getRibbon()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_PLUGIN_CONTENT__PLUGIN_BUTTONS_LAYER)
end

function ribbonToggle.restore()
    local layout = hiddenLayout
    if not layout then return end
    hiddenLayout = nil
    local ribbon = getRibbon()
    if ribbon == layout.ribbon then ribbon.hidden = false end

    local content
    if layout.categoryId == -1 then
        content = ui.Interfaces:GetComponent(layout.interfaceId, layout.staticId)
    else
        content = ui.Interfaces:GetComponent(layout.interfaceId, layout.staticId, layout.categoryId, layout.dynamicId)
    end
    if content ~= layout.content then return end
    -- Restore our offsets while preserving layout changes made by the client.
    local position, size = content.position, content.size
    if position.y == layout.raisedY then
        content:SetY(layout.originalY, position.yParentPc, position.ySelfPc)
    end
    if size.height == layout.expandedHeight then
        content:SetHeight(layout.originalHeight, size.heightParentPc)
    end
end

function ribbonToggle.hide(content)
    local ribbon = getRibbon()
    if hiddenLayout then
        if hiddenLayout.content == content and hiddenLayout.ribbon == ribbon then return end
        ribbonToggle.restore()
    end
    if not ribbon or ribbon.hidden or ribbon.height <= 0 then return end

    local position, size = content.position, content.size
    local raisedY, expandedHeight = position.y - ribbon.height, size.height + ribbon.height
    hiddenLayout = {
        ribbon = ribbon, content = content,
        interfaceId = content.interfaceID, staticId = content.staticID,
        categoryId = content.categoryID, dynamicId = content.dynamicID,
        originalY = position.y, originalHeight = size.height,
        raisedY = raisedY, expandedHeight = expandedHeight
    }
    -- Reclaim the ribbon's space by expanding the native content layer.
    ribbon.hidden = true
    content:SetY(raisedY, position.yParentPc, position.ySelfPc)
    content:SetHeight(expandedHeight, size.heightParentPc)
end

return ribbonToggle

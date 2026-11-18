local catalog = require("catalog/resourceCatalog")
local persistence = require("Core/persistence")
local resourceRow = require("ui/resourceRow")
local state = require("ui/trackerState")

local overlay = {}
local layerCategory = 188
local rowWidth, rowHeight = 230, 23
local defaultPosition = { x = 14, y = 38 }
local rowOptions = { shadow = true }
local backdropColour = Vector4.new(0, 0, 0, 0.25)

local root, rootId, content, handle
local shownRevision, shownGeneration
local hasRows, drag, handleVisible

local function getHost()
    local host = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if host and host.type == ui.ComponentType.LAYER then return host end
end

local function isAttached(host)
    return root and host and host:GetChild(layerCategory, rootId) == root
end

local function forget()
    root, rootId, content, handle, hasRows, drag = nil, nil, nil, nil, nil, nil
    shownRevision, shownGeneration, handleVisible = nil, nil, false
end

function overlay.destroy()
    if root and isAttached(getHost()) then root:Destroy() end
    forget()
end

-- Keep the display reachable when the game window or the row count changes.
local function place(x, y)
    x = math.max(0, math.min(x, root.width - content.width))
    y = math.max(0, math.min(y, root.height - content.height))
    if content.x ~= x or content.y ~= y then content:SetPos(x, y) end
end

local function fitHandle()
    if handle.x ~= content.x or handle.y ~= content.y then
        handle:SetPos(content.x, content.y)
    end
    if handle.width ~= content.width or handle.height ~= content.height then
        handle:SetSize(content.width, content.height)
    end
end

local function build(host)
    root = ui.Layer.new(host, layerCategory)
    rootId = root.dynamicID
    root:SetSize(0, 0, 1, 1)
    root.clickthrough = true
    content = ui.Layer.new(root)
    content.clickthrough = true
    -- Keep the input surface separate so rebuilding rows cannot interrupt a drag.
    handle = ui.Layer.new(root)
    handle.hidden = true
    handle.clickthrough = false
    handle:Subscribe(ui.Hook.ONCLICK, function(self, x, y)
        if self == handle and not drag and hasRows and Keyboard.IsShiftDown() then
            drag = { grabX = x, grabY = y, startX = content.x, startY = content.y }
        end
        return true
    end)
    handle:Subscribe(ui.Hook.ONHOLD, function(self, x, y)
        if self == handle and drag and drag.captured and not drag.released then
            place(x - drag.grabX, y - drag.grabY)
        end
        return true
    end)
    handle:Subscribe(ui.Hook.ONRELEASE, function(self)
        if self == handle and drag then drag.released = true end
        return true
    end)
end

local function drawRows(settings)
    local entries = {}
    local hidden = settings.hiddenSkills or {}
    for key, item in pairs(state.getItems()) do
        local definition = catalog.find(item.name, item.skill)
        if resourceRow.isVisible(item, definition, hidden, settings.showArtefacts) then
            entries[#entries + 1] = { item = item, key = key }
        end
    end
    table.sort(entries, function(a, b)
        if a.item.order ~= b.item.order then return a.item.order > b.item.order end
        return a.key < b.key
    end)
    local count = math.min(#entries, settings.overlayRows or persistence.overlayRows.default)
    hasRows = count > 0
    content:DeleteAll()
    content:SetSize(rowWidth, count * rowHeight)
    content.hidden = not hasRows
    if hasRows and settings.showOverlayBackdrop == true then
        local backdrop = ui.Rectangle.new(content)
        backdrop:SetSize(0, 0, 1, 1)
        backdrop.fill = true
        backdrop.colour = backdropColour
        backdrop.clickthrough = true
    end
    for index = 1, count do
        local row = ui.Layer.new(content)
        row:SetPos(0, (index - 1) * rowHeight)
        row:SetSize(rowWidth, rowHeight)
        row.clickthrough = true
        resourceRow.draw(row, entries[index].item, settings, rowWidth, rowOptions)
    end
end

-- The game layer can appear after account data or be replaced during a UI reload.
function overlay.refresh()
    local settings = state.getSettings()
    if not state.isReady() or settings.showOverlay ~= true then
        overlay.destroy()
        return
    end
    local host = getHost()
    if not isAttached(host) then
        forget()
        if not host then return end
        build(host)
    end
    local generation, revision = state.getGeneration(), state.getRevision()
    if shownGeneration ~= generation then
        drag = nil
        shownGeneration = generation
    end
    if shownRevision ~= revision then
        drawRows(settings)
        shownRevision = revision
    end
    if not hasRows then
        drag = nil
        handle.hidden = true
        handleVisible = false
        return
    end
    local position = settings.overlayPosition or defaultPosition
    if drag then
        place(content.x, content.y)
    else
        place(position.x, position.y)
        fitHandle()
    end
end

-- Only the drag surface accepts input, and only while Shift is held.
function overlay.updateInput()
    if not hasRows then return end
    local shiftDown = Keyboard.IsShiftDown()
    if not drag and shiftDown == handleVisible then return end
    if not isAttached(getHost()) then
        forget()
        return
    end
    if drag and (drag.released or not shiftDown) then
        local x, y = content.x, content.y
        if x ~= drag.startX or y ~= drag.startY then
            state.setSetting("overlayPosition", { x = x, y = y })
        end
        drag = nil
        fitHandle()
    elseif drag and not drag.captured then
        -- Listen across the game layer once grabbed, including beyond the original rows.
        -- Expand on Logic so hold events queued with the click use the original bounds.
        handle:SetPos(0, 0)
        handle:SetSize(0, 0, 1, 1)
        drag.captured = true
    end
    if shiftDown ~= handleVisible then
        handle.hidden = not shiftDown
        handleVisible = shiftDown
    end
end

return overlay

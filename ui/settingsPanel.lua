local catalog = require("catalog/resourceCatalog")
local state = require("ui/trackerState")
local trackerPanel = require("ui/trackerPanel")

local settingsPanel = {}
-- The Plugin Hub can recreate its settings component. Keep only the current
-- layer and scroll view so each rebuild cleanly replaces the old controls.
local root, view, parent
local page = "settings"
local historyIndex = 1
local historyClearArmed = false
local shownGeneration = -1
local shownRevision = -1
local shownPage
local rebuild = false

local textColour = Vector4.new(0.90, 0.84, 0.69, 1)
local titleColour = Vector4.new(0.95, 0.75, 0.38, 1)

local function label(owner, content, x, y, width, align, colour)
    local value = ui.Text.new(owner)
    value:SetPos(x, y)
    value:SetSize(width, 18)
    value.content = content
    value.font = id.Font.MUSEO_SANS_15PT_REGULAR
    value.colour = colour or textColour
    value.alignVertical = ui.AlignMode.CENTRE
    value.alignHorizontal = align or ui.AlignMode.TOPLEFT
    value.maxLines = 1
    value.clickthrough = true
    return value
end

local function duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60)
end

local function rate(count, activeSeconds)
    if activeSeconds <= 0 then return "-" end
    return string.format("%.0f", count * 3600 / activeSeconds)
end

local function formatCount(value)
    return string.format("%.0f", value)
end

local function drawTable(report, y)
    -- Split the available width between the resource name and the two numeric
    -- columns. This avoids squeezing counts into a narrow right-hand strip.
    local width = view.contentWidth
    local itemWidth = math.floor((width - 10) / 2)
    local countWidth = math.floor((width - 10 - itemWidth) / 2)
    local rateWidth = width - 10 - itemWidth - countWidth
    local countX = 5 + itemWidth
    local rateX = countX + countWidth
    label(view.content, "Item", 5, y, itemWidth, nil, titleColour)
    label(view.content, "Count", countX, y, countWidth, ui.AlignMode.CENTRE, titleColour)
    label(view.content, "Items/hr", rateX, y, rateWidth, ui.AlignMode.CENTRE, titleColour)
    y = y + 20
    for index, item in ipairs(report.items) do
        local background = ui.Rectangle.new(view.content)
        background:SetPos(2, y)
        background:SetSize(width - 4, 20)
        background.fill = true
        background.colour = index % 2 == 0 and Vector4.new(0, 0, 0, 0.2)
            or Vector4.new(0, 0, 0, 0.75)
        background.clickthrough = true
        label(view.content, item.name, 7, y + 1, itemWidth - 2)
        label(view.content, formatCount(item.count), countX, y + 1,
            countWidth, ui.AlignMode.CENTRE)
        label(view.content, rate(item.count, report.activeSeconds), rateX, y + 1,
            rateWidth, ui.AlignMode.CENTRE)
        y = y + 20
    end
    return y
end

local function buildSettings()
    -- These controls update the same settings used by the tracker.
    view:AddTitle("Resource Tracker settings")
    local settings = state.getSettings()
    view:AddTitle("Display")
    view:AddCheckboxButton({
        { text = "Show item icons", value = "showIcons", selected = settings.showIcons ~= false },
        { text = "Show goals", value = "showGoals", selected = settings.showGoals ~= false }
    }, {
        onChange = function(_, _, name, selected)
            trackerPanel.queue(function() state.setSetting(name, selected) end)
        end
    })

    view:AddTitle("Visible skills")
    local choices = {}
    local hidden = settings.hiddenSkills or {}
    for _, category in ipairs(catalog.getCategories()) do
        if category.id ~= "all" then
            choices[#choices + 1] = {
                text = category.label, value = category.id, selected = not hidden[category.id]
            }
        end
    end
    view:AddCheckboxButton(choices, {
        onChange = function(_, _, skill, selected)
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
end

local function buildSession()
    -- Reports include the current active interval without persisting every tick.
    local report = state.getSession()
    local y = 4
    label(view.content, "THIS SESSION", 5, y, view.contentWidth - 10, nil, titleColour)
    y = y + 23
    label(view.content, "Started: " .. (report.started or "-"), 5, y, view.contentWidth - 10)
    y = y + 19
    label(view.content, "Status: " .. report.status, 5, y, view.contentWidth - 10)
    y = y + 19
    label(view.content, "Active time: " .. duration(report.activeSeconds), 5, y, view.contentWidth - 10)
    y = y + 25
    label(view.content, "Total items: " .. formatCount(report.total), 5, y,
        view.contentWidth - 10, nil, titleColour)
    y = drawTable(report, y + 22)
    view:SetContentHeight(math.max(view.root.height, y + 4))
end

local function buildHistory()
    -- The picker keeps every saved day directly reachable, even after months of
    -- gathering history. Its own scroll view avoids making the report taller.
    local days = state.getSessionDays()
    local hasHistory = #days > 0
    if not hasHistory then days = { "No saved days" } end
    if historyIndex > #days then historyIndex = 1 end
    -- The client List component has a dedicated dropdown style. It owns the
    -- popup and scroll bar, so it is not clipped by the report's SimpleView.
    local picker = ui.List.new(root)
    picker.stylesheetID = id.StyleSheet.DROPDOWN_DEFAULT
    picker:SetPos(6, 31)
    local pickerWidth = parent.width - 12
    if pickerWidth > 220 then pickerWidth = 220 end
    picker:SetSize(pickerWidth, 22)
    picker.entryHeight = 22
    picker.dropdownMaxVisibleEntries = 8
    picker:SetEntries(days, historyIndex)
    if hasHistory then
        picker:Subscribe(ui.Hook.ONSELECTIONCHANGED, function(_, entryId, selected)
            if selected == true or selected == 1 then
                historyIndex = entryId
                rebuild = true
            end
            return true
        end)
    else
        picker:SetEntryEnabled(1, false)
    end
    prettyui.SimpleButton.new(root, historyClearArmed and "Confirm" or "Clear history", function()
        if not hasHistory then return end
        if historyClearArmed then
            trackerPanel.queue(function()
                state.clearHistory()
                historyIndex = 1
                historyClearArmed = false
                rebuild = true
            end)
        else
            historyClearArmed = true
            rebuild = true
        end
    end, { x = pickerWidth + 10, y = 31, width = 130, height = 22 })
    if not hasHistory then
        historyClearArmed = false
        label(view.content, "No daily history yet.", 5, 31, view.contentWidth - 10)
        view:SetContentHeight(view.root.height)
        return
    end
    local key = days[historyIndex]
    local report = state.getSessionDay(key)
    local y = 31
    label(view.content, "DAILY SUMMARY", 5, y, view.contentWidth - 10, nil, titleColour)
    y = y + 23
    label(view.content, "Total items: " .. formatCount(report.total), 5, y,
        view.contentWidth - 10)
    y = y + 19
    label(view.content, "Active time: " .. duration(report.activeSeconds), 5, y, view.contentWidth - 10)
    y = drawTable(report, y + 24)
    view:SetContentHeight(math.max(view.root.height, y + 4))
end

local function build()
    -- SimpleView owns scrolling children, so destroy it before replacing its
    -- parent layer during a page change, resize, or data refresh. Keep the
    -- same page's scroll position when new tracking data refreshes its report.
    local scroll = view and page == shownPage and view.scrollY or 0
    if view then
        view:Destroy()
        view = nil
    end
    if root then root:Destroy() end
    root = ui.Layer.new(parent)
    root:SetSize(parent.width, parent.height)
    local tabWidth = math.floor((parent.width - 8) / 3)
    local pages = {
        { id = "settings", text = "Settings" },
        { id = "session", text = "This session" },
        { id = "history", text = "Daily history" }
    }
    for index, entry in ipairs(pages) do
        prettyui.SimpleButton.new(root, entry.text, function()
            page = entry.id
            historyClearArmed = false
            rebuild = true
        end, { x = 2 + (index - 1) * (tabWidth + 2), y = 2, width = tabWidth, height = 22 })
    end
    view = prettyui.SimpleView.new(root, {
        x = 2, y = 27, width = parent.width - 4, height = math.max(1, parent.height - 29)
    })
    if page == "session" then
        buildSession()
    elseif page == "history" then
        buildHistory()
    else
        buildSettings()
    end
    shownGeneration = state.getGeneration()
    shownRevision = state.getRevision()
    shownPage = page
    view:SetScrollPosition(scroll)
    rebuild = false
end

function settingsPanel.onReady(event)
    parent = event.component
    build()
end

function settingsPanel.refresh()
    if not view then return end
    if not ui.Interfaces:GetInterface(parent.interfaceID) then
        root, view = nil, nil
        return
    end
    if rebuild or shownGeneration ~= state.getGeneration() then
        build()
        return
    end
    if shownRevision ~= state.getRevision() then
        -- Checkboxes update their own visual state. Rebuilding Settings here
        -- would reset its scroll position immediately after a toggle.
        if page == "settings" then
            shownRevision = state.getRevision()
        else
            build()
        end
    end
end

function settingsPanel.destroy()
    if view then view:Destroy() end
    if root then root:Destroy() end
    parent, root, view = nil, nil, nil
end

return settingsPanel

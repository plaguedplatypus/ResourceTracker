local state = require("ui/trackerState")

local session = {}
-- PrettyUI supplies the movable, resizable window. The report view is rebuilt
-- from its current viewport size, so rows follow the player's window size.
local window, root, view
local queue
local isOpen = false
local page = "session"
local historyIndex = 1
local historyClearArmed = false
local shownGeneration = -1
local shownRevision = -1
local shownPage
local rebuild = false
local shownWidth, shownHeight = 0, 0
local startedLabel, statusLabel, activeLabel, totalLabel
local rows = {}

local textColour = Vector4.new(0.22, 0.16, 0.10, 1)
local titleColour = Vector4.new(0.38, 0.22, 0.10, 1)

-- Give report headings and values consistent text styling.
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

-- Report active gathering time in hours, minutes, and seconds.
local function duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60)
end

-- Items per hour uses active time; show no rate before activity starts.
local function rate(count, activeSeconds)
    if activeSeconds <= 0 then return "-" end
    return string.format("%.0f", count * 3600 / activeSeconds)
end

-- Display whole resource quantities in session and day reports.
local function formatCount(value)
    return string.format("%.0f", value)
end

-- Split the available width between the resource name and the two numeric
-- columns. This avoids squeezing counts into a narrow right-hand strip.
local function drawTable(report, y)
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
        background.colour = index % 2 == 0 and Vector4.new(0.35, 0.22, 0.10, 0.06)
            or Vector4.new(0.35, 0.22, 0.10, 0.12)
        background.clickthrough = true
        label(view.content, item.name, 7, y + 1, itemWidth - 2)
        rows[index] = {
            name = item.name,
            count = label(view.content, formatCount(item.count), countX, y + 1,
                countWidth, ui.AlignMode.CENTRE),
            rate = label(view.content, rate(item.count, report.activeSeconds), rateX, y + 1,
                rateWidth, ui.AlignMode.CENTRE)
        }
        y = y + 20
    end
    return y
end

-- Reports include the current active interval without persisting every tick.
local function buildSession()
    local report = state.getSession()
    local y = 4
    label(view.content, "THIS SESSION", 5, y, view.contentWidth - 10, nil, titleColour)
    -- The session boundary follows the first tracked gain and logout.
    view:AddSprite(id.Sprite.RS3_ICON_INFO, {
        x = 5 + utils.CalcTextWidth(id.Font.MUSEO_SANS_15PT_REGULAR, "THIS SESSION") + 5,
        y = y + 1, size = 16, absolute = true,
        tooltip = { text = "A session starts with the first tracked resource after login and ends when you log out.",
            maxWidth = 260 }
    })
    y = y + 23
    startedLabel = label(view.content, "Started: " .. (report.started or "-"),
        5, y, view.contentWidth - 10)
    y = y + 19
    statusLabel = label(view.content, "Status: " .. report.status, 5, y, view.contentWidth - 10)
    y = y + 19
    activeLabel = label(view.content, "Active time: " .. duration(report.activeSeconds),
        5, y, view.contentWidth - 10)
    -- Only active time stops after an idle interval; the session remains open.
    view:AddSprite(id.Sprite.RS3_ICON_INFO, {
        x = 5 + utils.CalcTextWidth(id.Font.MUSEO_SANS_15PT_REGULAR, "Active time: 00:00:00") + 5,
        y = y + 1, size = 16, absolute = true,
        tooltip = { text = "Active time pauses after one minute without a tracked resource gain and resumes on the next gain.",
            maxWidth = 260 }
    })
    y = y + 25
    totalLabel = label(view.content, "Total items: " .. formatCount(report.total), 5, y,
        view.contentWidth - 10, nil, titleColour)
    y = drawTable(report, y + 22)
    view:SetContentHeight(math.max(view.root.height, y + 4))
end

-- The picker keeps every saved day directly reachable, even after months of
-- gathering history. Its own scroll view avoids making the report taller.
local function buildHistory()
    local days = state.getSessionDays()
    local hasHistory = #days > 0
    if not hasHistory then days = { "No saved days" } end
    if historyIndex > #days then historyIndex = 1 end
    -- Keep the picker outside the report view so its popup is not clipped.
    -- PrettyUI's ComboBox also handles client builds that interpret selected
    -- entry IDs as sorted positions rather than their explicit values.
    local pickerWidth = root.width - 184
    if pickerWidth > 220 then pickerWidth = 220 end
    local choices = {}
    for index, day in ipairs(days) do
        choices[#choices + 1] = { text = day, id = index }
    end
    prettyui.ComboBox.new(root, {
        x = 20, y = 45, width = pickerWidth, height = 22,
        entries = choices, selectedID = historyIndex,
        maxVisibleEntries = 8, disabled = not hasHistory,
        -- Switch the history report to the chosen saved day.
        onChange = function(_, entryId)
            historyIndex = entryId
            rebuild = true
        end
    })
    -- Require a second click before clearing all saved daily summaries.
    prettyui.SimpleButton.new(root, historyClearArmed and "Confirm" or "Clear history", function()
        if not hasHistory then return end
        if historyClearArmed then
            -- Persistent edits run during Logic, after this click callback.
            queue(function()
                state.clearHistory()
                historyIndex = 1
                historyClearArmed = false
                rebuild = true
            end)
        else
            historyClearArmed = true
            rebuild = true
        end
    end, { x = pickerWidth + 28, y = 45, width = 130, height = 22 })
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

-- SimpleView owns scrolling children, so destroy it before replacing its
-- parent layer during a page change, resize, or data refresh. Keep the
-- same page's scroll position when new tracking data refreshes its report.
local function build()
    local scroll = view and page == shownPage and view.scrollY or 0
    startedLabel, statusLabel, activeLabel, totalLabel = nil, nil, nil, nil
    rows = {}
    if view then
        view:Destroy()
        view = nil
    end
    if root then root:Destroy() end
    local width, height = window.viewport.width, window.viewport.height
    root = ui.Layer.new(window.content)
    root:SetSize(width, height)
    -- The in-game parchment sprite stays behind the report as the PrettyUI
    -- viewport changes size; the view keeps its own scrolling and clipping.
    local parchment = ui.Sprite.new(root)
    parchment:SetPos(2, 27)
    parchment:SetSize(width - 4, height - 29)
    parchment.spriteID = id.Sprite.RS3_PARCHMENT_SCROLL_BACKGROUND
    parchment.clickthrough = true
    local tabWidth = math.floor((width - 6) / 2)
    local pages = {
        { id = "session", text = "This session" },
        { id = "history", text = "Daily history" }
    }
    for index, entry in ipairs(pages) do
        -- Switching pages rebuilds the report in the same movable window.
        prettyui.SimpleButton.new(root, entry.text, function()
            page = entry.id
            historyClearArmed = false
            rebuild = true
        end, { x = 2 + (index - 1) * (tabWidth + 2), y = 2, width = tabWidth, height = 22 })
    end
    view = prettyui.SimpleView.new(root, {
        x = 18, y = 43, width = width - 36, height = math.max(1, height - 61)
    })
    if page == "session" then
        buildSession()
    else
        buildHistory()
    end
    shownGeneration = state.getGeneration()
    shownRevision = state.getRevision()
    shownPage = page
    shownWidth, shownHeight = width, height
    view:SetScrollPosition(scroll)
    rebuild = false
end

-- Reopen the same draggable window so its player-chosen position is retained.
function session.open(actionQueue)
    queue = actionQueue
    if not window then
        local gameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
        if not gameArea then return end
        -- These are starting dimensions only. PrettyUI handles dragging the
        -- title bar and resizing every edge; the report uses the live viewport.
        window = prettyui.Window.new(gameArea, {
            title = "Resource Tracker session",
            x = -215, y = -185, xAnchor = 0.5, yAnchor = 0.5,
            width = 430, height = 370,
            resizable = true, minWidth = 330, minHeight = 240,
            scrollable = false,
            -- Closing hides the report while keeping the window for later use.
            onClose = function() isOpen = false end
        })
        rebuild = true
    end
    isOpen = true
    window:Show()
    session.refresh()
end

-- Update live values without replacing the report on every resource gain.
function session.refresh()
    if not isOpen or not window then return end
    if not ui.Interfaces:GetInterface(window.content.interfaceID) then
        window, root, view = nil, nil, nil
        return
    end
    if rebuild or not view or shownGeneration ~= state.getGeneration()
        or shownWidth ~= window.viewport.width or shownHeight ~= window.viewport.height then
        build()
        return
    end
    if page == "history" then
        if shownRevision ~= state.getRevision() then build() end
        return
    end
    -- Changing text in place avoids flashing the window on each gain.
    -- Rebuild only when a new resource changes the table's row layout.
    local report = state.getSession()
    if #report.items ~= #rows then build(); return end
    for index, item in ipairs(report.items) do
        if rows[index].name ~= item.name then build(); return end
        rows[index].count.content = formatCount(item.count)
        rows[index].rate.content = rate(item.count, report.activeSeconds)
    end
    startedLabel.content = "Started: " .. (report.started or "-")
    statusLabel.content = "Status: " .. report.status
    activeLabel.content = "Active time: " .. duration(report.activeSeconds)
    totalLabel.content = "Total items: " .. formatCount(report.total)
    shownRevision = state.getRevision()
end

-- Release the report and window when the plugin unloads.
function session.destroy()
    if view then view:Destroy() end
    if root then root:Destroy() end
    if window then window:Destroy() end
    window, root, view = nil, nil, nil
    isOpen = false
end

return session

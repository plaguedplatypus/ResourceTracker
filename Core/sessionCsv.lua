-- Formats session and daily reports for copying into a spreadsheet.
local stats = require("Core/sessionStats")
local sessionCsv = {}

local function textCell(value)
    if value == nil then return "" end
    -- Keep display text with a formula prefix literal in spreadsheets.
    if value:match("^%s*[=+@%-]") then value = "'" .. value end
    return '"' .. value:gsub('"', '""') .. '"'
end

-- The period identifies the current session or the selected UTC day.
function sessionCsv.format(period, report)
    local lines = { "Period,Skill,Resource,Count,Active Seconds,Items per Hour" }
    local periodCell = textCell(period)
    local seconds = math.floor(report.activeSeconds)
    for _, item in ipairs(report.items) do
        local rate = stats.itemsPerHour(item.count, report.activeSeconds)
        lines[#lines + 1] = table.concat({
            periodCell, textCell(item.skill), textCell(item.name), string.format("%.0f", item.count),
            seconds, rate and string.format("%.0f", rate) or ""
        }, ",")
    end
    return table.concat(lines, "\n")
end

return sessionCsv

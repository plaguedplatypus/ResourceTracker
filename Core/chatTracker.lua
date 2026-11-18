local parser = require("Core/chatParser")
local decisions = require("Core/counting")
local trackerState = require("ui/trackerState")

local chatTracker = {}

-- Forward recognised rewards and timestamps; ordinary chat has no count effect.
function chatTracker.onMessage(event)
    trackerState.observeTime(event.timestamp)
    -- ChatMessage is permission-gated by the client; this subscription can stay
    -- in place when chat access is granted or revoked during a session.
    -- Native game messages are not limited to GENERAL and ENGINE. Restrict by
    -- sender and message wording so bank deliveries in other game chat types work.
    local hasSender = event.senderNameSimple ~= "" or event.senderNameUnfiltered ~= ""
    local playerType = event.chatType == ChatType.PUBLIC
        or event.chatType == ChatType.PRIVATE_INCOMING
        or event.chatType == ChatType.PRIVATE_OUTGOING
        or event.chatType == ChatType.PLUGIN
    local result
    if not hasSender and not playerType then
        -- Presets can replace backpack contents without a visible bank loss.
        -- Their chat notice identifies the transfer before it can look like a gain.
        if event.chatMessage:lower():find("your preset is being withdrawn", 1, true) then
            decisions.observePreset()
            return
        end
        result = parser.parse(event.chatMessage)
    end
    if result then
        decisions.observeChat(result)
    end
end

return chatTracker

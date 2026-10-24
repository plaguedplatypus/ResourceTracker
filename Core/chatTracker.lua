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
        result = parser.parse(event.chatMessage)
    end
    if result then
        decisions.observeChat(result)
    end
end

return chatTracker

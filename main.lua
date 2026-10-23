local inventoryTracker = require("Core/inventoryTracker")
local chatTracker = require("Core/chatTracker")
local decisions = require("Core/counting")
local trackerState = require("ui/trackerState")
local panel = require("ui/trackerPanel")
local settingsPanel = require("ui/settingsPanel")

-- Open the character's persisted record once its required tracking ID arrives.
-- Until then, counting keeps packet data in memory.
local function openData()
    if trackerState.isReady() or not Player.IsAvailable() then return end
    -- The tracking ID is transmitted after login and may arrive later.
    local id = Player.GetTrackingID()
    if id == nil then return end
    trackerState.open(id)
end

-- The client calls this when the plugin is disabled or reloaded.
function PluginShutdown()
    Event.InventoryAdded.Unsubscribe("resourceTrackerInventoryAdded")
    Event.InventoryUpdated.Unsubscribe("resourceTrackerInventoryUpdated")
    Event.InventoryRemoved.Unsubscribe("resourceTrackerInventoryRemoved")
    Event.ChatMessage.Unsubscribe("resourceTrackerChatMessage")
    Event.ServerLogic.Unsubscribe("resourceTrackerServerLogic")
    Event.GameStateChanged.Unsubscribe("resourceTrackerGameStateChanged")
    Event.ContentLayerReady.Unsubscribe("resourceTrackerContentLayerReady")
    Event.SettingsLayerReady.Unsubscribe("resourceTrackerSettingsLayerReady")
    Event.Logic.Unsubscribe("resourceTrackerUiLogic")
    panel.destroy()
    settingsPanel.destroy()
    decisions.discardPending()
    trackerState.unload()
end

-- Inventory and chat handlers collect observations from a server packet.
-- ServerLogic reconciles them before the panels read the saved tracker state.
Event.InventoryAdded.Subscribe("resourceTrackerInventoryAdded", inventoryTracker.onAdded)
Event.InventoryUpdated.Subscribe("resourceTrackerInventoryUpdated", inventoryTracker.onUpdated)
Event.InventoryRemoved.Subscribe("resourceTrackerInventoryRemoved", inventoryTracker.onRemoved)
Event.ChatMessage.Subscribe("resourceTrackerChatMessage", chatTracker.onMessage)
Event.ServerLogic.Subscribe("resourceTrackerServerLogic", function()
    openData()
    decisions.finishPacket()
    -- Refresh after a server packet so porter rewards appear promptly.
    panel.refresh()
    settingsPanel.refresh()
end)
Event.GameStateChanged.Subscribe("resourceTrackerGameStateChanged", function(event)
    -- Inventory snapshots from a previous world can be stale after a transition.
    inventoryTracker.onGameStateChanged(event)
    if event.newState == GameState.GAME then
        openData()
    else
        trackerState.unload()
    end
    panel.refresh()
    settingsPanel.refresh()
end)
Event.ContentLayerReady.Subscribe("resourceTrackerContentLayerReady", panel.onReady)
Event.SettingsLayerReady.Subscribe("resourceTrackerSettingsLayerReady", settingsPanel.onReady)

local uiTicks = 0
Event.Logic.Subscribe("resourceTrackerUiLogic", function()
    -- Queue UI clicks for the Logic event so state changes happen in one place.
    trackerState.tick()
    panel.tick()
    local changed = panel.flushActions()
    uiTicks = uiTicks + 1
    if not trackerState.isReady() and uiTicks % 20 == 0 then openData() end
    if changed or uiTicks % 20 == 0 then
        panel.refresh()
        settingsPanel.refresh()
    end
end)

-- Enabling while already in game may not emit InventoryAdded for the backpack.
inventoryTracker.seedBackpack()
openData()
log("Resource Tracker enabled")

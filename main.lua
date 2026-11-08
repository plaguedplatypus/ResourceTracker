local inventoryTracker = require("Core/inventoryTracker")
local chatTracker = require("Core/chatTracker")
local decisions = require("Core/counting")
local trackerState = require("ui/trackerState")
local panel = require("ui/trackerPanel")
local settingsPanel = require("ui/settingsPanel")
local session = require("ui/session")

-- A granted ID can arrive after login. Wait for it so a renamed character
-- cannot start a second save under the new name before its ID arrives.
local function openData()
    if not Player.IsAvailable() then return end
    local id = Player.GetTrackingID()
    if id == nil and (trackerState.isReady()
        or Plugin.HasPermission(PluginPermissions.trackingAccess)) then return end
    local player = Player.GetEntity()
    -- Wait for the name too, so an existing name-only save can be linked when
    -- tracking access is first granted.
    if not player or not player.isValid or player.displayName == "" then return end
    trackerState.open(id, player.displayName:lower())
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
    Event.Logic.Unsubscribe("resourceTrackerUiLogic")
    panel.destroy()
    settingsPanel.destroy()
    session.destroy()
    decisions.discardPending()
    trackerState.unload()
end

-- Inventory and chat handlers collect observations from a server packet.
-- ServerLogic reconciles them before the panels read the saved tracker state.
Event.InventoryAdded.Subscribe("resourceTrackerInventoryAdded", inventoryTracker.onAdded)
Event.InventoryUpdated.Subscribe("resourceTrackerInventoryUpdated", inventoryTracker.onUpdated)
Event.InventoryRemoved.Subscribe("resourceTrackerInventoryRemoved", inventoryTracker.onRemoved)
Event.ChatMessage.Subscribe("resourceTrackerChatMessage", chatTracker.onMessage)
-- Complete each server packet before refreshing the visible totals.
Event.ServerLogic.Subscribe("resourceTrackerServerLogic", function()
    openData()
    decisions.finishPacket()
    -- Refresh after a server packet so porter rewards appear promptly.
    panel.refresh()
    settingsPanel.refresh()
    session.refresh()
end)
-- A world transition resets snapshots and opens the account for the new game.
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
    session.refresh()
end)
Event.ContentLayerReady.Subscribe("resourceTrackerContentLayerReady", panel.onReady)

local uiTicks = 0
-- Tick the UI clock and apply player actions outside PrettyUI callbacks.
Event.Logic.Subscribe("resourceTrackerUiLogic", function()
    -- Queue UI clicks for the Logic event so state changes happen in one place.
    trackerState.tick()
    session.resize()
    local changed = panel.flushActions()
    uiTicks = uiTicks + 1
    if not trackerState.isReady() and uiTicks % 20 == 0 then openData() end
    if changed or uiTicks % 20 == 0 then
        panel.refresh()
        settingsPanel.refresh()
        session.refresh()
    end
end)

-- Enabling while already in game may not emit InventoryAdded for visible containers.
inventoryTracker.seedContainers()
openData()
log("Resource Tracker enabled.")

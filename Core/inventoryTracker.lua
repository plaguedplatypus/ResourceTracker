local decisions = require("Core/counting")

local inventoryTracker = {}
-- Keep the previous snapshot of each transmitted container for transfer checks.
local baselines = {}
local inGame = true
local notedIds = {}

-- Noted backpack items are excluded because their chat reward owns the count.
local function isNoted(obj)
    local noted = notedIds[obj.id]
    if noted ~= nil then return noted end

    -- ObjStackType.ALWAYS is 1 and NEVER is 2 in the published API.
    -- Treat stackable raw fish and stackable variants of ordinarily
    -- unstackable resources as notes; ObjType has no explicit note flag.
    noted = false
    if obj.stackType == 1 then
        local configName = obj.name:upper():gsub("[^A-Z0-9]+", "_")
        -- Some object variants have no corresponding ordinary config entry.
        local ok, ordinary = pcall(function() return config.Obj[configName] end)
        noted = obj.name:lower():sub(1, 4) == "raw "
            or (ok and ordinary and ordinary.name == obj.name
                and ordinary.id ~= obj.id and ordinary.stackType == 2)
    end
    notedIds[obj.id] = noted == true
    return notedIds[obj.id]
end

-- Return item ID, name, and stack quantity for every occupied slot.
local function snapshot(invType)
    local inv = Inventory.Find(invType)
    -- The live inventory proxy exposes isValid; checking valid discarded every snapshot.
    if not inv or not inv.isValid then
        return nil
    end
    local items = {}
    local slots = inv:GetSlots()
    -- Empty inventory slots may be holes in the returned array.
    for index = 1, inv.slotCount do
        local slot = slots[index]
        if slot and slot.obj then
            local id = slot.obj.id
            local item = items[id]
            if item then
                item.count = item.count + slot.count
            else
                items[id] = {
                    name = slot.obj.name,
                    count = slot.count,
                    noted = isNoted(slot.obj)
                }
            end
        end
    end
    return items
end

-- Adding a container establishes its baseline before any gain is counted.
function inventoryTracker.onAdded(event)
    if inGame then
        baselines[event.inv.id] = snapshot(event.inv)
    end
end

-- Compare against the last complete snapshot, then pass signed deltas to counting.
function inventoryTracker.onUpdated(event)
    if not inGame then
        return
    end
    local invType = event.inv
    local current = snapshot(invType)
    if not current then
        baselines[invType.id] = nil
        return
    end
    local previous = baselines[invType.id]
    baselines[invType.id] = current
    if not previous then
        -- The first population after login or container discovery is never a gain.
        return
    end

    -- Backpack changes, all container losses, and wood-box or metal-bank gains enter packet reconciliation.
    -- Ordinary bank gains are not counted alone, bank losses still identify withdrawals into the backpack.
    local ids = {}
    for id in pairs(previous) do ids[id] = true end
    for id in pairs(current) do ids[id] = true end
    for id in pairs(ids) do
        local before = previous[id] and previous[id].count or 0
        local after = current[id] and current[id].count or 0
        local delta = after - before
        local backpack = invType.id == config.Inv.INV.id
        local woodBox = invType.id == config.Inv.WOODCUTTING_WOODBOX.id
        local metalBank = invType.id == config.Inv.METAL_BANK.id
        if (backpack and delta ~= 0) or (not backpack and delta < 0)
            or ((woodBox or metalBank) and delta > 0) then
            local item = current[id] or previous[id]
            decisions.observeInventory({
                backpack = backpack,
                containerId = invType.id,
                itemId = id,
                name = item.name,
                delta = delta,
                noted = item.noted
            })
        end
    end
end

-- A container can later be recreated with unrelated contents.
function inventoryTracker.onRemoved(event)
    baselines[event.inv.id] = nil
end

-- Clear cached container contents when the client leaves or enters a game world.
function inventoryTracker.onGameStateChanged(event)
    baselines = {}
    decisions.discardPending()
    inGame = event.newState == GameState.GAME
    -- Wait for a fresh inventory event after a transition.
end

-- Reloading may not emit InventoryAdded for containers already transmitted.
function inventoryTracker.seedContainers()
    for _, invType in ipairs({ config.Inv.INV, config.Inv.WOODCUTTING_WOODBOX,
        config.Inv.METAL_BANK, config.Inv.BANK }) do
        local items = snapshot(invType)
        if items then
            baselines[invType.id] = items
        end
    end
end

return inventoryTracker

local catalog = require("catalog/resourceCatalog")
local trackerState = require("ui/trackerState")

local decisions = {}
local inventoryChanges = {}
local chatResults = {}
local waitingPackets = {}

-- Buffer inventory deltas until chat from the same game packet can be reconciled.
function decisions.observeInventory(change)
    inventoryChanges[#inventoryChanges + 1] = change
end

-- Chat may identify a reward already visible in an inventory delta.
function decisions.observeChat(result)
    chatResults[#chatResults + 1] = result
end

-- World changes invalidate observations and any delayed packet reconciliation.
function decisions.discardPending()
    inventoryChanges = {}
    chatResults = {}
    waitingPackets = {}
end

-- Claim only the available amount so overlapping sources cannot double count.
local function take(pool, name, amount)
    local available = pool[name] or 0
    local matched = math.min(available, amount)
    pool[name] = available - matched
    return amount - matched
end

-- Chat-owned rewards count from their message; direct chat only identifies
-- nearby backpack gains. Match withdrawals and conversions before counting.
local function countPacket(inventory, chat)
    local withdrawals = {}
    local backpackConversions = {}
    local chatClaims = {}
    local metalClaims = {}
    local unknownMetal = {}
    local directNames = {}
    local updates = {}

    for _, change in ipairs(inventory) do
        if not change.backpack and change.delta < 0 then
            withdrawals[#withdrawals + 1] = {
                itemId = change.itemId,
                name = catalog.normalize(change.name),
                bank = change.containerId == config.Inv.BANK.id,
                amount = -change.delta
            }
        elseif change.backpack and change.delta < 0 then
            local name = catalog.normalize(change.name)
            local losses = backpackConversions[name] or {}
            losses[#losses + 1] = {
                itemId = change.itemId,
                amount = -change.delta
            }
            backpackConversions[name] = losses
        end
    end

    for _, result in ipairs(chat) do
        for _, entry in ipairs(result.entries) do
            local name = catalog.normalize(entry.name)
            if result.metalBank then
                if result.unknownAmount then
                    local entries = unknownMetal[name] or {}
                    entries[#entries + 1] = entry
                    unknownMetal[name] = entries
                else
                    metalClaims[name] = (metalClaims[name] or 0) + entry.amount
                end
            end
            if result.method == "direct" then
                directNames[name] = entry.skill
                if entry.skill == "fishing" then
                    directNames["raw " .. name] = entry.skill
                end
            else
                -- Archaeology and Farming skillcape chat can describe backpack items. 
                -- Bank deliveries, including Boon, cannot overlap a
                -- direct backpack gain of the same resource.
                if result.method == "archaeology" or result.method == "farming" then
                    chatClaims[name] = (chatClaims[name] or 0) + entry.amount
                end
                updates[#updates + 1] = entry
            end
        end
    end

    for _, change in ipairs(inventory) do
        if change.backpack and change.delta > 0 and not change.noted then
            local remaining = change.delta
            local normalized = catalog.normalize(change.name)
            -- Noting and unnoting replace a inventory item ID with another ID
            -- using the same display name. Pair that replacement before looking
            -- for actual gains, so it cannot alter the count or stored icon.
            for _, loss in ipairs(backpackConversions[normalized] or {}) do
                if loss.itemId ~= change.itemId then
                    local matched = math.min(loss.amount, remaining)
                    loss.amount = loss.amount - matched
                    remaining = remaining - matched
                end
            end
            for _, withdrawal in ipairs(withdrawals) do
                if withdrawal.itemId == change.itemId then
                    local matched = math.min(withdrawal.amount, remaining)
                    withdrawal.amount = withdrawal.amount - matched
                    remaining = remaining - matched
                end
            end
            -- A noted withdrawal changes the inventory item ID. 
            -- Match only a witnessed bank loss with the same name, capped by its quantity.
            for _, withdrawal in ipairs(withdrawals) do
                if withdrawal.bank and withdrawal.name == normalized then
                    local matched = math.min(withdrawal.amount, remaining)
                    withdrawal.amount = withdrawal.amount - matched
                    remaining = remaining - matched
                end
            end
            remaining = take(chatClaims, normalized, remaining)
            if remaining > 0 then
                local definition = catalog.findById(change.itemId)
                    or catalog.find(change.name, directNames[normalized])
                -- Invention materials and spirit gifts use chat-only reward paths.
                -- Archaeology artefact popups can add directly to the inventory,
                -- where there may be no matching chat event to count.
                if definition and definition.skill ~= "invention" and definition.skill ~= "seren" then
                    updates[#updates + 1] = {
                        name = definition.name,
                        skill = definition.skill,
                        amount = remaining,
                        itemId = change.itemId
                    }
                end
            end
        end
    end

    -- Logs and nests can arrive directly in the wood box. Filling it also moves
    -- existing items there, so subtract observed losses before counting gains.
    local transfers = {}
    for _, withdrawal in ipairs(withdrawals) do
        transfers[withdrawal.name] = (transfers[withdrawal.name] or 0) + withdrawal.amount
    end
    for name, losses in pairs(backpackConversions) do
        for _, loss in ipairs(losses) do
            transfers[name] = (transfers[name] or 0) + loss.amount
        end
    end
    for _, change in ipairs(inventory) do
        if change.containerId == config.Inv.WOODCUTTING_WOODBOX.id and change.delta > 0 then
            local definition = catalog.findById(change.itemId)
                or catalog.find(change.name, "woodcutting")
            if definition and definition.skill == "woodcutting" then
                local remaining = take(transfers, catalog.normalize(change.name), change.delta)
                if remaining > 0 then
                    updates[#updates + 1] = {
                        name = definition.name,
                        skill = definition.skill,
                        amount = remaining,
                        itemId = change.itemId
                    }
                end
            end
        end
    end

    -- Some metal-bank messages name the ore but omit its quantity.
    -- Use the bank increase when transmitted, after visible deposits and quantified chat.
    local metalGains = {}
    for _, change in ipairs(inventory) do
        if change.containerId == config.Inv.METAL_BANK.id and change.delta > 0 then
            local definition = catalog.findById(change.itemId)
                or catalog.find(change.name, "mining")
            if definition and definition.skill == "mining" then
                local name = catalog.normalize(definition.name)
                metalGains[name] = (metalGains[name] or 0) + change.delta
            end
        end
    end
    for name, gained in pairs(metalGains) do
        local remaining = take(transfers, name, gained)
        remaining = take(metalClaims, name, remaining)
        local entries = unknownMetal[name]
        if entries and remaining >= #entries then
            -- Keep one update per chat line; their combined amount is the delta.
            entries[1].amount = remaining - #entries + 1
        end
    end

    trackerState.recordAuto(updates)
end

-- Delay one packet to allow chat and inventory events from the same gain to meet.
function decisions.finishPacket()
    if #inventoryChanges == 0 and #chatResults == 0 and #waitingPackets == 0 then
        return
    end
    local inventory, chat = inventoryChanges, chatResults
    inventoryChanges, chatResults = {}, {}
    if not trackerState.isReady() then
        -- GetTrackingID can arrive late after login. Keep each server packet
        -- separate so withdrawals and chat claims still pair correctly.
        if #inventory > 0 or #chat > 0 then
            waitingPackets[#waitingPackets + 1] = { inventory = inventory, chat = chat }
        end
        return
    end
    for _, packet in ipairs(waitingPackets) do
        countPacket(packet.inventory, packet.chat)
    end
    waitingPackets = {}
    if #inventory > 0 or #chat > 0 then
        countPacket(inventory, chat)
    end
end

return decisions

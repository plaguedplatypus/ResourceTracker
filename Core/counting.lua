local catalog = require("catalog/resourceCatalog")
local trackerState = require("ui/trackerState")

local decisions = {}
local inventoryChanges = {}
local chatResults = {}
local waitingPackets = {}

function decisions.observeInventory(change)
    inventoryChanges[#inventoryChanges + 1] = change
end

function decisions.observeChat(result)
    chatResults[#chatResults + 1] = result
end

function decisions.discardPending()
    inventoryChanges = {}
    chatResults = {}
    waitingPackets = {}
end

local function take(pool, name, amount)
    local available = pool[name] or 0
    local matched = math.min(available, amount)
    pool[name] = available - matched
    return amount - matched
end

local function countPacket(inventory, chat)
    local withdrawals = {}
    local backpackConversions = {}
    local chatClaims = {}
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
            if result.method == "direct" then
                directNames[name] = entry.skill
                if entry.skill == "fishing" then
                    directNames["raw " .. name] = entry.skill
                end
            else
                -- Explicit remote, material, artefact, or spirit messages own their reward path.
                chatClaims[name] = (chatClaims[name] or 0) + entry.amount
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
            -- A noted withdrawal changes the inventory item ID. Match only a
            -- witnessed bank loss with the same name, capped by its quantity.
            for _, withdrawal in ipairs(withdrawals) do
                if withdrawal.bank and withdrawal.name == normalized then
                    local matched = math.min(withdrawal.amount, remaining)
                    withdrawal.amount = withdrawal.amount - matched
                    remaining = remaining - matched
                end
            end
            remaining = take(chatClaims, normalized, remaining)
            if remaining > 0 then
                local definition = trackerState.findById(change.itemId)
                    or catalog.find(change.name, directNames[normalized])
                    or trackerState.findByName(change.name)
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

    trackerState.recordAuto(updates)
end

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

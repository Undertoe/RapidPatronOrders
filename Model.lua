local _, ns = ...
local L = ns.L
local Pricing = ns.Pricing
local EMPTY = ns.EMPTY

-- Turns raw patron CraftingOrderInfo tables into display/sort models:
-- material plan, cost, reward value, profit, concentration need, and blockers.

local Model = {}
ns.Model = Model

local MUTABLE_SLOT = Enum.TradeskillSlotDataType and Enum.TradeskillSlotDataType.ModifiedReagent

local function ReagentItemID(entry)
	if type(entry) ~= "table" then
		return nil
	end
	if type(entry.reagent) == "table" then
		return entry.reagent.itemID
	end
	return entry.itemID
end

-- Reagent quality tier, or 0 when the item has none. Midnight reagents are not
-- always answered by the direct lookup, so fall back to the quality chat-icon
-- atlas name (its tier number) and then the crafted-quality lookup.
local function ReagentQuality(itemID)
	local direct = C_TradeSkillUI.GetItemReagentQualityByItemInfo
	local quality = direct and direct(itemID)
	if type(quality) == "number" and quality > 0 then
		return quality
	end

	local infoLookup = C_TradeSkillUI.GetItemReagentQualityInfo
	local info = infoLookup and infoLookup(itemID)
	local atlas = type(info) == "table" and info.iconChat
	if type(atlas) == "string" then
		local tier = tonumber(atlas:match("Tier(%d+)"))
		if tier and tier > 0 then
			return tier
		end
	end

	local crafted = C_TradeSkillUI.GetItemCraftedQualityByItemInfo
	quality = crafted and crafted(itemID)
	return type(quality) == "number" and quality > 0 and quality or 0
end

-- Carries the item both nested ("reagent", the current CraftingReagentInfo
-- shape) and at the top level, so either reader of the struct finds it.
local function NewReagent(itemID, dataSlotIndex, quantity)
	return {
		reagent = { itemID = itemID },
		itemID = itemID,
		dataSlotIndex = dataSlotIndex,
		quantity = quantity,
	}
end

-- Lowest quality tier the recipe can produce. An order asking for this tier
-- or less is satisfied by any craft, so it has no real quality requirement.
local function LowestRecipeQuality(recipeInfo)
	local lowest
	for tier, qualityID in pairs(recipeInfo.qualityIDs or EMPTY) do
		if type(tier) == "number" and tier > 0 and qualityID then
			lowest = lowest and math.min(lowest, tier) or tier
		end
	end
	return lowest or 0
end

function Model.GetCurrencyQuantity(currencyID)
	local info = currencyID and C_CurrencyInfo.GetCurrencyInfo(currencyID)
	return info and info.quantity or 0
end

-- Material slots ------------------------------------------------------------

-- Returns the required slots we must fill ourselves, plus the reagents the
-- patron already supplies (needed for accurate quality checks).
local function CollectSlots(schematic, rawOrder)
	local slotSchematics = schematic and schematic.reagentSlotSchematics or EMPTY
	local schematicBySlot = {}
	for _, slotSchematic in ipairs(slotSchematics) do
		schematicBySlot[slotSchematic.slotIndex] = slotSchematic
	end

	-- Only patron reagents in quality (modified-reagent) slots go to the
	-- quality check, using the recipe's data-slot index, the same set the
	-- game's own order view sends. Plain basic reagents make it answer nil.
	local coveredSlots = {}
	local supplied = {}
	for _, suppliedReagent in ipairs(rawOrder.reagents or EMPTY) do
		local slotIndex = suppliedReagent.slotIndex
		if slotIndex then
			coveredSlots[slotIndex] = true
		end
		local slotSchematic = slotIndex and schematicBySlot[slotIndex]
		local info = suppliedReagent.reagentInfo
		local itemID = ReagentItemID(info)
		if itemID and slotSchematic and slotSchematic.dataSlotType == MUTABLE_SLOT then
			supplied[#supplied + 1] = NewReagent(itemID, slotSchematic.dataSlotIndex, info.quantity or 0)
		end
	end

	local slots = {}
	for _, slotSchematic in ipairs(slotSchematics) do
		if slotSchematic.required and not coveredSlots[slotSchematic.slotIndex] then
			local slot = {
				slotIndex = slotSchematic.slotIndex,
				dataSlotIndex = slotSchematic.dataSlotIndex,
				quantity = slotSchematic.quantityRequired or 0,
				mutable = slotSchematic.dataSlotType == MUTABLE_SLOT,
				options = {},
			}
			for _, reagent in ipairs(slotSchematic.reagents or EMPTY) do
				local itemID = ReagentItemID(reagent)
				if itemID then
					slot.options[#slot.options + 1] = {
						itemID = itemID,
						quality = ReagentQuality(itemID),
						price = Pricing:GetUnitPrice(itemID, nil, "material"),
					}
				end
			end
			table.sort(slot.options, function(left, right)
				return left.quality < right.quality
			end)
			slots[#slots + 1] = slot
		end
	end

	return slots, supplied
end

local function PickCheapest(slot)
	local chosen
	for _, option in ipairs(slot.options) do
		if option.price and (not chosen or not chosen.price or option.price < chosen.price) then
			chosen = option
		end
	end
	return chosen or slot.options[1]
end

local function PickBest(slot)
	return slot.options[#slot.options]
end

local function BuildPlan(slots, supplied, pick)
	local plan = {
		picks = {},
		cost = 0,
		costComplete = true,
		craftReagents = {},
		checkReagents = {},
	}
	for _, reagent in ipairs(supplied) do
		plan.checkReagents[#plan.checkReagents + 1] = reagent
	end

	for index, slot in ipairs(slots) do
		local option = pick(slot)
		if not option then
			plan.missingSlot = true
		else
			plan.picks[index] = option
			if option.price then
				plan.cost = plan.cost + option.price * slot.quantity
			else
				plan.costComplete = false
			end
			if slot.mutable then
				local reagent = NewReagent(option.itemID, slot.dataSlotIndex, slot.quantity)
				plan.craftReagents[#plan.craftReagents + 1] = reagent
				plan.checkReagents[#plan.checkReagents + 1] = reagent
			end
		end
	end

	return plan
end

function Model.GetOperationInfo(order, reagents, applyConcentration)
	if not (order.recipeID and C_TradeSkillUI.GetCraftingOperationInfoForOrder) then
		return nil
	end
	return C_TradeSkillUI.GetCraftingOperationInfoForOrder(order.recipeID, reagents, order.orderID, applyConcentration)
end

function Model.MeetsQuality(order, operationInfo)
	return operationInfo ~= nil and (operationInfo.craftingQuality or 0) >= order.minQuality
end

-- Can these reagents reach the order's quality? Returns ok plus the
-- concentration cost and currency (cost 0 when concentration is not used).
-- Concentration raises the result one quality tier, but the operation info
-- the game returns does not include that boost, so with concentration the
-- check is "one tier short and the recipe has a concentration cost".
function Model.ReachesQuality(order, reagents, useConcentration)
	local info = Model.GetOperationInfo(order, reagents, false)
	if not info then
		return false
	end
	if not useConcentration then
		return Model.MeetsQuality(order, info), 0, info.concentrationCurrencyID
	end
	local cost = info.concentrationCost or 0
	local reached = cost > 0 and (info.craftingQuality or 0) + 1 >= order.minQuality
	return reached, cost, info.concentrationCurrencyID
end

-- Tries, in order: cheapest materials, top-quality materials, then each with
-- concentration. The first plan that reaches the required quality wins, so
-- concentration is only spent when gold alone cannot reach the quality.
local function ChoosePlan(order, slots, supplied)
	local cheap = BuildPlan(slots, supplied, PickCheapest)
	if cheap.missingSlot or not order.isKnown or not order.supportsQualities or order.minQuality <= 0 then
		return cheap
	end

	local best = BuildPlan(slots, supplied, PickBest)
	local attempts = {
		{ cheap, false },
		{ best, false },
		{ cheap, true },
		{ best, true },
	}
	for _, attempt in ipairs(attempts) do
		local plan, useConcentration = attempt[1], attempt[2]
		local reached, cost, currencyID = Model.ReachesQuality(order, plan.checkReagents, useConcentration)
		if reached then
			plan.useConcentration = useConcentration
			plan.usesBestMaterials = plan == best
			plan.concentrationCost = cost
			plan.concentrationCurrencyID = currencyID
			return plan
		end
	end

	cheap.unreachable = true
	return cheap
end

-- Rewards -------------------------------------------------------------------

local function BuildReward(rawOrder)
	local gold = math.max(0, (rawOrder.tipAmount or 0) - (rawOrder.consortiumCut or 0))
	local reward = {
		gold = gold,
		value = gold,
		complete = true,
		items = {},
	}

	for _, rewardInfo in ipairs(rawOrder.npcOrderRewards or EMPTY) do
		local entry = {
			count = rewardInfo.count or 1,
			itemLink = rewardInfo.itemLink,
			currencyID = rewardInfo.currencyType,
		}
		local itemID = ns.ItemIDFromLink(rewardInfo.itemLink)
		if itemID then
			entry.itemID = itemID
			entry.icon = C_Item.GetItemIconByID(itemID)
			if itemID == ns.AUGMENT_RUNE_ITEM_ID then
				reward.hasAugmentRune = true
			end
			local tradeable = Pricing:IsTradeable(itemID)
			if tradeable == nil then
				reward.complete = false
				reward.waitingForItemData = true
			elseif tradeable then
				local price = Pricing:GetUnitPrice(itemID, rewardInfo.itemLink, "reward")
				if price then
					entry.value = price * entry.count
					reward.value = reward.value + entry.value
				else
					reward.complete = false
				end
			end
		elseif entry.currencyID then
			local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(entry.currencyID)
			entry.icon = currencyInfo and currencyInfo.iconFileID
			entry.name = currencyInfo and currencyInfo.name
		end
		reward.items[#reward.items + 1] = entry
	end

	return reward
end

-- Orders --------------------------------------------------------------------

function Model.Build(rawOrder)
	local order = {
		raw = rawOrder,
		orderID = rawOrder.orderID,
		expirationTime = rawOrder.expirationTime or 0,
		minQuality = rawOrder.minQuality or 0,
		isRecraft = not not rawOrder.isRecraft,
		outputLink = rawOrder.outputItemHyperlink,
		reward = BuildReward(rawOrder),
	}

	local recipeInfo = rawOrder.spellID and C_TradeSkillUI.GetRecipeInfo(rawOrder.spellID)
	if recipeInfo then
		order.recipeID = recipeInfo.recipeID
		order.name = recipeInfo.name
		order.icon = recipeInfo.icon
		order.isKnown = not not recipeInfo.learned
		order.supportsQualities = not not recipeInfo.supportsQualities
		order.maxQuality = recipeInfo.maxQuality
		if order.minQuality <= LowestRecipeQuality(recipeInfo) then
			order.minQuality = 0
		end
	else
		order.name = rawOrder.spellID and C_Spell.GetSpellName(rawOrder.spellID)
		order.icon = rawOrder.spellID and C_Spell.GetSpellTexture(rawOrder.spellID)
	end
	order.name = order.name or ""

	if order.recipeID then
		local schematic = C_TradeSkillUI.GetRecipeSchematic(order.recipeID, order.isRecraft)
		order.slots, order.supplied = CollectSlots(schematic, rawOrder)
		order.plan = ChoosePlan(order, order.slots, order.supplied)
	else
		order.slots, order.supplied = EMPTY, EMPTY
		order.plan = BuildPlan(EMPTY, EMPTY, PickCheapest)
	end

	order.cost = order.plan.cost
	order.needsConcentration = not not order.plan.useConcentration
	order.profit = order.reward.value - order.cost
	order.profitComplete = order.reward.complete and order.plan.costComplete and Pricing:HasProvider()
	order.waitingForItemData = order.reward.waitingForItemData

	return order
end

local function IsOnCooldown(recipeID)
	if not C_TradeSkillUI.GetRecipeCooldown then
		return false
	end
	local cooldown, _, charges, maxCharges = C_TradeSkillUI.GetRecipeCooldown(recipeID)
	if not (cooldown and cooldown > 0) then
		return false
	end
	return not (maxCharges and maxCharges > 0 and charges and charges > 0)
end

local function OwnedCount(itemID)
	return C_Item.GetItemCount(itemID, true, false, true, true)
end

-- First required material you do not own enough of (any quality counts),
-- as name, owned, needed. Bags, bank, and warband bank are included.
local function FindMissingMaterial(order)
	for index, slot in ipairs(order.slots or EMPTY) do
		if slot.quantity > 0 and #slot.options > 0 then
			local owned = 0
			for _, option in ipairs(slot.options) do
				owned = owned + OwnedCount(option.itemID)
			end
			if owned < slot.quantity then
				local itemID = (order.plan.picks[index] or slot.options[1]).itemID
				local name = C_Item.GetItemNameByID(itemID)
				if not name then
					C_Item.RequestLoadItemDataByID(itemID)
					name = L.UNKNOWN_ITEM:format(itemID)
				end
				return name, owned, slot.quantity
			end
		end
	end
	return nil
end

-- Reasons the order cannot be crafted at all. Evaluated live because
-- concentration, cooldowns, and owned materials change while the list is open.
-- The second return is true when the blocked order keeps its sort position
-- (missing materials only), so the list does not reshuffle as bags change.
function Model.GetBlocker(order)
	if not order.recipeID then
		return L.REASON_NO_RECIPE
	elseif not order.isKnown then
		return L.REASON_UNKNOWN
	elseif order.isRecraft then
		return L.REASON_RECRAFT
	elseif order.plan.missingSlot then
		return L.REASON_MISSING_SLOT
	elseif order.plan.unreachable then
		return L.REASON_QUALITY
	elseif IsOnCooldown(order.recipeID) then
		return L.REASON_COOLDOWN
	end
	local missingName, owned, needed = FindMissingMaterial(order)
	if missingName then
		return L.REASON_MISSING_MATERIALS:format(missingName, owned, needed), true
	elseif order.needsConcentration and not ns.GetConfig("allowConcentration") then
		-- "Allow concentration" gates spending it; such orders sink.
		return L.REASON_CONCENTRATION_NOT_ALLOWED
	elseif order.profit < 0 and not ns.GetConfig("allowUnprofitable") then
		-- Uses the estimate even when some prices are missing.
		return L.REASON_UNPROFITABLE_NOT_ALLOWED
	elseif order.needsConcentration
		and Model.GetCurrencyQuantity(order.plan.concentrationCurrencyID) < order.plan.concentrationCost then
		return L.REASON_CONCENTRATION
	end
	return nil
end

-- Craft-time reagents: fills each quality slot from what you own (bags, bank,
-- warband bank), preferring the planned quality, then higher, then lower.
-- Returns nil when owned stock cannot cover the plan at the required quality;
-- the caller then crafts with the plan as-is and the game reports shortages.
function Model.BuildOwnedReagents(order)
	local plan = order.plan
	local craftReagents = {}
	local checkReagents = {}
	for _, reagent in ipairs(order.supplied) do
		checkReagents[#checkReagents + 1] = reagent
	end

	local used = {}
	for index, slot in ipairs(order.slots) do
		local picked = plan.picks[index]
		if slot.mutable and picked then
			local candidates = { picked }
			for _, option in ipairs(slot.options) do
				if option.quality > picked.quality then
					candidates[#candidates + 1] = option
				end
			end
			for position = #slot.options, 1, -1 do
				local option = slot.options[position]
				if option.quality < picked.quality then
					candidates[#candidates + 1] = option
				end
			end

			local remaining = slot.quantity
			for _, option in ipairs(candidates) do
				if remaining <= 0 then
					break
				end
				local owned = C_Item.GetItemCount(option.itemID, true, false, true, true) - (used[option.itemID] or 0)
				local take = math.min(remaining, owned)
				if take > 0 then
					used[option.itemID] = (used[option.itemID] or 0) + take
					remaining = remaining - take
					local reagent = NewReagent(option.itemID, slot.dataSlotIndex, take)
					craftReagents[#craftReagents + 1] = reagent
					checkReagents[#checkReagents + 1] = reagent
				end
			end
			if remaining > 0 then
				return nil
			end
		end
	end

	if order.minQuality > 0 and order.supportsQualities then
		local reached, cost, currencyID = Model.ReachesQuality(order, checkReagents, plan.useConcentration)
		if not reached then
			return nil
		end
		if plan.useConcentration and Model.GetCurrencyQuantity(currencyID) < cost then
			return nil
		end
	end

	return craftReagents
end

-- Sorting -------------------------------------------------------------------

local DEFAULT_ASCENDING = {
	order = true,
	time = true,
}

function Model.GetDefaultAscending(sortKey)
	return DEFAULT_ASCENDING[sortKey] or false
end

local function SortValue(order, sortKey)
	if sortKey == "order" then
		return order.name
	elseif sortKey == "reward" then
		return order.reward.value
	elseif sortKey == "cost" then
		return order.cost
	elseif sortKey == "time" then
		return order.expirationTime
	end
	return order.profit
end

-- Priority, highest first: craftable before blocked, then the optional
-- non-concentration / profitable tiers, then the column sort.
-- "frozenRanks" (orderID string -> position) keeps the current on-screen order
-- while a craft is in progress so rows never move under the mouse; orders not
-- yet on screen go after them in normal priority order.
function Model.Sort(orders, frozenRanks)
	local sortKey = ns.GetConfig("sortKey")
	local ascending = ns.GetConfig("sortAscending")
	local preferNoConcentration = ns.GetConfig("prioritizeNonConcentration")
	local preferProfitable = ns.GetConfig("prioritizeProfitable")

	for _, order in ipairs(orders) do
		local blocker, keepsPosition = Model.GetBlocker(order)
		order.blocker = blocker
		order.sinks = blocker ~= nil and not keepsPosition
		order.frozenRank = frozenRanks and frozenRanks[tostring(order.orderID)] or nil
	end

	table.sort(orders, function(left, right)
		if frozenRanks then
			local leftRank, rightRank = left.frozenRank, right.frozenRank
			if leftRank and rightRank then
				return leftRank < rightRank
			elseif leftRank or rightRank then
				return leftRank ~= nil
			end
		end
		if left.sinks ~= right.sinks then
			return right.sinks
		end
		if preferNoConcentration and left.needsConcentration ~= right.needsConcentration then
			return right.needsConcentration
		end
		if preferProfitable then
			local leftProfitable, rightProfitable = left.profit > 0, right.profit > 0
			if leftProfitable ~= rightProfitable then
				return leftProfitable
			end
		end

		local leftValue, rightValue = SortValue(left, sortKey), SortValue(right, sortKey)
		if leftValue ~= rightValue then
			if ascending then
				return leftValue < rightValue
			end
			return leftValue > rightValue
		end
		if left.name ~= right.name then
			return left.name < right.name
		end
		return tostring(left.orderID) < tostring(right.orderID)
	end)
end

local _, ns = ...
local L = ns.L
local Model = ns.Model

-- One-click patron flow: Craft (claim) -> Craft (craft) -> Complete, with
-- Release available while an order is claimed. All server calls are the same
-- ones Blizzard's own order view makes.

local BUSY_TIMEOUT = 15
-- Every button shares the same spot through the flow, so a short lockout stops
-- a double-click from claiming and crafting in one go.
local CLICK_LOCKOUT = 0.5

local Craft = {}
ns.Craft = Craft

local function NotifyChanged()
	if ns.Pane then
		ns.Pane:RefreshButtons()
	end
end

function Craft.GetClaimedOrder()
	local claimed = C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
	if claimed and claimed.orderID then
		return claimed
	end
	return nil
end

-- The claimed order only matters to this list when it is a patron order.
function Craft.GetClaimedPatronOrder()
	local claimed = Craft.GetClaimedOrder()
	if claimed and (claimed.orderType == nil or claimed.orderType == ns.ORDER_TYPE_NPC) then
		return claimed
	end
	return nil
end

local function GetProfession()
	local info = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	return info and info.profession
end

local function GetBusy()
	local busy = Craft.busy
	if busy and GetTime() > busy.expiresAt then
		Craft.busy = nil
		return nil
	end
	return busy
end

local function SetBusy(orderID, action)
	local busy = { orderID = orderID, action = action, expiresAt = GetTime() + BUSY_TIMEOUT }
	Craft.busy = busy
	C_Timer.After(BUSY_TIMEOUT + 0.1, function()
		if Craft.busy == busy then
			Craft.busy = nil
			NotifyChanged()
		end
	end)
end

-- Returns true when the server answer belongs to an action we started.
local function ClearBusy(action, orderID)
	local busy = Craft.busy
	if not busy or (action and busy.action ~= action) then
		return false
	end
	if orderID ~= nil and not ns.IsSameOrderID(busy.orderID, orderID) then
		return false
	end
	Craft.busy = nil
	return true
end

local function LockClicks()
	local lock = {}
	Craft.clickLock = lock
	C_Timer.After(CLICK_LOCKOUT, function()
		if Craft.clickLock == lock then
			Craft.clickLock = nil
			NotifyChanged()
		end
	end)
end

local function CraftHint(order)
	if order.needsConcentration then
		return L.HINT_CRAFT_CONCENTRATION:format(order.plan.concentrationCost)
	end
	return L.HINT_CRAFT
end

-- Describes both buttons for a row:
-- { primary = { text, enabled, action, tooltip }, secondary = { ... } or nil }
function Craft.GetButtonState(order)
	local claimed = Craft.GetClaimedOrder()
	local busy = GetBusy()
	local isMine = claimed and ns.IsSameOrderID(claimed.orderID, order.orderID)
	local busyHere = busy and ns.IsSameOrderID(busy.orderID, order.orderID)
	local primary = { text = L.BUTTON_CRAFT }
	local state = { primary = primary }

	if isMine and claimed.isFulfillable then
		primary.text = L.BUTTON_COMPLETE
		if busyHere then
			primary.text = busy.action == "complete" and L.BUTTON_COMPLETING or primary.text
			primary.tooltip = L.REASON_BUSY
		else
			primary.enabled, primary.action, primary.tooltip = true, "complete", L.HINT_COMPLETE
		end
	elseif isMine then
		local secondary = { text = L.BUTTON_RELEASE }
		state.secondary = secondary
		if busyHere then
			if busy.action == "craft" then
				primary.text = L.BUTTON_CRAFTING
			elseif busy.action == "release" then
				secondary.text = L.BUTTON_RELEASING
			end
			primary.tooltip, secondary.tooltip = L.REASON_BUSY, L.REASON_BUSY
		else
			local blocker = Model.GetBlocker(order)
			primary.enabled, primary.action = blocker == nil, "craft"
			primary.tooltip = blocker or CraftHint(order)
			secondary.enabled, secondary.action, secondary.tooltip = true, "release", L.HINT_RELEASE
		end
	elseif busyHere and busy.action == "claim" then
		primary.text, primary.tooltip = L.BUTTON_CLAIMING, L.REASON_BUSY
	elseif claimed then
		primary.tooltip = L.REASON_OTHER_CLAIMED
	elseif busy then
		primary.tooltip = L.REASON_BUSY
	else
		local blocker = Model.GetBlocker(order)
		primary.enabled, primary.action = blocker == nil, "claim"
		primary.tooltip = blocker or L.HINT_CLAIM
	end

	if Craft.clickLock then
		primary.enabled = false
		if state.secondary then
			state.secondary.enabled = false
		end
	end
	return state
end

local actions = {}

function actions.claim(order)
	local profession = GetProfession()
	if not profession then
		ns.ShowError(L.REASON_NO_PROFESSION)
		return
	end
	SetBusy(order.orderID, "claim")
	C_CraftingOrders.ClaimOrder(order.orderID, profession)
end

function actions.craft(order, claimed)
	if claimed.isFulfillable then
		return
	end
	local reagents = Model.BuildOwnedReagents(order) or order.plan.craftReagents
	SetBusy(claimed.orderID, "craft")
	C_TradeSkillUI.CraftRecipe(order.recipeID, 1, reagents, nil, claimed.orderID, order.plan.useConcentration)
end

function actions.complete(_, claimed)
	local profession = GetProfession()
	if not (profession and claimed.isFulfillable) then
		return
	end
	SetBusy(claimed.orderID, "complete")
	C_CraftingOrders.FulfillOrder(claimed.orderID, "", profession)
end

function actions.release(_, claimed)
	local profession = GetProfession()
	if not profession then
		ns.ShowError(L.REASON_NO_PROFESSION)
		return
	end
	SetBusy(claimed.orderID, "release")
	C_CraftingOrders.ReleaseOrder(claimed.orderID, profession)
end

function Craft.Perform(order, action)
	-- Re-check the live state: the list may be stale relative to the server.
	local state = Craft.GetButtonState(order)
	local button = state.primary.action == action and state.primary
		or (state.secondary and state.secondary.action == action and state.secondary)
	if not (button and button.enabled) then
		if button and button.tooltip then
			ns.ShowError(button.tooltip)
		end
		NotifyChanged()
		return
	end

	LockClicks()
	local claimed = Craft.GetClaimedOrder()
	if action == "claim" then
		actions.claim(order)
	elseif claimed then
		actions[action](order, claimed)
	end
	NotifyChanged()
end

-- Server responses ----------------------------------------------------------

local function IsOk(result)
	return result == Enum.CraftingOrderResult.Ok
end

local function ClaimFailedMessage(result)
	local results = Enum.CraftingOrderResult
	if result == results.CannotClaimOwnOrder and PROFESSIONS_ORDER_CANNOT_CLAIM_OWN_ORDER then
		return PROFESSIONS_ORDER_CANNOT_CLAIM_OWN_ORDER
	elseif result == results.OutOfPublicOrderCapacity and PROFESSIONS_ORDER_FAILED_NO_CLAIMS then
		return PROFESSIONS_ORDER_FAILED_NO_CLAIMS
	end
	return PROFESSIONS_ORDER_NOT_AVAILABLE or L.ERROR_FAILED
end

local function GenericFailedMessage()
	return PROFESSIONS_ORDER_OP_FAILED or L.ERROR_FAILED
end

function Craft.InitializeEvents()
	ns.RegisterEvent("CRAFTINGORDERS_CLAIM_ORDER_RESPONSE", function(_, result, orderID)
		if ClearBusy("claim", orderID) and not IsOk(result) then
			ns.ShowError(ClaimFailedMessage(result))
		end
		NotifyChanged()
	end)
	ns.RegisterEvent("CRAFTINGORDERS_RELEASE_ORDER_RESPONSE", function(_, result, orderID)
		if ClearBusy("release", orderID) and not IsOk(result) then
			ns.ShowError(GenericFailedMessage())
		end
		NotifyChanged()
	end)
	ns.RegisterEvent("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", function(_, result, orderID)
		if ClearBusy("complete", orderID) and not IsOk(result) then
			ns.ShowError(GenericFailedMessage())
		end
		NotifyChanged()
	end)
	-- Blizzard only sends this event when a craft for an order fails.
	ns.RegisterEvent("CRAFTINGORDERS_CRAFT_ORDER_RESPONSE", function(_, _, orderID)
		if ClearBusy("craft", orderID) then
			ns.ShowError(GenericFailedMessage())
		end
		NotifyChanged()
	end)
	ns.RegisterEvent("CRAFTINGORDERS_CLAIMED_ORDER_ADDED", function()
		ClearBusy("claim")
		ns.Pane:OnClaimedOrderChanged(false)
	end)
	ns.RegisterEvent("CRAFTINGORDERS_CLAIMED_ORDER_UPDATED", function()
		ClearBusy("craft")
		ns.Pane:OnClaimedOrderChanged(false)
	end)
	ns.RegisterEvent("CRAFTINGORDERS_CLAIMED_ORDER_REMOVED", function()
		ClearBusy("complete")
		ClearBusy("release")
		ns.Pane:OnClaimedOrderChanged(true)
	end)

	local function OnSpellcastStopped(_, unit)
		if unit == "player" and ClearBusy("craft") then
			NotifyChanged()
		end
	end
	ns.RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", OnSpellcastStopped)
	ns.RegisterEvent("UNIT_SPELLCAST_FAILED", OnSpellcastStopped)
end

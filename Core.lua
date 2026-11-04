local addonName, ns = ...

ns.ADDON_NAME = addonName
ns.ORDER_TYPE_NPC = Enum.CraftingOrderType and Enum.CraftingOrderType.Npc
ns.AUGMENT_RUNE_ITEM_ID = 259085 -- Void-Touched Augment Rune
ns.EMPTY = {}

local DEFAULTS = {
	allowConcentration = false,
	prioritizeNonConcentration = true,
	prioritizeProfitable = true,
	sortKey = "profit",
	sortAscending = false,
	pricingSource = "auto",
}

-- Event dispatch ------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local handlers = eventHandlers[event]
	if not handlers then
		return
	end
	for index = 1, #handlers do
		handlers[index](event, ...)
	end
end)

function ns.RegisterEvent(event, handler)
	local handlers = eventHandlers[event]
	if not handlers then
		handlers = {}
		eventHandlers[event] = handlers
		eventFrame:RegisterEvent(event)
	end
	handlers[#handlers + 1] = handler
end

-- Config --------------------------------------------------------------------

local configListeners = {}

function ns.GetConfig(key)
	local db = RapidPatronOrdersDB
	local value = db and db[key]
	if value == nil then
		return DEFAULTS[key]
	end
	return value
end

function ns.SetConfig(key, value)
	if not RapidPatronOrdersDB then
		return
	end
	if RapidPatronOrdersDB[key] == value then
		return
	end
	RapidPatronOrdersDB[key] = value
	for index = 1, #configListeners do
		configListeners[index](key, value)
	end
end

function ns.OnConfigChanged(listener)
	configListeners[#configListeners + 1] = listener
end

local function InitializeDatabase()
	if type(RapidPatronOrdersDB) ~= "table" then
		RapidPatronOrdersDB = {}
	end
	-- v0.1.0 stored this toggle as "enableCrafting".
	if RapidPatronOrdersDB.enableCrafting ~= nil then
		if RapidPatronOrdersDB.allowConcentration == nil then
			RapidPatronOrdersDB.allowConcentration = RapidPatronOrdersDB.enableCrafting
		end
		RapidPatronOrdersDB.enableCrafting = nil
	end
	for key, value in pairs(DEFAULTS) do
		if RapidPatronOrdersDB[key] == nil then
			RapidPatronOrdersDB[key] = value
		end
	end
end

-- Shared helpers -----------------------------------------------------------

function ns.IsAddOnLoaded(name)
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) or false
end

function ns.IsSameOrderID(left, right)
	-- Order IDs can exceed exact double precision in string form; compare as text.
	return left ~= nil and right ~= nil and tostring(left) == tostring(right)
end

function ns.ItemIDFromLink(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

function ns.ShowError(message)
	if message and UIErrorsFrame then
		UIErrorsFrame:AddExternalErrorMessage(message)
	end
end

-- Lifecycle -----------------------------------------------------------------

local professionsReady = false

local function TryStartPane()
	if professionsReady or not ns.Pane or not ns.IsAddOnLoaded("Blizzard_Professions") then
		return
	end
	professionsReady = true

	if ns.IsAddOnLoaded("CraftingOrders++") then
		print(ns.L.CONFLICT_WARNING)
		return
	end

	ns.Pane:Initialize()
end

ns.RegisterEvent("ADDON_LOADED", function(_, loadedName)
	if loadedName == addonName then
		InitializeDatabase()
		if ns.Options then
			ns.Options:Initialize()
		end
	elseif loadedName == "Blizzard_Professions" then
		TryStartPane()
	end
end)

ns.RegisterEvent("PLAYER_LOGIN", TryStartPane)

SLASH_RAPIDPATRONORDERS1 = "/rpo"
SlashCmdList.RAPIDPATRONORDERS = function()
	if ns.Options then
		ns.Options:Open()
	end
end

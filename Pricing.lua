local addonName, ns = ...
local L = ns.L

-- Each provider answers unit prices in copper, or nil when it has no data.
-- "purpose" is "material" (what it costs us) or "reward" (what we could sell for).

local function PositiveNumber(value)
	value = tonumber(value)
	if value and value > 0 then
		return value
	end
	return nil
end

local function TSMItemString(itemID, itemLink)
	if TSM_API.ToItemString then
		local ok, itemString = pcall(TSM_API.ToItemString, itemLink or ("item:" .. itemID))
		if ok and itemString then
			return itemString
		end
	end
	return "i:" .. itemID
end

local function TSMValue(source, itemString)
	local ok, value = pcall(TSM_API.GetCustomPriceValue, source, itemString)
	return ok and PositiveNumber(value) or nil
end

local providers = {
	{
		key = "tsm",
		label = L.PROVIDER_TSM,
		IsAvailable = function()
			return type(TSM_API) == "table" and type(TSM_API.GetCustomPriceValue) == "function"
		end,
		GetPrice = function(itemID, itemLink, purpose)
			local itemString = TSMItemString(itemID, itemLink)
			local market = TSMValue("DBMarket", itemString)
			if purpose == "material" then
				-- Vendor-sold materials are cheaper from the vendor than the AH.
				local vendor = TSMValue("VendorBuy", itemString)
				if vendor and (not market or vendor < market) then
					return vendor
				end
			end
			return market
		end,
	},
	{
		key = "auctionator",
		label = L.PROVIDER_AUCTIONATOR,
		IsAvailable = function()
			local api = Auctionator and Auctionator.API and Auctionator.API.v1
			return type(api) == "table" and type(api.GetAuctionPriceByItemID) == "function"
		end,
		GetPrice = function(itemID, itemLink)
			local api = Auctionator.API.v1
			local ok, value
			if itemLink and type(api.GetAuctionPriceByItemLink) == "function" then
				ok, value = pcall(api.GetAuctionPriceByItemLink, addonName, itemLink)
				if ok and PositiveNumber(value) then
					return PositiveNumber(value)
				end
			end
			ok, value = pcall(api.GetAuctionPriceByItemID, addonName, itemID)
			return ok and PositiveNumber(value) or nil
		end,
	},
	{
		key = "auctioneer",
		label = L.PROVIDER_AUCTIONEER,
		IsAvailable = function()
			return type(AucAdvanced) == "table"
				and type(AucAdvanced.API) == "table"
				and type(AucAdvanced.API.GetMarketValue) == "function"
		end,
		GetPrice = function(itemID, itemLink)
			local link = itemLink or select(2, C_Item.GetItemInfo(itemID))
			if not link then
				return nil
			end
			local ok, value = pcall(AucAdvanced.API.GetMarketValue, link)
			return ok and PositiveNumber(value) or nil
		end,
	},
}

local Pricing = {
	providers = providers,
}
ns.Pricing = Pricing

function Pricing:GetActiveProvider()
	local wanted = ns.GetConfig("pricingSource")
	local firstAvailable
	for _, provider in ipairs(providers) do
		if provider.IsAvailable() then
			if provider.key == wanted then
				return provider
			end
			firstAvailable = firstAvailable or provider
		end
	end
	return firstAvailable
end

function Pricing:HasProvider()
	return self:GetActiveProvider() ~= nil
end

-- Returns the unit price in copper, or nil when unknown.
function Pricing:GetUnitPrice(itemID, itemLink, purpose)
	local provider = self:GetActiveProvider()
	if not (provider and itemID) then
		return nil
	end
	return provider.GetPrice(itemID, itemLink, purpose)
end

-- Soulbound rewards cannot be sold, so they add no gold value.
-- Returns true/false, or nil while item data is still loading.
function Pricing:IsTradeable(itemID)
	local bindType = select(14, C_Item.GetItemInfo(itemID))
	if bindType == nil then
		if C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(itemID)
		end
		return nil
	end
	local binds = Enum.ItemBind
	return bindType == binds.None or bindType == binds.OnEquip or bindType == binds.OnUse
end

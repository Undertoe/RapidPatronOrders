local _, ns = ...

-- English strings. Missing keys fall back to the key name so a typo is visible
-- instead of erroring.
ns.L = setmetatable({
	ADDON_TITLE = "Rapid Patron Orders",
	ADDON_DESCRIPTION = "Replaces the Patron crafting-orders list with a profit-ranked list and one-click Craft buttons.",

	OPTION_ALLOW_CONCENTRATION = "Allow concentration",
	OPTION_ALLOW_CONCENTRATION_DESC = "Lets the Craft buttons spend concentration. When unticked, orders that need concentration to reach their required quality cannot be crafted from the list and sink to the bottom.",
	OPTION_ALLOW_UNPROFITABLE = "Allow unprofitable crafts",
	OPTION_ALLOW_UNPROFITABLE_DESC = "Lets the Craft buttons craft orders whose estimated profit is negative. When unticked, those orders cannot be crafted from the list and sink to the bottom.",
	REASON_UNPROFITABLE_NOT_ALLOWED = "Loses gold. Tick \"Allow unprofitable crafts\" to craft this order.",
	OPTION_PRIORITY_HEADER = "List priority",
	OPTION_PRIORITY_DESC = "Orders you cannot craft always sink to the bottom. These options shape the order of everything above them, before the selected column sort is applied.",
	OPTION_PRIORITIZE_NON_CONCENTRATION = "Prioritize non-concentration",
	OPTION_PRIORITIZE_NON_CONCENTRATION_DESC = "Orders that reach their quality without concentration are listed first.",
	OPTION_PRIORITIZE_PROFITABLE = "Prioritize profitable",
	OPTION_PRIORITIZE_PROFITABLE_DESC = "Orders with a positive estimated profit are listed before break-even or losing orders.",
	OPTION_PRICING_HEADER = "Pricing source",
	OPTION_PRICING_AUTO = "Automatic (first available)",
	OPTION_PRICING_NOT_DETECTED = "%s (not detected)",
	OPTION_PRICING_NONE = "No pricing addon detected. Install TradeSkillMaster, Auctionator, or Auctioneer to see costs and profit.",

	PROVIDER_TSM = "TradeSkillMaster",
	PROVIDER_AUCTIONATOR = "Auctionator",
	PROVIDER_AUCTIONEER = "Auctioneer",

	COLUMN_ORDER = "Order",
	COLUMN_REWARD = "Reward",
	COLUMN_COST = "Cost",
	COLUMN_PROFIT = "Profit",
	COLUMN_TIME = "Time",

	REFRESH = "Refresh",
	STATE_LOADING = "Loading patron orders...",
	STATE_EMPTY = "No patron orders available.",
	STATE_FAILED = "Patron orders could not be loaded. Try Refresh.",
	CONFLICT_WARNING = "Rapid Patron Orders: Crafting Orders++ is also enabled. Both replace the Patron list, so Rapid Patron Orders stays inactive. Disable one of them and /reload.",

	TOOLTIP_COST_HEADER = "Materials you supply",
	TOOLTIP_COST_NONE = "The patron supplies every required material.",
	TOOLTIP_PRICE_UNKNOWN = "no price",
	TOOLTIP_REWARD_GOLD = "Gold",
	TOOLTIP_REWARD_UNPRICED = "Not tradeable / no price",
	TOOLTIP_PROFIT_PARTIAL = "Some prices are missing; this estimate is incomplete.",
	TOOLTIP_CONCENTRATION = "Needs %d concentration to reach the required quality.",
	DETAIL_CONCENTRATION = "Concentration: %d",
	TOOLTIP_BEST_REAGENTS = "Needs top-quality materials to reach the required quality.",
	TOOLTIP_AUGMENT = "Rewards a Void-Touched Augment Rune.",
	TOOLTIP_MIN_QUALITY = "Required quality: %s",

	BUTTON_CRAFT = "Craft",
	BUTTON_COMPLETE = "Complete",
	BUTTON_RELEASE = "Release",
	BUTTON_CLAIMING = "Claiming...",
	BUTTON_CRAFTING = "Crafting...",
	BUTTON_COMPLETING = "Completing...",
	BUTTON_RELEASING = "Releasing...",

	HINT_CLAIM = "Claim this order. Click Craft again to craft it.",
	HINT_CRAFT = "Craft this order with the cheapest materials that reach its quality.",
	HINT_CRAFT_CONCENTRATION = "Craft this order, spending %d concentration.",
	HINT_COMPLETE = "Turn in the crafted order.",
	HINT_RELEASE = "Release this order back to the patron list.",

	REASON_CONCENTRATION_NOT_ALLOWED = "Needs concentration. Tick \"Allow concentration\" to spend it on this order.",
	REASON_UNKNOWN = "You have not learned this recipe.",
	REASON_RECRAFT = "Recraft orders must be opened to craft.",
	REASON_COOLDOWN = "This recipe is on cooldown.",
	REASON_QUALITY = "The required quality cannot be reached.",
	REASON_MISSING_SLOT = "A required material slot has no usable material.",
	REASON_MISSING_MATERIALS = "Missing materials: %s (have %d of %d).",
	UNKNOWN_ITEM = "item %d",
	REASON_CONCENTRATION = "Not enough concentration.",
	REASON_NO_RECIPE = "Recipe information is not available.",
	REASON_OTHER_CLAIMED = "Complete or release your current order first.",
	REASON_BUSY = "Waiting for the server...",
	REASON_NO_PROFESSION = "Profession information is not available yet.",
	ERROR_FAILED = "The crafting order action failed.",
}, {
	__index = function(_, key)
		return key
	end,
})

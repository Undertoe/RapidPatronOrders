local _, ns = ...
local L = ns.L
local Model = ns.Model
local Craft = ns.Craft
local EMPTY = ns.EMPTY

-- The Patron-tab list. It sits over Blizzard's order list while the Patron
-- tab is selected and hands back to Blizzard on every other tab.

local ROW_HEIGHT = 65 -- Crafting Orders++ rows are 62; about 5% taller.
local HEADER_HEIGHT = 22
local ICON_SIZE = 44
local BUTTON_WIDTH = 82
local BUTTON_HEIGHT = 20
local SCROLLBAR_GAP = 18
local REWARD_ICON_SIZE = 20
local MAX_REWARD_ICONS = 4
local TIME_REFRESH_INTERVAL = 30
local REQUEST_TIMEOUT = 8
local INITIAL_REQUEST_DELAY = 1.5
local GLOW_COLOR = { 0.64, 0.21, 0.93 }
local SORT_ARROW_ATLAS = "auctionhouse-ui-sortarrow"
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"

-- Right-aligned columns. "left" is the distance from the row's right edge to
-- the column's left edge; the rightmost 92px hold the action buttons. The
-- order column takes whatever width is left.
local COLUMNS = {
	{ key = "reward", label = L.COLUMN_REWARD, left = 478, width = 150 },
	{ key = "cost", label = L.COLUMN_COST, left = 328, width = 86 },
	{ key = "profit", label = L.COLUMN_PROFIT, left = 242, width = 86 },
	{ key = "time", label = L.COLUMN_TIME, left = 156, width = 64 },
}
local ORDER_COLUMN_RIGHT = 482
local BLIZZARD_LIST_KEYS = { "OrderList", "SearchButton", "FavoritesSearchButton" }

local Pane = {
	orders = {},
	canRequest = true,
	hiddenBlizzardFrames = {},
}
ns.Pane = Pane

-- x offset (from the row's right edge) of a column's right edge.
local function ColumnRight(column)
	return -(column.left - column.width)
end

-- Formatting ----------------------------------------------------------------

local function FormatMoney(copper)
	local absolute = math.abs(copper)
	local text
	if absolute >= 10000 then
		text = BreakUpLargeNumbers(math.floor(absolute / 10000)) .. GOLD_ICON
	else
		text = GetMoneyString(absolute, true)
	end
	if copper < 0 then
		text = "-" .. text
	end
	return text
end

local function FormatTimeLeft(expirationTime)
	local seconds = math.max(0, expirationTime - C_CraftingOrders.GetCraftingOrderTime())
	local hours = math.floor(seconds / 3600)
	if hours >= 24 then
		return ("%dd %dh"):format(math.floor(hours / 24), hours % 24)
	end
	return ("%dh %dm"):format(hours, math.floor(seconds % 3600 / 60))
end

-- Midnight recipes use two quality tiers with their own "-12-" chat icons;
-- older recipes use the five-tier set. Falls back to plain text when the
-- atlas is missing rather than depending on Blizzard's helper signature.
local function QualityMarkup(quality, maxQuality)
	local atlases = { "Professions-ChatIcon-Quality-Tier%d", "Professions-ChatIcon-Quality-12-Tier%d" }
	if maxQuality and maxQuality <= 2 then
		atlases[1], atlases[2] = atlases[2], atlases[1]
	end
	for _, pattern in ipairs(atlases) do
		local atlas = pattern:format(quality)
		if C_Texture.GetAtlasInfo(atlas) then
			return CreateAtlasMarkup(atlas, 16, 16)
		end
	end
	return "Q" .. quality
end

local function GetOrdersPage()
	return ProfessionsFrame and ProfessionsFrame.OrdersPage
end

local function GetCurrentProfession()
	local ordersPage = GetOrdersPage()
	local info = ordersPage and ordersPage.professionInfo
	if info and info.profession then
		return info.profession
	end
	info = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	return info and info.profession
end

-- Tooltips ------------------------------------------------------------------

local function ShowTooltip(owner, build)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	build(GameTooltip)
	GameTooltip:Show()
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function BuildOrderTooltip(tooltip, order)
	if order.outputLink then
		tooltip:SetHyperlink(order.outputLink)
	else
		tooltip:SetText(order.name)
	end
	if order.minQuality > 0 then
		tooltip:AddLine(L.TOOLTIP_MIN_QUALITY:format(QualityMarkup(order.minQuality, order.maxQuality)), 1, 1, 1)
	end
	if order.needsConcentration then
		tooltip:AddLine(L.TOOLTIP_CONCENTRATION:format(order.plan.concentrationCost), 1, 0.82, 0)
	end
	if order.plan.usesBestMaterials then
		tooltip:AddLine(L.TOOLTIP_BEST_REAGENTS, 1, 0.82, 0)
	end
	if order.reward.hasAugmentRune then
		tooltip:AddLine(L.TOOLTIP_AUGMENT, 0.8, 0.5, 1)
	end
	local blocker = Model.GetBlocker(order)
	if blocker then
		tooltip:AddLine(blocker, 1, 0.3, 0.3, true)
	end
end

local function BuildCostTooltip(tooltip, order)
	tooltip:SetText(L.TOOLTIP_COST_HEADER)
	local any = false
	for index, slot in ipairs(order.slots) do
		local option = order.plan.picks[index]
		if option then
			any = true
			local name = C_Item.GetItemNameByID(option.itemID) or ("item:" .. option.itemID)
			local label = ("%dx %s"):format(slot.quantity, name)
			if option.quality > 0 then
				label = label .. " " .. QualityMarkup(option.quality, #slot.options)
			end
			local price = option.price and FormatMoney(option.price * slot.quantity) or L.TOOLTIP_PRICE_UNKNOWN
			tooltip:AddDoubleLine(label, price, 1, 1, 1, 1, 1, 1)
		end
	end
	if not any then
		tooltip:AddLine(L.TOOLTIP_COST_NONE, 1, 1, 1)
	end
end

local function BuildRewardTooltip(tooltip, order)
	tooltip:SetText(L.COLUMN_REWARD)
	if order.reward.gold > 0 then
		tooltip:AddDoubleLine(L.TOOLTIP_REWARD_GOLD, FormatMoney(order.reward.gold), 1, 1, 1, 1, 1, 1)
	end
	for _, item in ipairs(order.reward.items) do
		local name = item.itemLink or item.name or "?"
		local value = item.value and FormatMoney(item.value) or L.TOOLTIP_REWARD_UNPRICED
		tooltip:AddDoubleLine(("%dx %s"):format(item.count, name), value, 1, 1, 1, 0.8, 0.8, 0.8)
	end
end

local function BuildProfitTooltip(tooltip, order)
	tooltip:SetText(L.COLUMN_PROFIT)
	tooltip:AddDoubleLine(L.COLUMN_REWARD, FormatMoney(order.reward.value), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine(L.COLUMN_COST, FormatMoney(-order.cost), 1, 1, 1, 1, 1, 1)
	if not order.profitComplete then
		tooltip:AddLine(L.TOOLTIP_PROFIT_PARTIAL, 1, 0.82, 0, true)
	end
end

-- Rows ----------------------------------------------------------------------

local function CreateHoverRegion(row, column, build)
	local region = CreateFrame("Frame", nil, row)
	region:SetPoint("TOPRIGHT", row, "TOPRIGHT", ColumnRight(column), 0)
	region:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", ColumnRight(column), 0)
	region:SetWidth(column.width)
	-- Hover-only: clicks fall through to the row, which opens the order.
	region:SetMouseMotionEnabled(true)
	region:SetMouseClickEnabled(false)
	region:SetScript("OnEnter", function()
		if row.order then
			ShowTooltip(region, function(tooltip)
				build(tooltip, row.order)
			end)
		end
	end)
	region:SetScript("OnLeave", HideTooltip)
	return region
end

local function CreateColumnText(row, column, template)
	local text = row:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
	text:SetPoint("RIGHT", row, "RIGHT", ColumnRight(column), 0)
	text:SetWidth(column.width)
	text:SetJustifyH("CENTER")
	return text
end

local function CreateGlow(row)
	local glow = CreateFrame("Frame", nil, row)
	glow:SetAllPoints()
	glow:SetFrameLevel(row:GetFrameLevel() + 5)
	local thickness = 3
	local edges = {
		{ "TOPLEFT", "TOPRIGHT", nil, thickness },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness },
		{ "TOPLEFT", "BOTTOMLEFT", thickness, nil },
		{ "TOPRIGHT", "BOTTOMRIGHT", thickness, nil },
	}
	for _, edge in ipairs(edges) do
		local texture = glow:CreateTexture(nil, "OVERLAY")
		texture:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], 0.95)
		texture:SetBlendMode("ADD")
		texture:SetPoint(edge[1])
		texture:SetPoint(edge[2])
		if edge[3] then
			texture:SetWidth(edge[3])
		else
			texture:SetHeight(edge[4])
		end
	end

	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.35)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")
	glow.pulse = pulse
	glow:Hide()
	return glow
end

local function SetGlowShown(glow, shown)
	glow:SetShown(shown)
	if shown and not glow.pulse:IsPlaying() then
		glow.pulse:Play()
	elseif not shown then
		glow.pulse:Stop()
	end
end

local function CreateActionButton(row)
	local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	button:SetMotionScriptsWhileDisabled(true)
	button:SetScript("OnClick", function(self)
		if row.order and self.action then
			Craft.Perform(row.order, self.action)
		end
	end)
	button:SetScript("OnEnter", function(self)
		if self.tooltipText then
			ShowTooltip(self, function(tooltip)
				tooltip:SetText(self:GetText())
				tooltip:AddLine(self.tooltipText, 1, 1, 1, true)
			end)
		end
	end)
	button:SetScript("OnLeave", HideTooltip)
	return button
end

local function InitRow(row)
	if row.rpoInitialized then
		return
	end
	row.rpoInitialized = true
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")

	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints()

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(0.25, 0.55, 1, 0.12)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)

	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -4)
	row.name:SetPoint("RIGHT", row, "RIGHT", -ORDER_COLUMN_RIGHT, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -6)
	row.detail:SetPoint("RIGHT", row, "RIGHT", -ORDER_COLUMN_RIGHT, 0)
	row.detail:SetJustifyH("LEFT")
	row.detail:SetWordWrap(false)

	local rewardColumn, costColumn, profitColumn, timeColumn = COLUMNS[1], COLUMNS[2], COLUMNS[3], COLUMNS[4]
	row.rewardText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.rewardText:SetPoint("TOPRIGHT", row, "TOPRIGHT", ColumnRight(rewardColumn), -12)
	row.rewardText:SetWidth(rewardColumn.width)
	row.rewardText:SetJustifyH("CENTER")
	row.rewardIcons = {}
	for index = 1, MAX_REWARD_ICONS do
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(REWARD_ICON_SIZE, REWARD_ICON_SIZE)
		row.rewardIcons[index] = icon
	end
	row.costText = CreateColumnText(row, costColumn)
	row.profitText = CreateColumnText(row, profitColumn)
	row.timeText = CreateColumnText(row, timeColumn, "GameFontHighlightSmall")

	CreateHoverRegion(row, rewardColumn, BuildRewardTooltip)
	CreateHoverRegion(row, costColumn, BuildCostTooltip)
	CreateHoverRegion(row, profitColumn, BuildProfitTooltip)

	-- The primary button never moves, so Craft -> Craft -> Complete is
	-- clicked in one spot; Release appears above it while claimed.
	row.primaryButton = CreateActionButton(row)
	row.primaryButton:SetPoint("RIGHT", row, "RIGHT", -6, -(BUTTON_HEIGHT / 2 + 2))
	row.secondaryButton = CreateActionButton(row)
	row.secondaryButton:SetPoint("BOTTOM", row.primaryButton, "TOP", 0, 4)

	row.glow = CreateGlow(row)

	row:SetScript("OnClick", function(self)
		local ordersPage = GetOrdersPage()
		if self.order and ordersPage and ordersPage.ViewOrder then
			ordersPage:ViewOrder(self.order.raw)
		end
	end)
	row:SetScript("OnEnter", function(self)
		if self.order then
			ShowTooltip(self, function(tooltip)
				BuildOrderTooltip(tooltip, self.order)
			end)
		end
	end)
	row:SetScript("OnLeave", HideTooltip)
end

local function ApplyButtonState(button, info)
	if not info then
		button:Hide()
		button.action = nil
		return
	end
	button:Show()
	button:SetText(info.text)
	button:SetEnabled(not not info.enabled)
	button.action = info.action
	button.tooltipText = info.tooltip
end

local function UpdateRowButtons(row)
	local order = row.order
	if not order then
		return
	end
	local state = Craft.GetButtonState(order)
	ApplyButtonState(row.primaryButton, state.primary)
	ApplyButtonState(row.secondaryButton, state.secondary)
end

local function BuildDetailText(order, blocker)
	local parts = {}
	if order.minQuality > 0 then
		parts[#parts + 1] = QualityMarkup(order.minQuality, order.maxQuality)
	end
	if blocker then
		parts[#parts + 1] = "|cffff5555" .. blocker .. "|r"
	elseif order.needsConcentration then
		parts[#parts + 1] = ("|cffffd100%s|r"):format(L.DETAIL_CONCENTRATION:format(order.plan.concentrationCost))
	end
	return table.concat(parts, "  ")
end

local function UpdateRewardIcons(row, order)
	local rewardColumn = COLUMNS[1]
	local shown = 0
	local previous
	for _, item in ipairs(order.reward.items) do
		if item.icon and shown < MAX_REWARD_ICONS then
			shown = shown + 1
			local icon = row.rewardIcons[shown]
			icon:ClearAllPoints()
			if previous then
				icon:SetPoint("LEFT", previous, "RIGHT", 3, 0)
			else
				local inset = (rewardColumn.width - MAX_REWARD_ICONS * (REWARD_ICON_SIZE + 3)) / 2
				icon:SetPoint("TOPLEFT", row, "TOPRIGHT", -rewardColumn.left + inset, -32)
			end
			icon:SetTexture(item.icon)
			icon:Show()
			previous = icon
		end
	end
	for position = shown + 1, MAX_REWARD_ICONS do
		row.rewardIcons[position]:Hide()
	end
end

local function UpdateRow(row, order)
	row.order = order
	-- Missing materials only disable the button; the row keeps full color.
	local blocker, keepsPosition = Model.GetBlocker(order)

	row.background:SetColorTexture(1, 1, 1, (order.listIndex or 1) % 2 == 0 and 0.03 or 0.012)
	row.icon:SetTexture(order.icon or 134400)
	row.name:SetText(order.name)
	row.detail:SetText(BuildDetailText(order, blocker))

	row.rewardText:SetText(FormatMoney(order.reward.value))
	UpdateRewardIcons(row, order)

	row.costText:SetText(FormatMoney(order.cost))
	row.profitText:SetText(FormatMoney(order.profit))
	if order.profit > 0 then
		row.profitText:SetTextColor(0.25, 1, 0.25)
	elseif order.profit < 0 then
		row.profitText:SetTextColor(1, 0.3, 0.3)
	else
		row.profitText:SetTextColor(1, 1, 1)
	end
	-- Dimmed profit means some prices were missing.
	row.profitText:SetAlpha(order.profitComplete and 1 or 0.6)
	row.timeText:SetText(FormatTimeLeft(order.expirationTime))

	SetGlowShown(row.glow, not not order.reward.hasAugmentRune)
	row:SetAlpha((blocker and not keepsPosition) and 0.5 or 1)
	UpdateRowButtons(row)
end

-- Frame construction --------------------------------------------------------

function Pane:UpdateHeaderArrows()
	local sortKey = ns.GetConfig("sortKey")
	local ascending = ns.GetConfig("sortAscending")
	for _, header in ipairs(self.headers) do
		local active = header.sortKey == sortKey
		header.arrow:SetShown(active)
		if active then
			if header.arrow.SetTexCoord then
				-- The atlas points down; flip it for ascending.
				header.arrow:SetTexCoord(0, 1, ascending and 1 or 0, ascending and 0 or 1)
			else
				header.arrow:SetText(ascending and "^" or "v")
			end
		end
	end
end

local function CreateHeaderButton(parent, sortKey, label)
	local header = CreateFrame("Button", nil, parent)
	header.sortKey = sortKey
	header:SetHeight(HEADER_HEIGHT)
	header.label = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	header.label:SetPoint("CENTER", header, "CENTER", 0, 0)
	header.label:SetText(label)
	if C_Texture.GetAtlasInfo(SORT_ARROW_ATLAS) then
		header.arrow = header:CreateTexture(nil, "ARTWORK")
		header.arrow:SetAtlas(SORT_ARROW_ATLAS)
		header.arrow:SetSize(10, 6)
	else
		header.arrow = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	end
	header.arrow:SetPoint("LEFT", header.label, "RIGHT", 4, 0)
	header:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
	header:GetHighlightTexture():SetAlpha(0.25)
	header:SetScript("OnClick", function()
		if ns.GetConfig("sortKey") == sortKey then
			ns.SetConfig("sortAscending", not ns.GetConfig("sortAscending"))
		else
			-- Set the direction first so only one resort runs per click.
			RapidPatronOrdersDB.sortAscending = Model.GetDefaultAscending(sortKey)
			ns.SetConfig("sortKey", sortKey)
		end
	end)
	return header
end

-- A checkbox with its label to the right. The anchor arguments place the
-- label, so checkboxes can chain leftward along one row.
local function CreateToolbarCheckbox(toolbar, configKey, text, description, point, relativeTo, relativePoint, x, y)
	local checkbox = CreateFrame("CheckButton", nil, toolbar, "UICheckButtonTemplate")
	checkbox:SetSize(24, 24)
	local label = toolbar:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetText(text)
	label:SetPoint(point, relativeTo, relativePoint, x, y)
	checkbox:SetPoint("RIGHT", label, "LEFT", -2, 0)
	checkbox:SetScript("OnClick", function(self)
		ns.SetConfig(configKey, self:GetChecked())
	end)
	checkbox:SetScript("OnEnter", function(self)
		ShowTooltip(self, function(tooltip)
			tooltip:SetText(text)
			tooltip:AddLine(description, 1, 1, 1, true)
		end)
	end)
	checkbox:SetScript("OnLeave", HideTooltip)
	checkbox:SetChecked(ns.GetConfig(configKey))
	return checkbox
end

function Pane:BuildToolbar()
	-- Top-right of the pane: Refresh sits beside the order-type tabs, and the
	-- toggles share one row above it, right-aligned, below the title bar.
	local toolbar = CreateFrame("Frame", nil, self.root)
	toolbar:SetSize(420, 50)
	toolbar:SetPoint("BOTTOMRIGHT", self.root, "TOPRIGHT", -2, 4)
	toolbar:SetFrameLevel(self.root:GetFrameLevel() + 20)

	local refresh = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
	refresh:SetSize(70, 22)
	refresh:SetPoint("BOTTOMRIGHT")
	refresh:SetText(L.REFRESH)
	refresh:SetScript("OnClick", function()
		Pane:RequestOrders()
	end)
	self.refreshButton = refresh

	local concentration = CreateToolbarCheckbox(
		toolbar, "allowConcentration", L.OPTION_ALLOW_CONCENTRATION, L.OPTION_ALLOW_CONCENTRATION_DESC,
		"BOTTOMRIGHT", refresh, "TOPRIGHT", 0, 7
	)
	local unprofitable = CreateToolbarCheckbox(
		toolbar, "allowUnprofitable", L.OPTION_ALLOW_UNPROFITABLE, L.OPTION_ALLOW_UNPROFITABLE_DESC,
		"RIGHT", concentration, "LEFT", -14, 0
	)
	self.toolbarCheckboxes = {
		allowConcentration = concentration,
		allowUnprofitable = unprofitable,
	}
end

function Pane:BuildFrame()
	local ordersPage = GetOrdersPage()
	local browseFrame = ordersPage and ordersPage.BrowseFrame
	if not browseFrame then
		return false
	end

	local root = CreateFrame("Frame", "RapidPatronOrdersPane", browseFrame)
	self.root = root
	if browseFrame.OrderList then
		root:SetAllPoints(browseFrame.OrderList)
	else
		root:SetSize(800, 540)
		root:SetPoint("BOTTOMRIGHT", browseFrame, "BOTTOMRIGHT", -2, 3)
	end
	root:SetFrameLevel(browseFrame:GetFrameLevel() + 10)
	root:Hide()

	local background = root:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.03, 0.03, 0.04, 0.85)

	local header = CreateFrame("Frame", nil, root)
	header:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -4)
	header:SetPoint("TOPRIGHT", root, "TOPRIGHT", -SCROLLBAR_GAP, -4)
	header:SetHeight(HEADER_HEIGHT)
	local headerBackground = header:CreateTexture(nil, "BACKGROUND")
	headerBackground:SetAllPoints()
	headerBackground:SetColorTexture(1, 1, 1, 0.06)

	self.headers = {}
	local orderHeader = CreateHeaderButton(header, "order", L.COLUMN_ORDER)
	orderHeader:SetPoint("LEFT", header, "LEFT", 0, 0)
	orderHeader:SetPoint("RIGHT", header, "RIGHT", -ORDER_COLUMN_RIGHT, 0)
	self.headers[#self.headers + 1] = orderHeader
	for _, column in ipairs(COLUMNS) do
		local button = CreateHeaderButton(header, column.key, column.label)
		button:SetWidth(column.width)
		button:SetPoint("RIGHT", header, "RIGHT", ColumnRight(column), 0)
		self.headers[#self.headers + 1] = button
	end

	local scrollBox = CreateFrame("Frame", nil, root, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	scrollBox:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -SCROLLBAR_GAP, 4)
	local scrollBar = CreateFrame("EventFrame", nil, root, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", function(row, order)
		InitRow(row)
		UpdateRow(row, order)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	self.scrollBox = scrollBox

	self.emptyText = root:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
	self.emptyText:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)

	self:BuildToolbar()
	self:UpdateHeaderArrows()
	return true
end

-- Showing and hiding --------------------------------------------------------

-- Hides Blizzard's list widgets, remembering which were visible so leaving the
-- Patron tab restores exactly those.
local function SetBlizzardListShown(shown)
	local browseFrame = GetOrdersPage().BrowseFrame
	local hidden = Pane.hiddenBlizzardFrames
	for _, key in ipairs(BLIZZARD_LIST_KEYS) do
		local frame = browseFrame[key]
		if frame then
			if shown then
				if hidden[key] then
					frame:Show()
				end
				hidden[key] = nil
			elseif frame:IsShown() then
				hidden[key] = true
				frame:Hide()
			end
		end
	end
end

function Pane:SetActive(active)
	if self.active == active then
		if active then
			SetBlizzardListShown(false)
		end
		return
	end
	self.active = active
	self.root:SetShown(active)
	SetBlizzardListShown(not active)

	if active then
		self.orders = {}
		self.hasResults = false
		self.failed = false
		self:Render()
		-- Blizzard requests patron orders when the tab opens. Only send our own
		-- request if its results have not arrived shortly after.
		C_Timer.After(INITIAL_REQUEST_DELAY, function()
			if Pane.active and not Pane.hasResults and not Pane.requestToken then
				Pane:RequestOrders()
			end
		end)
		self.timeTicker = C_Timer.NewTicker(TIME_REFRESH_INTERVAL, function()
			Pane:RefreshTimes()
		end)
	else
		self.requestToken = nil
		self.loading = false
		if self.timeTicker then
			self.timeTicker:Cancel()
			self.timeTicker = nil
		end
	end
end

function Pane:SyncWithOrderType(orderType)
	local ordersPage = GetOrdersPage()
	orderType = orderType or ordersPage.orderType
	self:SetActive(ordersPage:IsShown() and orderType == ns.ORDER_TYPE_NPC)
end

-- Data ----------------------------------------------------------------------

function Pane:RequestOrders()
	if not self.active then
		return
	end
	if not self.canRequest then
		self.wantRequest = true
		self:UpdateEmptyState()
		return
	end
	local profession = GetCurrentProfession()
	if not profession then
		self.wantRequest = true
		C_Timer.After(1, function()
			if Pane.wantRequest and Pane.canRequest then
				Pane:RequestOrders()
			end
		end)
		return
	end

	self.canRequest = false
	self.wantRequest = false
	self.loading = true
	local token = {}
	self.requestToken = token

	local callback = C_FunctionContainers.CreateCallback(function(result, orderType)
		if Pane.requestToken ~= token then
			return
		end
		Pane.requestToken = nil
		Pane:OnOrdersReceived(result, orderType)
	end)

	C_CraftingOrders.RequestCrafterOrders({
		profession = profession,
		orderType = ns.ORDER_TYPE_NPC,
		forCrafter = true,
		offset = 0,
		searchFavorites = false,
		initialNonPublicSearch = false,
		primarySort = { sortType = Enum.CraftingOrderSortType.ItemName, reversed = false },
		secondarySort = { sortType = Enum.CraftingOrderSortType.Tip, reversed = true },
		callback = callback,
	})

	C_Timer.After(REQUEST_TIMEOUT, function()
		if Pane.requestToken == token then
			-- Throttled or dropped: retry on the next CRAFTINGORDERS_CAN_REQUEST.
			Pane.requestToken = nil
			Pane.loading = false
			Pane.wantRequest = true
			Pane:UpdateEmptyState()
		end
	end)
	self:UpdateEmptyState()
end

function Pane:OnOrdersReceived(result, orderType)
	if not self.active or orderType ~= ns.ORDER_TYPE_NPC then
		return
	end
	self.loading = false
	if result == Enum.CraftingOrderResult.Ok then
		self.hasResults = true
		self.failed = false
		self:Rebuild()
	else
		self.failed = not self.hasResults
		self:UpdateEmptyState()
	end
end

local function ClaimedOrderBelongsHere(claimed)
	local info = claimed.spellID
		and C_TradeSkillUI.GetProfessionInfoByRecipeID
		and C_TradeSkillUI.GetProfessionInfoByRecipeID(claimed.spellID)
	local current = GetCurrentProfession()
	return not (info and info.profession and current and info.profession ~= current)
end

function Pane:Rebuild()
	if not (self.active and self.hasResults) then
		return
	end

	-- The request is already scoped to patron orders, and current Retail does
	-- not reliably fill orderType on each result, so results are not re-filtered.
	local orders = {}
	local seen = {}
	for _, rawOrder in ipairs(C_CraftingOrders.GetCrafterOrders() or EMPTY) do
		orders[#orders + 1] = Model.Build(rawOrder)
		seen[tostring(rawOrder.orderID)] = true
	end

	-- A claimed order can drop out of the server list; keep it so its
	-- Craft/Complete buttons stay reachable.
	local claimed = Craft.GetClaimedPatronOrder()
	if claimed and not seen[tostring(claimed.orderID)] and ClaimedOrderBelongsHere(claimed) then
		orders[#orders + 1] = Model.Build(claimed)
	end

	self.orders = orders
	self:Render()
end

-- While an order is claimed or a server action is pending, rows keep their
-- on-screen positions so repeated clicks on one spot hit the same order.
-- "userResort" (a header click or option change) always re-sorts.
function Pane:Render(userResort)
	if not self.root then
		return
	end
	local craftInProgress = Craft.busy ~= nil or Craft.GetClaimedOrder() ~= nil
	local frozenRanks = craftInProgress and not userResort and self.ranks or nil
	Model.Sort(self.orders, frozenRanks)
	local ranks = {}
	for index, order in ipairs(self.orders) do
		order.listIndex = index
		ranks[tostring(order.orderID)] = index
	end
	self.ranks = ranks
	self.scrollBox:SetDataProvider(CreateDataProvider(self.orders), ScrollBoxConstants.RetainScrollPosition)
	self:UpdateHeaderArrows()
	self:UpdateEmptyState()
end

local function Debounce(field, delay, action)
	local token = {}
	Pane[field] = token
	C_Timer.After(delay, function()
		if Pane[field] == token then
			Pane[field] = nil
			if Pane.active then
				action(Pane)
			end
		end
	end)
end

function Pane:ScheduleRebuild(delay)
	Debounce("rebuildToken", delay or 0.3, Pane.Rebuild)
end

function Pane:ScheduleRender(delay)
	Debounce("renderToken", delay or 0.3, Pane.Render)
end

function Pane:UpdateEmptyState()
	if not self.emptyText then
		return
	end
	local text
	if #self.orders == 0 then
		if self.failed and not self.loading then
			text = L.STATE_FAILED
		elseif self.hasResults and not self.loading then
			text = L.STATE_EMPTY
		else
			text = L.STATE_LOADING
		end
	end
	self.emptyText:SetText(text or "")
	self.emptyText:SetShown(text ~= nil)
	if self.refreshButton then
		self.refreshButton:SetEnabled(not self.loading)
	end
end

function Pane:RefreshButtons()
	if not (self.active and self.scrollBox) then
		return
	end
	self.scrollBox:ForEachFrame(UpdateRowButtons)
end

function Pane:RefreshTimes()
	if not (self.active and self.scrollBox) then
		return
	end
	self.scrollBox:ForEachFrame(function(row)
		if row.order then
			row.timeText:SetText(FormatTimeLeft(row.order.expirationTime))
		end
	end)
end

function Pane:OnClaimedOrderChanged(removed)
	if not self.active then
		return
	end
	if removed then
		-- Completing or releasing changes the server list.
		self:RequestOrders()
	end
	self:Rebuild()
	self:RefreshButtons()
end

-- Setup ---------------------------------------------------------------------

function Pane:InstallHooks()
	local ordersPage = GetOrdersPage()
	if type(ordersPage.SetCraftingOrderType) == "function" then
		hooksecurefunc(ordersPage, "SetCraftingOrderType", function(_, orderType)
			Pane:SyncWithOrderType(orderType)
		end)
	end
	ordersPage:HookScript("OnShow", function()
		Pane:SyncWithOrderType()
	end)
	ordersPage:HookScript("OnHide", function()
		Pane:SetActive(false)
	end)
	-- Coming back from an order's detail view re-shows Blizzard's list.
	ordersPage.BrowseFrame:HookScript("OnShow", function()
		if Pane.active then
			SetBlizzardListShown(false)
		end
	end)
	-- Blizzard requests patron orders itself when the tab opens; use its
	-- results too instead of waiting for our own request.
	if type(ordersPage.OrderRequestCallback) == "function" then
		hooksecurefunc(ordersPage, "OrderRequestCallback", function(_, result, orderType)
			if Pane.active and orderType == ns.ORDER_TYPE_NPC then
				Pane:OnOrdersReceived(result, orderType)
			end
		end)
	end
end

function Pane:InstallEvents()
	ns.RegisterEvent("CRAFTINGORDERS_CAN_REQUEST", function()
		Pane.canRequest = true
		if Pane.wantRequest then
			Pane:RequestOrders()
		end
	end)
	ns.RegisterEvent("CRAFTINGORDERS_UPDATE_REWARDS", function()
		if Pane.active then
			Pane:ScheduleRebuild()
		end
	end)
	ns.RegisterEvent("ITEM_DATA_LOAD_RESULT", function()
		if Pane.active then
			for _, order in ipairs(Pane.orders) do
				if order.waitingForItemData then
					Pane:ScheduleRebuild(0.5)
					return
				end
			end
		end
	end)
	ns.RegisterEvent("CURRENCY_DISPLAY_UPDATE", function()
		if Pane.active then
			-- Concentration changed; blockers and their sort tier may differ.
			Pane:ScheduleRender()
		end
	end)
	ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
		if Pane.active then
			-- Owned materials changed; "missing materials" blockers may differ.
			Pane:ScheduleRender()
		end
	end)
	ns.RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", function()
		if Pane.active then
			Pane.orders = {}
			Pane.hasResults = false
			Pane:Render()
			Pane:RequestOrders()
		end
	end)

	ns.OnConfigChanged(function(key, value)
		local checkbox = Pane.toolbarCheckboxes and Pane.toolbarCheckboxes[key]
		if checkbox then
			checkbox:SetChecked(value)
		end
		if key == "pricingSource" then
			Pane:Rebuild()
		elseif Pane.active then
			Pane:Render(true)
		end
	end)
end

function Pane:Initialize()
	if self.root or not self:BuildFrame() then
		return
	end
	self:InstallHooks()
	self:InstallEvents()
	Craft.InitializeEvents()
	self:SyncWithOrderType()
end

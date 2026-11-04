local _, ns = ...
local L = ns.L
local Pricing = ns.Pricing

-- Settings > AddOns > Rapid Patron Orders.

local Options = {}
ns.Options = Options

local function CreateCheckbox(panel, label, description, configKey)
	local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	checkbox:SetSize(26, 26)
	checkbox.label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 4, 1)
	checkbox.label:SetText(label)
	checkbox.description = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	checkbox.description:SetPoint("TOPLEFT", checkbox.label, "BOTTOMLEFT", 0, -3)
	checkbox.description:SetWidth(560)
	checkbox.description:SetJustifyH("LEFT")
	checkbox.description:SetText(description)
	checkbox.configKey = configKey
	checkbox:SetScript("OnClick", function(self)
		ns.SetConfig(configKey, self:GetChecked())
	end)
	return checkbox
end

local function CreateHeader(panel, text)
	local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetText(text)
	return header
end

local function CreateRadio(panel, value)
	local radio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
	radio.value = value
	radio.label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	radio.label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
	radio:SetScript("OnClick", function()
		ns.SetConfig("pricingSource", value)
		Options:Refresh()
	end)
	return radio
end

function Options:Build()
	local panel = CreateFrame("Frame")
	panel.name = L.ADDON_TITLE
	panel:SetScript("OnShow", function()
		Options:Refresh()
	end)
	self.panel = panel

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L.ADDON_TITLE)

	local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetWidth(600)
	description:SetJustifyH("LEFT")
	description:SetText(L.ADDON_DESCRIPTION)

	self.checkboxes = {}
	local enable = CreateCheckbox(panel, L.OPTION_ALLOW_CONCENTRATION, L.OPTION_ALLOW_CONCENTRATION_DESC, "allowConcentration")
	enable:SetPoint("TOPLEFT", description, "BOTTOMLEFT", -2, -18)
	self.checkboxes[#self.checkboxes + 1] = enable

	local unprofitable = CreateCheckbox(panel, L.OPTION_ALLOW_UNPROFITABLE, L.OPTION_ALLOW_UNPROFITABLE_DESC, "allowUnprofitable")
	unprofitable:SetPoint("TOPLEFT", enable.description, "BOTTOMLEFT", -30, -10)
	self.checkboxes[#self.checkboxes + 1] = unprofitable

	local priorityHeader = CreateHeader(panel, L.OPTION_PRIORITY_HEADER)
	priorityHeader:SetPoint("TOPLEFT", unprofitable.description, "BOTTOMLEFT", -30, -24)
	local priorityDescription = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	priorityDescription:SetPoint("TOPLEFT", priorityHeader, "BOTTOMLEFT", 0, -6)
	priorityDescription:SetWidth(600)
	priorityDescription:SetJustifyH("LEFT")
	priorityDescription:SetText(L.OPTION_PRIORITY_DESC)

	local nonConcentration = CreateCheckbox(
		panel,
		L.OPTION_PRIORITIZE_NON_CONCENTRATION,
		L.OPTION_PRIORITIZE_NON_CONCENTRATION_DESC,
		"prioritizeNonConcentration"
	)
	nonConcentration:SetPoint("TOPLEFT", priorityDescription, "BOTTOMLEFT", -2, -10)
	self.checkboxes[#self.checkboxes + 1] = nonConcentration

	local profitable = CreateCheckbox(
		panel,
		L.OPTION_PRIORITIZE_PROFITABLE,
		L.OPTION_PRIORITIZE_PROFITABLE_DESC,
		"prioritizeProfitable"
	)
	profitable:SetPoint("TOPLEFT", nonConcentration.description, "BOTTOMLEFT", -30, -10)
	self.checkboxes[#self.checkboxes + 1] = profitable

	local pricingHeader = CreateHeader(panel, L.OPTION_PRICING_HEADER)
	pricingHeader:SetPoint("TOPLEFT", profitable.description, "BOTTOMLEFT", -30, -24)

	self.radios = {}
	local previous = pricingHeader
	local radioValues = { "auto" }
	for _, provider in ipairs(Pricing.providers) do
		radioValues[#radioValues + 1] = provider.key
	end
	for index, value in ipairs(radioValues) do
		local radio = CreateRadio(panel, value)
		radio:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, index == 1 and -10 or -6)
		self.radios[#self.radios + 1] = radio
		previous = radio
	end

	self.pricingNone = panel:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
	self.pricingNone:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10)
	self.pricingNone:SetWidth(600)
	self.pricingNone:SetJustifyH("LEFT")
	self.pricingNone:SetText(L.OPTION_PRICING_NONE)

	return panel
end

function Options:Refresh()
	if not self.panel then
		return
	end
	for _, checkbox in ipairs(self.checkboxes) do
		checkbox:SetChecked(ns.GetConfig(checkbox.configKey))
	end

	local selected = ns.GetConfig("pricingSource")
	local anyAvailable = false
	for _, radio in ipairs(self.radios) do
		if radio.value == "auto" then
			radio.label:SetText(L.OPTION_PRICING_AUTO)
			radio:Enable()
		else
			for _, provider in ipairs(Pricing.providers) do
				if provider.key == radio.value then
					local available = provider.IsAvailable()
					anyAvailable = anyAvailable or available
					radio.label:SetText(available and provider.label or L.OPTION_PRICING_NOT_DETECTED:format(provider.label))
					radio:SetEnabled(available)
				end
			end
		end
		radio:SetChecked(radio.value == selected)
	end
	self.pricingNone:SetShown(not anyAvailable)
end

function Options:Initialize()
	if self.category then
		return
	end
	local panel = self:Build()
	self.category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(self.category)

	-- Keep this panel in step with the toggle on the Patron list.
	ns.OnConfigChanged(function()
		if panel:IsShown() then
			Options:Refresh()
		end
	end)
end

function Options:Open()
	if self.category then
		Settings.OpenToCategory(self.category:GetID())
	end
end

local ADDON_NAME = ...

SpellbookProDB = SpellbookProDB or {}

local DEFAULTS = {
	showGeneralTab = false,
	showOtherTabs = false,
	showPetSpells = false,
	buttonScale = 1.0,
}

local function ApplyDefaults(db, defaults)
	for key, value in pairs(defaults) do
		if db[key] == nil then
			db[key] = value
		end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

local function GetPlayerClassToken()
	local _, classToken = UnitClass("player")
	return classToken
end

local function IsGeneralTab(tabIndex)
	return tabIndex == 1
end

local function IsPetTab(tabName)
	return tabName == PET or tabName == "Pet"
end

local function ShouldIncludeTab(tabIndex, tabName)
	if IsGeneralTab(tabIndex) then
		return SpellbookProDB.showGeneralTab
	end
	if IsPetTab(tabName) then
		return SpellbookProDB.showPetSpells
	end
	if tabIndex == 2 then
		return true
	end
	return SpellbookProDB.showOtherTabs
end

local function CollectSpellbookEntries()
	local entries = {}
	local numTabs = GetNumSpellTabs()

	for tabIndex = 1, numTabs do
		local tabName, _, tabOffset, numSpells = GetSpellTabInfo(tabIndex)
		if tabName and ShouldIncludeTab(tabIndex, tabName) then
			for i = 1, numSpells do
				local slot = tabOffset + i
				local spellType, spellID = GetSpellBookItemInfo(slot, "spell")
				if spellType == "SPELL" and spellID then
					local name, subName = GetSpellBookItemName(slot, "spell")
					local icon = GetSpellBookItemTexture(slot, "spell")
					if name and name ~= "" then
						table.insert(entries, {
							name = name,
							subName = subName,
							icon = icon,
							spellID = spellID,
							bookSlot = slot,
							bookType = "spell",
						})
					end
				end
			end
		end
	end

	table.sort(entries, function(a, b)
		return a.name < b.name
	end)

	return entries
end

local function NormalizeSearch(text)
	if not text then
		return ""
	end
	return string.lower(text):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function EntryMatchesSearch(entry, search)
	if search == "" then
		return true
	end
	local name = NormalizeSearch(entry.name)
	if string.find(name, search, 1, true) then
		return true
	end
	return false
end

local SpellbookProFrame
local allEntries = {}
local filteredEntries = {}

local function RefreshFilter()
	local search = NormalizeSearch(SpellbookProFrame and SpellbookProFrame.searchBox and SpellbookProFrame.searchBox:GetText())
	filteredEntries = {}
	for _, entry in ipairs(allEntries) do
		if EntryMatchesSearch(entry, search) then
			table.insert(filteredEntries, entry)
		end
	end
end

local function GetVisibleCount()
	return #filteredEntries
end

local BUTTON_HEIGHT = 32
local VISIBLE_ROWS = 12

local function UpdateScroll()
	if not SpellbookProFrame then
		return
	end

	RefreshFilter()

	local total = GetVisibleCount()
	FauxScrollFrame_Update(SpellbookProFrame.scrollFrame, total, VISIBLE_ROWS, BUTTON_HEIGHT)

	local offset = FauxScrollFrame_GetOffset(SpellbookProFrame.scrollFrame)
	for row = 1, VISIBLE_ROWS do
		local index = row + offset
		local button = SpellbookProFrame.rows[row]
		local entry = filteredEntries[index]

		if entry then
			button:Show()
			button.icon:SetTexture(entry.icon)
			button.name:SetText(entry.name)

			button:SetAttribute("type", "spell")
			button:SetAttribute("spell", entry.name)
			button.entry = entry
		else
			button:Hide()
			button.entry = nil
		end
	end
end

local function RebuildEntries()
	allEntries = CollectSpellbookEntries()
	UpdateScroll()
end

local function CreateMainWindow()
	if SpellbookProFrame then
		return SpellbookProFrame
	end

	local frame = CreateFrame("Frame", "SpellbookProFrame", UIParent, "BackdropTemplate")
	frame:SetSize(380, 520)
	frame:SetPoint("CENTER")
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	frame:Hide()

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("Spellbook-Pro")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	searchBox:SetSize(210, 20)
	searchBox:SetPoint("TOPLEFT", 18, -46)
	searchBox:SetScript("OnTextChanged", function() UpdateScroll() end)
	frame.searchBox = searchBox

	local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	help:SetPoint("TOPRIGHT", -40, -48)
	help:SetText("Drag spells to bars")

	local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "FauxScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 18, -76)
	scrollFrame:SetPoint("BOTTOMRIGHT", -36, 18)
	scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, BUTTON_HEIGHT, UpdateScroll)
	end)
	frame.scrollFrame = scrollFrame

	frame.rows = {}
	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,BackdropTemplate")
		row:SetHeight(BUTTON_HEIGHT)
		row:SetPoint("TOPLEFT", 18, -76 - (i - 1) * BUTTON_HEIGHT)
		row:SetPoint("TOPRIGHT", -48, -76 - (i - 1) * BUTTON_HEIGHT)
		row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
		row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.15 or 0.05)
		row:RegisterForClicks("AnyUp")
		row:RegisterForDrag("LeftButton")
		row:SetScript("OnDragStart", function(self)
			if not self.entry then
				return
			end
			PickUpSpellBookItem(self.entry.bookSlot, self.entry.bookType)
		end)

		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(22, 22)
		icon:SetPoint("LEFT", 6, 0)
		row.icon = icon

		local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
		name:SetPoint("RIGHT", -8, 0)
		name:SetJustifyH("LEFT")
		row.name = name

		frame.rows[i] = row
	end

	local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	refresh:SetSize(80, 20)
	refresh:SetPoint("TOPLEFT", searchBox, "TOPRIGHT", 10, 0)
	refresh:SetText("Refresh")
	refresh:SetScript("OnClick", function()
		if InCombatLockdown() then
			UIErrorsFrame:AddMessage("Spellbook-Pro: Can't refresh during combat", 1, 0.2, 0.2)
			return
		end
		RebuildEntries()
	end)

	scrollFrame:SetScript("OnShow", UpdateScroll)

	SpellbookProFrame = frame
	return frame
end

local function ToggleMainWindow()
	local frame = CreateMainWindow()
	if frame:IsShown() then
		frame:Hide()
	else
		if InCombatLockdown() then
			UIErrorsFrame:AddMessage("Spellbook-Pro: Can't open during combat", 1, 0.2, 0.2)
			return
		end
		RebuildEntries()
		frame:Show()
	end
end

local function CreateToggleButton()
	local button = CreateFrame("Button", "SpellbookProToggleButton", UIParent, "UIPanelButtonTemplate")
	button:SetSize(120, 22)
	button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -16)
	button:SetText("Spellbook-Pro")
	button:SetScale(SpellbookProDB.buttonScale or 1.0)
	button:SetScript("OnClick", ToggleMainWindow)
	button:RegisterForDrag("LeftButton")
	button:SetMovable(true)
	button:EnableMouse(true)
	button:SetScript("OnDragStart", function(self) self:StartMoving() end)
	button:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	return button
end

SLASH_SPELLBOOKPRO1 = "/sbp"
SlashCmdList["SPELLBOOKPRO"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

	if msg == "general" then
		SpellbookProDB.showGeneralTab = not SpellbookProDB.showGeneralTab
		print("Spellbook-Pro: showGeneralTab =", SpellbookProDB.showGeneralTab)
		RebuildEntries()
		return
	end
	if msg == "others" then
		SpellbookProDB.showOtherTabs = not SpellbookProDB.showOtherTabs
		print("Spellbook-Pro: showOtherTabs =", SpellbookProDB.showOtherTabs)
		RebuildEntries()
		return
	end
	if msg == "pet" then
		SpellbookProDB.showPetSpells = not SpellbookProDB.showPetSpells
		print("Spellbook-Pro: showPetSpells =", SpellbookProDB.showPetSpells)
		RebuildEntries()
		return
	end

	ToggleMainWindow()
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		ApplyDefaults(SpellbookProDB, DEFAULTS)
	elseif event == "PLAYER_LOGIN" then
		CreateMainWindow()
		CreateToggleButton()
	end
end)

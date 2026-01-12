local ADDON_NAME = ...

SpellbookProDB = SpellbookProDB or {}
SpellbookProSpellDB = SpellbookProSpellDB or { version = 1, classes = {} }

local DEFAULTS = {
	showGeneralTab = false,
	showOtherTabs = false,
	showPetSpells = false,
	buttonScale = 1.0,
	minimapAngle = 225,
	showUnlearned = false,
	selectedClassTabIndex = 1,
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
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local function GetPlayerClassToken()
	local _, classToken = UnitClass("player")
	return classToken
end

local function BuildSBPMacroBody(spellName, key)
	return "#showtooltip " .. spellName .. "\n/cast " .. spellName .. "\n#sbp " .. key
end

local function ShouldIncludeSpellForFaction(spellName)
	if not spellName or spellName == "" then
		return true
	end

	local faction = UnitFactionGroup("player")
	if faction ~= "Alliance" and faction ~= "Horde" then
		return true
	end

	local allianceOnlyCities = {
		["Stormwind"] = true,
		["Ironforge"] = true,
		["Darnassus"] = true,
	}
	local hordeOnlyCities = {
		["Orgrimmar"] = true,
		["Undercity"] = true,
		["Thunder Bluff"] = true,
	}

	local city = spellName:match("^Teleport:%s*(.+)$") or spellName:match("^Portal:%s*(.+)$")
	if not city then
		return true
	end

	if faction == "Alliance" and hordeOnlyCities[city] then
		return false
	end
	if faction == "Horde" and allianceOnlyCities[city] then
		return false
	end
	return true
end

local function IsGeneralTab(tabIndex)
	return tabIndex == 1
end

local function IsPetTab(tabName)
	return tabName == PET or tabName == "Pet"
end

local function IsProfessionTab(tabName)
	if not tabName or tabName == "" then
		return false
	end
	return tabName == TRADE_SKILLS or tabName == "Trade Skills" or tabName == "Professions"
end

local function ShouldIncludeTab(tabIndex, tabName)
	if IsGeneralTab(tabIndex) then
		return SpellbookProDB.showGeneralTab
	end
	if IsPetTab(tabName) then
		return SpellbookProDB.showPetSpells
	end
	return SpellbookProDB.showOtherTabs
end

local function GetClassTabIndices()
	local indices = {}
	local numTabs = GetNumSpellTabs()
	for tabIndex = 2, numTabs do
		local tabName = GetSpellTabInfo(tabIndex)
		if IsPetTab(tabName) or IsProfessionTab(tabName) then
			break
		end
		table.insert(indices, tabIndex)
		if #indices >= 3 then
			break
		end
	end
	if #indices == 0 and numTabs >= 2 then
		table.insert(indices, 2)
	end
	return indices
end

local function CollectSpellbookEntries(tabIndex)
	local entries = {}
	local tabName, _, tabOffset, numSpells = GetSpellTabInfo(tabIndex)
	if not tabName then
		return entries
	end

	for i = 1, numSpells do
		local slot = tabOffset + i
		local spellType, spellID = GetSpellBookItemInfo(slot, "spell")
		if spellType == "SPELL" and spellID then
			local name, subName = GetSpellBookItemName(slot, "spell")
			local icon = GetSpellBookItemTexture(slot, "spell")
			if name and name ~= "" and ShouldIncludeSpellForFaction(name) then
				table.insert(entries, {
					name = name,
					subName = subName,
					icon = icon,
					spellID = spellID,
					bookSlot = slot,
					bookType = "spell",
					learned = true,
				})
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
local classTabIndices = {}
local wantsWindowOpen = false

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
local VISIBLE_ROWS = 10

local function UpdateClassTabHighlights(frame)
	if not frame or not frame.classTabButtons then
		return
	end

	local selected = frame.selectedClassTabIndex or 1
	for i = 1, 3 do
		local button = frame.classTabButtons[i]
		if button then
			if i == selected then
				if button.LockHighlight then
					button:LockHighlight()
				end
				if button.SetButtonState then
					button:SetButtonState("PUSHED", true)
				end
			else
				if button.UnlockHighlight then
					button:UnlockHighlight()
				end
				if button.SetButtonState then
					button:SetButtonState("NORMAL", false)
				end
			end
		end
	end
end

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
			button.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			button.icon:SetDesaturated(not entry.learned)
			button.name:SetText(entry.name)
			if entry.learned then
				button.name:SetTextColor(1, 1, 1)
			else
				button.name:SetTextColor(0.7, 0.7, 0.7)
			end

			button:SetAttribute("type", "macro")
			button:SetAttribute("macrotext", "#showtooltip " .. "\n/cast " .. entry.name)
			button.entry = entry
		else
			button:Hide()
			button.entry = nil
		end
	end
end

local function RebuildEntries()
	if not SpellbookProFrame then
		return
	end

	classTabIndices = GetClassTabIndices()
	for i = 1, 3 do
		local button = SpellbookProFrame.classTabButtons and SpellbookProFrame.classTabButtons[i]
		local tabIndex = classTabIndices[i]
		if button and tabIndex then
			local tabName = GetSpellTabInfo(tabIndex)
			button:SetText(tabName or ("Tab " .. i))
			button:Show()
		elseif button then
			button:Hide()
		end
	end

	local selectedTabIndex = SpellbookProFrame.selectedClassTabIndex or 1
	if selectedTabIndex < 1 then
		selectedTabIndex = 1
	end
	if selectedTabIndex > #classTabIndices then
		selectedTabIndex = 1
	end
	SpellbookProFrame.selectedClassTabIndex = selectedTabIndex
	UpdateClassTabHighlights(SpellbookProFrame)

	local spellTabIndex = classTabIndices[selectedTabIndex]
	allEntries = CollectSpellbookEntries(spellTabIndex)

	local learnedByName = {}
	for _, entry in ipairs(allEntries) do
		learnedByName[entry.name] = true
	end

	local showUnlearned = SpellbookProFrame.showUnlearnedCheck and SpellbookProFrame.showUnlearnedCheck:GetChecked()
	if showUnlearned then
		local classToken = GetPlayerClassToken()
		local classSpells = SpellbookProSpellDB and SpellbookProSpellDB.classes and SpellbookProSpellDB.classes[classToken]
		if classSpells then
			for spellName, ranks in pairs(classSpells) do
				if type(spellName) == "string" and type(ranks) == "table" and not learnedByName[spellName] and ShouldIncludeSpellForFaction(spellName) then
					local bestID
					for _, rankInfo in ipairs(ranks) do
						if type(rankInfo) == "table" and type(rankInfo.id) == "number" then
							bestID = rankInfo.id
						end
					end
					table.insert(allEntries, {
						name = spellName,
						subName = "",
						icon = "Interface\\Icons\\INV_Misc_QuestionMark",
						spellID = bestID,
						bookSlot = nil,
						bookType = nil,
						learned = false,
					})
				end
			end
		end
	end

	table.sort(allEntries, function(a, b)
		if a.learned ~= b.learned then
			return a.learned and not b.learned
		end
		return a.name < b.name
	end)
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
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:Hide()
	tinsert(UISpecialFrames, "SpellbookProFrame")
	frame:SetScript("OnShow", function()
		wantsWindowOpen = true
	end)
	frame:SetScript("OnHide", function()
		wantsWindowOpen = false
	end)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("Spellbook-Pro")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local macroButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	macroButton:SetSize(96, 22)
	macroButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
	macroButton:SetText("Edit Macros")
	macroButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Edit Macros")
		GameTooltip:AddLine("Opens the Blizzard macro window.", 1, 1, 1, true)
		GameTooltip:AddLine("If you edit a Spellbook-Pro macro, rename it first or it may be overwritten the next time Spellbook-Pro updates it.", 1, 0.82, 0, true)
		GameTooltip:Show()
	end)
	macroButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	macroButton:SetScript("OnClick", function()
		if InCombatLockdown() then
			UIErrorsFrame:AddMessage("Spellbook-Pro: Can't open macros during combat", 1, 0.2, 0.2)
			return
		end
		if not MacroFrame then
			pcall(UIParentLoadAddOn, "Blizzard_MacroUI")
		end
		if ShowMacroFrame then
			ShowMacroFrame()
		elseif ToggleMacroFrame then
			ToggleMacroFrame()
		end

		if MacroFrameTab2 and MacroFrameTab2.Click then
			MacroFrameTab2:Click()
		elseif MacroFrame and PanelTemplates_SetTab then
			PanelTemplates_SetTab(MacroFrame, 2)
		end
	end)

	local searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	searchBox:SetSize(210, 20)
	searchBox:SetPoint("TOPLEFT", 18, -46)
	searchBox:SetScript("OnTextChanged", function() UpdateScroll() end)
	frame.searchBox = searchBox

	local showUnlearnedCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	showUnlearnedCheck:SetPoint("TOPLEFT", 18, -70)
	showUnlearnedCheck.text:SetText("Show unlearned")
	showUnlearnedCheck:SetChecked(SpellbookProDB.showUnlearned)
	showUnlearnedCheck:SetScript("OnClick", function()
		if InCombatLockdown() then
			UIErrorsFrame:AddMessage("Spellbook-Pro: Can't refresh during combat", 1, 0.2, 0.2)
			showUnlearnedCheck:SetChecked(not showUnlearnedCheck:GetChecked())
			return
		end
		SpellbookProDB.showUnlearned = showUnlearnedCheck:GetChecked() and true or false
		RebuildEntries()
	end)
	frame.showUnlearnedCheck = showUnlearnedCheck

	frame.selectedClassTabIndex = SpellbookProDB.selectedClassTabIndex or 1

	frame.classTabButtons = {}
		for i = 1, 3 do
			local tabButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			tabButton:SetSize(104, 20)
			tabButton:SetPoint("TOPLEFT", 18 + (i - 1) * 112, -94)
			tabButton:SetText("Tab " .. i)
			tabButton:SetScript("OnClick", function()
				if InCombatLockdown() then
					UIErrorsFrame:AddMessage("Spellbook-Pro: Can't refresh during combat", 1, 0.2, 0.2)
					return
				end
				frame.selectedClassTabIndex = i
				SpellbookProDB.selectedClassTabIndex = i
				UpdateClassTabHighlights(frame)
				RebuildEntries()
			end)
			frame.classTabButtons[i] = tabButton
		end

	local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 24, -126)
	help:SetText("Drag macros to bars")

	local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "FauxScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 18, -138)
	scrollFrame:SetPoint("BOTTOMRIGHT", -36, 46)
	scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, BUTTON_HEIGHT, UpdateScroll)
	end)
	frame.scrollFrame = scrollFrame

	frame.rows = {}
	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,BackdropTemplate")
		row:SetHeight(BUTTON_HEIGHT)
		row:SetPoint("TOPLEFT", 18, -138 - (i - 1) * BUTTON_HEIGHT)
		row:SetPoint("TOPRIGHT", -48, -138 - (i - 1) * BUTTON_HEIGHT)
		row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
		row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.15 or 0.05)
		row:RegisterForClicks("AnyUp")
		row:RegisterForDrag("LeftButton")
		row:SetScript("OnEnter", function(self)
			if not self.entry then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if self.entry.bookSlot then
				GameTooltip:SetSpellBookItem(self.entry.bookSlot, self.entry.bookType or "spell")
			elseif self.entry.spellID then
				GameTooltip:SetSpellByID(self.entry.spellID)
			else
				GameTooltip:AddLine(self.entry.name)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnDragStart", function(self)
			if not self.entry then
				return
			end
			if InCombatLockdown() then
				UIErrorsFrame:AddMessage("Spellbook-Pro: Can't create/pick up macros during combat", 1, 0.2, 0.2)
				return
			end

			local key = tostring(self.entry.spellID or self.entry.name)
			local macroName = "SBP" .. key
			local body = BuildSBPMacroBody(self.entry.name, key)

			local index = GetMacroIndexByName(macroName)
			local numGlobal, numChar = GetNumMacros()

			if index and index > 0 then
				EditMacro(index, macroName, self.entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark", body, index > numGlobal)
			else
				if (numGlobal + numChar) >= 120 then
					UIErrorsFrame:AddMessage("Spellbook-Pro: Macro list is full", 1, 0.2, 0.2)
					return
				end

				local ok, createdIndex = pcall(CreateMacro, macroName, self.entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark", body, true)
				if not ok or not createdIndex then
					UIErrorsFrame:AddMessage("Spellbook-Pro: Macro list is full", 1, 0.2, 0.2)
					return
				end
				index = createdIndex
			end

			PickupMacro(index)
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
			wantsWindowOpen = true
			return
		end
		frame:Show()
		frame:Raise()
		RebuildEntries()
	end
end

local function UpdateMinimapButtonPosition(button)
	local angle = SpellbookProDB.minimapAngle or 225
	local radians = math.rad(angle)
	local radius = 78
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

local function CreateMinimapButton()
	local button = CreateFrame("Button", "SpellbookProMinimapButton", Minimap)
	button:SetFrameStrata("MEDIUM")
	button:SetSize(32, 32)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	button:SetScript("OnClick", ToggleMainWindow)

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	button.border = border

	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function(self2)
			local cx, cy = Minimap:GetCenter()
			local x, y = GetCursorPosition()
			local scale = UIParent:GetScale()
			x, y = x / scale, y / scale
			local angle = math.deg(math.atan2(y - cy, x - cx))
			SpellbookProDB.minimapAngle = angle
			UpdateMinimapButtonPosition(self2)
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Spellbook-Pro")
		GameTooltip:AddLine("Click to open", 1, 1, 1)
		GameTooltip:AddLine("Drag to move", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	UpdateMinimapButtonPosition(button)
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
		CreateMinimapButton()
	elseif event == "PLAYER_REGEN_DISABLED" then
		if SpellbookProFrame and SpellbookProFrame:IsShown() then
			wantsWindowOpen = true
			SpellbookProFrame:Hide()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if wantsWindowOpen and SpellbookProFrame and not SpellbookProFrame:IsShown() then
			ToggleMainWindow()
		end
	end
end)

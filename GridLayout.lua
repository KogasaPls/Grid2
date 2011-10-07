--[[
Created by Grid2 original authors, modified by Michael
--]]

local Grid2Layout = Grid2:NewModule("Grid2Layout")

local media

local pairs, ipairs, next = pairs, ipairs, next

--{{{ Frame config function for secure headers

local function GridHeader_InitialConfigFunction(self, name)
	Grid2Frame:RegisterFrame(_G[name])
end

--}}}

--{{{ Class for group headers

local NUM_HEADERS = 0
local SecureHeaderTemplates = {
	party = "SecurePartyHeaderTemplate",
	partypet = "SecurePartyPetHeaderTemplate",
	raid = "SecureRaidGroupHeaderTemplate",
	raidpet = "SecureRaidPetHeaderTemplate",
}

local GridLayoutHeaderClass = {
	prototype = {},
	new = function (self, type)
		NUM_HEADERS = NUM_HEADERS + 1
		local frame
		if (type == "spacer") then
			frame = CreateFrame("Frame", "Grid2LayoutHeader"..NUM_HEADERS, Grid2Layout.frame)
		else
			frame = CreateFrame("Frame", "Grid2LayoutHeader"..NUM_HEADERS, Grid2Layout.frame, assert(SecureHeaderTemplates[type]))
			frame:SetAttribute("template",
				ClickCastHeader and "ClickCastUnitTemplate,SecureUnitButtonTemplate" or "SecureUnitButtonTemplate")
			frame.initialConfigFunction = GridHeader_InitialConfigFunction
			frame:SetAttribute("initialConfigFunction", [[
				RegisterUnitWatch(self)
				self:SetAttribute("*type1", "target")
				self:SetAttribute("useparent-toggleForVehicle", true)
				self:SetAttribute("useparent-allowVehicleTarget", true)
				self:SetAttribute("useparent-unitsuffix", true)
				local header = self:GetParent()
				header:CallMethod("initialConfigFunction", self:GetName())
			]])
		end
		for name, func in pairs(self.prototype) do
			frame[name] = func
		end
		frame:Reset()
		frame:SetOrientation()
		return frame
	end
}

local HeaderAttributes = {
	"showPlayer", "showSolo", "nameList", "groupFilter", "strictFiltering",
	"sortDir", "groupBy", "groupingOrder", "maxColumns", "unitsPerColumn",
	"startingIndex", "columnSpacing", "columnAnchorPoint",
	"useOwnerUnit", "filterOnPet", "unitsuffix",
	"allowVehicleTarget", "toggleForVehicle"
}
function GridLayoutHeaderClass.prototype:Reset()
	if self.initialConfigFunction then
		self:SetLayoutAttribute("sortMethod", "NAME")
		for _, attr in ipairs(HeaderAttributes) do
			self:SetLayoutAttribute(attr, nil)
		end
	end
	self:Hide()
end

-- nil or false for vertical
function GridLayoutHeaderClass.prototype:SetOrientation(horizontal)
	if not self.initialConfigFunction then return end

	local layoutSettings = Grid2Layout.db.profile
	local groupAnchor = layoutSettings.groupAnchor
	local padding = layoutSettings.Padding
	local xOffset, yOffset, point

	if horizontal then
		if groupAnchor == "TOPLEFT" or groupAnchor == "BOTTOMLEFT" then
			xOffset = padding
			yOffset = 0
			point = "LEFT"
		else
			xOffset = -padding
			yOffset = 0
			point = "RIGHT"
		end
	else
		if groupAnchor == "TOPLEFT" or groupAnchor == "TOPRIGHT" then
			xOffset = 0
			yOffset = -padding
			point = "TOP"
		else
			xOffset = 0
			yOffset = padding
			point = "BOTTOM"
		end
	end

	self:SetLayoutAttribute("xOffset", xOffset)
	self:SetLayoutAttribute("yOffset", yOffset)
	self:SetLayoutAttribute("point", point)
end

-- MSaint fix see: http://forums.wowace.com/showpost.php?p=315982&postcount=215
-- To maintain the code consistent all calls to SetAttribute were replaced with SetLayoutAttribute
-- including those which not affect anchors, the only exception: calls from GridLayoutHeaderClass.new)
function GridLayoutHeaderClass.prototype:SetLayoutAttribute(name, value)
	if name == "point" or name == "columnAnchorPoint" or name == "unitsPerColumn" then
	  self:ClearChildrenPoints()
  end
   self:SetAttribute(name, value)
end

function GridLayoutHeaderClass.prototype:ClearChildrenPoints() 
      local count = 1
      local uframe = self:GetAttribute("child1") 
      while uframe do
         uframe:ClearAllPoints()
         count = count + 1
         uframe = self:GetAttribute("child" .. count)
      end
end

--{{{ Grid2Layout
--{{{  Initialization

--{{{  AceDB defaults

Grid2Layout.defaultDB = {
	profile = {
		debug = false,
		FrameDisplay = "Always",
		layouts = {
					solo = "Solo w/Pet",
					party = "By Group 5 w/Pets",
					raid10 = "By Group 10 w/Pets",
					raid15 = "By Group 15 w/Pets",
					raid20 = "By Group 20",
					raid25 = "By Group 25 w/Pets",
					raid40 = "By Group 40",
					pvp = "By Group 40",
					arena = "By Group 5 w/Pets",
		},
		layoutScales= {},
		horizontal = true,
		clamp = true,
		FrameLock = false,
		ClickThrough = false,
		Padding = 0,
		Spacing = 10,
		ScaleSize = 1,
		BorderTexture = "Blizzard Tooltip",
		BorderR = .5,
		BorderG = .5,
		BorderB = .5,
		BorderA = 1,
		BackgroundR = .1,
		BackgroundG = .1,
		BackgroundB = .1,
		BackgroundA = .65,
		anchor = "TOPLEFT",
		groupAnchor = "TOPLEFT",
		PosX = 500,
		PosY = -200,
	},
}

--}}}
--}}}

Grid2Layout.layoutSettings = {}
Grid2Layout.layoutHeaderClass = GridLayoutHeaderClass

function Grid2Layout:OnModuleInitialize()
	self.groups = {
		raid = {},
		raidpet = {},
		party = {},
		partypet = {},
		spacer = {},
	}
	self.indexes = {
		raid = 0,
		raidpet = 0,
		party = 0,
		partypet = 0,
		spacer = 0,
	}
	-- Register user defined layouts
	local customLayouts= self.db.global.customLayouts
	if customLayouts then
		for n,l in pairs(customLayouts) do
			Grid2Layout:AddLayout(n,l)
		end
	end
end

function Grid2Layout:OnModuleEnable()
	if not media then
		media = LibStub("LibSharedMedia-3.0", true)
	end	
	if not self.frame then
		self:CreateFrame()
	end
	self:RestorePosition()
	if self.layoutName then
		self:ReloadLayout()
	end	
	self:RegisterMessage("Grid_GroupTypeChanged")
	self:RegisterMessage("Grid_UpdateLayoutSize", "UpdateSize")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Grid2Layout:OnModuleDisable()
	self:UnregisterMessage("Grid_GroupTypeChanged")
	self:UnregisterMessage("Grid_UpdateLayoutSize", "UpdateSize")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self.frame:Hide()
end

--{{{ Event handlers

local reloadLayoutQueued, updateSizeQueued, restorePositionQueued
function Grid2Layout:PLAYER_REGEN_ENABLED()
	if reloadLayoutQueued then return self:ReloadLayout() end
	if updateSizeQueued then return self:UpdateSize() end
	if restorePositionQueued then return self:RestorePosition() end
end

function Grid2Layout:Grid_GroupTypeChanged(_, type)
	Grid2Layout:Debug("GroupTypeChanged", type)
	self.partyType = type
	self:ReloadLayout()
end

--}}}

function Grid2Layout:StartMoveFrame(button)
	if not self.db.profile.FrameLock and button == "LeftButton" then
		self.frame:StartMoving()
		self.frame.isMoving = true
	end
end

function Grid2Layout:StopMoveFrame()
	if self.frame.isMoving then
		self.frame:StopMovingOrSizing()
		self:SavePosition()
		self.frame.isMoving = false
		self:RestorePosition()
	end
end

-- locked = nil : toggle
-- locked = false : disable movement
-- locked = true : enable movement
function Grid2Layout:FrameLock(locked)
	local p = self.db.profile
	if (locked == nil) then
		p.FrameLock = not p.FrameLock
	else
		p.FrameLock = locked
	end
	if (not p.FrameLock and p.ClickThrough) then
		p.ClickThrough = false
		self.frame:EnableMouse(true)
	end
end

--
-- ConfigMode support
--

-- Create the global table if it does not exist yet
CONFIGMODE_CALLBACKS = CONFIGMODE_CALLBACKS or {}

-- Declare our handler
CONFIGMODE_CALLBACKS["Grid2"] = function(action)
	if (action == "ON") then
		Grid2Layout:FrameLock(false)
	elseif (action == "OFF") then
		Grid2Layout:FrameLock(true)
	end
end

function Grid2Layout:CreateFrame()
	local p = self.db.profile
	-- create main frame to hold all our gui elements
	local f = CreateFrame("Frame", "Grid2LayoutFrame", UIParent)
	self.frame = f
	f:SetMovable(true)
	f:SetClampedToScreen(p.clamp)
	f:SetPoint("CENTER", UIParent, "CENTER")
	f:SetScript("OnMouseUp", function () self:StopMoveFrame() end)
	f:SetScript("OnHide", function () self:StopMoveFrame() end)
	f:SetScript("OnMouseDown", function (_, button) self:StartMoveFrame(button) end)
	f:SetFrameStrata("MEDIUM")
	f:SetFrameLevel(0)
	self:UpdateTextures()
	self:SetFrameLock(p.FrameLock, p.ClickThrough)
	self.CreateFrame = nil
end

local function getRelativePoint(point, horizontal)
	if point == "TOPLEFT" then
		if horizontal then
			return "BOTTOMLEFT", 1, -1
		else
			return "TOPRIGHT", 1, -1
		end
	elseif point == "TOPRIGHT" then
		if horizontal then
			return "BOTTOMRIGHT", -1, -1
		else
			return "TOPLEFT", -1, -1
		end
	elseif point == "BOTTOMLEFT" then
		if horizontal then
			return  "TOPLEFT", 1, 1
		else
			return "BOTTOMRIGHT", 1, 1
		end
	elseif point == "BOTTOMRIGHT" then
		if horizontal then
			return "TOPRIGHT", -1, 1
		else
			return "BOTTOMLEFT", -1, 1
		end
	end
end

local previousFrame
function Grid2Layout:PlaceGroup(frame, groupNumber)

	local settings = self.db.profile
	local horizontal = settings.horizontal
	local padding = settings.Padding
	local spacing = settings.Spacing
	local groupAnchor = settings.groupAnchor

	local relPoint, xMult, yMult = getRelativePoint(groupAnchor, horizontal)

	frame:ClearAllPoints()
	frame:SetParent(self.frame)
	if groupNumber == 1 then
		frame:SetPoint(groupAnchor, self.frame, groupAnchor, spacing * xMult, spacing * yMult)
	else
		if horizontal then	
			xMult = 0 
		else				
			yMult = 0
		end
		frame:SetPoint(groupAnchor, previousFrame, relPoint, padding * xMult, padding * yMult)
	end

	self:Debug("Placing group", groupNumber, frame:GetName(), groupAnchor, previousFrame and previousFrame:GetName(), relPoint)

	previousFrame = frame
end

function Grid2Layout:AddLayout(layoutName, layout)
	self.layoutSettings[layoutName] = layout
end

function Grid2Layout:SetClamp()
	self.frame:SetClampedToScreen(self.db.profile.clamp)
end

function Grid2Layout:ReloadLayout()
	if InCombatLockdown() then
		reloadLayoutQueued = true
		return
	end
	reloadLayoutQueued = false
	self:LoadLayout( self.db.profile.layouts[self.partyType or "solo"] )
end

local function getColumnAnchorPoint(point, horizontal)
	if not horizontal then
		if point == "TOPLEFT" or point == "BOTTOMLEFT" then
			return "LEFT"
		elseif point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
			return "RIGHT"
		end
	else
		if point == "TOPLEFT" or point == "TOPRIGHT" then
			return "TOP"
		elseif point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then
			return "BOTTOM"
		end
	end
	return point
end

local function SetAllAttributes(header, p, list, fix)
	local petgroup = false
	for attr, value in next, list do
		if attr == "unitsPerColumn" then
			header:SetLayoutAttribute("columnSpacing", p.Padding)
			header:SetLayoutAttribute("unitsPerColumn", value)
			header:SetLayoutAttribute("columnAnchorPoint", getColumnAnchorPoint(p.groupAnchor, p.horizontal))
		elseif attr ~= "type" then
			header:SetLayoutAttribute(attr, value)
		else
			petgroup = (value == "partypet" or value == "raidpet")
		end
	end
	if fix and petgroup then
		-- force these so that the bug in SecureGroupPetHeader_Update doesn't trigger
		header:SetLayoutAttribute("filterOnPet", true)
		header:SetLayoutAttribute("useOwnerUnit", false)
		header:SetLayoutAttribute("unitsuffix", nil)
	end
end

-- Precreate frames to avoid a blizzard bug that prevents initializing unit frames in combat
-- http://forums.wowace.com/showpost.php?p=307503&postcount=3163
local function ForceFramesCreation(header)
	local startingIndex = header:GetAttribute("startingIndex")
	local maxColumns = header:GetAttribute("maxColumns") or 1
	local unitsPerColumn = header:GetAttribute("unitsPerColumn") or 5
	local maxFrames = maxColumns * unitsPerColumn
	local count= header.FrameCount	
	if not count or count<maxFrames then
		header:Show()
		header:SetAttribute("startingIndex", 1-maxFrames )
		header:SetAttribute("startingIndex", startingIndex)
		header.FrameCount= maxFrames
	end	
end

function Grid2Layout:LoadLayout(layoutName)
	local layout = self.layoutSettings[layoutName]
	if not layout then return end
	
	self:Debug("LoadLayout", layoutName)

	self.layoutName= layoutName
	
	self:Scale()
	
	local p = self.db.profile
	local horizontal = p.horizontal
	
	for type, headers in pairs(self.groups) do
		self.indexes[type] = 0
		for _, g in ipairs(headers) do
			g:Reset()
		end
	end

	local defaults = layout.defaults
	local default_type = defaults and defaults.type or "raid"

	for i, l in ipairs(layout) do
		local type = l.type or default_type
		local headers = assert(self.groups[type], "Bad " .. type)
		local index = self.indexes[type] + 1
		local layoutGroup = headers[index]
		if not layoutGroup then
			layoutGroup = self.layoutHeaderClass:new(type)
			headers[index] = layoutGroup
		end
		self.indexes[type] = index

		if type ~= "spacer" then
			if defaults then
				SetAllAttributes(layoutGroup, p, defaults)
			end
			SetAllAttributes(layoutGroup, p, l, true)
			ForceFramesCreation(layoutGroup)
			layoutGroup:SetOrientation(horizontal)
		end
		self:PlaceGroup(layoutGroup, i)
		
		layoutGroup:Show()
	end

	self:UpdateDisplay()
end

function Grid2Layout:UpdateDisplay()
	self:UpdateTextures()
	self:UpdateColor()
	self:CheckVisibility()
	self:UpdateSize()
end

function Grid2Layout:UpdateSize()
	if InCombatLockdown() then
		updateSizeQueued = true
		return
	end
	updateSizeQueued = false
	
	local p = self.db.profile
	local curWidth, curHeight, maxWidth, maxHeight = 0, 0, 0, 0
	local Padding, Spacing = p.Padding, p.Spacing * 2
	
	local GridFrame = Grid2:GetModule("Grid2Frame")
	local frameWidth,frameHeight = GridFrame:GetFrameSize()

	for i = 1, self.indexes.spacer do
		self.groups.spacer[i]:SetSize(frameWidth,frameHeight)
	end
	
	for type, headers in pairs(self.groups) do
		for i = 1, self.indexes[type] do
			local g = headers[i]
			local width, height = g:GetWidth(), g:GetHeight()
			curWidth = curWidth + width + Padding
			curHeight = curHeight + height + Padding
			if maxWidth < width then maxWidth = width end
			if maxHeight < height then maxHeight = height end
		end
	end

	local x, y
	if p.horizontal then
		x = maxWidth + Spacing 
		y = curHeight + Spacing - Padding
	else
		x = curWidth + Spacing - Padding
		y = maxHeight + Spacing 
	end
	
	self.frame:SetWidth(x)
	self.frame:SetHeight(y)
end

function Grid2Layout:UpdateTextures()
	local f = self.frame
	local p = self.db.profile
	local borderTexture = media and media:Fetch("border", p.BorderTexture) or "Interface\\Tooltips\\UI-Tooltip-Border"
	f:SetBackdrop({
				 bgFile = "Interface\\ChatFrame\\ChatFrameBackground", tile = true, tileSize = 16,
				 edgeFile = borderTexture, edgeSize = 16,
				 insets = {left = 4, right = 4, top = 4, bottom = 4},
			 })
	-- create bg texture
	f.texture = f.texture or f:CreateTexture(nil, "BORDER")
	f.texture:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	f.texture:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
	f.texture:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
	f.texture:SetBlendMode("ADD")
	f.texture:SetGradientAlpha("VERTICAL", .1, .1, .1, 0, .2, .2, .2, 0.5)
end

function Grid2Layout:UpdateColor()
	local settings = self.db.profile
	self.frame:SetBackdropBorderColor(settings.BorderR, settings.BorderG, settings.BorderB, settings.BorderA)
	self.frame:SetBackdropColor(settings.BackgroundR, settings.BackgroundG, settings.BackgroundB, settings.BackgroundA)
	self.frame.texture:SetGradientAlpha("VERTICAL", .1, .1, .1, 0, .2, .2, .2, settings.BackgroundA/2 )
end

function Grid2Layout:CheckVisibility()
	local frameDisplay = self.db.profile.FrameDisplay

	if frameDisplay == "Always" then
		self.frame:Show()
	elseif frameDisplay == "Grouped" and self.partyType ~= "solo" then
		self.frame:Show()
	elseif frameDisplay == "Raid" and (self.partyType == "raid10" or self.partyType == "raid15" or self.partyType == "raid20" or self.partyType == "raid25") then
		self.frame:Show()
	else
		self.frame:Hide()
	end
end

function Grid2Layout:SavePosition()
	local f = self.frame
	local s = f:GetEffectiveScale()
	local uiScale = UIParent:GetEffectiveScale()
	local anchor = self.db.profile.anchor

	local x, y

	if not f:GetLeft() or not f:GetWidth() then return end

	if anchor == "CENTER" then
		x = (f:GetLeft() + f:GetWidth() / 2) * s - UIParent:GetWidth() / 2 * uiScale
		y = (f:GetTop() - f:GetHeight() / 2) * s - UIParent:GetHeight() / 2 * uiScale
	elseif anchor == "TOP" then
		x = (f:GetLeft() + f:GetWidth() / 2) * s - UIParent:GetWidth() / 2 * uiScale
		y = f:GetTop() * s - UIParent:GetHeight() * uiScale
	elseif anchor == "LEFT" then
		x = f:GetLeft() * s
		y = (f:GetTop() - f:GetHeight() / 2) * s - UIParent:GetHeight() / 2 * uiScale
	elseif anchor == "RIGHT" then
		x = f:GetRight() * s - UIParent:GetWidth() * uiScale
		y = (f:GetTop() - f:GetHeight() / 2) * s - UIParent:GetHeight() / 2 * uiScale
	elseif anchor == "BOTTOM" then
		x = (f:GetLeft() + f:GetWidth() / 2) * s - UIParent:GetWidth() / 2 * uiScale
		y = f:GetBottom() * s
	elseif anchor == "TOPLEFT" then
		x = f:GetLeft() * s
		y = f:GetTop() * s - UIParent:GetHeight() * uiScale
	elseif anchor == "TOPRIGHT" then
		x = f:GetRight() * s - UIParent:GetWidth() * uiScale
		y = f:GetTop() * s - UIParent:GetHeight() * uiScale
	elseif anchor == "BOTTOMLEFT" then
		x = f:GetLeft() * s
		y = f:GetBottom() * s
	elseif anchor == "BOTTOMRIGHT" then
		x = f:GetRight() * s - UIParent:GetWidth() * uiScale
		y = f:GetBottom() * s
	end

	if x and y then
		self.db.profile.PosX = x
		self.db.profile.PosY = y
		self:Debug("Saved Position", anchor, x, y)
	end
end

function Grid2Layout:ResetPosition()
	local uiScale = UIParent:GetEffectiveScale()

	self.db.profile.PosX = UIParent:GetWidth() / 2 * uiScale
	self.db.profile.PosY = - UIParent:GetHeight() / 2 * uiScale
	self.db.profile.anchor = "TOPLEFT"

	self:RestorePosition()
	self:SavePosition()
end

function Grid2Layout:RestorePosition()
	if InCombatLockdown() then
		restorePositionQueued = true
		return
	end
	restorePositionQueued = false

	local f = self.frame
	local s = f:GetEffectiveScale()
	local x, y = self.db.profile.PosX / s, self.db.profile.PosY / s
	local anchor = self.db.profile.anchor

	f:ClearAllPoints()
	f:SetPoint(anchor, x, y)

	self:Debug("Restored Position", anchor, x, y)
end

function Grid2Layout:Scale()
	self:SavePosition()
	local settings= self.db.profile
	self.frame:SetScale(  settings.ScaleSize * (settings.layoutScales[self.layoutName or "solo"] or 1) )
	self:RestorePosition()
end

function Grid2Layout:SetFrameLock(FrameLock, ClickThrough)
	local p = self.db.profile
	p.FrameLock = FrameLock
	if not FrameLock then
		ClickThrough = false
	end
	p.ClickThrough = ClickThrough
	self.frame:EnableMouse(not ClickThrough)
end

--}}}
_G.Grid2Layout = Grid2Layout

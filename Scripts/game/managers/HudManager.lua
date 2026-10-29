HudManager = class( nil )

-- Preset priority list. High number is high priority.
HudManager.Priority = {
	RaidCountdown = 10,
	WarehouseCountdown = 20,
	WarehouseBarrier = 30,  -- highest priority ensures effects can be started along with the border's visibility updating
}

HudManager.BorderType = {
	Alert = 1,
	WarehouseLock = 2,
}

HudManager.BorderPanels = {
	[HudManager.BorderType.Alert] = { "AlertGradientPanel" },
	[HudManager.BorderType.WarehouseLock] = { "LockGradientPanel" }
}

-- Warehouse Border
local WarehouseBorderInEffects = { -- In
	botLeft = { widgetName = "", effectName = "" },
	topLeft = { widgetName = "", effectName = "" },
	botRight = { widgetName = "", effectName = "" },
	topRight = { widgetName = "", effectName = "" },
	middle = { widgetName = "EffectPosScreenCenter", effectName = "Gui - Warehouse Lockdownlockactive" },
}
local WarehouseBorderIdleEffects = { -- Idle
	botLeft = { widgetName = "EffectPosBottomLeft", effectName = "Hudeffect - BotLeft Locked" },
	topLeft = { widgetName = "EffectPosTopLeft", effectName = "Hudeffect - TopLeft Locked" },
	botRight = { widgetName = "EffectPosBottomRight", effectName = "Hudeffect - BotRight Locked" },
	topRight = { widgetName = "EffectPosTopRight", effectName = "Hudeffect - TopRight Locked" },
	middle = { widgetName = "EffectPosScreenCenter", effectName = ""--[["Gui - Warehouse Lockdownlockidle"]] },
}
local WarehouseBorderOutEffects = { -- Out
	botLeft = { widgetName = "", effectName = "" },
	topLeft = { widgetName = "", effectName = "" },
	botRight = { widgetName = "", effectName = "" },
	topRight = { widgetName = "", effectName = "" },
	middle = { widgetName = "", effectName = "" },
}

--Transition warehouse to alert, not implemented yet
local WarehouseBorderTransitionEffects = {
	botLeft = { widgetName = "", effectName = "" },
	topLeft = { widgetName = "", effectName = "" },
	botRight = { widgetName = "", effectName = "" },
	topRight = { widgetName = "", effectName = "" },
	middle = { widgetName = "EffectPosScreenCenter", effectName = "Hudeffect - PromtCountdown" },
}

--Alert Border
local AlertBorderInEffects = { -- In
	botLeft = { widgetName = "", effectName = "" },
	topLeft = { widgetName = "", effectName = "" },
	botRight = { widgetName = "", effectName = "" },
	topRight = { widgetName = "", effectName = "" },
	middle = { widgetName = "", effectName = "" },
}
local AlertBorderIdleEffects = { -- Idle
	botLeft = { widgetName = "EffectPosBottomLeft", effectName = "Hudeffect - BotLeft Countdown" },
	topLeft = { widgetName = "EffectPosTopLeft", effectName = "Hudeffect - TopLeft Countdown" },
	botRight = { widgetName = "EffectPosBottomRight", effectName = "Hudeffect - BotRight Countdown" },
	topRight = { widgetName = "EffectPosTopRight", effectName = "Hudeffect - TopRight Countdown" },
	middle = { widgetName = "", effectName = "" },
}
local AlertBorderOutEffects = { -- Out
	botLeft = { widgetName = "", effectName = "" },
	topLeft = { widgetName = "", effectName = "" },
	botRight = { widgetName = "", effectName = "" },
	topRight = { widgetName = "", effectName = "" },
	middle = { widgetName = "", effectName = "" },
}

local function Cl_SetBorderColors( type, color )
	for _, panelName in ipairs( HudManager.BorderPanels[type] ) do
		g_survivalHud:setColor( panelName, color )
	end
end

local function Cl_ShowBorder( type )
	for panelType, panels in pairs( HudManager.BorderPanels ) do
		for _, panelName in ipairs( panels ) do
			g_survivalHud:setVisible( panelName, panelType == type )
		end
	end
end

local function Cl_HideBorder()
	for _, panels in pairs( HudManager.BorderPanels ) do
		for _, panelName in ipairs( panels ) do
			g_survivalHud:setVisible( panelName, false )
		end
	end
end

local function playEffects( table )
	for key, value in pairs( table ) do
		if value.widgetName ~= "" and value.effectName ~= "" then
			g_survivalHud:playEffect( value.widgetName, value.effectName, false, true )
		end
	end
end

local function stopEffects( table )
	for key, value in pairs( table ) do
		if value.widgetName ~= "" and value.effectName ~= "" then
			g_survivalHud:stopEffect( value.widgetName, value.effectName, false, true )
		end
	end
end

local function Cl_AlertBorderEffects( on )
	if not g_survivalHud then
		return
	end
	if on then
		playEffects( AlertBorderInEffects )
		playEffects( AlertBorderIdleEffects )
	else
		playEffects( AlertBorderOutEffects )
		stopEffects( AlertBorderIdleEffects )
	end
end

local function Cl_WarehouseLockEffects( on )
	if not g_survivalHud then
		return
	end
	if on then
		playEffects( WarehouseBorderInEffects )
		playEffects( WarehouseBorderIdleEffects )
	else
		playEffects( WarehouseBorderOutEffects )
		stopEffects( WarehouseBorderIdleEffects )
	end
end

-- Hudborder class
HudBorder = class( nil )
HudBorder.visible = false
HudBorder.priority = 0
HudBorder.type = HudManager.Alert

function HudBorder.update( self, visible )
	if self.destroyed then return end
	if visible ~= nil then
		if self.visible == visible then
			return
		else --changed
			self.visible = visible
			if self.type == HudManager.BorderType.WarehouseLock then
				Cl_WarehouseLockEffects( self.visible ) -- set effects here since this border has highest priority
			elseif self.type == HudManager.BorderType.Alert then
				Cl_AlertBorderEffects( self.visible )
			end
		end
	end
end

function HudBorder.destroy( self )
	self.destroyed = true
	self.visible = false
	self.priority = 0

	if self.type == HudManager.BorderType.WarehouseLock then
		Cl_WarehouseLockEffects( false )
	end
	if self.type == HudManager.BorderType.Alert then
		Cl_AlertBorderEffects( false )
	end
end

local BorderFadeInTime = 0.35
local BorderFadeOutTime = 0.7
local BorderMaxAlpha = 1.0

--[[ Server ]]
function HudManager.server_onCreate( self )
	assert( g_hudManager == nil )
	g_hudManager = self
	self.sv = {}
end

--[[ Client ]]
function HudManager.client_onCreate( self )
	assert( g_hudManagerClient == nil )
	g_hudManagerClient = self
	self.cl = {}
	self.cl.nextId = 1

	self.cl.borders = {}
	self.cl.activeBorder = nil
	self.cl.borderOpacity = 0.0
end

function HudManager.client_onUpdate( self, dt )

	-- Select the active border and remove destroyed borders
	local activeBorder
	local validBorders = {}
	for borderId, border in pairs( self.cl.borders ) do
		if not border.destroyed then
			validBorders[borderId] = border
			if border.visible and ( activeBorder == nil or border.priority > activeBorder.priority ) then
				activeBorder = border
			end
		end
	end
	self.cl.borders = validBorders

	if activeBorder then
		self.cl.mostRecentBorderType = activeBorder.type
	end

	if not g_survivalHud then
		-- No survival hud available
		return
	end

	-- Display the selected border and update opacity
	if activeBorder then
		self.cl.borderOpacity = math.min( self.cl.borderOpacity + ( dt / BorderFadeInTime ) * BorderMaxAlpha, BorderMaxAlpha )
	else
		self.cl.borderOpacity = math.max( self.cl.borderOpacity - ( dt / BorderFadeOutTime ) * BorderMaxAlpha, 0.0 )
	end
	local borderIsVisible = activeBorder ~= nil or self.cl.borderOpacity > 0.0
	local borderColor = sm.color.new( 1, 1, 1, self.cl.borderOpacity )

	if self.cl.mostRecentBorderType then
		if borderIsVisible then
			Cl_SetBorderColors( self.cl.mostRecentBorderType, borderColor )
			Cl_ShowBorder( self.cl.mostRecentBorderType )
		else
			Cl_HideBorder()
		end
	end
end

--[[ Manager ]]

function HudManager.Cl_CreateBorder( priority, type )
	if g_hudManagerClient then
		return g_hudManagerClient:cl_createBorder( priority, type )
	end
	return nil
end

function HudManager.cl_createBorder( self, priority, type )
	if not isAnyOf( type, HudManager.BorderType ) then
		print( "Error: HudManager unknown border type" )
		return
	end
	
	local border = HudBorder()
	border.priority = priority
	border.type = type
	border.id = self.cl.nextId
	self.cl.borders[self.cl.nextId] = border
	self.cl.nextId = self.cl.nextId + 1
	return border
end

function HudManager.Cl_WarehouseTransition()
	if g_hudManagerClient then
		return g_hudManagerClient:cl_warehouseTransition()
	end
	return nil
end

function HudManager.cl_warehouseTransition()
	playEffects( WarehouseBorderTransitionEffects )
end

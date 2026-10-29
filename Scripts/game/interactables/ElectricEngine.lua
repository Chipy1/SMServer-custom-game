-- ElectricEngine.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_items.lua")
dofile("$SURVIVAL_DATA/Scripts/util.lua")

ElectricEngine = class()
ElectricEngine.maxParentCount = 2
ElectricEngine.maxChildCount = 255
ElectricEngine.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.power + sm.interactable.connectionType.electricity
ElectricEngine.connectionOutput = sm.interactable.connectionType.bearing
ElectricEngine.colorNormal = sm.color.new( 0xffca1aff )
ElectricEngine.colorHighlight = sm.color.new( 0xffca1aff )
ElectricEngine.connectIcon = "electrical"
ElectricEngine.connectIconScale = 0.75

ElectricEngine.poseWeightCount = 1

local obj_survivalobject_electricengine = sm.uuid.new( "48563128-f84a-4342-8d9f-190c633a6ea9" )

local PoweringUpFactor = 4.5

local BearingSettingsGui = {}
BearingSettingsGui.root = sm.json.open( "$SURVIVAL_DATA/Gui/JsonGuis/BearingMode.gui" )
BearingSettingsGui.root.onClose = "cl_onBearingSettingsClose"
BearingSettingsGui.index = IndexWidgets( BearingSettingsGui.root )
BearingSettingsGui.index["ButtonStandard"].onClick = "cl_onBearingSettingClick"
BearingSettingsGui.index["ButtonDifferentialLeft"].onClick = "cl_onBearingSettingClick"
BearingSettingsGui.index["ButtonDifferentialRight"].onClick = "cl_onBearingSettingClick"

local Gears = {
	{ power = 1000, velocity = math.rad( 0 ) },
	{ power = 1000, velocity = math.rad( 30 ) },
	{ power = 1000, velocity = math.rad( 60 ) },
	{ power = 1000, velocity = math.rad( 90 ) },
	{ power = 1000, velocity = math.rad( 150 ) }, -- 1
	{ power = 1000, velocity = math.rad( 240 ) },
	{ power = 1000, velocity = math.rad( 390 ) }, -- 2
	{ power = 1000, velocity = math.rad( 630 ) },
	{ power = 1000, velocity = math.rad( 1020 ) }, -- 3
	{ power = 1000, velocity = math.rad( 1650 ) },
	{ power = 1000, velocity = math.rad( 2670 ) }, -- 4
	{ power = 1000, velocity = math.rad( 4320 ) },
	{ power = 1000, velocity = math.rad( 6990 ) }, -- 5
}

local EngineLevels = {
	[tostring(ITEMS.obj_interactive_electricengine_01)] = {
		gears = Gears,
		effect = "ElectricEngine - Level 1",
		upgrade = tostring(ITEMS.obj_interactive_electricengine_02),
		cost = 4,
		title = "#{LEVEL} 1",
		gearCount = 5,
		bearingCount = 2,
		pointsPerBattery = 4000,
		allowAdjustingJoints = true
	},
	[tostring(ITEMS.obj_interactive_electricengine_02)] = {
		gears = Gears,
		effect = "ElectricEngine - Level 2",
		upgrade = tostring(ITEMS.obj_interactive_electricengine_03),
		cost = 6,
		title = "#{LEVEL} 2",
		gearCount = 7,
		bearingCount = 4,
		pointsPerBattery = 6000,
		allowAdjustingJoints = true
	},
	[tostring(ITEMS.obj_interactive_electricengine_03)] = {
		gears = Gears,
		effect = "ElectricEngine - Level 3",
		upgrade = tostring(ITEMS.obj_interactive_electricengine_04),
		cost = 8,
		title = "#{LEVEL} 3",
		gearCount = 9,
		bearingCount = 6,
		pointsPerBattery = 9000,
		allowAdjustingJoints = true
	},
	[tostring(ITEMS.obj_interactive_electricengine_04)] = {
		gears = Gears,
		effect = "ElectricEngine - Level 4",
		upgrade = tostring(ITEMS.obj_interactive_electricengine_05),
		cost = 10,
		title = "#{LEVEL} 4",
		gearCount = 11,
		bearingCount = 8,
		pointsPerBattery = 13500,
		allowAdjustingJoints = true
	},
	[tostring(ITEMS.obj_interactive_electricengine_05)] = {
		gears = Gears,
		effect = "ElectricEngine - Level 5",
		title = "#{LEVEL} 5",
		gearCount = #Gears,
		bearingCount = 10,
		pointsPerBattery = 20250,
		allowAdjustingJoints = true
	},
	[tostring(obj_survivalobject_electricengine)] = {
		gears = Gears,
		effect = "ElectricEngine - Level 5",
		title = "#{LEVEL} 5",
		gearCount = #Gears,
		bearingCount = 10,
		pointsPerBattery = 20250,
		allowAdjustingJoints = false,
		creativeBattery = true
	}
}

--[[ Server ]]

function ElectricEngine.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if container then
		-- Validate that loaded container only holds the expected item
		local hasMismatchedItem = false
		for slot = 0, container:getSize() - 1 do
			local item = container:getItem( slot )
			if not item.uuid:isNil() and item.uuid ~= ITEMS.obj_consumable_battery then
				hasMismatchedItem = true
				break
			end
		end
		if hasMismatchedItem then
			self.shape.interactable:removeContainer( 0 )
			container = nil
		end
	end
	if not container then
		container = self.shape:getInteractable():addContainer( 0, 1, 10 )
	end
	container:setFilters( { ITEMS.obj_consumable_battery } )

	-- Remove any excess containers, keeping the fuel container at index 0
	for i = 1, 15 do
		if self.shape.interactable:getContainer( i ) then
			self.shape.interactable:removeContainer( i )
		end
	end

	local level = EngineLevels[tostring( self.shape:getShapeUuid() )]
	assert(level)
	self.level = level
	self.active = false
	self:server_init()
end

function ElectricEngine.server_onRefresh( self )
	self:server_init()
end

function ElectricEngine.server_init( self )
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.gearIdx == nil then
		self.saved.gearIdx = 1
	end
	if self.saved.batteryPoints == nil then
		self.saved.batteryPoints = 0
	end

	self.motorPower = 0
	self.motorImpulse = 0
	self.batteryPoints = self.saved.batteryPoints
	self.hasBattery = false
	self.dirtyStorageTable = false
	self.dirtyClientTable = false

	self:sv_setGear( self.saved.gearIdx )
end

function ElectricEngine.sv_setGear( self, gearIdx )
	self.saved.gearIdx = gearIdx
	self.dirtyStorageTable = true
	self.dirtyClientTable = true
end

function ElectricEngine.sv_updateFuelStatus( self, batteryContainer, useExternal )
	if self.saved.batteryPoints ~= self.batteryPoints then
		self.saved.batteryPoints = self.batteryPoints
		self.dirtyStorageTable = true
	end
	local hasBattery = ( self.batteryPoints > 0 )
	if not hasBattery then
		if useExternal then
			hasBattery = hasBattery or CanSpendFromConnectedContainer( batteryContainer, ITEMS.obj_consumable_battery, 1 )
		else
			hasBattery = hasBattery or sm.container.canSpend( batteryContainer, ITEMS.obj_consumable_battery, 1 )
		end
	end

	if self.hasBattery ~= hasBattery then
		self.hasBattery = hasBattery
		self.dirtyClientTable = true
	end
end

function ElectricEngine.getInputs( self )
	local active = true
	local direction = 1
	local sprint = false
	local batteryContainer = nil
	local hasInput = false
	local currentDriver = false

	local parents = self.interactable:getParents()
	if parents[2] then
		if parents[2]:hasOutputType( sm.interactable.connectionType.logic ) then
			active = parents[2]:isActive()
			direction = active and 1 or 0
			hasInput = true
		end
		if parents[2]:hasOutputType( sm.interactable.connectionType.power ) then
			active = parents[2]:isActive()
			direction = parents[2]:getPower()
			if parents[2]:hasSteering() then
				sprint = parents[2]:getSteeringSprint()
				currentDriver = parents[2]:getSeatCharacter()
			end
			hasInput = true
		end
		if parents[2]:hasOutputType( sm.interactable.connectionType.electricity ) then
			batteryContainer = parents[2]
		end
	end
	if parents[1] then
		if parents[1]:hasOutputType( sm.interactable.connectionType.logic ) then
			active = parents[1]:isActive()
			direction = active and 1 or 0
			hasInput = true
		end
		if parents[1]:hasOutputType( sm.interactable.connectionType.power ) then
			active = parents[1]:isActive()
			direction = parents[1]:getPower()
			if parents[1]:hasSteering() then
				sprint = parents[1]:getSteeringSprint()
				currentDriver = parents[1]:getSeatCharacter()
			end
			hasInput = true
		end
		if parents[1]:hasOutputType( sm.interactable.connectionType.electricity ) then
			batteryContainer = parents[1]
		end
	end

	return active, direction, sprint, batteryContainer, hasInput, currentDriver
end

function ElectricEngine.getControllingSteering( self )
	local parents = self.interactable:getParents()
	if parents[1] and parents[1]:hasSteering() then
		return parents[1]
	end
	if parents[2] and parents[2]:hasSteering() then
		return parents[2]
	end
	return nil
end

local TimeStep = 1 / 40

local function updatePower( power, direction )
	power = clamp( power, -1, 1 )
	direction = clamp( direction, -1, 1 )
	if direction > power then
		power = math.min( power + TimeStep * PoweringUpFactor, direction )
	elseif direction < power then
		power = math.max( power - TimeStep * PoweringUpFactor, direction )
	end
	return power
end

function ElectricEngine.controlEngine( self, direction, active, gearIdx )
	self.motorPower = updatePower( self.motorPower, direction )
	self.motorImpulse = self.level.gears[gearIdx].power * ( active and 1 or 2 )
end

function ElectricEngine.updateBearings( self, bearings, gearIdx, hasFuel, sprint )
	local steering = self:getControllingSteering()
	if steering then
		local steeringPower = hasFuel and steering:getSteeringPower() or 0
		local steeringAngle = hasFuel and steering:getSteeringAngle() or 0

		local motorModePower
		if steeringPower == 0 then
			motorModePower = { steeringAngle, -steeringAngle }
		elseif steeringAngle == 1 then
			motorModePower = { steeringPower, steeringPower * ( sprint and 0.67 or 0.33 ) }
		elseif steeringAngle == -1 then
			motorModePower = { steeringPower * ( sprint and 0.67 or 0.33 ), steeringPower }
		else
			motorModePower = { steeringPower, steeringPower }
		end

		self.bearingPower = self.bearingPower or {}
		for _, bearing in ipairs( bearings ) do
			local customData = self.interactable:getJointCustomData( bearing )
			local bearingMode = customData and customData.bearingMode or nil
			if bearingMode then
				local prev = self.bearingPower[bearing:getId()] or 0
				self.bearingPower[bearing:getId()] = updatePower( prev, motorModePower[bearingMode] )
				bearing:setMotorVelocity( self.bearingPower[bearing:getId()] * self.level.gears[gearIdx].velocity, self.motorImpulse )
			else
				bearing:setMotorVelocity( self.motorPower * self.level.gears[gearIdx].velocity, self.motorImpulse )
			end
		end
	else
		for _, bearing in ipairs( bearings ) do
			bearing:setMotorVelocity( self.motorPower * self.level.gears[gearIdx].velocity, self.motorImpulse )
		end
	end
end

function ElectricEngine.server_onFixedUpdate( self )

	-- Check engine connections
	local hadInput = self.hasInput == nil and true or self.hasInput --Pretend to have had input if nil to avoid starting engines at load
	local active, direction, sprint, batteryContainer, hasInput = self:getInputs()
	self.hasInput = hasInput
	local useCreativeBattery = not sm.game.getEnableFuelConsumption() and batteryContainer == nil or self.level.creativeBattery

	-- Check fuel container
	local useExternal = true
	if not batteryContainer or not CanSpendFromConnectedContainer( batteryContainer, ITEMS.obj_consumable_battery, 1 ) then
		useExternal = false
		batteryContainer = self.shape.interactable:getContainer( 0 )
	end

	-- Check bearings
	local bearings = GetBearingEnabledJoints( self.interactable )

	-- Update motor gear when a steering is added
	if not hadInput and hasInput then
		if self.saved.gearIdx == 1 then
			self:sv_setGear( 2 )
		end
	end

	-- Consume fuel for fuel points
	local canSpend = false
	if self.batteryPoints <= 0 then
		if useExternal then
			canSpend = CanSpendFromConnectedContainer( batteryContainer, ITEMS.obj_consumable_battery, 1 )
		else
			canSpend = sm.container.canSpend( batteryContainer, ITEMS.obj_consumable_battery, 1 )
		end
	end

	local gearIdx = self.saved.gearIdx
	if sprint then
		gearIdx = math.min( gearIdx + 1, #self.level.gears )
	end
	
	-- Control engine
	if self.batteryPoints > 0 or canSpend or useCreativeBattery then
		local batteryCost = 0
		if (active and direction ~= 0) and not useCreativeBattery then
			-- Consume fuel points
			local appliedImpulseCost = 0.015625
			for _, bearing in ipairs( bearings ) do
				if bearing.appliedImpulse * bearing.angularVelocity < 0 then -- No added fuel cost if the bearing is decelerating
					batteryCost = batteryCost + math.abs( bearing.appliedImpulse ) * appliedImpulseCost
				end
			end
			batteryCost = math.min( batteryCost, math.sqrt( batteryCost / 7.5 ) * 7.5 )

			self.batteryPoints = self.batteryPoints - batteryCost

			if self.batteryPoints <= 0 and batteryCost > 0 then
				local consumeResult = TryConsumePowerResource( self.interactable, ITEMS.obj_consumable_battery, sm.interactable.connectionType.electricity )
				if consumeResult == PowerConsumeType.resource then
					self.batteryPoints = self.batteryPoints + self.level.pointsPerBattery
				end
			end
		end
		if self.active ~= ( self.batteryPoints > 0 and batteryCost > 0 ) then
			self.interactable:setPublicData( { isActive = ( self.batteryPoints > 0 and batteryCost > 0 ) } )
			self.active = ( self.batteryPoints > 0 and batteryCost > 0 )
		end
		self:controlEngine( direction, active, gearIdx )
	else
		if self.active == true then
			self.interactable:setPublicData( { isActive = false } )
			self.active = false
		end
		self:controlEngine( 0, false, gearIdx )
	end

	-- Update rotational joints
	self:updateBearings( bearings, gearIdx, self.hasBattery or useCreativeBattery, sprint )

	self:sv_updateFuelStatus( batteryContainer, useExternal )

	-- Storage table dirty
	if self.dirtyStorageTable then
		self.storage:save( self.saved )
		self.dirtyStorageTable = false
	end

	-- Client table dirty
	if self.dirtyClientTable then
		self.network:setClientData( { gearIdx = self.saved.gearIdx, engineHasFuel = self.hasBattery or useCreativeBattery } )
		self.dirtyClientTable = false
	end
end

--[[ Client ]]

function ElectricEngine.client_onCreate( self )
	local level = EngineLevels[tostring( self.shape:getShapeUuid() )]
	self.level = level
	self.client_gearIdx = 1
	self.effect = sm.effect.createEffect( level.effect, self.interactable )
	self.engineHasFuel = false
	self.motorPower = 0
	self.bearingImpulses = {}
	self.fuelAlert = false
end

function ElectricEngine.client_onClientDataUpdate( self, params )
	if self.gui then
		if self.gui:isActive() and params.gearIdx ~= self.client_gearIdx then
			self.gui:setSliderPosition("Setting", params.gearIdx - 1 )
		end
	end

	self.client_gearIdx = params.gearIdx
	self.interactable:setPoseWeight( 0, params.gearIdx / #self.level.gears )

	self.engineHasFuel = params.engineHasFuel
end

function ElectricEngine.client_onDestroy( self )
	self.effect:destroy()

	if self.gui then
		self.gui:close()
		self.gui:destroy()
		self.gui = nil
	end
end

function ElectricEngine.client_onFixedUpdate( self )
	local active, direction, sprint, externalFuelTank, hasInput, driverCharacter = self:getInputs()

	if self.engineHasFuel or driverCharacter == nil then
		self.fuelAlert = false
	elseif driverCharacter and self.fuelAlert == false and sm.localPlayer.getPlayer() == driverCharacter:getPlayer() then
		self.fuelAlert = true
		NotificationManager.Cl_AddGenericNotification( "#{INFO_OUT_OF_ENERGY}" )
	end

	if self.gui then
		self.gui:setVisible( "FuelContainer", not externalFuelTank )
	end

	if sm.isHost then
		return
	end

	local gearIdx = self.client_gearIdx
	if sprint then
		gearIdx = math.min( gearIdx + 1, #self.level.gears )
	end

	-- Control engine
	if self.engineHasFuel then
		self:controlEngine( direction, active, gearIdx )
	else
		self:controlEngine( 0, false, gearIdx )
	end

	-- Update rotational joints
	local bearings = GetBearingEnabledJoints( self.interactable )
	self:updateBearings( bearings, gearIdx, self.engineHasFuel, sprint )
end

function ElectricEngine.client_onUpdate( self, dt )
	local active, direction, sprint = self:getInputs()
	self:cl_updateEffect( direction, active, sprint )

	if self.bearingModeGui and self.interactable:hasChanged( self.bearingModeUpdateTick ) then
		local customData = self.interactable:getJointCustomData( self.bearingModeJoint )
		self:cl_updateBearingModeGui( customData and customData.bearingMode )
		self.bearingModeUpdateTick = sm.game.getCurrentTick()
	end
end

function ElectricEngine.client_onInteract( self, character, state )
	if state == true then
		self.gui = sm.gui.createEngineGui()

		self.gui:setText( "Name", "#{CONTROLLER_ENGINE_ELECTRIC_TITLE}" )
		self.gui:setText( "Interaction", "#{CONTROLLER_ENGINE_INSTRUCTION}" )
		self.gui:setOnCloseCallback( "cl_onGuiClosed" )
		self.gui:setSliderCallback( "Setting", "cl_onSliderChange" )
		self.gui:setSliderData( "Setting", #self.level.gears, self.client_gearIdx - 1 )
		self.gui:setIconImage( "Icon", self.shape:getShapeUuid() )
		self.gui:setButtonCallback( "Upgrade", "cl_onUpgradeClicked" )

		local batteryContainer = self.shape.interactable:getContainer( 0 )

		if batteryContainer then
			self.gui:setContainer( "Fuel", batteryContainer )
		end

		local _, _, _, externalFuelContainer = self:getInputs()
		if externalFuelContainer then
			self.gui:setVisible( "FuelContainer", true )
		end

		if not sm.game.getEnableFuelConsumption() then
			self.gui:setVisible( "BackgroundBattery", false )
			self.gui:setVisible( "FuelGrid", false )
		end

		self.gui:open()

		if self.level then
			if self.level.upgrade then
				local nextLevel = EngineLevels[ self.level.upgrade ]
				self.gui:setData( "UpgradeInfo", { Gears = nextLevel.gearCount - self.level.gearCount, Bearings = nextLevel.bearingCount - self.level.bearingCount, Efficiency = string.format( "+%.f%%", ( nextLevel.pointsPerBattery / self.level.pointsPerBattery - 1 ) * 100 ) } )
				self.gui:setIconImage( "UpgradeIcon", sm.uuid.new( self.level.upgrade ) )
			else
				self.gui:setVisible( "UpgradeIcon", false )
				self.gui:setData( "UpgradeInfo", nil )
			end

			self.gui:setText( "SubTitle", self.level.title )
			self.gui:setSliderRangeLimit( "Setting", self.level.gearCount )

			if sm.game.getEnableUpgrade() and self.level.cost then
				local inventory = sm.localPlayer.getPlayer():getInventory()
				local availableKits = sm.container.totalQuantity( inventory, ITEMS.obj_consumable_component )
				local upgradeData = { cost = self.level.cost, available = availableKits }
				self.gui:setData( "Upgrade", upgradeData )
			else
				self.gui:setVisible( "Upgrade", false )
			end
		end

	end
end

function ElectricEngine.client_canInteractThroughJoint( self, character, joint )
	if not self.shape.body.connectable then
		return false
	end
	if not joint:getBearingEnabled() then
		return false
	end
	local level = EngineLevels[tostring( self.shape:getShapeUuid() )]
	return level.allowAdjustingJoints
end

function ElectricEngine.sv_n_setBearingMode( self, params )
	self.interactable:setJointCustomData( params.joint, { bearingMode = params.mode } )
end

function ElectricEngine.client_onInteractThroughJoint( self, character, state, joint )
	if state then
		self.bearingModeJoint = joint
		self.bearingModeGui = sm.jsonGui.createGui( { isInteractive = true, needsCursor = true } )
		local customData = self.interactable:getJointCustomData( self.bearingModeJoint )
		self:cl_updateBearingModeGui( customData and customData.bearingMode )
		self.bearingModeUpdateTick = sm.game.getCurrentTick()
	end
end

function ElectricEngine.cl_updateBearingModeGui( self, bearingMode )
	if self.bearingModeGui then
		BearingSettingsGui.index["ButtonStandard"].StateSelected = bearingMode == nil
		BearingSettingsGui.index["ButtonDifferentialLeft"].StateSelected = bearingMode == 1
		BearingSettingsGui.index["ButtonDifferentialRight"].StateSelected = bearingMode == 2
		self.bearingModeGui:render( BearingSettingsGui.root )
	end
end

local BearingModes = {
	["ButtonStandard"] = nil,
	["ButtonDifferentialLeft"] = 1,
	["ButtonDifferentialRight"] = 2
}

function ElectricEngine.cl_onBearingSettingClick( self, buttonName )
	local bearingMode = BearingModes[buttonName]
	if not sm.isHost then
		self:cl_updateBearingModeGui( bearingMode )
	end
	self.network:sendToServer( "sv_n_setBearingMode", { joint = self.bearingModeJoint, mode = bearingMode } )
end

function ElectricEngine.cl_onBearingSettingsClose( self )
	self.bearingModeJoint = nil
	self.bearingModeUpdateTick = nil
	self.bearingModeGui = nil
end

function ElectricEngine.client_getAvailableParentConnectionCount( self, connectionType )
	if bit.band( connectionType, bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.power ) ) ~= 0 then
		return 1 - #self.interactable:getParents( bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.power ) )
	end
	if bit.band( connectionType, sm.interactable.connectionType.electricity ) ~= 0 then
		return 1 - #self.interactable:getParents( sm.interactable.connectionType.electricity )
	end
	return 0
end

function ElectricEngine.client_getAvailableChildConnectionCount( self, connectionType )
	if connectionType ~= sm.interactable.connectionType.bearing then
		return 0
	end
	local maxBearingCount = self.level.bearingCount or 255
	return maxBearingCount - #self.interactable:getChildren( sm.interactable.connectionType.bearing )
end

function ElectricEngine.cl_onGuiClosed( self )
	self.gui:destroy()
	self.gui = nil
end

function ElectricEngine.cl_onSliderChange( self, sliderName, sliderPos )
	self.network:sendToServer( "sv_setGear", sliderPos + 1 )
	self.client_gearIdx = sliderPos + 1
end

function ElectricEngine.cl_onUpgradeClicked( self, buttonName )
	print( "upgrade clicked" )
	self.network:sendToServer("sv_n_tryUpgrade", sm.localPlayer.getPlayer() )
end

function ElectricEngine.cl_updateEffect( self, direction, active, sprint )
	local gearIdx = self.client_gearIdx
	if sprint then
		gearIdx = math.min( gearIdx + 1, #self.level.gears )
	end

	local gear = self.level.gears[gearIdx]

	local load = 0.0
	local appliedImpulse = 0.0
	local velocity = 0.0

	local bearings = GetBearingEnabledJoints( self.interactable )
	if #bearings > 0 then
		for _, currentBearing in ipairs( bearings ) do

			velocity = velocity + ( currentBearing:isReversed() and 1.0 or -1.0 ) * currentBearing:getAngularVelocity() 

			local prevImpulse = self.bearingImpulses[currentBearing:getId()]
			if prevImpulse == nil then				
				self.bearingImpulses[currentBearing:getId()] = 0.0
				prevImpulse = 0.0
			end

			local impulseDiff = math.abs( currentBearing:getAppliedImpulse() ) - prevImpulse
			if impulseDiff > 0  then
				prevImpulse = prevImpulse + math.min( impulseDiff, gear.power / 1.5 )
			else
				prevImpulse = prevImpulse + math.min( impulseDiff, gear.power / 3.0 )
			end

			appliedImpulse = appliedImpulse + prevImpulse
		end

		load = appliedImpulse / #bearings
		velocity = velocity / #bearings
	end

	local onLift = self.shape:getBody():isOnLift()

	if ( self.effect:isPlaying() == false or self.effect:isBreakSustaining() == true ) and #bearings > 0 and not onLift and math.abs( self.motorPower ) > 0 then
		self.effect:start()
	elseif ( self.effect:isPlaying() == true and self.effect:isBreakSustaining() == false ) and ( onLift or #bearings == 0 or self.motorPower == 0 ) then
		self.effect:setParameter( "load", 0.5 )
		self.effect:setParameter( "rpm", 0 )
		self.effect:stopBreakSustain()
	end
	
	local maxRPM = (gearIdx + 1) / #self.level.gears
	local rpm = math.min( ( math.abs( velocity ) / gear.velocity ) * maxRPM, maxRPM )

	if self.effect:isPlaying() then
		self.effect:setParameter( "rpm", rpm )
		self.effect:setParameter( "load", load * 0.5 + 0.5 )
	end

end

function ElectricEngine.sv_n_tryUpgrade( self, _, player )

	if self.level and self.level.upgrade then
		local function fnUpgrade()
			local nextLevel = EngineLevels[self.level.upgrade]
			assert( nextLevel )
		
			self.network:sendToClients( "cl_n_onUpgrade", self.level.upgrade )

			self.shape:replaceShape( sm.uuid.new( self.level.upgrade ) )
			self.level = nextLevel
		end

		if sm.game.getEnableUpgrade() then
			local inventory = player:getInventory()

			if sm.container.totalQuantity( inventory, ITEMS.obj_consumable_component ) >= self.level.cost then

				if sm.container.beginTransaction() then
					sm.container.spend( inventory, ITEMS.obj_consumable_component, self.level.cost, true )

					if sm.container.endTransaction() then
						fnUpgrade()
					end
				end
			else
				print( "Cannot afford upgrade" )
			end
		end
	else
		print( "Can't be upgraded" )
	end

end

function ElectricEngine.cl_n_onUpgrade( self, upgrade )
	local level = EngineLevels[upgrade]

	if self.gui and self.gui:isActive() then
		self.gui:setIconImage( "Icon", sm.uuid.new( upgrade ) )

		if sm.game.getEnableUpgrade() and level.cost then
			local inventory = sm.localPlayer.getPlayer():getInventory()
			local availableKits = sm.container.totalQuantity( inventory, ITEMS.obj_consumable_component )
			local upgradeData = { cost = level.cost, available = availableKits }
			self.gui:setData( "Upgrade", upgradeData )
		else
			self.gui:setVisible( "Upgrade", false )
		end

		self.gui:setText( "SubTitle", level.title )
		self.gui:setSliderRangeLimit( "Setting", level.gearCount )
		if level.upgrade then
			local nextLevel = EngineLevels[level.upgrade]
			self.gui:setData( "UpgradeInfo", { Gears = nextLevel.gearCount - level.gearCount, Bearings = nextLevel.bearingCount - level.bearingCount, Efficiency = string.format( "+%.f%%", ( nextLevel.pointsPerBattery / level.pointsPerBattery - 1 ) * 100 ) } )
			self.gui:setIconImage( "UpgradeIcon", sm.uuid.new( level.upgrade ) )
		else
			self.gui:setVisible( "UpgradeIcon", false )
			self.gui:setData( "UpgradeInfo", nil )
		end
	end

	self.effect = sm.effect.createEffect( level.effect, self.interactable )
	sm.effect.playHostedEffect( "Part - Upgrade", self.interactable )

	self.level = level
end
-- GasEngine.lua --
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

GasEngine = class()
GasEngine.maxParentCount = 2
GasEngine.maxChildCount = 255
GasEngine.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.power + sm.interactable.connectionType.gasoline
GasEngine.connectionOutput = sm.interactable.connectionType.bearing
GasEngine.colorNormal = sm.color.new( 0xff8000ff )
GasEngine.colorHighlight = sm.color.new( 0xff8000ff )
GasEngine.connectIcon = "gas"
GasEngine.connectIconScale = 0.75

GasEngine.poseWeightCount = 1

local obj_survivalobject_gasengine = sm.uuid.new( "f56d7788-122e-421a-b63b-2938466125e9" )

local TutorialActivationDistance = 7.5

local ScrapGears = {
	{ power = 0 },
	{ power = 30 },
	{ power = 60 },
	{ power = 90 }
}

local Gears = {
	{ power = 0 },
	{ power = 30 },
	{ power = 60 },
	{ power = 90 },
	{ power = 150 }, -- 1
	{ power = 240 },
	{ power = 390 }, -- 2
	{ power = 630 },
	{ power = 1020 }, -- 3
	{ power = 1650 },
	{ power = 2670 }, -- 4
	{ power = 4320 },
	{ power = 6990 }, -- 5
}

--[[
local gearsFromCreative = {
	{ power = 0 },
	{ power = 8 },
	{ power = 16 },
	{ power = 32 },
	{ power = 64 },
	{ power = 128 },
	{ power = 256 },
	{ power = 512 },
	{ power = 1024 }
}
]]

local EngineLevels = {
	[tostring(ITEMS.obj_scrap_gasengine)] = {
		gears = ScrapGears,
		effect = "GasEngine - Scrap",
		title = "#{CONTROLLER_ENGINE_GAS_SCRAP}",
		gearCount = #ScrapGears,
		bearingCount = 2,
		pointsPerFuel = 3000
	},
	[tostring(ITEMS.obj_interactive_gasengine_01)] = {
		gears = Gears,
		effect = "GasEngine - Level 1",
		upgrade = tostring(ITEMS.obj_interactive_gasengine_02),
		cost = 4,
		title = "#{LEVEL} 1",
		gearCount = 5,
		bearingCount = 2,
		pointsPerFuel = 4000
	},
	[tostring(ITEMS.obj_interactive_gasengine_02)] = {
		gears = Gears,
		effect = "GasEngine - Level 2",
		upgrade = tostring(ITEMS.obj_interactive_gasengine_03),
		cost = 6,
		title = "#{LEVEL} 2",
		gearCount = 7,
		bearingCount = 4,
		pointsPerFuel = 6000
	},
	[tostring(ITEMS.obj_interactive_gasengine_03)] = {
		gears = Gears,
		effect = "GasEngine - Level 3",
		upgrade = tostring(ITEMS.obj_interactive_gasengine_04),
		cost = 8,
		title = "#{LEVEL} 3",
		gearCount = 9,
		bearingCount = 6,
		pointsPerFuel = 9000
	},
	[tostring(ITEMS.obj_interactive_gasengine_04)] = {
		gears = Gears,
		effect = "GasEngine - Level 4",
		upgrade = tostring(ITEMS.obj_interactive_gasengine_05),
		cost = 10,
		title = "#{LEVEL} 4",
		gearCount = 11,
		bearingCount = 8,
		pointsPerFuel = 13500
	},
	[tostring(ITEMS.obj_interactive_gasengine_05)] = {
		gears = Gears,
		effect = "GasEngine - Level 5",
		title = "#{LEVEL} 5",
		gearCount = #Gears,
		bearingCount = 10,
		pointsPerFuel = 20250
	},
	[tostring(obj_survivalobject_gasengine)] = {
		gears = Gears,
		effect = "GasEngine - Level 5",
		title = "#{LEVEL} 5",
		gearCount = #Gears,
		bearingCount = 10,
		pointsPerFuel = 20250,
		creativeFuel = true
	}
}

local RadPerSecond_100KmPerHourOn3BlockDiameterTyres = 74.074074

--[[ Server ]]

function GasEngine.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	-- Validate that loaded container only holds the expected item
	if container then
		local hasMismatchedItem = false
		for slot = 0, container:getSize() - 1 do
			local item = container:getItem( slot )
			if not item.uuid:isNil() and item.uuid ~= ITEMS.obj_consumable_gas then
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
	container:setFilters( { ITEMS.obj_consumable_gas } )

	-- Remove any excess containers, keeping the fuel container at index 0
	for i = 1, 15 do
		if self.shape.interactable:getContainer( i ) then
			self.shape.interactable:removeContainer( i )
		end
	end

	local level = EngineLevels[tostring( self.shape:getShapeUuid() )]
	assert(level)
	if level.fn then
		level.fn( self )
	end
	if level.gears == ScrapGears then
		self.scrapOffset = math.random(0, 80)
	else
		self.scrapOffset = 0
	end
	self.pointsPerFuel = level.pointsPerFuel
	self.gears = level.gears
	self.creativeFuel = level.creativeFuel
	self.active = false
	self:server_init()
end

function GasEngine.server_onRefresh( self )
	self:server_init()
end

function GasEngine.server_init( self )

	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.gearIdx == nil then
		self.saved.gearIdx = 1
	end
	if self.saved.fuelPoints == nil then
		self.saved.fuelPoints = 0
	end

	self.power = 0
	self.motorVelocity = 0
	self.motorImpulse = 0
	self.fuelPoints = self.saved.fuelPoints
	self.hasFuel = false
	self.dirtyStorageTable = false
	self.dirtyClientTable = false

	self:sv_setGear( self.saved.gearIdx )
end

function GasEngine.sv_setGear( self, gearIdx )
	self.saved.gearIdx = gearIdx
	self.dirtyStorageTable = true
	self.dirtyClientTable = true
end

function GasEngine.sv_updateFuelStatus( self, fuelContainer, useExternal )

	if self.saved.fuelPoints ~= self.fuelPoints then
		self.saved.fuelPoints = self.fuelPoints
		self.dirtyStorageTable = true
	end

	local hasFuel = ( self.fuelPoints > 0 )
	if not hasFuel then
		if useExternal then
			hasFuel = hasFuel or CanSpendFromConnectedContainer( fuelContainer, ITEMS.obj_consumable_gas, 1 )
		else
			hasFuel = hasFuel or sm.container.canSpend( fuelContainer, ITEMS.obj_consumable_gas, 1 )
		end
	end
	
	if self.hasFuel ~= hasFuel then
		self.hasFuel = hasFuel
		self.dirtyClientTable = true
	end

end

function GasEngine.controlEngine( self, direction, active, timeStep, gearIdx )

	direction = clamp( direction, -1, 1 )
	if ( math.abs( direction ) > 0 or not active ) then
		self.power = self.power + timeStep
	else
		self.power = self.power - timeStep
	end
	self.power = clamp( self.power, 0, 1 )

	if direction == 0 and active then
		self.power = 0
	end

	if self.gears == ScrapGears then
		if active then
			self.motorVelocity = direction * RadPerSecond_100KmPerHourOn3BlockDiameterTyres
			local t = ( sm.game.getServerTick() + self.scrapOffset ) / 40 * 2.0 * math.pi / 2
			local scale = math.sin( t )
			scale = sm.util.clamp( 1 + scale * 0.4, 0, 1 )
			self.motorImpulse = self.power * self.gears[gearIdx].power * scale
			--print("Velocity: ", self.motorVelocity, " - Impulse: ", self.motorImpulse)
		else
			self.motorVelocity = 0
			self.motorImpulse = 0
		end
	else
		self.motorVelocity = ( active and direction or 0 ) * RadPerSecond_100KmPerHourOn3BlockDiameterTyres
		self.motorImpulse = ( active and self.power or 2 ) * self.gears[gearIdx].power
	end
end

function GasEngine.getInputs( self )
	local active = true
	local direction = 1
	local sprint = false
	local fuelContainer = nil
	local hasInput = false
	local currentDriver = false

	local parents = self.interactable:getParents()
	if parents[2] then
		if parents[2]:hasOutputType( sm.interactable.connectionType.logic ) then
			active = parents[2]:isActive()
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
		if parents[2]:hasOutputType( sm.interactable.connectionType.gasoline ) then
			fuelContainer = parents[2]
		end
	end
	if parents[1] then
		if parents[1]:hasOutputType( sm.interactable.connectionType.logic ) then
			active = parents[1]:isActive()
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
		if parents[1]:hasOutputType( sm.interactable.connectionType.gasoline ) then
			fuelContainer = parents[1]
		end
	end

	return active, direction, sprint, fuelContainer, hasInput, currentDriver
end

function GasEngine.server_onFixedUpdate( self, timeStep )
	-- Check engine connections
	local hadInput = self.hasInput == nil and true or self.hasInput --Pretend to have had input if nil to avoid starting engines at load
	local active, direction, sprint, fuelContainer, hasInput = self:getInputs()
	self.hasInput = hasInput
	local useCreativeFuel = not sm.game.getEnableFuelConsumption() and fuelContainer == nil or self.creativeFuel

	local useExternal = true
	-- Check fuel container
	if not fuelContainer or not CanSpendFromConnectedContainer( fuelContainer, ITEMS.obj_consumable_gas, 1 ) then
		useExternal = false
		fuelContainer = self.shape.interactable:getContainer( 0 )
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
	if self.fuelPoints <= 0 then
		if useExternal then
			canSpend = CanSpendFromConnectedContainer( fuelContainer, ITEMS.obj_consumable_gas, 1 )
		else
			canSpend = sm.container.canSpend( fuelContainer, ITEMS.obj_consumable_gas, 1 )
		end
	end

	local gearIdx = self.saved.gearIdx
	if sprint then
		gearIdx = math.min( gearIdx + 1, #self.gears )
	end

	-- Control engine
	if self.fuelPoints > 0 or canSpend or useCreativeFuel then
		local fuelCost = 0
		if (active and direction ~= 0) and not useCreativeFuel then
			-- Consume fuel points
			local appliedImpulseCost = 0.015625
			for _, bearing in ipairs( bearings ) do
				if bearing.appliedImpulse * bearing.angularVelocity < 0 then -- No added fuel cost if the bearing is decelerating
					fuelCost = fuelCost + math.abs( bearing.appliedImpulse ) * appliedImpulseCost
				end
			end
			fuelCost = math.min( fuelCost, math.sqrt( fuelCost / 7.5 ) * 7.5 )

			self.fuelPoints = self.fuelPoints - fuelCost

			if self.fuelPoints <= 0 and fuelCost > 0 then
				local consumeResult = TryConsumePowerResource( self.interactable, ITEMS.obj_consumable_gas, sm.interactable.connectionType.gasoline )
				if consumeResult == PowerConsumeType.resource then
					self.fuelPoints = self.pointsPerFuel
				end
			end
		end
		if self.active ~= ( self.fuelPoints > 0 and fuelCost > 0 ) then
			self.interactable:setPublicData( { isActive = self.fuelPoints > 0 and fuelCost > 0 } )
			self.active = ( self.fuelPoints > 0 and fuelCost > 0 )
		end
		self:controlEngine( direction, active, timeStep, gearIdx )
	else
		if self.active == true then
			self.interactable:setPublicData( { isActive = false } )
			self.active = false
		end
		self:controlEngine( 0, false, timeStep, gearIdx )
	end

	-- Update rotational joints
	for _, bearing in ipairs( bearings ) do
		bearing:setMotorVelocity( self.motorVelocity, self.motorImpulse )
	end

	self:sv_updateFuelStatus( fuelContainer, useExternal )

	-- Storage table dirty
	if self.dirtyStorageTable then
		self.storage:save( self.saved )
		self.dirtyStorageTable = false
	end

	-- Client table dirty
	if self.dirtyClientTable then
		self.network:setClientData( { gearIdx = self.saved.gearIdx, engineHasFuel = self.hasFuel or useCreativeFuel, scrapOffset = self.scrapOffset } )
		self.dirtyClientTable = false
	end
end

--[[ Client ]]

function GasEngine.client_onCreate( self )
	local level = EngineLevels[tostring( self.shape:getShapeUuid() )]
	self.gears = level.gears
	self.client_gearIdx = 1
	self.effect = sm.effect.createEffect( level.effect, self.interactable )
	self.engineHasFuel = false
	self.scrapOffset = self.scrapOffset or 0
	self.currentDriver = nil
	self.power = 0
	self.fuelAlert = false
end

function GasEngine.client_onClientDataUpdate( self, params )

	if self.gui then
		if self.gui:isActive() and params.gearIdx ~= self.client_gearIdx then
			self.gui:setSliderPosition("Setting", params.gearIdx - 1 )
		end
	end

	self.client_gearIdx = params.gearIdx
	self.interactable:setPoseWeight( 0, params.gearIdx / #self.gears )

	if params.engineHasFuel then
		self.effect:setParameter("gas", 0.0 )
	else
		self.effect:setParameter("gas", 1.0 )
	end

	self.engineHasFuel = params.engineHasFuel
	self.scrapOffset = params.scrapOffset
end

function GasEngine.client_onDestroy( self )
	self.effect:destroy()

	if self.gui then
		self.gui:close()
		self.gui:destroy()
		self.gui = nil
	end
end

function GasEngine.client_onFixedUpdate( self, timeStep )
	local active, direction, sprint, externalFuelTank, hasInput, driverCharacter = self:getInputs()

	if self.engineHasFuel or driverCharacter == nil then
		self.fuelAlert = false
	elseif driverCharacter and self.fuelAlert == false and sm.localPlayer.getPlayer() == driverCharacter:getPlayer() then
		self.fuelAlert = true
		if TutorialManager.Cl_HasWatched( TutorialEvent.CreationNeedsGas ) then
			NotificationManager.Cl_AddGenericNotification( "#{INFO_OUT_OF_FUEL}" )
		else
			TutorialManager.Cl_TutorialEvent( TutorialEvent.CreationNeedsGas )
		end
	end

	if self.gui then
		self.gui:setVisible( "FuelContainer", not externalFuelTank )
	end

	if sm.isHost then
		return
	end

	local gearIdx = self.client_gearIdx
	if sprint then
		gearIdx = math.min( gearIdx + 1, #self.gears )
	end

	-- Control engine
	if self.engineHasFuel then
		if hasInput == false then
			self.power = 1
		end
		self:controlEngine( direction, active, timeStep, gearIdx )
	else
		self:controlEngine( 0, false, timeStep, gearIdx )
	end

	-- Update rotational joints
	local bearings = GetBearingEnabledJoints( self.interactable )
	for _, bearing in ipairs( bearings ) do
		bearing:setMotorVelocity( self.motorVelocity, self.motorImpulse )
	end
end

function GasEngine.client_onUpdate( self, dt )

	local active, direction, sprint = self:getInputs()

	self:cl_updateEffect( direction, active, sprint )
end

function GasEngine.client_onInteract( self, character, state )
	if state == true then
		self.gui = sm.gui.createEngineGui()

		self.gui:setText( "Name", "#{CONTROLLER_ENGINE_GAS_TITLE}" )
		self.gui:setText( "Interaction", "#{CONTROLLER_ENGINE_INSTRUCTION}" )
		self.gui:setOnCloseCallback( "cl_onGuiClosed" )
		self.gui:setSliderCallback( "Setting", "cl_onSliderChange" )
		self.gui:setSliderData( "Setting", #self.gears, self.client_gearIdx - 1 )
		self.gui:setIconImage( "Icon", self.shape:getShapeUuid() )
		self.gui:setButtonCallback( "Upgrade", "cl_onUpgradeClicked" )

		local fuelContainer = self.shape.interactable:getContainer( 0 )

		if fuelContainer then
			self.gui:setContainer( "Fuel", fuelContainer )
		end

		local _, _, _, externalFuelContainer = self:getInputs()
		if externalFuelContainer then
			self.gui:setVisible( "FuelContainer", true )
		end

		if not sm.game.getEnableFuelConsumption() then
			self.gui:setVisible( "BackgroundGas", false )
			self.gui:setVisible( "FuelGrid", false )
		end

		self.gui:open()

		local level = EngineLevels[ tostring( self.shape:getShapeUuid() ) ]
		if level then
			if level.upgrade then
				local nextLevel = EngineLevels[ level.upgrade ]
				self.gui:setData( "UpgradeInfo", { Gears = nextLevel.gearCount - level.gearCount, Bearings = nextLevel.bearingCount - level.bearingCount, Efficiency = string.format( "+%.f%%", ( nextLevel.pointsPerFuel / level.pointsPerFuel - 1 ) * 100 ) } )
				self.gui:setIconImage( "UpgradeIcon", sm.uuid.new( level.upgrade ) )
			else
				self.gui:setVisible( "UpgradeIcon", false )
				self.gui:setData( "UpgradeInfo", nil )
			end

			self.gui:setText( "SubTitle", level.title )
			self.gui:setSliderRangeLimit( "Setting", level.gearCount )

			if sm.game.getEnableUpgrade() and level.cost then
				local inventory = sm.localPlayer.getPlayer():getInventory()
				local availableKits = sm.container.totalQuantity( inventory, ITEMS.obj_consumable_component )
				local upgradeData = { cost = level.cost, available = availableKits }
				self.gui:setData( "Upgrade", upgradeData )
			else
				self.gui:setVisible( "Upgrade", false )
			end
		end
	end
end

function GasEngine.client_getAvailableParentConnectionCount( self, connectionType )
	if bit.band( connectionType, bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.power ) ) ~= 0 then
		return 1 - #self.interactable:getParents( bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.power ) )
	end
	if bit.band( connectionType, sm.interactable.connectionType.gasoline ) ~= 0 then
		return 1 - #self.interactable:getParents( sm.interactable.connectionType.gasoline )
	end
	return 0
end

function GasEngine.client_getAvailableChildConnectionCount( self, connectionType )
	if connectionType ~= sm.interactable.connectionType.bearing then
		return 0
	end
	local level = EngineLevels[tostring( self.shape:getShapeUuid() )]
	assert(level)
	local maxBearingCount = level.bearingCount or 255
	return maxBearingCount - #self.interactable:getChildren( sm.interactable.connectionType.bearing )
end

function GasEngine.cl_onGuiClosed( self )
	self.gui:destroy()
	self.gui = nil
end

function GasEngine.cl_onSliderChange( self, sliderName, sliderPos )
	self.network:sendToServer( "sv_setGear", sliderPos + 1 )
	self.client_gearIdx = sliderPos + 1
end

function GasEngine.cl_onUpgradeClicked( self, buttonName )
	print( "upgrade clicked" )
	self.network:sendToServer("sv_n_tryUpgrade", sm.localPlayer.getPlayer() )
end

function GasEngine.cl_updateEffect( self, direction, active, sprint )
	local gearIdx = self.client_gearIdx
	if sprint then
		gearIdx = math.min( gearIdx + 1, #self.gears )
	end

	local RadPerSecond_100KmPerHourOn3BlockDiameterTyres = 74.074074
	local avgImpulse = 0
	local avgVelocity = 0

	local bearings = GetBearingEnabledJoints( self.interactable )
	if #bearings > 0 then
		for _, currentBearing in ipairs( bearings ) do
			avgImpulse = avgImpulse + math.abs( currentBearing.appliedImpulse )
			avgVelocity = avgVelocity + math.abs( currentBearing.angularVelocity )
		end

		avgImpulse = avgImpulse / #bearings
		avgVelocity = avgVelocity / #bearings

		avgVelocity = math.min( avgVelocity, RadPerSecond_100KmPerHourOn3BlockDiameterTyres )
	end

	local impulseFraction = 0
	local velocityFraction = avgVelocity / ( RadPerSecond_100KmPerHourOn3BlockDiameterTyres / 1.2 )

	if direction ~= 0 and self.gears[gearIdx].power > 0 then
		impulseFraction = math.abs( avgImpulse ) / self.gears[gearIdx].power
	end

	local maxRPM = 0.9 * (gearIdx / #self.gears)
	local rpm = 0.1

	if avgVelocity > 0 then
		rpm = rpm + math.min( velocityFraction * maxRPM, maxRPM )
	end

	local engineLoad = 0

	if direction ~= 0 then
		engineLoad = impulseFraction - math.min( velocityFraction, 1.0 )
	end

	local onLift = self.shape:getBody():isOnLift()
	if #self.interactable:getParents() == 0 then
		if ( self.effect:isPlaying() == false or self.effect:isBreakSustaining() == true ) and #bearings > 0 and not onLift and self.gears[gearIdx].power > 0 then
			self.effect:start()
		elseif ( self.effect:isPlaying() == true and self.effect:isBreakSustaining() == false ) and ( #bearings == 0 or onLift or self.gears[gearIdx].power == 0 ) then
			self.effect:setParameter( "load", 0.5 )
			self.effect:setParameter( "rpm", 0 )
			self.effect:stopBreakSustain()
		end
	else
		if ( self.effect:isPlaying() == true and self.effect:isBreakSustaining() == false ) and ( #bearings == 0 or onLift or active == false or self.gears[gearIdx].power == 0 ) then
			self.effect:setParameter( "load", 0.5 )
			self.effect:setParameter( "rpm", 0 )
			self.effect:stopBreakSustain()
		elseif ( self.effect:isPlaying() == false or self.effect:isBreakSustaining() == true ) and #bearings > 0 and not onLift and active == true and self.gears[gearIdx].power > 0 then
			self.effect:start()
		end
	end

	if self.effect:isPlaying() then
		self.effect:setParameter( "rpm", rpm )
		self.effect:setParameter( "load", engineLoad * 0.5 + 0.5 )
	end
end

function GasEngine.sv_n_tryUpgrade( self, player )

	local level = EngineLevels[tostring( self.shape:getShapeUuid() )]
	if level and level.upgrade then
		local function fnUpgrade()
			local nextLevel = EngineLevels[level.upgrade]
			assert( nextLevel )
			self.gears = nextLevel.gears
			self.network:sendToClients( "cl_n_onUpgrade", level.upgrade )

			if nextLevel.fn then
				nextLevel.fn( self )
			end

			self.shape:replaceShape( sm.uuid.new( level.upgrade ) )
		end

		if sm.game.getEnableUpgrade() then
			local inventory = player:getInventory()

			if sm.container.totalQuantity( inventory, ITEMS.obj_consumable_component ) >= level.cost then

				if sm.container.beginTransaction() then
					sm.container.spend( inventory, ITEMS.obj_consumable_component, level.cost, true )

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

function GasEngine.cl_n_onUpgrade( self, upgrade )
	local level = EngineLevels[upgrade]
	self.gears = level.gears
	self.pointsPerFuel = level.pointsPerFuel

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
			self.gui:setData( "UpgradeInfo", { Gears = nextLevel.gearCount - level.gearCount, Bearings = nextLevel.bearingCount - level.bearingCount, Efficiency = string.format( "+%.f%%", ( nextLevel.pointsPerFuel / level.pointsPerFuel - 1 ) * 100 ) } )
			self.gui:setIconImage( "UpgradeIcon", sm.uuid.new( level.upgrade ) )
		else
			self.gui:setVisible( "UpgradeIcon", false )
			self.gui:setData( "UpgradeInfo", nil )
		end
	end

	self.effect = sm.effect.createEffect( level.effect, self.interactable )
	sm.effect.playHostedEffect( "Part - Upgrade", self.interactable )
end
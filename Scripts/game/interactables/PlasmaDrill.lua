dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/interactables/DrillCasing.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

PlasmaDrill = class( nil )
PlasmaDrill.poseWeightCount = 1
PlasmaDrill.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity
PlasmaDrill.maxParentCount = 2
PlasmaDrill.maxChildCount = 0
PlasmaDrill.colorNormal = sm.color.new( 0xffca1aff )
PlasmaDrill.colorHighlight = sm.color.new( 0xfbd967ff )
PlasmaDrill.connectIcon = "electrical"
PlasmaDrill.connectIconScale = 0.75

local DrillUvFrameCount = 50 -- Number of frames in the drill UV animation, should be the same as the number of frames in the texture.
local EjectAnimDuration = 0.5 -- Duration of the eject animation
local EjectShapeDelay = 6 -- Delay in ticks between starting the eject animation and spawning the eject shape

local DrillLevels = {
	[tostring( ITEMS.obj_interactive_plasmadrill_lvl1 )] = {
		title = "#{LEVEL} 1",
		upgrade = tostring( ITEMS.obj_interactive_plasmadrill_lvl2 ),
		drillSpeed = 1,
		voxelDrillIntervalTicks = 4,
		pointsPerBattery = 2400,
		level = 1,
		maxSetting = 3,
		range = 10,
		cost = 5,
	},
	[tostring( ITEMS.obj_interactive_plasmadrill_lvl2 )] = {
		title = "#{LEVEL} 2",
		upgrade = tostring( ITEMS.obj_interactive_plasmadrill_lvl3 ),
		drillSpeed = 1.5,
		voxelDrillIntervalTicks = 4,
		pointsPerBattery = 2400,
		level = 2,
		maxSetting = 6,
		range = 15,
		cost = 20,
	},
	[tostring( ITEMS.obj_interactive_plasmadrill_lvl3 )] = {
		title = "#{LEVEL} 3",
		drillSpeed = 2.25,
		voxelDrillIntervalTicks = 4,
		pointsPerBattery = 2400,
		level = 3,
		maxSetting = 9,
		range = 22.5,
	}
}

local DrillSettings = {
	[1] = {
		radius = 2,
	},
	[2] = {
		radius = 2.25,
	},
	[3] = {
		radius = 2.5,
	},
	[4] = {
		radius = 2.75,
	},
	[5] = {
		radius = 3,
	},
	[6] = {
		radius = 3.25,
	},
	[7] = {
		radius = 3.5,
	},
	[8] = {
		radius = 3.75,
	},
	[9] = {
		radius = 4,
	}
}

local HitScanRadius = 0.375
local DrillWindupTicks = 60 -- Ticks before full effect
local SaveFrequency = 5 * 40

local ImpactVortexCooldownTime = 0.075
local ImpactVortexOffset = 1.5

local CeilingEffectCooldownTime = 1

function PlasmaDrill.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or {}
	self.sv.saved.casingMaterialAmounts = self.sv.saved.casingMaterialAmounts or {}
	self.sv.saved.batteryPower = self.sv.saved.batteryPower or 0
	self.sv.saved.settingsLevel = self.sv.saved.settingsLevel or 3
	self.storage:save( self.sv.saved )
	self.sv.hasCharge = self.sv.saved.batteryPower > 0
	self.sv.drillLevel = DrillLevels[tostring( self.shape:getShapeUuid() )]
	self.sv.container = self.shape.interactable:getContainer( 0 )
	if not self.sv.container then
		self.sv.container = self.shape:getInteractable():addContainer( 0, 1, 10 )
	end
	self.sv.container:setFilters( { ITEMS.obj_consumable_battery } )
	local index = math.floor( self:sv_getTotalCasingAmount() / GRAVEL_CASING_CAPACITY * DrillUvFrameCount )
	self.network:setClientData( { self.sv.saved.settingsLevel, self.sv.hasCharge, self:sv_isEmpty(), index } )
	self.sv.clientDataDirty = false
	self.sv.saveTickCounter = 0
	self.sv.voxelDrillTickCounter = 0
end

function PlasmaDrill.server_onRefresh( self )
	self.sv.areaTrigger = nil
end

function PlasmaDrill.getParents( self )
	local parents = self.interactable:getParents()
	local logic = nil
	local batteryContainer = nil
	if parents[2] then
		if parents[2]:hasOutputType( sm.interactable.connectionType.logic ) then
			logic = parents[2]
		elseif parents[2]:hasOutputType( sm.interactable.connectionType.electricity ) then
			batteryContainer = parents[2]:getContainer( 0 )
		end
	end
	if parents[1] then
		if parents[1]:hasOutputType( sm.interactable.connectionType.logic ) then
			logic = parents[1]
		elseif parents[1]:hasOutputType( sm.interactable.connectionType.electricity ) then
			batteryContainer = parents[1]:getContainer( 0 )
		end
	end
	return logic, batteryContainer
end

function PlasmaDrill.sv_isEmpty( self )
	local totalAmount = 0
	for _, amount in pairs( self.sv.saved.casingMaterialAmounts ) do
		totalAmount = totalAmount + amount
	end
	return totalAmount == 0
end

function PlasmaDrill.sv_getTotalCasingAmount( self )
	local totalAmount = 0
	for _, amount in pairs( self.sv.saved.casingMaterialAmounts ) do
		totalAmount = totalAmount + amount
	end
	return totalAmount
end

function PlasmaDrill.sv_tryConsumeBattery( self )

	if not sm.game.getEnableFuelConsumption() then
		self.sv.saved.batteryPower = self.sv.drillLevel.pointsPerBattery
		return true
	end

	local consumeResult = TryConsumePowerResource( self.interactable, ITEMS.obj_consumable_battery, sm.interactable.connectionType.electricity )

	if consumeResult == PowerConsumeType.failure then
		return false
	end

	if consumeResult == PowerConsumeType.resource then
		self.sv.saved.batteryPower = self.sv.drillLevel.pointsPerBattery
	end

	self.storage:save( self.sv.saved )
	return true
end

function PlasmaDrill.trigger_onStay( self, _, results )
	for i, body in ipairs( results ) do
		if sm.exists( body ) then
			local shape = body:getShape( 0 )
			if shape and sm.exists( shape ) then
				if shape.interactable and shape.interactable:getType() == "scripted" then
					local pubData = shape.interactable:getPublicData()
					if pubData and pubData.plasmaDrill then
						local item = pubData.plasmaDrill( 0.025 * self.sv.drillLevel.drillSpeed )
						if item then
							if item.uuid == ITEMS.obj_voxelmaterial_t4 then
								item.quantity = math.ceil( item.quantity * 0.5 )
							end
							self:sv_addMaterials( { item } )
						end
					end
				end
			end
		end
	end
end

function GetDrillIgnoreList()
	if CreativeGame == nil then
	return { hvs_loot, hvs_voxelspawncontainer }
	end
	return {}
end

function PlasmaDrill.server_onFixedUpdate( self, timeStep )
	self.sv.saveTickCounter = self.sv.saveTickCounter + 1

	if self.sv.saveTickCounter >= SaveFrequency then
		self.sv.saveTickCounter = 0
		self.storage:save( self.sv.saved )
	end

	local onLift = self.shape:getBody():isOnLift()
	if self.sv.saved.batteryPower <= 0 then
		if not onLift and self:sv_tryConsumeBattery() then
			if not self.sv.hasCharge then
				self.sv.hasCharge = true
				self.sv.clientDataDirty = true
			end
		else
			if self.sv.hasCharge then
				self.sv.hasCharge = false
				self.sv.clientDataDirty = true
			end
		end
	end


	local drilling = false
	local logic = self:getParents()
	self.interactable:setPublicData( { isActive = logic and logic:isActive() } )
	if not onLift and logic and logic:isActive() and self.sv.hasCharge then
		self.sv.saved.batteryPower = self.sv.saved.batteryPower - 1
		drilling = true
		self.sv.drillTicks = math.min( ( self.sv.drillTicks or 0 ) + 1, DrillWindupTicks )
	else
		self.sv.drillTicks = math.max( ( self.sv.drillTicks or 0 ) - 1, 0 )
	end

	if drilling then
		local drillSettings = DrillSettings[self.sv.saved.settingsLevel]

		if self.sv.areaTrigger and ( self.sv.drillLevel.range ~= self.sv.triggerRange or drillSettings.radius ~= self.sv.triggerRadius ) then
			self.sv.areaTrigger:destroy()
			self.sv.areaTrigger = nil
		end
		if self.sv.areaTrigger == nil then
			local filter = sm.areaTrigger.filter.dynamicBody
			self.sv.areaTrigger = sm.areaTrigger.createAttachedCylinder( self.shape, drillSettings.radius, self.sv.drillLevel.range / 2, sm.vec3.new( 0, self.sv.drillLevel.range / 2, 0 ), sm.quat.rotX90(), filter )
			self.sv.areaTrigger:bindOnStay( "trigger_onStay" )
			self.sv.triggerRange = self.sv.drillLevel.range
			self.sv.triggerRadius = drillSettings.radius
		end
		local groundFilter = sm.physics.filter.static + sm.physics.filter.dynamicBody + sm.physics.filter.character
		local from = self.shape.worldPosition
		local direction = self.shape.at
		local range = self.sv.drillLevel.range
		local to = from + direction * ( range - HitScanRadius )
		local hit, result = sm.physics.spherecast( from, to, HitScanRadius, self.shape.body, groundFilter, nil, GetDrillIgnoreList() )
		local point = sm.vec3.lerp( from, to, result.fraction ) + direction * HitScanRadius
		--sm.debugDraw.addArrow( "drillDirection"..self.shape.id, from, from + direction * range, sm.color.new( "0000ff" ) )
		--sm.debugDraw.addSphere( "drillFrom"..self.shape.id, from, HitScanRadius, sm.color.new( "0000ff" ) )
		--sm.debugDraw.addSphere( "drillTo"..self.shape.id, to, HitScanRadius, sm.color.new( "00007f" ) )
		--sm.debugDraw.addSphere( "drillHit"..self.shape.id, point, 0.1, sm.color.new( "ff0000" ) )

		if hit then
			if result.type == "harvestable" then
				local harvestable = result:getHarvestable()
				local pubData = harvestable:getPublicData()
				if pubData and pubData.drillLevel and self.sv.saved.settingsLevel >= pubData.drillLevel then
					local progress = timeStep * self.sv.drillLevel.drillSpeed
					sm.event.sendToHarvestable( harvestable, "sv_e_plasmaDrill", { position = result.pointWorld, direction = direction, drill = self.interactable, progress = progress }, sm.event.types.instant )
				end
			elseif result.type == "body" then
				local hitShape = result:getShape()
				local interactable = hitShape:getInteractable()
				local pubData = interactable and interactable:getType() == "scripted" and interactable:getPublicData() or nil
				if pubData and pubData.drillLevel and self.sv.saved.settingsLevel >= pubData.drillLevel then
					local progress = timeStep * self.sv.drillLevel.drillSpeed
					sm.event.sendToInteractable( interactable, "sv_e_plasmaDrill", { position = result.pointWorld, direction = direction, drill = self.interactable, progress = progress }, sm.event.types.instant )
				elseif hitShape.destructable and sm.item.getDurabilityRating( hitShape:getShapeUuid() ) == 1 then
					if hitShape.isBlock then
						local blockPosition = hitShape:getClosestBlockLocalPosition( point )
						hitShape:destroyBlock( blockPosition, nil, 1, sm.shape.destructionType.projectile )
					else
						hitShape:destroyShape( 1, sm.shape.destructionType.projectile, hitShape.worldPosition )
					end
				end
			elseif result.type == "character" then
				local unit = result:getCharacter():getUnit()
				if sm.exists( unit ) then
					local damage = 10 * timeStep * self.sv.drillLevel.drillSpeed
					sm.event.sendToUnit( unit, "sv_e_receiveDamage", { damage = damage, impact = direction * 5, hitPos = result.pointWorld, source = "plasma" } )
				end
			end
		end

		self.sv.voxelDrillTickCounter = self.sv.voxelDrillTickCounter + 1
		self:sv_drillVoxels( drillSettings, range, direction, point )
	else
		self.sv.voxelDrillTickCounter = 0
		if self.sv.areaTrigger then
			self.sv.areaTrigger:destroy()
			self.sv.areaTrigger = nil
		end
	end

	local eject = self.sv.saved.ejectQueue and self.sv.saved.ejectQueue[1]
	while eject and sm.game.getCurrentTick() >= eject.ejectTime do
		self:sv_ejectCasingShape( eject.casingMaterialAmounts )
		table.remove( self.sv.saved.ejectQueue, 1 )
		self.storage:save( self.sv.saved )
		eject = self.sv.saved.ejectQueue and self.sv.saved.ejectQueue[1]
	end

	if self.sv.clientDataDirty then
		local index = math.floor( self:sv_getTotalCasingAmount() / GRAVEL_CASING_CAPACITY * DrillUvFrameCount )
		self.network:setClientData( { self.sv.saved.settingsLevel, self.sv.hasCharge, self:sv_isEmpty(), index } )
		self.sv.clientDataDirty = false
	end
end

function PlasmaDrill.sv_drillVoxels( self, drillSettings, range, direction, point )
	local world = self.shape.body:getWorld()
	local fraction = self.sv.drillTicks >= DrillWindupTicks and 1 or 0.5
	local materialMask = 0
	if self.sv.voxelDrillTickCounter % self.sv.drillLevel.voxelDrillIntervalTicks == 0 then
		materialMask = bit.bor( materialMask, sm.world.voxelFilter.all )
	end





	local maxLength2 = range - 2 * drillSettings.radius + 0.5
	local from2 = self.shape.worldPosition + direction * ( drillSettings.radius - 0.5 )
	local direction2 = direction * clamp( direction:dot( point - from2 ) - drillSettings.radius + 1, 0, maxLength2 ) -- 1 extra to ensure we go a bit past the hit point
	local to2 = from2 + direction2
	--sm.debugDraw.addArrow( "drillDirection2"..self.shape.id, from2, to2, sm.color.new( "00ff00" ) )
	--sm.debugDraw.addSphere( "drillFrom2"..self.shape.id, from2, drillSettings.radius, sm.color.new( "ff0000" ) )
	--sm.debugDraw.addSphere( "drillTo2"..self.shape.id, to2, drillSettings.radius, sm.color.new( "ff0000" ) )

	if materialMask ~= 0 then
		local drillRequest = MiningManager.Sv_GetDrillParams( world, DrillLevels[tostring( self.shape:getShapeUuid() )].level, fraction )
		drillRequest.voxelMaterialMask = bit.band( drillRequest.voxelMaterialMask, materialMask )
		if drillRequest.voxelMaterialMask ~= 0 then
			world:voxelDensitySubtraction( from2, direction2, drillSettings.radius + 0.5, drillRequest.maxDensities, drillRequest.voxelMaterialMask, true, "sv_drillResult" )
		end
	end
end

function PlasmaDrill.sv_addMaterials( self, items )
	local totalAmount = 0
	for _, amount in pairs( self.sv.saved.casingMaterialAmounts ) do
		totalAmount = totalAmount + amount
	end
	local wasEmpty = totalAmount == 0
	local totalAdded = 0
	for i = 1, #items do
		local material = tostring( items[i].uuid )
		local amount = items[i].quantity
		totalAdded = totalAdded + amount
		while amount > 0 do
			self.sv.saved.casingMaterialAmounts[material] = self.sv.saved.casingMaterialAmounts[material] or 0
			if totalAmount + amount >= GRAVEL_CASING_CAPACITY then
				print( "Casing full, ejecting" )
				local addedAmount = GRAVEL_CASING_CAPACITY - totalAmount
				self.sv.saved.casingMaterialAmounts[material] = self.sv.saved.casingMaterialAmounts[material] + addedAmount
				totalAmount = GRAVEL_CASING_CAPACITY
				self:sv_ejectCasing()
				totalAmount = 0
				amount = amount - addedAmount
			else
				self.sv.saved.casingMaterialAmounts[material] = ( self.sv.saved.casingMaterialAmounts[material] or 0 ) + amount
				totalAmount = totalAmount + amount
				amount = 0
			end
		end
	end
	--print( "Casing: "..totalAmount.."/"..GRAVEL_CASING_CAPACITY.." (+"..totalAdded..")" )
	if totalAdded > 0 or self:sv_isEmpty() ~= wasEmpty then
		self.sv.clientDataDirty = true
	end
end

function PlasmaDrill.cl_n_ejectAnim( self )
	self.cl.ejectAnimTime = 0
	sm.effect.playHostedEffect( "Plasmadrill - Eject", self.shape )
end

function PlasmaDrill.sv_drillResult( self, destruction )
	local world = self.shape.body:getWorld()
	--local sumRemDensities = 0
	local items = {}
	for i = 1, #destruction.densities do
		if destruction.densities[i] > 0 then
			local itemUuid = MiningManager.Sv_GetVoxelMaterialItemUuid( world, i )
			if itemUuid then
				if itemUuid == ITEMS.obj_voxelmaterial_t4 then
					items[#items + 1] = { uuid = itemUuid, quantity = math.ceil( destruction.densities[i] * 0.5 ) }
				else
					items[#items + 1] = { uuid = itemUuid, quantity = destruction.densities[i] }
				end
			end
			--print( "Removed material", i..": "..destruction.densities[i] )
			--sumRemDensities = sumRemDensities + destruction.densities[i]
			--sm.debugDraw.addSphere( "voxeldestruction"..self.shape.id, destruction.avgPositions[i], 0.1, sm.color.new( "ffff00" ) )
		end
	end
	self:sv_addMaterials( items )
	--print( "Removed densities sum: "..sumRemDensities )
end

function PlasmaDrill.sv_e_receiveItem( self, params )
	sm.container.beginTransaction()
	sm.container.spendFromSlot( params.containerA, 0, params.itemA, params.quantityA, true )
	if sm.container.endTransaction() then
		local items = {}
		local carryData = params.player:getCarryData()
		for material, amount in pairs( carryData ) do
			print( "Casing material: "..sm.shape.getShapeTitle( sm.uuid.new( material ) ).." amount: "..amount )
			items[#items + 1] = { uuid = sm.uuid.new( material ), quantity = amount }
		end
		self:sv_addMaterials( items )
		--params.player:setCarryData( nil )
	else
		sm.log.error( "Transaction failed" )
	end
end

function PlasmaDrill.sv_ejectCasing( self )










	self.sv.saved.ejectQueue = self.sv.saved.ejectQueue or {}
	table.insert( self.sv.saved.ejectQueue, { ejectTime = sm.game.getCurrentTick() + EjectShapeDelay, casingMaterialAmounts = self.sv.saved.casingMaterialAmounts } )
	self.sv.saved.casingMaterialAmounts = {}
	self.storage:save( self.sv.saved )
	self.network:sendToClients( "cl_n_ejectAnim" )
end

local VoxelMaterials = { ITEMS.obj_voxelmaterial_rich, ITEMS.obj_voxelmaterial_t1, ITEMS.obj_voxelmaterial_t3, ITEMS.obj_voxelmaterial_t4 }

local function CasingTypeFromDominantMaterial( casingMaterialAmounts )
	local dominantMaterial = nil
	local dominantAmount = 0
	for i = 1, #VoxelMaterials do
		local material = VoxelMaterials[i]
		local amount = casingMaterialAmounts[tostring( material )] or 0
		if amount > dominantAmount then
			dominantAmount = amount
			dominantMaterial = material
		end
	end
	if dominantMaterial == ITEMS.obj_voxelmaterial_t1 then
		return ITEMS.obj_resource_drillcasingmixedt1
	elseif dominantMaterial == ITEMS.obj_voxelmaterial_t3 then
		return ITEMS.obj_resource_drillcasingmixedt3
	elseif dominantMaterial == ITEMS.obj_voxelmaterial_t4 then
		return ITEMS.obj_resource_drillcasingmixedt4
	end
	return ITEMS.obj_resource_drillcasingmixedrich
end

function PlasmaDrill.sv_ejectCasingShape( self, casingMaterialAmounts )
	local ejectRot = self.shape.worldRotation-- * sm.quat.angleAxis( math.rad( 90 ), sm.vec3.new( 1, 0, 0 ) )
	local ejectPos = self.shape.worldPosition + self.shape.worldRotation * ( sm.vec3.new( 0, 0, 0.75 ) ) + ejectRot * sm.vec3.new( -0.375, -0.5, -0.375 )
	local ejectShape
	if casingMaterialAmounts[tostring( ITEMS.obj_voxelmaterial_rich )] == GRAVEL_CASING_CAPACITY then
		ejectShape = sm.shape.createPart( ITEMS.obj_resource_drillcasingrich, ejectPos, ejectRot )
	elseif casingMaterialAmounts[tostring( ITEMS.obj_voxelmaterial_t1 )] == GRAVEL_CASING_CAPACITY then
		ejectShape = sm.shape.createPart( ITEMS.obj_resource_drillcasingt1, ejectPos, ejectRot )
	elseif casingMaterialAmounts[tostring( ITEMS.obj_voxelmaterial_t3 )] == GRAVEL_CASING_CAPACITY then
		ejectShape = sm.shape.createPart( ITEMS.obj_resource_drillcasingt3, ejectPos, ejectRot )
	elseif casingMaterialAmounts[tostring( ITEMS.obj_voxelmaterial_t4 )] == GRAVEL_CASING_CAPACITY then
		ejectShape = sm.shape.createPart( ITEMS.obj_resource_drillcasingt4, ejectPos, ejectRot )
	else
		local casingType = CasingTypeFromDominantMaterial( casingMaterialAmounts )
		ejectShape = sm.shape.createPart( casingType, ejectPos, ejectRot )
		ejectShape.interactable:setParams( casingMaterialAmounts )
	end
	sm.physics.applyImpulse( ejectShape.body, self.shape.worldRotation * sm.noise.gunSpread( sm.vec3.new( 0, 0, 7 ), 15 ) * ejectShape.mass, true )
	sm.physics.applyTorque( ejectShape.body, sm.vec3.new( math.random() - 0.5, math.random() - 0.5, math.random() - 0.5 ) * ejectShape.mass, true )
	--sm.debugDraw.addTransform( "drill", self.shape.worldPosition, self.shape.worldRotation, 1.0 )
	--sm.debugDraw.addTransform( "ejectShape", ejectShape.worldPosition, ejectShape.worldRotation, 1.0 )
end

function PlasmaDrill.sv_n_takeCasing( self, _, player )
	if not self:sv_isEmpty() then
		local carryContainer = player:getCarry()
		sm.container.beginTransaction()
		local casingType = CasingTypeFromDominantMaterial( self.sv.saved.casingMaterialAmounts )
		sm.container.collect( carryContainer, casingType, 1 )
		if sm.container.endTransaction() then
			player:setCarryData( self.sv.saved.casingMaterialAmounts )
			self.sv.saved.casingMaterialAmounts = {}
			self.sv.clientDataDirty = true
		end
	end
end

function PlasmaDrill.server_onMelee( self, position, attacker, damage, power, hitDirection )







































end

function PlasmaDrill.sv_n_tryUpgrade( self, _, player )
	if self.sv.drillLevel and self.sv.drillLevel.upgrade then
		local function fnUpgrade()
			local nextLevel = DrillLevels[self.sv.drillLevel.upgrade]
			assert( nextLevel )
			self.network:sendToClients( "cl_n_onUpgrade", self.sv.drillLevel.upgrade )

			self.shape:replaceShape( sm.uuid.new( self.sv.drillLevel.upgrade ) )
			self.sv.drillLevel = nextLevel
		end
		if sm.game.getEnableUpgrade() then
			local inventory = player:getInventory()
			if sm.container.totalQuantity( inventory, ITEMS.obj_consumable_multicomponent ) >= self.sv.drillLevel.cost then
				if sm.container.beginTransaction() then
					sm.container.spend( inventory, ITEMS.obj_consumable_multicomponent, self.sv.drillLevel.cost, true )

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

function PlasmaDrill.sv_n_setLevel( self, level )
	self.sv.saved.settingsLevel = level
	self.storage:save( self.sv.saved )
	self.sv.clientDataDirty = true
end

-- Client

function PlasmaDrill.client_onCreate( self )
	self.cl = {}
	self.cl.currentSettingsLevel = 1
	self.cl.hasCharge = false
	self.cl.drillLevel = DrillLevels[tostring( self.shape:getShapeUuid() )]
	self.cl.impactEffects = {}
	self.cl.secondaryImpactEffects = {}
	self.cl.vortexEffects = {}
end

function PlasmaDrill.client_onRefresh( self )
	print( "PlasmaDrill.client_onRefresh" )
	self.cl.effectBeamStart = nil
	self.cl.effectBeam = nil
	self.cl.effectBeamDiameter = nil
	self.cl.prevHithit = nil
	self.cl.effectBeamEnd = nil
	self.cl.effectProjection = nil
end


function PlasmaDrill.client_onFixedUpdate( self, dt )
	local logic, _ = self:getParents()
	local onLift = self.shape:getBody():isOnLift()
	local drilling = not onLift and logic and logic:isActive() and self.cl.hasCharge

	if drilling then
		local worldPos = self.shape.worldPosition
		local drillSettings = DrillSettings[self.cl.currentSettingsLevel]
		local radius = drillSettings.radius
		local range = self.cl.drillLevel.range
		local worldDir = self.shape.at
		sm.debris.createBlackHole( worldPos, radius, 60, worldPos + worldDir * range, -10, 2 )
	end
end

function PlasmaDrill.client_onUpdate( self, dt )
	--sm.debugDraw.addArrow( "drillCast"..self.shape.id, self.shape.worldPosition, self.shape.worldPosition + self.shape.worldRotation * sm.vec3.new( 0, HitScanDistance, 0 ), sm.color.new( "00ff00" ) )
	--sm.debugDraw.addArrow( "drillCasing"..self.shape.id, self.shape.worldPosition, self.shape.worldPosition + self.shape.worldRotation * sm.vec3.new( 0, 0, 0.375 ), sm.color.new( "00ff00" ) )

	local logic, _ = self:getParents()
	local onLift = self.shape:getBody():isOnLift()
	local drilling = not onLift and logic and logic:isActive() and self.cl.hasCharge
	local hithit = false

	if drilling then
		local drillSettings = DrillSettings[self.cl.currentSettingsLevel]
		local groundFilter = sm.physics.filter.static + sm.physics.filter.dynamicBody + sm.physics.filter.character
		local from = self.shape.worldPosition
		local direction = self.shape.at
		local range = self.cl.drillLevel.range
		local to = from + direction * ( range - HitScanRadius )
		local hit, result = sm.physics.spherecast( from, to, HitScanRadius, self.shape.body, groundFilter, nil, GetDrillIgnoreList() )
		local fraction = result.fraction or 1.0
		local point = sm.vec3.lerp( from, to, fraction ) + direction * HitScanRadius
		local length = ( point - from ):length()

		local world = self.shape.body:getWorld()

		hithit = hit and ( fraction * range < range - HitScanRadius - 0.5 )
		if hithit then
			local impactEffect = nil
			local secondaryImpactEffect = nil
			if result.type == "voxelTerrain" then
				local samplePos = result.pointWorld - result.normalWorld * 0.041666667
				local material = world:getVoxelMaterialFromWorldPosition( samplePos ) + 1
				if world.clientPublicData.type == "UndergroundWorld" then
					TutorialManager.Cl_TutorialEvent( TutorialEvent.PlasmaDrill )
					if MiningManager.Cl_GetVoxelMaterialItemUuid( world, material ) ~= nil then
						TutorialManager.Cl_TutorialEvent( TutorialEvent.PlasmaDrillAdvanced )
					end
				end
				local impactEffectName, secondaryImpactEffectName = MiningManager.Cl_GetVoxelDrillImpactEffect( world, material )
				if impactEffectName then
					self.cl.impactEffects[impactEffectName] = self.cl.impactEffects[impactEffectName] or sm.effect.createEffect( impactEffectName )
					impactEffect = self.cl.impactEffects[impactEffectName]
				end
				if secondaryImpactEffectName then
					self.cl.secondaryImpactEffects[secondaryImpactEffectName] = self.cl.secondaryImpactEffects[secondaryImpactEffectName] or sm.effect.createEffect( secondaryImpactEffectName )
					secondaryImpactEffect = self.cl.secondaryImpactEffects[secondaryImpactEffectName]
				end

				self.cl.impactVortexCooldown = ( self.cl.impactVortexCooldown or ImpactVortexCooldownTime ) - dt
				if self.cl.impactVortexCooldown <= 0.0 then
					local vortexEffectName = MiningManager.Cl_GetVoxelDrillVortexEffect( world, material )
					if vortexEffectName then
						self.cl.vortexEffects[vortexEffectName] = self.cl.vortexEffects[vortexEffectName] or sm.effect.createEffect( vortexEffectName )
						self.cl.vortexEffects[vortexEffectName]:start()
					end
					self.cl.impactVortexCooldown = ( self.cl.impactVortexCooldown % ImpactVortexCooldownTime ) + ImpactVortexCooldownTime
				end
				for _, effect in pairs( self.cl.vortexEffects ) do
					if effect and effect:isPlaying() then
						effect:setPosition( from + direction * math.max( length - ImpactVortexOffset, 0 ) )
						effect:setRotation( self.shape.worldRotation )
					end
				end
			else
				local defaultEffectName = "Plasmadrill - ImpactDefault"
				self.cl.impactEffects[defaultEffectName] = self.cl.impactEffects[defaultEffectName] or sm.effect.createEffect( defaultEffectName )
				impactEffect = self.cl.impactEffects[defaultEffectName]
			end

			if self.cl.currentImpactEffect and self.cl.currentImpactEffect ~= impactEffect then
				self.cl.currentImpactEffect:stopImmediate()
			end
			if impactEffect then
				impactEffect:setPosition( point )
				impactEffect:setRotation( self.shape.worldRotation )
				if not impactEffect:isPlaying() then
					impactEffect:start()
				end
			end
			self.cl.currentImpactEffect = impactEffect

			if self.cl.currentSecondaryImpactEffect and self.cl.currentSecondaryImpactEffect ~= secondaryImpactEffect then
				self.cl.currentSecondaryImpactEffect:stopImmediate()
			end
			if secondaryImpactEffect then
				secondaryImpactEffect:setPosition( point )
				secondaryImpactEffect:setRotation( self.shape.worldRotation )
				if not secondaryImpactEffect:isPlaying() then
					secondaryImpactEffect:start()
				end
			end
			self.cl.currentSecondaryImpactEffect = secondaryImpactEffect
			self.cl.contactValue = 1
		else
			if self.cl.currentImpactEffect then
				self.cl.currentImpactEffect:stopImmediate()
				self.cl.currentImpactEffect = nil
			end
			if self.cl.currentSecondaryImpactEffect then
				self.cl.currentSecondaryImpactEffect:stopImmediate()
				self.cl.currentSecondaryImpactEffect = nil
			end
			self.cl.contactValue = 0
		end

		self.cl.ceilingEffectCooldown = ( self.cl.ceilingEffectCooldown or CeilingEffectCooldownTime ) - dt
		if self.cl.ceilingEffectCooldown <= 0.0 then
			local upFrom = sm.vec3.lerp( from, point, math.random() )
			local upTo = upFrom + sm.vec3.new( 0, 0, drillSettings.radius * ( hithit and 2 or 1 ) - HitScanRadius - 0.65 ):rotate( ( math.random() - 0.5 ) * 0.5 * math.pi, direction )
			local upHit, upResult = sm.physics.spherecast( upFrom, upTo, HitScanRadius, self.shape.body, groundFilter, nil, GetDrillIgnoreList() )
			sm.debugDraw.flashArrow( upFrom, upTo, sm.color.new( "0000ff" ) )
			if upHit then
				sm.debugDraw.flashSphere( upResult.pointWorld, 0.1, sm.color.new( "0000ff" ) )
				if upResult.type == "voxelTerrain" then
					local samplePos = upResult.pointWorld - upResult.normalWorld * 0.041666667
					local material = world:getVoxelMaterialFromWorldPosition( samplePos ) + 1
					local drillCeilingEffectName = MiningManager.Cl_GetVoxelDrillCeilingEffect( world, material )
					if drillCeilingEffectName then
						local rot = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), upResult.normalWorld )
						sm.effect.playEffect( drillCeilingEffectName, upResult.pointWorld, nil, rot )
					end
				end
			end
			self.cl.ceilingEffectCooldown = math.max( CeilingEffectCooldownTime / length, CeilingEffectCooldownTime / 10 )
		end










		sm.debugDraw.addArrow( "drillRayResult"..self.shape.id, from, point, sm.color.new( "00ff00" ) )
		sm.debugDraw.addSphere( "drillHitSphere"..self.shape.id, sm.vec3.lerp( from, to, result.fraction ), HitScanRadius, sm.color.new( "ff0000" ) )

		if self.cl.effectBeamStart == nil then
			self.cl.effectBeamStart = sm.effect.createEffect( "Plasmadrill - BeamStart", self.interactable )
		end
		if self.cl.effectBeam == nil then
			self.cl.effectBeam = sm.effect.createEffect( "Plasmadrill - Beam_renderable01", self.interactable )
			self.cl.effectBeam:setOffsetPosition( sm.vec3.new( 0, 0.5, 0 ) )
		end
		if self.cl.effectBeamDiameter == nil then
			self.cl.effectBeamDiameter = sm.effect.createEffect( "Plasmadrill - BeamDiameter", self.interactable )
		end
		if self.cl.effectBeamEnd == nil then
			self.cl.effectBeamEnd = sm.effect.createEffect( "Plasmadrill - BeamEnd", self.interactable )
		end
		if self.cl.effectBeamShutOff == nil then
			self.cl.effectBeamShutOff = sm.effect.createEffect( "Plasmadrill - Shutoff", self.interactable )
		end

		if not self.cl.effectBeamStart:isPlaying() then
			self.cl.effectBeamStart:start()
		end
		if not self.cl.effectBeam:isPlaying() then
			self.cl.effectBeam:start()
		end
		if not self.cl.effectBeamDiameter:isPlaying() then
			self.cl.effectBeamDiameter:start()
		end
		if hithit then
			if self.cl.effectBeamEnd:isPlaying() then
				self.cl.effectBeamEnd:stopImmediate()
			end
			self.cl.effectBeam:setParameter( "pose0", 1 )
			self.cl.effectBeam:setParameter( "pose1", 0 )
		else
			if not self.cl.effectBeamEnd:isPlaying() then
				self.cl.effectBeamEnd:start()
			end
			self.cl.effectBeam:setParameter( "pose0", 0 )
			self.cl.effectBeam:setParameter( "pose1", 1 )
		end

		if self.cl.effectBeamDiameter and self.cl.prevHithit ~= hithit then
			local beamParticleScale = hithit and 5.0 or 1.0
			self.cl.effectBeamDiameter:setParameter( "Scale", sm.vec3.new( beamParticleScale, beamParticleScale, beamParticleScale ) )
			self.cl.effectBeamDiameter:stopImmediate()
			self.cl.effectBeamDiameter:start()
		end
		self.cl.prevHithit = hithit

		self.cl.effectBeam:setScale( sm.vec3.new( 1, math.max( length - 1, 0 ) / 9.5, 1 ) )
		self.cl.effectBeamDiameter:setOffsetPosition( sm.vec3.new( 0, length - 0.5, 0 ) )

		self.cl.previousLengthWeight = self.cl.previousLengthWeight or 0
		local lengthWeight = clamp( length / range, 0.0, 1.0 )
		self.cl.effectBeamStart:setParameter( "on_contact", self.cl.contactValue or 0 )
		self.cl.effectBeamStart:setParameter( "beam_distance", lengthWeight )
		lengthWeight = magicInterpolation( self.cl.previousLengthWeight, lengthWeight, dt )
		self.cl.previousLengthWeight = lengthWeight

		self.cl.previousWidthWeight = self.cl.previousWidthWeight or 0
		local widthWeight = clamp( ( self.cl.currentSettingsLevel - 1 ) / ( #DrillSettings - 1 ), 0.0, 1.0 )
		widthWeight = magicInterpolation( self.cl.previousWidthWeight, widthWeight, dt )
		self.cl.previousWidthWeight = widthWeight
		--local default = lengthWeight * ( 1 - widthWeight )

		--local pose0 = lengthWeight * widthWeight
		--local pose1 = ( 1 - lengthWeight ) * ( 1 - widthWeight )
		--local pose2 = ( 1 - lengthWeight ) * widthWeight
		--assert( math.abs( pose0 + pose1 + pose2 + default - 1 ) < 0.0001 )
		-- self.cl.effectBeamDiameter:setParameter( "pose0", pose0 )
		-- self.cl.effectBeamDiameter:setParameter( "pose1", pose1 )
		-- self.cl.effectBeamDiameter:setParameter( "pose2", pose2 )

		self.cl.effectBeamEnd:setOffsetPosition( sm.vec3.new( 0, length - 0.5, 0 ) )
	else
		if self.cl.wasDrilling and self.cl.effectBeamShutOff then
			self.cl.effectBeamShutOff:start()
		end
		if self.cl.effectBeamStart and self.cl.effectBeamStart:isPlaying() then
			self.cl.effectBeamStart:stop()
		end
		if self.cl.effectBeam and self.cl.effectBeam:isPlaying() then
			self.cl.effectBeam:stop()
		end
		if self.cl.effectBeamDiameter and self.cl.effectBeamDiameter:isPlaying() then
			self.cl.effectBeamDiameter:stopImmediate()
		end
		if self.cl.effectBeamEnd and self.cl.effectBeamEnd:isPlaying() then
			self.cl.effectBeamEnd:stopImmediate()
		end
		if self.cl.currentImpactEffect then
			self.cl.currentImpactEffect:stopImmediate()
			self.cl.currentImpactEffect = nil
		end
		if self.cl.currentSecondaryImpactEffect then
			self.cl.currentSecondaryImpactEffect:stopImmediate()
			self.cl.currentSecondaryImpactEffect = nil
		end
		self.cl.previousLengthWeight = 0
		self.cl.previousWidthWeight = 0
	end
	self.cl.wasDrilling = drilling

	if self.cl.ejectAnimTime and self.cl.ejectAnimTime >= 0 then
		self.cl.ejectAnimTime = self.cl.ejectAnimTime + dt
		local progress = math.min( self.cl.ejectAnimTime / EjectAnimDuration, 1.0 )
		local poseWeight
		if progress < 0.5 then
			poseWeight = sm.util.easing( "easeOutExpo", progress * 2 )
		else
			poseWeight = sm.util.easing( "easeInExpo", ( 1.0 - progress ) * 2 )
		end
		self.interactable:setPoseWeight( 0, poseWeight )
		if progress >= 1.0 then
			self.cl.ejectAnimTime = -1
		end
		self.cl.oscillationTime = 0
	elseif hithit or ( self.cl.oscillationTime or 0 ) > 0 then
		self.cl.oscillationTime = ( self.cl.oscillationTime or 0 ) + dt
		local oscilationSpeed = 5.57
		if not hithit then
			if math.floor( self.cl.oscillationTime * oscilationSpeed ) > math.floor( ( self.cl.oscillationTime - dt ) * oscilationSpeed ) then
				self.cl.oscillationTime = 0
			end
		end
		local poseWeight = ( -math.cos( self.cl.oscillationTime * oscilationSpeed * 2 * math.pi ) + 1 ) * 0.5 * 0.1
		self.interactable:setPoseWeight( 0, poseWeight )
	end
end

function PlasmaDrill.client_onClientDataUpdate( self, data, channel )
	self.cl.currentSettingsLevel = data[1]
	self.cl.hasCharge = data[2]
	self.cl.isEmpty = data[3]
	self.interactable:setUvFrameIndex( data[4] or 0 )
end

function PlasmaDrill.client_onDestroy( self, dt )
	--sm.debugDraw.removeArrow( "drillCast"..self.shape.id )
	--sm.debugDraw.removeArrow( "drillCasing"..self.shape.id )
	--sm.debugDraw.removeSphere( "drillHitSphere"..self.shape.id )
	--sm.debugDraw.removeArrow( "drillHitNormal"..self.shape.id )
	self:cl_onGuiClosed()
end

function PlasmaDrill.server_canErase( self )
	return self:sv_isEmpty()
end

function PlasmaDrill.client_canErase( self )
	if not self.cl.isEmpty then
		NotificationManager.Cl_AddGenericNotification( "Please empty the drill first by pressing "..sm.gui.getKeyBinding( "Tinker" ), 4 )
		return false
	end
	return true
end

function PlasmaDrill.client_canInteract( self )
	return true
end

function PlasmaDrill.client_canTinker( self, character )
	local carryContainer = sm.localPlayer.getPlayer():getCarry()
	if not self.cl.isEmpty then
		if carryContainer:isEmpty() then
			sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Tinker", true ), "#{UNLOAD}" )
			return true
		end
	end
	return false
end

function PlasmaDrill.client_onInteract( self, character, state )
	if state == true then
		self.gui = sm.gui.createEngineGui()

		self.gui:setText( "Name", "#{CONTROLLER_PLASMADRILL_TITLE}" )
		self.gui:setText( "Interaction", "#{CONTROLLER_PLASMADRILL_INSTRUCTION}" )
		self.gui:setOnCloseCallback( "cl_onGuiClosed" )
		self.gui:setSliderCallback( "Setting", "cl_onSliderChange" )
		self.gui:setSliderData( "Setting", #DrillSettings, self.cl.currentSettingsLevel - 1 )
		self.gui:setIconImage( "Icon", self.shape:getShapeUuid() )
		self.gui:setButtonCallback( "Upgrade", "cl_onUpgradeClicked" )
		self.gui:setImage( "UpgradeCostIcon", "gui_icon_multicomponents.png" )
		
		local drillLevel = DrillLevels[tostring( self.shape:getShapeUuid() )]
		if drillLevel then
			self.gui:setSliderRangeLimit( "Setting", drillLevel.maxSetting )
			self.gui:setData( "SliderCaptions", { min = "#{SLIDER_MIN}", max = "#{SLIDER_MAX}" } )
			if drillLevel.upgrade then
				local inventory = sm.localPlayer.getPlayer():getInventory()
				local availableKits = sm.container.totalQuantity( inventory, ITEMS.obj_consumable_multicomponent )
				local upgradeData = { cost = drillLevel.cost, available = availableKits }
				self.gui:setIconImage( "UpgradeIcon", self.shape:getShapeUuid() )
				self.gui:setData( "UpgradeInfo", { Speed = "+50%", Range = "+50%", Settings = 3 } )
				self.gui:setData( "Upgrade", upgradeData )
			end
			self.gui:setText( "SubTitle", drillLevel.title )
		end

		local batteryContainer = self.shape.interactable:getContainer( 0 )

		if batteryContainer then
			self.gui:setContainer( "Fuel", batteryContainer )
		end

		self.gui:open()
	end
end

function PlasmaDrill.client_onTinker( self, character, state )
	if state == true then
		if not self.cl.isEmpty then
			self.network:sendToServer( "sv_n_takeCasing" )
			self.cl.isEmpty = true
		end
	end
end

function PlasmaDrill.cl_onGuiClosed( self )
	if self.gui then
		self.gui:destroy()
		self.gui = nil
	end
end

function PlasmaDrill.cl_onSliderChange( self, sliderName, sliderPos )
	self.cl.currentSettingsLevel = sliderPos + 1
	self.network:sendToServer( "sv_n_setLevel", self.cl.currentSettingsLevel )
end

function PlasmaDrill.cl_onUpgradeClicked( self, buttonName )
	self.network:sendToServer("sv_n_tryUpgrade", sm.localPlayer.getPlayer() )
end

function PlasmaDrill.cl_n_onUpgrade( self, upgrade )
	local nextLevel = DrillLevels[upgrade]

	if self.gui and self.gui:isActive() then
		self.gui:setIconImage( "Icon", sm.uuid.new( upgrade ) )

		if sm.game.getEnableUpgrade() and nextLevel.upgrade then
			local inventory = sm.localPlayer.getPlayer():getInventory()
			local availableKits = sm.container.totalQuantity( inventory, ITEMS.obj_consumable_multicomponent )
			local upgradeData = { cost = nextLevel.cost, available = availableKits }
			self.gui:setData( "Upgrade", upgradeData )
		else
			self.gui:setVisible( "Upgrade", false )
		end

		self.gui:setText( "SubTitle", nextLevel.title )
		self.gui:setSliderRangeLimit( "Setting", nextLevel.maxSetting )
		
		if nextLevel.upgrade then
			self.gui:setData( "UpgradeInfo", { Speed = "+50%", Range = "+50%", Settings = 3 } )
			self.gui:setIconImage( "UpgradeIcon", sm.uuid.new( self.cl.drillLevel.upgrade ) )
		else
			self.gui:setVisible( "UpgradeIcon", false )
			self.gui:setData( "UpgradeInfo", nil )
		end
	end

	--change visual effects here if needed later
	sm.effect.playHostedEffect( "Part - Upgrade", self.interactable )
	self.cl.drillLevel = nextLevel
end

function PlasmaDrill.client_getAvailableParentConnectionCount( self, connectionType )
	if bit.band( connectionType, sm.interactable.connectionType.logic ) ~= 0 then
		return 1 - #self.interactable:getParents( bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.power ) )
	end
	if bit.band( connectionType, sm.interactable.connectionType.electricity ) ~= 0 then
		return 1 - #self.interactable:getParents( sm.interactable.connectionType.electricity )
	end
	return 0
end
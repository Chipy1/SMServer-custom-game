dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_collections.lua"

Prospector = class( nil )
Prospector.maxParentCount = 1
Prospector.maxChildCount = 0
Prospector.connectionInput = sm.interactable.connectionType.water
Prospector.connectionOutput = sm.interactable.connectionType.none
Prospector.colorNormal = sm.color.new( 0x00acfcff )
Prospector.colorHighlight = sm.color.new( 0x00acfcff )
Prospector.connectIcon = "water"
Prospector.connectIconScale = 0.75

Prospector.ContainerSize = 6

local AcceptedItems = {
	ITEMS.obj_resource_residueore,
}

local ProspectorRecipes = {
	[tostring( ITEMS.obj_resource_residueore )] = {
		craftTime = 25,
		ingredientList = {
			{ quantity = 1, itemId = ITEMS.obj_resource_residueore }
		},
		randomCraftList = {
			{ quantity = 5, 	itemUuid = ITEMS.blk_metal1, 				weight = 1 },
			{ quantity = 5, 	itemUuid = ITEMS.blk_sand, 					weight = 1 },
			{ quantity = 5, 	itemUuid = ITEMS.blk_scrapstone,			weight = 1 },
			{ quantity = 5, 	itemUuid = ITEMS.obj_resource_mud, 			weight = 1 },
			{ quantity = 1, 	itemUuid = ITEMS.obj_nugget_t1, 			weight = 0.5 },
			{ quantity = 1, 	itemUuid = ITEMS.obj_nugget_t2, 			weight = 0.5 },
			{ quantity = 1, 	itemUuid = ITEMS.obj_nugget_t3, 			weight = 0.5 },
			{ quantity = 1, 	itemUuid = ITEMS.obj_resource_quartz, 		weight = 0.5 },
			{ quantity = 1, 	itemUuid = ITEMS.obj_consumable_chemical, 	weight = 0.5 },
			{ quantity = 1, 	itemUuid = ITEMS.obj_resource_crudeoil, 	weight = 0.5 },

			{ quantity = 5, 	itemUuid = ITEMS.blk_metal1, 				weight = 1 },
			{ quantity = 5, 	itemUuid = ITEMS.blk_sand, 					weight = 1 },
			{ quantity = 5, 	itemUuid = ITEMS.blk_scrapstone,			weight = 1 },
			{ quantity = 5, 	itemUuid = ITEMS.obj_resource_mud, 			weight = 1 },
			{ quantity = 2, 	itemUuid = ITEMS.obj_nugget_t1, 			weight = 0.5 },
			{ quantity = 2, 	itemUuid = ITEMS.obj_nugget_t2, 			weight = 0.5 },
			{ quantity = 2, 	itemUuid = ITEMS.obj_nugget_t3, 			weight = 0.5 },
			{ quantity = 2, 	itemUuid = ITEMS.obj_resource_quartz, 		weight = 0.5 },
			{ quantity = 3, 	itemUuid = ITEMS.obj_consumable_chemical, 	weight = 0.5 },
			{ quantity = 3, 	itemUuid = ITEMS.obj_resource_crudeoil, 	weight = 0.5 },

			{ quantity = 10, 	itemUuid = ITEMS.blk_metal1, 				weight = 1 },
			{ quantity = 10, 	itemUuid = ITEMS.blk_sand, 					weight = 1 },
			{ quantity = 10, 	itemUuid = ITEMS.blk_scrapstone,			weight = 1 },
			{ quantity = 10, 	itemUuid = ITEMS.obj_resource_mud, 			weight = 1 },
			{ quantity = 3, 	itemUuid = ITEMS.obj_nugget_t1, 			weight = 0.5 },
			{ quantity = 3, 	itemUuid = ITEMS.obj_nugget_t2, 			weight = 0.5 },
			{ quantity = 3, 	itemUuid = ITEMS.obj_nugget_t3, 			weight = 0.5 },
			{ quantity = 3, 	itemUuid = ITEMS.obj_resource_quartz, 		weight = 0.5 },
			{ quantity = 4, 	itemUuid = ITEMS.obj_consumable_chemical, 	weight = 0.5 },
			{ quantity = 4, 	itemUuid = ITEMS.obj_resource_crudeoil, 	weight = 0.5 },

			{ quantity = 10, 	itemUuid = ITEMS.blk_metal1, 				weight = 1 },
			{ quantity = 10, 	itemUuid = ITEMS.blk_sand, 					weight = 1 },
			{ quantity = 10, 	itemUuid = ITEMS.blk_scrapstone,			weight = 1 },
			{ quantity = 10, 	itemUuid = ITEMS.obj_resource_mud, 			weight = 1 },
			{ quantity = 4, 	itemUuid = ITEMS.obj_nugget_t1, 			weight = 0.5 },
			{ quantity = 4, 	itemUuid = ITEMS.obj_nugget_t2, 			weight = 0.5 },
			{ quantity = 4, 	itemUuid = ITEMS.obj_nugget_t3, 			weight = 0.5 },
			{ quantity = 4, 	itemUuid = ITEMS.obj_resource_quartz, 		weight = 0.5 },
			{ quantity = 5, 	itemUuid = ITEMS.obj_consumable_chemical, 	weight = 0.5 },
			{ quantity = 5, 	itemUuid = ITEMS.obj_resource_crudeoil, 	weight = 0.5 },

			{ quantity = 10, 	itemUuid = ITEMS.blk_metal1, 				weight = 1 },
			{ quantity = 10, 	itemUuid = ITEMS.blk_sand, 					weight = 1 },
			{ quantity = 10, 	itemUuid = ITEMS.blk_scrapstone,			weight = 1 },
			{ quantity = 10, 	itemUuid = ITEMS.obj_resource_mud, 			weight = 1 },
			{ quantity = 5, 	itemUuid = ITEMS.obj_nugget_t1, 			weight = 0.5 },
			{ quantity = 5, 	itemUuid = ITEMS.obj_nugget_t2, 			weight = 0.5 },
			{ quantity = 5, 	itemUuid = ITEMS.obj_nugget_t3, 			weight = 0.5 },
			{ quantity = 4, 	itemUuid = ITEMS.obj_resource_quartz, 		weight = 0.5 },
			{ quantity = 5, 	itemUuid = ITEMS.obj_consumable_chemical, 	weight = 0.5 },
			{ quantity = 5, 	itemUuid = ITEMS.obj_resource_crudeoil, 	weight = 0.5 },
			--TODO: Add more stuff when player has access to Drill2
		}
	}
}

local EffectList = {
	[tostring( ITEMS.obj_resource_residueore )] = "OreProspector - Residueore1",
}

local DestructionEffectList = {
	[tostring( ITEMS.obj_resource_residueore )] = "Oreprospector - Washingfinnished",
}

local EffectOffset = sm.vec3.new( 0.0, 0.3, 0.0 )
local CollectionTickDelay = 0.4 * 40
local CraftTimeMinSeconds = 40
local CraftTimeMaxSeconds = 60
local CraftTimeAverage = ( CraftTimeMinSeconds + CraftTimeMaxSeconds ) / 2
local CraftTimeMinTicks = math.floor( CraftTimeMinSeconds * 40 )
local CraftTimeMaxTicks = math.floor( CraftTimeMaxSeconds * 40 )
local SecondsPerWater = 2
local TicksPerWater = math.floor( SecondsPerWater * 40 ) + CollectionTickDelay

function Prospector.server_onCreate( self )
	self.sv = {}
	if not self.interactable:getContainer( 0 ) then
		self.interactable:addContainer( 0, self.ContainerSize, 1 )
	end
	if not self.interactable:getContainer( 1 ) then
		local waterContainer = self.interactable:addContainer( 1, 5, 20 ) -- water container
		local carryData = self.interactable:getCarryData()
		if waterContainer and carryData then
			sm.container.beginTransaction()
			sm.container.collect( waterContainer, ITEMS.obj_consumable_water, carryData.quantity, false )
			sm.container.endTransaction()
		end
	end
	local container = self.interactable:getContainer( 1 )
	if container then
		container:setFilters( { ITEMS.obj_consumable_water } )
	end
	self.shape.interactable:setCarryData( { quantity = sm.container.totalQuantity( container, ITEMS.obj_consumable_water )  } )

	self.sv.resourceContainer = self.interactable:getContainer( 0 )
	self.sv.internalWaterContainer = self.interactable:getContainer( 1 )
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.isActivated = false
		self.sv.saved.waterTicks = 0
		
		self.sv.saved.productionSlotsData = {}
		local slotUuids = sm.container.itemUuid( self.sv.resourceContainer )
    	for index, slotUuid in ipairs( slotUuids ) do
			if not slotUuid:isNil() then
				assert( isAnyOf( slotUuid, AcceptedItems ), "Prospector invariant: unexpected uuid in resource container" )
				local t = math.floor( math.random( CraftTimeMinTicks, CraftTimeMaxTicks ) )
				self.sv.saved.productionSlotsData[index] = {
					resourceUuid = slotUuid,
					ticksLeft = t,
					originalTicks = t
				}
			end
		end
		
		self.network:setClientData( nil, 2 )
	end

	self.sv.connectedWaterInteractable = nil
	self.sv.slotOffsets = {}
	for i = 1, self.ContainerSize do
		self.sv.slotOffsets[i] = self.interactable:getLocalBonePosition( "bucket"..i.."_jnt" )
	end
	local waterTicksRemaining = sm.pipeGraph.getInteractableConditionTicks( self.shape )
	if waterTicksRemaining then
		self.sv.saved.waterTicks = waterTicksRemaining
		if self.sv.saved.waterTicks > 0 then
			self.sv.saved.isActivated = true
		else
			self.sv.saved.isActivated = false
		end
	end
	self.sv.lastCollectionTick = 0
	self.sv.shape = self.shape
	self:sv_saveAndSync()
	self:sv_setAutomatedTasks()
end

function Prospector.sv_setAutomatedTasks( self )
	sm.pipeGraph.removeAutomatedTasks( self.shape )
	local containers = {}
	if self.sv.connectedWaterInteractable then
		containers = sm.pipeGraph.getMatchingPipedContainers( self.sv.connectedWaterInteractable )
	end
	containers[#containers + 1] = self.sv.internalWaterContainer
	for i = 1, self.sv.resourceContainer.size do
		for _, recipe in pairs( ProspectorRecipes ) do
			local recipeCopy = DeepCopy( recipe )
			recipeCopy.externalContainers = containers
			sm.pipeGraph.setAutomatedTask( self.shape, recipeCopy, true )
		end
	end
	sm.pipeGraph.setParallelLimit( self.shape, self.sv.resourceContainer.size )
end

function Prospector.server_canErase( self )
	return not self.sv.saved.isActivated
end

function Prospector.server_onUnload( self )
	self.storage:save( self.sv.saved )
	self.sv.unloaded = true
	sm.pipeGraph.setInteractableCondition( self.sv.shape, { uuid = ITEMS.obj_consumable_water, tickFrequency = TicksPerWater, remainingTicks = self.sv.saved.waterTicks, consumptionCount = 1, onlyExternal = true } )
end

function Prospector.server_onDestroy( self )
	if not self.sv.unloaded then
		for index,productionData in pairs( self.sv.saved.productionSlotsData ) do
			if productionData.uuid then
				local projectileParams = { lootUid = productionData.uuid, lootQuantity = productionData.quantity, epic = false }
				local projectileDirection = self.sv.rotation * sm.vec3.new( 0,1,0 )
				local projectilePosition = self.sv.position + projectileDirection + ( self.sv.rotation * self.sv.slotOffsets[index] )
				sm.projectile.customProjectileAttack( projectileParams, projectile_loot, 0, projectilePosition, projectileDirection * 4, self.sv.world )
				self.sv.loaded = false
			end
		end
	end
end

function Prospector.sv_saveAndSync( self )
	self.storage:save( self.sv.saved )
	self.sv.markedDirty = false
	self.network:setClientData( self.sv.saved, 1 )
end

function Prospector.server_onFixedUpdate( self )
	self.sv.rotation = self.shape.worldRotation
	self.sv.position = self.shape.worldPosition
	self.sv.world = self.shape.body:getWorld()

	local waterInteractable = self:sv_getInput()
	if self.sv.connectedWaterInteractable ~= waterInteractable then
		self.sv.connectedWaterInteractable = waterInteractable
		self:sv_setAutomatedTasks()
	end

	if ( sm.game.getCurrentTick() - self.sv.lastCollectionTick ) >= CollectionTickDelay then
		local inputContainers = sm.pipeGraph.getInputContainers( self.shape )
		if not IsEmptyTable( inputContainers ) then
			local done = false
			for _,container in ipairs( inputContainers ) do
				for _,itemUid in ipairs( AcceptedItems ) do
					if self:sv_tryTransacation( GetPipeGraphObjectContainer( container ), itemUid ) then
						self.network:sendToClients( "cl_n_collectFromChest", { item = itemUid, targetContainer = container } )
						self.sv.lastCollectionTick = sm.game.getCurrentTick()
						done = true
						break
					end
				end
				if done then
					break
				end
			end
		end
	end

	if not self.sv.saved.isActivated then
		if not self.sv.resourceContainer:isEmpty() then
			if self.sv.saved.waterTicks > 0 or self:sv_tryConsumeWater() then
				self.sv.saved.isActivated = true
				for _,productionData in pairs( self.sv.saved.productionSlotsData ) do
					if not productionData.done and productionData.ticksLeft == nil then
						local randomProductionTicks = math.floor( math.random( CraftTimeMinTicks, CraftTimeMaxTicks ) )
						productionData.ticksLeft = randomProductionTicks
						productionData.originalTicks = randomProductionTicks
						self.sv.markedDirty = true
					end
				end
				self:sv_saveAndSync()
			end
		end
	end

	if self.sv.saved.waterTicks > 0 and not self.sv.resourceContainer:isEmpty() then
		self.sv.saved.waterTicks = self.sv.saved.waterTicks - 1

		if self.sv.saved.waterTicks <= 0 then
			self.sv.saved.isActivated = false
			self.sv.markedDirty = true
		end
	end
	for index,productionData in pairs( self.sv.saved.productionSlotsData ) do

		if self.sv.saved.isActivated then
			 if productionData.ticksLeft then
				productionData.ticksLeft = productionData.ticksLeft - 1
				if productionData.ticksLeft == 0 then
					self:sv_finishSlotProduction( index )
				end
			end
		end

		if productionData.doneTick and ( sm.game.getCurrentTick() - productionData.doneTick ) >= CollectionTickDelay then
			local outputContainers = sm.pipeGraph.getOutputContainers( self.shape )
			if not IsEmptyTable( outputContainers ) then
				for _,container in ipairs( outputContainers ) do
					local inventory = container:getInteractable():getContainer()
					if inventory then
						sm.container.beginTransaction()
						inventory:collect( productionData.uuid, productionData.quantity, true )
						if sm.container.endTransaction() then
							self.sv.saved.productionSlotsData[index] = nil
							self.sv.markedDirty = true
							local pos = self.sv.position + ( self.sv.rotation * self.sv.slotOffsets[index] )
							self.network:sendToClients( "cl_n_depositToChest", { index = index, position = pos, targetContainer = container, item = productionData.uuid } )
							break
						end
					end
				end
			end
		end
	end

	if self.sv.resourceContainer:isEmpty() and self.sv.saved.isActivated then
		self.sv.saved.isActivated = false
		self.sv.markedDirty = true
	end

	if self.sv.internalWaterContainer and self.sv.internalWaterContainer:hasChanged( sm.game.getServerTick() - 1 ) then
		self.shape.interactable:setCarryData( { quantity = sm.container.totalQuantity( self.sv.internalWaterContainer, ITEMS.obj_consumable_water ) } )
	end

	if self.sv.markedDirty then
		self:sv_saveAndSync()
	end
end

function Prospector.sv_waterNotification( self, player )
	if self.sv.saved.waterTicks == 0
	 and not CanSpendFromConnectedContainer( self.sv.connectedWaterInteractable, ITEMS.obj_consumable_water, 1 )
	 and not sm.container.canSpend( self.sv.internalWaterContainer, ITEMS.obj_consumable_water, 1 ) then
		NotificationManager.Sv_Generic( "#{REQUIRES_WATER}", 1.5, nil, player )
	end
end

function Prospector.sv_e_collectResource( self, params )
	local inventory = params.player:getInventory()
	self:sv_tryTransacation( inventory, params.itemId )
	self:sv_waterNotification( params.player )
end

function Prospector.sv_tryTransacation( self, container, itemId )
	if isAnyOf( itemId, AcceptedItems ) then
		sm.container.beginTransaction()
		sm.container.spend( container, itemId, 1, true )
		local collectedItem = false
		local foundIndex = -1
		local foundUid = sm.uuid.getNil()
		for index,uid in ipairs( sm.container.itemUuid( self.sv.resourceContainer ) ) do
			if uid == sm.uuid.getNil() and self.sv.saved.productionSlotsData[index] == nil then
				foundUid = uid
				self.sv.resourceContainer:setItem( index - 1, itemId, 1 )
				collectedItem = true
				foundIndex = index
				break
			end
		end
		if not collectedItem then
			sm.container.abortTransaction()
			return false
		elseif sm.container.endTransaction() then
			self.sv.markedDirty = true
			local randomProductionTicks = math.floor( math.random( CraftTimeMinTicks, CraftTimeMaxTicks ) )
			self.sv.saved.productionSlotsData[foundIndex] = { ticksLeft = randomProductionTicks, originalTicks = randomProductionTicks, resourceUuid = foundUid }
			return true
		end
	end
	return false
end

function Prospector.sv_getInput( self )
	local waterInteractable = nil
	local parents = self.interactable:getParents()
	if parents[1] then
		if parents[1]:hasOutputType( sm.interactable.connectionType.water ) then
			waterInteractable = parents[1]
		end
	end

	return waterInteractable
end

function Prospector.sv_tryConsumeWater( self )
	sm.container.beginTransaction()
	local spendAmount = 1
	spendAmount = TrySpendFromConnectedContainer( self.sv.connectedWaterInteractable, ITEMS.obj_consumable_water, spendAmount )
	if spendAmount > 0 and self.sv.internalWaterContainer then
		spendAmount = spendAmount - sm.container.spend( self.sv.internalWaterContainer, ITEMS.obj_consumable_water, spendAmount )
	end
	if spendAmount ~= 0 then
		sm.container.abortTransaction()
		return false
	else
		if sm.container.endTransaction() then
			self.sv.saved.waterTicks = TicksPerWater
			return true
		end
	end
	return false
end

function Prospector.sv_finishSlotProduction( self, index )
	sm.container.beginTransaction()
	local itemData = self.sv.resourceContainer:getItem( index - 1 )
	if not itemData.uuid:isNil() then
		local totalWeight = 0
		for _,recipeData in ipairs( ProspectorRecipes[tostring( itemData.uuid )].randomCraftList ) do
			totalWeight = totalWeight + recipeData.weight
		end
		local randomValue = math.random() * totalWeight
		local lootData = nil
		for _,recipeData in ipairs( ProspectorRecipes[tostring( itemData.uuid )].randomCraftList ) do
			if randomValue <= recipeData.weight then
				lootData = recipeData
				break
			end
			randomValue = randomValue - recipeData.weight
		end
		if lootData then
			sm.container.spendFromSlot( self.sv.resourceContainer, index - 1, itemData.uuid, 1, true )
			self.sv.saved.productionSlotsData[index] = {
				resourceUuid = itemData.uuid,
				uuid = lootData.itemUuid,
				quantity = lootData.quantity,
				doneTick = sm.game.getCurrentTick(),
				done = true,
			}
		else
			sm.log.error( "Prospector: No loot data found for uuid: " .. tostring( itemData.uuid ) )
		end
	end
	if sm.container.endTransaction() then
		self.sv.markedDirty = true
	end
end

function Prospector.sv_n_collect( self, data, player )
	if self.sv.saved.productionSlotsData[data.index] then
		local collectionData = self.sv.saved.productionSlotsData[data.index]
		if player and sm.exists( player ) then
			local inventory = player:getInventory()
			if sm.container.beginTransaction() then
				inventory:collect( collectionData.uuid, collectionData.quantity, true )
				if sm.container.endTransaction() then
					self.sv.saved.productionSlotsData[data.index] = nil
					self.sv.markedDirty = true
					local rot = self.shape.worldRotation * sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, -1 ) )
					sm.event.sendToPlayer( player, "sv_e_onLoot", { uuid = collectionData.uuid, pos = data.position, rot = rot } )
				else
					self.network:sendToClient( player, "cl_n_fullInventoryAlert" )
				end
			end
		end
	end
end

-- Client

function Prospector.client_onCreate( self )
	self.cl = {}
	self.cl.isActivated = false
	self.cl.effectList = {}
	self.cl.productionSlotsData = {}
	self.cl.pipeEffectPlayer = PipeEffectPlayer()
	self.cl.pipeEffectPlayer:onCreate()

	self.cl.container = self.interactable:getContainer( 0 )
	self.cl.containerRevision = 0

	self.cl.attachedTriggers = {}
	self.cl.triggersData = {}

	self.cl.animations = {}
	self.cl.unpackAnim = self:cl_createAnimation( "unpack" )
	self.cl.animations["start"] = self:cl_createAnimation( "start" )
	self.cl.animations["finish"] = self:cl_createAnimation( "finish" )
	self.cl.animations["use01"] = self:cl_createAnimation( "use01" )
	self.cl.animations["use02"] = self:cl_createAnimation( "use02" )
	self.cl.animations["use03_l"] = self:cl_createAnimation( "use03_l" )
	self.cl.animations["use03_r"] = self:cl_createAnimation( "use03_r" )
	self.cl.animations["use04"] = self:cl_createAnimation( "use04" )

	self.cl.useAnimationChances = {
		["use01"] = 0.40,
		["use02"] = 0.14,
		["use03_l"] = 0.22,
		["use03_r"] = 0.22,
		["use04"] = 0.02
	}

	self.cl.sortedChances = {}
	self.cl.totalChance = 0
	for name, chance in pairs( self.cl.useAnimationChances ) do
		table.insert( self.cl.sortedChances, { name = name, chance = chance } )
		self.cl.totalChance = self.cl.totalChance + chance
	end
	table.sort( self.cl.sortedChances, function( a, b ) return a.chance > b.chance end )

	for index,uuid in ipairs( sm.container.itemUuid( self.cl.container ) ) do
		if not uuid:isNil() then
			self:cl_loadProspector( index, uuid )
		end
	end
end

function Prospector.client_onRefresh( self )
	self.cl.sortedChances = {}
	self.cl.totalChance = 0
	for name, chance in pairs( self.cl.useAnimationChances ) do
		table.insert( self.cl.sortedChances, { name = name, chance = chance } )
		self.cl.totalChance = self.cl.totalChance + chance
	end
	table.sort( self.cl.sortedChances, function( a, b ) return a.chance > b.chance end )
end

function Prospector.client_onUpdate( self, dt )
	self.cl.pipeEffectPlayer:update( dt )
	if self.cl.isActivated then
		for index,productionData in pairs( self.cl.productionSlotsData ) do
			if productionData.timeLeft then
				productionData.timeLeft = productionData.timeLeft - dt
				if productionData.timeLeft >= 0 and self.cl.effectList[index] and sm.exists( self.cl.effectList[index] ) then
					self.cl.effectList[index]:setParameter( "pose0" , math.min( 1 - (  productionData.timeLeft / ( productionData.originalTime or CraftTimeAverage ) ), 1.0 ) )
				end
			end
		end
	end

	self:cl_updateAnimations( dt )
end

function Prospector.client_canErase( self )
	if self.cl.isActivated then
		NotificationManager.Cl_AddGenericNotification( "#{INFO_BUSY}", BUSY_NOTIFICATION_DURATION )
		return false
	end
	return true
end

function Prospector.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		if data == nil then
			return
		end
		self.cl.isActivated = data.isActivated
		if self.cl.isActivated then
			self:cl_startProspecting()
		end
		for containerIndex,uuid in ipairs( sm.container.itemUuid( self.cl.container ) ) do
			if not uuid:isNil() then
				if self.cl.effectList[containerIndex] == nil then
					self:cl_createEffectAtIndex( containerIndex, uuid )
				end
			end
		end
		self.cl.productionSlotsData = data.productionSlotsData
		for _,productionData in pairs( self.cl.productionSlotsData ) do
			if productionData.ticksLeft then
				productionData.timeLeft = productionData.ticksLeft * 0.025
				productionData.originalTime = productionData.originalTicks * 0.025
			end
		end
		if data.productionSlotsData then
			for index,triggerData in pairs( self.cl.attachedTriggers ) do -- clean up collected triggers
				if not data.productionSlotsData[index] or not data.productionSlotsData[index].done then
					if sm.exists( triggerData.trigger ) then
						local id = triggerData.trigger:getId()
						self.cl.triggersData[id] = nil
						triggerData.trigger:destroy()
					end
					if sm.exists( triggerData.effect ) then
						triggerData.effect:destroy()
					end
					self.cl.attachedTriggers[index] = nil
				end
			end
			for index,productionData in pairs( data.productionSlotsData ) do
				if self.cl.attachedTriggers[index] == nil and data.productionSlotsData[index].done then

					self.cl.attachedTriggers[index] = {}
					self.cl.attachedTriggers[index].trigger = sm.areaTrigger.createAttachedSphere( self.interactable, 0.3, sm.vec3.new( 0.0, 0.6, 0.0 ), nil, nil, nil, sm.areaTrigger.areaTriggerProxyType.interactable, "bucket"..index.."_jnt" )
					self.cl.attachedTriggers[index].trigger:bindCanInteract( "cl_trigger_canInteract" )
					self.cl.attachedTriggers[index].trigger:bindCanErase( "cl_trigger_canErase" )
					self.cl.attachedTriggers[index].trigger:bindOnInteract( "cl_trigger_onInteract" )
					self.cl.attachedTriggers[index].trigger:bindOnErase( "cl_trigger_onErase" )
					self.cl.attachedTriggers[index].trigger:setDestroyOnErase( false )
					self.cl.attachedTriggers[index].trigger:setEraseTime( 0.0 )

					self.cl.attachedTriggers[index].effect = sm.effect.createEffect( "Loot - GlowItem", self.interactable, "bucket"..index.."_jnt" )
					self.cl.attachedTriggers[index].effect:setParameter( "uuid", productionData.uuid )
					self.cl.attachedTriggers[index].effect:setParameter( "Color", sm.shape.getShapeTypeColor( productionData.uuid ) )
					self.cl.attachedTriggers[index].effect:setScale( sm.vec3.new( 0.25, 0.25, 0.25 ) )
					self.cl.attachedTriggers[index].effect:setOffsetPosition( sm.vec3.new( 0, 0.6, 0.0 ) )

					local randomRotation = sm.quat.angleAxis( math.random() * math.pi * 2, sm.vec3.new( 0, 1, 0 ) )
					self.cl.attachedTriggers[index].effect:setOffsetRotation( randomRotation * sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, -1 ) ) )
					self.cl.attachedTriggers[index].effect:start()
					self.cl.triggersData[self.cl.attachedTriggers[index].trigger:getId()] = { productionData = productionData, index = index }
					self:cl_finishProduction( index )
				end
				if self.cl.effectList[index] and sm.exists( self.cl.effectList[index] ) then
					self.cl.effectList[index]:setParameter( "pose0" , math.min( 1 - (  productionData.timeLeft or 0 ) / ( productionData.originalTime or CraftTimeAverage ), 1.0 ) )
				end
			end
		end

	elseif channel == 2 then
		self:cl_setAnimation( self.cl.unpackAnim, 0.0 )
	end
end

function Prospector.cl_createEffectAtIndex( self, index, uuid )
	self.cl.effectList[index] = sm.effect.createEffect( EffectList[tostring( uuid )], self.interactable, "bucket"..index.."_jnt" )
	self.cl.effectList[index]:setScale( sm.vec3.new( 0.25, 0.25, 0.25 ) )
	self.cl.effectList[index]:setOffsetPosition( EffectOffset )
	self.cl.effectList[index]:start()
end

function Prospector.cl_loadProspector( self, index, uuid )
	self:cl_createEffectAtIndex( index, uuid )
end

function Prospector.cl_startProspecting( self )
	local hasActiveAnimation = false
	for _, animation in pairs( self.cl.animations ) do
		if animation.isActive then
			if animation.name == "finish" then
				self:cl_setAnimation( self.cl.animations["start"], 0.0 )
				return
			end
			hasActiveAnimation = true
			break
		end
	end
	if not hasActiveAnimation then
		self:cl_setAnimation( self.cl.animations["start"], 0.0 )
	end
end

function Prospector.cl_finishProduction( self, index )
	if self.cl.effectList[index] then
		if sm.exists( self.cl.effectList[index] ) then
			self.cl.effectList[index]:destroy()
			self.cl.effectList[index] = nil
		end
		local uid = self.cl.productionSlotsData[index].resourceUuid
		self.cl.productionSlotsData[index].timeLeft = nil
		if uid then
			sm.effect.playHostedEffect( DestructionEffectList[tostring( uid )], self.interactable, "bucket"..index.."_jnt" )
		end
	end
end

function Prospector.client_onInteract( self, _, state )
	if state then
		self.gui = sm.gui.createProspectorContainerGui( true )

		self.gui:setContainer( "UpperGrid", self.interactable:getContainer( 1 ) )
		self.gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
		self.gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
		self.gui:setOnCloseCallback( "cl_e_onClose" )
		self.gui:open()
	end
end

function Prospector.cl_e_onClose( self )
	self.gui = nil
end

function Prospector.client_canInteract( self )
	local language = sm.gui.getCurrentLanguage()
	local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
	local title = sm.shape.getShapeTitle( self.shape.uuid )
	if language == "German" or language == "Japanese" or language == "Korean" then
		sm.gui.setInteractionText( "", keyBindingText, "".."#FFFFC0"..title.." #FFFFFF".."#{INTERACTION_USE}" )
	else
		sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_USE} ".."#FFFFC0"..title )
	end

	local playerActiveItem = nil
	if isAnyOf( sm.localPlayer.getActiveItem(), AcceptedItems ) then
		playerActiveItem = sm.localPlayer.getActiveItem()
	end

	if playerActiveItem then
		for i = 1, 6 do
			local slot = self.cl.productionSlotsData[i]
			if not slot then
				local keyBindingText =  sm.gui.getKeyBinding( "Create", true )
				local activeItemTitle = "#FFFFC0"..sm.shape.getShapeTitle( playerActiveItem )
				sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_INSERT} "..activeItemTitle )
				break
			end
		end
	end

	return true
end

function Prospector.cl_createAnimation( self, name )
	local animation =
	{
		name = name,
		playProgress = 0.0,
		playTime = self.interactable:getAnimDuration( name )
	}
	return animation
end

function Prospector.cl_setAnimation( self, animation, playProgress )
	self:cl_unsetAnimations()
	animation.isActive = true
	animation.playProgress = playProgress
	self.interactable:setAnimEnabled( animation.name, true )
end

function Prospector.cl_unsetAnimations( self )
	for name, animation in pairs( self.cl.animations ) do
		animation.isActive = false
		animation.playProgress = 0.0
		self.interactable:setAnimEnabled( animation.name, false )
		self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end

function Prospector.cl_updateAnimations( self, dt )
	for _, animation in pairs( self.cl.animations ) do
		self:cl_updateAnimation( animation, dt )
	end
	self:cl_updateAnimation( self.cl.unpackAnim, dt )
end

function Prospector.cl_updateAnimation( self, animation, dt )
	if animation.isActive then
		self.interactable:setAnimEnabled( animation.name, true )
		animation.playProgress = animation.playProgress + dt / animation.playTime
		self.interactable:setAnimProgress( animation.name, animation.playProgress )
			
		if animation.playProgress > 1.0 then
			self.interactable:setAnimEnabled( animation.name, false )
			animation.playProgress = 0.0
			animation.isActive = false
			local deactivated = not self.cl.isActivated or self.cl.container:isEmpty()
			local animationAllowed = animation.name ~= "unpack" and animation.name ~= "finish"
			if deactivated and animationAllowed then
				self:cl_setAnimation( self.cl.animations["finish"], 0.0 )
			elseif animation.name == "start" or self.cl.useAnimationChances[animation.name] ~= nil then
				self:cl_activateRandomUseAnimation()
			end
		end
	end
end

function Prospector.cl_activateRandomUseAnimation( self )
	local randomValue = math.random() * self.cl.totalChance
	for _, data in ipairs( self.cl.sortedChances ) do
		if randomValue <= data.chance then
			self:cl_setAnimation( self.cl.animations[data.name], 0.0 )
			self.interactable:setAnimProgress( data.name, self.cl.animations[data.name].playProgress )
			return
		else
			randomValue = randomValue - data.chance
		end
	end
end

function Prospector.cl_n_collectFromChest( self, data )
	local shapeList = {}
	local containerPath = sm.pipeGraph.getContainerPath( self.shape, data.targetContainer, sm.pipeGraph.direction.incoming )
	for _, shape in reverse_ipairs( containerPath ) do
		table.insert( shapeList, shape )
	end
	table.insert( shapeList, self.shape )
	self.cl.pipeEffectPlayer:pushShapeEffectTask( shapeList, data.item )
end

function Prospector.cl_n_depositToChest( self, data )
	local containerPath = sm.pipeGraph.getContainerPath( self.shape, data.targetContainer, sm.pipeGraph.direction.outgoing )
	table.insert( containerPath, 1, self.shape )
	self.cl.pipeEffectPlayer:pushShapeEffectTask( containerPath, data.item )
end

function Prospector.cl_trigger_canInteract( self, trigger )
	local keyBindingText = GetInteractionKeybinding()
	local data = self.cl.triggersData[trigger:getId()]
	if data then
		sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PICK_UP} #FFFFC0" .. sm.shape.getShapeTitle( data.productionData.uuid ) .. "#FFFFFF"..( data.productionData.quantity > 1 and (" x " .. data.productionData.quantity) or "" ) )
		return true
	end
	return false
end

function Prospector.cl_trigger_canErase( self )
	return true
end

function Prospector.cl_trigger_onInteract( self, trigger, _, state )
	if state then
		self.network:sendToServer( "sv_n_collect", { index = self.cl.triggersData[trigger:getId()].index, position = trigger:getWorldPosition() } )
	end
end

function Prospector.cl_trigger_onErase( self, id, pos )
	if self.cl.triggersData[id] == nil then
		return
	end
	self.network:sendToServer( "sv_n_collect", { index = self.cl.triggersData[id].index, position = pos } )
end

function Prospector.cl_n_fullInventoryAlert( self )
	NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 3.0 )
end
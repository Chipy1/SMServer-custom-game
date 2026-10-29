dofile( "$SURVIVAL_DATA/Scripts/game/survival_collections.lua" )

ResourceContainer = class( nil )
ResourceContainer.ContainerSize = 25
ResourceContainer.AcceptedItems = g_resourceCollectorHarvests

local UuidStringToMaterialId = {
	[tostring( ITEMS.obj_harvest_stone )] = 6,
	[tostring( ITEMS.obj_harvest_wood )] = 7,
	[tostring( ITEMS.obj_harvest_wood2 )] = 7,
	[tostring( ITEMS.obj_harvest_metal )] = 9,
	[tostring( ITEMS.obj_harvest_metal2 )] = 9,
	[tostring( ITEMS.obj_harvest_crystal )] = 10,
}
local CollectSoundVelocity = 10.0
local CollectionRange = 3.0

function ResourceContainer.server_onCreate( self )
	if not self.interactable:getContainer( 0 ) then
		self.interactable:addContainer( 0, self.ContainerSize, 1 )
	end
	self.sv = self.sv or {}
	self.sv.collectionRange = self.sv.collectionRange or CollectionRange
	self.sv.lastRearranged = sm.game.getCurrentTick()
	local shapeSize = sm.item.getShapeSize( self.shape:getShapeUuid() ) * 0.125
	local size = sm.vec3.new( shapeSize.x + self.sv.collectionRange, shapeSize.y + self.sv.collectionRange, shapeSize.z + self.sv.collectionRange )
	local filter = sm.areaTrigger.filter.staticBody + sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.areaTrigger
	
	self.sv.areaTrigger = sm.areaTrigger.createAttachedBox( self.interactable, size, sm.vec3.zero(), sm.quat.identity(), filter, { resourceCollector = self.shape, isGravelCollector = self.shape:getShapeUuid() == ITEMS.obj_interactive_gravelcollector } )
	self.sv.areaTrigger:setIncludeShapesInContent( true )
	self.sv.areaTrigger:bindOnStay( "trigger_onEnter" )

	self.interactable.publicData = { itemContents = {}}
end

local f_removedHarvests = { lastTick = 0, shapes = {} }
local clearFrequency = 5

function ResourceContainer.server_onFixedUpdate( self )
	local container = self.interactable:getContainer( 0 )
	if container then
		if container:hasChanged( self.sv.lastRearranged ) then
			local startChecking = false
			local changedSlot = nil
			for i = self.ContainerSize, 1, -1 do
				local slotItem = container:getItem( i - 1 )
				if slotItem.quantity == 0 and startChecking then
					changedSlot = i - 1
					break
				end
				if slotItem.quantity > 0 then
					startChecking = true
				end
			end
			if changedSlot then
				self:sv_rearrangeContents( changedSlot )
			end
			self.sv.lastRearranged = sm.game.getCurrentTick()
		end
	end
    local currentTick = sm.game.getCurrentTick()
    if currentTick - f_removedHarvests.lastTick > clearFrequency then
        f_removedHarvests = { lastTick = currentTick, shapes = {} }
    end
end

function ResourceContainer.canCollect( self, shape )
    local shapePos = shape:getWorldPosition()
    local triggerMin = self.sv.areaTrigger:getWorldMin()
    local triggerMax = self.sv.areaTrigger:getWorldMax()
    if shapePos.x < triggerMin.x or shapePos.y < triggerMin.y or shapePos.z < triggerMin.z or
       shapePos.x > triggerMax.x or shapePos.y > triggerMax.y or shapePos.z > triggerMax.z then
        return false
    end

	local interactable = shape.interactable
	if interactable and interactable.publicData and interactable.publicData.canCollectStatic == false then
		return shape.body:isDynamic()
	end
	return true
end

function ResourceContainer.processShapes( self, shapes )
	for _, shape in ipairs( shapes ) do
		if shape:getBody():getCreationId() ~= self.shape:getBody():getCreationId() then
			if isAnyOf( shape:getShapeUuid(), self.AcceptedItems ) then
				if self:canCollect( shape ) then
					if not f_removedHarvests.shapes[shape:getId()] then
						local container = self.interactable:getContainer( 0 )
						if container then
							local transactionSlot = nil
							for i = 1, self.ContainerSize do
								local slotItem = container:getItem( i - 1 )
								if slotItem.quantity == 0 then
									transactionSlot = i - 1
									break
								end
							end
							if transactionSlot then
								sm.container.beginTransaction()
								sm.container.collectToSlot( container, transactionSlot, shape:getShapeUuid(), 1, true )
								
								-- Check for itemContents in the shape
								local itemContents = nil
								if self.sv.saved and self.sv.saved.itemContents then
									-- Get shape interactable container if it exists
									local shapeInteractable = shape:getInteractable()
									if shapeInteractable and shapeInteractable.publicData then
										itemContents = shapeInteractable.publicData
									end
								end

								if sm.container.endTransaction() then
									local luaIndex = transactionSlot + 1 -- Adjust for 0-based index in container
									if itemContents then
										self.sv.saved.itemContents[luaIndex] = itemContents
										self.interactable.publicData.itemContents[luaIndex] = itemContents
										self.interactable:setCarryData( self.sv.saved )
										self.storage:save( self.sv.saved )
									end
									local params = {
										shapeUuid = shape:getShapeUuid(),
										fromPosition = shape.worldPosition,
										fromRotation = shape.worldRotation,
										velocity = shape.body.velocity,
										angularVelocity = shape.body.angularVelocity,
										slotIndex = transactionSlot,
										showRenderable = true
									}
									self.network:sendToClients( "cl_n_addPickupItem", params )
									f_removedHarvests.shapes[shape:getId()] = true
									f_removedHarvests.lastTick = sm.game.getCurrentTick()
									shape:destroyShape()
								end
							end
						end
					end
				end
			end
		end
	end
end

function ResourceContainer.trigger_onEnter( self, trigger, contents )
	local shapes = {}
	for _, result in ipairs( contents ) do
		if sm.exists( result ) and type( result ) == "Shape" then
			shapes[#shapes+1] = result
		end
	end
	if #shapes > 0 then
		self:processShapes( shapes )
	end
end

function ResourceContainer.sv_e_receiveItem( self, params )
	if isAnyOf( params.itemA, self.AcceptedItems ) then
		local container = self.interactable:getContainer( 0 )
		if container then
			local transactionSlot = nil
			for i = 1, self.ContainerSize do
				local slotItem = container:getItem( i - 1 )
				if slotItem.quantity == 0 then
					transactionSlot = i - 1
					break
				end
			end
			if transactionSlot then
				sm.container.beginTransaction()
				sm.container.spendFromSlot( params.containerA, 0, params.itemA, params.quantityA, true )
				sm.container.collectToSlot( container, transactionSlot, params.itemA, params.quantityA, true )
				local itemContents = nil
				if self.sv.saved and self.sv.saved.itemContents then
					itemContents = params.player:getCarryData()
				end
				if sm.container.endTransaction() then
					if itemContents then
						local luaIndex = transactionSlot + 1 -- Adjust for 0-based index in container
						self.sv.saved.itemContents[luaIndex] = itemContents
						self.interactable.publicData.itemContents[luaIndex] = itemContents
						self.interactable:setCarryData( self.sv.saved )
						self.storage:save( self.sv.saved )
					end
					self.network:sendToClients( "cl_n_addPickupItem", { showRenderable = false } )
				else
					sm.log.error( "Transaction failed" )
				end
			end
		end
	end
end

function ResourceContainer.sv_n_takeHarvest( self, params, player )
	local container = self.interactable:getContainer( 0 )
	if container then
		local slotItem = container:getItem( params.slotIndex )
		print( "Carry container size", player:getCarry():getSize() )
		sm.container.beginTransaction()
		sm.container.spendFromSlot( container, params.slotIndex, slotItem.uuid, 1, true )
		sm.container.collect( player:getCarry(), slotItem.uuid, 1, true )
		if sm.container.endTransaction() then
			if self.sv.saved and self.sv.saved.itemContents then
				local luaIndex = params.slotIndex + 1
				player:setCarryData( self.sv.saved.itemContents[luaIndex] )
				player:setCarryColor( sm.item.getShapeDefaultColor( slotItem.uuid ) )
				self.sv.saved.itemContents[luaIndex] = nil
				self.interactable.publicData.itemContents[luaIndex] = nil
				self.interactable:setCarryData( self.sv.saved )
				self.storage:save( self.sv.saved )
			end
			if self.shape:getShapeUuid() ~= ITEMS.obj_interactive_gravelcollector then
				self:sv_rearrangeContents( params.slotIndex )
			end
		else
			sm.log.error( "Transaction failed" )
		end
	end
end

function ResourceContainer.sv_rearrangeContents( self, removedSlotIndex )
	local container = self.interactable:getContainer( 0 )
	if container then
		local previousSlotIndex = removedSlotIndex
		for i = removedSlotIndex + 1, self.ContainerSize - 1 do
			local nextSlotItem = container:getItem( i )
			sm.container.beginTransaction()
			sm.container.spendFromSlot( container, i, nextSlotItem.uuid, 1, true )
			sm.container.collectToSlot( container, previousSlotIndex, nextSlotItem.uuid, 1, true )
			if sm.container.endTransaction() then
				if self.sv.saved and self.sv.saved.itemContents then
					self.sv.saved.itemContents[previousSlotIndex+1] = self.sv.saved.itemContents[i+1]
					self.interactable.publicData.itemContents[previousSlotIndex+1] = self.sv.saved.itemContents[i+1]
					self.cl.updateEffects = true
					self.sv.saved.itemContents[i+1] = nil
					self.interactable.publicData.itemContents[i+1] = nil
					self.interactable:setCarryData( self.sv.saved )
					self.storage:save( self.sv.saved )
				end
			else
				sm.log.error( "Transaction failed" )
			end
			previousSlotIndex = i
		end
		self.network:sendToClients( "cl_n_updateRearrange" )
		self.sv.lastRearranged = sm.game.getCurrentTick()
	end
end

function ResourceContainer.cl_n_updateRearrange( self, params )
	local container = self.interactable:getContainer( 0 )
	if container then
		self:cl_updateEffects( container )
	end

	-- Removed resource effect
	sm.effect.playEffect( "Resourcecollector - PutIn", self.shape.worldPosition )
end

function ResourceContainer.client_onCreate( self )
	self.cl = {}
	self.cl.pickupItems = {}
	self.cl.harvestItems = {}
	self.cl.updateEffects = true
	for i = 1, self.ContainerSize do
		local harvestItem = {}
		harvestItem.effect = sm.effect.createEffect( "ShapeRenderable", self.interactable )
		local positionOffset, rotationOffset = self:calculateSlotItemOffset( i - 1 )
		harvestItem.effect:setOffsetPosition( positionOffset )
		harvestItem.effect:setOffsetRotation( rotationOffset )
		harvestItem.effect:setScale( sm.vec3.new( 0.25, 0.25, 0.25 ) )
		harvestItem.enteringContainer = false
		self.cl.harvestItems[#self.cl.harvestItems+1] = harvestItem
	end
end

function ResourceContainer.client_onDestroy( self )
	for _, harvestItem in ipairs( self.cl.harvestItems ) do
		if harvestItem.effect then
			harvestItem.effect:stop()
		end
	end
end

function ResourceContainer.cl_n_addPickupItem( self, params )
	if self.cl == nil then
		self.cl = {}
	end
	if self.cl.pickupItems == nil then
		self.cl.pickupItems = {}
	end
	
	self.cl.updateEffects = true
	if params.showRenderable then
		local pickupItem = {}
		local fromScale = params.fromScale or 0.25
		pickupItem.effect = sm.effect.createEffect( "ShapeRenderable" )
		pickupItem.effect:setParameter( "uuid", params.shapeUuid )
		pickupItem.effect:setPosition( params.fromPosition )
		pickupItem.effect:setRotation( params.fromRotation )
		pickupItem.effect:setScale( sm.vec3.new( fromScale, fromScale, fromScale ) )
		pickupItem.effect:start()
		pickupItem.elapsedTime = 0.0
		pickupItem.fromScale = sm.vec3.new( fromScale, fromScale, fromScale )
		pickupItem.fromPosition = params.fromPosition
		pickupItem.fromRotation = params.fromRotation
		pickupItem.velocity = params.velocity
		pickupItem.angularVelocity = params.angularVelocity
		pickupItem.slotIndex = params.slotIndex
		self.cl.pickupItems[#self.cl.pickupItems+1] = pickupItem
		self.cl.harvestItems[pickupItem.slotIndex+1].enteringContainer = true
		local scale = params.scale or 0.25
		self.cl.harvestItems[pickupItem.slotIndex+1].targetScale = sm.vec3.new( scale ,scale,scale )
		sm.effect.playEffect( "Gravelcollector - Draw", self.shape.worldPosition )
	else
		if self.cl.gravelCollector then
			sm.effect.playEffect( "Gravelcollector - Insert", self.shape.worldPosition )
		else
			sm.effect.playEffect( "Resourcecollector - TakeOut", self.shape.worldPosition )
		end
	end
end

function ResourceContainer.cl_updateEffects( self, container )
	for i = 1, self.ContainerSize do
		local slotItem = container:getItem( i - 1 )
		local harvestItem = self.cl.harvestItems[i]
		if harvestItem.effect then
			if slotItem.uuid == sm.uuid.getNil() then
				if harvestItem.effect:isPlaying() then
					harvestItem.effect:stop()
				end
			else
				if not harvestItem.effect:isPlaying() and not harvestItem.enteringContainer then
					harvestItem.effect:start()
				end
				if harvestItem.effect:isPlaying() then
					harvestItem.effect:setParameter( "uuid", slotItem.uuid )
				end
			end
		end
	end
	self.cl.updateEffects = false
end

function ResourceContainer.client_onUpdate( self, dt )
	local container = self.interactable:getContainer( 0 )
	if container then

		-- Update pickup item effects
		local pickupTime = 0.4
		local remainingPickupItems = {}
		for _, pickupItem in ipairs( self.cl.pickupItems ) do
			pickupItem.elapsedTime = pickupItem.elapsedTime + dt
			if pickupItem.elapsedTime >= pickupTime then
				pickupItem.effect:stop()
				if self.cl.gravelCollector then
					sm.effect.playEffect( "Gravelcollector - Insert", self.shape.worldPosition )
				else
					sm.effect.playEffect( "Resourcecollector - PutIn", self.shape.worldPosition )
					local itemUuid = container:getItem( pickupItem.slotIndex ).uuid
					local materialId = UuidStringToMaterialId[tostring( itemUuid )]
					sm.effect.playEffect( "Collision - Impact", self.shape.worldPosition, nil, nil, nil, { Material = materialId, Velocity_max_50 = CollectSoundVelocity } )
				end
				self.cl.harvestItems[pickupItem.slotIndex+1].enteringContainer = false
				self.cl.updateEffects = true
			else
				self.cl.harvestItems[pickupItem.slotIndex+1].enteringContainer = true
				local windup = 0.55
				local progress = math.min( pickupItem.elapsedTime / pickupTime, 1.0 )
				pickupItem.fromPosition = pickupItem.fromPosition + pickupItem.velocity * dt * ( 1 - progress )
				pickupItem.fromRotation = PredictRotation( pickupItem.fromRotation, pickupItem.angularVelocity, dt * ( 1 - progress ) )
				if progress > windup then
					local positionOffset, rotationOffset = self:calculateSlotItemOffset( pickupItem.slotIndex )
					local toPosition = self.shape.worldPosition + self.shape.worldRotation * positionOffset
					local toRotation = self.shape.worldRotation * rotationOffset
					local windupProgress = ( ( progress - windup )/( 1 - windup ) )
					pickupItem.effect:setScale( sm.vec3.lerp(  pickupItem.fromScale, self.cl.harvestItems[pickupItem.slotIndex+1].targetScale or sm.vec3.new( 0.25,0.25,0.25 ), windupProgress ) )
					pickupItem.effect:setPosition( sm.vec3.lerp( pickupItem.fromPosition, toPosition, windupProgress ) )
					pickupItem.effect:setRotation( sm.quat.slerp( pickupItem.fromRotation, toRotation, windupProgress ) )
				else
					pickupItem.effect:setPosition( pickupItem.fromPosition )
					pickupItem.effect:setRotation( pickupItem.fromRotation )
				end
				self.cl.updateEffects = true
				remainingPickupItems[#remainingPickupItems+1] = pickupItem
			end
		end
		self.cl.pickupItems = remainingPickupItems

		local containerRevision = container:getRevision()
		if self.cl.updateEffects or self.cl.containerRevision ~= containerRevision then
			self:cl_updateEffects( container )
			self.cl.containerRevision = containerRevision
		end

		-- Update attached renderable effects
	end
end

function ResourceContainer.client_canInteract( self )
	local container = self.interactable:getContainer( 0 )
	if container and not container:isEmpty() and sm.localPlayer.getCarry():isEmpty() then
		local slotIndex = self:cl_getRaycastSlot()
		local slotItem = container:getItem( slotIndex )
		if slotItem.quantity > 0 then
			local keyBindingText = sm.gui.getKeyBinding( "Use", true )
			sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PICK_UP} #FFFFC0" .. sm.shape.getShapeTitle( slotItem.uuid ) )
			return true
		end
	end
	return false
end

function ResourceContainer.client_onInteract( self, user, state )
	if state then
		local container = self.interactable:getContainer( 0 )
		if not container:isEmpty() and sm.localPlayer.getCarry():isEmpty() then
			local params = { slotIndex = self:cl_getRaycastSlot() }
			self.network:sendToServer( "sv_n_takeHarvest", params )
		end
	end
end

function ResourceContainer.cl_getRaycastSlot( self )
	local interactRange = 7.5
	local success, result = sm.localPlayer.getRaycast( interactRange )
	if success then
		-- Adjust for angle and transform to local
		local f = -0.25 / ( result.directionWorld:normalize():dot( result.normalWorld ) * interactRange )
		local intersectionWorldPos = result.originWorld + result.directionWorld * ( result.fraction - f )
		local localPoint = self.shape:transformPoint( intersectionWorldPos ) * 4 + sm.vec3.new( 2.5, 2.5, 0 )
		local xIndex = math.min( math.max( math.floor( localPoint.x ), 0 ), 4 )
		local yIndex = math.min( math.max( math.floor( localPoint.y ), 0 ), 4 ) * 5
		local slotIndex = math.min( math.max( xIndex + yIndex, 0 ), 24 )
		return slotIndex
	end
	return 0
end

function ResourceContainer.calculateSlotItemOffset( self, slotIndex )
	local width = 5
	local height = 5
	local offsetCornerPosition = sm.vec3.new( -0.5, -0.5, 0 )
	local rotationOffset = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), sm.vec3.new( 0, 1, 0 ) )
	local positionOffset = offsetCornerPosition + sm.vec3.new( 0.25 * ( slotIndex % width ) , 0.25 * ( math.floor( slotIndex / width ) % height ), 0 )
	return positionOffset, rotationOffset
end
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/pipes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_items.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua"

Refinery = class( nil )
local AnimUnpackTime = 1
local AnimStartTime = 0.8667
local AnimUseTime = 4
local AnimFinishTime = 2
local TutorialActivationDistance = 7.5

local RefineryRecipes = {
	[tostring( ITEMS.obj_harvest_wood )] = {
		itemId = tostring( ITEMS.blk_scrapwood ),
		itemUuid = ITEMS.blk_scrapwood,
		quantity = 20,
		craftTime = 7,
        ingredientList = { { quantity = 1, itemId = ITEMS.obj_harvest_wood } }
	},
	[tostring( ITEMS.obj_harvest_wood2 )] =	{
		itemId = tostring( ITEMS.blk_scrapwood ),
		itemUuid = ITEMS.blk_scrapwood,
		quantity = 40,
		craftTime = 7,
        ingredientList = { { quantity = 1, itemId = ITEMS.obj_harvest_wood2 } } },
	[tostring( ITEMS.obj_harvest_metal )] = {
		itemId = tostring( ITEMS.blk_scrapmetal ),
		itemUuid = ITEMS.blk_scrapmetal,
		quantity = 20,
		craftTime = 7,
        ingredientList = { { quantity = 1, itemId = ITEMS.obj_harvest_metal } }
	},
	[tostring( ITEMS.obj_harvest_metal2 )] = {
		itemId = tostring( ITEMS.blk_metal1 ),
		itemUuid = ITEMS.blk_metal1,
		quantity = 20,
		craftTime = 7,
        ingredientList = { { quantity = 1, itemId = ITEMS.obj_harvest_metal2 } }
	},
	[tostring( ITEMS.obj_harvest_stone )] = {
		itemId = tostring( ITEMS.blk_scrapstone ),
		itemUuid = ITEMS.blk_scrapstone,
		quantity = 20,
		craftTime = 7,
        ingredientList = { { quantity = 1, itemId = ITEMS.obj_harvest_stone } }
	}
}

function Refinery.server_onCreate(self)
	self.sv = {}
	if not self.shape:getInteractable():getContainer( 1 ) then
		self.shape:getInteractable():addContainer( 1, 1, 1 )
	end
	local container = self.shape:getInteractable():getContainer( 0 )
	if not container then
		container = self.shape:getInteractable():addContainer( 0, 5 )
	end
	container.allowCollect = false

	local saved = self.storage:load()
	if saved == nil then
		self.storage:save( {} )
	else
		self.network:setClientData( nil )
	end

	self:sv_init()
end

function Refinery.getInputContainer( self )
	return self.shape:getInteractable():getContainer( 1 )
end

function Refinery.getOutputContainer( self )
	return self.shape:getInteractable():getContainer( 0 )
end

function Refinery.server_canErase( self )
	local containerIn = self:getInputContainer()
	if not containerIn:isEmpty() then
		return false
	end
	return true
end

function Refinery.client_canErase( self )
	local containerIn = self:getInputContainer()
	if not containerIn:isEmpty() then
		NotificationManager.Cl_AddGenericNotification( "#{INFO_BUSY}", BUSY_NOTIFICATION_DURATION )
		return false
	end
	return true
end

function Refinery.client_onCreate( self )
	self.cl = {}
	self:cl_init()
	self.cl.suckStartEffect = sm.effect.createEffect( "Refinery - SuckStart", self.interactable, "jnt_suction" )
	self.cl.workWoodEffect = sm.effect.createEffect( "Refinery - WorkWood", self.interactable, "root_jnt" )
	self.cl.workStoneEffect = sm.effect.createEffect( "Refinery - WorkStone", self.interactable, "root_jnt" )
	self.cl.workMetalEffect = sm.effect.createEffect( "Refinery - WorkMetal", self.interactable, "root_jnt" )
	self.cl.suckFinishEffect = sm.effect.createEffect( "Refinery - Finish", self.interactable, "jnt_suction" )
	self.cl.unpackEffect = sm.effect.createEffect( "Refinery - Unpack", self.interactable, "root_jnt" )

	self.cl.harvestEffect = sm.effect.createEffect( "ShapeRenderable", self.interactable, "rendable_jnt" )
	self.cl.startEffect = sm.effect.createEffect( "Refinery - Start", self.interactable, "root_jnt" )
	self.cl.scrapWoodEffect = sm.effect.createEffect( "Refinery - ScrapWoodBlock", self.interactable, "root_jnt" )
	self.cl.scrapStoneEffect = sm.effect.createEffect( "Refinery - ScrapStoneBlock", self.interactable, "root_jnt" )
	self.cl.scrapMetalEffect = sm.effect.createEffect( "Refinery - ScrapMetalBlock", self.interactable, "root_jnt" )
	self.cl.woodEffect = sm.effect.createEffect( "Refinery - WoodBlock", self.interactable, "root_jnt" )
	self.cl.metalEffect = sm.effect.createEffect( "Refinery - MetalBlock", self.interactable, "root_jnt" )

	self.cl.scrapWoodEffectLog = sm.effect.createEffect( "Refinery - ScrapWoodBlockLog", self.interactable, "rendable_jnt" )
	self.cl.scrapStoneEffectLog = sm.effect.createEffect( "Refinery - ScrapStoneBlockLog", self.interactable, "rendable_jnt" )
	self.cl.scrapMetalEffectLog = sm.effect.createEffect( "Refinery - ScrapMetalBlockLog", self.interactable, "rendable_jnt" )
	self.cl.woodEffectLog = sm.effect.createEffect( "Refinery - WoodBlockLog", self.interactable, "rendable_jnt" )
	self.cl.metalEffectLog = sm.effect.createEffect( "Refinery - MetalBlockLog", self.interactable, "rendable_jnt" )

	self.cl.playUnpackEffect = true

	local myCharacter = sm.localPlayer.getPlayer().character
	if sm.exists( myCharacter ) then
		local distance2 = ( myCharacter.worldPosition - self.shape.worldPosition ):length2()
		if distance2 <= TutorialActivationDistance^2 then
			TutorialManager.Cl_TutorialEvent( TutorialEvent.Refinerybot )
		end
	end
end

function Refinery.client_onClientDataUpdate( self, clientData, channel )
	self.cl.playUnpackEffect = false
end

function Refinery.client_onDestroy(self)
	if self.cl.pipeEffectPlayer then
		self.cl.pipeEffectPlayer:onDestroy()
	end
	if self.cl.gui and self.cl.gui:isActive() then
		self.cl.gui:close()
		self.cl.gui:destroy()
	end

	if self.cl.startEffect then
		self.cl.startEffect:stop()
		self.cl.startEffect:destroy()
	end
	if self.cl.suckStartEffect then
		self.cl.suckStartEffect:stop()
		self.cl.suckStartEffect:destroy()
	end
	if self.cl.workWoodEffect then
		self.cl.workWoodEffect:stop()
		self.cl.workWoodEffect:destroy()
	end
	if self.cl.workStoneEffect then
		self.cl.workStoneEffect:stop()
		self.cl.workStoneEffect:destroy()
	end
	if self.cl.workMetalEffect then
		self.cl.workMetalEffect:stop()
		self.cl.workMetalEffect:destroy()
	end
	if self.cl.suckFinishEffect then
		self.cl.suckFinishEffect:stop()
		self.cl.suckFinishEffect:destroy()
	end
	if self.cl.unpackEffect then
		self.cl.unpackEffect:stop()
		self.cl.unpackEffect:destroy()
	end
	if self.cl.harvestEffect then
		self.cl.harvestEffect:stop()
		self.cl.harvestEffect:destroy()
	end
	if self.cl.scrapWoodEffect then
		self.cl.scrapWoodEffect:stop()
		self.cl.scrapWoodEffect:destroy()
	end
	if self.cl.scrapStoneEffect then
		self.cl.scrapStoneEffect:stop()
		self.cl.scrapStoneEffect:destroy()
	end
	if self.cl.scrapMetalEffect then
		self.cl.scrapMetalEffect:stop()
		self.cl.scrapMetalEffect:destroy()
	end
	if self.cl.woodEffect then
		self.cl.woodEffect:stop()
		self.cl.woodEffect:destroy()
	end
	if self.cl.metalEffect then
		self.cl.metalEffect:stop()
		self.cl.metalEffect:destroy()
	end
	if self.cl.scrapWoodEffectLog then
		self.cl.scrapWoodEffectLog:stop()
		self.cl.scrapWoodEffectLog:destroy()
	end
	if self.cl.scrapStoneEffectLog then
		self.cl.scrapStoneEffectLog:stop()
		self.cl.scrapStoneEffectLog:destroy()
	end
	if self.cl.scrapMetalEffectLog then
		self.cl.scrapMetalEffectLog:stop()
		self.cl.scrapMetalEffectLog:destroy()
	end
	if self.cl.woodEffectLog then
		self.cl.woodEffectLog:stop()
		self.cl.woodEffectLog:destroy()
	end
	if self.cl.metalEffectLog then
		self.cl.metalEffectLog:stop()
		self.cl.metalEffectLog:destroy()
	end
end

function Refinery.sv_init(self)
	sm.pipeGraph.removeAutomatedTasks( self.shape )
	self.sv.updateProgress = 0.0
	self.sv.updateTime = 1.0 		--seconds

	self.sv.isProducing = false
	self.sv.productionProgress = 0.0
	self.sv.productionTime = AnimStartTime + AnimUseTime + AnimFinishTime

	self.sv.sourceShapeSignature = nil
	if self.sv.areaTrigger then
		sm.areaTrigger.destroy( self.sv.areaTrigger )
		self.sv.areaTrigger = nil
	end

	local size = sm.vec3.new( 0.5, 0.5, 0.5 )
	local position = sm.vec3.new( -2.0, -0.25, 0.0 )
	local filter = sm.areaTrigger.filter.areaTrigger
	self.sv.areaTrigger = sm.areaTrigger.createAttachedBox( self.interactable, size, position, sm.quat.identity(), filter )
	self.sv.areaTrigger:bindOnExit( "sv_t_exitRefresh" )
end

function Refinery.sv_t_exitRefresh( self )
	self.sv.updateProgress = 1.0
end

function Refinery.cl_createAnimation( self, name, playTime )
	local animation =
	{
		name = name,
		playProgress = 0.0,
		playTime = playTime,
		isActive = false,
		looping = false,
		playForward = true,
		nextAnimation = nil,
		nextAnimations = nil
	}
	return animation
end

function Refinery.cl_setAnimation( self, animation, playProgress )

	self:cl_unsetAnimation()
	animation.isActive = true
	animation.playProgress = playProgress
	self.interactable:setAnimEnabled(animation.name, true)
	self.cl.currentAnimation = animation.name
end

function Refinery.cl_unsetAnimation( self )

	for name, animation in pairs( self.cl.animations ) do
		animation.isActive = false
		animation.playProgress = 0.0
		self.interactable:setAnimEnabled(animation.name, false)
		self.interactable:setAnimProgress(animation.name, animation.playProgress )
	end
	self.cl.currentAnimation = ""
end

function Refinery.cl_updateAnimation( self, dt )
	for name, animation in pairs( self.cl.animations ) do
		if animation.isActive then
			self.interactable:setAnimEnabled(animation.name, true)
			if animation.playForward then
				animation.playProgress = animation.playProgress + dt / animation.playTime
				if animation.playProgress > 1.0 then
					if animation.looping then
						animation.playProgress = animation.playProgress - 1.0
					else
						if animation.nextAnimation then
							self:cl_setAnimation( animation.nextAnimation, 0.0 )
							return
						elseif animation.nextAnimations then
							self:cl_setAnimation( animation.nextAnimations[math.random( 1, #animation.nextAnimations )], 0.0 )
							return
						else
							animation.playProgress = 1.0
						end
					end
				end
				self.interactable:setAnimProgress(animation.name, animation.playProgress )
			else
				animation.playProgress = animation.playProgress - dt / animation.playTime
				if animation.playProgress < -1.0 then
					if animation.looping then
						animation.playProgress = animation.playProgress + 1.0
					else
						if animation.nextAnimation then
							self:cl_setAnimation( animation.nextAnimation, 0.0)
							return
						elseif animation.nextAnimations then
							self:cl_setAnimation( animation.nextAnimations[math.random( 1, #animation.nextAnimations )], 0.0 )
							return
						else
							animation.playProgress = -1.0
						end
					end
				end
				self.interactable:setAnimProgress(animation.name, 1.0 + animation.playProgress )
			end
		end
	end
end

function Refinery.cl_init(self)

	local animations = {}
	animations["unpack"] = self:cl_createAnimation( "Refinery_unpack", AnimUnpackTime )
	animations["start"] = self:cl_createAnimation( "Refinery_start", AnimStartTime )
	animations["use"] = self:cl_createAnimation( "Refinery_use", AnimUseTime )
	animations["finish"] = self:cl_createAnimation( "Refinery_finish", AnimFinishTime )
	animations["start"].nextAnimation = animations["use"]
	animations["use"].nextAnimation = animations["finish"]
	self.cl.animations = animations
	self.cl.currentAnimation = ""

	self:cl_setAnimation(self.cl.animations["unpack"], 0.0)

	self.cl.isProducing = false
	self.cl.productionProgress = 0.0
	self.cl.productionTime = AnimStartTime + AnimUseTime + AnimFinishTime

	self.cl.pipeEffectPlayer = PipeEffectPlayer()
	self.cl.pipeEffectPlayer:onCreate()
end

function Refinery.server_onRefresh(self)
	self:sv_init()
end

function Refinery.client_onRefresh(self)
	self:cl_init()
	self.cl.previousAnimation = nil
end

function Refinery.client_onUpdate(self, dt)

	if self.cl.playUnpackEffect then
		self.cl.unpackEffect:start()
		self.cl.playUnpackEffect = false
	end
	
	self.cl.pipeEffectPlayer:update( dt )

	local container0 = self.shape:getInteractable():getContainer(1)
	local container1 = self.shape:getInteractable():getContainer(0)
	if not container0 or not container1 then
		return
	end

	local inputItemUuids = sm.container.itemUuid(self.shape:getInteractable():getContainer(1))
	local harvestUuid = inputItemUuids[1]

	self:cl_updateAnimation( dt )

	if self.cl.isProducing then
		self.cl.productionProgress = self.cl.productionProgress + dt/self.cl.productionTime
		if self.cl.productionProgress >= 1.0 then
			self.cl.productionProgress = 1.0
		end
	else
		self.cl.productionProgress = 0.0
	end

	if self.cl.animations["start"].isActive then
		if self.cl.previousAnimation ~= self.cl.currentAnimation then
			self.cl.suckStartEffect:start()
			self.cl.startEffect:start()
			self.cl.harvestEffect:setParameter( "uuid", harvestUuid )
			self.cl.harvestEffect:setScale( sm.vec3.new( 0.25, 0.25, 0.25 ) )
			self.cl.harvestEffect:setParameter( "Color", sm.shape.getShapeTypeColor( harvestUuid ) )
			self.cl.harvestEffect:start()
		end
		
	elseif self.cl.animations["use"].isActive then
		if self.cl.previousAnimation ~= self.cl.currentAnimation then
			if harvestUuid == obj_harvest_wood or harvestUuid == obj_harvest_wood2 then
				self.cl.workWoodEffect:start()
			elseif harvestUuid == obj_harvest_stone then
				self.cl.workStoneEffect:start()
			elseif harvestUuid == obj_harvest_metal or harvestUuid == obj_harvest_metal2 then
				self.cl.workMetalEffect:start()
			end
		end
	elseif self.cl.animations["finish"].isActive then
		if self.cl.previousAnimation ~= self.cl.currentAnimation then
			self.cl.harvestEffect:stop()
			self.cl.suckFinishEffect:start()
			if harvestUuid == obj_harvest_wood then
				self.cl.scrapWoodEffect:start()
				self.cl.scrapWoodEffectLog:start()
			elseif harvestUuid == obj_harvest_stone then
				self.cl.scrapStoneEffect:start()
				self.cl.scrapStoneEffectLog:start()
			elseif harvestUuid == obj_harvest_metal then
				self.cl.scrapMetalEffect:start()
				self.cl.scrapMetalEffectLog:start()
			elseif harvestUuid == obj_harvest_metal2 then
				self.cl.metalEffect:start()
				self.cl.metalEffectLog:start()
			elseif harvestUuid == obj_harvest_wood2 then
				self.cl.woodEffect:start()
				self.cl.woodEffectLog:start()
			end
		end
	end

	self.cl.previousAnimation = self.cl.currentAnimation
end

function Refinery.client_onInteract(self, _, state)
	if state == true then
		self.cl.gui = sm.gui.createRefineryContainerGui( true )
		self.cl.gui:setText( "UpperName", "#{CONTAINER_TITLE_REFINERY}" )
		self.cl.gui:setContainer( "UpperGrid", self.shape:getInteractable():getContainer( 0 ) )
		self.cl.gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
		self.cl.gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
		self.cl.gui:setOnCloseCallback( "cl_e_onClose" )
		self.cl.gui:open()
	end
end

function Refinery.cl_e_onClose( self )
	self.cl.gui = nil
end

function Refinery.sv_canFitCraftedItem( self, itemUuid )
	local recipe = RefineryRecipes[tostring( itemUuid )]
	if recipe then
		-- Dry run to see if we can fit all crafted items
		sm.container.beginTransaction()
		local remainingQuantity = recipe.quantity
		remainingQuantity = remainingQuantity - sm.container.collect( self:getOutputContainer(), recipe.itemUuid, recipe.quantity, false )
		while remainingQuantity > 0 do
			local containerShape = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, { recipe.itemUuid }, { 1 } )
			if containerShape == nil then
				break
			end
			local outputContainer = containerShape:getInteractable():getContainer( 0 ) --TODO: Ask the pipe graph for which container to use
			local collected = sm.container.collect( outputContainer, recipe.itemUuid, remainingQuantity, false )
			if collected == 0 then
				break -- Should not be possible
			end
			remainingQuantity = remainingQuantity - collected
		end
		sm.container.abortTransaction()
		return remainingQuantity == 0
	end
	return false
end

function Refinery.server_onFixedUpdate( self, dt )
	if self.sv.isProducing then
		local inputItemUuids = sm.container.itemUuid( self:getInputContainer() )
		local harvestUuid = inputItemUuids[1]
		local recipe = RefineryRecipes[tostring( inputItemUuids[1] )]
		if recipe then
			self.sv.productionProgress = self.sv.productionProgress + dt/self.sv.productionTime
			if self.sv.productionProgress >= 1.0 then
				-- Done producing
				if sm.container.beginTransaction() then
					sm.container.spend( self:getInputContainer(), harvestUuid, 1, true )
					local internalContainer = self:getOutputContainer()
					local remainingQuantity = recipe.quantity
					local effectTargetShapes = {}
					while remainingQuantity > 0 do
						-- Prioritise filling attached pipe containers before the internal output container
						local pipeContainerShape = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, { recipe.itemUuid }, { 1 } )
						local outputContainer = pipeContainerShape and pipeContainerShape:getInteractable():getContainer( 0 ) or internalContainer --TODO: Ask the pipe graph for which container to use
						local collected = sm.container.collect( outputContainer, recipe.itemUuid, remainingQuantity, false )
						if collected == 0 then
							break
						end

						remainingQuantity = remainingQuantity - collected
						if pipeContainerShape then
							effectTargetShapes[#effectTargetShapes+1] = pipeContainerShape
						end
					end
					if remainingQuantity == 0 then
						if sm.container.endTransaction() then
							self.sv.productionProgress = 0.0
							self.sv.isProducing = false
							if #effectTargetShapes > 0 then
								self.network:sendToClients( "cl_n_finishProduction", { effectTargets = effectTargetShapes, item = recipe.itemUuid } )
							else
								self.network:sendToClients( "cl_n_finishProduction" )
							end
						end
					else
						sm.container.abortTransaction()
					end
				end
			end
		else
			self.sv.isProducing = false
			self.sv.productionProgress = 0.0
			local params = { isProducing = false }
			self.network:sendToClients( "cl_n_setIsProducing", params )
		end
	else
		self.sv.productionProgress = 0
	end

	--------------------

	self.sv.updateProgress = self.sv.updateProgress + dt/self.sv.updateTime
	if self.sv.updateProgress >= 1.0 then
		self.sv.updateProgress = 0.0

		local inputItemUuids = sm.container.itemUuid( self:getInputContainer() )
		local hasInputItem = RefineryRecipes[tostring( inputItemUuids[1] )] ~= nil

		if not sm.uuid.isNil( inputItemUuids[1] ) and not hasInputItem then
			sm.log.error( "Refinery got an invalid input item: "..tostring( inputItemUuids[1] ) )
			sm.container.beginTransaction()
			sm.container.setItem( self:getInputContainer(), 0, sm.uuid.getNil(), 0 )
			sm.container.endTransaction()
			hasInputItem = false
		end
		-------------------
		local foundContainers = {}
		local adjacentShapeIds = {}
		for _, object in ipairs( self.sv.areaTrigger:getContents() ) do
			if type( object ) == "AreaTrigger" then
				local trigger = object
				if sm.exists( trigger ) then
					local userData = trigger:getUserData()
					if userData and userData.resourceCollector and not userData.isGravelCollector then
						local shape = userData.resourceCollector
						--Search shape containers
						if shape:getInteractable() then
							local otherContainer = shape:getInteractable():getContainer( 0 )
							if otherContainer then
								foundContainers[#foundContainers+1] = otherContainer
								adjacentShapeIds[#adjacentShapeIds+1] = shape:getId()
							end
						end
					end
				end
			end
		end

		table.sort( adjacentShapeIds )
		if not ArrayCompareShallow( adjacentShapeIds, self.sv.sourceShapeSignature or {} ) then
			self.sv.sourceShapeSignature = adjacentShapeIds
			sm.pipeGraph.removeAutomatedTasks( self.shape )
		end
		
		if not hasInputItem then
			for _,otherContainer in ipairs( foundContainers ) do
				local otherItemUuids = sm.container.itemUuid( otherContainer )
				for _, itemUuid in ipairs( otherItemUuids ) do
					local recipe = RefineryRecipes[tostring( itemUuid )]
					if recipe then
						--if self:sv_canFitCraftedItem( itemUuid ) then --NOTE: Not guaranteed to still fit when done
							if sm.container.beginTransaction() then
								sm.container.collect( self.shape:getInteractable():getContainer( 1 ), itemUuid, 1, true )
								sm.container.spend( otherContainer, itemUuid, 1, true )
								for _, currentRecipe in pairs( RefineryRecipes ) do
									local recipeCopy = shallowcopy( currentRecipe )
									recipeCopy.externalContainers = foundContainers
									recipeCopy.selfOutputContainer = self:getOutputContainer()
									sm.pipeGraph.setAutomatedTask( self.shape, recipeCopy )
								end
								sm.container.endTransaction()
							end
							break
						--end
					end
				end
			end
		end

		if hasInputItem then
			-- Can produce so start production
			if not self.sv.isProducing then
				self.sv.isProducing = true
				self.sv.productionProgress = 0.0
				local params = { isProducing = true }
				self.network:sendToClients( "cl_n_setIsProducing", params )
			end
		end

		if not hasInputItem then
			-- Abort any ongoing production because production can't continue
			if self.sv.isProducing then
				self.sv.isProducing = false
				self.sv.productionProgress = 0.0
				local params = { isProducing = false }
				self.network:sendToClients( "cl_n_setIsProducing", params )
			end
		end
		--TODO: Handle outputFull. Sen jammed signal to client
	end
end












function Refinery.sv_e_receiveItem( self, params )
	local recipe = RefineryRecipes[tostring( params.itemA )]
	if recipe then --and self:sv_canFitCraftedItem( params.itemA )
		local container = self.interactable:getContainer( 1 )
		if container then
			sm.container.beginTransaction()
			sm.container.spend( params.containerA, params.itemA, params.quantityA, true )
			sm.container.collect( container, params.itemA, params.quantityA, true )
			sm.container.endTransaction()
		end
	end
end

function Refinery.cl_n_setIsProducing( self, params )
	self.cl.productionProgress = 0.0
	self.cl.isProducing = params.isProducing
	if params.isProducing then
		self:cl_setAnimation( self.cl.animations["start"], 0.0 )
	else
		self:cl_unsetAnimation()
	end
end

function Refinery.cl_n_finishProduction( self, params )
	self.cl.productionProgress = 0.0
	self.cl.isProducing = false
	self:cl_setAnimation( self.cl.animations["unpack"], 1.0 )
	if params then
		for _, targetShape in ipairs( params.effectTargets ) do
			local containerPath = sm.pipeGraph.getContainerPath( self.shape, targetShape )
			table.insert( containerPath, 1, self.shape )
			self.cl.pipeEffectPlayer:pushShapeEffectTask( containerPath, params.item )
		end
	end
end
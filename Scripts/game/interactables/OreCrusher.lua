dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/pipes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_items.lua"
dofile "$SURVIVAL_DATA/Scripts/game/interactables/Refinery.lua"

OreCrusher = class( Refinery )
local AnimUnpackTime = 0.85
local AnimStartTime = 1.5
local AnimUseTime = 2.5
local AnimFinishTime = 5.0

local PipeDelay = 0.5

local OreCrusherRecipes = {
	[tostring( ITEMS.obj_voxelmaterial_rich )] = {
		itemId = tostring( ITEMS.obj_resource_residueore ),
		itemUuid = ITEMS.obj_resource_residueore,
		quantity = 1,
		craftTime = 7,
		ingredientList = { { quantity = 500, itemId = ITEMS.obj_voxelmaterial_rich } }
	},
	[tostring( ITEMS.obj_voxelmaterial_t1 )] = {
		itemId = tostring( ITEMS.obj_nugget_t1 ),
		itemUuid = ITEMS.obj_nugget_t1,
		quantity = 1,
		craftTime = 7,
		ingredientList = { { quantity = 1000, itemId = ITEMS.obj_voxelmaterial_t1 } }
	},
	[tostring( ITEMS.obj_voxelmaterial_t3 )] = {
		itemId = tostring( ITEMS.obj_nugget_t3 ),
		itemUuid = ITEMS.obj_nugget_t3,
		quantity = 1,
		craftTime = 7,
		ingredientList = { { quantity = 1000, itemId = ITEMS.obj_voxelmaterial_t3 } }
	},
	[tostring( ITEMS.obj_voxelmaterial_t4 )] = {
		itemId = tostring( ITEMS.obj_nugget_t4 ),
		itemUuid = ITEMS.obj_nugget_t4,
		quantity = 1,
		craftTime = 7,
		ingredientList = { { quantity = 1000, itemId = ITEMS.obj_voxelmaterial_t4 } }
	},
	[tostring( ITEMS.obj_resource_drillcasingt1 )] = {
		itemId = tostring( ITEMS.obj_nugget_t1 ),
		itemUuid = ITEMS.obj_nugget_t1,
		quantity = 10,
		craftTime = 7,
		ingredientList = { { quantity = 1, itemId = ITEMS.obj_resource_drillcasingt1 } }
	},
	[tostring( ITEMS.obj_resource_drillcasingt3 )] = {
		itemId = tostring( ITEMS.obj_nugget_t3 ),
		itemUuid = ITEMS.obj_nugget_t3,
		quantity = 10,
		craftTime = 7,
		ingredientList = { { quantity = 1, itemId = ITEMS.obj_resource_drillcasingt3 } }
	},
	[tostring( ITEMS.obj_resource_drillcasingt4 )] = {
		itemId = tostring( ITEMS.obj_nugget_t4 ),
		itemUuid = ITEMS.obj_nugget_t4,
		quantity = 10,
		craftTime = 7,
		ingredientList = { { quantity = 1, itemId = ITEMS.obj_resource_drillcasingt4 } }
	},
	[tostring( ITEMS.obj_resource_drillcasingrich )] = {
		itemId = tostring( ITEMS.obj_resource_residueore ),
		itemUuid = ITEMS.obj_resource_residueore,
		quantity = 20,
		craftTime = 7,
		ingredientList = { { quantity = 1, itemId = ITEMS.obj_resource_drillcasingrich } }
	},
}






function OreCrusher.server_onCreate( self )
	self.sv = {}
	if not self:getInputContainer() then
		self.shape:getInteractable():addContainer( 1, 10 )
	end
	local container = self:getOutputContainer()
	if not container then
		container = self.shape:getInteractable():addContainer( 0, 5 )
	end
	container.allowCollect = false
	self.sv.saved = self.storage:load() or {}
	self.sv.saved.randomizedCraftData = self.sv.saved.randomizedCraftData or nil

	self:sv_init()
end

function OreCrusher.sv_init( self )

	sm.pipeGraph.removeAutomatedTasks( self.shape )
	self.sv.updateProgress = 0.0
	self.sv.updateTime = 1.0 		--seconds

	self.sv.hasInputItem = false
	self.sv.outputFull = false

	self.sv.isProducing = false
	self.sv.productionProgress = 0.0
	self.sv.productionTime = AnimStartTime + AnimUseTime + AnimFinishTime

	if self.sv.areaTrigger then
		sm.areaTrigger.destroy( self.sv.areaTrigger )
		self.sv.areaTrigger = nil
	end
	self.sv.sourceShapeSignature = nil

	local size = sm.vec3.new( 1, 1, 1 )
	local position = sm.vec3.new( 0, 0, 0 )
	local filter = sm.areaTrigger.filter.areaTrigger
	self.sv.areaTrigger = sm.areaTrigger.createAttachedBox( self.interactable, size, position, sm.quat.identity(), filter )
	self.sv.areaTrigger:bindOnExit( "sv_t_exitRefresh" )
end

function OreCrusher.client_onCreate( self )
	self.cl = {}
	self:cl_init()
end

function OreCrusher.client_onDestroy(self)
	if self.cl.pipeEffectPlayer then
		self.cl.pipeEffectPlayer:onDestroy()
	end
	-- TODO stop and destroy effects
	if self.cl.gui and sm.exists( self.cl.gui ) and self.cl.gui:isActive() then
		self.cl.gui:close()
		self.cl.gui:destroy()
	end
end

function OreCrusher.cl_init(self)

	local animations = {}
	animations["unpack"] = self:cl_createAnimation( "unpack", AnimUnpackTime )
	animations["start"] = self:cl_createAnimation( "start", AnimStartTime )
	animations["use"] = self:cl_createAnimation( "use01", AnimUseTime )
	animations["finish"] = self:cl_createAnimation( "finish01", AnimFinishTime )
	animations["finish2"] = self:cl_createAnimation( "finish02", AnimFinishTime )
	animations["start"].nextAnimation = animations["use"]
	animations["use"].nextAnimations = { animations["finish"], animations["finish2"] }
	self.cl.animations = animations
	self.cl.currentAnimation = ""
	self:cl_setAnimation( self.cl.animations["unpack"], 0.0 )

	self.cl.isProducing = false
	self.cl.productionProgress = 0.0
	self.cl.productionTime = AnimStartTime + AnimUseTime + AnimFinishTime

	self.cl.pipeEffectPlayer = PipeEffectPlayer()
	self.cl.pipeEffectPlayer:onCreate()
end

local StrT1 = tostring( ITEMS.obj_resource_drillcasingt1 )
local StrT3 = tostring( ITEMS.obj_resource_drillcasingt3 )
local StrT4 = tostring( ITEMS.obj_resource_drillcasingt4 )
local StrRich = tostring( ITEMS.obj_resource_drillcasingrich )
local StrMixedT1 = tostring( ITEMS.obj_resource_drillcasingmixedt1 )
local StrMixedT3 = tostring( ITEMS.obj_resource_drillcasingmixedt3 )
local StrMixedT4 = tostring( ITEMS.obj_resource_drillcasingmixedt4 )
local StrMixedRich = tostring( ITEMS.obj_resource_drillcasingmixedrich )

local CrushEffects = {
	Start = {
		[StrT1] = "Orecrusher - Start_t1",
		[StrT3] = "Orecrusher - Start_t3",
		[StrT4] = "Orecrusher - Start_t4",
		[StrRich] = "Orecrusher - Start_orerich",
		[StrMixedT1] = "Orecrusher - Start_t1",
		[StrMixedT3] = "Orecrusher - Start_t3",
		[StrMixedT4] = "Orecrusher - Start_t4",
		[StrMixedRich] = "Orecrusher - Start_orerich",
	},
	Use = {
		[StrT1] = "Orecrusher - Use01_t1",
		[StrT3] = "Orecrusher - Use01_t3",
		[StrT4] = "Orecrusher - Use01_t4",
		[StrRich] = "Orecrusher - Use01_orerich",
		[StrMixedT1] = "Orecrusher - Use01_t1",
		[StrMixedT3] = "Orecrusher - Use01_t3",
		[StrMixedT4] = "Orecrusher - Use01_t4",
		[StrMixedRich] = "Orecrusher - Use01_orerich",
	},
	Finish = {
		[StrT1] = "Orecrusher - Finish01_t1",
		[StrT3] = "Orecrusher - Finish01_t3",
		[StrT4] = "Orecrusher - Finish01_t4",
		[StrRich] = "Orecrusher - Finish01_orerich",
		[StrMixedT1] = "Orecrusher - Finish01_t1",
		[StrMixedT3] = "Orecrusher - Finish01_t3",
		[StrMixedT4] = "Orecrusher - Finish01_t4",
		[StrMixedRich] = "Orecrusher - Finish01_orerich",
	},
	FinishRocks = {
		[StrT1] = "Orecrusher - Finish02_t1",
		[StrT3] = "Orecrusher - Finish02_t3",
		[StrT4] = "Orecrusher - Finish02_t4",
		[StrRich] = "Orecrusher - Finish02_orerich",
		[StrMixedT1] = "Orecrusher - Finish02_t1",
		[StrMixedT3] = "Orecrusher - Finish02_t3",
		[StrMixedT4] = "Orecrusher - Finish02_t4",
		[StrMixedRich] = "Orecrusher - Finish02_orerich",
	}
}

function OreCrusher.client_onUpdate(self, dt)
	self.cl.pipeEffectPlayer:update( dt )

	local container0 = self:getInputContainer()
	local container1 = self:getOutputContainer()
	if not container0 or not container1 then
		return
	end

	self:cl_updateAnimation( dt )

	if self.cl.isProducing then
		self.cl.productionProgress = self.cl.productionProgress + dt/self.cl.productionTime
		if self.cl.productionProgress >= 1.0 then
			self.cl.productionProgress = 1.0
		end
	else
		self.cl.productionProgress = 0.0
	end

	local strItemUuid = tostring(container0:getItem( 0 ).uuid)

	if self.cl.animations["start"].isActive then
		if self.cl.previousAnimation ~= self.cl.currentAnimation then
			sm.effect.playHostedEffect( CrushEffects.Start[strItemUuid] or "Orecrusher - Start_t1", self.interactable, "jnt_suction" )
		end
	elseif self.cl.animations["use"].isActive then
		if self.cl.previousAnimation ~= self.cl.currentAnimation then
			sm.effect.playHostedEffect( CrushEffects.Use[strItemUuid] or "Orecrusher - Use01_t1", self.interactable, "rendable_jnt" )
		end
	elseif self.cl.animations["finish"].isActive or self.cl.animations["finish2"].isActive then
		if self.cl.previousAnimation ~= self.cl.currentAnimation then
			sm.effect.playHostedEffect( CrushEffects.Finish[strItemUuid] or "Orecrusher - Finish01_t1", self.interactable, "rendable_jnt" )
			sm.effect.playHostedEffect( CrushEffects.FinishRocks[strItemUuid] or "Orecrusher - Finish02_t1", self.interactable, "jnt_m_lower_tooth" )
		end
	end
	self.cl.previousAnimation = self.cl.currentAnimation
end

function OreCrusher.client_onInteract(self, _, state)
	if state == true then
		self.cl.gui = sm.gui.createOreCrusherContainerGui( true )
		self.cl.gui:setText( "UpperName", "#{CONTAINER_TITLE_ORECRUSHER}" )
		self.cl.gui:setContainer( "UpperGrid", self:getOutputContainer() )
		self.cl.gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
		self.cl.gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
		self.cl.gui:open()
	end
end

function OreCrusher.cl_n_finishProduction( self, params )
	self.cl.productionProgress = 0.0
	self.cl.isProducing = false
	self:cl_setAnimation( self.cl.animations["unpack"], 1.0 )
	if params then
		local counter = 0
		for _,data in pairs( params ) do
			if data.container then
				local containerPath = sm.pipeGraph.getContainerPath( self.shape, data.container )
				table.insert( containerPath, 1, self.shape )
				for _,item in ipairs( data.items ) do
					if containerPath then
						self.cl.pipeEffectPlayer:pushShapeEffectTask( containerPath, item, PipeDelay * counter )
						counter = counter + 1
					end
				end
			end
		end
	end
end

function OreCrusher.sv_e_receiveItem( self, params )
	if isAnyOf( params.itemA, g_gravelCollectorHarvests ) then
		local container = self.interactable:getContainer( 1 )
		if container and container:isEmpty() then
			sm.container.beginTransaction()
			if params.itemA == ITEMS.obj_resource_drillcasingmixedt1 or params.itemA == ITEMS.obj_resource_drillcasingmixedt3
			 or params.itemA == ITEMS.obj_resource_drillcasingmixedt4 or params.itemA == ITEMS.obj_resource_drillcasingmixedrich then
				local carryData = params.player:getCarryData()
				if carryData then
					for uid,count in pairs( carryData ) do
						assert( type( uid ) == "string" )
						if OreCrusherRecipes[uid] then
							sm.container.collect( self.shape:getInteractable():getContainer( 1 ), sm.uuid.new( uid ), count, true )
						else
							print( "OreCrusher: No recipe found for item in gravel casing: "..uid )
						end
					end
				end
				sm.container.spend( params.containerA, params.itemA, params.quantityA, true )
			else
				sm.container.moveAll( params.containerA, container, true )
			end
			sm.container.endTransaction()
		end
	end
end

function OreCrusher.sv_getUuidAndQuantity( self, recipe )
	local itemUuid = nil
	local quantity = 0
	if recipe.randomCraftList then
		if self.sv.saved.randomizedCraftData then
			itemUuid = self.sv.saved.randomizedCraftData.itemUuid
			quantity = self.sv.saved.randomizedCraftData.quantity
		else
			local totalWeight = 0
			for _,recipeData in ipairs( recipe.randomCraftList ) do
				totalWeight = totalWeight + recipeData.weight
			end
			local randomValue = math.random() * totalWeight
			for _,recipeData in ipairs( recipe.randomCraftList ) do
				if randomValue <= recipeData.weight then
					itemUuid = recipeData.itemUuid
					quantity = recipeData.quantity
					break
				end
				randomValue = randomValue - recipeData.weight
			end
			self.sv.saved.randomizedCraftData = { itemUuid = itemUuid, quantity = quantity }
			self.storage:save( self.sv.saved )
		end
	else
		itemUuid = recipe.itemUuid
		quantity = recipe.quantity
	end
	return itemUuid, quantity
end

function OreCrusher.server_onFixedUpdate( self, dt )
	if not OreCrusherRecipes then
		return
	end
	if self.sv.isProducing then

		local inputItemUuids = sm.container.itemUuid( self:getInputContainer() )
		local inputItemQuantities = sm.container.quantity( self:getInputContainer() )

		local canCraft = false

		for _,quantity in ipairs( inputItemQuantities ) do
			if quantity > 0 then
				canCraft = true
				break
			end
		end
		if canCraft then
			self.sv.productionProgress = self.sv.productionProgress + dt/self.sv.productionTime
			if self.sv.productionProgress >= 1.0 then
				local effectContainers = {}
				if sm.container.beginTransaction() then
					for index,uid in ipairs( inputItemUuids ) do
						if uid ~= sm.uuid.getNil() then
							local recipe = OreCrusherRecipes[tostring( uid )]
							
							if recipe then

								local itemUuid, quantity = self:sv_getUuidAndQuantity( recipe )

								local objContainer = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, { itemUuid }, { quantity } )
							
								local amount = math.floor( inputItemQuantities[index] / recipe.ingredientList[1].quantity )
								
								local outputContainer
								local pipeEffect = false
								if objContainer then
									pipeEffect = true
									outputContainer = objContainer:getInteractable():getContainer()
								end
								if outputContainer == nil then
									outputContainer = self:getOutputContainer()
								end
			
								sm.container.spend( self.shape:getInteractable():getContainer( 1 ), inputItemUuids[index], inputItemQuantities[index], true )
								if amount > 0 then
									sm.container.collect( outputContainer, itemUuid, quantity * amount, true )
									if pipeEffect then
										if effectContainers[outputContainer.id] == nil then
											effectContainers[outputContainer.id] = { container = objContainer, items = {} }
										end
										effectContainers[outputContainer.id].items[#effectContainers[outputContainer.id].items + 1] = itemUuid
									end
								end
							else
								print( "OreCrusher: No recipe found for item: " .. tostring( uid ) )
								sm.container.spend( self.shape:getInteractable():getContainer( 1 ), inputItemUuids[index], inputItemQuantities[index], true )
							end
						end
					end
				end
				if sm.container.endTransaction() then
					self.sv.productionProgress = 0.0
					self.sv.saved.randomizedCraftData = nil
					self.sv.isProducing = false
					if not IsEmptyTable( effectContainers ) then
						self.network:sendToClients( "cl_n_finishProduction", effectContainers )
					else
						self.network:sendToClients( "cl_n_finishProduction" )
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
		local recipe = OreCrusherRecipes[tostring(inputItemUuids[1])]

		if inputItemUuids[1] == sm.uuid.getNil() then
			self.sv.hasInputItem = false
		else
			self.sv.hasInputItem = true
		end

		-------------------
		--Determine if the output is occupied or available for more
		if recipe == nil then
			self.sv.outputFull = true
		else
			local canCollect = false
			local itemUuid, quantity = self:sv_getUuidAndQuantity( recipe )
			if sm.container.canCollect( self:getOutputContainer(), itemUuid, quantity ) then
				canCollect = true
			end
			if not canCollect then
				local objContainer = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, { itemUuid }, { quantity } )
				if objContainer then
					canCollect = true
				end
			end
			self.sv.outputFull = not canCollect
		end
		-------------------

		if self.sv.hasInputItem and not self.sv.outputFull then
			--Can produce so start production
			if not self.sv.isProducing then
				self.sv.isProducing = true
				self.sv.productionProgress = 0.0
				local params = { isProducing = true}
				self.network:sendToClients("cl_n_setIsProducing", params)
			end
		end
		----Try to collect nearby harvest
		local foundInteractables = {}
		local adjacentShapeIds = {}

		for _, object in ipairs( self.sv.areaTrigger:getContents() ) do
			if type( object ) == "AreaTrigger" then
				local trigger = object
				if sm.exists( trigger ) then
					local userData = trigger:getUserData()
					if userData and userData.resourceCollector then
						local shape = userData.resourceCollector
						--Search shape containers
						if shape:getInteractable() then

							local otherContainerInput = shape:getInteractable():getContainer(1)
							local otherContainerOutput = shape:getInteractable():getContainer(0)
							local otherContainer
							if otherContainerOutput then
								otherContainer = otherContainerOutput
							else
								otherContainer = otherContainerInput
							end
							if otherContainer then
								foundInteractables[#foundInteractables+1] = { interactable = shape:getInteractable(), container = otherContainer }
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
		
		if not self.sv.hasInputItem then
			local foundItem = false
			local foundContainers = {}
			for _,interactableData in ipairs( foundInteractables ) do
				local interactable = interactableData.interactable
				local otherContainer = interactableData.container
				foundContainers[#foundContainers+1] = otherContainer
				local otherItemUuids = sm.container.itemUuid( otherContainer )
				for index, itemUuid in ipairs( otherItemUuids ) do
					if foundItem then
						break
					end
					if itemUuid == ITEMS.obj_resource_drillcasingmixedt1 or itemUuid == ITEMS.obj_resource_drillcasingmixedt3
					 or itemUuid == ITEMS.obj_resource_drillcasingmixedt4 or itemUuid == ITEMS.obj_resource_drillcasingmixedrich then
						foundItem = true
						if sm.container.beginTransaction() then
							--sm.container.spend( otherContainer, itemUuid, 1, true )
							sm.container.setItem( otherContainer, index-1, sm.uuid.getNil(), 0 )
							if interactable.publicData and interactable.publicData.itemContents and interactable.publicData.itemContents[index] ~= nil then
								-- uuid count
								for strUid,count in pairs( interactable.publicData.itemContents[index] ) do
									assert( type( strUid ) == "string" )
									if OreCrusherRecipes[strUid] then
										sm.container.collect( self.shape:getInteractable():getContainer( 1 ), sm.uuid.new( strUid ), count, true )
									else
										print( "OreCrusher: No recipe found for item in gravel casing: "..strUid )
									end
								end
								interactable.publicData.itemContents[index] = nil
							end
							sm.container.endTransaction()
						end
					elseif isAnyOf( itemUuid, g_gravelCollectorHarvests ) then
						foundItem = true
						if sm.container.beginTransaction() then
							sm.container.spend( otherContainer, itemUuid, 1, true )
							sm.container.collect( self.shape:getInteractable():getContainer( 1 ), itemUuid, 1, true )
							sm.container.endTransaction()
						end
					end
				end
				for index, itemUuid in ipairs( otherItemUuids ) do
					if itemUuid == ITEMS.obj_resource_drillcasingmixedt1 or itemUuid == ITEMS.obj_resource_drillcasingmixedt3
					 or itemUuid == ITEMS.obj_resource_drillcasingmixedt4 or itemUuid == ITEMS.obj_resource_drillcasingmixedrich then
						if interactable.publicData.itemContents and interactable.publicData.itemContents[index] ~= nil then
							local autoData = {}
							autoData.selfOutputContainer = self:getOutputContainer()
							autoData.craftTime = 7.0
							autoData.specialCrafting = {}
							autoData.specialCrafting.container = otherContainer
							autoData.specialCrafting.slot = foundItem and index-2 or index-1
							autoData.specialCrafting.productions = {}
							for strUid,count in pairs( interactable.publicData.itemContents[index] ) do
								local autoRecipe = OreCrusherRecipes[strUid]
								if autoRecipe then
									local uid = autoRecipe.itemUuid
									local requiredAmount = autoRecipe.ingredientList[1].quantity
									local multiplier = math.floor( count / requiredAmount )
									local quantity = autoRecipe.quantity * multiplier
									autoData.specialCrafting.productions[#autoData.specialCrafting.productions+1] = { uid = uid, quantity = quantity }
								end
							end
							sm.pipeGraph.setAutomatedTask( self.shape, autoData )
						end
					end
				end

			end
			if #foundContainers > 0 then
				for _, currentRecipe in pairs( OreCrusherRecipes ) do
					local recipeCopy = DeepCopy( currentRecipe )
					recipeCopy.externalContainers = foundContainers
					recipeCopy.selfOutputContainer = self:getOutputContainer()
					sm.pipeGraph.setAutomatedTask( self.shape, recipeCopy )
				end
			end
		end

		if not self.sv.hasInputItem or self.sv.outputFull then
			--Abort any ongoing production because production can't continue
			if self.sv.isProducing then
				self.sv.isProducing = false
				self.sv.productionProgress = 0.0
				local params = { isProducing = false}
				self.network:sendToClients( "cl_n_setIsProducing", params )
			end
		end
	end
end
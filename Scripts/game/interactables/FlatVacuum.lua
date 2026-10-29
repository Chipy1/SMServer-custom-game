dofile( "$SURVIVAL_DATA/Scripts/game/util/Curve.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/pipes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

FlatVacuum = class()
FlatVacuum.poseWeightCount = 1
FlatVacuum.connectionInput = sm.interactable.connectionType.logic
FlatVacuum.maxParentCount = 1
FlatVacuum.maxChildCount = 0

local SuctionDelay = 1.0 * 40
local SuctionStrength = 30

function FlatVacuum.server_onCreate( self )
	self.sv = {}

	-- client table goes to client
	self.sv.client = {}
	self.sv.client.state = PipeState.off
	self.sv.client.showBlockVisualization = false
	
	self.sv.targetUuid = nil
	self.sv.dirtyClientTable = false

	self.sv.fireDelayProgress = 0
	self.sv.canFire = true
	self.sv.collectionTrigger = nil
	self.sv.killTrigger = nil
	self.sv.foundContainer = nil
	self.sv.foundItem = sm.uuid.getNil()
	self.sv.parentActive = false
	self:sv_createTriggers()
	-- public data used to interface with the packing station
	self.interactable:setPublicData( { packingStationTick = 0 } )
end

function FlatVacuum.sv_markClientTableAsDirty( self )
	self.sv.dirtyClientTable = true
end

function FlatVacuum.sv_createTriggers( self )
	local size = sm.vec3.new( 4, 2, 3 )
	local filter = sm.areaTrigger.filter.harvestable + sm.areaTrigger.filter.character
	self.sv.collectionTrigger = sm.areaTrigger.createAttachedBox( self.interactable, size, sm.vec3.new(0.0, -2.0, 0.0), sm.quat.identity(), filter )
	self.sv.killTrigger = sm.areaTrigger.createAttachedBox( self.interactable, sm.vec3.new( 0.5, 1, 0.5 ), sm.vec3.new(0.0, -1.0, 0.0), sm.quat.identity(), sm.areaTrigger.filter.character )
	self.sv.killTrigger:bindOnEnter( "sv_onCharacterEnter" )
end

function FlatVacuum.sv_onCharacterEnter( self, trigger, results )
	local parent = self.shape:getInteractable():getSingleParent()
	if parent and parent.active then
		for _, result in ipairs( results ) do
			if sm.exists( result ) then
				if type( result ) == "Character" then
					if result:getCharacterType() == unit_cablebot then
						sm.event.sendToUnit( result:getUnit(), "sv_onDeath" )
					end
				end
			end
		end
	end
end

function FlatVacuum.server_outgoingReload( self, container, item )
	self.sv.foundContainer, self.sv.foundItem = container, item

	local isBlock = sm.item.isBlock( self.sv.foundItem )
	if self.sv.client.showBlockVisualization ~= isBlock then
		self.sv.client.showBlockVisualization = isBlock
		self:sv_markClientTableAsDirty()
	end

	if self.sv.canFire then
		if ( self.sv.targetUuid ~= nil )  then
			self.sv.fireDelayProgress = SuctionDelay
		end
		self.sv.canFire = false
	end

	if self.sv.foundContainer then
		self.network:sendToClients( "cl_n_onOutgoingReload", { targetContainer = self.sv.foundContainer, item = self.sv.foundItem } )
	end
end

function FlatVacuum.server_onFixedUpdate( self )

	local function setVacuumState( state, containerShape )
		if self.sv.client.state ~= state then
			self.sv.client.state = state
			self.sv.foundContainer = containerShape
			self:sv_markClientTableAsDirty()
		end
	end

	-- Update fire delay progress
	if not self.sv.canFire then
		self.sv.fireDelayProgress = self.sv.fireDelayProgress - 1
		if self.sv.fireDelayProgress <= 0 then
			if self.sv.targetUuid ~= nil then
				self.sv.fireDelayProgress = SuctionDelay
			end
			self.sv.canFire = true
		end
	end

	self.sv.targetUuid = nil

	if #sm.pipeGraph.getOutputContainers( self.shape ) > 0 then

		local incomingObjects = {}
		local characterInZone = {}
		local areaContent = self.sv.collectionTrigger:getContents()

		for _, result in ipairs(  areaContent ) do
			if sm.exists( result ) then
				if type( result ) == "Harvestable" then
					local pubData = result.publicData
					if not pubData or not pubData.harvested then
						if pubData and pubData.vacuumable then
							local container = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, { pubData.uuid }, { pubData.quantity } )
							if container then
								table.insert( incomingObjects, { container = container, harvestable = result, uuid = pubData.uuid, amount = pubData.quantity } )
							end
						end
					end
				elseif type( result ) == "Character" then
					if result:getCharacterType() == unit_cablebot then
						characterInZone[#characterInZone+1] = result
					end
				end
			end
		end

		-- If active
		local parent = self.shape:getInteractable():getSingleParent()
		if parent and parent.active and self.sv.canFire then
			for _, character in ipairs( characterInZone ) do
				local toVecNoZ = ( self.shape.worldPosition - character.worldPosition )
				toVecNoZ.z = 0
				local toVec = toVecNoZ:safeNormalize( sm.vec3.new( 0, 0, 0 ) )
				toVec.z = 0
				sm.physics.applyImpulse( character, toVec * SuctionStrength )
			end
			for _, incomingObject in ipairs( incomingObjects ) do
				if incomingObject.container then
					sm.container.beginTransaction()

					sm.container.collect( incomingObject.container:getInteractable():getContainer(), incomingObject.uuid, incomingObject.amount, true)
					if incomingObject.seedIncomingObj then
						sm.container.collect( incomingObject.seedIncomingObj.container:getInteractable():getContainer(), incomingObject.seedIncomingObj.uuid, incomingObject.seedIncomingObj.amount, true)
					end

					if sm.container.endTransaction() then
						self.network:sendToClients( "cl_n_onIncomingFire", { targetContainer = incomingObject.container, item = incomingObject.uuid } )
						if incomingObject.shape then
							incomingObject.shape:destroyShape()
						end
						if incomingObject.harvestable then
							local pubData = incomingObject.harvestable.publicData
							if pubData then
								pubData.harvested = true
							end
							sm.harvestable.destroy( incomingObject.harvestable )
						end
					end
				else
					local targetContainer = self.sv.foundContainer
					if targetContainer == nil then
						local containers = sm.pipeGraph.getInputContainers( self.shape )
						if #containers > 0 then
							targetContainer = containers[1]
						end
					end
					self.network:sendToClients( "cl_n_onError", { targetContainer = targetContainer } )
				end
			end

			if #incomingObjects == 0 then
				local targetContainer = self.sv.foundContainer
					if targetContainer == nil then
						local containers = sm.pipeGraph.getInputContainers( self.shape )
						if #containers > 0 then
							targetContainer = containers[1]
						end
					end
				self.network:sendToClients( "cl_n_onError", { targetContainer = targetContainer } )
			end
			self.sv.canFire = false
		end

		-- Synch visual feedback
		if #incomingObjects > 0 then
			-- Highlight the path furthest container or target container
			local containers = sm.pipeGraph.getInputContainers( self.shape )
			local targetContainer = sm.pipeGraph.getContainerShapeToCollectTo( self.shape, { incomingObjects[1].uuid }, { incomingObjects[1].amount } )
			if targetContainer == nil then
				if #containers > 0 then
					targetContainer = containers[#containers]
				end
			end
			setVacuumState( PipeState.valid, targetContainer )
		else
			setVacuumState( PipeState.connected )
		end
	end

	-- Client table dirty
	if self.sv.dirtyClientTable then
		local targetContainer = self.sv.foundContainer
		if targetContainer == nil then
			local containers = sm.pipeGraph.getInputContainers( self.shape )
			if #containers > 0 then
				targetContainer = containers[1]
			end
		end
		self.network:setClientData( { targetContainer = targetContainer, state = self.sv.client.state, showBlockVisualization = self.sv.client.showBlockVisualization } )
		self.sv.dirtyClientTable = false
	end

end

-- Client
function FlatVacuum.client_onCreate( self )
	self.cl = {}

	-- Update from onClientDataUpdate
	self.cl.state = PipeState.off
	self.cl.showBlockVisualization = false

	self.cl.overrideUvFrameIndexTask = nil
	self.cl.poseAnimTask = nil
	self.cl.vacuumEffect = nil

	self.cl.previousPipeState = PipeState.off
	self.cl.previousPipeGlow = 1.0
	self.cl.overrideState = PipeState.off
	self.cl.targetContainer = nil
	self.cl.previousTargetContainer = nil

	self.cl.pipeEffectPlayer = PipeEffectPlayer()
	self.cl.pipeEffectPlayer:onCreate()
end

function FlatVacuum.client_onClientDataUpdate( self, clientData )
	assert( clientData.state )
	self.cl.state = clientData.state
	self.cl.targetContainer = clientData.targetContainer
	self.cl.showBlockVisualization = clientData.showBlockVisualization
end

function FlatVacuum.client_onUpdate( self, dt )

	-- Update pose anims
	self:cl_updatePoseAnims( dt )

	-- Update Uv Index frames
	self:cl_updateUvIndexFrames( dt )

	-- Update effects through pipes
	self.cl.pipeEffectPlayer:update( dt )
end

-- Events

function FlatVacuum.cl_n_onOutgoingReload( self, data )

	local path = sm.pipeGraph.getContainerPath( self.shape, data.targetContainer )
	local reversed = {}

	for _, shape in reverse_ipairs( path ) do
		table.insert( reversed, shape )
	end
	table.insert( reversed, #reversed+1, self.shape )

	self.cl.pipeEffectPlayer:pushShapeEffectTask( reversed, data.item )
	self.cl.targetContainer = data.targetContainer
	self.cl.overrideState = PipeState.valid
	self.cl.overrideUvFrameIndexTask = { state = PipeState.valid, progress = 0 }
end

function FlatVacuum.cl_n_onIncomingFire( self, data )
	local path = sm.pipeGraph.getContainerPath( self.shape, data.targetContainer )
	table.insert( path, 1, self.shape )

	self.cl.pipeEffectPlayer:pushShapeEffectTask( path, data.item )
	self.cl.targetContainer = data.targetContainer
	self.cl.overrideState = PipeState.valid
	self.cl.overrideUvFrameIndexTask = { state = PipeState.valid, progress = 0 }
	self:cl_setPoseAnimTask( "incomingFire" )

	self.cl.vacuumEffect = sm.effect.createEffect( "Vacuumpipe - Suction", self.interactable )
	self.cl.vacuumEffect:setOffsetRotation( sm.quat.angleAxis( math.pi*0.5, sm.vec3.new( 1, 0, 0 ) ) )
	self.cl.vacuumEffect:start()
end

function FlatVacuum.cl_n_onError( self, data )
	self.cl.targetContainer = data.targetContainer
	self.cl.overrideState = PipeState.invalid
	self.cl.overrideUvFrameIndexTask = { state = PipeState.invalid, progress = 0 }
end

-- State sets

function FlatVacuum.cl_setPoseAnimTask( self, name )
	self.cl.poseAnimTask = { name = name, progress = 0 }
end

-- Updates

PoseCurves = {}
PoseCurves["outgoingFire"] = Curve()
PoseCurves["outgoingFire"]:init({{v=0.5, t=0.0},{v=1.0, t=0.1},{v=0.5, t=0.2},{v=0.0, t=0.3},{v=0.5, t=0.6}})

PoseCurves["incomingFire"] = Curve()
PoseCurves["incomingFire"]:init({{v=0.5, t=0.0},{v=0.0, t=0.1},{v=0.5, t=0.2},{v=1.0, t=0.3},{v=0.5, t=0.6}})

function FlatVacuum.cl_updatePoseAnims( self, dt )

	if self.cl.poseAnimTask then

		self.cl.poseAnimTask.progress = self.cl.poseAnimTask.progress + dt

		local curve = PoseCurves[self.cl.poseAnimTask.name]
		if curve then
			self.shape:getInteractable():setPoseWeight( 0, curve:getValue( self.cl.poseAnimTask.progress ) )

			if self.cl.poseAnimTask.progress > curve:duration() then
				self.cl.poseAnimTask = nil
			end
		else
			self.cl.poseAnimTask = nil
		end
	end

end

local GlowCurve = Curve()
GlowCurve:init({{v=1.0, t=0.0}, {v=0.5, t=0.05}, {v=0.0, t=0.1}, {v=0.5, t=0.3}, {v=1.0, t=0.4}, {v=0.5, t=0.5}, {v=0.0, t=0.7}, {v=0.5, t=0.75}, {v=1.0, t=0.8}})

function FlatVacuum.cl_updateUvIndexFrames( self, dt )

	local glowMultiplier = 1.0

	-- Events allow for overriding the uv index frames, time it out
	if self.cl.overrideUvFrameIndexTask then
		self.cl.overrideUvFrameIndexTask.progress = self.cl.overrideUvFrameIndexTask.progress + dt

		glowMultiplier = GlowCurve:getValue( self.cl.overrideUvFrameIndexTask.progress )

		if self.cl.overrideUvFrameIndexTask.progress > 0.1 then

			self.cl.overrideUvFrameIndexTask.change = true
		end

		if self.cl.overrideUvFrameIndexTask.progress > 0.7 then

			self.cl.overrideUvFrameIndexTask.change = false
		end

		if self.cl.overrideUvFrameIndexTask.progress > GlowCurve:duration() then

			self.cl.overrideUvFrameIndexTask = nil
		end
	end

	-- Light up vacuum
	local state = self.cl.state
	if self.cl.overrideUvFrameIndexTask and self.cl.overrideUvFrameIndexTask.change == true then
		state = self.cl.overrideUvFrameIndexTask.state
	end

	VacuumFrameIndexTable = {
		[PipeState.off] = 0,
		[PipeState.invalid] = 1,
		[PipeState.connected] = 3,
		[PipeState.valid] = 5
	}
	assert( state > 0 and state <= 4 )
	local vacuumFrameIndex = VacuumFrameIndexTable[state]
	self.interactable:setUvFrameIndex( vacuumFrameIndex )
	if self.cl.overrideUvFrameIndexTask then
		self.interactable:setGlowMultiplier( glowMultiplier )
	else
		self.interactable:setGlowMultiplier( 1.0 )
	end

	if self.cl.targetContainer then
		if self.cl.previousPipeState ~= state or self.cl.previousPipeGlow ~= glowMultiplier then
			self.cl.previousPipeState = state
			self.cl.previousPipeGlow = glowMultiplier
			self.interactable.clientPublicData = { lightingOverride = { state = state, glow = glowMultiplier } }
			if self.cl.previousTargetContainer == nil then
				self.cl.previousTargetContainer = self.cl.targetContainer
			end
			if not sm.exists( self.cl.previousTargetContainer ) or self.cl.previousTargetContainer ~= self.cl.targetContainer then
				self.cl.previousTargetContainer = self.cl.targetContainer
				sm.pipeGraph.releaseLightingOverride( self.shape )
			end
			if self.cl.targetContainer then
				sm.pipeGraph.requestLightingOverride( self.shape, self.cl.targetContainer, state-1, glowMultiplier )
			end
		end
	end
end

function FlatVacuum.client_onDestroy( self )
	if self.cl.pipeEffectPlayer then
		self.cl.pipeEffectPlayer:onDestroy()
	end
end
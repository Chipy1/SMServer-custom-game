dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicBase.lua" )

dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

dofile( "$SURVIVAL_DATA/Scripts/kinematic_util.lua" )

dofile( "$GAME_DATA/Scripts/game/managers/TileStorageManager.lua" )

Kinematic = class( KinematicBase )

function Kinematic.getTrackData( self, instance, trackName, tracks )
	if instance.trackDataList == nil or instance.trackSettings == nil then
		local trackDataList, trackSettings = EvaluateNodes( tracks[trackName], self.harvestable.initialPosition, self.harvestable.initialRotation, self.harvestable:getScale() )
		instance.trackDataList = trackDataList
		instance.trackSettings = trackSettings
	end
	return instance.trackDataList, instance.trackSettings
end

function Kinematic.server_onCreate( self )
	self.sv = self.sv or {}
	self.sv.unlocked = true

	self.sv.trackInstances = {}
	self.sv.delayedEvents = {}

	self.sv.transform = {}
	self.sv.transform.worldPosition = self.harvestable.worldPosition
	self.sv.transform.worldRotation = self.harvestable.worldRotation

	if self.sv.parentedKinematic then
		self.harvestable.publicData = self.harvestable.publicData or {}
		self.harvestable.publicData.transform = self.sv.transform
	end

	if self.params.track then
		for trackName, trackParamData in pairs( self.params.track ) do
			self.sv.trackInstances[trackName] = {}
			local instance = self.sv.trackInstances[trackName]
				
			instance.updateData = {}
			instance.updateData.trackIndex = 1
			instance.updateData.playForward = true
			instance.updateData.moving = false
			instance.updateData.weight = 1
	
			instance.progressData = { segmentIndex = 1, segmentProgress = 0.0 }
		end
	end
	

	if g_tileStorageManager then
		self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )

		if self.params and self.params.lockTag and self.params.lockTag ~= "" then
			self.sv.unlocked = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.lockTag ) == true
		end

		local pendingActivation = nil
		if self.params and self.params.eventListen and self.params.eventListen ~= "" then
			KinematicManager.Sv_RegisterToEvent( self.harvestable, self.sv.tileStorageKey, self.params.eventListen, self.tags )
			pendingActivation = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_EVENTTRIGGER_TABLE, self.params.eventListen )
		end
		
		self.sv.storageKey = nil
		if self.params and self.params.storageTag and self.params.storageTag ~= "" then
			-- needed for drillbot kinematics. they are created from script and have salted hashes but but are reloaded from tilestorage as though they were from a cell.
			self.sv.storageKey = self.params.storageTag
		else
			
			self.sv.storageKey = self.harvestable:getInitialHash()



		end

		local storage = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.storageKey )
		if storage and storage.tracks then
			self.sv.readFromStorage = true
			for trackName, storageUpdateData in pairs( storage.tracks ) do
				local trackInstance = self.sv.trackInstances[trackName]
				if trackInstance then
					if storageUpdateData.moving ~= nil then trackInstance.updateData.moving = storageUpdateData.moving end
					if storageUpdateData.playForward ~= nil then trackInstance.updateData.playForward = storageUpdateData.playForward end
					if storageUpdateData.trackIndex ~= nil then trackInstance.updateData.trackIndex = storageUpdateData.trackIndex end
					if storageUpdateData.weight ~= nil then trackInstance.updateData.weight = storageUpdateData.weight end
					if storageUpdateData.tick ~= nil then
						local tickDiff = sm.game.getCurrentTick() - ( storage.unloadTick or sm.game.getCurrentTick() )
						trackInstance.updateData.tick = storageUpdateData.tick + tickDiff
					end
					if storageUpdateData.lastTransform ~= nil then trackInstance.updateData.lastTransform = storageUpdateData.lastTransform end
					if storageUpdateData.lastSegmentData then
						trackInstance.progressData = storageUpdateData.lastSegmentData
					end
					trackInstance.startupDone = false

				else
					sm.log.error( "Kinematic loaded from storage with unknown track" )
				end
			end
		end

		if pendingActivation then
			local lastSaveTick = storage and storage.unloadTick
			if lastSaveTick == nil or pendingActivation.tick > lastSaveTick then
				local trackName = pendingActivation.trackName or "track"
				local trackInstance = self.sv.trackInstances[trackName]
				if trackInstance then
					trackInstance.updateData.moving = true
					trackInstance.updateData.tick = pendingActivation.tick or sm.game.getServerTick()
				end
			end
		end
	end


	self.harvestable.publicData = self.harvestable.publicData or {}
	self.harvestable.publicData.moving = self:sv_isMoving()
	self.network:setClientData( { tracks = self.params.track }, 1 )
	self.network:setClientData( self:sv_getUpdateData(), 2 )

	self:sv_store()
end

function Kinematic.sv_getUpdateData( self )
	local updateData = {}
	for trackName, instance in pairs( self.sv.trackInstances ) do
		updateData[trackName] = instance.updateData
	end

	return updateData
end

function Kinematic.sv_isMoving( self )
	for _, instance in pairs( self.sv.trackInstances ) do
		if instance.updateData.moving == true then
			return true
		end
	end
	return false
end

function Kinematic.server_onDestroy( self )
	if g_tileStorageManager then
		if self.params and self.params.eventListen and self.params.eventListen ~= "" then
			KinematicManager.Sv_UnregisterFromEvent( self.harvestable, self.sv.tileStorageKey, self.params.eventListen )
		end
	end
end

function Kinematic.sv_e_destroy( self )
	if not self.sv.destroyed then
		self.harvestable:destroy()
		self.sv.destroyed = true
	end
end

function Kinematic.server_onUnload( self )
	self:sv_store()
end

function Kinematic.sv_store( self )
	if g_tileStorageManager and self.params and ( ( self.params.storageTag and self.params.storageTag ~= "" ) or ( self.params.saved == nil or self.params.saved ) ) then
		local storage = { tracks = {} }
		for trackName, instance in pairs( self.sv.trackInstances ) do
			storage.tracks[trackName] = instance.updateData
		end
		storage.position = self.sv.transform.worldPosition
		storage.rotation = self.sv.transform.worldRotation
		storage.unloadTick = sm.game.getCurrentTick()
		TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.storageKey, storage )
	end
end

function Kinematic.sv_triggerTrackEvent( self, trackNode, previousPlayForward, nodeIndex, fromActivation, onlyPersistent )
	if trackNode.event or trackNode.attachedEffects or trackNode.deactivateEffects or trackNode.effects then
		local hasEvent = false
		local attachedEffects = nil
		local deactivateEffects = nil
		local effects = nil

		local directional = trackNode.forwardsEvent or trackNode.backwardsEvent
		local forward = previousPlayForward and trackNode.forwardsEvent
		local backward = not previousPlayForward and trackNode.backwardsEvent
		if ( directional and ( forward or backward ) ) or not directional then
			hasEvent = trackNode.event ~= nil
			attachedEffects = shallowcopy( trackNode.attachedEffects )
			effects = shallowcopy( trackNode.effects )
			deactivateEffects = trackNode.deactivateEffects
		end
		if onlyPersistent then
			for index,effectData in reverse_ipairs( attachedEffects or {} ) do
				if not effectData.persistentActivation then
					attachedEffects[index] = nil
				end
			end
		end
		
		if attachedEffects ~= nil and not IsEmptyTable( attachedEffects ) or effects ~= nil and not IsEmptyTable( effects ) then
			if not trackNode.stop or ( trackNode.stop and fromActivation ) then
				self.network:sendToClients( "cl_n_manageAttachedEffects", { attachedEffects = attachedEffects, nodeIndex = nodeIndex, effects = effects } )
			end
		end

		if onlyPersistent then
			return
		end

		if hasEvent then
			if trackNode.eventDelay then
				self.sv.delayedEvents[#self.sv.delayedEvents+1] = { event = trackNode.event, activationTick = sm.game.getCurrentTick() + math.floor( trackNode.eventDelay * 40 ) }
			else
				local position = self.harvestable.initialPosition
				EffectManager.Sv_ActivateEventEffect( self.harvestable:getWorld(), trackNode.event, position )
			end
		end
		
		if deactivateEffects then
			self.network:sendToClients( "cl_n_manageAttachedEffects", { deactivate = deactivateEffects } )
		end

		if trackNode.kinematicActivations then
			for _,kinematicData in ipairs( trackNode.kinematicActivations ) do
				KinematicManager.Sv_Activate( self.sv.tileStorageKey, kinematicData.kinematicEventTrigger, { track = kinematicData.trackName } ) --triggering kinematics with activation tag matching event
			end
		end
	end
	if trackNode.stop then
		self.network:sendToClients( "cl_n_stopMovementEffect" )
	end
end

function Kinematic.server_onFixedUpdate( self, timeStep )
	if self.sv == nil then
		return
	end

	if not self.sv.unlocked then
		if g_tileStorageManager then
			if self.params and self.params.lockTag and self.params.lockTag ~= "" then
				self.sv.unlocked = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.lockTag ) == true
			end
		end
		if not self.sv.unlocked then return end
	end

	local finalTransform = nil
	local wasMoving = self:sv_isMoving()

	-- when only 1 track is active we can rely on our last position and avoid updating if we are not moving. 
	-- but when multiple tracks are active one can be stationary in some position and one can be moving, both must be evaluated
	local activeTracks = 0
	for trackName, instance in pairs( self.sv.trackInstances ) do
		if instance.updateData.weight > 0 then
			activeTracks = activeTracks + 1
		end
	end

	for trackName, instance in pairs( self.sv.trackInstances ) do
		if instance.startupDone == false then
			if instance.progressData then
				local lastNode = instance.progressData.segmentIndex
				if instance.updateData.playForward then
					lastNode = lastNode + math.floor( instance.progressData.segmentProgress )
				else
					lastNode = lastNode + math.ceil( instance.progressData.segmentProgress )
				end
				self:getTrackData( instance, trackName, self.params.track )
				if lastNode > 1 then
					if lastNode == #instance.trackDataList[instance.updateData.trackIndex].nodes then
						for i = 1, lastNode do
							local trackdata = instance.trackDataList[instance.updateData.trackIndex]
							if trackdata and trackdata.nodes[i] then
								self:sv_triggerTrackEvent( trackdata.nodes[i], not instance.updateData.playForward, i, false, true )
							end
						end
					else
						local from = instance.updateData.playForward and 1 or #instance.trackDataList[instance.updateData.trackIndex].nodes
						local direction = instance.updateData.playForward and 1 or -1
	
						if instance.updateData.playForward then
							for i = from, lastNode, direction do
								local trackdata = instance.trackDataList[instance.updateData.trackIndex]
								if trackdata and trackdata.nodes[i] then
									self:sv_triggerTrackEvent( trackdata.nodes[i], instance.updateData.playForward, i, false, true )
								end
							end
						end
					end
				elseif lastNode == 1 and instance.updateData.playForward then
					if not IsEmptyTable( instance.trackDataList ) then
						for i = #instance.trackDataList[instance.updateData.trackIndex].nodes, 1, -1 do
							local trackdata = instance.trackDataList[instance.updateData.trackIndex]
							if trackdata and trackdata.nodes[i] then
								self:sv_triggerTrackEvent( trackdata.nodes[i], not instance.updateData.playForward, i, false, true )
							end
						end
					end
				end
			end
			instance.startupDone = true
		end

		if instance.updateData.moving then
			local previousProgressData = {}
			previousProgressData.segmentIndex = instance.progressData.segmentIndex
			previousProgressData.segmentProgress = instance.progressData.segmentProgress
			local previousPlayForward = instance.updateData.playForward
			local transform

			self:getTrackData( instance, trackName, self.params.track )
			instance.updateData, instance.progressData, transform = KinematicTrackUpdate( instance.trackDataList, instance.trackSettings, instance.updateData )
			if transform then
				finalTransform = ApplyTransform( finalTransform, transform, instance.updateData.weight, self.harvestable.initialPosition, self.harvestable.initialRotation )
				instance.updateData.lastTransform = {
					worldPosition = sm.vec3.new( transform.worldPosition ),
					worldRotation = sm.quat.new( transform.worldRotation )
				}
			end

			-- Trigger events when traversing nodes
			if instance.updateData.moving then
				if instance.progressData.segmentIndex ~= previousProgressData.segmentIndex then
					-- Moved to a new node
					local trackIndex = instance.updateData.trackIndex
					local nodeIndex = instance.progressData.segmentIndex
					if not instance.updateData.playForward then
						nodeIndex = nodeIndex + 1
					end
					instance.updateData.lastSegmentData = instance.progressData
					local trackdata = instance.trackDataList[trackIndex]
					self:sv_triggerTrackEvent( trackdata.nodes[nodeIndex], previousPlayForward, nodeIndex )
				end
			else
				-- Catch the previous node if looping around
				if instance.trackSettings.loop then
					if instance.updateData.playForward then
						if instance.updateData.trackIndex == 1 and not IsEmptyTable( instance.trackDataList ) then
							local lastTrackData = instance.trackDataList[#instance.trackDataList]
							self:sv_triggerTrackEvent( lastTrackData.nodes[#lastTrackData.nodes], previousPlayForward, #lastTrackData.nodes )
						end
					else
						if instance.updateData.trackIndex == #instance.trackDataList then
							local firstTrackData = instance.trackDataList[1]
							if firstTrackData then
								self:sv_triggerTrackEvent( firstTrackData.nodes[1], previousPlayForward, 1 )
							end
						end
					end
				end

				-- Stopped at a new node in the next track
				local trackIndex = instance.updateData.trackIndex
				local nodeIndex = instance.progressData.segmentIndex
				if not instance.updateData.playForward then
					nodeIndex = nodeIndex + 1
				end
				local trackdata = instance.trackDataList[trackIndex]
				instance.updateData.lastSegmentData = instance.progressData
				if trackdata then
					self:sv_triggerTrackEvent( trackdata.nodes[nodeIndex], previousPlayForward, nodeIndex )
				end
			end
		elseif activeTracks > 1 and instance.updateData.weight > 0 then
			-- in this case this track is not moving but we want to apply our last transform anyway, because other active tracks will be applying theirs.
			local transform = instance.updateData.lastTransform
			if transform then
				finalTransform = ApplyTransform( finalTransform, transform, instance.updateData.weight, self.harvestable.initialPosition, self.harvestable.initialRotation )
			end
		end

		if not instance.updateData.moving and instance.updateData.weight > 0 then
			-- Start moving if not commanded to wait
			self:getTrackData( instance, trackName, self.params.track )
			local trackData = instance.trackDataList[instance.updateData.trackIndex]
			if trackData and trackData.nodes and #trackData.nodes >= 1 then
				local requiresInput = ( instance.updateData.playForward and trackData.nodes[1].stop ) or ( not instance.updateData.playForward and trackData.nodes[#trackData.nodes].stop )
				if not requiresInput and instance.trackSettings.loop then
					-- Check the previous node for stop events if looping around
					if instance.updateData.playForward then
						if instance.updateData.trackIndex == 1 then
							local lastTrackData = instance.trackDataList[#instance.trackDataList]
							local lastNodeStop = lastTrackData.nodes[#lastTrackData.nodes].stop
							requiresInput = lastNodeStop
						end
					else
						if instance.updateData.trackIndex == #instance.trackDataList then
							local firstTrackData = instance.trackDataList[1]
							local firstNodeStop = firstTrackData.nodes[1].stop
							requiresInput = firstNodeStop
						end
					end
				end
				if not requiresInput then
					self:sv_activate( nil, trackName )
					self.sv.synchUpdateData = true
				end
			end
		end
	end

	if finalTransform then
		if not self.sv.parentedKinematic then
			self.harvestable:setPosition( finalTransform.worldPosition )
			self.harvestable:setRotation( finalTransform.worldRotation )
		else
			self.harvestable.publicData = self.harvestable.publicData or {}
			self.harvestable.publicData.transform = self.harvestable.publicData.transform or {}
			self.harvestable.publicData.transform.worldPosition = finalTransform.worldPosition
			self.harvestable.publicData.transform.worldRotation = finalTransform.worldRotation
		end
		self.sv.transform.worldPosition = finalTransform.worldPosition
		self.sv.transform.worldRotation = finalTransform.worldRotation
	end

	-- Synch stopped kinematic
	local isMoving = self:sv_isMoving()
	if wasMoving and not isMoving then
		self.harvestable.publicData = self.harvestable.publicData or {}
		self.harvestable.publicData.moving = false
		self.sv.synchUpdateData = true
	end

	if self.sv.synchUpdateData then
		self.network:setClientData( self:sv_getUpdateData(), 2 )
		self:sv_store()
		self.sv.synchUpdateData = false
	end

	if not IsEmptyTable( self.sv.delayedEvents ) then
		local finishedEventIndexes = {}
		for i,eventData in ipairs( self.sv.delayedEvents ) do
			if eventData.activationTick <= sm.game.getCurrentTick() then
				local position = self.harvestable.initialPosition
				EffectManager.Sv_ActivateEventEffect( self.harvestable:getWorld(), eventData.event, position )
				finishedEventIndexes[#finishedEventIndexes+1] = i
			end
		end
		for _, index in reverse_ipairs( finishedEventIndexes ) do
			table.remove( self.sv.delayedEvents, index )
		end
	end
end

function Kinematic.sv_e_setTrackWeights( self, args )
	self:sv_setTrackWeights( args )
end

function Kinematic.sv_e_setTrackWeight( self, args )
	self:sv_setTrackWeight( args.trackName, args.weight )
end

function Kinematic.sv_setTrackWeights( self, args )
	for _, track in ipairs( args ) do
		self:sv_setTrackWeight( track.trackName, track.weight )
	end
end

function Kinematic.sv_setTrackWeight( self, trackName, weight )
	local instance = self.sv.trackInstances[trackName]
	if instance then
		instance.updateData.weight = weight
		self.sv.synchUpdateData = true
	else
		sm.log.error( "Tried to set track weight of unknown track:", trackName )
	end
end

function Kinematic.sv_activate( self, activationTick, trackName )
	if not self.sv.unlocked then return end

	trackName = trackName or "track"

	if IsEmptyTable( self.sv.trackInstances ) then
		return
	end

	local instance = self.sv.trackInstances[trackName]
	if instance then
		self:getTrackData( instance, trackName, self.params.track )
		if instance.trackDataList and not instance.updateData.moving then
			local nodeIndex = instance.progressData.segmentIndex
			local trackDataNodeIndex = nodeIndex
			local trackdata = instance.trackDataList[instance.updateData.trackIndex]
			if not instance.updateData.playForward then
				nodeIndex = math.min( nodeIndex + 1, #trackdata.nodes )
				trackDataNodeIndex = nodeIndex
			elseif instance.updateData.trackIndex ~= nil then
				nodeIndex = instance.updateData.trackIndex
			end
			if trackdata then
				self:sv_triggerTrackEvent( trackdata.nodes[trackDataNodeIndex], instance.updateData.playForward, nodeIndex, true )
			end
			instance.updateData.moving = true
			instance.updateData.tick = activationTick or sm.game.getServerTick()

			self.sv.synchUpdateData = true
			self.network:sendToClients( "cl_n_activateMovementEffect" )
			self.harvestable.publicData = self.harvestable.publicData or {}
			self.harvestable.publicData.moving = self:sv_isMoving()

		elseif not instance.trackDataList then
			sm.log.error( "Kinematic trackinstance has no track" )
		end
	else
		sm.log.error( "Tried to activate kinematic with unknown track named ", trackName )
	end
end

function Kinematic.sv_e_resetTrack( self, args )
	if args then
		self:sv_resetTrack( args.trackName, args.toBack )
	else
		self:sv_resetTrack()
	end
end

function Kinematic.sv_resetTrack( self, trackName, toBack )
	if not self.sv.unlocked then 
		return 
	end

	trackName = trackName or "track"
	local instance = self.sv.trackInstances[trackName]
	if not instance or instance.updateData.moving then 
		return 
	end

	self:getTrackData( instance, trackName, self.params.track )
	if not instance.trackDataList then 
		return 
	end

	if toBack then

		local lastIndex = #instance.trackDataList
		local lastNodeCount = #instance.trackDataList[lastIndex].nodes
		if instance.updateData.trackIndex == lastIndex and not instance.updateData.playForward and
				instance.progressData.segmentIndex == lastNodeCount - 1 and instance.progressData.segmentProgress == 1.0 then
			return
		end
		instance.updateData.trackIndex = lastIndex
		instance.updateData.playForward = false
		instance.progressData = { segmentIndex = lastNodeCount - 1, segmentProgress = 1.0 }
	else
		if instance.updateData.trackIndex == 1 and instance.updateData.playForward and instance.progressData.segmentIndex == 1 and instance.progressData.segmentProgress == 0.0 then
			return
		end
		instance.updateData.trackIndex = 1
		instance.updateData.playForward = true
		instance.progressData = { segmentIndex = 1, segmentProgress = 0.0 }
	end

	local updateData = { moving = true, playForward = instance.updateData.playForward, trackIndex = instance.updateData.trackIndex, tick = sm.game.getServerTick(), weight = instance.updateData.weight }
	local _, _, transform = KinematicTrackUpdate( instance.trackDataList, instance.trackSettings, updateData )
	if transform then
		local final = ApplyTransform( nil, transform, instance.updateData.weight, self.harvestable.initialPosition, self.harvestable.initialRotation )
		if final then
			if not self.sv.parentedKinematic then
				self.harvestable:setPosition( final.worldPosition )
				self.harvestable:setRotation( final.worldRotation )
			else
				self.harvestable.publicData = self.harvestable.publicData or {}
				self.harvestable.publicData.transform = { worldPosition = final.worldPosition, worldRotation = final.worldRotation }
			end
			self.sv.transform.worldPosition = final.worldPosition
			self.sv.transform.worldRotation = final.worldRotation
		end
		instance.updateData.lastTransform = { worldPosition = sm.vec3.new( transform.worldPosition ), worldRotation = sm.quat.new( transform.worldRotation ) }
	end

	self.sv.synchUpdateData = true
	self.harvestable.publicData = self.harvestable.publicData or {}
	self.harvestable.publicData.moving = self:sv_isMoving()
end

function Kinematic.sv_e_activate( self, args )
	if args then
		self:sv_activate( args.tick, args.trackName )
	else
		self:sv_activate()
	end
end

function Kinematic.client_onCreate( self )
	KinematicBase.client_onCreate( self )

	self.cl = self.cl or {}

	self.cl.trackInstances = self.cl.trackInstances or {}

	self.cl.activatedAttachedEffects = {}
	self.cl.effectIdentifierLookups = {}

	if self.data.kinematic	then
		self.cl.maxSpeed = self.data.kinematic.maxSpeed or 70.0
	else
		self.cl.maxSpeed = 70.0
	end
	self.cl.previousPosition = self.harvestable.worldPosition

	if not sm.isHost then
		if self.cl.parentedKinematic then
			self.harvestable.clientPublicData = self.harvestable.clientPublicData or {}
			self.harvestable.clientPublicData.transform = self.harvestable.clientPublicData.transform or {}
			self.harvestable.clientPublicData.transform.worldPosition = self.harvestable.initialPosition
			self.harvestable.clientPublicData.transform.worldRotation = self.harvestable.initialRotation
		end
	end


	if self.data and self.data.kinematic then
		if self.data.kinematic.movementEffect then
			self.cl.movementEffect = sm.effect.createEffect( self.data.kinematic.movementEffect, self.harvestable )
		end
		if self.data.kinematic.permanentEffects then
			self.cl.permanentEffects = {}
			for i, value in ipairs( self.data.kinematic.permanentEffects ) do
				local createdEffect = sm.effect.createEffect( value.effectName, self.harvestable )
				if createdEffect then
					if value.offsetPosition then
						createdEffect:setOffsetPosition( value.offsetPosition * self.harvestable:getScale() )
					end
					if value.offsetRotation then
						createdEffect:setOffsetRotation( sm.quat.fromEuler( value.offsetRotation ) )
					end
					createdEffect:start()
					
					-- need to store them to prevent garbage collection
					self.cl.permanentEffects[i] = createdEffect
				end
			end
		end
	end
end

function Kinematic.client_onDestroy( self )
	if self.cl.movementEffect then
		self.cl.movementEffect:destroy()
	end
	for _,value in pairs( self.cl.activatedAttachedEffects ) do
		for _, effect in ipairs( value ) do
			effect:destroy()
		end
	end	
	if self.cl.permanentEffects and not IsEmptyTable( self.cl.permanentEffects ) then
		for _, effect in ipairs( self.cl.permanentEffects ) do
			effect:destroy()
		end
	end
end

function Kinematic.cl_n_activateMovementEffect( self )
	if self.cl.movementEffect and ( not self.cl.movementEffect:isPlaying() or self.cl.movementEffect:isBreakSustaining() ) then
		self.cl.movementEffect:start()
	end
end

function Kinematic.cl_n_stopMovementEffect( self )
	if self.cl.movementEffect then
		self.cl.movementEffect:stopBreakSustain()
	end
end

function Kinematic.client_onClientDataUpdate( self, clientData, channel )
	

	if self.cl.trackInstances == nil then
		self.cl.trackInstances = {}
	end

	if channel == 1 then
		if clientData.tracks then
			self.cl.trackdata = clientData.tracks
			for trackName, trackParamData in pairs( clientData.tracks ) do
				self.cl.trackInstances[trackName] = self.cl.trackInstances[trackName] or {}
				local instance = self.cl.trackInstances[trackName]

				if instance.updateData == nil then
					instance.updateData = {}
					instance.updateData.trackIndex = 1
					instance.updateData.playForward = true
					instance.updateData.moving = false
					instance.updateData.weight = 1
				end
			end
		end
		
	elseif channel == 2 then
		
		if not sm.isHost then
			local finalTransform = nil
			
			for trackName, updateData in pairs( clientData ) do
				self.cl.trackInstances[trackName].updateData = updateData
				local instance = self.cl.trackInstances[trackName]
				self:getTrackData( instance, trackName, self.cl.trackdata )
				if updateData.lastTransform then
					finalTransform = ApplyTransform( finalTransform, updateData.lastTransform, updateData.weight, self.harvestable.initialPosition, self.harvestable.initialRotation )
				end
			end

			if finalTransform then
				if self.cl.parentedKinematic then
					self.harvestable.clientPublicData = self.harvestable.clientPublicData or {}
					self.harvestable.clientPublicData.transform = finalTransform
				else
					self.harvestable:setPosition( finalTransform.worldPosition )
					self.harvestable:setRotation( finalTransform.worldRotation )
				end
			end
		end
	end
end

function Kinematic.client_onFixedUpdate( self )
	if self.data.kinematic then 
		if self.data.kinematic.useVelocity then
			if self.cl.movementEffect and sm.exists( self.cl.movementEffect ) and self.cl.movementEffect:isPlaying() then
				local velocity = ( self.harvestable.worldPosition - self.cl.previousPosition ) * 40
				if self.cl.maxSpeed == 0 then
					self.cl.movementEffect:setParameter( "velocity", 0 )
				else
					self.cl.movementEffect:setParameter( "velocity", clamp( math.abs( velocity:length() ) / self.cl.maxSpeed, 0, 1 ) )
				end
				self.cl.previousPosition = self.harvestable.worldPosition;
			end
		end
	end

	if sm.isHost then
		return
	end
	
	local finalTransform = nil

	local activeTracks = 0
	for trackName, instance in pairs( self.cl.trackInstances ) do
		if instance.updateData.weight > 0 then
			activeTracks = activeTracks + 1
		end
	end

	for trackName, trackInstance in pairs( self.cl.trackInstances ) do
		if trackInstance.updateData.moving then
			local transform

			self:getTrackData( trackInstance, trackName, self.cl.trackdata )
			trackInstance.updateData, _, transform = KinematicTrackUpdate( trackInstance.trackDataList, trackInstance.trackSettings, trackInstance.updateData )
			if transform then
				finalTransform = ApplyTransform( finalTransform, transform, trackInstance.updateData.weight, self.harvestable.initialPosition, self.harvestable.initialRotation )
				trackInstance.updateData.lastTransform = {
					worldPosition = sm.vec3.new( transform.worldPosition ),
					worldRotation = sm.quat.new( transform.worldRotation )
				}
			end
		elseif activeTracks > 1 and trackInstance.updateData.weight > 0 then
			-- in this case this track is not moving but we want to apply our last transform anyway, because other active tracks will be applying theirs.
			local transform = trackInstance.updateData.lastTransform
			if transform then
				finalTransform = ApplyTransform( finalTransform, transform, trackInstance.updateData.weight, self.harvestable.initialPosition, self.harvestable.initialRotation )
			end
		end
	end

	if finalTransform then
		if self.cl.parentedKinematic then
			self.harvestable.clientPublicData = self.harvestable.clientPublicData or {}
			self.harvestable.clientPublicData.transform = finalTransform
		else
			self.harvestable:setPosition( finalTransform.worldPosition )
			self.harvestable:setRotation( finalTransform.worldRotation )
		end
	end
end

function Kinematic.cl_n_manageAttachedEffects( self, data )
	if data.effects then
		for index, value in pairs( data.effects ) do
			local pos = self.harvestable.worldPosition
			local rot = self.harvestable.worldRotation
			if value.offsetPosition then
				pos = self.harvestable:transformLocalPoint( value.offsetPosition * self.harvestable:getScale() )
			end
			if value.offsetRotation then
				rot = rot * sm.quat.fromEuler( value.offsetRotation )
			end
			sm.effect.playEffect( value.effectName, pos, nil, rot )
		end
	end
	if data.attachedEffects then
		if not self.cl.activatedAttachedEffects[data.nodeIndex] then
			self.cl.activatedAttachedEffects[data.nodeIndex] = {}
		end
		for index, value in pairs( data.attachedEffects ) do
			if not value.deactivate then
				if self.cl.activatedAttachedEffects[data.nodeIndex] == nil then
					self.cl.activatedAttachedEffects[data.nodeIndex] = {}
				end
				if self.cl.activatedAttachedEffects[data.nodeIndex][index] == nil or not sm.exists( self.cl.activatedAttachedEffects[data.nodeIndex][index] ) then
					local createdEffect = sm.effect.createEffect( value.effectName, self.harvestable )
					if value.offsetPosition then
						createdEffect:setOffsetPosition( value.offsetPosition * self.harvestable:getScale() )
					end
					if value.offsetRotation then
						createdEffect:setOffsetRotation( sm.quat.fromEuler( value.offsetRotation ) )
					end
					self.cl.activatedAttachedEffects[data.nodeIndex][index] = createdEffect
					self.cl.activatedAttachedEffects[data.nodeIndex][index]:start()
				elseif value.repeatable == true then
					if self.cl.activatedAttachedEffects[data.nodeIndex][index]:isPlaying() then
						self.cl.activatedAttachedEffects[data.nodeIndex][index]:stop()
					end
					self.cl.activatedAttachedEffects[data.nodeIndex][index]:start()
				end
				if value.identifier and value.identifier ~= "" then
					self.cl.effectIdentifierLookups[value.identifier] = self.cl.effectIdentifierLookups[value.identifier] or {}
					self.cl.effectIdentifierLookups[value.identifier][#self.cl.effectIdentifierLookups[value.identifier]+1] = { nodeIndex = data.nodeIndex, arrayIndex = index }
				end
			end
		end
	end
	if data.deactivate and data.deactivate ~= "" then
		if self.cl.effectIdentifierLookups[data.deactivate] then
			for _, effectData in ipairs( self.cl.effectIdentifierLookups[data.deactivate] ) do
				if self.cl.activatedAttachedEffects[effectData.nodeIndex] and self.cl.activatedAttachedEffects[effectData.nodeIndex][effectData.arrayIndex] then
					self.cl.activatedAttachedEffects[effectData.nodeIndex][effectData.arrayIndex]:destroy()
					self.cl.activatedAttachedEffects[effectData.nodeIndex][effectData.arrayIndex] = nil
				end
			end
			self.cl.effectIdentifierLookups[data.deactivate] = nil
		end
	end
end
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

QuestActorManager = class( nil )

QuestActorManager.ActorTrackVersion = 1

local CheckTickInterval = 200
local UnitRequestCooldownTicks = 40
local TicksPerSecond = 40

local Actor = {
	home = { world = nil, position = nil, direction = nil }, -- if the actor is missing it will respawn at home. home will be set as commands are completed.
	stateData = { -- runtime data for the actor state.
		commandList = nil, -- the list of commands to execute.
		trackName = nil, -- active actor track name, nil when no track is active.
		pendingTrackName = nil, -- track requested before its node loaded; applied on registration (see sv_onActorTrackRegistered).
		pendingForceRestart = nil, -- forceRestart flag to use when the pending track begins.
		pendingNotifications = nil, -- notify events received before the track started; applied when the track begins.
		trackVersion = nil, -- version of the track when it was started, compared against QuestEntityManager to patch running tracks.
		currentCommandIndex = 1, -- 1 means first command, 0 means no active command (finished track)
		commandStartTick = 0, -- 0 means not started.

		-- settings for the actor
		lookAtPlayer = false,
		facingAngle = 0,
		movementType = "walk"
	}
}

-- Mark commands in the list complete for a received notify event. Returns true if anything changed.
local function applyNotifyEvent( commandList, event )
	local changed = false
	for _, command in ipairs( commandList ) do
		if command.complete ~= true then
			if ( command.name == "wait" or command.name == "interactiveWait" ) and command.notifyActorEvent == event then
				command.complete = true
				changed = true
			elseif ( command.name == "awaitInteraction" or command.name == "blockingDialog" ) and command.notifySkip == event then
				command.complete = true
				changed = true
			end
		end
	end
	return changed
end

function QuestActorManager.Sv_GetOrCreateActor( name )
	if g_questActorManager then
		return g_questActorManager:sv_getOrCreateActor( name )
	end
end

function QuestActorManager.sv_getOrCreateActor( self, name )
	if name then
		if not self.sv.saved.actors[name] then
			local saved = sm.storage.load( { STORAGE_CHANNEL_QUEST_ACTOR_MANAGER, name } )
			if saved then
				self.sv.saved.actors[name] = saved
			else
				self.sv.saved.actors[name] = DeepCopy( Actor )
			end
		end
		self:sv_patchTrackVersion( name, self.sv.saved.actors[name] )
		return self.sv.saved.actors[name]
	end
	return nil
end

function QuestActorManager.Sv_GetActor( name )
	if g_questActorManager then
		return g_questActorManager:sv_getActor( name )
	end
end

function QuestActorManager.Sv_GetActorTrackName( actorName )
	if g_questActorManager then
		return g_questActorManager:sv_getActorTrackName( actorName )
	end
	return nil
end

function QuestActorManager.sv_getActor( self, name )
	if name then
		if not self.sv.saved.actors[name] then
			local saved = sm.storage.load( { STORAGE_CHANNEL_QUEST_ACTOR_MANAGER, name } )
			if saved then
				self.sv.saved.actors[name] = saved
			end
		end
		self:sv_patchTrackVersion( name, self.sv.saved.actors[name] )
		return self.sv.saved.actors[name]
	end
	return nil
end

function QuestActorManager.sv_getActorTrackName( self, actorName )
	local actorData = self:sv_getActor( actorName )
	if actorData and actorData.stateData then
		return actorData.stateData.trackName
	end
	return nil
end

-- Returns the actor's current blocking command, or nil when there is no active command.
function QuestActorManager.Sv_GetActorCurrentCommand( name )
	if g_questActorManager then
		return g_questActorManager:sv_getActorCurrentCommand( name )
	end
	return nil
end

function QuestActorManager.sv_getActorCurrentCommand( self, name )
	local actorData = self:sv_getActor( name )
	if actorData and actorData.stateData and actorData.stateData.commandList then
		local index = actorData.stateData.currentCommandIndex
		if index and index ~= 0 then
			return actorData.stateData.commandList[index]
		end
	end
	return nil
end

function QuestActorManager.Sv_GetActorUnit( name )
	if g_questActorManager then
		return g_questActorManager:sv_getActorUnit( name )
	end
	return nil
end

function QuestActorManager.sv_getActorUnit( self, name )
	if name and self.sv.saved.actorUnits[name] then
		return self.sv.saved.actorUnits[name].unit
	end
	return nil
end

-- True if the manager has a registered unit entry for this actor, even when the live unit has not
-- respawned yet this session (the entry persists by character uuid across save/load).
function QuestActorManager.Sv_HasActorUnit( name )
	if g_questActorManager then
		return g_questActorManager:sv_hasActorUnit( name )
	end
	return false
end

function QuestActorManager.sv_hasActorUnit( self, name )
	return name ~= nil and self.sv.saved.actorUnits[name] ~= nil
end

function QuestActorManager.Sv_SaveActorState( name )
	if g_questActorManager then
		g_questActorManager:sv_saveActorState( name )
	end
end

function QuestActorManager.sv_saveActorState( self, name )
	local actorData = self.sv.saved.actors[name]
	if actorData then
		self:sv_saveActor( name )
	end
end

function QuestActorManager.Sv_SetActorHome( name, world, position, direction )
	if g_questActorManager then
		g_questActorManager:sv_setActorHome( name, world, position, direction )
	end
end

function QuestActorManager.sv_setActorHome( self, name, world, position, direction )
	local actorData = self.sv.saved.actors[name]
	if actorData then
		if actorData.home.position ~= position or actorData.home.direction ~= direction or actorData.home.world ~= world then
			actorData.home.world = world
			actorData.home.position = position
			actorData.home.direction = direction
			self:sv_saveActor( name )
		end
	end
end

function QuestActorManager.Sv_RegisterUniqueActor( name, actorUnit )
	if g_questActorManager then
		g_questActorManager:sv_registerUniqueActor( name, actorUnit )
	end
end

function QuestActorManager.sv_registerUniqueActor( self, name, actorUnit )
	if self.sv.saved.actorUnits[name] and self.sv.saved.actorUnits[name].unit ~= actorUnit then
		if self.sv.saved.actorUnits[name].unit then
			sm.unit.forceDestroy( self.sv.saved.actorUnits[name].unit )
		end
	end
	self.sv.saved.actorUnits[name] = { unit = actorUnit, uuid = actorUnit.character:getCharacterType() }
	sm.storage.save( STORAGE_CHANNEL_QUEST_ACTOR_MANAGER, self.sv.saved.actorUnits )
end

function QuestActorManager.Sv_UnregisterActor( name )
	if g_questActorManager then
		g_questActorManager:sv_unregisterActor( name )
	end
end

function QuestActorManager.sv_unregisterActor( self, name )
	if self.sv.saved.actorUnits[name] then
		self.sv.saved.actorUnits[name] = nil
		sm.storage.save( STORAGE_CHANNEL_QUEST_ACTOR_MANAGER, self.sv.saved.actorUnits )

		self.sv.saved.actors[name] = nil
		self:sv_saveActor( name )
	end
end

--[[ Server ]]
function QuestActorManager.server_onCreate( self )
	assert( g_questActorManager == nil )
	g_questActorManager = self
	self.sv = {}
	local unitStorage = sm.storage.load( STORAGE_CHANNEL_QUEST_ACTOR_MANAGER )
	
	self.sv.saved = {}
	self.sv.saved.actorUnits = unitStorage or {}
	self.sv.saved.actors = {} -- filled by individual actor data loads

	self.sv.pendingUnitRequestTicks = {}

	self.sv.lastCheckTick = sm.game.getCurrentTick()
	self.sv.missingActors = {}
end

function QuestActorManager.server_onFixedUpdate( self, dt )
	local saveUnits = false
	local currentTick = sm.game.getCurrentTick()
	if currentTick >= self.sv.lastCheckTick + CheckTickInterval then
		self.sv.lastCheckTick = currentTick
		for actorName, actorData in pairs( self.sv.saved.actors ) do
			-- Flush a pending track request whose node has since loaded.
			if actorData.stateData and actorData.stateData.pendingTrackName then
				local pendingTrackData = QuestEntityManager.Sv_GetNamedActorTrack( actorData.stateData.pendingTrackName )
				if pendingTrackData then
					self:sv_applyActorTrack( actorName, actorData, actorData.stateData.pendingTrackName, pendingTrackData, actorData.stateData.pendingForceRestart )
				end
			end

			local pendingTick = self.sv.pendingUnitRequestTicks[actorName]
			if pendingTick then
				if currentTick >= pendingTick + UnitRequestCooldownTicks then
					self.sv.pendingUnitRequestTicks[actorName] = nil
				end
			end
			
			local actorUnitData = SafeNestedAccess( self.sv.saved.actorUnits, actorName )
			local unit = SafeNestedAccess( actorUnitData, "unit" )
			local unitCharacterUuid = SafeNestedAccess( actorUnitData, "uuid" )

			if unitCharacterUuid and not sm.exists( unit ) and self.sv.pendingUnitRequestTicks[actorName] == nil then
				if actorData.home and actorData.home.world and actorData.home.position then
					local cellX = math.floor( actorData.home.position.x / 64 )
					local cellY = math.floor( actorData.home.position.y / 64 )
					if sm.exists( actorData.home.world ) and actorData.home.world:isCellLoadedServer( cellX, cellY ) then
						local spawnParams = {
							uuid = unitCharacterUuid,
							position = actorData.home.position,
							amount = 1,
							customParams = { questActorParams = { actorName = actorName } }
						}

						sm.event.sendToWorld( actorData.home.world, "sv_e_spawnUnit", spawnParams )
						self.sv.pendingUnitRequestTicks[actorName] = currentTick
						if unit then
							sm.unit.forceDestroy( unit ) -- destroy old unit
						end
						self.sv.saved.actorUnits[actorName].unit = nil
						saveUnits = true
					end
				end
			elseif sm.exists( unit ) then
				local unitWorld = GetWorld( unit )
				if unitWorld and actorData.home and actorData.home.world and unitWorld ~= actorData.home.world then
					sm.unit.forceDestroy( unit )
					self.sv.saved.actorUnits[actorName].unit = nil
					saveUnits = true
				end
			end
		end
	end
	if saveUnits then
		sm.storage.save( STORAGE_CHANNEL_QUEST_ACTOR_MANAGER, self.sv.saved.actorUnits )
	end
end

function QuestActorManager.sv_saveActor( self, name )
	sm.storage.save( { STORAGE_CHANNEL_QUEST_ACTOR_MANAGER, name }, self.sv.saved.actors[name] )
end

function QuestActorManager.Sv_BeginActorTrack( trackName, actorName, forceRestart )
	-- get the command list from the quest entity manager
	if g_questActorManager then
		g_questActorManager:sv_beginActorTrack( trackName, actorName, forceRestart )
	end
end

function QuestActorManager.sv_beginActorTrack( self, trackName, actorName, forceRestart )
	local actorData = QuestActorManager.Sv_GetOrCreateActor( actorName )
	if not actorData then
		sm.log.error( "QuestActorManager: Failed to get or create actor '" .. tostring( actorName ) .. "'." )
		return
	end
	local actorTrackData = QuestEntityManager.Sv_GetNamedActorTrack( trackName )
	if actorTrackData then
		self:sv_applyActorTrack( actorName, actorData, trackName, actorTrackData, forceRestart )
	else
		-- Track isn't registered yet (its node hasn't loaded this session). Record the request so it
		-- begins for real once the track loads (see sv_onActorTrackRegistered / server_onFixedUpdate).
		actorData.stateData.pendingTrackName = trackName
		actorData.stateData.pendingForceRestart = forceRestart or nil
		self:sv_saveActor( actorName )
	end
end

-- Assign a loaded track's commands to an already-resolved actor and clear any pending request.
function QuestActorManager.sv_applyActorTrack( self, actorName, actorData, trackName, actorTrackData, forceRestart )
	local commandList = actorTrackData.commandList
	if IsEmptyTable( commandList ) then
		sm.log.error( "QuestActorManager: Actor track '" .. trackName .. "' has no commands." )
		return
	end

	local hadPending = actorData.stateData.pendingTrackName ~= nil
	actorData.stateData.pendingTrackName = nil
	actorData.stateData.pendingForceRestart = nil

	-- Skip restart if already on the same track (preserves notification state)
	if not forceRestart and actorData.stateData.trackName == trackName then
		if hadPending then
			self:sv_saveActor( actorName )
		end
		return
	end

	-- assign the command list to the actor, update home position to the start position of the track.
	actorData.stateData.trackName = trackName
	actorData.stateData.trackVersion = actorTrackData.version
	actorData.stateData.commandList = DeepCopy( commandList ) -- make a copy to avoid modifying the original commands
	actorData.stateData.currentCommandIndex = 1
	actorData.stateData.commandStartTick = 0
	self:sv_setActorHome( actorName, actorTrackData.world, commandList[1].position or sm.vec3.new( 0, 0, 0 ), commandList[1].direction or sm.vec3.new( 1, 0, 0 ) )
	-- Apply any notifications that arrived before the track started.
	if actorData.stateData.pendingNotifications then
		for pendingEvent in pairs( actorData.stateData.pendingNotifications ) do
			applyNotifyEvent( actorData.stateData.commandList, pendingEvent )
		end
		actorData.stateData.pendingNotifications = nil
	end
	self:sv_saveActor( actorName )
end

-- Called by QuestEntityManager when an actor track's node registers. Begins any actor that requested
-- this track before it had loaded (its request is held in stateData.pendingTrackName).
function QuestActorManager.Sv_OnActorTrackRegistered( trackName )
	if g_questActorManager then
		g_questActorManager:sv_onActorTrackRegistered( trackName )
	end
end

function QuestActorManager.sv_onActorTrackRegistered( self, trackName )
	local actorTrackData = QuestEntityManager.Sv_GetNamedActorTrack( trackName )
	if not actorTrackData then
		return
	end
	for actorName, actorData in pairs( self.sv.saved.actors ) do
		if actorData.stateData and actorData.stateData.pendingTrackName == trackName then
			self:sv_applyActorTrack( actorName, actorData, trackName, actorTrackData, actorData.stateData.pendingForceRestart )
		end
	end
end

function QuestActorManager.sv_patchTrackVersion( self, name, actorData )
	if not ( actorData and actorData.stateData and actorData.stateData.trackName ) then
		return
	end
	local freshTrackData = QuestEntityManager.Sv_GetNamedActorTrack( actorData.stateData.trackName )
	if not freshTrackData or freshTrackData.version == nil or actorData.stateData.trackVersion == freshTrackData.version then
		return
	end
	
	--add missing fields
	local runningList = actorData.stateData.commandList
	local freshList = freshTrackData.commandList
	if runningList and freshList and #runningList == #freshList then
		for i, freshCommand in ipairs( freshList ) do
			local runningCommand = runningList[i]
			if runningCommand and runningCommand.name == freshCommand.name then
				for key, value in pairs( freshCommand ) do
					if runningCommand[key] == nil then
						runningCommand[key] = value
					end
				end
			end
		end
	end
	actorData.stateData.trackVersion = freshTrackData.version
	self:sv_saveActor( name )
end

function QuestActorManager.Sv_EndActorTrack( actorName )
	if g_questActorManager then
		g_questActorManager:sv_endActorTrack( actorName )
	end
end

function QuestActorManager.sv_endActorTrack( self, actorName )
	local actorData = self.sv.saved.actors[actorName]
	if actorData then
		--keep home position, remember a persistent world position for the actor. clear manually if actor should disappear permanently.
		actorData.stateData = DeepCopy( Actor.stateData )
		self:sv_saveActor( actorName )
	end
end

function QuestActorManager.PrepareCommandList( waypointTrackParamData, worldPosition, worldRotation, scale, world )
	-- preprocess the track to format it into commands.
	local preprocessedTrack = EvaluateWaypointTrack( waypointTrackParamData, worldPosition, worldRotation, scale, world ) -- transform positions
	local commandList = {}
	for _, waypoint in ipairs( preprocessedTrack ) do
		-- insert a move command to the waypoint position
		local facingDirection = waypoint.rotation * sm.vec3.new( 0, 0, 1 )
		facingDirection.z = 0.0

		table.insert( commandList, {
			name = "move",
			position = waypoint.position,
			rotation = waypoint.rotation,
			direction = facingDirection:safeNormalize( sm.vec3.new( 1, 0, 0 ) ),
			waitForPlayer = waypoint.waitForPlayer,
			incrementalDelay = waypoint.incrementalDelay,
			teleport = waypoint.teleport,
			blocking = true
		} )

		if waypoint.commands then
			for	_, command in ipairs( waypoint.commands ) do
				if command.name == "questEvent" then
					table.insert( commandList, {
						name = "questEvent",
						questEvent = command.questEvent,
						delay = command.delay and math.floor( command.delay * TicksPerSecond ) or 0,
					} )
				elseif command.name == "characterEvent" then
					table.insert( commandList, {
						name = "characterEvent",
						characterEvent = command.characterEvent,
						delay = command.delay and math.floor( command.delay * TicksPerSecond ) or 0,
					} )
				elseif command.name == "setFacingDirection" then
					table.insert( commandList, {
						name = "setFacingDirection",
						angle = command.angle,
						delay = command.delay and math.floor( command.delay * TicksPerSecond ) or 0,
					} )
				elseif command.name == "setFacePlayer" then
					table.insert( commandList, {
						name = "setFacePlayer",
						enabled = command.enabled,
						delay = command.delay and math.floor( command.delay * TicksPerSecond ) or 0,
					} )
				elseif command.name == "giveItem" then
					table.insert( commandList, {
						name = "giveItem",
						type = command.type,
						uuid = command.uuid,
						quantity = command.quantity,
						questEvent = command.questEvent,
						shapeRenderableUuid = command.shapeRenderableUuid,
						incrementalDelay = command.incrementalDelay,
						blocking = true
					} )
				elseif command.name == "awaitInteraction" then
					table.insert( commandList, {
						name = "awaitInteraction",
						interactionText = command.interactionText,
						questEvent = command.questEvent,
						notifySkip = command.notifySkip ~= "" and command.notifySkip or nil,
						externalCompletion = command.externalCompletion or nil,
						incrementalDelay = command.incrementalDelay,
						blocking = true
					} )
				elseif command.name == "wait" then
					local ticks = command.seconds and command.seconds ~= 0 and math.floor( command.seconds * TicksPerSecond ) or nil -- nil means wait indefinitely
					table.insert( commandList, {
						name = "wait",
						ticks = ticks,
						notifyActorEvent = command.notifyActorEvent ~= "" and command.notifyActorEvent or nil,
						incrementalDelay = command.incrementalDelay,
						idle = command.idle,
						immovable = command.immovable,
						blocking = true
					} )
				elseif command.name == "setMovementType" then
					table.insert( commandList, {
						name = "setMovementType",
						movementType = command.movementType,
						delay = command.delay and math.floor( command.delay * TicksPerSecond ) or 0,
					} )
				elseif command.name == "beginTrack" then
					table.insert( commandList, {
						name = "beginTrack",
						trackName = command.trackName,
						blocking = true
					} )
				elseif command.name == "dialog" then
					table.insert( commandList, {
						name = "dialog",
						uuid = command.uuid,
						dialogEntry = command.dialogEntry,
						dialogBeatLookup = command.dialogBeatLookup ~= "" and command.dialogBeatLookup or nil,
						delay = command.delay and math.floor( command.delay * TicksPerSecond ) or 0,
					} )
				elseif command.name == "blockingDialog" then
					table.insert( commandList, {
						name = "blockingDialog",
						uuid = command.uuid,
						dialogEntry = command.dialogEntry,
						dialogBeatLookup = command.dialogBeatLookup ~= "" and command.dialogBeatLookup or nil,
						notifySkip = command.notifySkip ~= "" and command.notifySkip or nil,
						incrementalDelay = command.incrementalDelay,
						blocking = true
					} )
				elseif command.name == "blockingCharacterEvent" then
					table.insert( commandList, {
						name = "blockingCharacterEvent",
						characterEvent = command.characterEvent,
						ticks = command.seconds and math.floor( command.seconds * TicksPerSecond ) or 0,
						incrementalDelay = command.incrementalDelay,
						blocking = true
					} )
				elseif command.name == "interactiveWait" then
					table.insert( commandList, {
						name = "interactiveWait",
						uuid = command.uuid,
						characterEvent = command.characterEvent ~= "" and command.characterEvent or nil,
						interactionText = command.interactionText,
						notifyActorEvent = command.notifyActorEvent ~= "" and command.notifyActorEvent or nil,
						cooldownTicks = command.cooldown and math.floor( command.cooldown * TicksPerSecond ) or 0,
						repeating = command.repeating or true,
						incrementalDelay = command.incrementalDelay,
						blocking = true
					} )
				end
			end
		end
	end
	return commandList
end

function QuestActorManager.Sv_CompleteActorInteraction( name )
	if g_questActorManager then
		g_questActorManager:sv_completeActorInteraction( name )
	end
end

function QuestActorManager.sv_completeActorInteraction( self, name )
	local actorData = self:sv_getActor( name )
	if actorData and actorData.stateData.commandList then
		local index = actorData.stateData.currentCommandIndex
		local command = index ~= 0 and actorData.stateData.commandList[index] or nil
		if command and command.name == "awaitInteraction" and command.complete ~= true then
			command.complete = true
			self:sv_saveActor( name )
		end
	end
end

function QuestActorManager.Sv_NotifyActor( name, event )
	if g_questActorManager then
		g_questActorManager:sv_notifyActor( name, event )
	end
end

function QuestActorManager.sv_notifyActor( self, name, event )
	if name and event then
		local actorData = self:sv_getOrCreateActor( name )
		if actorData then
			if actorData.stateData.commandList then
				if applyNotifyEvent( actorData.stateData.commandList, event ) then
					self:sv_saveActor( name )
				end
			else
				-- No track started yet; hold the notify until the track begins (see sv_applyActorTrack).
				actorData.stateData.pendingNotifications = actorData.stateData.pendingNotifications or {}
				if not actorData.stateData.pendingNotifications[event] then
					actorData.stateData.pendingNotifications[event] = true
					self:sv_saveActor( name )
				end
			end
		end
	end
end

function QuestActorManager.Sv_CancelNotifyActor( name, event )
	if g_questActorManager then
		g_questActorManager:sv_cancelNotifyActor( name, event )
	end
end

function QuestActorManager.sv_cancelNotifyActor( self, name, event )
	if name and event then
		if self.sv.saved.actors[name] then
			local actorData = self.sv.saved.actors[name]
			local needsSave = false
			if actorData.stateData.pendingNotifications and actorData.stateData.pendingNotifications[event] then
				actorData.stateData.pendingNotifications[event] = nil
				needsSave = true
			end
			if actorData.stateData.commandList then
				for _, command in ipairs( actorData.stateData.commandList ) do
					if command.complete == true then
						if ( command.name == "wait" or command.name == "interactiveWait" ) and command.notifyActorEvent == event then
							command.complete = nil
							needsSave = true
						elseif ( command.name == "awaitInteraction" or command.name == "blockingDialog" ) and command.notifySkip == event then
							command.complete = nil
							needsSave = true
						end
					end
				end
			end
			if needsSave then
				self:sv_saveActor( name )
			end
		end
	end
end



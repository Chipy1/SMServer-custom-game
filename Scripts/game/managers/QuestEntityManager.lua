dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")

QuestEntityManager = class( nil )

local QuestInteractables =
{
	obj_survivalobject_powercoresocket,
	obj_survivalobject_powercore
}

--[[ Server ]]
function QuestEntityManager.server_onCreate( self )
	g_questEntityManager = self
	self.sv = {}
	-- Area Triggers
	self.sv.worldCellAreaTriggers = {}
	self.sv.namedAreaTriggers = {}
	self.sv.namedAreaTriggersById = {}
	self.sv.bindRequests = {}

	-- Waypoints
	self.sv.worldCellWaypoints = {}
	self.sv.namedWaypoints = {}

	-- WaypointTracks
	self.sv.worldCellWaypointTracks = {}
	self.sv.namedWaypointTracks = {}

	-- ActorTracks
	self.sv.worldCellActorTracks = {}
	self.sv.namedActorTracks = {}

	-- Nodes
	self.sv.worldCellNodes = {}
	self.sv.eventNodes = {}
	self.sv.cellQuestNodes = {}

	-- Interactables
	self.sv.interactablesByUuid = {}
	self.sv.interactablesById = {}

	-- Saved markers information
	
	self.sv.saved = sm.storage.load( STORAGE_CHANNEL_QUESTENTITYMANAGER )
	self.sv.isDirty = false
	if self.sv.saved == nil then
		self.sv.saved = {}
	else
		if IsArray( self.sv.saved ) then -- convert to map
			local map = {}
			for _,markerData in pairs( self.sv.saved ) do
				map[markerData.name] = markerData
			end
			self.sv.saved = map
		end
	end
	self.network:setClientData( self.sv.saved )

	self.sv.loadedPrecachedMarkers = {}
end

function QuestEntityManager.Sv_OnTerrainLoaded( world )
	if g_questEntityManager then
		sm.event.sendToScriptableObject( g_questEntityManager.scriptableObject, "sv_onTerrainLoaded", world, sm.event.types.instant )
	end
end

function QuestEntityManager.sv_onTerrainLoaded( self, world )
	local targetWorldId = world.id
	if self.sv.loadedPrecachedMarkers[targetWorldId] == nil then
		
		local precachedNodes = sm.storage.load( STORAGE_CHANNEL_PRECACHED_MARKERS )
		
		if precachedNodes then
			for worldId, nodeList in pairs( precachedNodes ) do
				if worldId == targetWorldId then
					for _,node in ipairs( nodeList ) do
						local fnMakeMarker = function( node )
							local markerData = {}
							markerData.name = node.params.name
							markerData.position = node.pos
							markerData.world = node.world
							markerData.isMainQuest = not node.params.isSideQuest
							markerData.visibleFar = node.params.visibleFar
							return markerData
						end

						if self.sv.saved[node.params.name] == nil then
							local markerData = fnMakeMarker( node )
							if markerData.name == nil or markerData.name == "" then
								sm.log.warning( "QuestEntityManager: Skipping marker with empty key in sv_onTerrainLoaded" )
							else
								self.sv.saved[markerData.name] = markerData
								self.sv.isDirty = true
							end
						else
							local savedMarker = self.sv.saved[node.params.name]
							if not sm.vec3.fuzzyEquals( savedMarker.position, node.pos ) or savedMarker.world ~= node.world or savedMarker.isMainQuest ~= not node.params.isSideQuest then
								local markerData = fnMakeMarker( node )
								self.sv.saved[savedMarker.name] = markerData
								self.sv.isDirty = true
							end
						end
					end
					break
				end
			end
		end
		self.sv.loadedPrecachedMarkers[targetWorldId] = true
	end

	QuestManager.Sv_QuestEntityTerrainLoaded( world )
end

function QuestEntityManager.server_onFixedUpdate( self, dt )
	if self.sv.isDirty then
		self:sv_saveMarkers()
	end
end

function QuestEntityManager.sv_saveMarkers( self )
	self.sv.isDirty = false
	sm.storage.save( STORAGE_CHANNEL_QUESTENTITYMANAGER, self.sv.saved )
	self.network:setClientData( self.sv.saved )
end

--[[ Manager ]]
function QuestEntityManager.Sv_OnWorldCellLoaded( world, x, y )
	if g_questEntityManager then
		g_questEntityManager:sv_onWorldCellLoaded( world, x, y )
	end
end

function QuestEntityManager.sv_onWorldCellLoaded( self, world, x, y )
	local worldId = world.id
	local cellKey = CellKey( x, y )
	-- AreaTrigger
	local areaTriggerNodes = sm.cell.getNodesByTag( x, y, "AREATRIGGER" )
	self.sv.worldCellAreaTriggers[worldId] = self.sv.worldCellAreaTriggers[worldId] or {}
	self.sv.worldCellAreaTriggers[worldId][cellKey] = {}
	local areaTriggers = self.sv.worldCellAreaTriggers[worldId][cellKey]
	for _, node in ipairs( areaTriggerNodes ) do
		if node.params and node.params.name then
			-- Create the areatrigger
			local filter = sm.areaTrigger.filter.character
			local areaTrigger = sm.areaTrigger.createBox( node.scale * 0.5, node.position, node.rotation, filter )
			self.sv.bindRequests[#self.sv.bindRequests+1] = areaTrigger
			local areaTriggerData = {
				areaTrigger = areaTrigger,
				name = node.params.name
			}
			areaTriggers[#areaTriggers+1] = areaTriggerData
			self.sv.namedAreaTriggers[areaTriggerData.name] = areaTriggerData
			self.sv.namedAreaTriggersById[areaTrigger.id] = areaTriggerData
		end
	end
	if #self.sv.bindRequests > 0 then
		sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_bindCallbacks" )
	end

	-- Enemy event spawn nodes
	local eventNodes = sm.cell.getNodesByTag( x, y, "EVENT_NODE" )
	self.sv.worldCellNodes[worldId] = self.sv.worldCellNodes[worldId] or {}
	self.sv.worldCellNodes[worldId][cellKey] = {}
	local cellNodes = self.sv.worldCellNodes[worldId][cellKey]
	for _, node in ipairs( eventNodes ) do
		if node.params and node.params.eventName then
			node.world = world
			cellNodes[#cellNodes+1] = node
			if self.sv.eventNodes[node.params.eventName] == nil then
				self.sv.eventNodes[node.params.eventName] = {}
			end
			self.sv.eventNodes[node.params.eventName][#self.sv.eventNodes[node.params.eventName] + 1 ] = node
		end
	end

	-- Cell Quest nodes
	local eventNodes = sm.cell.getNodesByTag( x, y, "CELL_QUEST_NODE" )
	local cellNodes = self.sv.worldCellNodes[worldId][cellKey]
	for _, node in ipairs( eventNodes ) do
		if node.params and node.params.name then
			node.world = world
			cellNodes[#cellNodes+1] = node
			self.sv.cellQuestNodes[node.params.name] = node
		end
	end

	-- Waypoint
	local waypointNodes = sm.cell.getNodesByTag( x, y, "WAYPOINT" )
	self.sv.worldCellWaypoints[worldId] = self.sv.worldCellWaypoints[worldId] or {}
	self.sv.worldCellWaypoints[worldId][cellKey] = {}
	local waypoints = self.sv.worldCellWaypoints[worldId][cellKey]
	for _, node in ipairs( waypointNodes ) do
		if node.params and node.params.name then
			local waypointData = {
				position = node.position,
				rotation = node.rotation,
				name = node.params.name,
				world = world
			}
			waypoints[#waypoints+1] = waypointData
			self.sv.namedWaypoints[waypointData.name] = waypointData
			QuestManager.Sv_SendEvent( QuestEvent.WaypointLoaded, { name = node.params.name } )
		end
	end

	-- Questmarkers
	local questMarkerNodes = sm.cell.getNodesByTag( x, y, "QUESTMARKER" )
	for _, node in ipairs( questMarkerNodes ) do
		if node.params and node.params.name then

			local markerData = {}

			markerData.name = node.params.name
			markerData.position = node.position
			markerData.world = world
			markerData.visibleFar = node.params.visibleFar
			if node.params.isSideQuest then
				markerData.isMainQuest = false
			else
				markerData.isMainQuest = true
			end

			-- Replace precached markers with the new ones if they dont have host
			if markerData.name == nil or markerData.name == "" then
				sm.log.warning( "Skipping marker with empty key in sv_onWorldCellLoaded QUESTMARKER" )
			elseif self.sv.saved[markerData.name] then
				if self.sv.saved[markerData.name].host == nil then
					self.sv.saved[markerData.name] = markerData
					self.sv.isDirty = true
				end
			else

				self.sv.saved[markerData.name] = markerData
				self.sv.isDirty = true
			end
		end
	end

	-- Waypoint Tracks
	local waypointTrackNodes = sm.cell.getNodesByTag( x, y, "WAYPOINTTRACK" )
	self.sv.worldCellWaypointTracks[worldId] = self.sv.worldCellWaypointTracks[worldId] or {}
	self.sv.worldCellWaypointTracks[worldId][cellKey] = {}
	local waypoints = self.sv.worldCellWaypointTracks[worldId][cellKey]
	for _, node in ipairs( waypointTrackNodes ) do
		if node.params and node.params.name then
			local waypointTrackData = {
				position = node.position,
				rotation = node.rotation,
				scale = node.scale,
				name = node.params.name,
				world = world,
				waypointTrack = node.params.waypointTrack
			}
			waypoints[#waypoints+1] = waypointTrackData
			self.sv.namedWaypointTracks[waypointTrackData.name] = waypointTrackData
			QuestManager.Sv_SendEvent( QuestEvent.WaypointTrackLoaded, { name = node.params.name } )
		end
	end

	-- prepare actor track
	local actorTrackNodes = sm.cell.getNodesByTag( x, y, "ACTORTRACK" )
	self.sv.worldCellActorTracks[worldId] = self.sv.worldCellActorTracks[worldId] or {}
	self.sv.worldCellActorTracks[worldId][cellKey] = {}
	local actorTracks = self.sv.worldCellActorTracks[worldId][cellKey]
	for _, node in ipairs( actorTrackNodes ) do
		if node.params and node.params.name and self.sv.namedActorTracks[node.params.name] == nil then
			local actorTrackData = {
				position = node.position,
				rotation = node.rotation,
				scale = node.scale,
				name = node.params.name,
				world = world,
				version = QuestActorManager.ActorTrackVersion,
				commandList = QuestActorManager.PrepareCommandList( node.params, node.position, node.rotation, node.scale, world )
			}
			actorTracks[#actorTracks+1] = actorTrackData
			self.sv.namedActorTracks[actorTrackData.name] = actorTrackData
			QuestManager.Sv_SendEvent( QuestEvent.ActorTrackLoaded, { name = node.params.name } )
			QuestActorManager.Sv_OnActorTrackRegistered( actorTrackData.name )
		end
	end

end

function QuestEntityManager.Sv_GetQuestMarkerPosition( markerName )
	return SafeNestedAccess( g_questEntityManager.sv.saved, markerName, "position" )
end

function QuestEntityManager.Sv_RegisterHostedQuestMarker( host, offset, isMainQuest, markerName )
	g_questEntityManager:sv_registerHostedQuestMarker( host, offset, isMainQuest, markerName )
end

function QuestEntityManager.sv_registerHostedQuestMarker( self, host, offset, isMainQuest, markerName )
	if markerName == nil or markerName == "" then
		sm.log.warning( "Skipping marker with empty key in sv_registerHostedQuestMarker" )
		return
	end
	local markerData = self.sv.saved[markerName] or {}
	markerData.name = markerName
	markerData.offset = offset
	markerData.host = host
	if type( host ) == "Shape" then
		markerData.position = host:getWorldPosition()
		markerData.world = host.body:getWorld()
	elseif type( host ) == "Character" then
		markerData.position = host:getWorldPosition()
		markerData.world = host:getWorld()
	end
	if isMainQuest then
		markerData.isMainQuest = true
	else
		markerData.isMainQuest = false
	end

	self.sv.saved[markerName] = markerData
	self.sv.isDirty = true
end

function QuestEntityManager.Sv_UpdateHostedMarkerBasePosition( markerName, position )
	g_questEntityManager:sv_updateHostedMarkerBasePosition( markerName, position )
end

function QuestEntityManager.sv_updateHostedMarkerBasePosition( self, markerName, position )
	if self.sv.saved[markerName] then
		self.sv.saved[markerName].position = position
		self.sv.isDirty = true
	end
end

function QuestEntityManager.Sv_UnregisterHostedQuestMarker( markerName )
	g_questEntityManager:sv_unregisterHostedQuestMarker( markerName )
end

function QuestEntityManager.sv_unregisterHostedQuestMarker( self, markerName )
	self.sv.saved[markerName] = nil
	self.sv.isDirty = true
end

function QuestEntityManager.Sv_ReleaseHostedQuestMarker( markerName )
	g_questEntityManager:sv_releaseHostedQuestMarker( markerName )
end

function QuestEntityManager.sv_releaseHostedQuestMarker( self, markerName )
	if self.sv.saved[markerName] then
		self.sv.saved[markerName].host = nil
		self.sv.isDirty = true
	end
end

function QuestEntityManager.sv_e_bindCallbacks( self )
	-- Bind triggers within the manager
	for _, areaTrigger in ipairs( self.sv.bindRequests ) do
		if sm.exists( areaTrigger ) then
			areaTrigger:bindOnEnter( "trigger_onEnter" )
			areaTrigger:bindOnExit( "trigger_onExit" )
		end
	end
	self.sv.bindRequests = {}
end

function QuestEntityManager.Sv_OnWorldCellUnloaded( world, x, y )
	if g_questEntityManager then
		g_questEntityManager:sv_onWorldCellUnloaded( world, x, y )
	end
end

function QuestEntityManager.sv_onWorldCellUnloaded( self, world, x, y )
	local worldId = world.id
	local cellKey = CellKey( x, y )

	-- AreaTrigger
	local areaTriggers = self.sv.worldCellAreaTriggers[worldId] and self.sv.worldCellAreaTriggers[worldId][cellKey] or nil
	if areaTriggers then
		for _, areaTriggerData in ipairs( areaTriggers ) do
			if areaTriggerData.name then
				self.sv.namedAreaTriggers[areaTriggerData.name] = nil
			end
			if areaTriggerData.areaTrigger then
				self.sv.namedAreaTriggersById[areaTriggerData.areaTrigger.id] = nil
				if sm.exists( areaTriggerData.areaTrigger ) then
					sm.areaTrigger.destroy( areaTriggerData.areaTrigger )
				end
			end
		end
		self.sv.worldCellAreaTriggers[worldId][cellKey] = nil
	end

	-- Node
	local cellNodes = self.sv.worldCellNodes[worldId] and self.sv.worldCellNodes[worldId][cellKey] or nil
	if cellNodes then
		for _, node in ipairs( cellNodes ) do
			if node.params.eventName then
				self.sv.eventNodes[node.params.eventName] = nil
			end
			if node.params.name then
				self.sv.cellQuestNodes[node.params.name] = nil
			end
		end
		self.sv.worldCellNodes[worldId][cellKey] = nil
	end

	-- Waypoint
	local waypoints = self.sv.worldCellWaypoints[worldId] and self.sv.worldCellWaypoints[worldId][cellKey] or nil
	if waypoints then
		for _, waypointData in ipairs( waypoints ) do
			if waypointData.name then
				self.sv.namedWaypoints[waypointData.name] = nil
			end
		end
		self.sv.worldCellWaypoints[worldId][cellKey] = nil
	end

	-- Waypoint Tracks
	local waypointTracks = self.sv.worldCellWaypointTracks[worldId] and self.sv.worldCellWaypointTracks[worldId][cellKey] or nil
	if waypointTracks then
		for _, waypointTrackData in ipairs( waypointTracks ) do
			if waypointTrackData.name then
				self.sv.namedWaypointTracks[waypointTrackData.name] = nil
			end
		end
		self.sv.worldCellWaypointTracks[worldId][cellKey] = nil
	end
end

--[[ Areatrigger ]]
function QuestEntityManager.Sv_GetNamedAreaTrigger( name )
	if g_questEntityManager then
		return g_questEntityManager:sv_getNamedAreaTrigger( name )
	end
	return nil
end

function QuestEntityManager.sv_getNamedAreaTrigger( self, name )
	return self.sv.namedAreaTriggers[name]
end

function QuestEntityManager.Sv_NamedAreaTriggerContainsPlayer( name )
	if g_questEntityManager then
		return g_questEntityManager:sv_namedAreaTriggerContainsPlayer( name )
	end
	return false
end

function QuestEntityManager.sv_namedAreaTriggerContainsPlayer( self, name )
	local triggerData = self.sv.namedAreaTriggers[name]
	if triggerData then
		local contents = triggerData.areaTrigger:getContents()
		for _, content in ipairs( contents ) do
			if type( content ) == "Character" then
				if content:isPlayer() then
					return true
				end
			end
		end
	end
	return false
end

function QuestEntityManager.Sv_GetNamedAreaTriggerPlayers( name )
	if g_questEntityManager then
		return g_questEntityManager:sv_getNamedAreaTriggerPlayers( name )
	end
	return {}
end

function QuestEntityManager.sv_getNamedAreaTriggerPlayers( self, name )
	local players = {}
	local triggerData = self.sv.namedAreaTriggers[name]
	if triggerData and triggerData.areaTrigger and sm.exists( triggerData.areaTrigger ) then
		local contents = triggerData.areaTrigger:getContents()
		for _, content in ipairs( contents ) do
			if type( content ) == "Character" and content:isPlayer() then
				players[#players+1] = content:getPlayer()
			end
		end
	end
	return players
end

function QuestEntityManager.trigger_onEnter( self, trigger, results )
	local areaTriggerNode = self.sv.namedAreaTriggersById[trigger.id]
	if areaTriggerNode then
		local params = { name = areaTriggerNode.name, results = results, world = trigger.world, position = trigger:getWorldPosition() }
		if TriggerResultContainsAnyPlayer( results ) then
			QuestManager.Sv_SendEvent( QuestEvent.AreaTriggerPlayerEnter, params )
			QuestManager.Sv_SendEvent( areaTriggerNode.name .. QuestEvent.AreaTriggerPlayerEnterSuffix, params )
		else
			QuestManager.Sv_SendEvent( QuestEvent.AreaTriggerEnter, params )
			QuestManager.Sv_SendEvent( areaTriggerNode.name .. QuestEvent.AreaTriggerEnterSuffix, params )
		end
	end
end

function QuestEntityManager.trigger_onExit( self, trigger, results )
	local areaTriggerNode = self.sv.namedAreaTriggersById[trigger.id]
	if areaTriggerNode then
		local params = { name = areaTriggerNode.name, results = results, world = trigger.world }
		if TriggerResultContainsAnyPlayer( results ) then
			QuestManager.Sv_SendEvent( QuestEvent.AreaTriggerPlayerExit, params )
			QuestManager.Sv_SendEvent( areaTriggerNode.name .. QuestEvent.AreaTriggerPlayerExitSuffix, params )
		else
			QuestManager.Sv_SendEvent( QuestEvent.AreaTriggerExit, params )
			QuestManager.Sv_SendEvent( areaTriggerNode.name .. QuestEvent.AreaTriggerExitSuffix, params )
		end
	end
end

function QuestEntityManager.Sv_BumpNamedAreaTrigger( name )
	if g_questEntityManager then
		g_questEntityManager:sv_bumpNamedAreaTrigger( name )
	end
end

function QuestEntityManager.sv_bumpNamedAreaTrigger( self, name )
	local triggerData = self.sv.namedAreaTriggers[name]
	if triggerData and triggerData.areaTrigger and sm.exists( triggerData.areaTrigger ) then
		local contents = triggerData.areaTrigger:getContents()
		if #contents > 0 then
			local params = { name = name, results = contents, world = triggerData.areaTrigger.world, position = triggerData.areaTrigger:getWorldPosition() }
			if TriggerResultContainsAnyPlayer( contents ) then
				QuestManager.Sv_SendEvent( QuestEvent.AreaTriggerPlayerEnter, params )
				QuestManager.Sv_SendEvent( name .. QuestEvent.AreaTriggerPlayerEnterSuffix, params )
			else
				QuestManager.Sv_SendEvent( QuestEvent.AreaTriggerEnter, params )
				QuestManager.Sv_SendEvent( name .. QuestEvent.AreaTriggerEnterSuffix, params )
			end
		end
	end
end

function QuestEntityManager.Sv_GetEventNodes( eventName )
	if g_questEntityManager then
		return g_questEntityManager:sv_getEventNodes( eventName )
	end
end

function QuestEntityManager.sv_getEventNodes( self, eventName )
	return self.sv.eventNodes[eventName]
end

function QuestEntityManager.Sv_GetNamedCellQuestNode( name )
	return g_questEntityManager:sv_getNamedCellQuestNode( name )
end

function QuestEntityManager.sv_getNamedCellQuestNode( self, name )
	return self.sv.cellQuestNodes[name]
end

--[[ Waypoint ]]
function QuestEntityManager.Sv_GetNamedWaypoint( name )
	if g_questEntityManager then
		return g_questEntityManager:sv_getNamedWaypoint( name )
	end
	return nil
end

function QuestEntityManager.sv_getNamedWaypoint( self, name )
	return self.sv.namedWaypoints[name]
end

--[[ WaypointTrack ]]
function QuestEntityManager.Sv_GetNamedWaypointTrack( name )
	if g_questEntityManager then
		return g_questEntityManager:sv_getNamedWaypointTrack( name )
	end
	return nil
end

function QuestEntityManager.sv_getNamedWaypointTrack( self, name )
	return self.sv.namedWaypointTracks[name]
end

--[[ ActorTrack ]]
function QuestEntityManager.Sv_GetNamedActorTrack( name )
	if g_questEntityManager then
		return g_questEntityManager:sv_getNamedActorTrack( name )
	end
	return nil
end

function QuestEntityManager.sv_getNamedActorTrack( self, name )
	return self.sv.namedActorTracks[name]
end

function QuestEntityManager.Sv_RegisterActorTrackFromNode( node, world )
	if g_questEntityManager then
		g_questEntityManager:sv_registerActorTrackFromNode( node, world )
	end
end

function QuestEntityManager.sv_registerActorTrackFromNode( self, node, world )
	if node.params and node.params.name and self.sv.namedActorTracks[node.params.name] == nil then
		local actorTrackData = {
			position = node.position,
			rotation = node.rotation,
			scale = node.scale,
			name = node.params.name,
			world = world,
			version = QuestActorManager.ActorTrackVersion,
			commandList = QuestActorManager.PrepareCommandList( node.params, node.position, node.rotation, node.scale, world )
		}
		self.sv.namedActorTracks[actorTrackData.name] = actorTrackData
		QuestManager.Sv_SendEvent( QuestEvent.ActorTrackLoaded, { name = node.params.name } )
		QuestActorManager.Sv_OnActorTrackRegistered( actorTrackData.name )
	end
end

function QuestEntityManager.Sv_UnregisterActorTrack( name )
	if g_questEntityManager then
		g_questEntityManager:sv_unregisterActorTrack( name )
	end
end

function QuestEntityManager.sv_unregisterActorTrack( self, name )
	self.sv.namedActorTracks[name] = nil
end

--[[ Interactable ]]
function QuestEntityManager.Sv_OnInteractableCreated( interactable )
	QuestManager.Sv_SendEvent( QuestEvent.InteractableCreated, { interactable = interactable } )
	if g_questEntityManager then
		g_questEntityManager:sv_onInteractableCreated( interactable )
	end
end

function QuestEntityManager.sv_onInteractableCreated( self, interactable )
	if interactable.shape then
		if isAnyOf( interactable.shape.uuid, QuestInteractables ) then
			local stringUuid = tostring( interactable.shape.uuid )
			self.sv.interactablesByUuid[stringUuid] = self.sv.interactablesByUuid[stringUuid] or {}
			self.sv.interactablesByUuid[stringUuid][interactable.id] = interactable
			self.sv.interactablesById[interactable.id] = { uuid = interactable.shape.uuid, interactable = interactable }
		end
	end
end

function QuestEntityManager.Sv_OnInteractableDestroyed( interactable )
	QuestManager.Sv_SendEvent( QuestEvent.InteractableDestroyed, { interactable = interactable } )
	if g_questEntityManager then
		g_questEntityManager:sv_onInteractableDestroyed( interactable )
	end
end

function QuestEntityManager.sv_onInteractableDestroyed( self, interactable )
	local interactableData = self.sv.interactablesById[interactable.id]
	if interactableData then
		local stringUuid = tostring( interactableData.uuid )
		if self.sv.interactablesByUuid[stringUuid] then
			self.sv.interactablesByUuid[stringUuid][interactable.id] = nil
		end
	end
	self.sv.interactablesById[interactable.id] = nil
end

function QuestEntityManager.Sv_GetInteractablesWithUuid( uuid )
	if g_questEntityManager then
		return g_questEntityManager:sv_getInteractablesWithUuid( uuid )
	end
	return {}
end

function QuestEntityManager.sv_getInteractablesWithUuid( self, uuid )
	return self.sv.interactablesByUuid[tostring( uuid )] or {}
end













--[[ Client ]]
function QuestEntityManager.client_onCreate( self )
	g_questEntityManagerClient = self
	self.cl = {}
	self.cl.namedQuestMarkers = {}
	self.cl.activeQuestMarkers = {}
	self.cl.worldPingMarkers = {}
	self.cl.activePingEvents = {}
	self.cl.localPlayer = sm.localPlayer.getPlayer()
	self.cl.compassEnabled = sm.game.getSettingBoolean( "CompassHud" )
end

--[[ Manager ]]

function QuestEntityManager.cl_setActiveMarker( self, markerName, localPlayerPosition )
	if self.cl.activeQuestMarkers[markerName] then
		local markerData = self.cl.namedQuestMarkers[markerName]
		WorldMarkerManager.Cl_SetWorldPosition( markerData.questMarkerName, markerData.position, markerData.world )
	end
end

function QuestEntityManager.Cl_ActivateEventPing( eventName )
	if g_questEntityManagerClient then
		g_questEntityManagerClient:cl_activateEventPing( eventName )
	end
end

function QuestEntityManager.cl_activateEventPing( self, eventName )
	self.cl.activePingEvents[eventName] = true
	for world,cellList in pairs( self.cl.worldPingMarkers ) do
		for cellKey,eventList in pairs( cellList ) do
			for event,effectList in pairs( eventList ) do
				if event == eventName then
					for _,effect in ipairs( effectList ) do
						if not effect:isPlaying() then
							effect:start()
						end
					end
				end
			end
		end
	end
end

function QuestEntityManager.Cl_DeactivateEventPing( eventName )
	if g_questEntityManagerClient then
		g_questEntityManagerClient:cl_deactivateEventPing( eventName )
	end
end

function QuestEntityManager.cl_deactivateEventPing( self, eventName )
	self.cl.activePingEvents[eventName] = false
	for world,cellList in pairs( self.cl.worldPingMarkers ) do
		for cellKey,eventList in pairs( cellList ) do
			for event,effectList in pairs( eventList ) do
				if event == eventName then
					for _,effect in ipairs( effectList ) do
						effect:stop()
					end
				end
			end
		end
	end
end

function QuestEntityManager.Cl_OnWorldCellLoaded( world, x, y )
	if g_questEntityManagerClient then
		g_questEntityManagerClient:cl_onWorldCellLoaded( world, x, y )
	end
end

function QuestEntityManager.cl_onWorldCellLoaded( self, world, x, y )
	local worldId = world.id
	local cellKey = CellKey( x, y )

	-- we dont newed this we sync everyting over client data

	-- QuestMarker
	-- local questMarkerNodes = sm.cell.getNodesByTag( x, y, "QUESTMARKER" )
	-- for _, node in ipairs( questMarkerNodes ) do
	-- 	if node.params and node.params.name then

	-- 		local questMarkerName = node.params.name
	-- 		if self.cl.namedQuestMarkers[node.params.name] == nil then
	-- 			local isSide = node.params.isSideQuest
	-- 			WorldMarkerManager.Cl_CreateOrUpdateMarker( questMarkerName, {
	-- 				effect = "QuestMarker",
	-- 				farEffect = node.params.visibleFar and "QuestMarker_Far" or nil,
	-- 				position = node.position,
	-- 				world = world,
	-- 				textureIndex = isSide and 1 or 0,
	-- 				color = isSide and sm.color.new( "79F1E20F" ) or sm.color.new( "798B0FF1" ),
	-- 				compassImage = isSide and "icon_compass_side_quest.png" or "icon_compass_main_quest.png",
	-- 			})
	-- 		end

	-- 		local questMarkerData = {
	-- 			position = node.position,
	-- 			name = node.params.name,
	-- 			world = world,
	-- 			questMarkerName = questMarkerName,
	-- 			isMainQuest = not node.params.isSideQuest,
	-- 		}
	-- 		if questMarkerData.name == nil or questMarkerData.name == "" then
	-- 			sm.log.warning( "Skipping marker with empty key in cl_onWorldCellLoaded" )
	-- 		else
	-- 			if self.cl.namedQuestMarkers[questMarkerData.name] == nil or self.cl.namedQuestMarkers[questMarkerData.name].host == nil then
	-- 				self.cl.namedQuestMarkers[questMarkerData.name] = questMarkerData
	-- 			end

	-- 			if self.cl.activeQuestMarkers[node.params.name] then
	-- 				local markerIconName = self.cl.namedQuestMarkers[questMarkerData.name].questMarkerName
	-- 				WorldMarkerManager.Cl_ActivateMarker( markerIconName )
	-- 				local character = self.cl.localPlayer:getCharacter()
	-- 				if character then
	-- 					self:cl_setActiveMarker( node.params.name, character:getWorldPosition() )
	-- 				end
	-- 			end
	-- 		end
	-- 	end
	-- end

	-- ping markers
	local pingMarkers = sm.cell.getNodesByTag( x, y, "QUEST_POI_PING" )
	if #pingMarkers > 0 then
		self.cl.worldPingMarkers[worldId] = self.cl.worldPingMarkers[worldId] or {}
		self.cl.worldPingMarkers[worldId][cellKey] = {}
		for _,node in ipairs( pingMarkers ) do
			if node.params and node.params.event and node.params.effect then
				local effect = sm.effect.createEffect( node.params.effect.name )
	
				effect:setWorld( world )
				effect:setPosition( node.position )
				effect:setRotation( node.rotation )
				effect:setScale( node.scale )
				if node.params.effect.params  then
					for k,v in kvpairs( node.params.effect.params ) do
						effect:setParameter(k, v)
					end
				end
				effect = effect
				self.cl.worldPingMarkers[worldId][cellKey][node.params.event] = self.cl.worldPingMarkers[worldId][cellKey][node.params.event] or {}
				self.cl.worldPingMarkers[worldId][cellKey][node.params.event][#self.cl.worldPingMarkers[worldId][cellKey][node.params.event]+1] = effect
				if self.cl.activePingEvents[node.params.event] then
					effect:start()
				end
			end
		end
	end
end

function QuestEntityManager.Cl_OnWorldCellUnloaded( worldSelf, x, y )
	if g_questEntityManagerClient then
		g_questEntityManagerClient:cl_onWorldCellUnloaded( worldSelf, x, y )
	end
end

function QuestEntityManager.cl_onWorldCellUnloaded( self, worldSelf, x, y )
	local worldId = worldSelf.world.id
	local cellKey = CellKey( x, y )

	if self.cl.worldPingMarkers[worldId] and self.cl.worldPingMarkers[worldId][cellKey] then
		for _,eventList in pairs( self.cl.worldPingMarkers[worldId][cellKey] ) do
			for _,effect in ipairs( eventList ) do
				if effect and sm.exists( effect ) then
					effect:stopImmediate()
					effect:destroy()
				end
			end
		end
		self.cl.worldPingMarkers[worldId][cellKey] = nil
	end
end

--[[ QuestMarker ]]
function QuestEntityManager.Cl_GetNamedQuestMarker( name )
	if g_questEntityManagerClient then
		return g_questEntityManagerClient:cl_getNamedQuestMarker( name )
	end
	return nil
end









function QuestEntityManager.cl_getNamedQuestMarker( self, name )
	return self.cl.namedQuestMarkers[name]
end

function QuestEntityManager.Cl_GetActiveMainQuestMarker()
	if g_questEntityManagerClient then
		return g_questEntityManagerClient:cl_getActiveMainQuestMarker()
	end
	return nil
end

function QuestEntityManager.cl_getActiveMainQuestMarker( self )

	for name in pairs( self.cl.activeQuestMarkers ) do

		local marker = self.cl.namedQuestMarkers[name]
		if marker and marker.isMainQuest and marker.position and marker.world then
			return marker
		end
		
	end
	return nil
end

function QuestEntityManager.Cl_SetNamedQuestMarkerVisible( name, state )
	if g_questEntityManagerClient then
		g_questEntityManagerClient:cl_setNamedQuestMarkerVisible( name, state )
	end
end

function QuestEntityManager.cl_setNamedQuestMarkerVisible( self, name, state )
	if self.cl.activeQuestMarkers[name] and self.cl.activeQuestMarkers[name] == state then
		return
	end
	if state == true then
		self.cl.activeQuestMarkers[name] = state
	else
		self.cl.activeQuestMarkers[name] = nil
	end
	local questMarker = QuestEntityManager.Cl_GetNamedQuestMarker( name )
	if questMarker then
		local markerName = questMarker.questMarkerName
		if self.cl.activeQuestMarkers[name] then
			if not questMarker.host then
				WorldMarkerManager.Cl_SetWorldPosition( markerName, questMarker.position, questMarker.world )
			end
			WorldMarkerManager.Cl_ActivateMarker( markerName )
		else
			WorldMarkerManager.Cl_HideMarker( markerName )
		end
	end
end

function QuestEntityManager.client_onClientDataUpdate( self, data )
	local syncedMarkers = {}
	for name, markerData in pairs( data ) do
		syncedMarkers[#syncedMarkers+1] = name
		if self.cl.namedQuestMarkers[markerData.name] == nil then
			local isMain = markerData.isMainQuest
			local host = ( markerData.host and sm.exists( markerData.host ) ) and markerData.host or nil
			WorldMarkerManager.Cl_CreateOrUpdateMarker( name, {
				effect = "QuestMarker",
				farEffect = markerData.visibleFar and "QuestMarker_Far" or nil,
				position = markerData.position,
				world = markerData.world,
				host = host,
				hostOffset = markerData.offset,
				textureIndex = isMain and 0 or 1,
				color = isMain and sm.color.new( "798B0FF1" ) or sm.color.new( "79F1E20F" ),
				compassImage = isMain and "icon_compass_main_quest.png" or "icon_compass_side_quest.png",
			})
		elseif markerData.host then
			if sm.exists( markerData.host ) then
				WorldMarkerManager.Cl_SetHost( name, markerData.host, markerData.offset )
			else
				WorldMarkerManager.Cl_SetWorldPosition( name, markerData.position, markerData.world )
			end
		else
			WorldMarkerManager.Cl_SetWorldPosition( name, markerData.position, markerData.world )
		end

		local questMarkerData = {
			position = markerData.position,
			name = markerData.name,
			world = markerData.world,
			questMarkerName = name,
			host = markerData.host,
			offset = markerData.offset,
			isMainQuest = markerData.isMainQuest
		}
		
		self.cl.namedQuestMarkers[questMarkerData.name] = questMarkerData
		
		if self.cl.activeQuestMarkers[markerData.name] then
			WorldMarkerManager.Cl_ActivateMarker( name )
		end
	end

	for name,_ in pairs( self.cl.namedQuestMarkers ) do
		if not isAnyOf( name, syncedMarkers ) then
			WorldMarkerManager.Cl_DestroyMarker( name )
			self.cl.namedQuestMarkers[name] = nil
		end
	end
end

function QuestEntityManager.Cl_BumpHostedQuestMarker( markerName )
	if g_questEntityManagerClient then
		return g_questEntityManagerClient:cl_bumpHostedQuestMarker( markerName )
	end
	return false
end

function QuestEntityManager.cl_bumpHostedQuestMarker( self, markerName )
	if self.cl.namedQuestMarkers[markerName] ~= nil then
		local questMarkerName = markerName
		local markerData = self.cl.namedQuestMarkers[markerName]
		if markerData.host ~= nil then
			if sm.exists( markerData.host ) then
				WorldMarkerManager.Cl_SetHost( questMarkerName, markerData.host, markerData.offset )
			else
				WorldMarkerManager.Cl_SetWorldPosition( questMarkerName, markerData.position, markerData.world )
			end
			return true
		end
	end
	return false
end

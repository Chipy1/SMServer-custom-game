dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalGame.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/worlds/BaseWorld.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DrillbotManager.lua" )

DrillbotWorld = class( BaseWorld )

DrillbotWorld.executionOrder = 50

DrillbotWorld.terrainScript = "$SURVIVAL_DATA/Scripts/terrain/terrain_drillbot.lua"
DrillbotWorld.enableSurface = false
DrillbotWorld.enableAssets = true
DrillbotWorld.enableClutter = false
DrillbotWorld.enableNodes = true
DrillbotWorld.enableCreations = true
DrillbotWorld.enableHarvestables = true
DrillbotWorld.enableKinematics = true
DrillbotWorld.enableNavMesh = false
DrillbotWorld.renderMode = "underground"
DrillbotWorld.isIndoor = true
DrillbotWorld.worldBorder = false
DrillbotWorld.cellMinX = -7
DrillbotWorld.cellMaxX = 7
DrillbotWorld.cellMinY = -7
DrillbotWorld.cellMaxY = 7

local BezierSampleCount = 32
local BaseSpeed = 330

local MaxPassedDistance = 3000
local MinForwardDistance = 1200

local ArenaBounds = sm.vec3.new( 60, 8192, 20 )
local ArenaTriggerOffset = sm.vec3.new( 0, 0, 10 )

function DrillbotWorld.trigger_onEnterKillBox( self, trigger, results )
	-- New objects in the kill box
	for _,result in ipairs( results ) do
		if sm.exists( result ) then
			-- Respawn character
			if type( result ) == "Character" then
				if result:isPlayer() then
					sm.event.sendToPlayer( result:getPlayer(), "sv_e_receiveDamage", { damage = 9999, source = "shock" } )
					sm.event.sendToScriptableObject( self.sv.drillbotManager, "sv_e_playerExitedArena", result:getPlayer() )
				else
					result:getUnit():destroy()
				end
			end
			--Destroy shapes
			if type( result ) == "Body" then
				for _, shape in ipairs( result:getShapes() ) do
					sm.shape.destroyShape( shape )
				end
			end
		end
	end
end

function DrillbotWorld.trigger_onExitArena( self, trigger, characters )
	for index, character in ipairs( characters ) do
		if sm.exists( character ) and type( character ) == "Character" then
			if character:isPlayer() then
				sm.event.sendToPlayer( character:getPlayer(), "sv_e_receiveDamage", { damage = 9999, source = "shock" } )
				sm.event.sendToScriptableObject( self.sv.drillbotManager, "sv_e_playerExitedArena", character:getPlayer() )
			else
				local unit = character:getUnit()
				if unit and sm.exists( unit ) then
					local questUnitName = SafeGet( unit.publicData, "questUnitName" )
					if questUnitName and isAnyOf( questUnitName, DRILLBOT_FIGHT_ACTORS ) then
						unit:destroy()
					end
				end
			end
		end
	end
end

function DrillbotWorld.sv_createKillBox( self )

	self.arenaTrigger = sm.areaTrigger.createBox( ArenaBounds, ArenaTriggerOffset, sm.quat.identity(), sm.areaTrigger.filter.character )
	self.arenaTrigger:bindOnExit( "trigger_onExitArena" )

	-- Filter
	local filter = sm.areaTrigger.filter.character + sm.areaTrigger.filter.dynamicBody

	-- Kill effect box
	local rotation = sm.quat.identity()

	-- Kill box -Z
	local halfSize = sm.vec3.new( 8192, 8192, 512.0 )
	local position = sm.vec3.new( 0.0, 0.0, -1024.0 )
	self.killAreaTriggerNZ = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerNZ:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box +Z
	local halfSize = sm.vec3.new( 8192, 8192, 512.0 )
	local position = sm.vec3.new( 0.0, 0.0, 1024.0 )
	self.killAreaTriggerPZ = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerPZ:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box +Y
	local halfSize = sm.vec3.new( 8192, 512.0, 8192 )
	local position = sm.vec3.new( 0.0, 1024.0, 0.0 )
	self.killAreaTriggerPY = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerPY:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box -Y
	local halfSize = sm.vec3.new( 8192, 512.0, 8192 )
	local position = sm.vec3.new( 0.0, -1024.0, 0.0 )
	self.killAreaTriggerNY = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerNY:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box +X
	local halfSize = sm.vec3.new( 512.0, 8192, 8192 )
	local position = sm.vec3.new( 1024.0, 0.0, 0.0 )
	self.killAreaTriggerPX = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerPX:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box -X
	local halfSize = sm.vec3.new( 512.0, 8192, 8192 )
	local position = sm.vec3.new( -1024.0, 0.0, 0.0 )
	self.killAreaTriggerNX = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerNX:bindOnEnter( "trigger_onEnterKillBox" )
end

function ProcessTrack( mainTrack )
	if not mainTrack then
		return nil
	end

	local trackData = {}
	local distances = {}
	local durations = {}
	local easings = {}
	local segments = {}
	local acceleration = {}
	local speed = {}

	local nodes = mainTrack
	if nodes and #nodes > 1 then
		for i = 1, #nodes-1 do
			local points = {}
			local rotations = {}
			points[#points+1] = nodes[i].position
			rotations[#rotations+1] = nodes[i].rotation
			for _, tangent in ipairs( nodes[i].tangents ) do
				points[#points+1] = tangent.position
			end
			points[#points+1] = nodes[i+1].position
			rotations[#rotations+1] = nodes[i+1].rotation

			local precalculatedDistances = nil
			if nodes[i].tangents  then
				precalculatedDistances = nodes[i].tangents.precalculatedDistances
			end
			segments[#segments+1] = { points = points, rotations = rotations, precalculatedDistances = precalculatedDistances }
		end

		-- Used for progress calculation
		distances[1] = 0
		for _, segment in ipairs( segments ) do
			local length
				if segment.precalculatedDistances then
					length = segment.precalculatedDistances[#segment.precalculatedDistances]
				elseif #segment.points == 2 then
					length = ( segment.points[1] - segment.points[2] ):length()
				else
					assert( false, "bezier segment missing precalculatedDistances" )
				end
			
			distances[#distances+1] = distances[#distances] + length
		end

		durations[1] = 0
		for i = 1, #nodes - 1 do
			local distanceSegment = distances[i+1] - distances[i]

			local s = distanceSegment -- displacement at end
			local u = (nodes[i].speed or 1) * BaseSpeed -- initial speed
			local vEnd = (nodes[i+1].speed or 1) * BaseSpeed -- final speed

			local tEnd = s / ( u + 0.5 * ( vEnd - u ) ) -- arrival time
			durations[#durations+1] = durations[#durations] + tEnd

			local a = ( vEnd - u ) / tEnd -- the constant acceleration from this key to next
			acceleration[i] = a
			speed[i] = nodes[i].speed or 1

			local easing = nodes[i].easing or "linear"
			easings[#easings+1] = sm.util.easingFunctionIds[easing]
		end

		trackData.nodes = nodes
		trackData.durations = durations
		trackData.easings = easings
		trackData.distances = distances
		trackData.segments = segments
		trackData.acceleration = acceleration
		trackData.speed = speed
	end

	return trackData
end

function GetSegmentProgress( segmentIndex, time, trackData )
	segmentIndex =  math.min( math.max( segmentIndex, 1 ), #trackData.segments )
	local segmentLength = trackData.distances[segmentIndex+1] - trackData.distances[segmentIndex]
	
	local u = trackData.speed[segmentIndex] * BaseSpeed --segmentStartSpeed
	local t = time - trackData.durations[segmentIndex]--timeInSegment
	t = max( 0, t )
	local a = trackData.acceleration[segmentIndex] --segmentAcceleration
	local s = u * t + 0.5 * a * math.pow( t, 2 )  --displacement
	local segmentProgress = s / segmentLength
	
	segmentProgress = finite( segmentProgress ) and segmentProgress or 1.0
	segmentProgress = saturate( segmentProgress )
	
	segmentProgress = sm.util.easing( trackData.easings[segmentIndex], segmentProgress )

	return segmentProgress
end

function TrackTransform( time, trackData )
	local transform
	local segmentIndex = BinarySearchInterval( trackData.durations, time )
	local segmentProgress = 0
	if segmentIndex then
		segmentIndex =  math.min( math.max( segmentIndex, 1 ), #trackData.segments )

		segmentProgress = GetSegmentProgress( segmentIndex, time, trackData )

		local curveParam = segmentProgress
		
		if trackData.segments[segmentIndex].precalculatedDistances then
			curveParam = ProgressToCurveParam( segmentProgress, trackData.segments[segmentIndex].precalculatedDistances )
		end

		local kinematicPosition = BezierPosition( trackData.segments[segmentIndex].points, curveParam )
		local kinematicRotation = sm.quat.slerp( trackData.segments[segmentIndex].rotations[1], trackData.segments[segmentIndex].rotations[2], segmentProgress )

		transform = { position = kinematicPosition, rotation = kinematicRotation }
	end
	return transform, segmentIndex, segmentProgress
end

function DrillbotWorld.Sv_QueueTrackRequest( request )
	if g_DrillbotWorld then
		g_DrillbotWorld:sv_queueTrackRequest( request )
	end
end

function DrillbotWorld.sv_queueTrackRequest( self, request )
	table.insert( self.sv.saved.requestQueue, request )
	sm.storage.save( STORAGE_CHANNEL_DRILLBOT_WORLD, self.sv.saved ) -- save changes to queue
end

function DrillbotWorld.sv_setState( self, state )
	if self.sv.saved.trackState ~= state then
		self.sv.saved.trackState = state
		self.world.publicData.trackState = self.sv.saved.trackState
		sm.storage.save( STORAGE_CHANNEL_DRILLBOT_WORLD, self.sv.saved ) -- save changes to trackState
	end
end

function DrillbotWorld.sv_initSaveData( self )
	self.sv.saved = {
		requestQueue = {},
		trackState = DrillbotTrackTypes.Intro,
		instances = {}, -- represents an instance of a piece in use on the track, contains a piece id, a track index where the instance is located, and an id for effect lifetime
		time = 0, -- the time of the track, must be adjusted if the track changes in order to preserve our relative position to the instances on the track
		instanceId = 0, -- counter for instance ids
		activated = false -- whether the drillbot fight is active
	}
	sm.storage.save( STORAGE_CHANNEL_DRILLBOT_WORLD, self.sv.saved )
end

function DrillbotWorld.server_onCreate( self )
	BaseWorld.server_onCreate( self )

	g_DrillbotWorld = self
	self.world.publicData.type = "DrillbotWorld"

	self.sv.pieces = {} -- unpacked prefabs, contains track and effect nodes

	self.sv.mainTrack = {} -- stiched together track nodes of active pieces
	self.sv.mainTrackData = nil -- when main track changes it is reevaluated into this

	self.sv.drillbotManager = sm.scriptableObject.createScriptableObject( sm.uuid.new( "dc2ca337-59a8-45c0-9019-1ac0925413d8" ), nil, self.world )

	self.sv.saved = sm.storage.load( STORAGE_CHANNEL_DRILLBOT_WORLD )
	if not self.sv.saved then
		self:sv_initSaveData()
	end
	self.world.publicData.trackState = self.sv.saved.trackState

	self.network:setClientData( { activated = self.sv.saved.activated }, 2 )

	self.sv.updateTrack = false

	self:sv_createKillBox()
end

function DrillbotWorld.initialTrackPieces( self )
	-- setup instances, initial setup if no saved data
	if IsEmptyTable( self.sv.saved.instances ) then
		-- Start with Intro pieces for initial drillbot appearance
		for i = 1, 2 do
			table.insert( self.sv.saved.instances, {
				piece = { pieceType = DrillbotTrackTypes.Intro, id = i },
				trackIndex = 0,
				id = self.sv.saved.instanceId
			} )
			self.sv.saved.instanceId = self.sv.saved.instanceId + 1
		end
	end
end

function DrillbotWorld.sv_e_resetWorld( self )
	self:sv_initSaveData()
	
	self.sv.mainTrack = {}
	self.sv.mainTrackData = nil
	
	self.world.publicData.trackState = self.sv.saved.trackState
	
	self:initialTrackPieces()
	self.sv.updateTrack = true
end


function DrillbotWorld.sv_worldReady( self )
	BaseWorld.server_onTerrainCreated( self )
	DrillbotManager.Sv_WorldReady( self.world )
	
	-- event to quest
	QuestManager.Sv_SendEvent( "event.quest_bosstrain.world_ready", { world = self.world } )
end

function DrillbotWorld.server_onTerrainCreated( self )
	self:sv_worldReady()
end

function DrillbotWorld.server_onTerrainLoaded( self )
	self:sv_worldReady()
end



function DrillbotWorld.server_onUnload( self )
	sm.storage.save( STORAGE_CHANNEL_DRILLBOT_WORLD, self.sv.saved )
end

function ProcessPieceGroup( outPieces, pieceGroup, groupType )
	for i, groupPiece in ipairs( pieceGroup ) do
		local newPiece = {
			effects = {},
			track = nil,
			legsAnimation = groupPiece.legsAnimation,
			bodyAnimation = groupPiece.bodyAnimation,
			pieceType = groupType
		}
		for _, node in ipairs( groupPiece.nodes ) do
			if isAnyOf( "EFFECT", node.tags ) then
				newPiece.effects[#newPiece.effects+1] = node
			elseif isAnyOf( "TRACK", node.tags ) or isAnyOf( "BOSSTRAINTRACK",  node.tags ) then
				newPiece.track = node.params.track.track.track
				newPiece.length = 0
				for trackIndex, trackNode in ipairs( newPiece.track ) do
					-- remove unnecessary data
					if trackNode.easing == "linear" then
						trackNode.easing = nil -- linear easing by default
					end
					trackNode.duration = nil -- always use speed
					trackNode.durationFromSpeed = nil -- assume true
					trackNode.inheritDuration = nil -- no duration

					trackNode.position = Vec3IfArray( trackNode.position ) * node.scale
					trackNode.rotation = sm.quat.fromEuler( Vec3IfArray( trackNode.rotation ) )
					if trackNode.tangents then
						for _, tangent in ipairs( trackNode.tangents ) do
							tangent.position = Vec3IfArray( tangent.position ) * node.scale
							tangent.rotation = sm.quat.fromEuler( Vec3IfArray( tangent.rotation ) )
						end

						-- precalculate tables for bezier distances
						local table = {}
						if newPiece.track[trackIndex+1] ~= nil then
							
							local previousPosition = trackNode.position
							local totalLength = 0
							local curve = { trackNode.position }
							for _, tangent in ipairs( trackNode.tangents ) do
								curve[#curve+1] = tangent.position
							end
							curve[#curve+1] = newPiece.track[trackIndex+1].position * node.scale

							table[1] = 0
							for sample = 2, BezierSampleCount, 1 do
								local t = saturate( ( sample - 1 ) / ( BezierSampleCount - 1 ) )

								local position = BezierPosition( curve, t )
								local diff = previousPosition - position
								totalLength = totalLength + diff:length()
								table[sample] = totalLength
								previousPosition = position
							end
							trackNode.tangents.precalculatedDistances = table

							newPiece.length = newPiece.length + totalLength
						end
					else
						trackNode.tangents = {}
						if newPiece.track[trackIndex+1] ~= nil then
							newPiece.length = newPiece.length
							local nextPosition = newPiece.track[trackIndex+1].position * node.scale
							local diff = nextPosition - trackNode.position
							newPiece.length = newPiece.length + diff:length()
						end
					end
				end
			end
		end
		outPieces[i] = newPiece
	end
end

function ProcessPieces( prefabs )
	local pieces = {
		CombatTrackPieces = {},
		EnterTrackPieces = {},
		RollercoasterTrackPieces = {},
		DownTrackPieces = {},
		EndTrackPieces = {},
		CinematicTrackPieces = {},
		DownTransitionTrackPieces = {},
		EndTransitionTrackPieces = {},
		IntroTrackPieces = {}
	}

	ProcessPieceGroup( pieces.CombatTrackPieces, prefabs.CombatTrackPrefabs, DrillbotTrackTypes.Combat )
	ProcessPieceGroup( pieces.EnterTrackPieces, prefabs.EnterTrackPrefabs, DrillbotTrackTypes.Enter )
	ProcessPieceGroup( pieces.RollercoasterTrackPieces, prefabs.RollercoasterTrackPrefabs, DrillbotTrackTypes.Rollercoaster )
	ProcessPieceGroup( pieces.DownTrackPieces, prefabs.DownTrackPrefabs, DrillbotTrackTypes.Down )
	ProcessPieceGroup( pieces.EndTrackPieces, prefabs.EndTrackPrefabs, DrillbotTrackTypes.End )
	ProcessPieceGroup( pieces.CinematicTrackPieces, prefabs.CinematicTrackPrefabs, DrillbotTrackTypes.Cinematic )
	ProcessPieceGroup( pieces.DownTransitionTrackPieces, prefabs.DownTransitionTrackPrefabs, DrillbotTrackTypes.DownTransition )
	ProcessPieceGroup( pieces.EndTransitionTrackPieces, prefabs.EndTransitionTrackPrefabs, DrillbotTrackTypes.EndTransition )
	ProcessPieceGroup( pieces.IntroTrackPieces, prefabs.IntroTrackPrefabs, DrillbotTrackTypes.Intro )

	return pieces
end

function ProgressToCurveParam( progression, precalculatedDistances )
	local totalDistance = precalculatedDistances[#precalculatedDistances]
	local distance = progression * totalDistance
	if distance >= totalDistance then
		return 1
	end
	if distance <= 0 then
		return 0
	end

	for i = BezierSampleCount, 1, -1 do

		if precalculatedDistances[i] < distance then
			local p = inverseLerp( precalculatedDistances[i], precalculatedDistances[i+1], distance )

			local t1 =  saturate( ( i - 1 ) / ( BezierSampleCount - 1 ) )
			local t2 =  saturate( ( i ) / ( BezierSampleCount - 1 ) )

			local t = lerp( t1, t2, p )
			return t
		end
	end
end

function DrillbotWorld.sv_pickNextPiece( self )
	if self.sv.saved.requestQueue[1] and self.sv.saved.requestQueue[1].type == "piece" then
		local type = self.sv.saved.requestQueue[1].pieceType
		local id = self.sv.saved.requestQueue[1].id
		table.remove( self.sv.saved.requestQueue, 1 )
		return { pieceType = type, id = id }
	end


	if self.sv.saved.trackState == nil then
		self:sv_setState( DrillbotTrackTypes.Combat )
	end

	local keystring = DrillbotTrackNames[self.sv.saved.trackState].."TrackPieces"
	if self.sv.pieces[keystring] then
		local num = #self.sv.pieces[keystring]
		return { pieceType = self.sv.saved.trackState, id = math.random(num) }
	end
	assert( false, "track piece picking failed", keystring )
end

function DrillbotWorld.server_onFixedUpdate( self, timeStep )

	if #self.sv.saved.requestQueue > 0 then
		while #self.sv.saved.requestQueue > 0 do --  to jump through sequential state changes (should not happen though?)
			if self.sv.saved.requestQueue[1].type == "state" then
				self:sv_setState( self.sv.saved.requestQueue[1].state )
			else
				break
			end
			table.remove( self.sv.saved.requestQueue, 1 )
		end
	end

	local updateTrack = self.sv.updateTrack
	local finalTimeAdjustment = 0

	-- TODO do this in terrain load callback
	if not self.sv.pieces or IsEmptyTable( self.sv.pieces ) then 
		local prefabs = sm.storage.load( STORAGE_CHANNEL_DRILLBOT_PREFABS )
		if prefabs then
			self.sv.pieces = ProcessPieces( prefabs )
			self.cl.pieces = self.sv.pieces

			self:initialTrackPieces()
			updateTrack = true
		end

		sm.storage.save( STORAGE_CHANNEL_DRILLBOT_WORLD, self.sv.saved )
	end

	if not self.sv.saved.activated and not updateTrack then
		return
	end

	-- update
	if #self.sv.saved.instances > 0 and self.sv.mainTrackData and self.sv.pieces then
		self.sv.saved.time = self.sv.saved.time + timeStep

		local segmentIndex = BinarySearchInterval( self.sv.mainTrackData.durations,  self.sv.saved.time )
		local segmentProgress = GetSegmentProgress( segmentIndex, self.sv.saved.time, self.sv.mainTrackData )
		assert( (segmentProgress <= 1) and (segmentProgress >= 0) )

		local from = self.sv.mainTrackData.distances[segmentIndex]
		local to = self.sv.mainTrackData.distances[segmentIndex+1]
		local currentDistance = lerp( from, to, segmentProgress )
		local remainingDistance = self.sv.mainTrackData.distances[#self.sv.mainTrackData.distances] - currentDistance

		local currentInstanceIndex = 1
		for i, instance in ipairs( self.sv.saved.instances ) do
			if self.sv.mainTrackData.durations[instance.trackIndex] > self.sv.saved.time then
				break
			end
			currentInstanceIndex = i
		end

		if currentDistance > MaxPassedDistance and #self.sv.saved.instances >= 2 then
			-- need to remove instances until within limit
			local instanceRemoveCount = 0
			for i, instance in ipairs( self.sv.saved.instances ) do

				if i >= currentInstanceIndex - 1 then -- do not try to remove the instance right behind our current instance
					break
				end

				currentDistance = currentDistance - self:sv_getPieceData( instance.piece ).length

				instanceRemoveCount = i
				if currentDistance < MaxPassedDistance then
					break
				end
			end

			if instanceRemoveCount > 0 then
				for i = 1, instanceRemoveCount, 1 do
					local newTrackBeginIndex = self.sv.saved.instances[2].trackIndex

					
					local timeAdjustment = ( finalTimeAdjustment + self.sv.mainTrackData.durations[newTrackBeginIndex] )
					if self.sv.saved.time - timeAdjustment < 0 then
						break
					end

					finalTimeAdjustment = timeAdjustment

					
					table.remove( self.sv.saved.instances, 1 )
					updateTrack = true
				end
			end
		end

		-- TODO Fix hitching that happens the first time we add an instance here, not an issue when loading only on init
		if remainingDistance < MinForwardDistance then
			-- we are about to reach the end of the track, pick a new piece to append

			local instance = {
				piece = self:sv_pickNextPiece(), --pick this depending on mode
				trackIndex = 0, -- this will be set when track is rebuilt
				id = self.sv.saved.instanceId
			}
			self.sv.saved.instanceId = self.sv.saved.instanceId + 1

			table.insert( self.sv.saved.instances, instance )
			updateTrack = true
		end
		
	end

	if updateTrack then
		self.sv.saved.time = self.sv.saved.time - finalTimeAdjustment

		--loop over the order of instances in the track, rebuild the track, assign track indexes to instances
		self.sv.mainTrack = {}
		for i, instance in ipairs(self.sv.saved.instances) do
			instance.trackIndex = max( 1, #self.sv.mainTrack )

			self:appendMainTrack( self:sv_getPieceData( instance.piece ).track, self.sv.mainTrack )
		end

		self.sv.mainTrackData = ProcessTrack( self.sv.mainTrack )

		sm.storage.save( STORAGE_CHANNEL_DRILLBOT_WORLD, self.sv.saved )

		--synchronize here
		self.sv.sectionTick = sm.game.getServerTick()
		local syncData = {
			track = self.sv.mainTrack,
			time = self.sv.saved.time,
			sectionTick = self.sv.sectionTick,
			instances = self.sv.saved.instances,
			timeAdjustment = -finalTimeAdjustment
		}
		self.network:setClientData( syncData )
	end

	if self.sv.mainTrackData and not IsEmptyTable( self.sv.saved.instances ) then
		local currentInstance = nil
		for i, instance in ipairs( self.sv.saved.instances ) do
			if self.sv.mainTrackData.durations[instance.trackIndex] > self.sv.saved.time then
				break
			end
			currentInstance = instance
		end
		local currentPiece = self:sv_getPieceData( currentInstance.piece )

		self.world.publicData.piece = currentPiece
		self.world.publicData.pieceId = currentInstance.piece.id
		self.world.publicData.instanceId = currentInstance.id
	end

end

function DrillbotWorld.server_onCellCreated( self, x, y )
	BaseWorld.server_onCellCreated( self, x, y )

end

function DrillbotWorld.server_onCellLoaded( self, x, y )
	BaseWorld.server_onCellLoaded( self, x, y )

end

function DrillbotWorld.sv_getPieceData( self, pieceInfo )
	local keystring = DrillbotTrackNames[pieceInfo.pieceType].."TrackPieces"
	if self.sv.pieces[keystring] and self.sv.pieces[keystring][pieceInfo.id] then
		return self.sv.pieces[keystring][pieceInfo.id]
	else
		assert( false, "could not find current piece" )
	end
end

---------------------------- client

function DrillbotWorld.cl_getPieceData( self, pieceInfo )
	local keystring = DrillbotTrackNames[pieceInfo.pieceType].."TrackPieces"
	if self.cl.pieces[keystring] and self.cl.pieces[keystring][pieceInfo.id] then
		return self.cl.pieces[keystring][pieceInfo.id]
	else
		assert( false, "could not find current piece" )
	end
end

function DrillbotWorld.client_onCreate( self )
	BaseWorld.client_onCreate( self )

	self.world.clientPublicData.isLiftPlacable = false
	self.world.clientPublicData.currentTrackPieceProgression = 0
	self.world.clientPublicData.currentPiece = nil
	self.world.clientPublicData.defaultRenderSetting = "$GAME_DATA/Render/RenderSettings/World/world_drillbot.rendersettings"
	self.world.clientPublicData.ambience = "audio:event:/amb/2D/underground_train+audio:event:/music/boss_drillbot"


	self.cl.pieces = nil
	self.cl.instances = {} -- instances received from server, ids used to create effects in self.cl.instanceEffects
	self.cl.instanceEffects = {} -- holds the active effects for a particular instance on the track

	self.cl.mainTrack = {} -- stiched together track nodes of active pieces
	self.cl.mainTrackData = nil -- when main track changes it is reevaluated into this

	self.cl.time = 0
end

function DrillbotWorld.cl_onTerrainReady( self )
	DrillbotManager.Cl_WorldReady( self.world )

	if not self.cl.pieces and not sm.isHost then -- initial setup
		local prefabs = sm.storage.load( STORAGE_CHANNEL_DRILLBOT_PREFABS )
		if prefabs then
			self.cl.pieces = ProcessPieces( prefabs )

			-- consume client data if received early
			if self.cl.queuedClientData then
				self:client_onClientDataUpdate( self.cl.queuedClientData, 1 )
				self.cl.queuedClientData = nil
			end
		end
	end
end

function DrillbotWorld.client_onTerrainCreated( self )
	self:cl_onTerrainReady()
end
function DrillbotWorld.client_onTerrainLoaded( self )
	self:cl_onTerrainReady()
end

function DrillbotWorld.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		if self.cl.pieces == nil then
			-- if we haven't loaded our pieces yet we aren't ready to use this data yet, save it for later
			self.cl.queuedClientData = data
			return
		end
	
		self.cl.mainTrack = data.track
		self.cl.instances = data.instances
		
		if sm.isHost then
			self.cl.mainTrackData = self.sv.mainTrackData
		else
			self.cl.mainTrackData = ProcessTrack( data.track )
		end
		
		local TimeStep = 0.025
		local tickDiff = sm.game.getServerTick() - data.sectionTick
		self.cl.desiredTime = data.time + ( tickDiff * TimeStep )

		if self.cl.initialData == false then
			self.cl.lerpDuration = 1
			self.cl.lerpTimer = 0

			self.cl.time = self.cl.time + data.timeAdjustment
		else
			self.cl.time = self.cl.desiredTime --set time instantly on initialdata, otherwise lerp with 
		end
	
		for _, value in pairs( self.cl.instanceEffects ) do
			value.inUse = false
		end
	
		for _, instance in ipairs( self.cl.instances ) do
			local instancePiece = self:cl_getPieceData( instance.piece )
			if self.cl.instanceEffects[instance.id] == nil then
				local effects = {}
				for j, effectNode in ipairs( instancePiece.effects ) do
					effects[j] = sm.effect.createEffect( effectNode.params.effect.name )
					effects[j]:setWorld( self.world )
					effects[j]:setScale( effectNode.scale )
					if effectNode.params.effect.params then
						for k,v in kvpairs( effectNode.params.effect.params ) do
							effects[j]:setParameter( k, v )
						end
					end
					effects[j]:start()
				end
				self.cl.instanceEffects[instance.id] = { inUse = true, effects = effects }
			else
				self.cl.instanceEffects[instance.id].inUse = true
			end
		end
	
		for key, value in pairs( self.cl.instanceEffects ) do
			if value.inUse == false then
				for _, effect in ipairs( value.effects ) do
					effect:destroy()
				end
				self.cl.instanceEffects[key] = nil
			end
		end

		if self.cl.initialData == false then
			self.cl.initialData = true
		end
	elseif channel == 2 then
		self.cl.activated = data.activated
	end
end

function DrillbotWorld.client_onDestroy( self )
	--TODO destroy effects somewhere, this is not called
	for key, value in pairs( self.cl.instanceEffects ) do
		for _, effect in ipairs( value.effects ) do
			effect:destroy()
		end
		self.cl.instanceEffects[key] = nil
	end
end

function DrillbotWorld.appendMainTrack( self, track, mainTrack )
	if #mainTrack == 0 then
		for i = 1, #track do
			mainTrack[#mainTrack+1] = DeepCopy( track[i] )
		end
	else
		local trackEndPosition = mainTrack[#mainTrack].position
		local trackEndRotation = mainTrack[#mainTrack].rotation
		mainTrack[#mainTrack].speed = track[1].speed

		for i = 2, #track do
			local appendNode = DeepCopy( track[i] )
			appendNode.position = trackEndPosition + trackEndRotation * appendNode.position
			appendNode.rotation = trackEndRotation * appendNode.rotation
			for _, tangent in ipairs( appendNode.tangents ) do
				tangent.position = trackEndPosition + trackEndRotation * tangent.position
				tangent.rotation = trackEndRotation * tangent.rotation
			end
			mainTrack[#mainTrack+1] = appendNode
		end
	end
end

function DrillbotWorld.client_onUpdate( self, deltaTime )
	BaseWorld.client_onUpdate( self, deltaTime )

	if (not g_drillbotManagerClientWorld) or (not g_drillbotManagerClientWorld[self.world.id]) then
		return
	end

	if not self.cl.activated then
		return
	end

	local player = sm.localPlayer.getPlayer()
	local character = player:getCharacter()
	
	if not (#self.cl.instances > 0 and self.cl.mainTrackData) then
		return
	end
	
	self.cl.time = self.cl.time + deltaTime

	local trackTransformTime = self.cl.time
	if self.cl.desiredTime ~= nil and self.cl.lerpTimer ~= nil and self.cl.lerpDuration ~= nil then
		if self.cl.lerpTimer < self.cl.lerpDuration then
			self.cl.desiredTime = self.cl.desiredTime + deltaTime
			self.cl.lerpTimer = min( self.cl.lerpTimer + deltaTime, self.cl.lerpDuration )

			local p = self.cl.lerpTimer / self.cl.lerpDuration
			trackTransformTime = lerp( self.cl.time, self.cl.desiredTime, p )
			
			if p == 1 then
				self.cl.time = self.cl.desiredTime
			end
		end
	end
	
	local transform, segmentIndex, segmentProgress = TrackTransform( trackTransformTime, self.cl.mainTrackData )

	-- calculate current piece progress
	local currentInstance = nil
	for i, instance in ipairs( self.cl.instances ) do
		if self.cl.mainTrackData.durations[instance.trackIndex] > self.cl.time then
			break
		end
		currentInstance = instance
	end

	if not currentInstance then
		if not self.cl.requestedUpdate then
			self:cl_requestUpdate()
		end
		return
	end

	local currentPiece = self:cl_getPieceData( currentInstance.piece )

	local pieceStartDistance = self.cl.mainTrackData.distances[currentInstance.trackIndex]

	local from = self.cl.mainTrackData.distances[segmentIndex]
	local to = self.cl.mainTrackData.distances[segmentIndex+1]
	local segmentDistance = lerp( from, to, segmentProgress ) - self.cl.mainTrackData.distances[segmentIndex]

	local instanceStartToSegmentStart = self.cl.mainTrackData.distances[segmentIndex] - pieceStartDistance
	local pieceProgress = ( instanceStartToSegmentStart + segmentDistance ) / currentPiece.length
	pieceProgress = saturate( pieceProgress )

	self.world.clientPublicData.currentTrackPieceProgression = pieceProgress
	self.world.clientPublicData.currentPiece = currentPiece
	self.world.clientPublicData.instanceId = currentInstance.id
	
	if self.cl.pieces == nil then
		return
	end
	
	
	local centerPosition = nil
	local managerPublicData = g_drillbotManagerClientWorld[self.world.id].scriptableObject.clientPublicData
	if managerPublicData then
		centerPosition = managerPublicData.bossfightCenter
	end
	if centerPosition == nil then
		return
	end
	
	local trackOffset = { position = -transform.position, rotation = sm.quat.inverse( transform.rotation ) }
	for _, instance in ipairs( self.cl.instances ) do
		local rootTrackNode = self.cl.mainTrackData.nodes[instance.trackIndex]
		
		local instancePiece = self:cl_getPieceData( instance.piece )
		
		for j, effect in ipairs( self.cl.instanceEffects[instance.id].effects ) do
			
			local effectNode = instancePiece.effects[j]
			local instanceEffectPosition = rootTrackNode.position + rootTrackNode.rotation * effectNode.pos
			effect:setPosition( centerPosition + trackOffset.rotation * ( trackOffset.position + instanceEffectPosition) )
			effect:setRotation( trackOffset.rotation * rootTrackNode.rotation * effectNode.rot )
		end
	end

end

function DrillbotWorld.sv_n_updateRequest( self, params )
	local syncData = {
		track = self.sv.mainTrack,
		time = self.sv.saved.time,
		sectionTick = self.sv.sectionTick,
		instances = self.sv.saved.instances,
		timeAdjustment = 0
	}
	self.network:sendToClient( params.player, "cl_n_manualUpdate", syncData )
end

function DrillbotWorld.cl_requestUpdate( self )
	self.cl.requestedUpdate = true
	self.network:sendToServer( "sv_n_updateRequest", { player = sm.localPlayer.getPlayer() } )
end

function DrillbotWorld.cl_n_manualUpdate( self, syncData )
	self:client_onClientDataUpdate( syncData, 1 )
	self.cl.requestedUpdate = false
end

function DrillbotWorld.sv_e_activate( self )
	self.sv.saved.activated = true
	sm.storage.save( STORAGE_CHANNEL_DRILLBOT_WORLD, self.sv.saved )
	self.network:setClientData( { activated = self.sv.saved.activated }, 2 )
end

function DrillbotWorld.sv_e_deactivate( self )
	self.sv.saved.activated = false
	sm.storage.save( STORAGE_CHANNEL_DRILLBOT_WORLD, self.sv.saved )
	self.network:setClientData( { activated = self.sv.saved.activated }, 2 )
end


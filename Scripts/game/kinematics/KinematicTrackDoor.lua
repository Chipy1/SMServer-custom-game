dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicBase.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

KinematicTrackDoor = class( KinematicBase )

function KinematicTrackDoor.server_onCreate( self )
	self.sv = {}
	self.sv.trackData = self:evaluateNodes( self.params.track )
	self.sv.completionFraction = clamp( self.params.completionFraction or 1.0, 0.1, 1.0 )

	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )

	local group = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag )
	group = SafeSet( group, "door", self.harvestable )
	if SafeGetExist( group, "spinner" ) then
		self.sv.spinner = group.spinner
		self.network:setClientData( { spinner = self.sv.spinner, trackData = self.sv.trackData, completionFraction = self.sv.completionFraction } )
	end
	
	if SafeGetExist( group, "sign" ) then
		sm.event.sendToHarvestable( group.sign, "sv_e_receiveDoor", self.harvestable )
	end
	TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag, group )
end

function KinematicTrackDoor.server_onFixedUpdate( self, timeStep )
	if self.sv == nil or self.sv.trackData == nil then
		return
	end

	if not self.sv.spinner then
		local group = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.params.keyTag )
		if SafeGetExist( group, "spinner") then
			self.sv.spinner = group.spinner
			self.network:setClientData( { spinner = self.sv.spinner, trackData = self.sv.trackData, completionFraction = self.sv.completionFraction } )
		end
	end
end

function KinematicTrackDoor.client_onCreate( self )
	KinematicBase.client_onCreate( self )
	self.cl = {}
	self.cl.open = false
	if self.data.kinematic then 
		self.cl.movementEffect = sm.effect.createEffect( self.data.kinematic.movementEffect or "Growlab - Kinematicspindooraudio", self.harvestable )
	else
		self.cl.movementEffect = sm.effect.createEffect( "Growlab - Kinematicspindooraudio", self.harvestable )
	end
end

function KinematicTrackDoor.client_onDestroy( self )
	self.cl.movementEffect:destroy()
end

function KinematicTrackDoor.client_onClientDataUpdate( self, clientData )
	if self.cl == nil then
		self.cl = {}
	end
	self.cl.lastProgress = 0.0
	self.cl.spinner = clientData.spinner
	self.cl.trackData = clientData.trackData
	self.cl.completionFraction = clientData.completionFraction
end

function KinematicTrackDoor.client_onFixedUpdate( self )
	if self.cl.spinner then
		if not sm.exists( self.cl.spinner ) or not self.cl.spinner.clientPublicData then
			return
		end
		local progress = self.cl.spinner.clientPublicData.progress / self.cl.completionFraction
		
		local maxDistance = self.cl.trackData.distances[#self.cl.trackData.distances]
		local distance = progress * maxDistance
		if self.cl.lastProgress ~= progress then
			if self.cl.lastProgress == 0.0 or self.cl.lastProgress == 1.0 then
				self.cl.movementEffect:start()
			end
			local soundVelocity = 0
			local currentSpeed = self.cl.spinner.clientPublicData.speed
			if self.data.kinematic then 
				if self.data.kinematic.maxSpeed == 0 then
					soundVelocity = 0
				else
					soundVelocity = clamp( math.abs( currentSpeed ) / ( self.data.kinematic.maxSpeed or 50 ), 0.0, 1.0 )
				end
			end
			self.cl.movementEffect:setParameter( "velocity", soundVelocity )
			self.harvestable.clientPublicData = { progress = progress, speed = self.cl.spinner.clientPublicData.speed }
			if progress == 1.0 then
				self.cl.open = true
				self.cl.movementEffect:stopBreakSustain()
				if self.data and self.data.lockEffect then
					sm.effect.playEffect( "Growlab - Kinematicspinnerandlatchdoor", self.harvestable.worldPosition, sm.vec3.zero(), self.harvestable.worldRotation )
				end
			elseif progress == 0.0 then
				if self.cl.open then
					self.cl.open = false
				end
				self.cl.movementEffect:stopBreakSustain()
			end
			self.harvestable.clientPublicData = { progress = progress, speed = self.cl.spinner.clientPublicData.speed, open = self.cl.open }
		end
		self.cl.lastProgress = progress
		self:trackUpdate( distance, self.cl.trackData )
	end
end

function KinematicTrackDoor.evaluateNodes( self, trackParam )
	if not trackParam then
		return nil
	end

	-- Translate track nodes into world space
	local nodes
	local worldPosition = self.harvestable.initialPosition
	local worldRotation = self.harvestable.initialRotation
	local trackData = trackParam.track
	if trackData and trackData.track then
		local worldTrack = {}
		for i, trackNode in ipairs( trackData.track ) do
			local trackPos = Vec3IfArray( trackNode.position )
			local trackRotEuler = Vec3IfArray( trackNode.rotation )
			local trackRotQuat = sm.quat.fromEuler( trackRotEuler )

			local worldTrackNode = {}
			worldTrackNode.position = worldPosition + worldRotation * ( trackPos * self.harvestable:getScale() )
			worldTrackNode.rotation = worldRotation * trackRotQuat

			local worldTangents = {}
			if trackNode.tangents then
				for _, tangent in ipairs( trackNode.tangents ) do
					local tangentPos = sm.vec3.new( tangent.position[1], tangent.position[2], tangent.position[3] )
					local tangentRotEuler = sm.vec3.new( tangent.rotation[1], tangent.rotation[2], tangent.rotation[3] )
					local tangentRotQuat = sm.quat.fromEuler( tangentRotEuler )

					local worldTangent = {}
					worldTangent.position = worldPosition + worldRotation * ( tangentPos * self.harvestable:getScale() )
					worldTangent.rotation = worldRotation * tangentRotQuat
					worldTangents[#worldTangents+1] = worldTangent
				end
			end
			worldTrackNode.tangents = worldTangents

			worldTrack[#worldTrack+1] = worldTrackNode
		end
		nodes = worldTrack
	end

	-- Extract segment information
	local distances = {}
	local segments = {}
	if nodes and #nodes > 1 then
		for i = 1, #nodes-1 do
			local points = {}
			local rotations = {}
			points[#points+1] = nodes[i].position
			rotations[#rotations+1] = nodes[i].rotation
			for _, tangent in ipairs( nodes[i].tangents ) do
				points[#points+1] = tangent.position
				rotations[#rotations+1] = tangent.rotation
			end
			points[#points+1] = nodes[i+1].position
			rotations[#rotations+1] = nodes[i+1].rotation

			segments[#segments+1] = { points = points, rotations = rotations }
		end

		-- Used for progress calculation
		distances[1] = 0
		for _, segment in ipairs( segments ) do
			local length = EstimateBezierLength( segment.points, 32 )
			distances[#distances+1] = distances[#distances] + length
		end
	else
		return nil
	end

	local trackData = {}
	trackData.nodes = nodes
	trackData.distances = distances
	trackData.segments = segments

	return trackData
end

function KinematicTrackDoor.trackUpdate( self, distance, trackData )
	local kinematicPosition, kinematicRotation = self:getTransform( distance, trackData )
	self.harvestable:setPosition( kinematicPosition )
	self.harvestable:setRotation( kinematicRotation )
end

function KinematicTrackDoor.getTransform( self, distance, trackData )
	if trackData and trackData.segments and #trackData.segments >= 1 then

		local distances = trackData.distances
		local segments = trackData.segments

		-- Find current segment
		local currentSegment = BinarySearchInterval( distances, distance )
		if currentSegment then
			currentSegment =  math.min( math.max( currentSegment, 1 ), #trackData.segments )
			local fromDistance = distances[currentSegment]
			local toDistance = distances[currentSegment+1]

			local inbetweenProgress = math.min( math.max( ( distance - fromDistance ) / ( toDistance - fromDistance ), 0.0 ), 1.0 )
			inbetweenProgress = finite( inbetweenProgress ) and inbetweenProgress or 1.0

			local kinematicPosition = BezierPosition( segments[currentSegment].points, inbetweenProgress )
			local kinematicRotation = BezierRotation( segments[currentSegment].rotations, inbetweenProgress )
			return kinematicPosition, kinematicRotation
		end
	end
	return self.harvestable.worldPosition, self.harvestable.worldRotation
end
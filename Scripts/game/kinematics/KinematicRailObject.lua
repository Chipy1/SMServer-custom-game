dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicBase.lua" )

dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

KinematicRailObject = class( KinematicBase )

local SpeedForEffect = 6.0
local SpeedForStop = 0.1
local PotatoProjectileVelocity = 130.0
local PotatoProjectileMass = 3.0
local MinimumImpactSoundVelocity = 8.0

function KinematicRailObject.sv_init( self )
	self.sv = {}
	self.sv.trackData, self.sv.trackSettings = self:evaluateNodes( self.params.track )
	self.sv.updateData = {}
	self.sv.updateData.distance = 0
	self.sv.updateData.speed = 0
	self.sv.updateData.acceleration = 0

	self.sv.characterCollisionIds = {}
	self.sv.unlocked = true
end

function KinematicRailObject.server_onCreate( self )
	KinematicRailObject.sv_init( self )

	self.sv.initialHash = self.harvestable:getInitialHash()

	if g_tileStorageManager then
		self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )

		if self.params and self.params.lockTag and self.params.lockTag ~= "" then
			self.sv.unlocked = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.lockTag ) == true
		end

		local stored = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash )
		if stored then
			self.sv.updateData.speed = stored.speed or 0.0
			self.sv.updateData.acceleration = 0
			self.sv.updateData.distance = stored.distance
			local kinematicPosition, kinematicRotation = self:getTransform( self.sv.updateData.distance, self.sv.trackData )
			self.harvestable:setPosition( kinematicPosition )
			self.harvestable:setRotation( kinematicRotation )
			self.network:setClientData( self.sv.updateData, 2 )
		end
	end

	self.network:setClientData( { params = self.params }, 1 )
	self.harvestable.publicData = { isRailKinematic = true }
end

function KinematicRailObject.server_onUnload( self )
	local stored = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash ) or {}
	stored.distance = self.sv.updateData.distance
	stored.speed = self.sv.updateData.speed
	TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash, stored )
end

function KinematicRailObject.server_onFixedUpdate( self )
	if self.sv == nil then
		return
	end
	if self.sv.updateData.speed ~= 0.0 then
		self.sv.updateData = self:trackUpdate( self.sv.trackData, self.sv.trackSettings, self.sv.updateData )
	end
	if not self.sv.unlocked then
		if g_tileStorageManager then
			if self.params and self.params.lockTag and self.params.lockTag ~= "" then
				self.sv.unlocked = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.lockTag ) == true
			end
		end
		if not self.sv.unlocked then return end
	end
	if not IsEmptyTable( self.sv.characterCollisionIds ) then
		local currentTick = sm.game.getCurrentTick()
		removeFromArray( self.sv.characterCollisionIds, function( value ) return currentTick - value.tick >= 40 end )
	end
end

function KinematicRailObject.sv_n_lockKinematic( self )
	if self.params and self.params.kinematicEventTrigger then
		g_kinematicManager:sv_activate( self.sv.tileStorageKey, self.params.kinematicEventTrigger )
	end
	if g_tileStorageManager then
		local stored = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash ) or {}
		stored.distance = self.sv.trackData.distances[#self.sv.trackData.distances]
		TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_STORAGE_TABLE, self.sv.initialHash, stored )
		if self.params and self.params.keyTag and self.params.keyTag ~= "" then
			TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.keyTag, true )
		end
	end
end

function KinematicRailObject.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( other ) then
		return
	end
	local vVelImpact = ( selfPointVelocity - otherPointVelocity )
	local fVelImpact = vVelImpact:length()
	local vDirImpact = vVelImpact / fVelImpact
	local fCosImpactAngle = vDirImpact:dot( -collisionNormal )

	local massSelf = self.harvestable.mass
	local massOther = 0
	if type( other ) == "Shape" and other.body:isDynamic() then
		massOther = other.body.mass
	elseif type( other ) == "Character" then
		if not other:isPlayer() then
			if selfPointVelocity:length2() >= RAIL_KINEMATIC_UNSTOPPABLE_THRESHOLD * RAIL_KINEMATIC_UNSTOPPABLE_THRESHOLD then
				-- Kinematic won't stop for units when traveling fast
				return
			end
		end
		massOther = other.mass
		local charId = other.id
		for _,collisionInfo in ipairs( self.sv.characterCollisionIds ) do
			if collisionInfo.id == charId then
				return
			end
		end
		self.sv.characterCollisionIds[#self.sv.characterCollisionIds+1] = { id = charId, tick = sm.game.getServerTick() }
	end

	if fCosImpactAngle > 0.5 then -- At least 30 degree impact angle
		local fVel0Self = selfPointVelocity:dot( vDirImpact )
		local fVel0Other = otherPointVelocity:dot( vDirImpact )
		local fVel1Self
		local fRestitution = 0.3

		if massOther > 0 then
			fVel1Self = ( fRestitution * massOther * ( fVel0Other - fVel0Self ) + massSelf * fVel0Self + massOther * fVel0Other ) / ( massSelf + massOther )
		else
			-- Simplified with massSelf as 0, massOther as 1
			fVel1Self = fRestitution * ( fVel0Other - fVel0Self ) + fVel0Other
		end

		-- Change in velocity from collision
		local fVelDiffSelf = ( fVel1Self - fVel0Self )

		local forwardDirection = self:getDirection( self.sv.updateData.distance, self.sv.trackData )
		local dotAngle = forwardDirection:dot( vDirImpact )
		self.sv.updateData.speed = self.sv.updateData.speed + dotAngle * fVelDiffSelf
		self.sv.updateData.serverTick = sm.game.getServerTick()
		self.network:setClientData( self.sv.updateData, 2 )
	end
end

function KinematicRailObject.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if attacker.character then
		if self.data and self.data.soundEffect then
			sm.effect.playEffect( self.data.soundEffect, self.harvestable.position )
		end
		local forwardDirection = self:getDirection( self.sv.updateData.distance, self.sv.trackData )

		local MeleeImpulse = self.data and self.data.meleeImpulse and self.data.meleeImpulse or 15.0
		self.sv.updateData.speed = self.sv.updateData.speed + forwardDirection:dot( hitDirection ) * MeleeImpulse
		self.sv.updateData.serverTick = sm.game.getServerTick()
		self.network:setClientData( self.sv.updateData, 2 )
	end
end

function KinematicRailObject.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid, projectileMass )
	if damage <= 0 then
		return
	end
	local hitDirection = hitVelocity:safeNormalize( sm.vec3.new( 0, 0, 0 ) )

	local forwardDirection = self:getDirection( self.sv.updateData.distance, self.sv.trackData )
	local velocityMultiplier = 1.0
	local massMultiplier = 1.0
	if not isAnyOf( projectileUuid, g_potatoProjectiles ) then
		-- Use potato projectiles as a benchmark for scaling other projectiles
		velocityMultiplier = math.min( hitVelocity:length() / PotatoProjectileVelocity, 1.0 )
		massMultiplier = math.min( projectileMass / PotatoProjectileMass, 1.0 )
	end

	local ProjectileImpulse = self.data and self.data.projectileImpulse and self.data.projectileImpulse or 5.0
	self.sv.updateData.speed = self.sv.updateData.speed + forwardDirection:dot( hitDirection ) * ProjectileImpulse * velocityMultiplier * massMultiplier
	self.sv.updateData.serverTick = sm.game.getServerTick()
	self.network:setClientData( self.sv.updateData, 2 )
end

function KinematicRailObject.client_onCreate( self )
	KinematicBase.client_onCreate( self )
	self.cl = {}
	self.cl.updateData = {}
	self.cl.updateData.distance = 0
	self.cl.updateData.speed = 0
	self.cl.updateData.acceleration = 0
	self.cl.previousSpeed = 0
	self.cl.maxSpeed = self.data.maxSpeed or 70.0
	local effectName = self.data.movementEffect or "Growlab - Kinematicrailsparks"
	local effectOffsets = self.data.movementEffectOffsets
	self.cl.railEffects = {}
	if effectOffsets ~= nil then
		for _,offset in ipairs( effectOffsets ) do
			self.cl.railEffects[#self.cl.railEffects+1] = sm.effect.createEffect( effectName, self.harvestable )
			self.cl.railEffects[#self.cl.railEffects]:setOffsetPosition( sm.vec3.new( offset.x, offset.y, offset.z ) )
		end
	else
		self.cl.railEffects[#self.cl.railEffects+1] = sm.effect.createEffect( effectName, self.harvestable )
	end
	self.cl.lastPosition = self.harvestable.worldPosition
	self.cl.effectActive = false
end

function KinematicRailObject.client_onUpdate( self )
	for _,effect in ipairs( self.cl.railEffects ) do
		if self.cl.updateData.speed ~= self.cl.previousSpeed then
			effect:setParameter( "velocity", clamp( math.abs( self.cl.updateData.speed ) / self.cl.maxSpeed, 0, 1 ) )
			if ( self.cl.previousSpeed < 0.0 and self.cl.updateData.speed > 0.0 ) or ( self.cl.previousSpeed > 0.0 and self.cl.updateData.speed < 0.0 ) then
				sm.effect.playEffect( "Impact - Single", self.harvestable.worldPosition, nil, nil, nil, { Material = 22, Velocity_max_50 = math.max( math.abs( self.cl.updateData.speed ), MinimumImpactSoundVelocity ) } )
			end
		end
	end
	self.cl.previousSpeed = self.cl.updateData.speed
end

function KinematicRailObject.client_onDestroy( self )
	for _,effect in ipairs( self.cl.railEffects ) do
		effect:destroy()
	end
end

function KinematicRailObject.client_onClientDataUpdate( self, clientData, channel )
	if self.cl == nil then
		self.cl = {}
	end

	if channel == 1 then
		if not sm.isHost then
			self.params = clientData.params
		end
		self.cl.trackData, self.cl.trackSettings = self:evaluateNodes( self.params.track )
	elseif channel == 2 then
		self.cl.updateData.speed = clientData.speed
		self.cl.updateData.catchupTick = clientData.serverTick
		if clientData.distance ~= 0.0 then
			self.cl.updateData.distance = clientData.distance
		end
		
		local kinematicPosition, kinematicRotation = self:getTransform( self.cl.updateData.distance, self.cl.trackData )
		self.harvestable:setPosition( kinematicPosition )
		self.harvestable:setRotation( kinematicRotation )
	end
end

function KinematicRailObject.cl_setEffectState( self, active )
	self.cl.effectActive = active
	if active then
		for _,effect in ipairs( self.cl.railEffects ) do
			effect:start()
		end
	else
		for _,effect in ipairs( self.cl.railEffects ) do
			effect:stopBreakSustain()
		end
	end
end

function KinematicRailObject.client_onMelee( self, hitPos, attacker, damage, power, hitNormal )
	if type( attacker ) == "Player" then
		if self.cl.effectActive then
			self.cl.effectActive = false
			for _,effect in ipairs( self.cl.railEffects ) do
				if sm.exists( effect ) then
					effect:stopBreakSustain()
				end
			end
		end
	end
end

function KinematicRailObject.client_onFixedUpdate( self )
	if self.cl.updateData.speed == 0.0 then
		return
	end

	local missedTicks = 1
	local estimatedServerTick = sm.game.getServerTick()
	if self.cl.updateData.catchupTick then
		missedTicks = math.min( math.max( estimatedServerTick - self.cl.updateData.catchupTick, 0 ), 40 )
		self.cl.updateData.catchupTick = self.cl.updateData.catchupTick + missedTicks
	end
	
	local maxDistance = self.cl.trackData.distances[#self.cl.trackData.distances]
	local previousDistance = self.cl.updateData.distance

	if missedTicks > 0 then
		for i = 1, missedTicks do
			self.cl.updateData = self:trackUpdate( self.cl.trackData, self.cl.trackSettings, self.cl.updateData )
		end
	else
		self.cl.updateData = self:trackUpdate( self.cl.trackData, self.cl.trackSettings, self.cl.updateData )
	end
	
	if not self.cl.effectActive and previousDistance ~= self.cl.updateData.distance and math.abs( self.cl.updateData.speed ) >= SpeedForEffect then
		self:cl_setEffectState( true )
	elseif self.cl.effectActive and math.abs( self.cl.updateData.speed ) < SpeedForStop then
		self:cl_setEffectState( false )
	end

	if previousDistance ~= self.cl.updateData.distance and self.cl.updateData.distance >= maxDistance then
		if self.cl.updateData.endReached then
			if sm.isHost then
				self.network:sendToServer( "sv_n_lockKinematic" )
			end
			if self.data.endEffectOffsets then
				for _,offset in ipairs( self.data.endEffectOffsets ) do
					local effectPos = self.harvestable.worldPosition + self.harvestable.worldRotation * sm.vec3.new( offset.x, offset.y, offset.z )
					sm.effect.playEffect( "Growlab - Kinematicrailfinnishconnect", effectPos, sm.vec3.zero(), self.harvestable.worldRotation )
				end
			else
				sm.effect.playEffect( "Growlab - Kinematicrailfinnishconnect", self.harvestable.worldPosition, sm.vec3.zero(), self.harvestable.worldRotation )
			end
		end
	end
end

function KinematicRailObject.trackUpdate( self, trackData, trackSettings, updateData )
	local TimeStep = 0.025
	local Gravity = self.data and self.data.gravity and self.data.gravity or GRAVITY
	local Friction = self.data and self.data.friction and self.data.friction or 0.15
	local Restitution = self.data and self.data.restitution and self.data.restitution or 0.35
	local MaxSpeed = self.data and self.data.maxSpeed and self.data.maxSpeed or 70.0
	local OnlyForward = self.params and self.params.onlyForward and self.params.onlyForward or false
	local maxDistance = trackData.distances[#trackData.distances]
	local previousDistance = updateData.distance
	updateData.endReached = false

	-- Slope acceleration
	local forwardDirection = self:getDirection( updateData.distance, trackData )
	local slope = forwardDirection:dot( sm.vec3.new( 0, 0, 1 ) )
	local slopeRadians = -math.asin( slope )

	local slopeAcc =  Gravity * math.sin( slopeRadians )
	if ( updateData.distance >= maxDistance and sign( slopeAcc ) > 0 ) or ( updateData.distance <= 0 and sign( slopeAcc ) < 0 ) then
		-- No acceleration towards dead ends
		slopeAcc = 0.0
	end

	local frictionAcc =  Friction * Gravity * math.cos( slopeRadians )
	updateData.speed = updateData.speed + slopeAcc * TimeStep
	updateData.speed = sign( updateData.speed ) * math.max( math.abs( updateData.speed ) - frictionAcc * TimeStep, 0.0 )

	-- Generic acceleration
	updateData.speed = updateData.speed + updateData.acceleration * TimeStep

	-- Clamp speed
	updateData.speed = sign( updateData.speed ) * math.min( MaxSpeed, math.abs( updateData.speed ) )

	-- Change direction at end of track
	local preTraveledSpeed = 0.0
	local changed = false
	if not trackSettings.loop then
		if updateData.distance + updateData.speed * TimeStep > maxDistance then
			preTraveledSpeed = -math.abs( ( maxDistance - updateData.distance ) / TimeStep ) * Restitution
			updateData.speed = math.abs( updateData.speed ) * -1 * Restitution
			updateData.distance = maxDistance
			if OnlyForward then
				updateData.endReached = true
			else
				changed = true
			end

		elseif updateData.distance + updateData.speed * TimeStep < 0 then
			preTraveledSpeed = math.abs( ( 0 - updateData.distance ) / TimeStep ) * Restitution
			updateData.speed = math.abs( updateData.speed ) * Restitution
			updateData.distance = 0
		end
	end

	-- Restrict movement backward based on setting
	updateData.speed = OnlyForward and math.max( updateData.speed, 0.0 ) or updateData.speed

	-- Update transform on the track
	local effectiveSpeed = updateData.speed - preTraveledSpeed
	effectiveSpeed = sign( effectiveSpeed ) == sign( updateData.speed ) and effectiveSpeed or 0.0
	if effectiveSpeed >= FLT_EPSILON or effectiveSpeed <= -FLT_EPSILON then
		if trackSettings.loop then
			updateData.distance = ( updateData.distance + effectiveSpeed * TimeStep ) % maxDistance
		else
			updateData.distance = clamp( updateData.distance + effectiveSpeed * TimeStep, 0, maxDistance  )
		end
	end
	if not sm.isServerMode() and previousDistance ~= updateData.distance then
		local kinematicPosition, kinematicRotation = self:getTransform( updateData.distance, trackData )
		self.harvestable:setPosition( kinematicPosition )
		self.harvestable:setRotation( kinematicRotation )
	end

	return updateData
end

function KinematicRailObject.evaluateNodes( self, trackParam )
	local trackSettings = {}
	if not trackParam then
		return nil, trackSettings
	end

	-- Translate track nodes into world space
	local nodes
	local worldPosition = self.harvestable.initialPosition
	local worldRotation = self.harvestable.initialRotation
	local trackParamData = trackParam.track
	if trackParamData and trackParamData.track then
		local worldTrack = {}
		for i, trackNode in ipairs( trackParamData.track ) do
			local trackPos = Vec3IfArray( trackNode.position )
			local trackRotEuler = Vec3IfArray( trackNode.rotation )
			local trackRotQuat = sm.quat.fromEuler( trackRotEuler )

			local worldTrackNode = {}
			worldTrackNode.position = worldPosition + worldRotation * ( trackPos * self.harvestable:getScale() )
			worldTrackNode.rotation = worldRotation * trackRotQuat

			local worldTangents = {}
			if trackNode.tangents then
				for _, tangent in ipairs( trackNode.tangents ) do
					local tangentPos = Vec3IfArray( tangent.position )
					local tangentRotEuler = Vec3IfArray( tangent.rotation )
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
	local shortestDistance = math.huge
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
			shortestDistance = math.min( shortestDistance, length )
		end
	else
		return nil, trackSettings
	end

	local trackData = {}
	trackData.nodes = nodes
	trackData.distances = distances
	trackData.segments = segments
	trackData.shortestDistance = shortestDistance

	if trackParamData then
		trackSettings.loop = trackParamData.loop
	end

	return trackData, trackSettings
end

function KinematicRailObject.getTransform( self, distance, trackData )
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

function KinematicRailObject.getDirection( self, distance, trackData )

	local minStep = FLT_EPSILON * 10000
	local step = math.max( minStep, trackData.shortestDistance * 0.5 )
	local backPosition, _ = self:getTransform( distance - step, trackData )
	local frontPosition, _ = self:getTransform( distance + step, trackData )
	local forwardDirection = ( frontPosition - backPosition ):safeNormalize( sm.vec3.zero() )

	if forwardDirection == sm.vec3.zero() then
		-- Fallback to harvestable forward rotation
		local _, rotation = self:getTransform( distance, trackData )
		forwardDirection = rotation * sm.vec3.new( 0, 0, -1 )
	end

	--sm.debugDraw.addArrow( "kinematicForward" .. tostring( self.harvestable.id ), self.harvestable.worldPosition, self.harvestable.worldPosition + forwardDirection, sm.color.new( 1, 0, 0 ) )

	return forwardDirection
end
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/SwimMoveState.lua" )

IdleRoamSwimState = class( BaseState )

local MaxSwimTickTime = 40 * 10 -- Abort swimming if stuck
local DefaultRoamStartTimeMin = 40 * 4
local DefaultRoamStartTimeMax = 40 * 8

local DefaultTetherRadius = 20.0 -- Allowed roam area around the home position
local DefaultRoamCenterRadius = 7.0 -- Roam sphere radius to select a new position from
local DefaultCenterOffset = 5.0 -- Offset the roam sphere in the character direction
local DefaultMinMoveDistance = 3.0
local DefaultMaxMoveDistance = DefaultCenterOffset + DefaultRoamCenterRadius

function IdleRoamSwimState.sv_onCreate( self, unit, homePosition, roamStartTimeMin, roamStartTimeMax )
	self.unit = unit
	self.homePosition = homePosition or self.unit.character.worldPosition

	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Roam
	self.roamStartTimeMin = roamStartTimeMin or DefaultRoamStartTimeMin
	self.roamStartTimeMax = roamStartTimeMax or DefaultRoamStartTimeMax

	self.roamTimer = Timer()
	self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
	self.roamTetherRadius = DefaultTetherRadius
	self.roamCenterRadius = DefaultRoamCenterRadius
	self.roamCenterOffset = DefaultCenterOffset
	self.roamMinMoveDistance = DefaultMinMoveDistance
	self.roamMaxMoveDistance = DefaultMaxMoveDistance

	self.swimMoveState = SwimMoveState()
	self.swimMoveState:sv_onCreate( unit )
	self.swimMoveState.debugName = "swimMoveState"
	self.swimMoveState:sv_setDestination( self.homePosition )

	self.swimTimeoutTimer = Timer()
	self.swimTimeoutTimer:start( MaxSwimTickTime )

	self.currentState = self.idleState
end

function IdleRoamSwimState.sv_setMovementType( self, movementType )
	self.swimMoveState:sv_setMovementType( movementType )
end

function IdleRoamSwimState.sv_calculateNewDestination( self )

	local currentPosition = self.unit.character.worldPosition
	local destination = self.homePosition

	-- Calculate a sphere to roam within
	local roamCenterDirection = self.unit:getCurrentMovementDirection()
	if not self.unit.character:isDiving() then
		-- Move the roam center down to same level if not underwater
		roamCenterDirection.z = math.min( roamCenterDirection.z, 0 )
		roamCenterDirection:safeNormalize( sm.vec3.new( 0, 0, -1 ) )
	end
	local roamSphereCenter = self.unit.character.worldPosition + roamCenterDirection * self.roamCenterOffset
	-- Clamp the roam sphere to fit within the tether radius
	if ( roamSphereCenter - self.homePosition ):length2() + self.roamCenterRadius > self.roamMaxMoveDistance * self.roamMaxMoveDistance then
		roamSphereCenter = self.homePosition + ( roamSphereCenter - self.homePosition ):safeNormalize( sm.vec3.zero() ) * math.max( self.roamTetherRadius - self.roamCenterRadius, 0.0 )
	end

	-- Select a random destination inside the roam sphere
	local randomYawPitchEuler = sm.vec3.new( math.random(), math.random(), 0 ) * 360
	local randomDirection = sm.quat.fromEuler( randomYawPitchEuler ) * sm.vec3.new( 0, 1, 0 )
	destination = roamSphereCenter + randomDirection * self.roamCenterRadius
	-- Clamp min/max distances
	if ( destination - currentPosition ):length2() < self.roamMinMoveDistance * self.roamMinMoveDistance then
		destination = currentPosition + ( destination - currentPosition ):safeNormalize( sm.vec3.zero() ) * self.roamMinMoveDistance
	end
	if ( destination - currentPosition ):length2() > self.roamMaxMoveDistance * self.roamMaxMoveDistance then
		destination = currentPosition + ( destination - currentPosition ):safeNormalize( sm.vec3.zero() ) * self.roamMaxMoveDistance
	end

	-- Check for obstacle
	local hitObstacle, resultObstacle = sm.physics.spherecast( currentPosition, destination, self.unit.character:getRadius(), self.unit.character, sm.physics.filter.default )
	if hitObstacle then
		-- Hit obstacle
		destination = resultObstacle.pointWorld - resultObstacle.directionWorld:safeNormalize( sm.vec3.zero() ) * self.unit.character:getRadius()
	end
	-- Check for water surface
	local hitWater, resultWater = sm.physics.raycast( destination, currentPosition, self.unit.character, sm.physics.filter.waterArea )
	if hitWater then
		-- Hit water surface
		destination.z = resultWater.pointWorld.z
	end

	self.swimMoveState:sv_setDestination( destination )
end

--[[API functions]]

function IdleRoamSwimState.start( self )
	self.currentState:stop()
	self.currentState = self.idleState
	self.currentState:start()
	self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
	self.swimTimeoutTimer:reset()
end

function IdleRoamSwimState.stop( self )
	self.currentState:stop()
end

function IdleRoamSwimState.onFixedUpdate( self, dt )
	self.currentState:onFixedUpdate( dt )

	local prevState = self.currentState
	if not self.unit.character:isTumbling() then
		local done, result = self.currentState:isDone()
		if self.currentState == self.idleState then
			self.roamTimer:tick()
			if self.roamTimer:done() and result ~= "started" then
				self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
				-- Set random destination
				self:sv_calculateNewDestination()
				self.currentState = self.swimMoveState
			end
		elseif self.currentState == self.swimMoveState then
			self.swimTimeoutTimer:tick()
			if done or self.swimTimeoutTimer:done() then
				self.currentState = self.idleState
				self.swimTimeoutTimer:reset()
			end
		end
	else
		-- Stay idle while tumbling
		self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
		self.currentState = self.idleState
	end

	if self.currentState ~= prevState then
		prevState:stop()
		self.currentState:start()
	end
end

function IdleRoamSwimState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function IdleRoamSwimState.isDone( self )
	return self.currentState:isDone()
end

function IdleRoamSwimState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function IdleRoamSwimState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function IdleRoamSwimState.getMovementType( self )
	return self.currentState:getMovementType()
end

function IdleRoamSwimState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function IdleRoamSwimState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end
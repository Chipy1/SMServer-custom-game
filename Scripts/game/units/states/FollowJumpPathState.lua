dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/JumpMoveState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

FollowJumpPathState = class( BaseState )

-- State specific functions

function FollowJumpPathState.sv_onCreate( self, unit )
	self.unit = unit

	-- Move state
	self.jumpMoveState = JumpMoveState()
	self.jumpMoveState:sv_onCreate( self.unit )
	self.jumpMoveState.debugName = "jumpMoveState"

	self.movementType = "walk"
	self.sharpTurnTimer = Timer()
	self.sharpTurnTimer:reset()
	self.sharpTurnTickTime = 20
end

function FollowJumpPathState.sv_onDestroy( self ) end

function FollowJumpPathState.sv_setMovementType( self, movementType )
	self.movementType = movementType
end

function FollowJumpPathState.sv_setPath( self, path )
	self.path = path

	if self.path and #self.path > 1 then
		-- Used for spline calculation
		self.distances = {}
		self.distances[1] = 0
		for i = 2,#self.path do
			self.distances[i] = self.distances[i - 1] + ( self.path[i] - self.path[i - 1] ):length()
		end

		local closest = closestPointInLines( self.path, self.unit.character.worldPosition )
		self.segmentLength = closest.len

		self.targetPosition = self.unit.character.worldPosition
		self:sv_updateProgress()

		return true
	end
	return false
end

-- AiState common interface

function FollowJumpPathState.start( self )
	if not self.path or #self.path < 2 then
		print( "FollowJumpPathState for unit", self.unit.id, "does not have enough nodes to start" )
		return
	end

	local closest = closestPointInLines( self.path, self.unit.character.worldPosition )

	self.segmentLength = closest.len

	self.targetPosition = self.unit.character.worldPosition
	self:sv_updateProgress()

	self.jumpMoveState:sv_setDirection( self.unit:getCurrentMovementDirection() )
	self.jumpMoveState:start()

	self.started = true
end

function FollowJumpPathState.stop( self )
	self.started = false

	self.jumpMoveState:stop()

	self.targetPosition = nil
	self.segmentLength = nil
	self.done = nil
end

function FollowJumpPathState.onFixedUpdate( self, timeStep )
	if not self.started then return end

	if ( self.targetPosition - self.unit.character.worldPosition ):length2() > 0.25 then

		local fromToTarget = self.targetPosition - self.unit.character.worldPosition
		local flatFromToTarget = sm.vec3.new( fromToTarget.x, fromToTarget.y, 0.0 )
		local desiredDirection = self.unit:getCurrentMovementDirection()
		if flatFromToTarget:length2() >= FLT_EPSILON * FLT_EPSILON then
			desiredDirection = flatFromToTarget:normalize()
		end

		self.jumpMoveState:sv_setDirection( desiredDirection )

		if self.unit:getCurrentMovementDirection():dot( desiredDirection ) < 0.86602540378 then --cos(30deg)
			self.sharpTurnTimer:tick()
			if self.sharpTurnTimer.count > self.sharpTurnTickTime then
				self.jumpMoveState:sv_setMovementType( "stand" )
			elseif self.sharpTurnTimer.count > self.sharpTurnTickTime * 0.5 then
				self.jumpMoveState:sv_setMovementType( "walk" )
			end
		else
			self.sharpTurnTimer:reset()
			self.jumpMoveState:sv_setMovementType( self.movementType )
		end
	else
		self.jumpMoveState:sv_setMovementType( "stand" )
	end

	self.jumpMoveState:onFixedUpdate( timeStep )
end

function FollowJumpPathState.onUnitUpdate( self, dt )
	if not self.started then return end

	-- Update progess
	self:sv_updateProgress()
end

function FollowJumpPathState.isDone( self )
	return self.done ~= nil, self.done
end

function FollowJumpPathState.getMovementDirection( self )
	return self.jumpMoveState:getMovementDirection()
end

function FollowJumpPathState.getFacingDirection( self )
	return self.jumpMoveState:getFacingDirection()
end

function FollowJumpPathState.getMovementType( self )
	return self.jumpMoveState:getMovementType()
end

function FollowJumpPathState.getWantsJump( self )
	return self.jumpMoveState:getWantsJump()
end

function FollowJumpPathState.getWantsCrouch( self )
	return self.jumpMoveState:getWantsCrouch()
end

-- Private

function FollowJumpPathState.sv_updateProgress( self )
	local totalLength, lines = lengthOfLines( self.path )
	if totalLength == 0 then
		return
	end

	if #self.path > 2 then
		local res = closestPointInLinesSkipFirst( self.path, self.unit.character.worldPosition )
		local distToIndex2 = self.path[2] - self.unit.character.worldPosition
		local distToIndex2Flat = sm.vec3.new( distToIndex2.x, distToIndex2.y, 0.0 ):length()

		if res.i == 2 and ( res.t > 0.0 or distToIndex2Flat < 1.5 ) then
			self.targetPosition = self.path[3]

			local pt, t, len = closestPointOnLineSegment( self.path[2], self.path[3], self.unit.character.worldPosition )
			local fromToSegment = pt - self.unit.character.worldPosition
			local flatFromToSegment = sm.vec3.new( fromToSegment.x, fromToSegment.y, 0.0 )

			self.distanceToPath = flatFromToSegment:length()
		else
			self.targetPosition = self.path[2]
			self.distanceToPath = distToIndex2Flat
		end
	elseif #self.path == 2 then
		self.targetPosition = self.path[2]

		local distToIndex2 = self.path[2] - self.unit.character.worldPosition
		local distToIndex2Flat = sm.vec3.new( distToIndex2.x, distToIndex2.y, 0.0 ):length()

		self.distanceToPath = distToIndex2Flat

	elseif #self.path == 1 then
		self.targetPosition = self.path[#self.path]
		self.distanceToPath = 1000.0
	else
		self.distanceToPath = 1000.0
	end

	if #self.path ~= 0 then
		local fromToDestination = self.path[#self.path] - self.unit.character.worldPosition
		local flatFromToDestination = sm.vec3.new( fromToDestination.x, fromToDestination.y, 0.0 )

		if flatFromToDestination:length2() < 1.0 then
			self.done = "arrived"
		else
			self.done = nil
		end
	else
		self.done = "failed"
	end
end
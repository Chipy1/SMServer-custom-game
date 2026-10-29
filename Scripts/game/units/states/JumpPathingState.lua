dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/JumpMoveState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/FollowJumpPathState.lua" )

JumpPathingState = class( PathingState )

local StandTolerance = 1.0
local WalkTolerance = 2.0

-- State specific functions

function JumpPathingState.sv_onCreate( self, unit )
	self.unit = unit

	self.movementDirection = sm.vec3.new( 0, 1, 0 )
	self.destination = nil
	self.done = nil

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Jump path state
	self.followJumpPathState = FollowJumpPathState()
	self.followJumpPathState:sv_onCreate( unit )
	self.followJumpPathState.debugName = "followJumpPathState"

	-- Move state
	self.jumpMoveState = JumpMoveState()
	self.jumpMoveState:sv_onCreate( self.unit )
	self.jumpMoveState.debugName = "jumpMoveState"

	self.progressTimeout = 5.0 -- seconds without progress
	self.ticksWithoutProgress = 0
	self.lastProgressPosition = self.unit.character.worldPosition

	self.currentState = self.idleState
end

function JumpPathingState.sv_setTimeout( self, progressTimeout )
	self.progressTimeout = progressTimeout
end

function JumpPathingState.sv_setMovementType( self, movementType )
	self.followJumpPathState:sv_setMovementType( movementType )
	self.jumpMoveState.movementType = movementType
end

function JumpPathingState.sv_setDestination( self, toPosition )
	self.destination = toPosition
	self.hasNewDestination = true
end

function JumpPathingState.sv_updatePath( self )
	local path = sm.pathfinder.getPath( self.unit.character, self.destination )
	self.mainPath = {}
	self.mainPath[1] = self.unit.character.worldPosition
	for _, link in ipairs( path ) do
		local pathPosition = link.toNode:getPosition() + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
		if ( pathPosition - self.mainPath[#self.mainPath] ):length() > 0 then
			self.mainPath[#self.mainPath+1] = pathPosition
		end
	end
	if ( self.destination - self.mainPath[#self.mainPath] ):length() > 0 then
		self.mainPath[#self.mainPath+1] = self.destination
	end

	-- Tweak path by finding shortcuts when entering and leaving the node network
	if #self.mainPath > 2 then

		-- Attempt to shortcut the first step
		local firstShortcut
		--if ( self.mainPath[2] - self.mainPath[3] ):length() > 0 then
		--	local closest = closestPointInLines( { self.mainPath[2], self.mainPath[3] }, self.unit.character.worldPosition )
		--	if sm.ai.directPathAvailable( self.unit, closest.pt, ( closest.pt - self.unit.character.worldPosition ):length() ) then
		--		firstShortcut = closest.pt
		--	end
		--end

		-- Check for shortcut on the final step
		local finalShortcut
		if ( self.mainPath[#self.mainPath-2] - self.mainPath[#self.mainPath-1] ):length() > 0 then
			local closest = closestPointInLines( { self.mainPath[#self.mainPath-2], self.mainPath[#self.mainPath-1] }, self.destination )
			finalShortcut = closest.pt
		end

		local allowShortcut = true
		if firstShortcut and finalShortcut then
			if ( finalShortcut - firstShortcut ):length() == 0 then
				allowShortcut = false
			end
		end
		if allowShortcut then
			if firstShortcut and ( firstShortcut - self.mainPath[3] ):length() > 0 and ( firstShortcut - self.mainPath[1] ):length() > 0 then
				self.mainPath[2] = firstShortcut
			end
			if finalShortcut and ( finalShortcut - self.mainPath[#self.mainPath-2] ):length() > 0 and ( finalShortcut - self.mainPath[#self.mainPath] ):length() > 0 then
				self.mainPath[#self.mainPath-1] = finalShortcut
			end
		end
	end

	self.followJumpPathState:sv_setPath( self.mainPath )
end

--[[API functions]]

function JumpPathingState.start( self )
	self.started = true
	self.currentState:stop()
	self.currentState = self.idleState
	self.currentState:start()
	self.done = nil
	self.lastProgressPosition = self.unit.character.worldPosition
	self.ticksWithoutProgress = 0
end

function JumpPathingState.stop( self )
	self.started = false
	self.currentState:stop()
end

function JumpPathingState.onFixedUpdate( self, timeStep )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onFixedUpdate( timeStep )
	end

	if self.hasNewDestination then
		self:sv_updatePath()
		self.done = nil
		self.hasNewDestination = nil
	end

	local movementSpeed = self.unit.character:getCurrentMovementSpeed()
	local updateInterval = 0.3 -- tweakable, % of timeout
	local progressUpdateDistance = movementSpeed * ( self.progressTimeout * updateInterval )
	local flatProgressDelta = self.lastProgressPosition - self.unit.character.worldPosition
	flatProgressDelta.z = 0
	local flatDistanceTraveled2 = flatProgressDelta:length2()
	if flatDistanceTraveled2 >= progressUpdateDistance * progressUpdateDistance then
		self.lastProgressPosition = self.unit.character.worldPosition
		self.ticksWithoutProgress = 0
	else
		self.ticksWithoutProgress = self.ticksWithoutProgress + 1
	end
	local timedOut = ( self.ticksWithoutProgress / 40 ) >= self.progressTimeout

	local destinationDistance = 0
	local destinationDirection = sm.vec3.new( 0, 1, 0 )
	local hasDirectPath = false
	if self.destination then
		local toDestination = ( self.destination - self.unit.character.worldPosition )
		toDestination.z = 0
		destinationDistance = toDestination:length()
		destinationDirection = toDestination:safeNormalize( destinationDirection )
		--hasDirectPath = sm.ai.directPathAvailable( self.unit, self.destination, math.min( destinationDistance, 16.0 ) )
	end

	local nextState = self.currentState
	if destinationDistance > StandTolerance then
		if timedOut then
			nextState = self.idleState
			self.done = "failed"
		else
			if hasDirectPath then
				self.jumpMoveState:sv_setDirection( destinationDirection )
				nextState = self.jumpMoveState
			else
				nextState = self.followJumpPathState
			end
		end
	else
		nextState = self.idleState
		self.done = "arrived"
	end

	if self.currentState ~= nextState then
		self.currentState:stop()
		self.currentState = nextState
		self.currentState:start()
	end
end

function JumpPathingState.onUnitUpdate( self, dt )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end
end

function JumpPathingState.isDone( self )
	if self.done then
		return true, self.done
	end
	return false, ""
end

function JumpPathingState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function JumpPathingState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function JumpPathingState.getMovementType( self )
	if not self.unit.character:isOnGround() then
		if self.destination then
			local diff = self.destination - self.unit.character.worldPosition
			diff.z = 0
			local distance2 = diff:length2()
			if distance2 > WalkTolerance * WalkTolerance then
				return "sprint"
			elseif distance2 > StandTolerance * StandTolerance then
				return "walk"
			end
		end
	end
	return "stand"
end

function JumpPathingState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function JumpPathingState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end

-- Inherited from PathingState, but unimplemented for jump pathing
function JumpPathingState.sv_setWaterAvoidance( self, waterAvoidance ) end

function JumpPathingState.sv_setCliffAvoidance( self, cliffAvoidance ) end

function JumpPathingState.sv_setWhiskerAvoidance( self, whiskerAvoidance ) end

function JumpPathingState.sv_setTolerance( self, tolerance ) end
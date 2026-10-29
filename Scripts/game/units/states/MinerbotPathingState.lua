dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/FlyPathingState.lua" )
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"

MinerbotPathingState = class( PathingState )

local MinBoostTickTime = 5
local MaxBoostTickTime = 20
local MinBoostImpulse = 8000
local MaxBoostImpulse = 22500
local BoostSpreadDeg = 50.0
local BoostActivationDistance = 3.0
local SprintActivationDistance = 14.0
local BoostEffectFractionThreshold = 0.5

local AbortApproachTickTime = 1.0 * 40
local ExpectedTravelVelocity = 8.0
local TravelTimeMargin = 2.0 -- seconds


-- State specific functions

function MinerbotPathingState.sv_onCreate( self, unit )
	self.unit = unit
	self.destination = self.unit.character.worldPosition
	self.tolerance = 1.0

	self.boostTimer = Timer()
	self.boostTimer:start( MinBoostTickTime )

	self.abortApproachTimer = Timer()
	self.abortApproachTimer:start( AbortApproachTickTime )

	self.abortPathingTimer = Timer()
	self.abortPathingTimer:start( 5 )

	self.flyPathingState = FlyPathingState()
	self.flyPathingState:sv_onCreate( self.unit )
	self.flyPathingState:sv_setMovementType( "walk" )
	self.flyPathingState:sv_setPathNodeSize( 3 )
	self.flyPathingState.debugName = "flyPathingState"

	self.movementType = "walk"
	self.facingDirection = sm.vec3.new( 0, 1, 0 )
	self.movementDirection = sm.vec3.new( 0, 1, 0 )
end

function MinerbotPathingState.sv_onDestroy( self )
	self.flyPathingState:sv_onDestroy()
end

function MinerbotPathingState.sv_setDestination( self, toPosition )
	self.destination = toPosition
	self.flyPathingState:sv_setDestination( toPosition )

	local destinationDistance = ( self.destination - self.unit.character.worldPosition ):length2()
	local expectedTravelSeconds = ( destinationDistance / ExpectedTravelVelocity ) + TravelTimeMargin
	self.abortPathingTimer:start( expectedTravelSeconds * 40 )
end

-- AiState common interface

function MinerbotPathingState.start( self )
	self.done = nil
	self.flyPathingState:start()
	self.abortApproachTimer:reset()
	self.abortPathingTimer:reset()
end

function MinerbotPathingState.stop( self )
	self.flyPathingState:stop()
end


function MinerbotPathingState.onFixedUpdate( self, timeStep )
	local character = self.unit.character
	if not sm.exists( character ) then return end

	local done, _ = self.flyPathingState:isDone()
	if not done then
		self.flyPathingState:onFixedUpdate( timeStep )
	end

	-- Update boost
	local fromTo = self.destination - character.worldPosition
	local destinationDistance = fromTo:length()
	local shouldSprint = false
	local shouldBoost = false
	local subDirection = self.flyPathingState:sv_getSubDirection()
	if subDirection then
		shouldSprint = destinationDistance >= SprintActivationDistance
		shouldBoost = destinationDistance >= BoostActivationDistance
		if shouldBoost then
			self.boostTimer:tick()
			if self.boostTimer:done() then
				local boostFraction = self.boostTimer.ticks / MaxBoostTickTime
				local boostImpulse = lerp( MinBoostImpulse, MaxBoostImpulse, boostFraction )
				self.boostTimer:start( math.random( MinBoostTickTime, MaxBoostTickTime ) )
				subDirection = ( sm.noise.gunSpread( subDirection, BoostSpreadDeg ) ):safeNormalize( sm.vec3.zero() )
				if subDirection:length2() > FLT_EPSILON then
					ApplyCharacterImpulse( character, subDirection, boostImpulse )
					local forward = self.facingDirection:safeNormalize( sm.vec3.new( 0, 1, 0 ) )
					local directionDeterminant = ( forward.x * subDirection.y - forward.y * subDirection.x )
					if boostFraction < BoostEffectFractionThreshold then
						if directionDeterminant > 0 then
							-- Moving right, burst left thruster
							self.unit:sendCharacterEvent( "burst01left" )
						else
							-- Moving left, burst right thruster
							self.unit:sendCharacterEvent( "burst01right" )
						end
					else
						if directionDeterminant > 0 then
							-- Moving right, burst left thruster
							self.unit:sendCharacterEvent( "burst02left" )
						else
							-- Moving left, burst right thruster
							self.unit:sendCharacterEvent( "burst02right" )
						end
					end
				end
			end
		end
	end

	-- Update movement
	if destinationDistance >= self.tolerance then
		self.facingDirection = fromTo:safeNormalize( self.flyPathingState:getFacingDirection() )
		local done, _ = self.flyPathingState:isDone()
		if done then
			self.movementDirection = fromTo:safeNormalize( self.unit:getCurrentMovementDirection() )
			self.done = "approaching"
			self.movementType = "walk"
		else
			self.movementDirection = self.flyPathingState:getMovementDirection()
			self.done = "pathing"
			self.movementType = shouldSprint and "sprint" or "walk"
		end
	else
		self.done = "arrived"
		self.facingDirection = self.unit:getCurrentFacingDirection()
		self.movementType = "stand"
		self.movementDirection = self.unit:getCurrentMovementDirection()
	end

	-- Check if pathing is stuck, time out
	if self.done == "approaching" then
		self.abortApproachTimer:tick()
	elseif self.done == "pathing" then
		self.abortPathingTimer:tick()
	end
end

function MinerbotPathingState.onUnitUpdate( self, dt )
	local done, _ = self.flyPathingState:isDone()
	if not done then
		self.flyPathingState:onUnitUpdate( dt )
	end
end

function MinerbotPathingState.isDone( self )
	if self.abortApproachTimer:done() or self.abortPathingTimer:done() then
		return true, "timedout"
	elseif isAnyOf( self.done, { "approaching", "arrived" } ) then
		return self.done == "arrived", self.done
	else
		local _, status = self.flyPathingState:isDone()
		return false, status
	end
end

function MinerbotPathingState.getMovementDirection( self )
	return self.movementDirection
end

function MinerbotPathingState.getFacingDirection( self )
	return self.facingDirection
end

function MinerbotPathingState.getMovementType( self )
	return self.movementType
end

function MinerbotPathingState.getWantsJump( self )
	return self.flyPathingState:getWantsJump()
end

function MinerbotPathingState.getWantsCrouch( self )
	return self.flyPathingState:getWantsCrouch()
end

-- Inherited from PathingState, but unimplemented for minerbot pathing
function MinerbotPathingState.sv_setTimeout( self, progressTimeout ) end

function MinerbotPathingState.sv_setMovementType( self, movementType ) end

function MinerbotPathingState.sv_setWaterAvoidance( self, waterAvoidance ) end

function MinerbotPathingState.sv_setCliffAvoidance( self, cliffAvoidance ) end

function MinerbotPathingState.sv_setWhiskerAvoidance( self, whiskerAvoidance ) end

function MinerbotPathingState.sv_setTolerance( self, tolerance ) end
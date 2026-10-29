dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

IdleRoamState = class( BaseState )

local DefaultRoamStartTimeMin = 40 * 4
local DefaultRoamStartTimeMax = 40 * 8

function IdleRoamState.sv_onCreate( self, unit, homePosition, roamStartTimeMin, roamStartTimeMax )
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
	self.roamState = self.unit:createState( "roam" )
	self.roamState.debugName = "roamState"
	self.roamState.tetherPosition = self.homePosition
	self.roamState.customData = { onUnitUpdateOnly = true }

	self.currentState = self.idleState
end

--[[API functions]]

function IdleRoamState.start( self )
	self.currentState:start()
end

function IdleRoamState.stop( self )
	self.currentState:stop()
end

function IdleRoamState.onFixedUpdate( self, dt )
	if not self.currentState.customData or not self.currentState.customData.onUnitUpdateOnly then
		self.currentState:onFixedUpdate( dt )
	end

	local prevState = self.currentState
	if not self.unit.character:isTumbling() then
		local done, result = self.currentState:isDone()
		if self.currentState == self.idleState then
			self.roamTimer:tick()
			if self.roamTimer:done() and result ~= "started" then
				self.roamTimer:start( math.random( self.roamStartTimeMin, self.roamStartTimeMax ) )
				self.currentState = self.roamState
			end
		elseif self.currentState == self.roamState then
			if done then
				self.currentState = self.idleState
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

function IdleRoamState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
	if self.currentState.customData and self.currentState.customData.onUnitUpdateOnly then
		self.currentState:onFixedUpdate( dt )
	end
end

function IdleRoamState.isDone( self )
	return self.currentState:isDone()
end

function IdleRoamState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function IdleRoamState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function IdleRoamState.getMovementType( self )
	return self.currentState:getMovementType()
end

function IdleRoamState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function IdleRoamState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

LookAroundState = class( BaseState )

local MinLookDirectionTickTime = 40 * 0.5
local MaxLookDirectionTickTime = 40 * 1.5
local LookAroundTickTime = 40 * 6.0

-- State specific functions

function LookAroundState.sv_onCreate( self, unit )
	self.unit = unit

	-- LookAt
	self.lookAtState = self.unit:createState( "positioning" )
	self.lookAtState.debugName = "lookAt"
	self.lookAtState.timeout = 3.2
	self.lookAtState.tolerance = 0.5
	self.lookAtState.avoidance = false
	self.lookAtState.movementType = "stand"

	self.newDirectionTimer = Timer()
	self.stateTimer = Timer()
end

--[[API functions]]

function LookAroundState.start( self )
	self.started = true
	self.lookAtState.desiredDirection = sm.vec3.new( 0, 1, 0 ):rotateZ( math.rad( math.random() * 360 ) )
	self.lookAtState.desiredPosition = self.unit.character.worldPosition

	self.lookAtState:start()
	self.newDirectionTimer:start( math.random( MinLookDirectionTickTime, MaxLookDirectionTickTime ) )
	self.stateTimer:start( LookAroundTickTime )

	self.unit:sendCharacterEvent( "idlealert" )
end

function LookAroundState.stop( self )
	self.started = false
	self.lookAtState:stop()
end

function LookAroundState.onFixedUpdate( self, timeStep )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	self.lookAtState:onFixedUpdate( timeStep )
	self.newDirectionTimer:tick()
	self.stateTimer:tick()
	if self.newDirectionTimer:done() then
		self.lookAtState.desiredDirection = sm.vec3.new( 0, 1, 0 ):rotateZ( math.rad( math.random() * 360 ) )
		self.lookAtState.desiredPosition = self.unit.character.worldPosition
		self.lookAtState:start()
		self.newDirectionTimer:start( math.random( MinLookDirectionTickTime, MaxLookDirectionTickTime ) )
	end
end

function LookAroundState.onUnitUpdate( self, dt )
	if not self.started then return end
	local character = self.unit.character
	if not sm.exists( character ) then return end

	self.lookAtState:onUnitUpdate( dt )
end

function LookAroundState.isDone( self )
	return self.stateTimer:done(), ""
end

function LookAroundState.getMovementDirection( self )
	return self.lookAtState:getMovementDirection()
end

function LookAroundState.getFacingDirection( self )
	return self.lookAtState:getFacingDirection()
end

function LookAroundState.getMovementType( self )
	return self.lookAtState:getMovementType()
end

function LookAroundState.getWantsJump( self )
	return self.lookAtState:getWantsJump()
end

function LookAroundState.getWantsCrouch( self )
	return self.lookAtState:getWantsCrouch()
end
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/FlyMoveState.lua" )

MinerbotUnstuckState = class( BaseState )

local UnstuckTickTime = 1.0 * 40
local UnstuckCheckDistance = 8.0

local TwoAxisAngle = math.sqrt( 2 ) / 2
local ThreeAxisAngle = math.sqrt( 3 ) / 3
local Directions = {
	--Up
	sm.vec3.new( 0, 0, 1 ),
	-- Angled Up
	sm.vec3.new( 0, TwoAxisAngle, TwoAxisAngle ),
	sm.vec3.new( ThreeAxisAngle, ThreeAxisAngle, ThreeAxisAngle ),
	sm.vec3.new( TwoAxisAngle, 0, TwoAxisAngle ),
	sm.vec3.new( ThreeAxisAngle, -ThreeAxisAngle, ThreeAxisAngle ),
	sm.vec3.new( 0, -TwoAxisAngle, TwoAxisAngle ),
	sm.vec3.new( -ThreeAxisAngle, -ThreeAxisAngle, ThreeAxisAngle ),
	sm.vec3.new( -TwoAxisAngle, 0, TwoAxisAngle ),
	sm.vec3.new( -ThreeAxisAngle, ThreeAxisAngle, ThreeAxisAngle ),
	-- Flat
	sm.vec3.new( 0, 1, 0 ),
	sm.vec3.new( TwoAxisAngle, TwoAxisAngle, 0 ),
	sm.vec3.new( 1, 0, 0 ),
	sm.vec3.new( TwoAxisAngle, -TwoAxisAngle, 0 ),
	sm.vec3.new( 0, -1, 0 ),
	sm.vec3.new( -TwoAxisAngle, -TwoAxisAngle, 0 ),
	sm.vec3.new( -1, 0, 0 ),
	sm.vec3.new( -TwoAxisAngle, TwoAxisAngle, 0 ),
	-- Angled Down
	sm.vec3.new( 0, TwoAxisAngle, -TwoAxisAngle ),
	sm.vec3.new( ThreeAxisAngle, ThreeAxisAngle, -ThreeAxisAngle ),
	sm.vec3.new( TwoAxisAngle, 0, -TwoAxisAngle ),
	sm.vec3.new( ThreeAxisAngle, -ThreeAxisAngle, -ThreeAxisAngle ),
	sm.vec3.new( 0, -TwoAxisAngle, -TwoAxisAngle ),
	sm.vec3.new( -ThreeAxisAngle, -ThreeAxisAngle, -ThreeAxisAngle ),
	sm.vec3.new( -TwoAxisAngle, 0, -TwoAxisAngle ),
	sm.vec3.new( -ThreeAxisAngle, ThreeAxisAngle, -ThreeAxisAngle ),
	-- Down
	sm.vec3.new( 0, 0, -1 )
}

-- State specific functions

function MinerbotUnstuckState.sv_onCreate( self, unit )
	self.unit = unit

	self.unstuckTimer = Timer()
	self.unstuckTimer:start( UnstuckTickTime )

	-- Movement
	self.flyMoveState = FlyMoveState()
	self.flyMoveState:sv_onCreate( self.unit )
	self.flyMoveState:sv_setMovementType( "walk" )
	self.flyMoveState.debugName = "flyMoveState"
end

function MinerbotUnstuckState.sv_selectUnstuckDirection( self )
	local castAttempts = #Directions
	local castRadius = 0.15
	local startPoint = self.unit.character.worldPosition
	local casts = {}
	for i = 1, castAttempts do
		local endPoint = startPoint + Directions[i] * UnstuckCheckDistance
		casts[#casts+1] = { type = "sphere",
							startPoint = startPoint,
							endPoint = endPoint,
							radius = castRadius,
							ignoreObject = self.unit.character }
	end
	local retTable = sm.physics.multicast( casts )

	local freeDirections = {}
	local furthestFallbackFraction = 0.0
	local furthestFallbackDirection = sm.vec3.new( 0, 0, 1 )
	for i = 1, castAttempts do
		local hit = retTable[i][1]
		local result = retTable[i][2]
		if hit then
			if result.fraction > furthestFallbackFraction then
				furthestFallbackDirection = result.directionWorld
			end
		else
			freeDirections[#freeDirections+1] = Directions[i]
		end
	end

	if #freeDirections > 0 then
		return freeDirections[math.random( 1, #freeDirections )]
	end
	return furthestFallbackDirection
end

--[[API functions]]

function MinerbotUnstuckState.start( self )
	self.started = true
	self.unstuckTimer:start( UnstuckTickTime )
	self.flyMoveState:sv_setDirection( self:sv_selectUnstuckDirection() )
	self.flyMoveState:start()
end

function MinerbotUnstuckState.stop( self )
	self.started = false
	self.flyMoveState:stop()
end

function MinerbotUnstuckState.onFixedUpdate( self, timeStep )
	local character = self.unit.character
	if not sm.exists( character ) then return end

	self.unstuckTimer:tick()
	self.flyMoveState:onFixedUpdate( timeStep )
end

function MinerbotUnstuckState.onUnitUpdate( self, dt ) end

function MinerbotUnstuckState.isDone( self )
	return self.unstuckTimer:done(), ""
end

function MinerbotUnstuckState.getMovementDirection( self )
	return self.flyMoveState:getMovementDirection()
end

function MinerbotUnstuckState.getFacingDirection( self )
	return self.flyMoveState:getFacingDirection()
end

function MinerbotUnstuckState.getMovementType( self )
	return self.flyMoveState:getMovementType()
end

function MinerbotUnstuckState.getWantsJump( self )
	return self.flyMoveState:getWantsJump()
end

function MinerbotUnstuckState.getWantsCrouch( self )
	return self.flyMoveState:getWantsCrouch()
end
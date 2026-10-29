dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ScannerbotManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/ScannerbotAttackState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

ScannerbotMoveAttackState = class( BaseState )

local ToleranceMovementXY = 8.0
local ToleranceDirectionXY = 1.0
local ToleranceHeightDiff = 10.0 -- +/-
local TicksBeforeAscending = 40
local MaxAscendTicks = TicksBeforeAscending * 2
local TicksBeforeDescending = 40
local MaxDescendTicks = TicksBeforeDescending * 2
local StuckDistance2 = 20 * 20
local UnstuckTickTime = 10.0 * 40

function ScannerbotMoveAttackState.sv_onCreate( self, unit )
	self.unit = unit
	self.destination = self.unit.character.worldPosition
	self.direction = sm.vec3.new( self.unit.character.direction.x, self.unit.character.direction.y, 0 ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
	if ScannerbotManager.Sv_GetBehaviour() == ScannerbotBehaviour.RELOCATE then
		self.movementType = "sprint"
	else
		self.movementType = "walk"
	end
	self.ascendTicks = 0
	self.descendTicks = 0
	self.status = ""
	self.stuckTimer = Timer()
	self.stuckTimer:start( UnstuckTickTime )
	self.stuckCenterPosition = nil

	-- Scannerbot attack state
	self.scannerbotAttackState = ScannerbotAttackState()
	self.scannerbotAttackState:sv_onCreate( self.unit )
	self.scannerbotAttackState.debugName = "scannerbotAttackState"
end

function ScannerbotMoveAttackState.sv_setDestination( self, toPosition )
	self.destination = toPosition
end

function ScannerbotMoveAttackState.sv_hasArrived( self )
	local behaviour = ScannerbotManager.Sv_GetBehaviour()
	if isAnyOf( behaviour, { ScannerbotBehaviour.RELOCATE, ScannerbotBehaviour.ROAD } ) then
		local toDestination = ( self.destination - self.unit.character.worldPosition )
		toDestination.z = 0
		local distance2 = toDestination:length2()
		return distance2 <= ToleranceMovementXY * ToleranceMovementXY
	elseif isAnyOf( behaviour, { ScannerbotBehaviour.RELOCATE_ASCEND, ScannerbotBehaviour.RELOCATE_DESCEND } ) then
		return not self:getWantsJump() and not self:getWantsCrouch()
	end
	return false
end

function ScannerbotMoveAttackState.sv_isAttacking( self )
	local done, result = self.scannerbotAttackState:isDone()
	return not done
end

--[[API functions]]

function ScannerbotMoveAttackState.start( self )
	self.status = "moving"
	self.scannerbotAttackState:start()
end

function ScannerbotMoveAttackState.stop( self )
	self.scannerbotAttackState:stop()
end

function ScannerbotMoveAttackState.onFixedUpdate( self, dt )
	if not sm.exists( self.unit ) or not sm.exists( self.unit.character ) then return end

	------------
	-- Attack --
	------------
	self.scannerbotAttackState:onFixedUpdate( dt )

	--------------
	-- Movement --
	--------------
	local behaviour = ScannerbotManager.Sv_GetBehaviour()
	local toDestination = ( self.destination - self.unit.character.worldPosition )
	toDestination.z = 0
	local distance2 = toDestination:length2()
	if distance2 > ToleranceDirectionXY * ToleranceDirectionXY then
		self.direction = toDestination:safeNormalize( self.direction )
	end
	if distance2 > ToleranceMovementXY * ToleranceMovementXY then
		if behaviour == ScannerbotBehaviour.RELOCATE then
			self.movementType = "sprint"
		elseif isAnyOf( behaviour, { ScannerbotBehaviour.RELOCATE_ASCEND, ScannerbotBehaviour.RELOCATE_DESCEND } ) then
			self.movementType = "stand"
		else
			self.movementType = "walk"
		end
		self.status = "moving"
	else
		self.movementType = "stand"
		self.status = "arrived"
	end

	if isAnyOf( behaviour, { ScannerbotBehaviour.RELOCATE, ScannerbotBehaviour.ROAD } ) and distance2 > ToleranceMovementXY * ToleranceMovementXY then
		self.stuckCenterPosition = self.stuckCenterPosition or self.unit.character.worldPosition
		local distanceFromStuckCenter = self.unit.character.worldPosition - self.stuckCenterPosition
		distanceFromStuckCenter.z = 0
		if distanceFromStuckCenter:length2() > StuckDistance2 then
			self.stuckTimer:reset()
			self.stuckCenterPosition = nil
		else
			self.stuckTimer:tick()
			if self.stuckTimer:done() then
				self.unit.character:setWorldPosition( self.destination )
				self.stuckTimer:reset()
				self.stuckCenterPosition = nil
			end
		end
	else
		self.stuckTimer:reset()
		self.stuckCenterPosition = nil
	end

	local heightAboveGroundLevel = ScannerbotManager.Sv_GetHeightAboveGround()
	if heightAboveGroundLevel then
		if behaviour == ScannerbotBehaviour.RELOCATE_ASCEND then
			-- Ascend
			if heightAboveGroundLevel + SCANNERBOT_CHARACTER_HEIGHT_OFFSET < SCANNERBOT_GROUND_HEIGHT_RELOCATE then
				self.ascendTicks = math.min( self.ascendTicks + 1, MaxAscendTicks )
			else
				self.ascendTicks = math.max( self.ascendTicks - 1, 0 )
			end
			self.descendTicks = math.max( self.descendTicks - 1, 0 )

		elseif behaviour == ScannerbotBehaviour.RELOCATE_DESCEND then
			-- Descend
			self.ascendTicks = math.max( self.ascendTicks - 1, 0 )
			if heightAboveGroundLevel + SCANNERBOT_CHARACTER_HEIGHT_OFFSET > SCANNERBOT_GROUND_HEIGHT_ROAD then
				self.descendTicks = math.min( self.descendTicks + 1, MaxDescendTicks )
			else
				self.descendTicks = math.max( self.descendTicks - 1, 0 )
			end
		elseif behaviour == ScannerbotBehaviour.RELOCATE then
			-- Fly high
			if heightAboveGroundLevel + SCANNERBOT_CHARACTER_HEIGHT_OFFSET < SCANNERBOT_GROUND_HEIGHT_RELOCATE - ToleranceHeightDiff then
				self.ascendTicks = math.min( self.ascendTicks + 1, MaxAscendTicks )
			else
				self.ascendTicks = math.max( self.ascendTicks - 1, 0 )
			end

			if heightAboveGroundLevel + SCANNERBOT_CHARACTER_HEIGHT_OFFSET > SCANNERBOT_GROUND_HEIGHT_RELOCATE + ToleranceHeightDiff then
				self.descendTicks = math.min( self.descendTicks + 1, MaxDescendTicks )
			else
				self.descendTicks = math.max( self.descendTicks - 1, 0 )
			end
		else
			-- Fly low
			if heightAboveGroundLevel + SCANNERBOT_CHARACTER_HEIGHT_OFFSET < SCANNERBOT_GROUND_HEIGHT_ROAD - ToleranceHeightDiff then
				self.ascendTicks = math.min( self.ascendTicks + 1, MaxAscendTicks )
			else
				self.ascendTicks = math.max( self.ascendTicks - 1, 0 )
			end

			if heightAboveGroundLevel + SCANNERBOT_CHARACTER_HEIGHT_OFFSET > SCANNERBOT_GROUND_HEIGHT_ROAD + ToleranceHeightDiff then
				self.descendTicks = math.min( self.descendTicks + 1, MaxDescendTicks )
			else
				self.descendTicks = math.max( self.descendTicks - 1, 0 )
			end
		end
	else
		if behaviour == ScannerbotBehaviour.RELOCATE_ASCEND then
			-- No ground, assume gain altitude
			self.ascendTicks = math.min( self.ascendTicks + 1, MaxAscendTicks )
			self.descendTicks = math.max( self.descendTicks - 1, 0 )
		elseif behaviour == ScannerbotBehaviour.RELOCATE_DESCEND then
			-- No ground, assume lower altitude
			self.ascendTicks = math.max( self.ascendTicks - 1, 0 )
			self.descendTicks = math.min( self.descendTicks + 1, MaxDescendTicks )
		else
			-- No ground, undefined
			self.ascendTicks = math.max( self.ascendTicks - 1, 0 )
			self.descendTicks = math.max( self.descendTicks - 1, 0 )
		end
	end
end

function ScannerbotMoveAttackState.onUnitUpdate( self, dt )
	self.scannerbotAttackState:onUnitUpdate( dt )
end

function ScannerbotMoveAttackState.isDone( self )
	local done, result = self.scannerbotAttackState:isDone()
	return done, self.status
end

function ScannerbotMoveAttackState.getMovementDirection( self )
	return self.direction
end

function ScannerbotMoveAttackState.getFacingDirection( self )
	return self.direction
end

function ScannerbotMoveAttackState.getMovementType( self )
	return self.movementType
end

function ScannerbotMoveAttackState.getWantsJump( self )
	return self.ascendTicks >= TicksBeforeAscending and self.ascendTicks >= self.descendTicks
end

function ScannerbotMoveAttackState.getWantsCrouch( self )
	return self.descendTicks >= TicksBeforeDescending and self.descendTicks >= self.ascendTicks
end
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/DrillAttack.lua" )

TotebotBlueChargeState = class( BaseState )

local ChargeSetupRange2 = 9.0 * 9.0
local ChargeWindupTime = 0.5
local RetaliateWindupTime = 0.35
local ChargeCooldownTime = 1.2
local ChargePassDistance = 1.5
local ChargeMinDistance = 5.0
local ChargeMaxDistance = 14.0
local ChargeTurnRate = math.rad( 45.0 ) -- Max steering rate (rad/s) while charging

local function turnTowards( current, target, maxAngle )
	current = sm.vec3.new( current.x, current.y, 0 ):safeNormalize( target )
	target = sm.vec3.new( target.x, target.y, 0 ):safeNormalize( current )
	local dot = math.max( -1.0, math.min( 1.0, current:dot( target ) ) )
	local angle = math.acos( dot )
	if angle <= maxAngle or angle == 0 then
		return target
	end
	local sign = current:cross( target ).z >= 0 and 1 or -1
	return sm.quat.angleAxis( sign * maxAngle, sm.vec3.new( 0, 0, 1 ) ) * current
end

function TotebotBlueChargeState.sv_onCreate( self, unit )
	self.unit = unit
	self.target = nil
	self.targetPosition = nil
	self.chargeDirection = nil
	self.retaliate = false
	self.sprintSpeed = unit.character:getSprintSpeed()

	self.drillAttack = DrillAttack()
	self.drillAttack:sv_onCreate( self.unit )

	self.pathingState = PathingState()
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState.debugName = "pathingState"
	self.pathingState:sv_setTolerance( 1.0 )
	self.pathingState:sv_setMovementType( "walk" )
	self.pathingState:sv_setWaterAvoidance( false )
	self.pathingState:sv_setCliffAvoidance( false )

	self.windupState = self.unit:createState( "wait" )
	self.windupState.debugName = "windupState"
	self.windupState.time = ChargeWindupTime
	self.windupState.interruptible = false

	self.retaliateState = self.unit:createState( "wait" )
	self.retaliateState.debugName = "retaliateState"
	self.retaliateState.time = RetaliateWindupTime
	self.retaliateState.interruptible = false

	self.sprintState = self.unit:createState( "wait" )
	self.sprintState.debugName = "sprintState"
	self.sprintState.name = "melee"
	self.sprintState.time = 0.0
	self.sprintState.interruptible = false

	self.cooldownState = self.unit:createState( "wait" )
	self.cooldownState.debugName = "cooldownState"
	self.cooldownState.time = ChargeCooldownTime
	self.cooldownState.interruptible = false

	self.finishedState = self.unit:createState( "wait" )
	self.finishedState.debugName = "finishedState"
	self.finishedState.time = 0.0
	self.finishedState.interruptible = true

	self.currentState = self.finishedState
end

function TotebotBlueChargeState.sv_setTarget( self, target )
	self.target = target
	if sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
	else
		self.targetPosition = nil
	end
end

function TotebotBlueChargeState.sv_setRetaliate( self, target )
	self:sv_setTarget( target )
	self.retaliate = true
end

function TotebotBlueChargeState.sv_prepareCharge( self )
	if not self.targetPosition then
		return false
	end

	local botPosition = self.unit.character.worldPosition
	local toTarget = self.targetPosition - botPosition
	toTarget.z = 0
	local chargeDirection = toTarget:safeNormalize( self.unit.character.direction )
	local targetRadius = self.target and type( self.target ) == "Character" and self.target:getRadius() or 0.0
	local botRadius = self.unit.character:getRadius()
	local distanceToTarget = toTarget:length()

	local predictedDistance = 0.0
	if self.target and type( self.target ) == "Character" then
		local targetVelocity = self.target.velocity
		local awaySpeed = sm.vec3.new( targetVelocity.x, targetVelocity.y, 0 ):dot( chargeDirection )
		if awaySpeed > 0 then
			local interceptTime = distanceToTarget / math.max( self.sprintSpeed - awaySpeed, 1.0 )
			predictedDistance = awaySpeed * interceptTime
		end
	end

	local chargeDistance = distanceToTarget + predictedDistance + targetRadius + botRadius + ChargePassDistance
	chargeDistance = clamp( chargeDistance, ChargeMinDistance, ChargeMaxDistance )

	self.chargeDirection = chargeDirection
	self.sprintState.time = chargeDistance / self.sprintSpeed
	return true
end

function TotebotBlueChargeState.start( self )
	self.done = nil
	self.chargeDirection = nil
	self.currentState:stop()
	if self.targetPosition then
		if self.retaliate then
			self.currentState = self.retaliateState
		else
			self.currentState = self.pathingState
		end
	else
		self.currentState = self.finishedState
		self.done = "lost"
	end
	self.retaliate = false
	self.currentState:start()
end

function TotebotBlueChargeState.stop( self )
	self.drillAttack:sv_setActive( false )
	self.currentState:stop()
end

function TotebotBlueChargeState.onFixedUpdate( self, dt )
	if self.target and sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
	elseif self.target then
		self.target = nil
		self.targetPosition = nil
	end

	-- Slow turning while charging
	if self.currentState == self.sprintState and self.chargeDirection and self.targetPosition then
		local toTarget = self.targetPosition - self.unit.character.worldPosition
		local desiredDirection = toTarget:safeNormalize( self.chargeDirection )
		self.chargeDirection = turnTowards( self.chargeDirection, desiredDirection, ChargeTurnRate * dt )
	end

	self.drillAttack:sv_setActive( self.currentState == self.sprintState )
	self.drillAttack:sv_onFixedUpdate( dt )

	self.currentState:onFixedUpdate( dt )

	local prevState = self.currentState
	local done, result = self.currentState:isDone()

	if not self.targetPosition and self.currentState ~= self.sprintState then
		self.currentState = self.finishedState
		self.done = "lost"
	elseif self.currentState == self.pathingState then
		-- Commit to the charge when within range.
		local toTarget = self.targetPosition - self.unit.character.worldPosition
		toTarget.z = 0
		if toTarget:length2() <= ChargeSetupRange2 then
			self.currentState = self.windupState
		end
	elseif isAnyOf( self.currentState, { self.windupState, self.retaliateState } ) and done then
		if self:sv_prepareCharge() then
			self.currentState = self.sprintState
		else
			self.currentState = self.finishedState
			self.done = "lost"
		end
	elseif self.currentState == self.sprintState and done then
		self.currentState = self.cooldownState
	elseif self.currentState == self.cooldownState and done then
		self.currentState = self.pathingState
	elseif self.currentState == self.finishedState then
		self.done = self.done or result or "lost"
	end

	if self.currentState ~= prevState then
		prevState:stop()
		self.currentState:start()
	end
end

function TotebotBlueChargeState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
	if self.currentState == self.pathingState and self.targetPosition then
		self.pathingState:sv_setDestination( self.targetPosition )
	end
end

function TotebotBlueChargeState.isDone( self )
	if self.currentState == self.finishedState then
		return true, self.done or "lost"
	end
	return false, ""
end

function TotebotBlueChargeState.getMovementDirection( self )
	if self.currentState == self.sprintState and self.chargeDirection then
		return self.chargeDirection
	end
	return self.currentState:getMovementDirection()
end

function TotebotBlueChargeState.getFacingDirection( self )
	if self.currentState == self.sprintState and self.chargeDirection then
		return self.chargeDirection
	end
	local stateFacingDirection = self.currentState:getFacingDirection()
	if isAnyOf( self.currentState, { self.windupState, self.retaliateState, self.cooldownState, self.finishedState } ) and self.targetPosition then
		return ( self.targetPosition - self.unit.character.worldPosition ):safeNormalize( stateFacingDirection )
	end
	return stateFacingDirection
end

function TotebotBlueChargeState.getMovementType( self )
	if self.currentState == self.sprintState and self.chargeDirection then
		return "sprint"
	end
	return self.currentState:getMovementType()
end

function TotebotBlueChargeState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function TotebotBlueChargeState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end
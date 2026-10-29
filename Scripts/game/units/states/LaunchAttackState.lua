dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

LaunchAttackState = class( BaseState )

local JumpWindUp = math.floor( 0.5 * 40 )
local TrackingTicks = math.floor( JumpWindUp * 0.9 * 40 )
local AirTicksBeforeTumble = math.floor( 0.56 * 40 )
local LandingTicks = math.floor( 0.4 * 40 )
local AttackDamage = 15
local LandingStumbleChance = 0.2

local HeightAimOffset = 1.1
local ImpulseModifier = 4.8

local JumpStates = {
	prepare  = 1,
	inAir = 2,
	landing = 3
}

function LaunchAttackState.sv_onCreate( self, unit )
	self.unit = unit
	self.target = nil
	self.targetPosition = nil

	-- Initial

	self.prepareTimer = Timer()
	self.prepareTimer:start( JumpWindUp )

	self.trackingTimer = Timer()
	self.trackingTimer:start( TrackingTicks )

	self.airRagdollTimer = Timer()
	self.airRagdollTimer:start( AirTicksBeforeTumble )

	self.landingTimer = Timer()
	self.landingTimer:start( LandingTicks )

	self.currentState = JumpStates.prepare

	self.jumpDirection = sm.vec3.new( 1, 0, 0 )
	self.hasTumbled = false
	self.abort = false
	
	self.hitBox = sm.areaTrigger.createAttachedBox( self.unit.character, sm.vec3.new( 0.5, 0.5, 0.2 ), sm.vec3.new( 0, 0.5, 1 ), nil, sm.areaTrigger.filter.character )
	self.hitBox:bindOnEnter( "sv_t_onEnter", self )
	self.hitCharacters = { self.unit.character }
end

function LaunchAttackState.sv_setAttack( self, attackUuid )
	self.attackUuid = attackUuid
end

function LaunchAttackState.sv_t_onEnter( self, trigger, results )
	if not sm.exists( self.unit ) or not sm.exists( self.unit.character ) then
		return
	end
	if self.stateActive and self.currentState == JumpStates.inAir and sm.exists( self.unit ) and not self.unit.character:isTumbling() then
		local hits = {}
		for _, result in pairs( results ) do
			if not isAnyOf( result, self.hitCharacters ) then
				hits[#hits+1] = result
			end
		end
		--melee
		if #hits > 0 then
			sm.melee.meleeAttack( self.attackUuid, AttackDamage, self.unit.character.worldPosition, self.jumpDirection, self.unit, nil, nil, self.hitCharacters )
			for _, character in ipairs( hits ) do
				self.hitCharacters[#self.hitCharacters+1] = character
			end
		end
	end
end

function LaunchAttackState.sv_setTarget( self, target )
	self.target = target
	if sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
		self.jumpDirection = ( self.targetPosition - self.unit.character.worldPosition ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
	end
end

--[[API functions]]

function LaunchAttackState.start( self )
	self.prepareTimer:start( JumpWindUp )
	self.trackingTimer:start( TrackingTicks )
	self.landingTimer:start( LandingTicks )
	self.airRagdollTimer:start( AirTicksBeforeTumble )
	self.hitCharacters = { self.unit.character }
	self.currentState = JumpStates.prepare
	self.stateActive = true
	self.unit:sendCharacterEvent( "launch" )
	self.hasTumbled = false
	self.abort = false
end

function LaunchAttackState.stop( self )
	self.stateActive = false
	self.unit:sendCharacterEvent( "stop" )
end

function LaunchAttackState.onFixedUpdate( self, dt )
	if self.currentState == JumpStates.prepare then
		self.trackingTimer:tick()
		self.prepareTimer:tick()
		if not self.trackingTimer:done() then
			if sm.exists( self.target ) then
				self.targetPosition = self.target.worldPosition
				self.jumpDirection = ( self.targetPosition - self.unit.character.worldPosition ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
			end
		end
	elseif self.currentState == JumpStates.inAir then
		self.airRagdollTimer:tick()
		if self.airRagdollTimer:isActive() and self.airRagdollTimer:done() then
			self.airRagdollTimer:stop()
			if not self.unit.character:isOnGround() then
				self.unit.character:setTumbling( true )
				self.unit.character:applyTumblingImpulse( self.unit.character.velocity )
				self.unit.character:applyTumblingImpulse( sm.vec3.new( 0, 0, -1 ) * self.unit.character.mass, self.jumpDirection )
			end
		end
		if ( self.airRagdollTimer:getTick() > 10 or not self.airRagdollTimer:isActive() ) and self.unit.character:isOnGround() then
			self.airRagdollTimer:stop()
			if math.random() < LandingStumbleChance and not self.hasTumbled then
				self.unit.character:setTumbling( true )
				self.unit.character:applyTumblingImpulse( self.unit.character.velocity )
				self.unit.character:applyTumblingImpulse( sm.vec3.new( 0, 0, -1 ) * self.unit.character.mass, self.jumpDirection )
				self.hasTumbled = true
			else
				self.unit:sendCharacterEvent( "landing" )
				self.currentState = JumpStates.landing
			end
		end
	elseif self.currentState == JumpStates.landing then
		self.landingTimer:tick()
	end

	if self.currentState == JumpStates.prepare and self.prepareTimer:done() then
		if self:launch() then
			self.currentState = JumpStates.inAir
		else
			self.abort = true
		end
	end
	if not self.hasTumbled and self.unit.character:isTumbling() then
		self.hasTumbled = true
	end
end

function LaunchAttackState.launch( self )
	local aimPos = self.targetPosition + sm.vec3.new( 0, 0, 0.5 )
	local horizontalDistance = ( sm.vec3.new( aimPos.x, aimPos.y, 0 ) - sm.vec3.new( self.unit.character.worldPosition.x, self.unit.character.worldPosition.y, 0 ) ):length()
	local verticalDistance = math.abs( aimPos.z - self.unit.character.worldPosition.z )
	local hypotenuse = math.sqrt( horizontalDistance^2 + verticalDistance^2 )

	if ( verticalDistance + HeightAimOffset ) >= hypotenuse then
		return false -- Cant jump too vertically
	end

	local initialImpulse = math.sqrt( GRAVITY * ( hypotenuse ) ) * self.unit.character.mass * ImpulseModifier
	local theta = math.asin( ( verticalDistance + HeightAimOffset ) / hypotenuse )

	local flatDirection = sm.vec3.new( self.jumpDirection.x, self.jumpDirection.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
	local cross = flatDirection:cross( sm.vec3.new( 0, 0, 1 ) )
	local direction = flatDirection:rotate( theta / 2, cross )
	self.unit:sendCharacterEvent( "inAir" )

	sm.physics.applyImpulse( self.unit.character, direction * initialImpulse, true )
	return true
end

function LaunchAttackState.onUnitUpdate( self, dt )
end

function LaunchAttackState.isDone( self )
	if self.abort then
		return true, "aborted"
	end
	if self.hasTumbled then
		return true, "tumbled"
	end
	if self.currentState == JumpStates.inAir then
		if self.airRagdollTimer:isActive() then
			return false, ""
		end
	elseif self.currentState == JumpStates.landing then
		if self.landingTimer:done() or not self.landingTimer:isActive() then
			return true, "landed"
		else
			return false, ""
		end
	end
	return false, ""
end

function LaunchAttackState.getMovementDirection( self )
	return self.jumpDirection
end

function LaunchAttackState.getFacingDirection( self )
	return self.jumpDirection
end

function LaunchAttackState.getMovementType( self )
	return "stand"
end
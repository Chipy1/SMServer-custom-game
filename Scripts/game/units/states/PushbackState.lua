dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

PushbackState = class( BaseState )

local PushbackTime = 2.0
local PushbackDistance = 45
local PushbackImpulsePower = 3000

function PushbackState.sv_onCreate( self, unit )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.stageIndex = 1

	self.pushbackEventState = self.unit:createState( "wait" )
	self.pushbackEventState.debugName = "pushbackEventState"
	self.pushbackEventState.name = "startPushback"
	self.pushbackEventState.time = PushbackTime
	self.pushbackEventState.interruptible = false

	self.pushbackFinishedEventState = self.unit:createState( "wait" )
	self.pushbackFinishedEventState.debugName = "pushbackFinishedEventState"
	self.pushbackFinishedEventState.name = "endPushback"
	self.pushbackFinishedEventState.time = 0.5
	self.pushbackFinishedEventState.interruptible = false

	self.currentState = self.pushbackEventState
end

function PushbackState.refresh( self ) end

function PushbackState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function PushbackState.sv_setPosition( self, worldPosition ) end

function PushbackState.sv_setTarget( self, target )
	self.target = target
end

function PushbackState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

function PushbackState.sv_updatePushback( self )
	local players = sm.player.getAllPlayers()
	for _,player in ipairs( players ) do
		if player.character:getWorld().id == self.unit.character:getWorld().id then
			local fromToTarget = player.character.worldPosition - self.unit.character.worldPosition
			local distanceToTarget = fromToTarget:length()
			local pushbackDirection = -fromToTarget:safeNormalize( self.lookDirection )
			if distanceToTarget <= PushbackDistance then
				sm.event.sendToPlayer( player, "sv_e_grantTumbleImmunity", PushbackTime * 40 )
				ApplyCharacterImpulse( player.character, -pushbackDirection, PushbackImpulsePower )
			end
		end
	end
end

--[[API functions]]

function PushbackState.start( self )
	self.currentState:stop()
	self.currentState = self.pushbackEventState
	self.currentState:start()
end

function PushbackState.stop( self )
	self.currentState:stop()
end

function PushbackState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.currentState:onFixedUpdate( dt )
	if self.currentState == self.pushbackEventState then
		local done, _ = self.currentState:isDone()
		if done then
			self.currentState:stop()
			self.currentState = self.pushbackFinishedEventState
			self.currentState:start()
		else
			if self.target then
				self:sv_updatePushback()
			end
		end

		local players = sm.player.getAllPlayers()
		for _,player in ipairs( players ) do
			if done then
				sm.event.sendToPlayer( player, "sv_e_stopPushbackSound" )
			else
				sm.event.sendToPlayer( player, "sv_e_startPushbackSound" )
			end
		end
	end
end

function PushbackState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function PushbackState.isDone( self )
	if self.currentState == self.pushbackFinishedEventState then
		local done, _ = self.currentState:isDone()
		return done, "finished"
	elseif self.currentState == self.pushbackEventState then
		return false, "pushback"
	end
	return true, "unknown state"
end

function PushbackState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function PushbackState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function PushbackState.getMovementType( self )
	return self.currentState:getMovementType()
end

function PushbackState.getWantsJump( self )
	return false
end
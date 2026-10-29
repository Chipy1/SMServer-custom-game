dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

ScannerbotAttackState = class( BaseState )

local InitialFireIntervalTickTime = 5
local SlowFireIntervalTickTime = 12
local MissileUuid = sm.uuid.new( "7daebf10-a0ce-11ed-a8fc-0242ac120002" )
local LaunchData = {
	{ targetOffset = 2, localPosition = sm.vec3.new( 8.66722, 9.91707, 10.1631 ), localRotation = sm.quat.new( 0.265161, 0.826149, -0.473375, -0.151934 ), curveChance = 0.75 },
	{ targetOffset = 2, localPosition = sm.vec3.new( -10.3763, 8.38183, 10.239 ), localRotation = sm.quat.new( -0.327914, 0.803309, -0.460288, 0.187891 ), curveChance = 0.75 },
	{ targetOffset = 2, localPosition = sm.vec3.new( 9.26181, -13.0316, 9.47858 ), localRotation = sm.quat.new( -0.584499, 0.641244, 0.496838, -0.0178842 ), curveChance = 0.75 },
	{ targetOffset = 1, localPosition = sm.vec3.new( -7.44352, -14.8363, 9.5921 ), localRotation = sm.quat.new( 0.53345, 0.684298, 0.496742, -0.0203802 ), curveChance = 0.75 },
	{ targetOffset = 1, localPosition = sm.vec3.new( 8.56347, 9.84164, 5.54021 ), localRotation = sm.quat.new( 0.26516, 0.826149, -0.473375, -0.151934 ), curveChance = 0.75 },
	{ targetOffset = 1, localPosition = sm.vec3.new( -9.91522, 7.91104, 5.30115 ), localRotation = sm.quat.new( -0.327914, 0.803309, -0.460288, 0.187891 ), curveChance = 0.75 },
	{ targetOffset = 1, localPosition = sm.vec3.new( 9.46878, -13.4352, 4.89328 ), localRotation = sm.quat.new( -0.584498, 0.641244, 0.496838, -0.0178842 ), curveChance = 0.75 },
	{ targetOffset = 1, localPosition = sm.vec3.new( -7.16309, -14.8053, 4.78268 ), localRotation = sm.quat.new( 0.53345, 0.684298, 0.496742, -0.0203805 ), curveChance = 0.75 },
	{ targetOffset = 1, localPosition = sm.vec3.new( 8.42567, 9.6058, 0.89328 ), localRotation = sm.quat.new( 0.265161, 0.826149, -0.473375, -0.151934 ), curveChance = 0.75 },
	{ targetOffset = 0, localPosition = sm.vec3.new( -9.33836, 7.32214, 0.330498 ), localRotation = sm.quat.new( -0.327914, 0.803308, -0.460288, 0.187891 ), curveChance = 0.75 },
	{ targetOffset = 0, localPosition = sm.vec3.new( 9.3218, -13.3428, 0.179161 ), localRotation = sm.quat.new( -0.584498, 0.641244, 0.496838, -0.0178838 ), curveChance = 0.75 },
	{ targetOffset = 0, localPosition = sm.vec3.new( -7.08134, -14.641, 0.103905 ), localRotation = sm.quat.new( 0.533449, 0.684298, 0.496742, -0.0203803 ), curveChance = 0.75 },
}
local LaunchTargetOffsets = {
	{ min = 1.5, max = 8 },
	{ min = 1, max = 4 },
	{ min = 1, max = 2 },
	{ min = 0, max = 1 }
}

function ScannerbotAttackState.sv_onCreate( self, unit )
	self.unit = unit

	self.launchIndex = 1
	self.firedMissiles = 0
	self.initialFireIntervalTimer = Timer()
	self.initialFireIntervalTimer:start( InitialFireIntervalTickTime )
	self.initialFireIntervalTimer.count = InitialFireIntervalTickTime

	self.slowFireIntervalTimer = Timer()
	self.slowFireIntervalTimer:start( SlowFireIntervalTickTime )
	self.slowFireIntervalTimer.count = SlowFireIntervalTickTime

	self.preOpenHatchState = self.unit:createState( "wait" )
	self.preOpenHatchState.debugName = "preOpenHatchState"
	self.preOpenHatchState.time = 2.0
	self.preOpenHatchState.interruptible = false

	self.openHatchState = self.unit:createState( "wait" )
	self.openHatchState.name = "openHatch"
	self.openHatchState.debugName = "openHatchState"
	self.openHatchState.time = 1.0
	self.openHatchState.interruptible = false

	self.initialFireMissilesState = self.unit:createState( "wait" )
	self.initialFireMissilesState.debugName = "initialFireMissilesState"
	self.initialFireMissilesState.time = 2.0
	self.initialFireMissilesState.interruptible = false

	self.slowFireMissilesState = self.unit:createState( "wait" )
	self.slowFireMissilesState.debugName = "slowFireMissilesState"
	self.slowFireMissilesState.time = 0.0
	self.slowFireMissilesState.interruptible = false

	self.reloadState = self.unit:createState( "wait" )
	self.reloadState.debugName = "reloadState"
	self.reloadState.time = 0.0
	self.reloadState.interruptible = false

	self.closeHatchState = self.unit:createState( "wait" )
	self.closeHatchState.name = "closeHatch"
	self.closeHatchState.debugName = "closeHatchState"
	self.closeHatchState.time = 1.0
	self.closeHatchState.interruptible = false

	self.calmState = self.unit:createState( "wait" )
	self.calmState.debugName = "calmState"
	self.calmState.interruptible = true

	self.currentState = self.preOpenHatchState
end

function ScannerbotAttackState.sv_fire( self, missileIndex )
	local characterTargets = ScannerbotManager.Sv_GetTargets()
	if not IsEmptyTable( characterTargets ) then
		local clampedIndex = ( ( missileIndex - 1 ) % #LaunchData ) + 1
		local launchData = LaunchData[clampedIndex]

		local character = self.unit.character
		local characterRotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), character.direction )
		local worldPosition = character.worldPosition + characterRotation * launchData.localPosition
		local worldRotation = characterRotation * launchData.localRotation
		local worldDirection = worldRotation * sm.vec3.new( 0, 0, -1 )

		-- Sort targets by distance to scannerbot
		local characterTargetsByDistance = {}
		for _, characterTarget in pairs( characterTargets ) do
			if sm.exists( characterTarget.character ) then
				local distance2 = ( characterTarget.character.worldPosition - character.worldPosition ):length2()
				characterTargetsByDistance[#characterTargetsByDistance+1] = { character = characterTarget.character, distance2 = distance2 }
			end
		end

		if not IsEmptyTable( characterTargetsByDistance ) then
			-- Nearest first, prioritize players
			local SortByPlayerAndDistance = function( a, b )
				if a.character:isPlayer() == b.character:isPlayer() then
					-- Same type, sort nearest first
					return a.distance2 < b.distance2
				else
					-- Different type, sort players first
					return a.character:isPlayer()
				end
			end

			table.sort( characterTargetsByDistance, SortByPlayerAndDistance )
			local clampedTargetIndex = ( ( missileIndex - 1 ) % #characterTargetsByDistance ) + 1
			local selectedCharacter = characterTargetsByDistance[clampedTargetIndex].character

			-- Get offset to simulate bad initial accuracy
			local launchTargetOffset = LaunchTargetOffsets[self.launchIndex]
			local targetOffset = launchTargetOffset.min + math.random() * ( launchTargetOffset.max - launchTargetOffset.min ) + math.random() * launchData.targetOffset
			local params = { worldPosition = worldPosition, worldDirection = worldDirection, targetOffset = targetOffset, targetCharacter = selectedCharacter, curveChance = launchData.curveChance }
			sm.scriptableObject.createScriptableObject( MissileUuid, params, character:getWorld() )
			sm.effect.playEffect( "Scannerbot - Shootingmissles", worldPosition, nil, worldRotation )
		end
	end
end

--[[API functions]]

function ScannerbotAttackState.start( self )
	self.currentState:stop()
	self.currentState = self.preOpenHatchState
	self.currentState:start()
	self.launchIndex = 1
	self.firedMissiles = 0
	self.initialFireIntervalTimer.count = InitialFireIntervalTickTime
	self.slowFireIntervalTimer.count = SlowFireIntervalTickTime
end

function ScannerbotAttackState.stop( self )
	self.currentState:stop()
end

function ScannerbotAttackState.onFixedUpdate( self, dt )
	if not sm.exists( self.unit ) or not sm.exists( self.unit.character ) then return end

	self.currentState:onFixedUpdate( dt )
	if self.currentState == self.initialFireMissilesState then
		if self.firedMissiles < #LaunchData then
			self.initialFireIntervalTimer:tick()
			if self.initialFireIntervalTimer:done() then
				self.firedMissiles = self.firedMissiles + 1
				self:sv_fire( self.firedMissiles )
				self.initialFireIntervalTimer:reset()
			end
		end
	elseif self.currentState == self.slowFireMissilesState then
		if self.firedMissiles < #LaunchData then
			self.slowFireIntervalTimer:tick()
			if self.slowFireIntervalTimer:done() then
				self.firedMissiles = self.firedMissiles + 1
				self:sv_fire( self.firedMissiles )
				self.slowFireIntervalTimer:reset()
			end
		end
	end
end

function ScannerbotAttackState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
	local done, _ = self.currentState:isDone()
	if done then
		local characterTargets = ScannerbotManager.Sv_GetTargets()
		local hasTarget = next( characterTargets ) ~= nil

		local prevState = self.currentState
		if self.currentState == self.preOpenHatchState then
			if hasTarget then
				self.currentState = self.openHatchState
			else
				self.currentState = self.calmState
			end
		elseif self.currentState == self.openHatchState then
			if hasTarget then
				self.launchIndex = 1
				self.firedMissiles = 0
				self.currentState = self.initialFireMissilesState
			else
				self.currentState = self.closeHatchState
			end
		elseif self.currentState == self.initialFireMissilesState then
			if self.firedMissiles >= #LaunchData then
				if hasTarget then
					self.currentState = self.reloadState
				else
					self.currentState = self.closeHatchState
				end
			end
		elseif self.currentState == self.slowFireMissilesState then
			if hasTarget then
				if self.firedMissiles >= #LaunchData then
					self.currentState = self.reloadState
				end
			else
				self.currentState = self.closeHatchState
			end
		elseif self.currentState == self.reloadState then
			self.launchIndex = math.min( self.launchIndex + 1, #LaunchTargetOffsets )
			self.firedMissiles = 0
			if hasTarget then
				self.currentState = self.slowFireMissilesState
			else
				self.currentState = self.closeHatchState
			end
		elseif self.currentState == self.closeHatchState then
			self.launchIndex = 1
			self.firedMissiles = 0
			if hasTarget then
				self.currentState = self.preOpenHatchState
			else
				self.currentState = self.calmState
			end
		elseif self.currentState == self.calmState then
			if hasTarget then
				self.currentState = self.preOpenHatchState
			end
		end

		if self.currentState ~= prevState then
			prevState:stop()
			self.currentState:start()
		end
	end
end

function ScannerbotAttackState.isDone( self )
	return self.currentState == self.calmState, self.currentState.debugName
end

function ScannerbotAttackState.getMovementDirection( self )
	return self.unit.character.direction
end

function ScannerbotAttackState.getFacingDirection( self )
	return self.unit.character.direction
end

function ScannerbotAttackState.getMovementType( self )
	return "stand"
end

function ScannerbotAttackState.getWantsJump( self )
	return false
end
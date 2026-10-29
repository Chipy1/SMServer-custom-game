dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BulletHellState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BulletSprayState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/JunkWaveState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/VolleyBombState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/ChargedBulletState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/TrashBallState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/TurboBulletSprayState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/PushbackState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/LaughState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/SprayGroundState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/VolleyBombLoopState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/TrashSprinklerState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/ClearPatternState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/DestructionSwayState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

TrashbotAttackState = class( BaseState )

function TrashbotAttackState.sv_onCreate( self, unit )
	self.unit = unit
	self.rightState = nil
	self.leftState = nil

	self.rightAttackType = nil
	self.leftAttackType = nil

	-- Bullet Spray
	self.bulletSprayRightState = BulletSprayState()
	self.bulletSprayRightState:sv_onCreate( self.unit, true )
	self.bulletSprayRightState.debugName = "bulletSprayRightState"

	self.bulletSprayLeftState = BulletSprayState()
	self.bulletSprayLeftState:sv_onCreate( self.unit, false )
	self.bulletSprayLeftState.debugName = "bulletSprayLeftState"

	-- Junk Wave
	self.junkWaveRightState = JunkWaveState()
	self.junkWaveRightState:sv_onCreate( self.unit, true )
	self.junkWaveRightState.debugName = "junkWaveRightState"

	self.junkWaveLeftState = JunkWaveState()
	self.junkWaveLeftState:sv_onCreate( self.unit, false )
	self.junkWaveLeftState.debugName = "junkWaveLeftState"

	-- Volley Bomb
	self.volleyBombRightState = VolleyBombState()
	self.volleyBombRightState:sv_onCreate( self.unit, true )
	self.volleyBombRightState.debugName = "volleyBombRightState"

	self.volleyBombLeftState = VolleyBombState()
	self.volleyBombLeftState:sv_onCreate( self.unit, false )
	self.volleyBombLeftState.debugName = "volleyBombLeftState"

	-- Charged Bullet
	self.chargedBulletRightState = ChargedBulletState()
	self.chargedBulletRightState:sv_onCreate( self.unit, true )
	self.chargedBulletRightState.debugName = "chargedBulletRightState"

	self.chargedBulletLeftState = ChargedBulletState()
	self.chargedBulletLeftState:sv_onCreate( self.unit, false )
	self.chargedBulletLeftState.debugName = "chargedBulletLeftState"

	-- Trash Ball
	self.trashBallState = TrashBallState()
	self.trashBallState:sv_onCreate( self.unit )
	self.trashBallState.debugName = "trashBallState"

	-- Turbo Bullet Spray
	self.turboBulletSprayRightState = TurboBulletSprayState()
	self.turboBulletSprayRightState:sv_onCreate( self.unit, true )
	self.turboBulletSprayRightState.debugName = "turboBulletSprayRightState"

	self.turboBulletSprayLeftState = TurboBulletSprayState()
	self.turboBulletSprayLeftState:sv_onCreate( self.unit, false )
	self.turboBulletSprayLeftState.debugName = "turboBulletSprayLeftState"

	-- Trash Spray State
	self.trashSprinklerRightState = TrashSprinklerState()
	self.trashSprinklerRightState:sv_onCreate( self.unit, true )
	self.trashSprinklerRightState.debugName = "trashSprinklerRightState"

	self.trashSprinklerLeftState = TrashSprinklerState()
	self.trashSprinklerLeftState:sv_onCreate( self.unit, false )
	self.trashSprinklerLeftState.debugName = "trashSprinklerLeftState"

	-- Spray Ground
	self.sprayGroundState = SprayGroundState()
	self.sprayGroundState:sv_onCreate( self.unit )
	self.sprayGroundState.debugName = "sprayGroundState"

	-- Volley Loop
	self.volleyLoopState = VolleyBombLoopState()
	self.volleyLoopState:sv_onCreate( self.unit )
	self.volleyLoopState.debugName = "volleyLoopState"

	-- Laugh
	self.laughState = LaughState()
	self.laughState:sv_onCreate( self.unit )
	self.laughState.debugName = "laughState"

	-- Pushback
	self.pushbackState = PushbackState()
	self.pushbackState:sv_onCreate( self.unit )
	self.pushbackState.debugName = "pushbackState"

	-- Destruction Sway
	self.destructionSwayState = DestructionSwayState()
	self.destructionSwayState:sv_onCreate( self.unit )
	self.destructionSwayState.debugName = "destructionSwayState"

	-- BulletHell
	self.bulletHellState = BulletHellState()
	self.bulletHellState:sv_onCreate( self.unit )
	self.bulletHellState.debugName = "bulletHellState"

	-- ClearPatternState
	self.clearPatternState = ClearPatternState()
	self.clearPatternState:sv_onCreate( self.unit )
	self.clearPatternState.debugName = "clearPatternState"

	self.twoHandedStates = { self.trashBallState, self.laughState, self.pushbackState, self.sprayGroundState, self.volleyLoopState, self.clearPatternState, self.destructionSwayState }
	self.twoHandedAttacks = { TrashbotAttack.TRASH_BALL, TrashbotAttack.LAUGH, TrashbotAttack.PUSHBACK, TrashbotAttack.SPRAY_GROUND, TrashbotAttack.CONTINUOUS_VOLLEY, TrashbotAttack.CLEAR_PATTERN }
	self.loopDurationAffectedStates = { self.volleyLoopState, self.sprayGroundState, self.trashSprinklerRightState, self.trashSprinklerLeftState, self.bulletSprayLeftState, self.bulletSprayRightState }
	self.abortableStates = { self.trashSprinklerLeftState, self.trashSprinklerRightState }

	self.typeAffectedStates = { self.junkWaveRightState, self.junkWaveLeftState, self.volleyLoopState }
end

function TrashbotAttackState.refresh( self ) end

function TrashbotAttackState.sv_setRightAttack( self, attackIndex )
	if attackIndex == TrashbotAttack.BULLET_SPRAY then
		self.rightState = self.bulletSprayRightState
	elseif attackIndex == TrashbotAttack.JUNK_WAVE then
		self.rightState = self.junkWaveRightState
	elseif attackIndex == TrashbotAttack.VOLLEY_BOMB then
		self.rightState = self.volleyBombRightState
	elseif attackIndex == TrashbotAttack.CHARGED_BULLET then
		self.rightState = self.chargedBulletRightState
	elseif attackIndex == TrashbotAttack.TRASH_BALL then
		self.rightState = self.trashBallState
	elseif attackIndex == TrashbotAttack.TURBO_BULLET_SPRAY then
		self.rightState = self.turboBulletSprayRightState
	elseif attackIndex == TrashbotAttack.LAUGH then
		self.rightState = self.laughState
	elseif attackIndex == TrashbotAttack.CLEAR_PATTERN then
		self.rightState = self.clearPatternState
	elseif attackIndex == TrashbotAttack.PUSHBACK then
		self.rightState = self.pushbackState
	elseif attackIndex == TrashbotAttack.SPRAY_GROUND then
		self.rightState = self.sprayGroundState
	elseif attackIndex == TrashbotAttack.CONTINUOUS_VOLLEY then
		self.rightState = self.volleyLoopState
	elseif attackIndex == TrashbotAttack.TRASH_SPRINKLER then
		self.rightState = self.trashSprinklerRightState
	elseif attackIndex == TrashbotAttack.DESTRUCTION_SWAY then
		self.rightState = self.destructionSwayState
	else
		self.rightState = nil
	end

	if self.rightState then
		self.rightAttackType = attackIndex
	end

	if isAnyOf( self.rightState, self.twoHandedStates ) then
		-- leftState is unused together with two handed attacks
		self.leftState = nil
	end
end

function TrashbotAttackState.sv_setLeftAttack( self, attackIndex )
	if attackIndex == TrashbotAttack.BULLET_SPRAY then
		self.leftState = self.bulletSprayLeftState
	elseif attackIndex == TrashbotAttack.JUNK_WAVE then
		self.leftState = self.junkWaveLeftState
	elseif attackIndex == TrashbotAttack.VOLLEY_BOMB then
		self.leftState = self.volleyBombLeftState
	elseif attackIndex == TrashbotAttack.CHARGED_BULLET then
		self.leftState = self.chargedBulletLeftState
	elseif attackIndex == TrashbotAttack.TRASH_BALL then
		-- Wrong usage, forcing the two handed state to the rightState
		self.rightState = self.trashBallState
		self.leftState = nil
	elseif attackIndex == TrashbotAttack.TURBO_BULLET_SPRAY then
		self.leftState = self.turboBulletSprayLeftState
	elseif attackIndex == TrashbotAttack.LAUGH then
		-- Wrong usage, forcing the two handed state to the rightState
		self.rightState = self.laughState
		self.leftState = nil
	elseif attackIndex == TrashbotAttack.CLEAR_PATTERN then
		-- Wrong usage, forcing the two handed state to the rightState
		self.rightState = self.clearPatternState
		self.leftState = nil
	elseif attackIndex == TrashbotAttack.PUSHBACK then
		-- Wrong usage, forcing the two handed state to the rightState
		self.rightState = self.pushbackState
		self.leftState = nil
	elseif attackIndex == TrashbotAttack.SPRAY_GROUND then
		-- Wrong usage, forcing the two handed state to the rightState
		self.rightState = self.sprayGroundState
		self.leftState = nil
	elseif attackIndex == TrashbotAttack.CONTINUOUS_VOLLEY then
		-- Wrong usage, forcing the two handed state to the rightState
		self.rightState = self.volleyLoopState
		self.left = nil
	elseif attackIndex == TrashbotAttack.TRASH_SPRINKLER then
		self.leftState = self.trashSprinklerLeftState
	elseif attackIndex == TrashbotAttack.DESTRUCTION_SWAY then
		-- Wrong usage, forcing the two handed state to the rightState
		self.rightState = self.destructionSwayState
		self.leftState = nil
	else
		self.leftState = nil
	end

	if self.leftState then
		self.leftAttackType = attackIndex
	end

	if isAnyOf( self.rightState, self.twoHandedStates ) then
		-- leftState is unused together with two handed attacks
		if self.leftState then
			sm.log.warning( "TrashbotAttackState's left side was forced to disable!" )
		end
		self.leftState = nil
	end
end

function TrashbotAttackState.sv_setLookDirection( self, lookDirection )
	if self.rightState and self.rightState.sv_setLookDirection then
		self.rightState:sv_setLookDirection( lookDirection )
	end
	if self.leftState and self.leftState.sv_setLookDirection then
		self.leftState:sv_setLookDirection( lookDirection )
	end
	if self.bulletHellState and self.bulletHellState.sv_setLookDirection then
		self.bulletHellState:sv_setLookDirection( lookDirection )
	end
end

function TrashbotAttackState.sv_setRightPosition( self, worldPosition )
	if self.rightState then
		if not isAnyOf( self.rightState, self.twoHandedStates ) and self.rightState.sv_setPosition then
			self.rightState:sv_setPosition( worldPosition )
		elseif self.rightState.sv_setRightPosition  then
			self.rightState:sv_setRightPosition( worldPosition )
		end
	end
end

function TrashbotAttackState.sv_setLeftPosition( self, worldPosition )
	if self.rightState and isAnyOf( self.rightState, self.twoHandedStates ) and self.rightState.sv_setLeftPosition then
			self.rightState:sv_setLeftPosition( worldPosition )
		return
	end
	if self.leftState then
		if not isAnyOf( self.leftState, self.twoHandedStates ) and self.leftState.sv_setPosition then
			self.leftState:sv_setPosition( worldPosition )
		end
	end
end

function TrashbotAttackState.sv_setTarget( self, target )
	if self.bulletHellState then
		self.bulletHellState:sv_setTarget( target )
	end
end

function TrashbotAttackState.sv_setLeftTarget( self, target )
	if self.leftState and self.leftState.sv_setTarget then
		self.leftState:sv_setTarget( target )
	end
end

function TrashbotAttackState.sv_setRightTarget( self, target )
	if self.rightState and self.rightState.sv_setTarget then
		self.rightState:sv_setTarget( target )
	end
end

function TrashbotAttackState.sv_setStage( self, stageIndex )
	if self.rightState and self.rightState.sv_setStage then
		self.rightState:sv_setStage( stageIndex )
	end
	if self.leftState and self.leftState.sv_setStage then
		self.leftState:sv_setStage( stageIndex )
	end
	if self.bulletHellState then
		self.bulletHellState:sv_setStage( stageIndex )
	end
end

function TrashbotAttackState.sv_isAttackTwoHanded( self, state )
	return isAnyOf( state, self.twoHandedAttacks )
end

function TrashbotAttackState.sv_isRightTwoHanded( self )
	if self.rightState and isAnyOf( self.rightState, self.twoHandedStates ) then
		return true
	end
	return false
end

function TrashbotAttackState.sv_isLeftAbortable( self )
	if self.leftState and isAnyOf( self.leftState, self.loopDurationAffectedStates ) then
		return true
	end
	return false
end

function TrashbotAttackState.sv_isRightAbortable( self )
	if self.rightState and isAnyOf( self.rightState, self.loopDurationAffectedStates ) then
		return true
	end
	return false
end

function TrashbotAttackState.sv_tryAbortAttacks( self )
	if self.rightState and isAnyOf( self.rightState, self.abortableStates ) then
		if self.rightState.abort then
			self.rightState:abort()
		end
	end
	if self.leftState and isAnyOf( self.leftState, self.abortableStates ) then
		if self.leftState.abort then
			self.leftState:abort()
		end
	end
end

function TrashbotAttackState.sv_getLeftAttackType( self )
	return self.leftAttackType
end

function TrashbotAttackState.sv_getRightAttackType( self )
	return self.rightAttackType
end

--[[API functions]]

function TrashbotAttackState.startLeft( self )
	if self.leftState then
		self.leftState:start()
	end
end

function TrashbotAttackState.startRight( self )
	if self.rightState then
		self.rightState:start()
	end
end

function TrashbotAttackState.start( self )
	if self.rightState then
		self.rightState:start()
	end
	if self.leftState then
		self.leftState:start()
	end
	if self.bulletHellState then
		self.bulletHellState:start()
	end
end

function TrashbotAttackState.stop( self )
	if self.rightState then
		self.rightState:stop()
	end
	if self.leftState then
		self.leftState:stop()
	end
end

function TrashbotAttackState.stun( self )
	if self.bulletHellState then
		self.bulletHellState:stun()
	end
end

function TrashbotAttackState.deactivateBulletHell( self )
	if self.bulletHellState then
		self.bulletHellState:deactivate()
	end
end

function TrashbotAttackState.setPatternName( self, name )
	if self.bulletHellState then
		self.bulletHellState:setPatternName( name )
	end
end

function TrashbotAttackState.isBulletHellActive( self )
	if self.bulletHellState then
		return self.bulletHellState:isActive()
	end
	return false
end

function TrashbotAttackState.setTrashBallPreset( self, presetName )
	if self.trashBallState then
		self.trashBallState:sv_setTrashBallPreset( presetName )
	end
end

function TrashbotAttackState.setWaveAmount( self, waveAmount )
	self.junkWaveRightState:setWaveAmount( waveAmount )
	self.junkWaveLeftState:setWaveAmount( waveAmount )
end

function TrashbotAttackState.setColor( self, color )
	self.junkWaveRightState:setColor( color )
	self.junkWaveLeftState:setColor( color )
end

function TrashbotAttackState.setLeftLoopDuration( self, loopDuration )
	if self.leftState and isAnyOf( self.leftState, self.loopDurationAffectedStates ) then
		self.leftState:setLoopDuration( loopDuration )
	end
end

function TrashbotAttackState.setRightLoopDuration( self, loopDuration )
	if self.rightState and isAnyOf( self.rightState, self.loopDurationAffectedStates ) then
		self.rightState:setLoopDuration( loopDuration )
	end
end

function TrashbotAttackState.setLeftClockwise( self, clockwise )
	if self.leftState and self.leftState.setClockwise then
		self.leftState:setClockwise( clockwise )
	end
end

function TrashbotAttackState.setRightClockwise( self, clockwise )
	if self.rightState and self.rightState.setClockwise then
		self.rightState:setClockwise( clockwise )
	end
end

function TrashbotAttackState.setFightType( self, fightType )
	for _, state in pairs( self.typeAffectedStates ) do
		if state.setFightType then
			state:setFightType( fightType )
		end
	end
end

function TrashbotAttackState.onFixedUpdate( self, dt )
	if self.rightState then
		self.rightState:onFixedUpdate( dt )
	end
	if self.leftState then
		self.leftState:onFixedUpdate( dt )
	end
	if self.bulletHellState then
		self.bulletHellState:onFixedUpdate( dt )
	end
end

function TrashbotAttackState.onUnitUpdate( self, dt )
	if self.rightState then
		self.rightState:onUnitUpdate( dt )
	end
	if self.leftState then
		self.leftState:onUnitUpdate( dt )
	end
end

function TrashbotAttackState.isLeftDone( self )
	if self.leftState then
		local doneLeft, _ = self.leftState:isDone()
		if doneLeft then
			self.leftAttackType = nil
			self.leftState = nil
		end
		return doneLeft
	end
	self.leftAttackType = nil
	return true
end

function TrashbotAttackState.isRightDone( self )
	if self.rightState then
		local doneRight, _ = self.rightState:isDone()
		if doneRight then
			self.rightAttackType = nil
			self.rightState = nil
		end
		return doneRight
	end
	self.rightAttackType = nil
	return true
end

function TrashbotAttackState.isDone( self )
	if self.rightState and self.leftState then
		local doneRight, _ = self.rightState:isDone()
		local doneLeft, _ = self.leftState:isDone()
		if doneRight and doneLeft then
			return true, "all done"
		elseif doneRight then
			return false, "right done, waiting on left"
		elseif doneLeft then
			return false, "left done, waiting on right"
		end
		return false, "waiting on right and left"
	elseif self.rightState then
		local done, _ = self.rightState:isDone()
		if done then
			return true, "right done"
		end
		return false, "waiting on right"
	elseif self.leftState then
		local done, _ = self.leftState:isDone()
		if done then
			return true, "left done"
		end
		return false, "waiting on left"
	end
	return true, "nostates"
end

function TrashbotAttackState.getMovementDirection( self )
	return self.unit.character.direction
end

function TrashbotAttackState.getFacingDirection( self )
	return self.unit.character.direction
end

function TrashbotAttackState.getMovementType( self )
	return "stand"
end

function TrashbotAttackState.getWantsJump( self )
	return false
end
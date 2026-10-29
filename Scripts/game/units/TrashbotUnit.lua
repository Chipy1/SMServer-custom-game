dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/CombatAttackState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/TrashbotAttackState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_loot.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/trashbot/TrashbotStageValues.lua"

TrashbotUnit = class(nil)

local TargetingAttacks = {
	TrashbotAttack.BULLET_SPRAY,
	TrashbotAttack.CHARGED_BULLET,
	TrashbotAttack.TURBO_BULLET_SPRAY,
	TrashbotAttack.VOLLEY_BOMB
}

local AimedAttacks = {
	TrashbotAttack.BULLET_SPRAY,
	TrashbotAttack.CHARGED_BULLET,
	TrashbotAttack.TURBO_BULLET_SPRAY,
}

local ProjectileHitEffects = {
	[tostring( projectile_potato )] = "Trashbot - Hitimpact",
	[tostring( projectile_smallpotato )] = "Trashbot - Hitimpact_fries",
	[tostring( projectile_fries )] = "Trashbot - Hitimpact_fries",
}

local ProjectileRicochetEffects = {
	[tostring( projectile_potato )] = "Trashbot - Hitimpactnodamage_ricochet",
	[tostring( projectile_smallpotato )] = "Trashbot - Hitimpactnodamage_ricochet",
	[tostring( projectile_fries )] = "Trashbot - Hitimpactnodamage_ricochet_fries", -- replace with fries version
}

local IntermissionSequence = {
	sequence = {
		{ type = TrashbotAttack.PUSHBACK, count = 1 },
	},
	nextPatternIndex = { 1 },
	eyeOpen = false,
	bulletPatternName = nil,
	waitTimeBetweenAttacks = 0.0,
}

local DestructionItemSpawns = {
	ITEMS.obj_fittings_ac,
	ITEMS.obj_fittings_cordbend,
	ITEMS.obj_decor_toiletroll,
	ITEMS.obj_decor_toiletroll,
	ITEMS.obj_decor_sink,
	ITEMS.obj_decor_babyduck,
	ITEMS.obj_containers_barrel_tomato,
	ITEMS.obj_decor_cone,
	ITEMS.obj_decor_cone,
	ITEMS.obj_decor_cone,
	ITEMS.obj_fittings_powerstation,
	ITEMS.obj_fittings_7x8_bend_glass,
	ITEMS.obj_containers_woodbox,
	ITEMS.obj_containers_woodbox,
	ITEMS.obj_road_signcurve,
	ITEMS.obj_decor_mug,
	ITEMS.obj_scrap_smallwheel,
	ITEMS.obj_scrap_smallwheel,
	ITEMS.obj_scrap_smallwheel,
	ITEMS.obj_scrap_gasengine,
	ITEMS.obj_scrap_driverseat,
	ITEMS.obj_scrap_seat,
}

local DestroyEffectsOffset = sm.vec3.new( 0, 0, 2.0 )
local CoreUuid = sm.uuid.new( "86d95db4-6355-49ce-a645-03938c986dca" )
local LookMaxRadiansPerSecond = math.rad( 75 )
local AimedRadiansPerSecond = math.rad( 20 )
local part_spawn_force = 60.0 -- Settable force multiplier for spawned parts
local ActivateCombatDistance = 56.0
local DisableCombatDistance = 64.0
local MeleeAttackRange = 4.0
local EscapeTime = 14.3
local DestroyTime = 8.5
local AlertedTime = 4.6
local RecoverTime = 2.5
local StageThinkTime = { 1.1, 0.6, 0.2 }
local ReductionBetweenAttacksPerPlayer = 0.20 -- for each player in the game lower the wait time between attacks with 10%
local MaxReductionBetweenAttacks = 0.6 -- capped at 60% lower wait time between attacks
local PlayerCountCheckFrequency = 200 -- ticks = 5 seconds
local PlayerCountRangeLimit = 128
local PlayerCountHpMultiplier = {
	1.0,
	1.1,
	1.2,
	1.3,
	1.4
}
local DefaultEyeHitThreshold = 3

function TrashbotUnit.sv_checkPlayersInRange( self )
	local playersInRange = GetPlayersInRange( self.unit.character.worldPosition, PlayerCountRangeLimit, self.unit.character:getWorld() )
	self.maxEncounteredPlayers = math.max( self.maxEncounteredPlayers, #playersInRange )
end

function TrashbotUnit.server_onCreate( self )
	self.sequenceTarget = nil
	self.attackTarget = nil
	self.currentAttackTarget = nil
	self.currentTarget = nil
	self.previousTarget = nil
	self.rotationSpeedOverride = nil
	self.lookDirection = self.unit.character.direction:safeNormalize(sm.vec3.new(0, 1, 0))
	self.lookingAtTarget = false
	self.leftAttackType = nil
	self.rightAttackType = nil
	self.maxEncounteredPlayers = 1
	self.playerCheckTickCounter = 0
	self:sv_checkPlayersInRange()

	self.coreHits = 0
	self.currentHealthFraction = 1.0
	
	self.forcedPattern = false
	
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
		self.saved.damageTaken = 0
		self.saved.totalCoreHits = 0
		self.saved.attackStage = 1
		self.saved.currentAttackPatternIndex = 1
		local worldData = self.unit.character:getWorld().publicData
		self.saved.fightType = worldData.type == "Overworld" and 1 or 2
		if self.params and self.params.fightOverride then
			self.saved.fightType = self.params.fightOverride
		end
	else
		-- Resets boss on spawn if there are no players nearby
		local playersInRange = GetPlayerCharactersInSphere( self.unit.character.worldPosition, ActivateCombatDistance, self.unit.character:getWorld() )
		if #playersInRange <= 0 then
			self:sv_resetFight()
		end
	end
	
	self.unit.publicData = { fightType = self.saved.fightType }
	if self.saved.fightType == 1 then
		sm.event.sendToCharacter( self.unit.character, "sv_e_setFightType", { fightType = self.saved.fightType }, sm.event.types.blind )
	end

	self.totalCoreHitsToDestroy = TRASHBOT_STATS[self.saved.fightType].coreHitsToRecover * #TRASHBOT_PATTERNS[self.saved.fightType]
	self.attackDurationTimer = 0
	self.attackQueue = {}
	self.currentQueueIndex = 1
	self.currentPattern = TRASHBOT_PATTERNS[self.saved.fightType][self.saved.attackStage][self.saved.currentAttackPatternIndex]
	if TRASHBOT_PATTERNS[self.saved.fightType][self.saved.attackStage] ~= nil and TRASHBOT_PATTERNS[self.saved.fightType][self.saved.attackStage][self.saved.currentAttackPatternIndex] ~= nil then
		for _, attackData in ipairs(TRASHBOT_PATTERNS[self.saved.fightType][self.saved.attackStage][self.saved.currentAttackPatternIndex].sequence) do
			for i = 1, ( attackData.count or 1 ) do
				self.attackQueue[#self.attackQueue + 1] = attackData
			end
		end
	end
	
	if self.currentPattern.eyeOpen ~= nil and self.eyeOpen ~= self.currentPattern.eyeOpen then
		self.eyeOpen = self.currentPattern.eyeOpen
		if self.eyeOpen then
			self.unit:sendCharacterEvent( "eyeOpen" )
		else
			self.unit:sendCharacterEvent( "eyeClose" )
		end
	end

	self.eyeOpenTicks = self.currentPattern.eyeOpenDuration and self.currentPattern.eyeOpenDuration * 40 or math.huge
	self.eyeClosedTicks = self.currentPattern.eyeClosedDuration and self.currentPattern.eyeClosedDuration * 40 or math.huge
	self.eyeOpenTickCounter = 0
	self.eyeClosedTickCounter = 0
	self.eyeHitCounter = 0

	self.previousWaitTime = self.currentPattern.waitTimeBetweenAttacks or 1.0
	self.waitTimeCounter = self.previousWaitTime
	self.position = self.unit.character.worldPosition
	self.world = self.unit.character:getWorld()
	self.unitId = self.unit.id

	g_respawnManager.Sv_ActivateCellRange( self.position, self.world )

	self.isAggressive = true
	if self.params then
		if self.params.deathEvent then
			self.saved.deathEvent = self.params.deathEvent
			if QuestManager.Sv_IsQuestActive("quest_scrapyard") then
				self.saved.activeQuest = "quest_scrapyard"
				QuestManager.Sv_SendEvent("event.quest_scrapyard.spawn_trashbot")
			elseif QuestManager.Sv_IsQuestActive("quest_clear_warehouse") then
				self.saved.activeQuest = "quest_clear_warehouse"
				QuestManager.Sv_SendEvent("event.quest_clear_warehouse.spawn_trashbot")
			end
			self.isAggressive = false
		end
	end

	self.storage:save(self.saved)

	sm.message.subscribe( MESSAGE_TYPES.EFFECT_EVENTS.ClearWarehouseAttack, "sv_m_clearWarehouseAttack" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.SetTrashbotBossMusic, "sv_m_setBossMusic" )

	if self.saved.hasBossMusicControl and self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_e_setBossMusicControl", true, sm.event.types.blind )
	end

	self.stateTicker = Ticker()
	self.stateTicker:init()

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Attacks
	self.broomAttackState = self.unit:createState( "meleeAttack" )
	self.broomAttackState.meleeType = melee_farmbotswipe
	self.broomAttackState.event = "broom"
	self.broomAttackState.damage = 10
	self.broomAttackState.attackRange = MeleeAttackRange - self.unit.character:getRadius()
	self.broomAttackState.animationCooldown = 1.0 * 40
	self.broomAttackState.attackCooldown = 1.0 * 40
	self.broomAttackState.globalCooldown = 0.0 * 40
	self.broomAttackState.attackDelay = 0.375 * 40
	self.broomAttackState.power = 10000.0

	-- Combat
	self.combatAttackState = CombatAttackState()
	self.combatAttackState:sv_onCreate( self.unit )
	self.combatAttackState.debugName = "combatAttackState"
	self.stateTicker:addState( self.combatAttackState )
	self.combatAttackState:sv_addAttack( self.broomAttackState )

	-- Trashbot attack state
	self.trashbotAttackState = TrashbotAttackState()
	self.trashbotAttackState:sv_onCreate( self.unit )
	self.trashbotAttackState.debugName = "trashbotAttackState"

	-- Stunned
	self.stunnedEventState = self.unit:createState( "wait" )
	self.stunnedEventState.debugName = "stunnedState"
	self.stunnedEventState.time = TRASHBOT_STATS[self.saved.fightType].stunTime
	self.stunnedEventState.interruptible = false
	self.stunnedEventState.name = "koIn"

	-- Vulnerable
	self.vulnerableEventState = self.unit:createState( "wait" )
	self.vulnerableEventState.debugName = "vulnerableState"
	self.vulnerableEventState.time = 12.0
	self.vulnerableEventState.interruptible = false

	-- Cinematic state
	self.cinematicEventState = self.unit:createState( "wait" )
	self.cinematicEventState.debugName = "cinematicState"
	self.cinematicEventState.name = self.saved.activeQuest == "quest_scrapyard" and "underground_cinematic" or "cinematic"
	self.cinematicEventState.time = 30.0
	self.cinematicEventState.interruptible = false

	-- Recover
	self.recoverEventState = self.unit:createState( "wait" )
	self.recoverEventState.debugName = "recoverState"
	self.recoverEventState.time = RecoverTime
	self.recoverEventState.interruptible = false
	self.recoverEventState.name = "koOut"

	-- HurtEye
	self.hurtEyeEventState = self.unit:createState( "wait" )
	self.hurtEyeEventState.debugName = "hurtEyeState"
	self.hurtEyeEventState.time = 0.5
	self.hurtEyeEventState.interruptible = false
	self.hurtEyeEventState.name = "hurteye"

	-- Think
	self.thinkEventState = self.unit:createState( "wait" )
	self.thinkEventState.debugName = "thinkState"
	self.thinkEventState.time = StageThinkTime[1]
	self.thinkEventState.interruptible = false
	self.thinkEventState.name = "think"

	-- Escape
	self.escapeEventState = self.unit:createState( "wait" )
	self.escapeEventState.debugName = "escapeState"
	self.escapeEventState.time = EscapeTime
	self.escapeEventState.interruptible = false
	self.escapeEventState.name = "escape"

	-- Destroy
	self.destroyEventState = self.unit:createState( "wait" )
	self.destroyEventState.debugName = "destroyState"
	self.destroyEventState.time = DestroyTime
	self.destroyEventState.interruptible = false
	self.destroyEventState.name = "destroy"

	-- Alerted
	self.alertedEventState = self.unit:createState( "wait" )
	self.alertedEventState.debugName = "alertedState"
	self.alertedEventState.time = AlertedTime
	self.alertedEventState.interruptible = false
	self.alertedEventState.name = "alerted"


	self.aggressiveStates = { self.trashbotAttackState, self.combatAttackState, self.thinkEventState }

	if self.isAggressive then
		self.currentState = self.thinkEventState
	else
		self.currentState = self.cinematicEventState
	end
	self.currentState:start()

	self.trashbotAttackState:setFightType( self.saved.fightType )
	print( "-- TrashbotUnit created --" )
end

function TrashbotUnit.sv_resetFight( self )
	self.saved.damageTaken = 0
	self.saved.totalCoreHits = 0
	self.saved.attackStage = 1
	self.saved.currentAttackPatternIndex = 1
	self.currentQueueIndex = 1
	self.currentHealthFraction = 1.0
	self.maxEncounteredPlayers = 1
	self.currentPattern = TRASHBOT_PATTERNS[self.saved.fightType][self.saved.attackStage][self.saved.currentAttackPatternIndex]
end

function TrashbotUnit.server_onDestroy( self )
	g_respawnManager.Sv_DisableCellRange( self.position, self.world )
	print("-- TrashbotUnit terminated --")
end

function TrashbotUnit.sv_getRightArmPosition( self )
	local rightArmPosition = self.unit.character:getTpBonePos( "r_arm04_jnt" )
	if not rightArmPosition then
		local heightOffset = sm.vec3.new( 0, 0, 1.5 )
		local sideOffset = self.lookDirection:cross( sm.vec3.new( 0, 0, 1 ) ) * 3.5
		local directionOffset = self.lookDirection * 2.5

		rightArmPosition = self.unit.character.worldPosition + heightOffset + sideOffset + directionOffset
	end
	return rightArmPosition
end

function TrashbotUnit.sv_getLeftArmPosition( self )
	local leftArmPosition = self.unit.character:getTpBonePos( "l_arm04_jnt" )
	if not leftArmPosition then
		local heightOffset = sm.vec3.new( 0, 0, 1.5 )
		local sideOffset = self.lookDirection:cross( sm.vec3.new( 0, 0, 1 ) ) * -3.5
		local directionOffset = self.lookDirection * 2.5

		leftArmPosition = self.unit.character.worldPosition + heightOffset + sideOffset + directionOffset
	end

	return leftArmPosition
end

function TrashbotUnit.server_onFixedUpdate( self, dt )
	if not sm.exists( self.unit ) or self.destroyed then
		return
	end
	if self.currentState == self.trashbotAttackState then
		if self.eyeOpen then
			self.eyeOpenTickCounter = self.eyeOpenTickCounter + 1
			if self.eyeOpenTickCounter >= self.eyeOpenTicks then
				self.eyeOpen = false
				self.eyeOpenTickCounter = 0
				self.eyeHitCounter = 0
				self.unit:sendCharacterEvent( "eyeClose" )
			end
		end
		
		if not self.eyeOpen then
			self.eyeClosedTickCounter = self.eyeClosedTickCounter + 1
			if self.eyeClosedTickCounter >= self.eyeClosedTicks then
				self.eyeOpen = true
				self.eyeClosedTickCounter = 0
				self.eyeHitCounter = 0
				self.unit:sendCharacterEvent( "eyeOpen" )
			end
		end
	end

	self.playerCheckTickCounter = self.playerCheckTickCounter + 1
	if self.playerCheckTickCounter >= PlayerCountCheckFrequency then
		self:sv_checkPlayersInRange()
		self.playerCheckTickCounter = 0
	end

	self.stateTicker:tick()

	local shouldLookAtTarget = false
	if self.currentState then
		self.sequenceTarget = sm.exists( self.sequenceTarget ) and self.sequenceTarget or nil
		local target = sm.exists( self.attackTarget ) and self.attackTarget or self.sequenceTarget
		self.currentTarget = target or self.currentTarget

		self.trashbotAttackState:sv_setRightPosition( self:sv_getRightArmPosition() )
		self.trashbotAttackState:sv_setLeftPosition( self:sv_getLeftArmPosition() )
		self.trashbotAttackState:sv_setTarget( self.sequenceTarget )
		self.trashbotAttackState:sv_setStage( self.saved.attackStage )

		if self.currentTarget and sm.exists( self.currentTarget ) then
			local inDestructionPhase = self.currentState == self.trashbotAttackState and ( self.trashbotAttackState:sv_getRightAttackType() == TrashbotAttack.DESTRUCTION_SWAY )
			if self.currentState == self.vulnerableEventState or inDestructionPhase then
				local corePosition = self.unit.character:getTpBonePos( "powercore_05_jnt" )
				if not corePosition then
					corePosition = self.unit.character.worldPosition + self.lookDirection * 8.5 + sm.vec3.new( 0, 0, -1.0 )
				end
				local coreRotation = self.unit.character:getTpBoneRot( "powercore_05_jnt" )
				if not coreRotation then
					coreRotation = sm.quat.identity()
				end
				if self.core == nil then
					-- Spawn vulnerable core
					self.core = sm.harvestable.createHarvestable( CoreUuid, corePosition, coreRotation )
					self.core:setParams( { trashbot = self.unit, final = inDestructionPhase } )
				end
				if sm.exists( self.core ) then
					self.core:setPosition( corePosition )
					self.core:setRotation( coreRotation )
				end
			elseif self.currentState == self.recoverEventState or self.currentState == self.destroyEventState then
				if self.core and sm.exists( self.core ) then
					-- Remove vulnerable core
					self.core:destroy()
					self.core = nil
				end
			elseif self.rotate then
				-- Rotate continuously
				local rotationZ = TRASHBOT_ROTATION_SPEED * dt
				self.lookDirection = ( self.lookDirection:rotateZ( rotationZ ) ):safeNormalize( self.lookDirection )
			elseif isAnyOf( self.currentState, self.aggressiveStates ) then
				-- Look at target
				local fromToTarget = self.currentTarget.worldPosition - self.unit.character.worldPosition
				local flatFromToTarget = sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 )
				local wantedLookDirection = flatFromToTarget:safeNormalize( self.lookDirection )

				-- Radians to rotate this step
				local radiansToRotate = math.acos( clamp( self.lookDirection:dot( wantedLookDirection ), -1, 1 ) )

				local isAiming = isAnyOf( self.leftAttackType, AimedAttacks ) or isAnyOf( self.rightAttackType, AimedAttacks )
				local rotationStep = math.min( ( isAiming and AimedRadiansPerSecond or LookMaxRadiansPerSecond ) * dt, radiansToRotate )

				-- Find which direction to rotate
				local rotationZ = 0.0
				local determinant = wantedLookDirection.x * self.lookDirection.y -
				wantedLookDirection.y * self.lookDirection.x
				if determinant <= -FLT_EPSILON then
					rotationZ = rotationStep
				elseif determinant >= FLT_EPSILON then
					rotationZ = -rotationStep
				end
				self.lookDirection = ( self.lookDirection:rotateZ( rotationZ ) ):safeNormalize( self.lookDirection )
				shouldLookAtTarget = true
			end

			self.trashbotAttackState:sv_setLookDirection( self.lookDirection )
		end
		self.currentState:onFixedUpdate( dt )
	end

	-- Update target for character
	if self.currentTarget ~= self.previousTarget then
		self:sv_updateCharacterTarget()
		if self.previousTarget == nil and self.currentState ~= self.cinematicEventState and self.currentState ~= self.stunnedEventState then
			self.currentState = self.alertedEventState
			self.currentState:start()
		end
		self.previousTarget = self.currentTarget
	end

	if self.lookingAtTarget ~= shouldLookAtTarget then
		self.lookingAtTarget = shouldLookAtTarget
		self:sv_toggleLookAtTarget()
	end
end

function TrashbotUnit.server_onUnitUpdate( self, dt )
	if not sm.exists( self.unit ) or self.destroyed then
		return
	end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	if self.currentState == self.trashbotAttackState or self.currentState == self.thinkEventState then
		self.attackDurationTimer = self.attackDurationTimer + dt
	end

	-- Find target
	if self.currentTarget == nil or not sm.exists( self.currentTarget ) then
		self.currentTarget = self:sv_getNewTarget()
	end

	local inMeleeAttackRange = false
	if self.currentTarget then
		local fromToTarget = self.currentTarget.worldPosition - self.unit.character.worldPosition

		inMeleeAttackRange = fromToTarget:length() <= MeleeAttackRange

		local flatFromToTarget = sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 )
		flatFromToTarget = flatFromToTarget:safeNormalize( self.unit.character.direction )
		self.combatAttackState:sv_setAttackDirection( flatFromToTarget )
	end
	local shouldBeStunned = self.saved.damageTaken >= TRASHBOT_STATS[self.saved.fightType].healthPerPhase * PlayerCountHpMultiplier[math.min( self.maxEncounteredPlayers, #PlayerCountHpMultiplier )]
	local shouldRecover = self.coreHits >= TRASHBOT_STATS[self.saved.fightType].coreHitsToRecover
	local shouldBeDestroyed = self.saved.totalCoreHits >= self.totalCoreHitsToDestroy

	local prevState = self.currentState
	local done, result = self.currentState:isDone()
	local abortState = self.currentState ~= self.escapeEventState and self.currentState ~= self.destroyEventState and
		(
			( shouldBeStunned and self.currentState == self.thinkEventState ) or
			( shouldRecover and self.currentState == self.vulnerableEventState ) or
			( shouldBeStunned and self.trashbotAttackState:sv_getRightAttackType() == TrashbotAttack.DESTRUCTION_SWAY )
		)
	self.rightAttackType = self.trashbotAttackState:sv_getRightAttackType()
	self.leftAttackType = self.trashbotAttackState:sv_getLeftAttackType()
	local rightDone = self.trashbotAttackState:isRightDone()
	if rightDone and ( self.rightAttackType == TrashbotAttack.TRASH_BALL or self.rightAttackType == TrashbotAttack.SPRAY_GROUND ) then
		self.rotate = false
	end
	local leftDone = self.trashbotAttackState:isLeftDone()
	local canStartAttack = ( ( self.currentState == self.thinkEventState and done ) or self.currentState == self.trashbotAttackState or self.currentState == self.combatAttackState ) and not ( shouldBeDestroyed or shouldBeStunned or shouldRecover )
	if self.currentState ~= self.destroyEventState and not ( self.rightAttackType == TrashbotAttack.DESTRUCTION_SWAY ) then
		if ( rightDone or leftDone ) and canStartAttack then
			if self.currentTarget and self:sv_getDistanceToTarget() <= DisableCombatDistance then
				-- Select the next attack
				if inMeleeAttackRange then
					-- Hit nearby player
					self.currentState = self.combatAttackState
					done = false
				else
					local attackStage = TRASHBOT_PATTERNS[self.saved.fightType][self.saved.attackStage]
					local attackPattern = self.currentPattern or attackStage[self.saved.currentAttackPatternIndex]
					self.waitTimeCounter = self.waitTimeCounter + dt
					if self.waitTimeCounter >= self.previousWaitTime then
						if attackPattern.loopDuration and self.attackDurationTimer >= attackPattern.loopDuration then
							self:sv_selectNextPattern()
							attackPattern = self.currentPattern
						end
	
						local nextAttack = self.attackQueue[self.currentQueueIndex]
						local attackUsed = false
						local wasRight = false
						local canUseAttack = true
	
						if nextAttack then
							if self.trashbotAttackState:sv_isAttackTwoHanded(nextAttack.type) then
								canUseAttack = rightDone and leftDone
							end
							if canUseAttack then
								if rightDone and not ( nextAttack.forceArm ~= nil and nextAttack.forceArm == TRASHBOT_ARM.left ) and not ( isAnyOf( self.leftAttackType, AimedAttacks ) and ( isAnyOf( nextAttack.type, AimedAttacks ) ) ) then
									self.trashbotAttackState:sv_setRightAttack( nextAttack.type )
									if leftDone then
										self.trashbotAttackState:sv_setLeftAttack( nil )
									end
									attackUsed = true
									wasRight = true
								elseif leftDone and not self.trashbotAttackState:sv_isRightTwoHanded() and not ( nextAttack.forceArm ~= nil and nextAttack.forceArm == TRASHBOT_ARM.right ) and not ( isAnyOf( self.rightAttackType, AimedAttacks ) and ( isAnyOf( nextAttack.type, AimedAttacks ) ) ) then
									self.trashbotAttackState:sv_setLeftAttack( nextAttack.type )
									if rightDone then
										self.trashbotAttackState:sv_setRightAttack( nil )
									end
									wasRight = false
									attackUsed = true
								end
							end
							if attackUsed then
								if self.currentQueueIndex == 1 then
									self.forcedPattern = false
									self.sequenceTarget = self:sv_getNewTarget()
								end
	
								self.trashbotAttackState:setPatternName( attackPattern.bulletPatternName )
								if self.currentQueueIndex == 1 then
									if attackPattern.eyeOpen ~= nil and self.eyeOpen ~= attackPattern.eyeOpen then
										self.eyeOpen = attackPattern.eyeOpen
										if self.eyeOpen then
											self.unit:sendCharacterEvent( "eyeOpen" )
										else
											self.unit:sendCharacterEvent( "eyeClose" )
										end
									end
	
									self.eyeOpenTicks = attackPattern.eyeOpenDuration and attackPattern.eyeOpenDuration * 40 or math.huge
									self.eyeClosedTicks = attackPattern.eyeClosedDuration and attackPattern.eyeClosedDuration * 40 or math.huge
									self.eyeOpenTickCounter = 0
									self.eyeClosedTickCounter = 0
									self.eyeHitCounter = 0
								end
								done = false
								self.waitTimeCounter = 0
								if nextAttack.duration ~= nil then
									if wasRight then
										self.trashbotAttackState:setRightLoopDuration( nextAttack.duration )
									else
										self.trashbotAttackState:setLeftLoopDuration( nextAttack.duration )
									end
								end
	
								if nextAttack.clockwise ~= nil then
									if wasRight then
										self.trashbotAttackState:setRightClockwise( nextAttack.clockwise )
									else
										self.trashbotAttackState:setLeftClockwise( nextAttack.clockwise )
									end
								end
	
								if nextAttack.preset ~= nil then
									self.trashbotAttackState:setTrashBallPreset( nextAttack.preset )
								end
								if nextAttack.waveAmount ~= nil then
									self.trashbotAttackState:setWaveAmount( nextAttack.waveAmount )
								end
	
								if nextAttack.color ~= nil then
									self.trashbotAttackState:setColor( nextAttack.color )
								end
	
								self.previousWaitTime = self.attackQueue[self.currentQueueIndex].nextAttackWaitTime or self.currentPattern.waitTimeBetweenAttacks or 1.0
								
								if self.maxEncounteredPlayers > 1 then
									self.previousWaitTime = math.max( self.previousWaitTime * ( 1 - ReductionBetweenAttacksPerPlayer * ( self.maxEncounteredPlayers - 1 ) ), self.previousWaitTime * ( 1.0 - MaxReductionBetweenAttacks ) )
								end
								if nextAttack.repeatable == false then
									table.remove( self.attackQueue, self.currentQueueIndex )
									self.currentQueueIndex = self.currentQueueIndex - 1
								end
								self.currentQueueIndex = self.currentQueueIndex + 1
								if self.currentQueueIndex > #self.attackQueue then
									if attackPattern.loopDuration then
										self.currentQueueIndex = 1
									else
										self:sv_selectNextPattern()
									end
								end
	
								if isAnyOf( nextAttack.type, AimedAttacks ) then
									self.attackTarget = self:sv_getNewTarget( self.currentAttackTarget )
									if self.attackTarget then
										self.currentAttackTarget = self.attackTarget
									end
								elseif isAnyOf( nextAttack.type, TargetingAttacks ) then
									local target = self:sv_getNewTarget( self.currentAttackTarget )
									if target then
										self.currentAttackTarget = target
									end
								end
	
								if wasRight then
									self.trashbotAttackState:sv_setRightTarget( self.currentAttackTarget or self.currentTarget )
								else
									self.trashbotAttackState:sv_setLeftTarget( self.currentAttackTarget or self.currentTarget )
								end
								if not self.currentAttackTarget then
									self.attackTarget = nil
								end
	
								if self.currentState == self.trashbotAttackState then
									if wasRight or self.trashbotAttackState:sv_isAttackTwoHanded( nextAttack.type ) then
										self.trashbotAttackState:startRight()
										if nextAttack.type == TrashbotAttack.TRASH_BALL or nextAttack.type == TrashbotAttack.SPRAY_GROUND then
											self.rotate = true
										end
									else
										self.trashbotAttackState:startLeft()
									end
								end
							end
						end
	
						self.currentState = self.trashbotAttackState
					end
				end
			else
				self.currentTarget = self:sv_getNewTarget()
				if self.currentTarget and self:sv_getDistanceToTarget() <= DisableCombatDistance then
					-- Wait for the next attack
					self.currentState = self.thinkEventState
				else
					self:sv_resetFight()
					-- Select non-combat state
					self.currentState = self.idleState
				end
			end
		elseif self.currentState == self.idleState then
			if self.trashbotAttackState:sv_getRightAttackType() ~= nil or self.trashbotAttackState:sv_getLeftAttackType() ~= nil or self.trashbotAttackState:isBulletHellActive() then
				self.trashbotAttackState:stop()
				self.trashbotAttackState:sv_setRightAttack( nil )
				self.trashbotAttackState:sv_setLeftAttack( nil )
				self.trashbotAttackState:stun()
			end
		elseif ( not rightDone or not leftDone ) and not canStartAttack then
			self.trashbotAttackState:sv_tryAbortAttacks()
			done = false
		end
	end

	if ( done or abortState ) then
		-- Select state
		if self.currentState == self.destroyEventState then
			self:sv_onDeath()
		elseif self.currentState == self.trashbotAttackState and ( self.rightAttackType == TrashbotAttack.DESTRUCTION_SWAY ) then
			self.currentState = self.destroyEventState
		elseif self.currentState == self.escapeEventState then
			self:sv_onDeath()
		elseif shouldRecover then
			self.currentState = self.recoverEventState
			self.coreHits = 0
			self.saved.attackStage = math.min( self.saved.attackStage + 1, #TRASHBOT_PATTERNS[self.saved.fightType] )
			self.saved.currentAttackPatternIndex = 1
			self.currentPattern = nil
			self.thinkEventState.time = StageThinkTime[math.min( self.saved.attackStage, #StageThinkTime )]
			self.forcePushbackAttack = true
			if self.saved.fightType == 1 then
				if self.saved.attackStage == 2 then
					DialogManager.Sv_PlayShoutDialog( dialog_trashbot_fight, "FirstPhaseDone", nil, DialogSpeakerName.Lorenzo, nil, 60 )
				elseif self.saved.attackStage == 3 then
					DialogManager.Sv_PlayShoutDialog( dialog_trashbot_fight, "SecondPhaseDone", nil, DialogSpeakerName.Lorenzo, nil, 60 )
				end
			end
			self.storage:save( self.saved )
		elseif self.forcePushbackAttack then
			self.forcePushbackAttack = false
			self.unit:sendCharacterEvent( "phase"..self.saved.attackStage )
			self.currentState = self.trashbotAttackState
			self.trashbotAttackState:sv_setLeftAttack( nil )
			self.trashbotAttackState:sv_setRightAttack( nil )
			if not shouldBeDestroyed then
				self:sv_selectNextPattern( IntermissionSequence )
				self.waitTimeCounter = math.huge
			else
				self.trashbotAttackState:stun()
			end
		elseif shouldBeDestroyed then
			if self.saved.fightType == 1 then
				sm.game.pauseSaving( "Trashbot Despawn", 40 * 30 )
				self:sv_setBossMusicControl( false )
				EffectManager.Sv_PlayNamedCinematic( { name = "cinematic.trashbotdespawn01", callbackData = { world = WorldManager.Sv_GetWorld( "overworld" ) }, interruptible = false } )
				sm.message.send( MESSAGE_TYPES.GENERAL.TrashbotDefeated )
				self.trashbotAttackState:deactivateBulletHell()
				self.currentState = self.escapeEventState
			end
		elseif shouldBeStunned then
			self.unit:sendCharacterEvent( "eyeClose" )
			self.unit:sendCharacterEvent( "removeProjectiles" )
			self.saved.damageTaken = 0
			self.currentHealthFraction = 1.0
			self.trashbotAttackState:setPatternName( nil )
			if self.saved.fightType == 1 then
				self.currentState = self.stunnedEventState
				DialogManager.Sv_PlayShoutDialog( dialog_trashbot_fight, "Downed", nil, DialogSpeakerName.Lorenzo, nil, 60 )
			elseif self.saved.fightType == 2 then
				if self.saved.attackStage < #TRASHBOT_PATTERNS[self.saved.fightType] then
					self.currentState = self.stunnedEventState
				else
					self.currentState = self.destroyEventState
				end
			end
			if self.trashbotAttackState then
				self.trashbotAttackState:stun()
			end
		elseif self.currentState == self.stunnedEventState then
			self.currentState = self.vulnerableEventState
		elseif self.currentState == self.vulnerableEventState then
			self.currentState = self.recoverEventState
			self.attackDurationTimer = 0
		elseif self.currentState == self.idleState then
			-- Initiate combat
			self.currentTarget = self:sv_getNewTarget()
			if self.currentTarget and self:sv_getDistanceToTarget() <= ActivateCombatDistance then
				self.currentState = self.thinkEventState
			end
		elseif self.currentState == self.hurtEyeEventState then
			self.currentState = self.thinkEventState
		elseif self.currentState == self.cinematicEventState then
			self.currentState = self.thinkEventState
		else
			if self.currentTarget and self:sv_getDistanceToTarget() <= DisableCombatDistance then
				-- Wait for the next attack
				if self.currentState ~= self.trashbotAttackState then
					self.currentState = self.thinkEventState
				end
			else
				-- Select non-combat state
				self.currentState = self.idleState
			end
		end
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
		if DEBUG_AI_STATES then
			print( self.currentState.debugName )
		end
	end
end

function TrashbotUnit.sv_getNewTarget( self, avoidTarget )
	local playersInRange = GetPlayerCharactersInSphere( self.unit.character.worldPosition, ActivateCombatDistance, self.unit.character:getWorld() )
	local previousTarget = avoidTarget or self.currentTarget or self.sequenceTarget
	local newTarget = nil
	if #playersInRange > 1 then
		for index, player in ipairs( playersInRange ) do
			if player == previousTarget then
				table.remove( playersInRange, index )
				break
			end
		end
		newTarget = playersInRange[math.random( 1, #playersInRange )]
	elseif #playersInRange == 1 then
		newTarget = playersInRange[1]
	end
	return newTarget
end

function TrashbotUnit.sv_selectNextPattern( self, forcedPattern )
	local attackStage = TRASHBOT_PATTERNS[self.saved.fightType][self.saved.attackStage]
	local attackPattern = forcedPattern or attackStage[self.saved.currentAttackPatternIndex]
	if self.currentPattern then
		self.saved.currentAttackPatternIndex = self.currentPattern.nextPatternIndex[math.random( 1, #self.currentPattern.nextPatternIndex )]
	else
		self.saved.currentAttackPatternIndex = attackPattern.nextPatternIndex[math.random( 1, #attackPattern.nextPatternIndex )]
	end
	self.attackDurationTimer = 0
	self.attackQueue = {}
	self.currentQueueIndex = 1
	self.waitTimeCounter = 0
	self.currentPattern = forcedPattern ~= nil and forcedPattern or TRASHBOT_PATTERNS[self.saved.fightType][self.saved.attackStage][self.saved.currentAttackPatternIndex]
	if self.currentPattern then
		for _, attackData in ipairs( self.currentPattern.sequence ) do
			for i = 1, ( attackData.count or 1 ) do
				if attackData.multiplayerOnly then
					if self.maxEncounteredPlayers > 1 then
						self.attackQueue[#self.attackQueue+1] = attackData
					end
				else
					self.attackQueue[#self.attackQueue + 1] = attackData
				end
			end
		end
	end
	self.storage:save( self.saved )
end

function TrashbotUnit.sv_getDistanceToTarget( self )
	if self.currentTarget and sm.exists( self.currentTarget ) then
		return ( self.unit.character.worldPosition - self.currentTarget.worldPosition ):length()
	end
	return math.huge
end

function TrashbotUnit.sv_e_coreDamaged( self, params )
	if self.currentState ~= self.vulnerableEventState then
		self:sv_e_eyeDamaged( params )
		return
	end
	if params ~= nil then
		return
	end
	if self.coreHits < TRASHBOT_STATS[self.saved.fightType].coreHitsToRecover then
		self.coreHits = self.coreHits + 1
		self.saved.totalCoreHits = self.saved.totalCoreHits + 1
		self.storage:save( self.saved )
		if self.coreHits < TRASHBOT_STATS[self.saved.fightType].coreHitsToRecover then
			self.unit:sendCharacterEvent( "koDmg" )
		else
			self.unit:sendCharacterEvent( "koFinal" )
		end
	end
end

function TrashbotUnit.sv_e_eyeDamaged( self, params )
	if self.currentState == self.trashbotAttackState and ( self.trashbotAttackState:sv_getRightAttackType() == TrashbotAttack.DESTRUCTION_SWAY ) then
		sm.effect.playEffect( "Trashbot - Core_takedamage", params.hitPos - params.hitVelocity:normalize() * 0.7 , nil, params.direction )
		self.saved.damageTaken = self.saved.damageTaken + 10
		return
	end
	if not self.eyeOpen or self.eyeOpenTickCounter >= self.eyeOpenTicks then
		local effectName = ProjectileRicochetEffects[tostring( params.projectileType )] or "Trashbot - Hitimpactnodamage_ricochet"
		sm.effect.playEffect( effectName, params.hitPos - params.hitVelocity:normalize() * 0.7 , nil, params.direction )
		sm.effect.playEffect( "Trashbot - Hitimpactnodamage_eye", params.hitPos - params.hitVelocity:normalize() * 0.7 , nil, params.direction )
		return
	end
	if isAnyOf( self.currentState, self.aggressiveStates ) and not self.forcedPattern then
		self.eyeHitCounter = self.eyeHitCounter + 1
		if self.eyeHitCounter >= ( self.currentPattern.eyeHitThreshold or DefaultEyeHitThreshold ) then
			self.eyeOpenTickCounter = self.eyeOpenTicks
		end
		self.saved.damageTaken = self.saved.damageTaken + 1
		local currentMaxHp = TRASHBOT_STATS[self.saved.fightType].healthPerPhase * PlayerCountHpMultiplier[math.min( self.maxEncounteredPlayers, #PlayerCountHpMultiplier )]
		if self.saved.damageTaken >= currentMaxHp then
			self.eyeOpenTickCounter = self.eyeOpenTicks
			sm.effect.playEffect( "Trashbot - Hitimpactlast", params.hitPos - params.hitVelocity:normalize() * 0.7 , nil, params.direction )
		else
			local effectName = ProjectileHitEffects[tostring( params.projectileType )] or "Trashbot - Hitimpact"
			sm.effect.playEffect( effectName, params.hitPos - params.hitVelocity:normalize() * 0.7 , nil, params.direction )
		end
		self.unit:sendCharacterEvent( "hurteye" )
		if TRASHBOT_HP_THRESHOLDS[self.saved.fightType][self.saved.attackStage] then
			for hpFraction, pattern in pairs( TRASHBOT_HP_THRESHOLDS[self.saved.fightType][self.saved.attackStage] ) do
				if ( currentMaxHp - self.saved.damageTaken ) / currentMaxHp <= hpFraction and self.currentHealthFraction > hpFraction then
					self.currentHealthFraction = hpFraction
					self.forcedPattern = true
					self:sv_selectNextPattern( pattern )
					self.waitTimeCounter = math.huge
					self.previousWaitTime = 0.0
					self.trashbotAttackState:sv_tryAbortAttacks()
				end
			end
		end
		self.storage:save( self.saved )
	end
end

function TrashbotUnit.sv_m_clearWarehouseAttack( self )
	if self.currentState == self.cinematicEventState then
		self.currentState:stop()
		self.currentState = self.thinkEventState
		self.currentState:start()
	end
end

function TrashbotUnit.server_onProjectile(self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid)
	local effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -hitVelocity )
	sm.effect.playEffect( "Sledgehammer - NoProgress", hitPos, nil, effectRotation )
end

function TrashbotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if type( attacker ) == "Player" then
		local effectRotation = sm.vec3.getRotation( sm.vec3.new(0, 0, 1), -hitDirection )
		sm.effect.playEffect( "Sledgehammer - NoProgress", hitPos, nil, effectRotation )
	end
end

function TrashbotUnit.server_onExplosion( self, center, destructionLevel ) end

function TrashbotUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_e_updateTarget", { target = self.currentTarget } )
	end
end

function TrashbotUnit.sv_toggleLookAtTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_e_toggleLookAtTarget", { lookAtTarget = self.lookingAtTarget } )
	end
end

function TrashbotUnit.sv_setBossMusicControl( self, control )
	control = control == true
	if self.saved.hasBossMusicControl ~= control then
		self.saved.hasBossMusicControl = control
		self.storage:save( self.saved )
	end
	if sm.exists( self.unit ) and self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_e_setBossMusicControl", control, sm.event.types.blind )
	end
end

function TrashbotUnit.sv_m_setBossMusic( self )
	self:sv_setBossMusicControl( true )
end

function TrashbotUnit.sv_onDeath( self )
	if not self.destroyed then
		local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.unit:getCharacter() )
		if self.saved.fightType == 2 then
			self:sv_setBossMusicControl( false )
			sm.effect.playEffect( "Trashbot - Deathexplosion", self.unit.character.worldPosition + DestroyEffectsOffset )
			
			-- remove projectiles from the world when the trashbot is destroyed in the scrapyard quest
			QuestManager.Sv_SendEvent( "event.quest_scrapyard.remove_projectiles", { character = self.unit.character, world = self.unit.character:getWorld() } )
			
			-- find players in range and goop them
			local playerCharacters = GetPlayerCharactersInSphere( self.unit.character.worldPosition, TRASHBOT_EXPLOSION_RADIUS, self.unit.character:getWorld() )
			for _,character in pairs( playerCharacters ) do
				if character then
					sm.event.sendToCharacter( character, "sv_e_addStatusEffect", { status = "goop", strength = 1 } )
				end
			end
			for _,uid in pairs( DestructionItemSpawns ) do
				local partPosition = self.unit.character.worldPosition + sm.vec3.new( math.random() - 0.5, math.random() - 0.5, 1.0 ) * 2.0
				local part = sm.shape.createPart( uid, partPosition, sm.quat.identity() )
				if part then
					local impulse_dir = (partPosition - self.unit.character.worldPosition):normalize()
					sm.physics.applyImpulse( part, impulse_dir * part.mass * part_spawn_force, true )
					sm.event.sendToCharacter( self.unit.character, "sv_e_partEffect", { SpawnedPart = part } )
				end
			end
		end
		self.unit:destroy()
		if self.core and sm.exists( self.core ) then
			self.core:destroy()
			self.core = nil
		end
		print( "'TrashbotUnit' killed!" )
		TileStorageManager.Sv_SetValueInSubTable( tileStorageKey, KEY_LOCK_TABLE, "trashbotDefeated", true )
		if self.saved.deathEvent then
			QuestManager.Sv_SendEvent( self.saved.deathEvent )
		end
		self.destroyed = true
	end
end

function TrashbotUnit.sv_e_receiveTarget( self, params ) end


















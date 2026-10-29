dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseTotebotUnit.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/JumpStompState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/JumpRoamingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/JumpPathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/JumpFleeState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PatrolState.lua"

TotebotYellowUnit = class( BaseTotebotUnit )

local SmashUuid = sm.uuid.new( "eeeaa198-6b28-11ed-a1eb-0242ac120002" )
local HeadSmashMaxAngle = 45.0
local CombatStompRange = 12.0 -- Range where the unit will perform stomp attacks
local StaggerProjectile = 0.5
local StaggerMelee = 1.0
local StaggerCooldownTickTime = 1.65 * 40

local AllyRange = 20.0

local HearRange = 40.0

function TotebotYellowUnit.server_onCreate( self )
	BaseTotebotUnit.server_onCreate( self )

	self.target = nil
	self.previousTarget = nil
	self.lastTargetPosition = nil
	self.ambushPosition = nil
	self.raidTargetNonVisiblePlayer = true
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 80, maxhp = 80 }
	end

	InitRobotParams( self )
	self.storage:save( self.saved )

	self.unit.eyeHeight = self.unit.character:getHeight() * 0.75
	self.unit.visionFrustum = {
		{ 3.0, math.rad( 80.0 ), math.rad( 80.0 ) },
		{ 20.0, math.rad( 40.0 ), math.rad( 35.0 ) },
		{ 40.0, math.rad( 20.0 ), math.rad( 20.0 ) }
	}
	self.unit:setWhiskerData( 3, math.rad( 60.0 ), 1.5, 5.0 )
	self.noiseScale = 1.0
	self.impactCooldownTicks = 0

	self.isInCombat = false
	self.combatTimer = Timer()
	self.combatTimer:start( 40 * 12 )

	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Stagger
	self.staggeredEventState = self.unit:createState( "wait" )
	self.staggeredEventState.time = 0.25
	self.staggeredEventState.interruptible = false
	self.staggeredEventState.debugName = "staggeredEventState"
	self.stagger = 0.0
	self.staggerCooldownTicks = 0

	-- Roam
	self.jumpRoamingState = JumpRoamingState()
	self.jumpRoamingState:sv_onCreate( self.unit, self.homePosition )
	self.jumpRoamingState.debugName = "jumpRoamingState"

	-- Pathing
	self.jumpPathingState = JumpPathingState()
	self.jumpPathingState:sv_onCreate( self.unit )
	self.jumpPathingState:sv_setMovementType( "sprint" )
	self.jumpPathingState.debugName = "jumpPathingState"

	-- Jump & Stomp
	self.jumpStompState = JumpStompState()
	self.jumpStompState:sv_onCreate( self.unit )
	self.jumpStompState.debugName = "jumpStompState"

	-- LookAt
	self.lookAtState = self.unit:createState( "positioning" )
	self.lookAtState.debugName = "lookAt"
	self.lookAtState.timeout = 3.0
	self.lookAtState.tolerance = 0.5
	self.lookAtState.avoidance = false
	self.lookAtState.movementType = "stand"

	-- Flee
	self.raidFlee = JumpFleeState()
	self.raidFlee:sv_onCreate( self.unit )
	self.raidFlee.debugName = "raidFlee"

	-- Patrol
	self.patrolState = PatrolState()
	self.patrolState:sv_onCreate( self.unit, self.saved.patrolKey )
	self.patrolState.debugName = "patrolState"

	-- Tumble
	initTumble( self )

	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )

	self.currentState = self.idleState
	self.currentState:start()
end

function TotebotYellowUnit.server_onRefresh( self )
end

function TotebotYellowUnit.server_onFixedUpdate( self, dt )
	BaseUnit.server_onFixedUpdate( self )

	if updateCrushing( self ) then
		self:sv_onDeath( sm.vec3.new( 0, 0, 0 ) )
	end

	updateTumble( self )
	local inImmuneState = isAnyOf( self.currentState, { self.raidFlee, self.jumpStompState, self.jumpRoamingState, self.jumpPathingState, self.patrolState } )
	if inImmuneState then
		self.airTicks = 0
	else
		updateAirTumble( self, self.idleState )
	end

	if self.currentState then
		if self.target and not sm.exists( self.target ) then
			self.target = nil
		end

		-- React to jumping up and hitting head
		local goingUp = not self.unit.character:isOnGround() and self.unit.character.velocity.z > 0
		local inJumpingState = isAnyOf( self.currentState, { self.jumpStompState, self.jumpRoamingState, self.jumpPathingState } )
		if goingUp and inJumpingState then
			local characterRadius = self.unit.character:getRadius()
			local characterHeight = self.unit.character:getHeight()
			local capsuleHalfHeight = ( characterHeight - characterRadius * 2 ) * 0.5
			local margin = 0.05 -- To avoid detecting walls
			local sphereRadius = characterRadius - margin
			-- Offset used to move the characterRadius spherecast to the upper part of the capsule
			local capsuleOffset = sm.vec3.new( 0, 0, capsuleHalfHeight + margin )
			local from = self.unit.character.worldPosition + capsuleOffset
			local to = from + self.unit.character.velocity * dt
			local filter = sm.physics.filter.static + sm.physics.filter.dynamicBody
			local hit, result = sm.physics.spherecast( from, to, sphereRadius, self.unit.character, filter )

			if hit then
				local headHitDirection = ( result.pointWorld - self.unit.character.worldPosition ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
				local headHitAngle = math.deg( math.acos( headHitDirection:dot( sm.vec3.new( 0, 0, 1 ) ) ) )
				if headHitAngle <= HeadSmashMaxAngle then
					-- Smash roof
					local heightOffset = sm.vec3.new( 0, 0, characterHeight * 0.5 )
					local headPosition = self.unit.character.worldPosition + heightOffset
					local params = { position = headPosition, smasher = self.unit, normal = result.normalWorld }
					sm.scriptableObject.createScriptableObject( SmashUuid, params, self.unit.character:getWorld() )

					local enteringStompState = self.currentState ~= self.jumpStompState
					if enteringStompState then
						self.currentState:stop()
						self.jumpStompState.target = nil
						self.jumpStompState.destination = nil
						self.currentState = self.jumpStompState
					end
					if enteringStompState or self.jumpStompState.currentState ~= self.jumpStompState.stompState then
						self.jumpStompState:sv_startStomp()
					end
				end
			end
		end

		self.currentState:onFixedUpdate( dt )
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )
		self.unit:setWantsJump( self.currentState:getWantsJump() )

		if self.isInCombat then
			self.combatTimer:tick()
		end

		self.staggerCooldownTicks = math.max( self.staggerCooldownTicks - 1, 0 )
		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )

	end

	-- Update target for totebot character
	if self.target ~= self.previousTarget then
		self:sv_updateCharacterTarget()
		self.previousTarget = self.target
	end
	if self.isDirty then
		self.storage:save( self.saved )
		self.isDirty = false
	end
end

function TotebotYellowUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function TotebotYellowUnit.server_onUnitUpdate( self, dt )

	if not sm.exists( self.unit ) then
		return
	end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	if CheckFleeFromRaid( self ) then
		return
	end

	if self.unit.character:isTumbling() then
		return
	end

	RobotSelectTarget( self, AllyRange, dt )

	if self.saved.raidPosition and not self.lastTargetPosition and sm.exists( self.unit.character ) then
		local raidSpots = RaidManager.Sv_GetPlantLocations( self.unit.character:getWorld().id, self.saved.raidKey )
		local closestSpot = nil
		if #raidSpots > 0 and ( self.saved.randomPlotTarget == nil or self.saved.randomPlotTarget > #raidSpots ) then
			self.saved.randomPlotTarget = math.random( #raidSpots )
			self.isDirty = true
			closestSpot = raidSpots[self.saved.randomPlotTarget]
		end
		if closestSpot then
			self.homePosition = closestSpot + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
			if closestSpot then
				self.lastTargetPosition = closestSpot
			end
		end
	end

	-- Check for positions acquired from noise
	local noiseShape = g_unitManager:sv_getClosestNoiseShape( self.unit.character.worldPosition, HearRange )
	if noiseShape and self.eventNoisePosition == nil then
		self.eventNoisePosition = noiseShape.worldPosition
	end
	local heardNoise = false
	if self.eventNoisePosition then
		self.lookAtState.desiredPosition = self.unit.character.worldPosition
		local fromToNoise = self.eventNoisePosition - self.unit.character.worldPosition
		fromToNoise.z = 0
		if fromToNoise:length() >= FLT_EPSILON then
			self.lookAtState.desiredDirection = fromToNoise:normalize()
		else
			self.lookAtState.desiredDirection = -self.unit.character.direction
		end
		heardNoise = true
	end
	self.eventNoisePosition = nil


	-- Update pathing destination
	if self.currentState == self.jumpPathingState then
		if self.lastTargetPosition then
			self.jumpPathingState:sv_setDestination( self.lastTargetPosition )
		end
	end

	local inCombatStompRange = false
	if self.lastTargetPosition then
		local fromToTarget = self.lastTargetPosition - self.unit.character.worldPosition
		local targetRadius = 0.0
		if self.target and type( self.target ) == "Character" then
			targetRadius = self.target:getRadius()
		end

		inCombatStompRange = fromToTarget:length() - targetRadius <= CombatStompRange
	end

	local prevState = self.currentState
	local prevInCombat = self.isInCombat
	if self.lastTargetPosition then
		self.isInCombat = true
		self.combatTimer:reset()
	end
	if self.combatTimer:done() then
		self.isInCombat = false
	end

	local canPatrol
	if self.saved.patrolKey then
		canPatrol = PatrolManager.Sv_IsPatrolActive( self.saved.patrolKey )
	end

	local restartState = false
	local done, result = self.currentState:isDone()
	local abortState = 	( self.currentState ~= self.jumpStompState ) and
						(
							( prevInCombat and self.combatTimer:done() ) or
							( self.currentState == self.lookAtState and self.isInCombat ) or
							( self.currentState == self.roamState and heardNoise ) or
							( self.currentState == self.jumpPathingState and inCombatStompRange )
						)

	if ( done or abortState ) then
		-- Select state
		if self.isInCombat then
			-- Select combat state
			if inCombatStompRange then
				-- Stomp towards target
				if self.currentState == self.jumpStompState and done then
					restartState = true
				end
				self.currentState = self.jumpStompState
				if self.target then
					self.jumpStompState:sv_setTarget( self.target )
				else
					self.jumpStompState:sv_setDestination( self.lastTargetPosition )
					self.lastTargetPosition = nil
				end
			elseif self.lastTargetPosition then
				if self.currentState ~= self.jumpPathingState then
					self.jumpPathingState:sv_setDestination( self.lastTargetPosition )
				else
					self.lastTargetPosition = nil
				end
				self.currentState = self.jumpPathingState
			else
				-- No target information
				self.isInCombat = false
			end
		else
			-- Select non-combat state
			if heardNoise then
				self.currentState = self.lookAtState
			elseif canPatrol then
				self.currentState = self.patrolState
			else
				self.currentState = self.jumpRoamingState
			end
		end
	end

	if prevState ~= self.currentState or restartState then
		local wasRoaming = isAnyOf( prevState, { self.idleState, self.jumpRoamingState, self.patrolState } )
		local isAlert = not isAnyOf( self.currentState, { self.idleState, self.jumpRoamingState, self.patrolState } )
		if wasRoaming and isAlert then
			self.unit:sendCharacterEvent( "alerted" )
		elseif not wasRoaming and not isAlert then
			self.unit:sendCharacterEvent( "roaming" )
		end

		prevState:stop()
		self.currentState:start()
	end

end

function TotebotYellowUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	local teamOpponent = false
	if type( attacker ) == "Unit" then
		if not SurvivalGame then
			teamOpponent = not InSameTeam( attacker, self.unit )
		end
	end

	if type( attacker ) == "Player" or type( attacker ) == "Shape" or teamOpponent then
		if damage > 0 then
			if type( attacker ) == "Player" then
				g_ambienceManager:triggerCombatMusic()
			end
			self:sv_addStagger( StaggerProjectile )
			if self.eventTarget == nil then
				if type( attacker ) == "Player" or type( attacker ) == "Unit" then
					self.eventTarget = attacker:getCharacter()
				elseif type( attacker ) == "Shape" then
					self.eventTarget = attacker
				end
			end
		end
		local impact = hitVelocity:normalize() * 6
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function TotebotYellowUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	local teamOpponent = false
	if type( attacker ) == "Unit" then
		if not SurvivalGame then
			teamOpponent = not InSameTeam( attacker, self.unit )
		end
	end

	if type( attacker ) == "Player" or teamOpponent then
		if type( attacker ) == "Player" then
			g_ambienceManager:triggerCombatMusic()
		end

		local attackingCharacter = attacker:getCharacter()
		self:sv_addStagger( StaggerMelee )
		if self.eventTarget == nil then
			self.eventTarget = attackingCharacter
		end

		local impact = hitDirection * 6
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function TotebotYellowUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 6
	self:sv_takeDamage( self.saved.stats.maxhp, impact, self.unit:getCharacter().worldPosition )
end

function TotebotYellowUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( self.unit ) then
		return
	end

	if type( other ) == "Character" then
		if not sm.exists( other ) then
			return
		end
		local teamOpponent = false
		if not SurvivalGame then
			teamOpponent = not InSameTeam( other, self.unit )
		end
		if other:isPlayer() or teamOpponent then
			if self.eventTarget == nil then
				self.eventTarget = other
			end
		end
	elseif type( other ) == "Shape" then
		if not sm.exists( other ) then
			return
		end
		if self.target == nil and self.eventTarget == nil then
			local creationBodies = other.body:getCreationBodies()
			for _, body in ipairs( creationBodies ) do
				local seatedCharacters = body:getAllSeatedCharacter()
				if #seatedCharacters > 0 then
					self.eventTarget = seatedCharacters[1]
					break
				end
			end
		end
	end
	local hitByRailKinematic = type( other ) == "Harvestable" and sm.exists( other ) and other.publicData and other.publicData.isRailKinematic

	if self.impactCooldownTicks > 0 then
		return
	end

	local inImmuneState = isAnyOf( self.currentState, { self.raidFlee, self.jumpStompState, self.jumpRoamingState, self.jumpPathingState, self.patrolState } )
	if not inImmuneState then
		local collisionDamageMultiplier = 1.0
		local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.unit.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, self.saved.stats.maxhp / collisionDamageMultiplier, nil, self.velocityBuffer, self.velocityBufferIndex )
		damage = damage * collisionDamageMultiplier
		if damage > 0 or tumbleTicks > 0 then
			self.impactCooldownTicks = 6
		end
		if damage > 0 then
			self:sv_takeDamage(damage, collisionNormal, collisionPosition)
			if self.saved.stats.hp <= 0 then
				--Achievement check
			RoadRageAchievementCheck( other )
			end
		end
		if tumbleTicks > 0 then
			if hitByRailKinematic then
				self:sv_takeDamage( self.saved.stats.maxhp, collisionNormal, collisionPosition )
			else
				if startTumble( self, tumbleTicks, self.idleState, tumbleVelocity ) then
					if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
						sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
					end
				end
			end
		end
	end

end

function TotebotYellowUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function TotebotYellowUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_n_updateTarget", { target = self.target } )
	end
end

function TotebotYellowUnit.sv_addStagger( self, stagger )

	-- Update stagger
	if self.staggerCooldownTicks <= 0 then
		self.staggerCooldownTicks = StaggerCooldownTickTime
		self.stagger = self.stagger + stagger
		local triggerStaggered = ( self.stagger >= 1.0 )
		self.stagger = math.fmod( self.stagger, 1.0 )

		if triggerStaggered then
			local prevState = self.currentState
			self.currentState = self.staggeredEventState
			prevState:stop()
			self.currentState:start()
		end
	end
end

function TotebotYellowUnit.sv_onDeath( self, impact )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		self.unit:sendCharacterEvent( "death" )
		g_unitManager:sv_addDeathMarker( character.worldPosition )
		self.saved.stats.hp = 0
		self.unit:destroy()
		self:sv_spawnParts( impact )
		if SurvivalGame then
			local loot = SelectLoot( "lootsource_totebot_yellow", nil, self.saved.lootType )
			SpawnLoot( self.unit, loot )
		end
		self.destroyed = true
		BaseUnit.sv_onDeath( self );
	end
end

function TotebotYellowUnit.sv_spawnParts( self, impact )
	local character = self.unit:getCharacter()

	local lookDirection = character:getDirection()
	local bodyPos = character.worldPosition
	local bodyRot = sm.quat.identity()
	lookDirection = sm.vec3.new( lookDirection.x, lookDirection.y, 0 )
	if lookDirection:length() >= FLT_EPSILON then
		lookDirection = lookDirection:normalize()
		bodyRot = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), lookDirection  ) --Turn parts sideways
	end
	local bodyOffset = bodyRot * sm.vec3.new( -0.25, 0.25, 0.375 )
	bodyPos = bodyPos - bodyOffset

	local color = self.unit.character:getColor()
	if SurvivalGame then
		if math.random( 1, 15 ) == 1 then
			local headBody = sm.body.createBody( bodyPos, bodyRot, true )
			local headShape = headBody:createPart( ITEMS.obj_interactive_robotdrumhead, sm.vec3.new( 0, 1, 2 ), sm.vec3.new( 0, 1, 0 ), sm.vec3.new( -1, 0, 0 ), true )
			headShape.color = color
			sm.physics.applyImpulse( headShape, impact * headShape.mass, true )
		end
	end
end

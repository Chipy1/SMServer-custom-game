dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseTotebotUnit.lua" 

LootbotUnit = class( BaseTotebotUnit )

local RoamStartTimeMin = 40 * 1
local RoamStartTimeMax = 40 * 2
local FleeTimeMin = 40 * 2
local FleeTimeMax = 40 * 3
local MinFleeDeviationDegree = 50.0
local MaxFleeDeviationDegree = 80.0

local PlayerFleeDistance = 2.5
local RaidFleeTickTime = 40 * 10
local DamageCooldownTickTime = 40.0

function LootbotUnit.server_onCreate( self )

	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 14, maxhp = 14 }
	end

	InitRobotParams( self )
	if self.params then
		if self.params.lootTableName then
			self.saved.lootTableName = self.params.lootTableName
		end
	end
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
	self.damageCooldownTicks = 0

	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Roam
	self.roamTimer = Timer()
	self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
	self.roamState = self.unit:createState( "roam" )
	self.roamState.debugName = "roamState"
	self.roamState.tetherPosition = self.unit.character.worldPosition
	self.roamState.waterAvoidance = false
	self.roamState.roamCenterOffset = 0.0
	self.roamState.minMoveDistance = 6.0
	self.roamState.maxRadius = 32.0
	self.roamState.maxTetherDistance = 32.0
	self.roamState.customData = { onUnitUpdateOnly = true }

	-- Flee (avoid)
	self.fleeState = self.unit:createState( "flee" )
	self.fleeState.movementAngleThreshold = math.rad( 180 )
	self.fleeState.maxDeviation = 45 * math.pi / 180
	self.fleeState.headingDeviation = 0.0
	self.fleeState.debugName = "fleeState"

	-- Flee (raid end)
	self.raidFlee = self.unit:createState( "flee" )
	self.raidFlee.movementAngleThreshold = math.rad( 180 )
	self.raidFlee.maxFleeTime = 0.0
	self.raidFlee.maxDeviation = 45 * math.pi / 180
	self.raidFlee.debugName = "raidFlee"

	-- Tumble
	initTumble( self )

	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )

	self.currentState = self.idleState
	self.currentState:start()
end

function LootbotUnit.server_onRefresh( self )
end

function LootbotUnit.server_onFixedUpdate( self, dt )
	-- Remove the unit when the death timestamp is reached
	if sm.exists( self.unit ) and not self.destroyed then
		if self.saved.deathTickTimestamp and sm.game.getCurrentTick() >= self.saved.deathTickTimestamp then
			BaseUnit.sv_onDeath( self )
			sm.physics.explode( self.unit.character.worldPosition, 7, 2.0, 6.0, 25, "PropaneTank - ExplosionSmall", nil, nil, nil, 35 )
			self.unit:destroy()
			self.destroyed = true
			return
		end
	end

	if self.unit.character:isSwimming() then
		self.roamState.cliffAvoidance = false
	else
		self.roamState.cliffAvoidance = true
	end

	if updateCrushing( self ) then
		self:sv_takeDamage( 1, sm.vec3.zero(), self.unit.character.worldPosition )
		self.fleeFrom = self.unit.character.worldPosition
	end

	updateTumble( self )
	updateAirTumble( self, self.idleState )

	if self.currentState then
		if not self.currentState.customData or not self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )

		-- Random roaming during idle
		if self.currentState == self.idleState then
			self.roamTimer:tick()
		end

		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )
		self.damageCooldownTicks = math.max( self.damageCooldownTicks - 1, 0 )
	end
end

function LootbotUnit.server_onUnitUpdate( self, dt )
	if not sm.exists( self.unit ) then
		return
	end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
		if self.currentState.customData and self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
	end

	if CheckFleeFromRaid( self ) then
		return
	end

	if self.unit.character:isTumbling() then
		return
	end

	-- Flee when player gets close
	local closestDistance2 = math.huge
	local closestPlayer
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if sm.exists( player.character ) then
			local distance2 = ( self.unit.character.worldPosition - player.character.worldPosition ):length2()
			if distance2 < closestDistance2 then
				closestDistance2 = distance2
				closestPlayer = player
			end
		end
	end
	if closestDistance2 <= PlayerFleeDistance * PlayerFleeDistance then
		if self.fleeFrom == nil and self.currentState ~= self.fleeState then
			self.fleeFrom = closestPlayer
			self.fleeState.headingDeviation = 0.0
		end
	end
	

	local prevState = self.currentState
	local done, result = self.currentState:isDone()
	local abortState = 	(
							( self.fleeFrom )
						)

	if done or abortState then
		-- Select state
		if self.fleeFrom then
			self.fleeState.fleeFrom = self.fleeFrom
			self.fleeFrom = nil
			self.fleeState.maxFleeTime = math.random( FleeTimeMin, FleeTimeMax ) / 40
			self.currentState = self.fleeState
		elseif self.currentState == self.fleeState then
			self.currentState = self.idleState
		elseif self.roamTimer:done() and not ( self.currentState == self.idleState and result == "started" ) then
			self.roamTimer:start( math.random( RoamStartTimeMin, RoamStartTimeMax ) )
			self.currentState = self.roamState
		elseif not ( self.currentState == self.roamState and result == "roaming" ) then
			self.currentState = self.idleState
		end
	end

	if prevState ~= self.currentState or abortState then
		prevState:stop()
		self.currentState:start()
	end
end

function LootbotUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end

	if type( attacker ) == "Player" or type( attacker ) == "Shape" then
		if damage > 0 then
			if type( attacker ) == "Player" then
				g_ambienceManager:triggerCombatMusic()
			end
			if self.fleeFrom == nil then
				self.fleeFrom = attacker
			end
		end
		local impact = hitVelocity:normalize() * 6
		self:sv_takeDamage( 1, impact, hitPos )
	end
end

function LootbotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end

	if type( attacker ) == "Player" then
		if damage > 0 then
			g_ambienceManager:triggerCombatMusic()
			if self.fleeFrom == nil then
				self.fleeFrom = attacker
			end
		end
		local impact = hitDirection * 6
		self:sv_takeDamage( 1, impact, hitPos )
	end
end

function LootbotUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 6
	self:sv_takeDamage( 1, impact, self.unit:getCharacter().worldPosition )
	if self.fleeFrom == nil then
		self.fleeFrom = center
	end
end

function LootbotUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( self.unit ) then
		return
	end

	if type( other ) == "Shape" then
		if not sm.exists( other ) then
			return
		end
		if self.fleeFrom == nil then
			local creationBodies = other.body:getCreationBodies()
			for _, body in ipairs( creationBodies ) do
				local seatedCharacters = body:getAllSeatedCharacter()
				if #seatedCharacters > 0 then
					self.fleeFrom = seatedCharacters[1]
					break
				end
			end
		end
	end

	if self.impactCooldownTicks > 0 then
		return
	end

	local collisionDamageMultiplier = 1.0
	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.unit.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, self.saved.stats.maxhp / collisionDamageMultiplier, nil, self.velocityBuffer, self.velocityBufferIndex )
	damage = damage * collisionDamageMultiplier
	if damage > 0 or tumbleTicks > 0 then
		self.impactCooldownTicks = 6
	end
	if damage > 0 then
		self:sv_takeDamage( 1, collisionNormal, collisionPosition )
		self.fleeFrom = collisionPosition

		if self.saved.stats.hp <= 0 then
			--Achievement check
			RoadRageAchievementCheck( other )
		end
	end
	if tumbleTicks > 0 then
		if startTumble( self, tumbleTicks, self.idleState, tumbleVelocity ) then
			if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
				sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
			end
		end
	end
end

function LootbotUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function LootbotUnit.sv_takeDamage( self, damage, impact, hitPos )
	if self.saved.stats.hp > 0 and damage > 0 then
		if self.damageCooldownTicks > 0 then
			return
		end
		if hitPos and impact then
			local up = sm.vec3.new( 0, 0, 1 )
			local effectRotation = sm.vec3.getRotation( up, -impact:safeNormalize( up ) )
			if self.saved.stats.hp - damage > 0 then
				sm.effect.playEffect( "Lootbot - Hit", hitPos, nil, effectRotation )
			end
		end
		self.damageCooldownTicks = DamageCooldownTickTime

		local deviationDegree = math.random() * ( MaxFleeDeviationDegree - MinFleeDeviationDegree ) + MinFleeDeviationDegree
		local deviationSign = math.random( 0, 1 ) > 0 and 1 or -1
		self.fleeState.headingDeviation = math.rad( deviationDegree ) * deviationSign

		if SurvivalGame then
			local loot = SelectLoot( "lootsource_lootbot_hit" )
			SpawnLoot( self.unit, loot )
		end

		BaseTotebotUnit.sv_onDamaged()
	end
end

function LootbotUnit.sv_onDeath( self, impact )
	if not self.destroyed then
		self.unit:sendCharacterEvent( "death" )
		self.saved.stats.hp = 0
		self.unit:destroy()
		if SurvivalGame then
			local lootTableName = self.saved.lootTableName or "lootsource_lootbot_raid_default"
			local loot = SelectLoot( lootTableName )
			SpawnLoot( self.unit, loot )
		end
		self.destroyed = true
		BaseUnit.sv_onDeath( self )
	end
end

function LootbotUnit.sv_e_receiveTarget( self, params ) end

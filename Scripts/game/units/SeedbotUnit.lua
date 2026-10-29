dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseUnit.lua"

SeedbotUnit = class( BaseUnit )

local RoamStartTimeMin = 40 * 1
local RoamStartTimeMax = 40 * 2
local FleeTimeMin = 40 * 2
local FleeTimeMax = 40 * 3
local MinFleeDeviationDegree = 15.0
local MaxFleeDeviationDegree = 45.0

local PlayerFleeDistance = 2.5

function SeedbotUnit.server_onCreate( self )
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 100, maxhp = 100 }
	end

	InitRobotParams( self )
	if self.params and self.params.seedType then
		self.saved.seedType = self.params.seedType
	end
	self.saved.seedType = self.saved.seedType or "tomato"

	sm.event.sendToCharacter( self.unit.character, "sv_e_setSeedType", self.saved.seedType, sm.event.types.blind )
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

	-- Tumble
	initTumble( self )

	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )

	self.currentState = self.idleState
	self.currentState:start()
end

function SeedbotUnit.server_onRefresh( self )
end

function SeedbotUnit.server_onFixedUpdate( self, dt )
	-- Remove the unit when the death timestamp is reached
	if sm.exists( self.unit ) and not self.destroyed and not self.saved.markedForRemoval then
		if self.saved.deathTickTimestamp and sm.game.getCurrentTick() >= self.saved.deathTickTimestamp then
			RobotOnDestroy( self )
			self.saved.markedForRemoval = true
			return
		end
	end

	if self.unit.character:isSwimming() then
		self.roamState.cliffAvoidance = false
	else
		self.roamState.cliffAvoidance = true
	end

	if updateCrushing( self ) then
		self:sv_takeDamage( self.saved.stats.maxhp, sm.vec3.zero(), self.unit.character.worldPosition )
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
	end
end

function SeedbotUnit.server_onUnitUpdate( self, dt )
	if not sm.exists( self.unit ) then
		return
	end

	if self.currentState then
		self.currentState:onUnitUpdate( dt )
		if self.currentState.customData and self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
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

function SeedbotUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
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
			local impact = hitVelocity:normalize() * 6
			self:sv_takeDamage( damage, impact, hitPos )
		end
	end
end

function SeedbotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
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
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function SeedbotUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):normalize() * 6
	self:sv_takeDamage( self.saved.stats.maxhp, impact, self.unit:getCharacter().worldPosition )
	if self.fleeFrom == nil then
		self.fleeFrom = center
	end
end

function SeedbotUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
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
				for _, seatedCharacter in ipairs( seatedCharacters ) do
					local player = seatedCharacter:getPlayer()
					if player then
						self.fleeFrom = player
						break
					end
				end
			end
		end
	end

	if self.impactCooldownTicks > 0 then
		return
	end

	local collisionDamageMultiplier = 1
	local velDiffThreshold = TUMBLE_VELOCITY_THRESHOLD
	if type( other ) == "Shape" then
		collisionDamageMultiplier = 4
		velDiffThreshold = 8
	end

	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.unit.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, self.saved.stats.maxhp / collisionDamageMultiplier, velDiffThreshold, self.velocityBuffer, self.velocityBufferIndex )
	damage = damage * collisionDamageMultiplier
	if damage > 0 or tumbleTicks > 0 then
		self.impactCooldownTicks = 6
	end
	if damage > 0 then
		self:sv_takeDamage( damage, collisionNormal, collisionPosition )
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

function SeedbotUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function SeedbotUnit.sv_e_receiveDamage( self, damageData )
	if self.fleeFrom == nil then
		self.fleeFrom = damageData.hitPos
	end
	self:sv_takeDamage( damageData.damage )
end

function SeedbotUnit.sv_takeDamage( self, damage, impact, hitPos, source )
	if self.saved.stats.hp > 0 then
		if hitPos and impact then
			local up = sm.vec3.new( 0, 0, 1 )
			local effectRotation = sm.vec3.getRotation( up, -impact:safeNormalize( up ) )
			if self.saved.stats.hp - damage > 0 then
				local currentTick = sm.game.getCurrentTick()
				if source ~= "plasma" or not self.lastPlasmaDrillEffectTick or currentTick - self.lastPlasmaDrillEffectTick >= PLASMA_BOT_HIT_EFFECT_TICK_THRESHOLD then
					self.lastPlasmaDrillEffectTick = currentTick
					sm.effect.playEffect( "ToteBot - Hit", hitPos, nil, effectRotation )
				end
			end
		end

		local thresholdsPassed = math.floor( self.saved.stats.hp / ( self.saved.stats.maxhp / 5 ) ) - math.floor( ( self.saved.stats.hp - damage ) / ( self.saved.stats.maxhp / 5 ) )
		self.saved.stats.hp = self.saved.stats.hp - damage
		self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )

		local deviationDegree = math.random() * ( MaxFleeDeviationDegree - MinFleeDeviationDegree ) + MinFleeDeviationDegree
		local deviationSign = math.random( 0, 1 ) > 0 and 1 or -1
		self.fleeState.headingDeviation = math.rad( deviationDegree ) * deviationSign

		if SurvivalGame and thresholdsPassed > 0 then
			local loot = {}
			for i = 1, math.min( thresholdsPassed, 5 ) do
				local lootSource = "lootsource_seedbot_hit_tomato"
				if self.saved.seedType then
					lootSource = "lootsource_seedbot_hit_"..self.saved.seedType
				end
				concat( loot, SelectLoot( lootSource ) )
			end
			if #loot > 0 then
				local worldPosition = self.unit.character.worldPosition + sm.vec3.new( 0, 0, 1.0 )
				SpawnLoot( self.unit, loot, worldPosition, math.pi / 180 * 25, 4.5 )
			end
		end

		if self.saved.stats.hp <= 0 then
			self:sv_onDeath( impact )
		else
			self.storage:save( self.saved )
		end
	end
end

function SeedbotUnit.sv_onDeath( self, impact )
	if not self.destroyed then
		self.unit:sendCharacterEvent( "death" )
		self.saved.stats.hp = 0
		self.unit:destroy()
		if SurvivalGame then
			local lootSource = "lootsource_seedbot_destroyed_tomato"
			if self.saved.seedType then
				lootSource = "lootsource_seedbot_destroyed_"..self.saved.seedType
			end
			local loot = SelectLoot( lootSource )
			local worldPosition = self.unit.character.worldPosition + sm.vec3.new( 0, 0, 1.0 )
			SpawnLoot( self.unit, loot, worldPosition, math.pi / 180 * 25, 6 )
		end
		self.destroyed = true
		BaseUnit.sv_onDeath( self )
	end
end

function SeedbotUnit.sv_e_receiveTarget( self, params ) end

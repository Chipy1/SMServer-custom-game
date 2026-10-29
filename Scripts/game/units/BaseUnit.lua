dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua"
dofile "$SURVIVAL_DATA/Scripts/achievement_common.lua"

BaseUnit = class( nil )

local VelocityBufferCount = 8

function BaseUnit.server_onDestroy( self )
	if SurvivalGame then
		if self.saved.patrolKey then
			PatrolManager.Sv_RemoveUnit( self.saved.patrolKey, self.unit )
		end
	end
	-- markedForRemoval lives in saved data: server_onDestroy currently only runs on an unload (not on game
	-- shutdown), so the mark must survive a restart and only be consumed here when the unit is truly unloaded.
	if self.saved.markedForRemoval then
		sm.unit.forceDestroy( self.unit )
		if SurvivalGame then
			if self.actorName then
				QuestActorManager.Sv_UnregisterActor( self.actorName )
			end
		end
	end
end

function BaseUnit.server_onFixedUpdate( self )
	if sm.exists( self.unit ) and not self.destroyed then
		if self.saved.deathTickTimestamp and sm.game.getCurrentTick() >= self.saved.deathTickTimestamp then
			RobotOnDestroy( self )
			if self.saved.raider then
				self.unit:destroy()
			else
				self.saved.markedForRemoval = true
				self.isDirty = true
			end
			return
		end

		local character = self.unit.character
		if sm.exists( character ) then
			if self.velocityBufferIndex == nil then
				self.velocityBuffer = {}
				self.velocityBufferIndex = 1
			end
			self.velocityBufferIndex = self.velocityBufferIndex + 1
			if self.velocityBufferIndex > VelocityBufferCount then
				self.velocityBufferIndex = 1
			end
			self.velocityBuffer[self.velocityBufferIndex] = character:getVelocity()
		end
	end
	if self.saved.marked and not self.markerPlaced then
		if sm.exists( self.unit.character ) then
			self.markerPlaced = true
			sm.event.sendToCharacter( self.unit.character, "sv_e_markEnemy", { raider = self.saved.raider, raidKey = self.saved.raidKey } )
		end
	end
end

function BaseUnit.sv_e_receiveDamage( self, damageData )
	if damageData.hitPos and self.eventNoisePosition == nil then
		-- Sense damage
		self.eventNoisePosition = damageData.hitPos
	end
	self:sv_takeDamage( damageData.damage, damageData.impact, damageData.hitPos, damageData.source )
end

function BaseUnit.sv_takeDamage( self, damage, impact, hitPos, source )
    print("Unimplemented Unit 'sv_takeDamage'" )
end

function BaseUnit.sv_onDeath( self )
	if SurvivalGame then
		if self.saved.deathEvent then
			QuestManager.Sv_SendEvent( self.saved.deathEvent )
		end
		if self.saved.combatRoomName then
			CombatRoomManager.Sv_EnemyDefeated( self.saved.combatRoomName, self.unit.id )
		end
		if not self.saved.raider and isAnyOf( self.unit.character:getCharacterType(), g_robots ) then
			if ProgressionManager then
				ProgressionManager.Sv_TrySpawnGrowlabKey( self.unit )
			end
		end
	end

	if isAnyOf(self.unit.character:getCharacterType(), g_robots) then
		local playersInRange = {}
		local deathPos = self.unit.character:getWorldPosition()
		local unitWorld = self.unit.character:getWorld()

		local sqrdAchievementRange = 192 * 192 -- 3*64 == 192 (aprox 3 tiles)

		for _, player in ipairs(sm.player.getAllPlayers()) do
			local playerWorld = player:getCharacter():getWorld()
			if unitWorld == playerWorld then
				local distSqrd = (player:getCharacter():getWorldPosition() - deathPos):length2()
				if distSqrd < sqrdAchievementRange then
					table.insert(playersInRange, player.id)
				end
			end
		end
		if( isAnyOf( self.unit.character:getCharacterType(), g_totebots ) ) then
			sm.achievement.addi( "5e348e50-813d-4c52-9a3f-b5605d0fdb9f", 1, playersInRange ) -- Totebots
		else
			sm.achievement.addi( tostring( self.unit.character:getCharacterType() ), 1, playersInRange )
		end
	end
	RobotOnDestroy(self)
end

function BaseUnit.sv_e_receiveTarget( self, params )
	if self.saved.targetPlayerOnly and not params.targetCharacter:isPlayer() then return end
	
    if self.unit ~= params.sendingUnit and not self.saved.raider then
		if self.eventTarget == nil then
			local sameTeam = false
			if not SurvivalGame then
				sameTeam = InSameTeam( params.targetCharacter, self.unit )
			end
			if not sameTeam then
				self.eventTarget = params.targetCharacter
			end
		end
	end
end

function BaseUnit.sv_e_tumble( self, params )
	if self.canTumble and self.idleState then
		startTumble( self, params.tumbleTickTime, self.idleState, params.tumbleVelocity )
	end
end

function BaseUnit.sv_e_markForRemoval( self )
	self.saved.markedForRemoval = true
	self.isDirty = true
end

function BaseUnit.sv_e_raidOver( self )
	if self.saved and self.saved.raider then
		self.saved.deathTickTimestamp = sm.game.getCurrentTick() + 30.0 * 40.0
		self.saved.markedForRemoval = true
		self.isDirty = true
	end
end

function BaseUnit.sv_m_projectileHit( self, params )
	if sm.exists( self.unit ) and sm.exists( params.attacker ) and self.isInCombat == false and InSameWorld( params.world, self.unit ) then
		local distanceToProjectile = ( self.unit.character.worldPosition - params.position ):length()
		if distanceToProjectile <= 4.0 then
			local isEnemyUnit = type( params.attacker ) == "Unit" and not InSameTeam( self.unit, params.attacker )
			if type( params.attacker ) == "Player" or isEnemyUnit then
				if self.eventTarget == nil then
					self.eventTarget = params.attacker:getCharacter()
				end
			elseif type( params.attacker ) == "Shape" then
				if self.eventNoisePosition == nil then
					self.eventNoisePosition = params.attacker.worldPosition
				end
			end
		end
	end
end

function BaseUnit.sv_m_projectileFire( self, params )
	if sm.exists( self.unit ) and self.isInCombat == false and InSameWorld( params.world, self.unit ) then
		local distanceToShooter = ( self.unit.character.worldPosition - params.position ):length()
		if distanceToShooter <= 10.0 then
			local isEnemyUnit = type( params.attacker ) == "Unit" and not InSameTeam( self.unit, params.attacker )
			if type( params.attacker ) == "Player" or isEnemyUnit then
				if self.eventTarget == nil then
					if sm.exists( params.attacker ) then
						self.eventTarget = params.attacker:getCharacter()
					else
						self.eventNoisePosition = params.position
					end
				end
			elseif type( params.attacker ) == "Shape" then
				if self.eventNoisePosition == nil then
					self.eventNoisePosition = params.position
				end
			end
		end
	end
end

function BaseUnit.sv_m_collision( self, params )
	if sm.exists( self.unit ) and self.isInCombat == false and InSameWorld( params.world, self.unit ) then
		local soundReach = math.min( math.max( math.log( 1 + params.impactEnergy ) * 10.0, 0.0 ), 40.0 )
		local betweenVec = self.unit.character.worldPosition - params.position
		betweenVec.z = betweenVec.z * HEIGHT_DISTANCE_MULTIPLIER
		local distanceToSound = betweenVec:length()
		if distanceToSound <= soundReach then
			if self.eventNoisePosition == nil then
				self.eventNoisePosition = params.position
			end
		end
	end
end

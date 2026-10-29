dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

QuartzHarvest = class()

local HammerDamagePerHit = 20
local MaxHealth = 100
local CollisionImpactThreshold = 3
local CollisionDamageMultiplier = 9

function QuartzHarvest.server_onCreate( self )
	self.sv = {}
	self.sv.health = MaxHealth
	self.sv.dmgCd = sm.game.getCurrentTick()
	self.interactable.publicData = { drillLevel = 1 }
end

function QuartzHarvest.sv_onHit( self, damage, spawnPosOverride, directionOverride )
	if not self.sv.destroyed and sm.exists( self.shape ) then
		self.sv.health = self.sv.health - damage
		if self.sv.health <= 0 then
			self.sv.destroyed = true
			local lootList = SelectLoot( self.data.lootSource )
			if spawnPosOverride == nil then
				spawnPosOverride = self.shape.worldPosition
			end
			SpawnLoot( self.shape.body:getWorld(), lootList, spawnPosOverride, nil, nil, directionOverride )
			if spawnPosOverride then
				sm.debugDraw.flashSphere( spawnPosOverride, 0.5, nil, 10 )
			end
			sm.effect.playEffect( self.data.destroyEffect, spawnPosOverride or self.shape.worldPosition, directionOverride or self.shape.velocity, self.shape.worldRotation, nil, { size = 10000 / AUDIO_MASS_DIVIDE_RATIO } )
			self.shape:destroyShape()
		end
	end
end

function QuartzHarvest.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_onHit( HammerDamagePerHit )
	self.sv.dmgCd = sm.game.getCurrentTick()
	self.sv.dmgVelPenalty = nil
end

function QuartzHarvest.server_onExplosion( self, center, destructionLevel )
	self:sv_onHit( self.sv.health )
end

function QuartzHarvest.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if type( other ) == "Character" then
		return
	end
	local velocity = ( selfPointVelocity - otherPointVelocity ):dot( -collisionNormal )
	if velocity > CollisionImpactThreshold then
		if not self.sv.dmgCd or ( sm.game.getCurrentTick() - self.sv.dmgCd > 10 ) then
			self:sv_onHit( velocity * CollisionDamageMultiplier, collisionPosition + collisionNormal * 0.5, collisionNormal )
			self.sv.dmgCd = sm.game.getCurrentTick()
			self.sv.dmgVelPenalty = velocity * 0.5
		elseif self.sv.dmgVelPenalty and velocity > self.sv.dmgVelPenalty then
			self:sv_onHit( ( velocity - self.sv.dmgVelPenalty ) * CollisionDamageMultiplier, collisionPosition + collisionNormal * 0.5, collisionNormal )
			self.sv.dmgCd = sm.game.getCurrentTick()
			self.sv.dmgVelPenalty = velocity * 0.5
		end
	end
end

function QuartzHarvest.sv_e_plasmaDrill( self, params )
	self:sv_onHit( 5 )
end

dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

BlowupHarvest = class()

local HammerDamagePerHit = 35
local MaxHealth = 100

function BlowupHarvest.server_onCreate( self )
	self.sv = {}
	self.sv.health = MaxHealth
	self.interactable.publicData = { drillLevel = 1 }

	if self.params and self.params.inheritedDamage then
		self:sv_onHit( self.params.inheritedDamage )
	end
end

function BlowupHarvest.sv_onHit( self, damage )
	if not self.sv.destroyed and sm.exists( self.shape ) then
		self.sv.health = self.sv.health - damage
		if self.sv.health <= 0 then
			self.sv.destroyed = true
			local lootList = SelectLoot( self.data.blowupHarvest.lootSource )
			local spawnPos = self.shape.worldPosition
			local velocity = self.shape.velocity
			SpawnLoot( self.shape.body:getWorld(), lootList, spawnPos, nil, nil, velocity )
			sm.effect.playEffect( self.data.blowupHarvest.destroyEffect, spawnPos, velocity, self.shape.worldRotation, nil, { size = 10000 / AUDIO_MASS_DIVIDE_RATIO } )
			self.shape:destroyShape()




		end
	end
end

function BlowupHarvest.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_onHit( HammerDamagePerHit )
end

function BlowupHarvest.server_onExplosion( self, center, destructionLevel )
	self:sv_onHit( self.sv.health )
end

function BlowupHarvest.sv_e_plasmaDrill( self, params )
	self:sv_onHit( 5 )
end









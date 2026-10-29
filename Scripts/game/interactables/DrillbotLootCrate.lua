dofile("$SURVIVAL_DATA/Scripts/game/survival_loot.lua")

DrillbotLootCrate = class()

function DrillbotLootCrate.sv_onHit( self, velocity )
	if not self.destroyed and sm.exists( self.shape ) then
		
		if self.data.destroyEffect then
			sm.effect.playEffect( self.data.destroyEffect, self.shape.worldPosition, nil, self.shape.worldRotation, nil, { startVelocity = velocity, Color = self.shape:getColor() } )
		end

		if self.data and self.data.lootSource then
			local lootList = SelectLoot( self.data.lootSource )
			SpawnLoot( self.shape, lootList )
		end

		self.destroyed = true
		self.shape:destroyShape()
	end
end

function DrillbotLootCrate.sv_e_destroy( self, velocity )
	self.sv_onHit( self, velocity )
end

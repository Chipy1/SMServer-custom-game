dofile("$SURVIVAL_DATA/Scripts/game/survival_loot.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua" )

LootCrate = class()

function LootCrate.server_onCreate( self )
	self.saved = self.storage:load()
	self.sv = {}
	if self.saved == nil and self.params then
		self.saved = {}
		self.saved.lootTable = self.params.lootTable
		self.storage:save( self.saved )
	end

	local min, max = self.harvestable:getLocalAabb()
	local bounds = sm.vec3.new( math.abs( max.x - min.x ), math.abs( max.y - min.y ), math.abs( max.z - min.z ) )
	local centerPos = min + bounds * 0.5

	self.sv.areaTrigger = sm.areaTrigger.createBox( bounds * 0.5, self.harvestable:transformLocalPoint( centerPos ), self.harvestable:getRotation(), sm.areaTrigger.filter.dynamicBody )
	self.sv.areaTrigger:bindOnEnter( "trigger_onEnter" )

	self.harvestable.publicData = { drillLevel = 1 }
end

function LootCrate.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage > 0 then
		self:sv_onHit()
	end
end

function LootCrate.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_onHit( hitDirection * 5 )
end

function LootCrate.server_onExplosion( self, center, destructionLevel )
	self:sv_onHit()
end

function LootCrate.sv_e_plasmaDrill( self, params )
	self:sv_onHit()
end

function LootCrate.sv_onHit( self, velocity )
	if not self.destroyed and sm.exists( self.harvestable ) then
		if self.data.destroyEffect then
			sm.effect.playEffect( self.data.destroyEffect, self.harvestable.worldPosition, nil, self.harvestable.worldRotation, nil, { startVelocity = velocity } )
		end
		if self.data.staticDestroyEffect then
			sm.effect.playEffect( self.data.staticDestroyEffect, self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
		end
		local lootTable = self.saved and self.saved.lootTable or "lootsource_lootcrate_common"
		local lootType = nil
		if not lootType then
			local pubData = sm.world.getCurrentWorld().publicData
			local worldType = pubData and pubData.type
			if worldType == "DungeonWorld" then
				lootType = "growlab"
			elseif worldType == "WarehouseWorld" then
				lootType = "warehouse"
			elseif worldType == "UndergroundWorld" then
				lootType = "underground"
			end
		end
		local ignoreType = not RecipeManager.Cl_CanUnlockRandom() and "schematic" or nil
		local lootList = SelectLoot( lootTable, nil, lootType, ignoreType )
		SpawnLoot( self.harvestable, lootList )
		ProgressionManager.Sv_TrySpawnGrowlabKey( self.harvestable )

		self.destroyed = true
		sm.areaTrigger.destroy( self.sv.areaTrigger )
		self.harvestable:destroy()
	end
end

function LootCrate.client_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	self:cl_onHit( attacker )
end

function LootCrate.client_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:cl_onHit( attacker )
end

function LootCrate.cl_onHit( self, attacker )
	if sm.localPlayer.getPlayer() == attacker then
		TutorialManager.Cl_TutorialEvent( TutorialEvent.SmashACrate )
	end
end

function LootCrate.trigger_onEnter( self, trigger, results )
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Body" then
				if result:getVelocity():length() >= 4.0 then
					self:sv_onHit( result:getVelocity() )
				end
			end
		end
	end
end

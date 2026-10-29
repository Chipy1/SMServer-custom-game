-- MatureHarvestable.lua --
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

MatureHarvestable = class( nil )

function MatureHarvestable.server_onCreate( self )
	self.harvestable.publicData = {}
end

function MatureHarvestable.client_onInteract( self, state )
	self.network:sendToServer( "sv_n_harvest" )
end

function MatureHarvestable.client_canInteract( self )
	sm.gui.setInteractionText( "", GetInteractionKeybinding(), "#{INTERACTION_HARVEST}" )
	return true
end

function MatureHarvestable.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested then
		sm.effect.playEffect( "Plants - Picked", self.harvestable:getPosition() )
		if type( attacker ) == "Player" then
			local harvest = {
				lootUid = sm.uuid.new( self.data.harvest ),
				lootQuantity = self.data.amount
			}
			local seedUuid = sm.uuid.new( self.data.seed )
			local seed = { lootUid = seedUuid, lootQuantity = PlantSeedDropAmount( seedUuid ) }
			local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
			sm.projectile.harvestableCustomProjectileAttack( harvest, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
			if seed.lootQuantity > 0 then
				sm.projectile.harvestableCustomProjectileAttack( seed, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
			end
		end
		sm.harvestable.createHarvestable( hvs_soil, self.harvestable:getPosition(), self.harvestable:getRotation() )
		RaidManager.Sv_CropDestroyed( self.harvestable )
		
		self.harvestable:destroy()
		self.harvestable.publicData.harvested = true
	end
end

function MatureHarvestable.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if type( attacker ) == "Unit" then
		if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested then
			sm.effect.playEffect( "Plants - Picked", self.harvestable:getPosition() )
			sm.harvestable.createHarvestable( hvs_soil, self.harvestable:getPosition(), self.harvestable:getRotation() )
			RaidManager.Sv_CropDestroyed( self.harvestable )
			self.harvestable:destroy()
			self.harvestable.publicData.harvested = true
		end
	end
end

function MatureHarvestable.server_canErase( self ) return true end
function MatureHarvestable.client_canErase( self ) return true end

function MatureHarvestable.server_onRemoved( self, player )
	self:sv_n_harvest( nil, player )
end

function MatureHarvestable.cl_n_onInventoryFull( self )
	NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 4 )
end

function MatureHarvestable.sv_n_harvest( self, params, player )
	if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested then
		local container = player:getInventory()
		if sm.container.beginTransaction() then
			sm.container.collect( container, sm.uuid.new( self.data.harvest ), self.data.amount, true )
			local seedUuid = sm.uuid.new( self.data.seed )
			local seedAmount = PlantSeedDropAmount( seedUuid )
			local seedsCollected = sm.container.collect( container, seedUuid, seedAmount, false )
			if sm.container.endTransaction() then
				sm.effect.playEffect( "Plants - Picked", self.harvestable:getPosition() )
				sm.harvestable.createHarvestable( hvs_soil, self.harvestable:getPosition(), self.harvestable:getRotation() )
				RaidManager.Sv_CropDestroyed( self.harvestable )
				sm.achievement.addi( "943f3e53-cbe4-4a97-84a0-c5e742063799", 1, { player:getId() } ) -- Harvest mature plant

				self.harvestable:destroy()
				self.harvestable.publicData.harvested = true
				if seedsCollected < seedAmount then
					self.network:sendToClient( player, "cl_n_onInventoryFull" )
					local loot = { lootUid = seedUuid, lootQuantity = seedAmount - seedsCollected }
					local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
					sm.projectile.harvestableCustomProjectileAttack( loot, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
				end
			else
				self.network:sendToClient( player, "cl_n_onInventoryFull" )
			end
		end
	end
end








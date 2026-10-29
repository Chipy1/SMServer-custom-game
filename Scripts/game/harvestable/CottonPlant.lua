dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

CottonPlant = class( nil )

function CottonPlant.server_onCreate( self )
	self.harvestable.publicData = {}
end

function CottonPlant.client_onInteract( self, state )
	self.network:sendToServer( "sv_n_harvest" )
end

function CottonPlant.client_canInteract( self )
	sm.gui.setInteractionText( "", GetInteractionKeybinding(), "#{INTERACTION_PICK_UP}" )
	return true
end

function CottonPlant.server_canErase( self ) return true end
function CottonPlant.client_canErase( self ) return true end

function CottonPlant.server_onRemoved( self, player )
	self:sv_n_harvest( nil, player )
end

function CottonPlant.cl_n_onInventoryFull( self )
	NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 4 )
end

function CottonPlant.client_onCreate( self )
	self.cl = {}
	self.cl.cottonfluff = sm.effect.createEffect( "Cotton - Fluff" )
	self.cl.cottonfluff:setPosition( self.harvestable.worldPosition )
	self.cl.cottonfluff:setRotation( self.harvestable.worldRotation )
	self.cl.cottonfluff:start()
end

function CottonPlant.sv_n_harvest( self, _, player )
	if not self.harvested and sm.exists( self.harvestable ) then
		if SurvivalGame then
			local container = player:getInventory()
			if sm.container.beginTransaction() then
				sm.container.collect( container, ITEMS.obj_resource_cotton, 1, true )
				local seedAmount = PlantSeedDropAmount( ITEMS.obj_seed_cotton )
				local seedsCollected = sm.container.collect( container, ITEMS.obj_seed_cotton, seedAmount, false )
				if sm.container.endTransaction() then
					sm.effect.playEffect( "Cotton - Picked", self.harvestable.worldPosition )
					sm.harvestable.createHarvestable( hvs_farmables_growing_cottonplant, self.harvestable.worldPosition, self.harvestable.worldRotation )
					sm.harvestable.destroy( self.harvestable )
					self.harvested = true
					self.harvestable.publicData.harvested = true
					if seedsCollected < seedAmount then
						self.network:sendToClient( player, "cl_n_onInventoryFull" )
						local loot = { lootUid = ITEMS.obj_seed_cotton, lootQuantity = seedAmount - seedsCollected }
						local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
						sm.projectile.harvestableCustomProjectileAttack( loot, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
					end
				else
					self.network:sendToClient( player, "cl_n_onInventoryFull" )
				end
			end
		else
			sm.effect.playEffect( "Cotton - Picked", self.harvestable.worldPosition )
			sm.harvestable.createHarvestable( hvs_farmables_growing_cottonplant, self.harvestable.worldPosition, self.harvestable.worldRotation )
			sm.harvestable.destroy( self.harvestable )
			self.harvested = true
			self.harvestable.publicData.harvested = true
		end
	end
end

function CottonPlant.client_onDestroy( self )
	self.cl.cottonfluff:stop()
	self.cl.cottonfluff:destroy()
end

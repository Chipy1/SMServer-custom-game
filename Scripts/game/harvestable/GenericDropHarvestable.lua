-- GenericDropHarvestable.lua --
--
-- A generic harvestable that can be configured through data fields to drop items
-- and respond to different interaction types (melee, projectiles, explosions, interaction)
--
-- Example data configuration:
-- {
--     "lootSource" : "lootsource_mineral_01",
--     "reactToDrill": true,
--     "reactToInteraction": true,
--     "reactToMelee": true,
--     "reactToProjectiles": true,
--     "reactToCollision": true,
--     "reactToExplosions": true,
--     "drillTime": 3,
--     "harvestEffect": "Crystal - Shatter",
--     "stageEffect": "Crystal - Crack",
--     "persistentEffect": "Crystal - Glow",
--     "persistentEffectColor": "FFFFFF",
--     "stages": [
--         [ "m_gold0", "m_rock0" ],
--         [ "m_gold1", "m_rock1" ],
--         [ "m_gold2", "m_rock2" ]
--     ]
-- }

dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )

---@class GenericDropHarvestable : HarvestableClass
---@field harvested boolean?
---@field carved boolean?
---@field drillProgress number?
---@field cl table
GenericDropHarvestable = class( nil )

function GenericDropHarvestable.server_onCreate( self )
	if self.data.genericDropHarvestable.reactToDrill then
		self.harvestable.publicData = { drillLevel = 1 }
	end
end

function GenericDropHarvestable.sv_getStage( self )
	local stages = self.data.genericDropHarvestable.stages
	if not stages then
		return nil
	end

	local drillTime = self.data.genericDropHarvestable.drillTime or 1
	local fraction = ( self.drillProgress or 0 ) / drillTime
	return math.min( math.floor( fraction * #stages ) + 1, #stages )
end

function GenericDropHarvestable.sv_addProgress( self, amount )
	local previousStage = self:sv_getStage()
	self.drillProgress = self.drillProgress or 0
	self.drillProgress = self.drillProgress + amount
	local currentStage = self:sv_getStage()
	if currentStage and currentStage ~= previousStage then
		self.network:setClientData( currentStage )
	end
	if self.drillProgress >= ( self.data.genericDropHarvestable.drillTime or 1 ) then
		self:sv_dropLootAndDestroy()
	end
end

function GenericDropHarvestable.client_onInteract( self, state )
	if self.data.genericDropHarvestable.reactToInteraction then
		self.network:sendToServer( "sv_n_harvest" )
	end
end

function GenericDropHarvestable.client_canInteract( self )
	if self.data.genericDropHarvestable.reactToInteraction then
		sm.gui.setInteractionText( "", GetInteractionKeybinding(), "#{INTERACTION_PICK_UP}" )
		return true
	end
	return false
end

function GenericDropHarvestable.sv_dropLootAndDestroy( self )
	if not self.harvested and sm.exists( self.harvestable ) then
		if self.data.genericDropHarvestable.lootSource then
			local filter = bit.bor( sm.world.voxelFilter.material0, sm.world.voxelFilter.material1, sm.world.voxelFilter.material2, sm.world.voxelFilter.material3 )
			self.harvestable:getWorld():sphereVoxelDensitySubtraction( self.harvestable.worldPosition, 1.25, filter )
			self.carved = true
			local lootList = SelectLoot( self.data.genericDropHarvestable.lootSource )
			local min, max = self.harvestable:getLocalAabb()
			local offset = self.harvestable.worldRotation * ( min + max ) * 0.5
			local direction = self.harvestable.worldRotation * sm.vec3.new( 0, 1, 0 )
			SpawnLoot( self.harvestable, lootList, self.harvestable.worldPosition + offset, nil, nil, direction )
		end
		self:sv_destroy()
		self.harvested = true
	end
end

function GenericDropHarvestable.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if self.data.genericDropHarvestable.reactToCollision and type( other ) ~= "Character" then
		self:sv_dropLootAndDestroy()
	end
end

function GenericDropHarvestable.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if self.data.genericDropHarvestable.reactToMelee then
		local stages = self.data.genericDropHarvestable.stages
		if stages and #stages > 0 then
			local drillTime = self.data.genericDropHarvestable.drillTime or 1
			local progressPerStage = drillTime / #stages
			self:sv_addProgress( progressPerStage )
		else
			self:sv_dropLootAndDestroy()
		end
	end
end

function GenericDropHarvestable.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if self.data.genericDropHarvestable.reactToProjectiles and damage > 0 then
		self:sv_dropLootAndDestroy()
	end
end

function GenericDropHarvestable.server_onExplosion( self, center, destructionLevel )
	if self.data.genericDropHarvestable.reactToExplosions then
		self:sv_dropLootAndDestroy()
	end
end

function GenericDropHarvestable.sv_e_plasmaDrill( self, params )
	self:sv_addProgress( params.progress )
end

function GenericDropHarvestable.server_onFloating( self )
	self:sv_dropLootAndDestroy()
end

function GenericDropHarvestable.server_canErase( self ) return true end
function GenericDropHarvestable.client_canErase( self ) return true end

function GenericDropHarvestable.server_onRemoved( self, player )
	self:sv_n_harvest( nil, player )
end

function GenericDropHarvestable.client_onCreate( self )
	self.cl = {}
	self.cl.stage = 1
	if self.data.genericDropHarvestable.persistentEffect then
		self.cl.persistentEffect = sm.effect.createEffect( self.data.genericDropHarvestable.persistentEffect, self.harvestable )
		self.cl.persistentEffect:setAutoPlay( true )
		if self.data.genericDropHarvestable.persistentEffectColor then
			self.cl.persistentEffect:setParameter( "color", sm.color.new( self.data.genericDropHarvestable.persistentEffectColor ) )
		end
	end
	self:cl_updateVisibleSubmeshes()

end

function GenericDropHarvestable.client_onClientDataUpdate( self, data )
	self.cl.stage = data
	self:cl_updateVisibleSubmeshes()
	if self.data.genericDropHarvestable.stageEffect then
		sm.effect.playEffect( self.data.genericDropHarvestable.stageEffect, self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
	end
end

function GenericDropHarvestable.cl_updateVisibleSubmeshes( self )
	local stages = self.data.genericDropHarvestable.stages
	if not stages then
		return
	end

	for i = 1, #stages do
		local visible = ( i == self.cl.stage )
		for _, subMesh in ipairs( stages[i] ) do
			self.harvestable:setSubMeshVisible( subMesh, visible )
		end
	end

end

function GenericDropHarvestable.client_onDestroy( self )
	if self.cl.persistentEffect then
		self.cl.persistentEffect:stop()
		self.cl.persistentEffect:destroy()
	end
end

function GenericDropHarvestable.cl_n_onInventoryFull( self )
	NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 4 )
end

function GenericDropHarvestable.sv_n_harvest( self, params, player )
	if not self.harvested and sm.exists( self.harvestable ) then
		local container = player:getInventory()
		if sm.container.beginTransaction() then
			if self.data.genericDropHarvestable.lootSource then
				local lootList = SelectLoot( self.data.genericDropHarvestable.lootSource )
				for _, loot in ipairs( lootList ) do
					sm.container.collect( container, loot.uuid, loot.quantity, true )
				end
			end
			if sm.container.endTransaction() then
				self:sv_destroy()
				self.harvested = true
			else
				self.network:sendToClient( player, "cl_n_onInventoryFull" )
			end
		end
	end
end

function GenericDropHarvestable.sv_destroy( self )
	local pos = self.harvestable.worldPosition
	local rot = self.harvestable.worldRotation
	if self.data.genericDropHarvestable.harvestEffect then
		sm.effect.playEffect( self.data.genericDropHarvestable.harvestEffect, pos, nil, rot, nil, { Color = self.harvestable:getColor() } )
	end
	local harvestShape = self.data.genericDropHarvestable.harvestShape
	if harvestShape then
		if not self.carved then
			local filter = bit.bor( sm.world.voxelFilter.material0, sm.world.voxelFilter.material1, sm.world.voxelFilter.material2, sm.world.voxelFilter.material3 )
			self.harvestable:getWorld():sphereVoxelDensitySubtraction( pos, 1.25, filter )
			self.carved = true
		end
		local uid = ITEMS[harvestShape]
		sm.shape.createPart( uid, pos - rot * sm.item.getShapeSize( uid ) * 0.125, rot, true )
	end
	sm.harvestable.destroy( self.harvestable )
end
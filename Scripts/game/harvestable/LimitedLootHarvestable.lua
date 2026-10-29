-- LootHarvestable.lua --
dofile "$SURVIVAL_DATA/Scripts/game/harvestable/LootHarvestable.lua"

LimitedLootHarvestable = class( LootHarvestable )

function LimitedLootHarvestable.sv_addLimitedLoot( self )
	g_limitedLootLimits = g_limitedLootLimits or {}

	local value = g_limitedLootLimits[self.sv.tileStorageKey] or {}
	if value[self.sv.saved.limitedLoot] == nil then
		value[self.sv.saved.limitedLoot] = { limit = LIMITED_LOOT_DEFAULT_LIMIT, quantity = 0 }
	end
	value[self.sv.saved.limitedLoot].quantity = value[self.sv.saved.limitedLoot].quantity + 1
	g_limitedLootLimits[self.sv.tileStorageKey] = value
end

function LimitedLootHarvestable.sv_removeLimitedLoot( self )
	g_limitedLootLimits = g_limitedLootLimits or {}

	local value = g_limitedLootLimits[self.sv.tileStorageKey] or {}
	if value[self.sv.saved.limitedLoot] then
		value[self.sv.saved.limitedLoot].quantity = value[self.sv.saved.limitedLoot].quantity - 1
		g_limitedLootLimits[self.sv.tileStorageKey] = value
	end
end

function LimitedLootHarvestable.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or {}
	local save = false
	if self.params then
		self.sv.saved.uuid = self.params.uuid
		self.sv.saved.quantity = self.params.quantity
		self.sv.saved.epic = self.params.epic
		self.sv.saved.limitedLoot = self.params.limitedLoot
		save = true
	end
	self.sv.saved.uuid = self.sv.saved.uuid or sm.uuid.getNil()
	self.sv.saved.quantity = self.sv.saved.quantity or 0
	self.sv.saved.epic = self.sv.saved.epic or nil
	self.sv.saved.limitedLoot = self.sv.saved.limitedLoot or ""
	self.sv.saved.killTick = self.sv.saved.killTick or ( sm.game.getCurrentTick() + 12000 ) -- 5 minutes until removed
	if save then
		self.storage:save( self.sv.saved )
	end
	
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
	self:sv_addLimitedLoot()

	self.network:setClientData( { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, epic = self.sv.saved.epic } )
	self.harvestable.publicData = { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, vacuumable = true }
end

function LimitedLootHarvestable.server_onReceiveUpdate( self )
	if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested and sm.game.getCurrentTick() >= self.sv.saved.killTick then
		self.harvestable.publicData.harvested = true
		self:sv_removeLimitedLoot()
		self.harvestable:destroy()
	end
end

function LimitedLootHarvestable.server_onFloating( self )
	if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested then
		self.harvestable.publicData.harvested = true
		SpawnLoot( self.harvestable, { { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, epic = self.sv.saved.epic, limitedLoot = self.sv.saved.limitedLoot } }, nil, nil, 2 )
		self:sv_removeLimitedLoot()
		self.harvestable:destroy()
	end
end

function LimitedLootHarvestable.sv_n_harvest( self, params, player )
	if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested then
		-- Give the represented items to the interacting player and destroy the harvestable
		local container = player:getInventory()
		if sm.container.beginTransaction() then
			sm.container.collect( container, self.sv.saved.uuid, self.sv.saved.quantity )
			if sm.container.endTransaction() then
				self.harvestable.publicData.harvested = true
				sm.event.sendToPlayer( player, "sv_e_onLoot", { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, pos = self.harvestable:getPosition() } )
				self:sv_removeLimitedLoot()
				self.harvestable:destroy()
			else
				self.network:sendToClient( player, "cl_n_onInventoryFull" )
			end
		end
	end
end
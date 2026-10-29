dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

-- OBS: currently does not restart effects if game is quit while active. fix later
BalloonCrate = class()

EffectDurationTicks = 11.5 * 40 -- temp hack

local ReplacementUuid = sm.uuid.new( "3c51a75c-f201-4f2b-b995-b2036adf1427" )
local WarehouseDrop = tostring( obj_interactive_plasmadrill_lvl1 )
local SeedAmount = 5

function BalloonCrate.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	self.sv.index = 0
	if self.harvestable:getWorld().publicData and self.harvestable:getWorld().publicData.index then
		self.sv.index = self.harvestable:getWorld().publicData.index
	end
	if not self.sv.saved then
		self.sv.saved = {}
		self.sv.saved.opened = false
		self.sv.saved.lootSpawned = false
		if self.params and self.params.reward then
			self.sv.saved.reward = self.params.reward
		end
		if self.params and self.params.achievement then
			self.sv.saved.achievement = self.params.achievement
		end
		
		self.storage:save(self.sv.saved)
	end
	if self.sv.saved.opened == false and self.sv.index == 1 then
		if g_questPinManagerServer then
			QuestPinManager.Sv_AddPin( self.harvestable, self.harvestable:getWorld(), "SmashPin", sm.vec3.new( 0, 0, 1.8 ) )
		end
	end
    self.sv.tickCounter = 0
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
	self.network:setClientData( self.sv.saved )
end

function BalloonCrate.server_onFixedUpdate( self )
    if self.sv.saved.opened and not self.sv.saved.lootSpawned then
        self.sv.tickCounter = self.sv.tickCounter + 1
        if self.sv.tickCounter == EffectDurationTicks then
            self:sv_spawnLoot()
			self.sv.saved.lootSpawned = true
			self.storage:save( self.sv.saved )
        end
    end
end

function BalloonCrate.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_openChest()
	if g_questPinManagerServer and self.sv.index == 1 then
		QuestPinManager.Sv_RemovePin( self.harvestable.id, type( self.harvestable ) )
	end
end

function BalloonCrate.server_onExplosion( self, center, destructionLevel )
	self:sv_openChest()
end

function BalloonCrate.sv_openChest( self )
	if not self.sv.saved.opened then
        self.sv.saved.opened = true
		self.storage:save( self.sv.saved )
        self.network:setClientData( self.sv.saved )
		sm.effect.playEffect( "Ballooncrate - Balloon", self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
	end
end

function BalloonCrate.sv_spawnLoot( self )
	if sm.exists( self.harvestable ) then
		if self.sv.saved.reward then
			if self.sv.saved.achievement then
				sm.achievement.seti( self.sv.saved.achievement, 1 )
			end
			if ITEMS[self.sv.saved.reward] ~= nil then
				RecipeManager.Sv_UnlockRecipe( tostring( ITEMS[self.sv.saved.reward] ) )
			elseif CUSTOMIZATIONS[self.sv.saved.reward] ~= nil then
				sm.event.sendToGame( "sv_e_grantAdditionalRewards", { { uuid = CUSTOMIZATIONS[self.sv.saved.reward], type = "additionalReward" } } )
			end
		elseif self.harvestable:getWorld().publicData.type == "DungeonWorld" then
			local poiType = self.harvestable:getWorld().publicData.poiType
			RecipeManager.Sv_UnlockRecipe( POI_TYPE_TO_GROWLAB_BALLOONCRATE_REWARD[poiType] )
			QuestManager.Sv_SendEvent( QuestEvent.GrowlabRewardClaimed, { poiType = poiType } )
			ProgressionManager.Sv_MarkGrowlabCrateSmashed( poiType )
			sm.achievement.seti( "5b68f8e1-e2f3-4a69-8ddf-0808799dbdd9", 1 )
		elseif self.harvestable:getWorld().publicData.type == "WarehouseWorld" then
			RecipeManager.Sv_UnlockRecipe( WarehouseDrop )
		end
		sm.harvestable.createHarvestable( ReplacementUuid, self.harvestable.worldPosition, self.harvestable.worldRotation )
		self.harvestable:destroy()
	end
end

-- Client

function BalloonCrate.client_onClientDataUpdate( self, data, channel )
	if data.opened then
		self.harvestable:setSubMeshVisible( "questitems_balloon", false )
		self.harvestable:setSubMeshVisible( "questitems_ballooncrate_breakaway", false )
	end
end

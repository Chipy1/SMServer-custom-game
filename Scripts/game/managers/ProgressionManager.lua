dofile "$SURVIVAL_DATA/Scripts/game/survival_items.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_spawns.lua"
dofile "$SURVIVAL_DATA/Scripts/game/loot/lootconditions.lua"
dofile "$SURVIVAL_DATA/Scripts/terrain/overworld/poi_types.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_logs.lua"

ProgressionManager = class()

local MaxEnemiesDefeatedBeforeKey = 70
local MinEnemiesDefeatedBeforeKey = 50
local KeySpawnCooldownTicks = 40 * 60 * 5 -- 5 minutes

function ProgressionManager.server_onCreate( self )
    g_progressionManager = self

    self.sv = {}
    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_PROGRESSION_MANAGER )
    if self.sv.saved == nil then
        self.sv.saved = {}
    end

    self.sv.saved.completedGrowlabs = self.sv.saved.completedGrowlabs or {}
    self.sv.saved.seedTier = self.sv.saved.seedTier or 1
    self.sv.saved.vaultTotal = self.sv.saved.vaultTotal or 0
    self.sv.saved.growlabKeySpawnKillCount = self.sv.saved.growlabKeySpawnKillCount or 0
    self.sv.saved.lastKeySpawnTick = self.sv.saved.lastKeySpawnTick or -KeySpawnCooldownTicks
    self.sv.saved.warehouseConsoleUnlocked = self.sv.saved.warehouseConsoleUnlocked or false
    self.sv.saved.hasCraftedBeacon = self.sv.saved.hasCraftedBeacon or false
    self.sv.saved.reachedUndergroundDepths = self.sv.saved.reachedUndergroundDepths or {}
    if self.sv.saved.smashedGrowlabCrates == nil then
        -- Delay one tick so RecipeManager has loaded before we infer smashed crates from unlocked rewards.
        sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_patchSmashedGrowlabCrates" )
    end
    self.sv.saved.smashedGrowlabCrates = self.sv.saved.smashedGrowlabCrates or {}

    self.sv.dirty = false
    sm.storage.save( STORAGE_CHANNEL_PROGRESSION_MANAGER, self.sv.saved )
    self:sv_sync()
end

function ProgressionManager.sv_setClientData( self )
    self.network:setClientData( {
        hasCraftedBeacon = self.sv.saved.hasCraftedBeacon,
        warehouseConsoleUnlocked = self.sv.saved.warehouseConsoleUnlocked,
        vaultTotal = self.sv.saved.vaultTotal,
    } )
end

function ProgressionManager.Sv_CraftBeacon()
    if g_progressionManager then
        g_progressionManager:sv_craftBeacon()
    end
end

function ProgressionManager.sv_craftBeacon( self )
    if self.sv.saved.hasCraftedBeacon == false then
        self.sv.saved.hasCraftedBeacon = true
        self.sv.dirty = true
    end
end

function ProgressionManager.server_onFixedUpdate( self )
    if self.sv.dirty then
        self.sv.dirty = false
        self:sv_setClientData()
        sm.storage.save( STORAGE_CHANNEL_PROGRESSION_MANAGER, self.sv.saved )
    end
end

function ProgressionManager.server_onUnload( self )
    sm.storage.save( STORAGE_CHANNEL_PROGRESSION_MANAGER, self.sv.saved )
end

function ProgressionManager.Sv_ConditionsFulfilled( conditions )
	if conditions == nil then
		return true
	end
	if conditions.completedQuest and not QuestManager.Sv_IsQuestComplete( conditions.completedQuest ) then
		return false
	end
	if conditions.minSeedTier and ProgressionManager.Sv_GetSeedTier() < conditions.minSeedTier then
		return false
	end
	if conditions.impossible then
		return false
	end
	return true
end

function ProgressionManager.Sv_CompleteGrowlab( poiType )
    if g_progressionManager then
        g_progressionManager:sv_completeGrowlab( poiType )
    end
end

function ProgressionManager.sv_completeGrowlab( self, poiType )
    if self.sv.saved.completedGrowlabs[poiType] == nil then
		sm.log.info( "Growlab completed: "..tostring( poiType ) )
        self.sv.saved.completedGrowlabs[poiType] = true
        self.sv.saved.seedTier = self.sv.saved.seedTier + 1



        sm.storage.save( STORAGE_CHANNEL_PROGRESSION_MANAGER, self.sv.saved )
        QuestManager.Sv_SendEvent( QuestEvent.GrowlabCompleted, { poiType = poiType } )
		-- Some growlabs trigger a trader tracking call handing the player a follow-up log on completion.
		if poiType == POI_BURNTFOREST_GROWLAB_FROZEN_LARGE then
			sm.scriptableObject.createScriptableObject( sm.uuid.new( "9dde94ad-6524-4e1d-9024-1210c0ab659d" ), {
				dialogUuid = dialog_trader_tracking,
				dialogEntry = "NeedFruit",
				dialogType = DialogType.Call,
				dialogSpeaker = DialogSpeakerName.Hubert,
				tickDelay = 400,
				log = LOGS.log_packingstation_fruit
			} )
		end
		-- Reset seedbot spawn timers in all overworld cells so that they can spawn right away.
		-- Routed through the overworld so ResetNodeSpawnTimer runs with a current world.
		local overworld = WorldManager.Sv_GetWorld( "overworld" )
		sm.event.sendToWorld( overworld, "sv_e_resetNodeSpawnTimers", { tag = "SEEDBOT" }, sm.event.types.instant )
    end
end

-- Records that the reward crate for a growlab has been smashed. Leaving the growlab through the
-- entrance elevator afterwards counts as completing it (see MinidungeonElevator).
function ProgressionManager.Sv_MarkGrowlabCrateSmashed( poiType )
    if g_progressionManager then
        g_progressionManager:sv_markGrowlabCrateSmashed( poiType )
    end
end

function ProgressionManager.sv_markGrowlabCrateSmashed( self, poiType )
    if poiType and self.sv.saved.smashedGrowlabCrates[poiType] == nil then
        self.sv.saved.smashedGrowlabCrates[poiType] = true
        sm.storage.save( STORAGE_CHANNEL_PROGRESSION_MANAGER, self.sv.saved )
    end
end

function ProgressionManager.Sv_IsGrowlabCrateSmashed( poiType )
    if g_progressionManager then
        return g_progressionManager:sv_isGrowlabCrateSmashed( poiType )
    end
    return false
end

function ProgressionManager.sv_isGrowlabCrateSmashed( self, poiType )
    return self.sv.saved.smashedGrowlabCrates[poiType] == true
end

-- PATCH ------------------------------------------------------------
-- Saves predating smashedGrowlabCrates: the balloon crate unlocks the growlab's reward schematic
-- directly on smash, so an already-unlocked reward means the crate was smashed.
function ProgressionManager.sv_e_patchSmashedGrowlabCrates( self )
    if not g_recipeManager or not sm.game.getRecipesEnabled() then
        return
    end
    local changed = false
    for poiType, reward in pairs( POI_TYPE_TO_GROWLAB_BALLOONCRATE_REWARD ) do
        if self.sv.saved.smashedGrowlabCrates[poiType] == nil and RecipeManager.Sv_IsUnlocked( reward ) then
            self.sv.saved.smashedGrowlabCrates[poiType] = true
            changed = true
        end
    end
    if changed then
        sm.storage.save( STORAGE_CHANNEL_PROGRESSION_MANAGER, self.sv.saved )
    end
end

function ProgressionManager.Sv_SetVaultTotal( total )
    if g_progressionManager then
        g_progressionManager:sv_setVaultTotal( total )
    end
end

function ProgressionManager.sv_setVaultTotal( self, total )
    if total ~= self.sv.saved.vaultTotal then
        self.sv.saved.vaultTotal = total
        self.sv.dirty = true
    end
end

function ProgressionManager.Sv_GetVaultTotal()
    if g_progressionManager then
        return g_progressionManager:sv_getVaultTotal()
    end
    return 0
end

function ProgressionManager.sv_getVaultTotal( self )
    return self.sv.saved.vaultTotal
end

function ProgressionManager.Cl_GetVaultTotal()
    if g_progressionManagerClient then
        return g_progressionManagerClient:cl_getVaultTotal()
    end
    return 0
end

function ProgressionManager.cl_getVaultTotal( self )
    return self.cl.vaultTotal or 0
end

function ProgressionManager.Sv_GetSeedTier()
    if g_progressionManager then
        return g_progressionManager:sv_getSeedTier()
    end
	return 1
end

function ProgressionManager.sv_getSeedTier( self )
    return self.sv.saved.seedTier
end

-- Records that players have reached the given underground depth.
function ProgressionManager.Sv_SetReachedUndergroundDepth( depth )
    if g_progressionManager then
        g_progressionManager:sv_setReachedUndergroundDepth( depth )
    end
end

function ProgressionManager.sv_setReachedUndergroundDepth( self, depth )
    if self.sv.saved.reachedUndergroundDepths[depth] == nil then
        self.sv.saved.reachedUndergroundDepths[depth] = true
        sm.storage.save( STORAGE_CHANNEL_PROGRESSION_MANAGER, self.sv.saved )
    end
end

-- Returns true if players have reached the given underground depth.
function ProgressionManager.Sv_HasReachedUndergroundDepth( depth )
    if g_progressionManager then
        return g_progressionManager:sv_hasReachedUndergroundDepth( depth )
    end
    return false
end

function ProgressionManager.sv_hasReachedUndergroundDepth( self, depth )
    return self.sv.saved.reachedUndergroundDepths[depth] == true
end

function ProgressionManager.Sv_TrySpawnGrowlabKey( source )
    g_progressionManager:sv_trySpawnGrowlabKey( source )
end

function ProgressionManager.sv_trySpawnGrowlabKey( self, source )
	for _, log in ipairs( g_growlabLogs ) do
		if not LogEntryManager.Sv_HasLog( log.uuid ) then
			if ProgressionManager.Sv_ConditionsFulfilled( log.lootConditions ) then
				self.sv.saved.growlabKeySpawnKillCount = self.sv.saved.growlabKeySpawnKillCount + 1
				if sm.game.getCurrentTick() >= self.sv.saved.lastKeySpawnTick + KeySpawnCooldownTicks
					and self.sv.saved.growlabKeySpawnKillCount >= math.random( MinEnemiesDefeatedBeforeKey, MaxEnemiesDefeatedBeforeKey ) then
					local position = nil
					if type( source ) == "Unit" then
						position = source.character.worldPosition
					elseif type( source ) == "Harvestable" then
						position = source.worldPosition
					end
					if position then
						self.sv.saved.lastKeySpawnTick = sm.game.getCurrentTick()
						self.sv.saved.growlabKeySpawnKillCount = 0
						SpawnLogLoot( source, position, { displayItemUuid = ITEMS.obj_growlab_key, logUuid = log.uuid, color = log.color } )
					end
				end
			end
			break
		end
	end
end

function ProgressionManager.Sv_UnlockWarehouseConsole()
    return g_progressionManager:sv_unlockWarehouseConsole()
end

function ProgressionManager.sv_unlockWarehouseConsole( self )
    self.sv.saved.warehouseConsoleUnlocked = true
    sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_saveAndSync" )
end

function ProgressionManager.Sv_IsWarehouseConsoleUnlocked()
    if g_progressionManager then
        return g_progressionManager:sv_isWarehouseConsoleUnlocked()
    end
	return false
end

function ProgressionManager.sv_isWarehouseConsoleUnlocked( self )
    return self.sv.saved.warehouseConsoleUnlocked
end

function ProgressionManager.sv_e_saveAndSync( self )
    sm.storage.save( STORAGE_CHANNEL_PROGRESSION_MANAGER, self.sv.saved )
    self:sv_sync()
end

function ProgressionManager.sv_sync( self )
    self:sv_setClientData()
end

function ProgressionManager.client_onCreate( self )
    assert( g_progressionManagerClient == nil )
	g_progressionManagerClient = self

    self.cl = {}
    self.cl.hasCraftedBeacon = false
    self.cl.warehouseConsoleUnlocked = false
    self.cl.vaultTotal = 0
end

function ProgressionManager.client_onClientDataUpdate( self, clientData )
    if clientData then
        if clientData.hasCraftedBeacon ~= nil then
            self.cl.hasCraftedBeacon = clientData.hasCraftedBeacon
        end
        self.cl.warehouseConsoleUnlocked = clientData.warehouseConsoleUnlocked
        self.cl.vaultTotal = clientData.vaultTotal or 0
    end
end

function ProgressionManager.Cl_HasCraftedBeacon()
    if g_progressionManagerClient then
        return g_progressionManagerClient:cl_hasCraftedBeacon()
    end
    return false
end

function ProgressionManager.cl_hasCraftedBeacon( self )
    return self.cl.hasCraftedBeacon
end

function ProgressionManager.Cl_IsWarehouseConsoleUnlocked()
    if g_progressionManagerClient then
        return g_progressionManagerClient:cl_isWarehouseConsoleUnlocked()
    end
	return false
end

function ProgressionManager.cl_isWarehouseConsoleUnlocked( self )
    return self.cl.warehouseConsoleUnlocked
end
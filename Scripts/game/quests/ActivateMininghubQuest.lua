dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/powerladder_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile("$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/survival_logs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )

ActivateMininghubQuest = class()
ActivateMininghubQuest.isSaveObject = true

local WaitTickTime = 40
local FinishEvent = "event.quest_activate_mininghub.finish"
ActivateMininghubQuest.Stages = {
    power_stations         = 1,   -- Find and insert batteries into 4 stations
    listen_stations_dialog = 2,   -- Hidden: Lorenzo "pull the switch" call plays; tracker keeps the station checkmarks
    activate_pylon         = 3,   -- Pull the pylon lever
    wait_for_lights        = 4,   -- Lights come on, vault door opens
    enter_vault            = 5,   -- Walk into the vault
    interact_shop          = 6,   -- Interact with the axobot shop
    listen_lorenzo_vault   = 7,   -- Lorenzo calls about placing something valuable
    pickup_valuable        = 8,   -- Pick up one of the unlocked valuables in the vault
    place_valuable         = 9,   -- Place a valuable in the vault
    listen_axobot          = 10,  -- Axobot congratulates the player on the placed valuable
    get_card               = 11,  -- Interact with Wonky to receive access card 01
    wait_for_effect        = 12,
}
local Stages = ActivateMininghubQuest.Stages

local VaultEntranceTrigger = "quest_activate_mininghub.vault_entrance"

local ValuableUuid = sm.uuid.new( "127f5ce0-09d1-4e3a-b1ac-a89f6340ddc8" )
local ValuablesMarkerNode = "quest_activate_mininghub.valuables"
local VaultMarkerNode = "quest_activate_mininghub.vault"

local StationCount = 4
local StationActivatorFlags = {
    "minehub:dispenser.activated",
    "minehub:smelter.activated",
    "minehub:caster.activated",
    "minehub:powerrails.activated",
}

local StationMarkerNames = {
    ["minehub:dispenser.activated"]   = "quest_activate_mininghub.station_dispenser",
    ["minehub:smelter.activated"]     = "quest_activate_mininghub.station_smelter",
    ["minehub:caster.activated"]      = "quest_activate_mininghub.station_caster",
    ["minehub:powerrails.activated"]  = "quest_activate_mininghub.station_powerrails",
}

local StationTrackingKeys = {
    ["minehub:dispenser.activated"]   = "power_dispenser",
    ["minehub:smelter.activated"]     = "power_smelter",
    ["minehub:caster.activated"]      = "power_caster",
    ["minehub:powerrails.activated"]  = "power_powerrails",
}

local PylonMarkerName = "quest_activate_mininghub.pylon"

local PowerRailTags = {
    "ts:rail:powerrail_blue",
    "ts:rail:powerrail_cyan",
    "ts:rail:powerrail_gray",
    "ts:rail:powerrail_green",
    "ts:rail:powerrail_orange",
    "ts:rail:powerrail_pink",
    "ts:rail:powerrail_red",
    "ts:rail:powerrail_violet",
    "ts:rail:powerrail_yellow",
}

local LorenzoCallDelayTicks = 1 * 40   -- Dialog delay after closing shop GUI

local MininghubCell = { x = -2, y = -1 }

-- Server

function ActivateMininghubQuest.server_onCreate( self )
    self.sv = {}
    self.sv.dirty = false

    local world = WorldManager.Sv_GetWorld( "undergroundworld1" )
    self.sv.storageKey = TileStorageManager.Sv_GetTileStorageKeyFromCell( world, MininghubCell.x, MininghubCell.y )

    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.power_stations
        self.sv.saved.activatedStations = {}
        self.sv.saved.firstCallDone = false
        self.sv.saved.secondCallDone = false
        self.sv.dirty = true
    end
    self.network:setClientData( { stage = self.sv.saved.stage, activatedStations = self.sv.saved.activatedStations } )

    -- Reload recovery: reconstruct activatedStations from TILESTORAGE_FLAGS_TABLE
    if self.sv.saved.stage == Stages.power_stations then
        for _, flag in ipairs( StationActivatorFlags ) do
            if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.storageKey, TILESTORAGE_FLAGS_TABLE, flag ) == true then
                self.sv.saved.activatedStations[flag] = true
            end
        end
        -- Stations may have been activated before the quest started or completed prior to this reload
        if tableCount( self.sv.saved.activatedStations ) >= StationCount then
            self:sv_completePowerStations()
        end
    end

    -- Reload recovery: if lights are already on during wait_for_lights, advance
    if self.sv.saved.stage == Stages.wait_for_lights then
        self:sv_recoverLightsOn()
    end


    QuestManager.Sv_SubscribeEvent( "mininghub_station_activated", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "mininghub_lever_pulled", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "mininghub_lights_on", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( VaultEntranceTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "axobot_interaction_complete", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "axobot_gui_closed", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "axobot_card_taken", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.VaultTotalUpdated, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.InventoryChanges, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )
    QuestManager.Sv_SubscribeEvent( FinishEvent, self.scriptableObject, "sv_finishQuest" )




    self:sv_saveIfDirty()
end

function ActivateMininghubQuest.sv_unlockValuables( self )
    local triggerData = QuestEntityManager.Sv_GetNamedAreaTrigger( VaultEntranceTrigger )
    if not triggerData or not sm.exists( triggerData.areaTrigger ) then return false end
    local trigger = triggerData.areaTrigger
    -- The named area trigger has a character-only filter, so query the volume manually for shapes.
    local shapeContacts = sm.physics.getShapeContactsInBox( trigger:getWorldPosition(), trigger:getWorldRotation(), trigger:getSize(), trigger:getWorld() )
    local unlockedBodies = {}
    local unlockedAny = false
    for _, contact in ipairs( shapeContacts ) do
        local shape = contact.shape
        if sm.exists( shape ) and shape.uuid == ValuableUuid then
            local body = shape.body
            if not unlockedBodies[body.id] then
                unlockedBodies[body.id] = true
                body.buildable    = true
                body.paintable    = true
                body.connectable  = true
                body.liftable     = true
                body.erasable     = true
                body.usable       = true
                unlockedAny = true
            end
        end
    end
    return unlockedAny
end

function ActivateMininghubQuest.sv_completePowerStations( self )
    self.sv.saved.stage = Stages.listen_stations_dialog
    KinematicManager.Sv_Activate( self.sv.storageKey, "mininghub.pylon", { persistent = true } )
    DialogManager.Sv_PlayDialogBeat( "activated_all_stations_pull_the_switch", self.scriptableObject )
    self.sv.dirty = true
end

function ActivateMininghubQuest.sv_recoverLightsOn( self )
    if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.storageKey, TILESTORAGE_FLAGS_TABLE, "minehub:lights.activated" ) == true then
        KinematicManager.Sv_Activate( self.sv.storageKey, "vaultKinematic" )
        self.sv.saved.stage = Stages.enter_vault
        self.sv.dirty = true
    end
end





























































































function ActivateMininghubQuest.server_onFixedUpdate( self )

    --Recovery from a pylon that never raised.
    if not self.sv.pylonRaised and not KinematicManager.Sv_IsMoving( self.sv.storageKey, "mininghub.pylon" ) and ( self.sv.saved.stage == Stages.activate_pylon ) then
        local world = WorldManager.Sv_GetWorld( "undergroundworld1" )
        if sm.exists( world ) and world:isCellLoadedServer( MininghubCell.x, MininghubCell.y ) then
            KinematicManager.Sv_ResetTrack( self.sv.storageKey, "mininghub.pylon", { toBack = true } )
            self.sv.pylonRaised = true
        end
    end

    -- Retry unlocking the vault valuables while on the pickup stage.
    if self.sv.saved.stage == Stages.pickup_valuable and not self.sv.valuablesUnlocked then
        if self:sv_unlockValuables() then
           self.sv.valuablesUnlocked = true
        end
    end

    -- Delayed Lorenzo call after player closes shop GUI
    if self.sv.saved.stage == Stages.listen_lorenzo_vault and self.sv.saved.shopClosedTick then
        local currentTick = sm.game.getCurrentTick()
        if currentTick >= self.sv.saved.shopClosedTick + LorenzoCallDelayTicks then
            self.sv.saved.shopClosedTick = nil
            DialogManager.Sv_PlayDialogBeat( "after_close_shop_before_place_valuable", self.scriptableObject )
            self:sv_saveAndSync()
        end
    end
end

function ActivateMininghubQuest.sv_saveIfDirty( self )
    if self.sv.dirty then
        self.sv.dirty = false
        self:sv_saveAndSync()
    end
end

function ActivateMininghubQuest.sv_saveAndSync( self )
    self.storage:save( self.sv.saved )
    self.network:setClientData( { stage = self.sv.saved.stage, activatedStations = self.sv.saved.activatedStations } )
end

function ActivateMininghubQuest.sv_e_onQuestEvent( self, data )
    -- Advance pickup stage when the player picks up a valuable
    if data.event == QuestEvent.InventoryChanges then
        if self.sv.saved.stage == Stages.pickup_valuable then
            if FindInventoryChange( data.params.changes, ValuableUuid ) > 0 then
                self.sv.saved.stage = Stages.place_valuable
                self.sv.dirty = true
            end
        end
        self:sv_saveIfDirty()
        return
    end

    if self.sv.saved.stage == Stages.power_stations then
        if data.event == "mininghub_station_activated" and data.params and data.params.activatorStorageFlag then
            local flag = data.params.activatorStorageFlag
            if StationMarkerNames[flag] and not self.sv.saved.activatedStations[flag] then
                self.sv.saved.activatedStations[flag] = true
                if tableCount( self.sv.saved.activatedStations ) >= StationCount then
                    self:sv_completePowerStations()
                end
                self.sv.dirty = true
            end
        end
    elseif self.sv.saved.stage == Stages.activate_pylon then
        if data.event == "mininghub_lever_pulled" then
            self.sv.saved.stage = Stages.wait_for_lights
            self.sv.dirty = true
        end
    elseif self.sv.saved.stage == Stages.wait_for_lights then
        if data.event == "mininghub_lights_on" then
            KinematicManager.Sv_Activate( self.sv.storageKey, "vaultKinematic" )
            self.sv.saved.stage = Stages.enter_vault
            self.sv.dirty = true
            sm.achievement.seti("322bd992-a72d-4311-88b6-9417a663c10a", 1 )
        end
    elseif self.sv.saved.stage == Stages.enter_vault then
        if data.event == VaultEntranceTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.stage = Stages.interact_shop
            self.sv.dirty = true
        end
    elseif self.sv.saved.stage == Stages.interact_shop then
        if data.event == "axobot_interaction_complete" then
            self.sv.saved.stage = Stages.listen_lorenzo_vault
            self.sv.dirty = true
        end
    elseif self.sv.saved.stage == Stages.listen_lorenzo_vault then
        if data.event == "axobot_gui_closed" and not self.sv.saved.shopClosedTick then
            self.sv.saved.shopClosedTick = sm.game.getCurrentTick()
            self.sv.dirty = true
        end
    elseif self.sv.saved.stage == Stages.pickup_valuable or self.sv.saved.stage == Stages.place_valuable then
        if data.event == QuestEvent.VaultTotalUpdated and data.params.total > 0 then
            self.sv.saved.stage = Stages.listen_axobot
            self.sv.dirty = true
            PlayDialogBeatDelayed( "placed_first_valuable", 3 * 40 )
        end
    elseif self.sv.saved.stage == Stages.get_card then
        -- The access card log is granted by Wonky (MininghubTrader) on interaction; advance once it reports back.
        if data.event == "axobot_card_taken" then
            self.sv.saved.stage = Stages.wait_for_effect
            FinishQuestAfterDelay( FinishEvent, WaitTickTime )
            self.sv.dirty = true
        end
    end
    self:sv_saveIfDirty()
end

function ActivateMininghubQuest.sv_e_onDialogCompleted( self, data )
    if self.sv.saved.stage == Stages.listen_stations_dialog and IsDialogBeat( data.params.uuid, data.params.entryName, "activated_all_stations_pull_the_switch" ) then
        self.sv.saved.stage = Stages.activate_pylon
        self:sv_saveAndSync()
    elseif self.sv.saved.stage == Stages.listen_lorenzo_vault and IsDialogBeat( data.params.uuid, data.params.entryName, "after_close_shop_before_place_valuable" ) then
        self.sv.saved.stage = Stages.pickup_valuable
        self.sv.valuablesUnlocked = self:sv_unlockValuables()
        self:sv_saveAndSync()
    elseif self.sv.saved.stage == Stages.listen_axobot and IsDialogBeat( data.params.uuid, data.params.entryName, "placed_first_valuable" ) then
        self.sv.saved.stage = Stages.get_card
        self:sv_saveAndSync()
    end
end

function ActivateMininghubQuest.sv_finishQuest( self )
    self.sv.done = true
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )

    -- Start VaultQuest1 directly after getting the card. Lorenzo's "first quota" intro call is now played
    -- from VaultQuest1 shortly after it starts (see VaultQuest1.server_onCreate), rather than gating activation.
    CompleteQuest( "quest_activate_mininghub", "quest_vault_1" )
end

-- Client

function ActivateMininghubQuest.client_onCreate( self )
    self.cl = {}
    self.cl.activatedStations = {}
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.progressString = ""
    self.scriptableObject.clientPublicData.stage = Stages.power_stations

    QuestManager.Cl_OnQuestCreated( "quest_activate_mininghub" )
    QuestManager.Cl_UpdateQuestTracker()
end

function ActivateMininghubQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function ActivateMininghubQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage
    self.cl.activatedStations = data.activatedStations or {}
    self:cl_updateProgress( prevStage )
end

function ActivateMininghubQuest.cl_updateProgress( self, prevStage )
    if not self.cl.stage then return end
    local trackingData = self.data.trackingSteps
    -- Station power tracking (individual lines)
    for flag, trackingKey in pairs( StationTrackingKeys ) do
        trackingData[trackingKey].complete = self.cl.stage > Stages.power_stations or self.cl.activatedStations[flag] == true
    end
    trackingData.pylon.complete = self.cl.stage > Stages.activate_pylon
    trackingData.enter_vault.complete = self.cl.stage > Stages.enter_vault
    trackingData.interact_shop.complete = self.cl.stage > Stages.interact_shop
    trackingData.pickup_valuable.complete = self.cl.stage > Stages.pickup_valuable
    trackingData.place_valuable.complete = self.cl.stage > Stages.place_valuable
    trackingData.get_card.complete = self.cl.stage > Stages.get_card

    ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

    self.scriptableObject.clientPublicData.traderResponse = ( self.cl.stage == Stages.get_card ) and "give_access_card" or nil
    self.scriptableObject.clientPublicData.traderCardLog = ( self.cl.stage == Stages.get_card ) and tostring( LOGS.log_accesscard_01 ) or nil

    if self.cl.tracked then
        self:cl_updateMarkers()
    end
    QuestManager.Cl_UpdateQuestTracker()
end

function ActivateMininghubQuest.client_onRefresh( self )
    self:cl_updateProgress()
end

function ActivateMininghubQuest.cl_updateMarkers( self )
    self:cl_hideMarkers()
    if self.cl.stage == Stages.power_stations then
        for flag, markerName in pairs( StationMarkerNames ) do
            if not self.cl.activatedStations[flag] then
                QuestEntityManager.Cl_SetNamedQuestMarkerVisible( markerName, true )
            end
        end
    elseif self.cl.stage == Stages.activate_pylon then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( PylonMarkerName, true )
    elseif self.cl.stage == Stages.enter_vault then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_activate_mininghub.vault_door", true )
    elseif self.cl.stage == Stages.interact_shop then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_activate_mininghub.axobot", true )
    elseif self.cl.stage == Stages.pickup_valuable then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ValuablesMarkerNode, true )
    elseif self.cl.stage == Stages.place_valuable then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( VaultMarkerNode, true )
    elseif self.cl.stage == Stages.get_card or self.cl.stage == Stages.wait_for_effect then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_activate_mininghub.axobot", true )
    end
end

function ActivateMininghubQuest.cl_hideMarkers( self )
    for _, markerName in pairs( StationMarkerNames ) do
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( markerName, false )
    end
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( PylonMarkerName, false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_activate_mininghub.vault_door", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_activate_mininghub.axobot", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ValuablesMarkerNode, false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( VaultMarkerNode, false )
end

function ActivateMininghubQuest.cl_e_onTracked( self )
    self.cl.tracked = true
    self:cl_updateMarkers()
end

function ActivateMininghubQuest.cl_e_onUntracked( self )
    self.cl.tracked = false
    self:cl_hideMarkers()
end

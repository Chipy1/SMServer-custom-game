dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

FindExcavationIslandQuest = class()
FindExcavationIslandQuest.isSaveObject = true

local Stages = {
    find_lorenzo = 1,
    listen_excavation = 2,
    get_key = 3,
    pull_lever = 4,
    watch_bridge = 5,
    listen_boombox = 6,
    unlock_elevator = 7,
    descend = 8,
    explore_mine = 9,               -- Player explores underground, ends at hub trigger
}

local DistanceCheckFrequency = 5 * 40
local DistanceForDialog = 3000
local BoomboxTimeoutTicks = 10 * 40    -- 10 seconds before Lorenzo drops boombox as loot
local BoomboxUuid = sm.uuid.new( "03bdd942-c808-4795-aa0b-554fa98c3c74" )

local HubCallDelayTicks = 10 * 40     -- 10 seconds at 40 tps after entering hub trigger

local LorenzoAreaTrigger = "quest_findexcavation.area"
local HubAreaTrigger = "quest_findexcavation.hub_area"

function FindExcavationIslandQuest.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.find_lorenzo
        self.sv.saved.called = false
        self.sv.saved.tileStorageKey = nil
        NodeSpawnManager.Sv_ActivateSpawnTrigger( "event.quest_find_excavation.spawn_lorenzo", WorldManager.Sv_GetWorld( "overworld" ) )
    end

    self.sv.bridgePosition = QuestEntityManager.Sv_GetQuestMarkerPosition( "quest_findexcavation.button" )

    self.sv.callTickCounter = 0
    if not self.sv.bridgePosition then
        sm.message.subscribe( MESSAGE_TYPES.QUEST.TerrainLoaded, "sv_m_questEntityTerrainLoaded" )
    end

    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( LorenzoAreaTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( HubAreaTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.LorenzoTalk, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.BridgeRaised, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "bridge_button_pressed", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "mininghub_elevator_unlock", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "underground_elevator_used", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )




    QuestManager.Sv_SubscribeEvent( "give_boombox", self.scriptableObject, "sv_e_giveBoombox" )



    self:sv_setNpcInteractionData()
    self:sv_saveAndSync()
end

function FindExcavationIslandQuest.sv_m_questEntityTerrainLoaded( self, world )
    if world == WorldManager.Sv_GetWorld( "overworld" ) then
        self.sv.bridgePosition = QuestEntityManager.Sv_GetQuestMarkerPosition( "quest_findexcavation.button" )
    end
end

function FindExcavationIslandQuest.sv_setNpcInteractionData( self )
    if self.sv.previousInteraction == self.sv.saved.stage then
        return
    end
    if self.sv.saved.stage == Stages.listen_excavation then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Lorenzo, { animation = "emote_wave", canInteract = false } )
    elseif self.sv.saved.stage == Stages.get_key then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Lorenzo, { animation = "emote_give_in", canInteract = true, log = ITEMS.obj_underground_key } )
    elseif self.sv.saved.stage == Stages.pull_lever then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Lorenzo, { animation = "emote_give_out", canInteract = false } )
    end
    self.sv.previousInteraction = self.sv.saved.stage
end















function FindExcavationIslandQuest.server_onFixedUpdate( self )
    if not self.sv.saved.called and self.sv.saved.stage == Stages.find_lorenzo then
        self.sv.callTickCounter = self.sv.callTickCounter + 1
        if self.sv.callTickCounter >= DistanceCheckFrequency then
            self.sv.callTickCounter = 0
            local startCall = false
            if self.sv.bridgePosition then
                local closestDistance = math.huge
                for _,player in ipairs( sm.player.getAllPlayers() ) do
                    if player.character then
                        local distance = ( player.character.worldPosition - self.sv.bridgePosition ):length()
                        if distance < closestDistance then
                            closestDistance = distance
                        end
                    end
                end
                if closestDistance < DistanceForDialog then
                    startCall = true
                end
            end
            if startCall then
                self.sv.saved.called = true
                DialogManager.Sv_PlayDialogBeat( "lorenzo_calls_on_the_way_to_bridge", self.scriptableObject )
                self:sv_saveAndSync()
            end
        end
    end

    -- Boombox timeout: if Lorenzo offered the boombox but the player didn't take it, drop it as loot
    if self.sv.saved.boomboxTimeoutTick then
        if sm.game.getServerTick() >= self.sv.saved.boomboxTimeoutTick then
            local unit = QuestManager.Sv_GetQuestUnit( QuestUnits.Lorenzo )
            if unit and sm.exists( unit ) and sm.exists( unit.character ) then
                QuestManager.Sv_SetNpcInteractionData( QuestUnits.Lorenzo, { animation = "emote_give_out", canInteract = false } )
                local dropPos = unit.character.worldPosition + unit.character.direction -  sm.vec3.new( 0, 0, 0.5 )
                local upRotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) )
                local loot = sm.harvestable.createHarvestable( hvs_loot, dropPos, upRotation, nil, WorldManager.Sv_GetWorld( "overworld" ) )
                loot:setParams( { uuid = BoomboxUuid, quantity = 1 } )
                self.sv.saved.boomboxTimeoutTick = nil
                self:sv_saveAndSync()
            end
        end
    end
end

function FindExcavationIslandQuest.sv_saveAndSync( self )
    self.storage:save( self.sv.saved )
    self.network:setClientData( { stage = self.sv.saved.stage } )
end

function FindExcavationIslandQuest.sv_e_onQuestEvent( self, data )
    -- Boombox pickup: if player talks to Lorenzo while the boombox offer is still active, cancel the timeout
    if data.event == QuestEvent.LorenzoTalk and self.sv.saved.boomboxTimeoutTick then
        self.sv.saved.boomboxTimeoutTick = nil
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Lorenzo, { animation = "emote_give_out", canInteract = false } )
        self:sv_saveAndSync()
        return
    end

    if self.sv.saved.stage == Stages.find_lorenzo then
        if data.event == LorenzoAreaTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.stage = Stages.listen_excavation
            DialogManager.Sv_PlayDialogBeat( "meet_lorenzo_at_the_bridge", self.scriptableObject )
            QuestActorManager.Sv_BeginActorTrack( "lorenzoBridgeTrack", "Lorenzo" )
        end
    elseif self.sv.saved.stage == Stages.get_key then
        if data.event == QuestEvent.LorenzoTalk then
            self.sv.saved.stage = Stages.pull_lever
            local pos = QuestEntityManager.Sv_GetQuestMarkerPosition( "quest_findexcavation.button" )
            local world = WorldManager.Sv_GetWorld( "overworld" )
            --  notify move to next position
            QuestActorManager.Sv_NotifyActor( "Lorenzo", "notify.new_home" )

            self.sv.saved.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, pos )
            KinematicManager.Sv_Activate( self.sv.saved.tileStorageKey, "bridgeKinematic", { tick = sm.game.getServerTick() } )
            LogEntryManager.Sv_AddLog( LOGS.log_underground_elevator_key_01 )
            QuestManager.Sv_SendEvent( "bridgeQuestEvent" )
        end
    elseif self.sv.saved.stage == Stages.pull_lever then
        if data.event == "bridge_button_pressed" then
            self.sv.saved.stage = Stages.watch_bridge
        end
    elseif self.sv.saved.stage == Stages.watch_bridge then
        if data.event == QuestEvent.BridgeRaised then
            self.sv.saved.stage = Stages.listen_boombox
            QuestActorManager.Sv_NotifyActor( "Lorenzo", "notify.bridge_raised" )
            KinematicManager.Sv_Activate( self.sv.saved.tileStorageKey, "bridgeKinematic" )
            KinematicManager.Sv_Activate( self.sv.saved.tileStorageKey, "bridgeLeverKinematic" )
        end
    elseif data.event == "mininghub_elevator_unlock" then
        if self.sv.saved.stage == Stages.unlock_elevator then
            self.sv.saved.stage = Stages.descend
        end
    elseif data.event == "underground_elevator_used" then
        if self.sv.saved.stage <= Stages.descend then
            self.sv.saved.stage = Stages.explore_mine
        end
    elseif self.sv.saved.stage == Stages.explore_mine then
        -- Player enters the hub trigger box → complete quest + queue Lorenzo call to start next quest
        if data.event == HubAreaTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self:sv_finishQuest()
            return
        end
    end
    self:sv_setNpcInteractionData()
    self:sv_saveAndSync()
end

function FindExcavationIslandQuest.sv_finishQuest( self )
    self.sv.done = true
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
    LogEntryManager.Sv_AddLog( LOGS.log_mininghub )
    CompleteAndActivateQuestThroughDialogBeat( "quest_find_excavation", "quest_activate_mininghub", "lorenzo_activate_hub", 120 )
end

function FindExcavationIslandQuest.sv_e_onDialogCompleted( self, data )
    if data.params.uuid ~= dialog_find_excavation then
        return
    end
    if self.sv.saved.stage == Stages.listen_excavation and data.params.entryName ~= "LorenzoCall" then
        self.sv.saved.stage = Stages.get_key
    elseif self.sv.saved.stage == Stages.listen_boombox then
        self:sv_e_giveBoombox() -- fallback in case client-side dialog callback fails
        self.sv.saved.boomboxTimeoutTick = sm.game.getServerTick() + BoomboxTimeoutTicks
        self.sv.saved.stage = Stages.unlock_elevator
    else
        return
    end
    self:sv_setNpcInteractionData()
    self:sv_saveAndSync()
end

function FindExcavationIslandQuest.sv_e_giveBoombox( self )
    if not self.sv.saved.boomboxDone then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Lorenzo, { animation = "emote_give_in", canInteract = true, item = BoomboxUuid } )
        self.sv.saved.boomboxDone = true
        self.storage:save( self.sv.saved )
    end
end

-- Client

function FindExcavationIslandQuest.client_onCreate( self )
    self.cl = {}
    self.cl.stage = Stages.find_lorenzo
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.progressString = ""

    QuestManager.Cl_OnQuestCreated( "quest_find_excavation" )
    QuestManager.Cl_UpdateQuestTracker()
end

function FindExcavationIslandQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function FindExcavationIslandQuest.cl_n_spawnScannerbotEffect( self, params )
    ScannerbotManager.Cl_spawnScannerbotEffect( params )
end

function FindExcavationIslandQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage
    self:cl_updateProgress( prevStage )
end

function FindExcavationIslandQuest.cl_updateProgress( self, prevStage )
    local trackingData = self.data.trackingSteps
    trackingData.find.complete = self.cl.stage > Stages.find_lorenzo
    trackingData.key.complete = self.cl.stage > Stages.get_key
    trackingData.lever.complete = self.cl.stage >= Stages.watch_bridge
    trackingData.search.complete = self.cl.stage > Stages.unlock_elevator
    trackingData.elevator.complete = self.cl.stage > Stages.descend
    trackingData.explore.complete = false  -- never completes within this quest; quest ends at hub trigger

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )
    if self.cl.stage == Stages.pull_lever then
        self.scriptableObject.clientPublicData.onButtonStep = true
    end
    if self.cl.tracked then
        self:cl_updateMarkers()
    end
    QuestManager.Cl_UpdateQuestTracker()
end

function FindExcavationIslandQuest.client_onRefresh( self )
    self:cl_updateProgress()
end

function FindExcavationIslandQuest.cl_updateMarkers( self )
    self:cl_hideMarkers()
    if self.cl.stage == Stages.find_lorenzo then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_findexcavation.button", true )
    elseif self.cl.stage == Stages.unlock_elevator then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_findexcavation.elevator", true )
    elseif self.cl.stage == Stages.descend then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_findexcavation.descend", true )
    end
end

function FindExcavationIslandQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_findexcavation.button", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_findexcavation.elevator", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_findexcavation.descend", false )
end

function FindExcavationIslandQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function FindExcavationIslandQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end 
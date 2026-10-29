dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestEntityManager.lua" )

ScrapyardQuest = class()
ScrapyardQuest.isSaveObject = true

local Stages = {
    arrive = 1,
    defeat_the_trashbot = 2,
    wait_for_dialog = 3,
}

local RAIL_TAG = "ts:rail:scrapyard"
local ELEVATOR_CONNECTION = "TILE_ELEVATOR_TRASHBOT_CONNECTION"

local NextQuestDelay = 30 -- seconds
local DefeatDialogBeat = "lorenzo_trashbot_defeated"

local ElevatorArriveTrigger = "underground_trashbot.elevator_arrive"

function ScrapyardQuest.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.arrive
    end
    self.sv.cinematicTriggered = false

    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( ElevatorArriveTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_scrapyard.spawn_trashbot", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_scrapyard.defeat_trashbot", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_scrapyard.remove_projectiles", self.scriptableObject, "sv_e_removeTrashbotProjectiles" )
    QuestManager.Sv_SubscribeEvent( "event.quest_scrapyard.bossfight_music", self.scriptableObject, "sv_e_setBossFightMusicFlag" )
    QuestManager.Sv_SubscribeEvent( "quest_event.trashbot.attack", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )





    self:sv_saveAndSync()
end











function ScrapyardQuest.sv_saveAndSync( self )
    self.storage:save( self.sv.saved )
    self.network:setClientData( { stage = self.sv.saved.stage } )
end

function ScrapyardQuest.sv_setElevatorDisabled( self, disabled )
    if not self.sv.saved.tileKey then return end
    local elevatorData = TileStorageManager.Sv_GetValueInSubTable( self.sv.saved.tileKey, TILE_ELEVATOR_TABLE, ELEVATOR_CONNECTION )
    if elevatorData then
        elevatorData.disabled = disabled
        TileStorageManager.Sv_SetValueInSubTable( self.sv.saved.tileKey, TILE_ELEVATOR_TABLE, ELEVATOR_CONNECTION, elevatorData )
        TileStorageManager.Sv_Save()
    end
end

function ScrapyardQuest.sv_e_setBossFightMusicFlag( self )
    -- Tell the trashbot to enable its client-side boss music radius monitor.
    -- Fired by the spawn cinematic right after players are teleported into the arena.
    sm.message.send( MESSAGE_TYPES.GENERAL.SetTrashbotBossMusic )
end

function ScrapyardQuest.sv_e_onQuestEvent( self, data )
    if data.event == "quest_event.trashbot.attack" then
        sm.game.resumeSaving( "Trashbot Spawn Cinematic 2" )
        DialogManager.Sv_PlayDialogBeat( "lorenzo_trashbot_reaction", self.scriptableObject )
        self.sv.saved.stage = Stages.defeat_the_trashbot
        self.scriptableObject:setPublicData( { bossfight = true } )
    end

    if self.sv.saved.stage == Stages.arrive and not self.sv.cinematicTriggered then
        if data.event == ElevatorArriveTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            local namedAreaTrigger = QuestEntityManager.Sv_GetNamedAreaTrigger( ElevatorArriveTrigger )
            sm.game.pauseSaving( "Trashbot Spawn Cinematic 2", 40 * 30 )
            local world = namedAreaTrigger.areaTrigger:getWorld()
            -- Play cinematic (placeholder name)
            EffectManager.Sv_PlayNamedCinematic( {
                name = "cinematic.trashbot02",
                callbackData = { world = world, players = QuestEntityManager.Sv_GetNamedAreaTriggerPlayers( ElevatorArriveTrigger ) },
                interruptible = false
            } )

            -- Activate powerladder and disable elevator
            local triggerAreaPosition = namedAreaTrigger.areaTrigger:getWorldPosition()
            local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world , triggerAreaPosition )
            self.sv.saved.tileKey = tileKey
            SetRailPower( true, RAIL_TAG, tileKey )
            self:sv_setElevatorDisabled( true )
            self.sv.cinematicTriggered = true
        end
    end

    if self.sv.saved.stage == Stages.defeat_the_trashbot then
        if data.event == "event.quest_scrapyard.defeat_trashbot" then
            self.sv.saved.stage = Stages.wait_for_dialog
            DialogManager.Sv_PlayDialogBeat( DefeatDialogBeat, self.scriptableObject )
        end
    end

    self:sv_saveAndSync()
end

function ScrapyardQuest.sv_e_removeTrashbotProjectiles( self, data )
    -- The trashbot unit has been destroyed; broadcast the (now-dead) character and the world
    -- it died in to clients so they can clear any of its in-flight projectiles locally.
    self.network:sendToClients( "cl_n_removeTrashbotProjectiles", { character = data.params.character, world = data.params.world } )
end

function ScrapyardQuest.cl_n_removeTrashbotProjectiles( self, params )
    if params.character and params.world then
        sm.projectile.removeProjectilesWithSource( params.character, 0, params.world )
    end
end

function ScrapyardQuest.sv_e_onDialogCompleted( self, data )
    if self.sv.saved.stage == Stages.wait_for_dialog and IsDialogBeat( data.params.uuid, data.params.entryName, DefeatDialogBeat ) then
        self:sv_finishQuest()
    end
end

function ScrapyardQuest.sv_finishQuest( self )
    self:sv_setElevatorDisabled( false )
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )

    if QuestManager.Sv_IsQuestComplete( "quest_vault_3" ) then
        -- Edge case: the player completed the vault_3 quota before reaching the scrapyard.
        -- vault_3 did not start the station quest (it deferred to here), so play a rapid catch-up
        -- sequence that ends by starting the second station quest.
        CompleteQuest( "quest_scrapyard" )
        DialogManager.Sv_PlayDialogBeat( "scrapyard_complete_start_vault3", self.scriptableObject )
        DialogManager.Sv_PlayDialogBeat( "phae_station_2_hint", self.scriptableObject )

        ActivateQuestThroughDialogBeat( "quest_station_2", "finish_quota_3_start_station_2", 0 )
    else
        CompleteAndActivateQuestThroughDialogBeat( "quest_scrapyard", "quest_vault_3", "scrapyard_complete_start_vault3", NextQuestDelay )
    end
end

-- Client

function ScrapyardQuest.client_onCreate( self )
    QuestManager.Cl_OnQuestCreated( "quest_scrapyard" )
    self.cl = {}
    self.cl.stage = Stages.arrive
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.progressString = ""
end

function ScrapyardQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function ScrapyardQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage
    local trackingData = self.data.trackingSteps
    if trackingData then
        trackingData.defeat.complete = self.cl.stage > Stages.defeat_the_trashbot
        ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )
    end
    QuestManager.Cl_UpdateQuestTracker()
end



function ScrapyardQuest.cl_e_onTracked( self )
    self.cl.tracked = true
end

function ScrapyardQuest.cl_e_onUntracked( self )
    self.cl.tracked = false
end

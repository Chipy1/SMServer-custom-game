dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestActorManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ProgressionManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/UndergroundElevatorManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_logs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

VaultQuest2 = class()
VaultQuest2.isSaveObject = true

local QUEST_NAME = "quest_vault_2"
local WaitTickTime = 40
local FinishEvent = "event.quest_vault_2.finish"

local Stages = {
    speak_with_lorenzo = 1,
    track_quota = 2,
    listen_axobot = 3,  -- Quota done: listen to Axobot's completion call before fetching the card.
    get_card = 4,
    wait_for_effect = 5,  -- Dummy final stage: lets the get_card checkmark show before the quest untracks.
}

local AxobotQuotaCompleteBeat = "axobot_quota_2_complete"

local LorenzoTrack = "lorenzoArrive"
local HubertTrack = "hubertArrive"
local DialogUnblockEvent = "vault_quest_2.become_interactable"
local NpcArriveSpawnEvent = "quest.npc_arrive"

local DistanceCheckFrequency = 5 * 40
local HubertCallDistance = 150

local Quota2UndergroundWorld = "undergroundworld4"
local Drill1FloorIndex = 5 -- UNDERGROUND_ELEVATORS["MAIN"].floors[5] = drill1

-- Hubert's "digging" bond builder, fired once players dig far enough from the drill1 elevator.
local DiggingBondBuilder = "drill1_digging"

-- Access card ("vault quota key") handed over by the trader (Wonky/Axobot) once the quota is met.
local AccessCardLog = LOGS.log_accesscard_03
-- Trader quest marker shown while the player needs to return for the access card.
local TraderMarker = "quest_activate_mininghub.axobot"

-- Server

function VaultQuest2.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {
            stage = Stages.speak_with_lorenzo,
            lorenzoTalkStarted = false,
            lorenzoHalfCallDone = false,
        }
        self.storage:save( self.sv.saved )
    end
    self.sv.distanceCheckCounter = 0
    self.sv.elevatorPosition = nil

    -- Ensure actors have tracks assigned (works on saved state, no unit required)
    local lorenzoData = QuestActorManager.Sv_GetActor( "Lorenzo" )
    local needsSpawn = false
    if not lorenzoData or lorenzoData.stateData.trackName ~= LorenzoTrack then
        QuestActorManager.Sv_BeginActorTrack( LorenzoTrack, "Lorenzo" )
        needsSpawn = true
    end
    local hubertData = QuestActorManager.Sv_GetActor( "Hubert" )
    if not hubertData or hubertData.stateData.trackName ~= HubertTrack then
        QuestActorManager.Sv_BeginActorTrack( HubertTrack, "Hubert" )
        needsSpawn = true
    end

    -- ensure the npcs are spawned in case previous trigger failed.
    if needsSpawn then
        local undergroundWorld = WorldManager.Sv_GetWorld( "undergroundworld1" )
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Lorenzo, nil )
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, nil )
        NodeSpawnManager.Sv_ActivateSpawnTrigger( NpcArriveSpawnEvent, undergroundWorld )
    end

    if self.sv.saved.stage == Stages.speak_with_lorenzo then
        QuestActorManager.Sv_NotifyActor( "Lorenzo", DialogUnblockEvent )
        QuestActorManager.Sv_NotifyActor( "Hubert", DialogUnblockEvent )
    end

    QuestManager.Sv_SubscribeEvent( QuestEvent.VaultTotalUpdated, self.scriptableObject, "sv_e_onVaultTotalUpdated" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.LorenzoTalk, self.scriptableObject, "sv_e_onLorenzoTalk" )
    -- Player must collect the access card from the trader (Wonky) to finish the quest.
    QuestManager.Sv_SubscribeEvent( "axobot_card_taken", self.scriptableObject, "sv_e_onCardTaken" )
    -- Delayed finish: fired by FinishQuestAfterDelay once the get_card checkmark has had time to show.
    QuestManager.Sv_SubscribeEvent( FinishEvent, self.scriptableObject, "sv_finishQuest" )





    self:sv_updateQuestProgress( ProgressionManager.Sv_GetVaultTotal() )

    self:sv_sync()
end

-- Fires Hubert's "digging" bond builder once players dig far enough from the drill1 elevator.
-- The quest does not track that it has fired; DialogManager guarantees a named bond builder plays only once.
function VaultQuest2.server_onFixedUpdate( self )
    if self.sv.saved.stage ~= Stages.track_quota then
        return
    end

    self.sv.distanceCheckCounter = self.sv.distanceCheckCounter + 1
    if self.sv.distanceCheckCounter < DistanceCheckFrequency then
        return
    end
    self.sv.distanceCheckCounter = 0

    -- Try to cache elevator position in drill1 world
    if not self.sv.elevatorPosition then
        self.sv.elevatorPosition = UndergroundElevatorManager.Sv_GetFloorPosition( "MAIN", Drill1FloorIndex )
    end
    if not self.sv.elevatorPosition then
        return
    end
    local undergroundWorld = WorldManager.Sv_GetWorld( Quota2UndergroundWorld )
    if not undergroundWorld then
        return
    end

    for _, player in ipairs( sm.player.getAllPlayers() ) do
        if player.character and player.character:getWorld() == undergroundWorld then
            local distance = ( player.character.worldPosition - self.sv.elevatorPosition ):length()
            if distance >= HubertCallDistance then
                DialogManager.Sv_PlayNamedBondBuilder( DiggingBondBuilder )
                return
            end
        end
    end
end

function VaultQuest2.sv_e_onVaultTotalUpdated( self, data )
    self:sv_updateQuestProgress( data.params.total )
end

function VaultQuest2.sv_e_onLorenzoTalk( self )
    -- Check the "speak with Lorenzo" step while the dialog is playing rather than after it completes.
    if self.sv.saved.stage == Stages.speak_with_lorenzo and not self.sv.saved.lorenzoTalkStarted then
        self.sv.saved.lorenzoTalkStarted = true
        self.storage:save( self.sv.saved )
        self:sv_sync()
    end
end

function VaultQuest2.sv_updateQuestProgress( self, vaultTotal )
    local step = self.data.trackingSteps.quota

    -- Lorenzo calls at 50% quota
    if not self.sv.saved.lorenzoHalfCallDone and vaultTotal >= math.floor( step.threshold / 2 ) then
        self.sv.saved.lorenzoHalfCallDone = true
        self.storage:save( self.sv.saved )
        DialogManager.Sv_PlayDialogBeat( "lorenzo_quota_2_halfway", self.scriptableObject )
    end

    -- Quota reached: complete the quota step and play congratulatory dialog. The trader hands over the
    -- access card; the quest finishes once the player collects it.
    if vaultTotal >= step.threshold and self.sv.saved.stage == Stages.track_quota then
        self.sv.saved.stage = Stages.listen_axobot
        self.storage:save( self.sv.saved )
        DialogManager.Sv_PlayDialogBeat( AxobotQuotaCompleteBeat, self.scriptableObject )
        QuestManager.Sv_SendEvent( QuestEvent.VaultQuotaReached )
    end

    self:sv_sync( vaultTotal )
end

function VaultQuest2.sv_e_onDialogCompleted( self, data )
    if self.sv.saved.stage == Stages.speak_with_lorenzo and IsDialogBeat( data.params.uuid, data.params.entryName, "speak_to_lorenzo_to_start_second_quota" ) then
        self.sv.saved.stage = Stages.track_quota
        self.storage:save( self.sv.saved )
        self:sv_updateQuestProgress( ProgressionManager.Sv_GetVaultTotal() )
    elseif IsDialogBeat( data.params.uuid, data.params.entryName, AxobotQuotaCompleteBeat ) then
        -- Quota dialog finished: now send the player back to the trader to collect the access card.
        if self.sv.saved.stage == Stages.listen_axobot then
            self.sv.saved.stage = Stages.get_card
            self.storage:save( self.sv.saved )
            self:sv_sync()
        end
    end
end

-- Collected the access card: advance to wait_for_effect so the get_card checkmark flashes, then finish after a short delay.
function VaultQuest2.sv_e_onCardTaken( self )
    if self.sv.saved.stage == Stages.get_card then
        self.sv.saved.stage = Stages.wait_for_effect
        self.storage:save( self.sv.saved )
        self:sv_sync()
        FinishQuestAfterDelay( FinishEvent, WaitTickTime )
    end
end

function VaultQuest2.sv_sync( self, vaultTotal )
    vaultTotal = vaultTotal or ProgressionManager.Sv_GetVaultTotal()
    self.network:setClientData( { stage = self.sv.saved.stage, vaultTotal = vaultTotal, lorenzoTalkStarted = self.sv.saved.lorenzoTalkStarted } )
end

function VaultQuest2.sv_finishQuest( self )
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )

    -- Phae congratulates after the complete popup shows, then starts vault_3 once her dialog finishes.
    -- Routed through the util so the quest completes, rewards are granted, and vault_3 is gated on the dialog.
    CompleteAndActivateQuestThroughDialogBeat( QUEST_NAME, "quest_vault_3", "phae_quota_2_complete_fake_start_quota_3", 3 )
end

-- Client

function VaultQuest2.client_onCreate( self )
    self.cl = {}
    self.scriptableObject.clientPublicData = {}

    QuestManager.Cl_OnQuestCreated( QUEST_NAME )
    QuestManager.Cl_UpdateQuestTracker()
end

function VaultQuest2.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function VaultQuest2.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage
    self.cl.vaultTotal = data.vaultTotal
    self.cl.lorenzoTalkStarted = data.lorenzoTalkStarted
    self:cl_updateProgress( prevStage )
end

function VaultQuest2.cl_updateProgress( self, prevStage )
    local trackingData = self.data.trackingSteps
    local stage = self.cl.stage
    if not stage then return end

    trackingData.speak_with_lorenzo.complete = stage > Stages.speak_with_lorenzo or self.cl.lorenzoTalkStarted == true

    if stage >= Stages.track_quota then
        local vaultTotal = self.cl.vaultTotal or 0
        trackingData.quota.count1 = vaultTotal
        trackingData.quota.count2 = trackingData.quota.threshold
    end
    -- get_card completes at the wait_for_effect stage; its flash plays via ApplyTrackingProgress.
    trackingData.get_card.complete = stage > Stages.get_card

    ApplyTrackingProgress( self, trackingData, stage, prevStage )
    
    -- Tell the trader (Wonky) to hand over this quest's access card while we're in the get_card stage.
    self.scriptableObject.clientPublicData.traderResponse = ( stage == Stages.get_card ) and "give_access_card" or nil
    self.scriptableObject.clientPublicData.traderCardLog = ( stage == Stages.get_card ) and tostring( AccessCardLog ) or nil
    self.scriptableObject.clientPublicData.stage = stage

    if self.cl.tracked then
        self:cl_updateMarkers()
    end
    QuestManager.Cl_UpdateQuestTracker()
end

function VaultQuest2.client_onRefresh( self )
    self:cl_updateProgress()
end

function VaultQuest2.cl_e_onTracked( self )
    self.cl.tracked = true
    self:cl_updateMarkers()
end

function VaultQuest2.cl_e_onUntracked( self )
    self.cl.tracked = false
    self:cl_hideMarkers()
end

function VaultQuest2.cl_updateMarkers( self )
    self:cl_hideMarkers()
    if self.cl.stage == Stages.speak_with_lorenzo then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_lorenzo.marker", true )
    elseif self.cl.stage == Stages.get_card or self.cl.stage == Stages.wait_for_effect then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( TraderMarker, true )
    end
end

function VaultQuest2.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_lorenzo.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( TraderMarker, false )
end

dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ProgressionManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/NodeSpawnManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_logs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

VaultQuest1 = class()
VaultQuest1.isSaveObject = true

local QUEST_NAME = "quest_vault_1"
local WaitTickTime = 40
local FinishEvent = "event.quest_vault_1.finish"

local Stages = {
    track_quota = 1,
    listen_axobot = 2,  -- Quota done: listen to Axobot's completion call before fetching the card.
    get_card = 3,
    wait_for_effect = 4,  -- Dummy final stage: lets the get_card checkmark show before the quest untracks.
}

local AxobotQuotaCompleteBeat = "axobot_quota_1_complete"

-- Lorenzo's "first quota" intro call, played shortly after this quest starts (like the bosstrain intro).
local LorenzoFirstQuotaCallBeat = "started_quota1"
local LorenzoFirstQuotaCallDelay = 8 * 40

local FirstCaveTrigger = "onboarding_cave_first"
local SecondCaveTrigger = "onboarding_cave_second"
local FinalCaveTrigger = "onboarding_cave_final"

local NpcArriveSpawnEvent = "quest.npc_arrive"

-- Access card ("vault quota key") handed over by the trader (Wonky/Axobot) once the quota is met.
local AccessCardLog = LOGS.log_accesscard_02
-- Trader quest marker shown while the player needs to return for the access card.
local TraderMarker = "quest_activate_mininghub.axobot"

-- Bonus elevator marker (not a quest stage): reuses the mysterious-signal marker inside the MAIN
-- elevator, shown until the player rides below the mining hub.
local ElevatorMarker = "quest_mysterious_signal.elevator"
local MininghubFloorIndex = 2 -- UNDERGROUND_ELEVATORS["MAIN"].floors[2] = "mining hub, main elevator"

-- Server

function VaultQuest1.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.track_quota
        self.sv.saved.firstCaveHubertCallDone = false
        self.sv.saved.finalCaveLorenzoHintDone = false
        self.sv.saved.npcArriveDone = false
        self.sv.saved.leftMininghub = false
        self.storage:save( self.sv.saved )

        PlayDialogBeatDelayed( LorenzoFirstQuotaCallBeat, LorenzoFirstQuotaCallDelay )
    end

    if not self.sv.saved.firstCaveHubertCallDone then
        QuestManager.Sv_SubscribePlayerEnterAreaTrigger( FirstCaveTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    end
    if not self.sv.saved.npcArriveDone then
        QuestManager.Sv_SubscribePlayerEnterAreaTrigger( SecondCaveTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    end
    if not self.sv.saved.finalCaveLorenzoHintDone then
        QuestManager.Sv_SubscribePlayerEnterAreaTrigger( FinalCaveTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    end

    QuestManager.Sv_SubscribeEvent( QuestEvent.VaultTotalUpdated, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )
    -- Player must collect the access card from the trader (Wonky) to finish the quest.
    QuestManager.Sv_SubscribeEvent( "axobot_card_taken", self.scriptableObject, "sv_e_onCardTaken" )
    -- Delayed finish: fired by FinishQuestAfterDelay once the get_card checkmark has had time to show.
    QuestManager.Sv_SubscribeEvent( FinishEvent, self.scriptableObject, "sv_finishQuest" )
    -- Bonus elevator-marker hint: stop watching once the player has ridden below the mining hub.
    if not self.sv.saved.leftMininghub then
        QuestManager.Sv_SubscribeEvent( "underground_elevator_used", self.scriptableObject, "sv_e_onElevatorUsed" )
    end




    self:sv_updateQuestProgress( ProgressionManager.Sv_GetVaultTotal() )
end

function VaultQuest1.sv_e_onQuestEvent( self, data )
    local event = data.event

    if event == FirstCaveTrigger..QuestEvent.AreaTriggerPlayerEnterSuffix then
        if self.sv.saved.firstCaveHubertCallDone then
            return
        end
        self.sv.saved.firstCaveHubertCallDone = true
        self.storage:save( self.sv.saved )
        QuestManager.Sv_UnsubscribeEvent( event, self.scriptableObject )
        DialogManager.Sv_PlayDialogBeat( "enter_first_onboarding_cave", self.scriptableObject )

    elseif event == SecondCaveTrigger..QuestEvent.AreaTriggerPlayerEnterSuffix then
        if self.sv.saved.npcArriveDone then
            return
        end
        self.sv.saved.npcArriveDone = true
        self.storage:save( self.sv.saved )
        QuestManager.Sv_UnsubscribeEvent( event, self.scriptableObject )
        DialogManager.Sv_PlayDialogBeat( "enter_second_onboarding_cave", self.scriptableObject )
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Lorenzo, nil )
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, nil )
        NodeSpawnManager.Sv_ActivateSpawnTrigger( NpcArriveSpawnEvent, WorldManager.Sv_GetWorld( "undergroundworld1" ) )

    elseif event == FinalCaveTrigger..QuestEvent.AreaTriggerPlayerEnterSuffix then
        if self.sv.saved.finalCaveLorenzoHintDone then
            return
        end
        self.sv.saved.finalCaveLorenzoHintDone = true
        self.storage:save( self.sv.saved )
        QuestManager.Sv_UnsubscribeEvent( event, self.scriptableObject )
        DialogManager.Sv_PlayDialogBeat( "enter_final_onboarding_cave", self.scriptableObject )

    elseif event == QuestEvent.VaultTotalUpdated then
        self:sv_updateQuestProgress( data.params.total )
    end
end

function VaultQuest1.sv_e_onDialogCompleted( self, data )
    if IsDialogBeat( data.params.uuid, data.params.entryName, AxobotQuotaCompleteBeat ) then
        -- Quota dialog finished: now send the player back to the trader to collect the access card.
        if self.sv.saved.stage == Stages.listen_axobot then
            self.sv.saved.stage = Stages.get_card
            self.storage:save( self.sv.saved )
            self:sv_sync()
        end
    end
end

-- Finish the quest once the player has collected the access card from the trader (Wonky/Axobot).
function VaultQuest1.sv_e_onCardTaken( self )
    if self.sv.saved.stage == Stages.get_card then
        self.sv.saved.stage = Stages.wait_for_effect
        self.storage:save( self.sv.saved )
        self:sv_sync()
        FinishQuestAfterDelay( FinishEvent, WaitTickTime )
    end
end

-- Hide the bonus elevator marker once the player rides the MAIN elevator below the mining hub.
function VaultQuest1.sv_e_onElevatorUsed( self, data )
    if self.sv.saved.leftMininghub then
        return
    end
    if data.params.elevatorName == "MAIN" and data.params.floor > MininghubFloorIndex then
        self.sv.saved.leftMininghub = true
        self.storage:save( self.sv.saved )
        QuestManager.Sv_UnsubscribeEvent( "underground_elevator_used", self.scriptableObject )
        self:sv_sync()
    end
end

function VaultQuest1.sv_updateQuestProgress( self, vaultTotal )
    local step = self.data.trackingSteps.quota
    if vaultTotal >= step.threshold and self.sv.saved.stage == Stages.track_quota then
        self.sv.saved.stage = Stages.listen_axobot
        self.storage:save( self.sv.saved )
        DialogManager.Sv_PlayDialogBeat( AxobotQuotaCompleteBeat, self.scriptableObject )
        QuestManager.Sv_SendEvent( QuestEvent.VaultQuotaReached )
    end

    self:sv_sync( vaultTotal )
end

function VaultQuest1.sv_sync( self, vaultTotal )
    vaultTotal = vaultTotal or ProgressionManager.Sv_GetVaultTotal()
    self.network:setClientData( { stage = self.sv.saved.stage, vaultTotal = vaultTotal, showElevatorMarker = not self.sv.saved.leftMininghub } )
end

function VaultQuest1.sv_finishQuest( self )
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )

    -- Start the next quest from a slightly delayed dialog after this quest completes.
    CompleteAndActivateQuestThroughDialogBeat( QUEST_NAME, "quest_mysterious_signal", "lorenzo_first_station_start", 3 )
end

-- Client

function VaultQuest1.client_onCreate( self )
    self.cl = {}
    self.cl.showElevatorMarker = false
    self.scriptableObject.clientPublicData = {}

    QuestManager.Cl_OnQuestCreated( QUEST_NAME )
    QuestManager.Cl_UpdateQuestTracker()
end

function VaultQuest1.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function VaultQuest1.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage or Stages.track_quota
    self.cl.vaultTotal = data.vaultTotal
    self.cl.showElevatorMarker = data.showElevatorMarker == true
    self:cl_updateProgress( prevStage )
end

function VaultQuest1.cl_updateProgress( self, prevStage )
    local vaultTotal = self.cl.vaultTotal or 0
    local stage = self.cl.stage or Stages.track_quota
    local trackingData = self.data.trackingSteps

    trackingData.quota.count1 = vaultTotal
    trackingData.quota.count2 = trackingData.quota.threshold

    trackingData.get_card.complete = stage > Stages.get_card

    ApplyTrackingProgress( self, trackingData, stage, prevStage )

    -- Tell the trader (Wonky) to hand over this quest's access card while we're in the get_card stage.
    self.scriptableObject.clientPublicData.traderResponse = ( stage == Stages.get_card ) and "give_access_card" or nil
    self.scriptableObject.clientPublicData.traderCardLog = ( stage == Stages.get_card ) and tostring( AccessCardLog ) or nil

    if self.cl.tracked then
        self:cl_updateMarkers()
    end
    QuestManager.Cl_UpdateQuestTracker()
end

function VaultQuest1.cl_updateMarkers( self )
    -- Bonus hint pointing back to the elevator until the player rides below the mining hub. Not a quest stage.
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ElevatorMarker, self.cl.showElevatorMarker == true and self.cl.stage == Stages.track_quota )
    -- Point back to the trader while collecting the access card; kept through wait_for_effect so the checkmark settles.
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( TraderMarker, self.cl.stage == Stages.get_card or self.cl.stage == Stages.wait_for_effect )
end

function VaultQuest1.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ElevatorMarker, false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( TraderMarker, false )
end

function VaultQuest1.client_onRefresh( self )
    self:cl_updateProgress()
end

function VaultQuest1.cl_e_onTracked( self )
    self.cl.tracked = true
    self:cl_updateMarkers()
end

function VaultQuest1.cl_e_onUntracked( self )
    self.cl.tracked = false
    self:cl_hideMarkers()
end

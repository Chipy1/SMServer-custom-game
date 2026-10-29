dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

ClearMinidungeonQuest = class()
ClearMinidungeonQuest.isSaveObject = true

local Stages = {
    talk_to_farmer = 1,
    listen_to_farmer = 2,
    grab_the_key = 3,
    reach_minidungeon = 4,
    active_keyreader = 5,
    call_elevator = 6,
    activate_elevator = 7,
    reach_the_end = 8,
    claim_reward = 9,
    get_out = 10,
    receive_call = 11
}

local GrowlabNearAreaTrigger = "growlab01_near_area.trigger"
local GrowlabEndTrigger = "quest_clear_minidungeon_end.trigger"
local GrowlabExitAreaTrigger = "growlab01_exit_area.trigger"

function ClearMinidungeonQuest.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.talk_to_farmer
        self.sv.saved.destroyedBots = 0
        NodeSpawnManager.Sv_ActivateSpawnTrigger( "event.clearMinidungeon", nil )





    end
    self.sv.previousInteraction = nil
    
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( GrowlabNearAreaTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( GrowlabEndTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( GrowlabExitAreaTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.GrowlabUnlocked, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.GrowlabElevatorCalled, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.GrowlabElevatorActivated, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.GrowlabRewardClaimed, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.LogBookWaypointTracked, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.FarmerTalk, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )




    
    self:sv_saveAndSync()
end

function ClearMinidungeonQuest.sv_setNpcInteractionData( self )
    if self.sv.previousInteraction == self.sv.saved.stage then
        return
    end
    if self.sv.saved.stage == Stages.talk_to_farmer then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = true } )
    elseif self.sv.saved.stage == Stages.grab_the_key then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { animation = "emote_give_in", canInteract = true, log = ITEMS.obj_growlab_key } )
    elseif self.sv.saved.stage == Stages.reach_minidungeon then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { animation = "emote_give_out", canInteract = false } )
    else
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = false } )
    end
    self.sv.previousInteraction = self.sv.saved.stage
end






























function ClearMinidungeonQuest.sv_saveAndSync( self )
    self.storage:save( self.sv.saved )
    self.network:setClientData( { stage = self.sv.saved.stage } )
    self:sv_setNpcInteractionData()
end

function ClearMinidungeonQuest.sv_e_onQuestEvent( self, data )













    if self.sv.saved.stage == Stages.talk_to_farmer then
        if data.event == QuestEvent.FarmerTalk then
            self.sv.saved.stage = Stages.listen_to_farmer
            DialogManager.Sv_PlayDialogBeat( "hubert_clear_minidungeon_request", self.scriptableObject )
        end
    elseif self.sv.saved.stage == Stages.grab_the_key then
        if data.event == QuestEvent.FarmerTalk then
            LogEntryManager.Sv_SetLogHighlight( LOGS.log_growlab_01, true )
            LogEntryManager.Sv_AddLog( tostring( LOGS.log_growlab_01 ) )
            self.sv.saved.stage = Stages.reach_minidungeon
        end
    elseif self.sv.saved.stage == Stages.active_keyreader then
        if data.event == QuestEvent.GrowlabUnlocked then
            if data.params.poiType == POI_MEADOW_GROWLAB_QUEST_LARGE then
                self.sv.saved.stage = Stages.call_elevator
            end
        end
    elseif self.sv.saved.stage == Stages.call_elevator then
        if data.event == QuestEvent.GrowlabElevatorCalled then
            if data.params.poiType == POI_MEADOW_GROWLAB_QUEST_LARGE then
                self.sv.saved.stage = Stages.activate_elevator
            end
        end
    elseif self.sv.saved.stage == Stages.activate_elevator then
        if data.event == QuestEvent.GrowlabElevatorActivated then
            if data.params.poiType == POI_MEADOW_GROWLAB_QUEST_LARGE then
                self.sv.saved.stage = Stages.reach_the_end
            end
        end
    elseif self.sv.saved.stage == Stages.reach_the_end then
        if data.event == GrowlabEndTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.stage = Stages.claim_reward
        end
    elseif self.sv.saved.stage == Stages.claim_reward then
        if data.event == QuestEvent.GrowlabRewardClaimed then
            if data.params.poiType == POI_MEADOW_GROWLAB_QUEST_LARGE then
                self.sv.saved.stage = Stages.get_out
            end
        end
    elseif self.sv.saved.stage == Stages.get_out then
        if data.event == GrowlabExitAreaTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix or data.event == QuestEvent.GrowlabElevatorActivated then
            self:sv_finishQuest()
        end
    end
    if self.sv.saved.stage <= Stages.reach_minidungeon and self.sv.saved.stage > Stages.listen_to_farmer then
        if data.event == GrowlabNearAreaTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.stage = Stages.active_keyreader
            LogEntryManager.Sv_SetLogHighlight( LOGS.log_growlab_01, false )
        end
    end
    if data.event == QuestEvent.GrowlabRewardClaimed then
        if data.params.poiType == POI_MEADOW_GROWLAB_QUEST_LARGE then
            if self.sv.saved.stage < Stages.claim_reward then
                self.sv.saved.stage = Stages.get_out
            end
        end
    end
    self:sv_saveAndSync()
end

function ClearMinidungeonQuest.sv_finishQuest( self ) 
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
    CompleteAndActivateQuestThroughDialogBeat( "quest_clear_minidungeon", "quest_trader_tracking", "growlab_cleared_trader_tracking_start" )
    NodeSpawnManager.Sv_DeactivateSpawnTrigger( "event.clearMinidungeon" )
end

function ClearMinidungeonQuest.sv_e_onDialogCompleted( self, data )
    if data.params.uuid ~= dialog_clear_minidungeon then
        return
    end
    if self.sv.saved.stage == Stages.listen_to_farmer then
        self.sv.saved.stage = Stages.grab_the_key
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { animation = "emote_give_in", log = LOGS.log_growlab_01 } )
    end
    self:sv_saveAndSync()
end

-- Client

function ClearMinidungeonQuest.client_onCreate( self )
    self.cl = {}
    self.cl.stage = Stages.listen_to_farmer
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.progressString = ""
    QuestManager.Cl_OnQuestCreated( "quest_clear_minidungeon" )
end

function ClearMinidungeonQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end



function ClearMinidungeonQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    if data.stage ~= self.cl.stage then
		self:cl_hideMarkers()
        self.cl.stage = data.stage
	end
    
    self:cl_updateProgress( prevStage )
    self:cl_updateMarkers()
end

function ClearMinidungeonQuest.cl_updateProgress( self, prevStage )
    local trackingData = self.data.trackingSteps
    trackingData.speak.complete = self.cl.stage > Stages.talk_to_farmer
    trackingData.key.complete = self.cl.stage > Stages.grab_the_key
    trackingData.enter.complete = self.cl.stage > Stages.activate_elevator
    trackingData.reach_end.complete = self.cl.stage > Stages.reach_the_end
    trackingData.reward.complete = self.cl.stage > Stages.claim_reward
    trackingData.exit.complete = self.cl.stage > Stages.get_out

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

    QuestManager.Cl_UpdateQuestTracker()
end

function ClearMinidungeonQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end
    if self.cl.stage == Stages.talk_to_farmer then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", true )
    elseif self.cl.stage == Stages.active_keyreader then
        QuestEntityManager.Cl_ActivateEventPing( "ping_keyreader" )
    elseif self.cl.stage == Stages.call_elevator then
        QuestEntityManager.Cl_ActivateEventPing( "ping_keyreader" )
    elseif self.cl.stage == Stages.activate_elevator then
        QuestEntityManager.Cl_ActivateEventPing( "ping_elevatorbutton" )
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_minidungeon_end.marker", true )
    elseif self.cl.stage == Stages.reach_the_end then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_minidungeon_end.marker", true )
    elseif self.cl.stage == Stages.get_out then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_minidungeon_exit.marker", true )
        QuestEntityManager.Cl_ActivateEventPing( "ping_trashchute" )
    end
end

function ClearMinidungeonQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_minidungeon_position.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_minidungeon_end.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_minidungeon_exit.marker", false )
    QuestEntityManager.Cl_DeactivateEventPing( "ping_keyreader" )
    QuestEntityManager.Cl_DeactivateEventPing( "ping_elevatorbutton" )
    QuestEntityManager.Cl_DeactivateEventPing( "ping_trashchute" )
end

function ClearMinidungeonQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function ClearMinidungeonQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end
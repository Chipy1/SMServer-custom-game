dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua"

FindRecordingQuest = class()
FindRecordingQuest.isSaveObject = true

local Stages = {
    talk_to_farmer = 1,
    listen_to_farmer = 2,
    grab_recording = 3,
    start_recording1 = 4,
    listen_to_book_recording = 5,
    go_to_bunks = 6,
    investigate = 7,
    find_the_recording = 8,
    start_recording2 = 9,
    listen_to_the_recording = 10,
}

local BunksTrigger = "quest_find_bunks.trigger"
local RecordingTrigger = "quest_find_recording.trigger"

function FindRecordingQuest.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.talk_to_farmer
    end
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( BunksTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( RecordingTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_find_recording.pick_up_recording", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.FarmerTalk, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.RecordingStarted, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )





    self.sv.lastInteraction = nil
    self:sv_saveAndSync()
    self:sv_setNpcInteractionData()
end















function FindRecordingQuest.sv_setNpcInteractionData( self )
    if self.sv.lastInteraction == self.sv.saved.stage then
        return
    end
    if self.sv.saved.stage == Stages.talk_to_farmer then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = true } )
    elseif self.sv.saved.stage == Stages.grab_recording then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { animation = "emote_give_in", canInteract = true, log = sm.uuid.new( "44395054-ce48-40ba-aa21-03eae2298834" ) } )
    elseif self.sv.saved.stage == Stages.start_recording1 then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { animation = "emote_give_out", canInteract = false } )
    end
    self.sv.lastInteraction = self.sv.saved.stage
end

function FindRecordingQuest.sv_saveAndSync( self )
    self.storage:save( self.sv.saved )
    self.network:setClientData( { stage = self.sv.saved.stage } )
end

function FindRecordingQuest.sv_e_onQuestEvent( self, data )

    if self.sv.saved.stage == Stages.talk_to_farmer then
        if data.event == QuestEvent.FarmerTalk then
            self.sv.saved.stage = Stages.listen_to_farmer
            DialogManager.Sv_PlayDialogBeat( "hubert_talk_to_farmer_recording", self.scriptableObject )
        end
    elseif self.sv.saved.stage == Stages.grab_recording then
        if data.event == QuestEvent.FarmerTalk then
            self.sv.saved.stage = Stages.start_recording1
            LogEntryManager.Sv_AddLog( LOGS.log_audioBunkRecording )
            LogEntryManager.Sv_SetLogHighlight( LOGS.log_audioBunkRecording, true )
        end
    elseif self.sv.saved.stage == Stages.start_recording1 then
        if data.event == QuestEvent.RecordingStarted then
            if data.params and data.params.dialogUuid == dialog_recording_1 and data.params.entry == "FindRecordingFirst" then
                self.sv.saved.stage = Stages.listen_to_book_recording
            end
        end
    elseif self.sv.saved.stage == Stages.listen_to_book_recording then
        -- handled by sv_e_onDialogCompleted
    elseif self.sv.saved.stage == Stages.go_to_bunks then
        if data.event == BunksTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            NodeSpawnManager.Sv_ActivateSpawnTrigger( "quest_find_recording_trigger", WorldManager.Sv_GetWorld( "overworld" ) )
            self.sv.saved.stage = Stages.investigate
            QuestEntityManager.Sv_BumpNamedAreaTrigger( RecordingTrigger )
        end
    elseif self.sv.saved.stage == Stages.investigate then
        if data.event == RecordingTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.stage = Stages.find_the_recording
        end
    elseif self.sv.saved.stage == Stages.find_the_recording then
        if data.event == "event.quest_find_recording.pick_up_recording" then
            self.sv.saved.stage = Stages.start_recording2
            NodeSpawnManager.Sv_ActivateSpawnTrigger( "event.findRecording.enemies", WorldManager.Sv_GetWorld( "overworld" ) )
            LogEntryManager.Sv_AddLog( LOGS.log_audioBunkRecording2 )
            LogEntryManager.Sv_SetLogHighlight( LOGS.log_audioBunkRecording2, true )
        end
    elseif self.sv.saved.stage == Stages.start_recording2 then
        if data.event == QuestEvent.RecordingStarted then
            if data.params and data.params.dialogUuid == dialog_recording_2 and data.params.entry == "FindRecordingSecond" then
                self.sv.saved.stage = Stages.listen_to_the_recording
            end
        end
    elseif self.sv.saved.stage == Stages.listen_to_the_recording then
        -- handled by sv_e_onDialogCompleted
    end
    self:sv_setNpcInteractionData()
    self:sv_saveAndSync()
end

function FindRecordingQuest.sv_finishQuest( self )
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
    CompleteAndActivateQuestThroughDialogBeat( "quest_find_recording", "quest_clear_warehouse", "found_recordings_start_clear_warehouse" )
    NodeSpawnManager.Sv_DeactivateSpawnTrigger( "quest_find_recording_trigger" )
end

function FindRecordingQuest.sv_e_onDialogCompleted( self, data )
    if data.params.uuid == dialog_find_recording_quest then
        if self.sv.saved.stage == Stages.listen_to_farmer then
            self.sv.saved.stage = Stages.grab_recording
        end
    elseif data.params.uuid == dialog_recording_1 and data.params.entryName == "FindRecordingFirst" then
        if self.sv.saved.stage == Stages.listen_to_book_recording then
            self.sv.saved.stage = Stages.go_to_bunks
            QuestEntityManager.Sv_BumpNamedAreaTrigger( BunksTrigger )
        end
    elseif data.params.uuid == dialog_recording_2 and data.params.entryName == "FindRecordingSecond" then
        if self.sv.saved.stage == Stages.listen_to_the_recording then
            self:sv_finishQuest()
            return
        end
    else
        return
    end
    self:sv_setNpcInteractionData()
    self:sv_saveAndSync()
end

function FindRecordingQuest.client_onCreate( self )
    self.cl = {}
    self.cl.stage = Stages.talk_to_farmer
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.progressString = ""
    self.cl.tracked = true
    QuestManager.Cl_OnQuestCreated( "quest_find_recording" )
end

function FindRecordingQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function FindRecordingQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage
    self:cl_updateProgress( prevStage )
end

function FindRecordingQuest.cl_updateProgress( self, prevStage )

    local trackingData = self.data.trackingSteps
    trackingData.talk.complete = self.cl.stage > Stages.talk_to_farmer
    trackingData.recording.complete = self.cl.stage > Stages.start_recording1
    trackingData.find.complete = self.cl.stage > Stages.go_to_bunks
    trackingData.investigate.complete = self.cl.stage > Stages.investigate
    trackingData.retrieve.complete = self.cl.stage > Stages.start_recording2

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

    if self.cl.stage == Stages.start_recording1 then
        QuestManager.Cl_SetQuestRecording( dialog_recording_1, "FindRecordingFirst" )
    elseif self.cl.stage == Stages.start_recording2 then
        QuestManager.Cl_SetQuestRecording(  dialog_recording_2, "FindRecordingSecond" )
    else
        QuestManager.Cl_SetQuestRecording( nil, nil )
    end
    self:cl_updateMarkers()
	QuestManager.Cl_UpdateQuestTracker()
end

function FindRecordingQuest.cl_updateMarkers( self )

    if not self.cl.tracked then
        return
    end

    self:cl_hideMarkers()

    if self.cl.stage == Stages.go_to_bunks or self.cl.stage == Stages.investigate then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_find_recording.area_waypoint", true )
    elseif self.cl.stage == Stages.talk_to_farmer or self.cl.stage == Stages.return_to_farmer then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", true )
    elseif self.cl.stage == Stages.find_the_recording then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_find_recording.recording_marker", true )
    end
end

function FindRecordingQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_find_recording.area_waypoint", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_find_recording.recording_marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", false )
end

function FindRecordingQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function FindRecordingQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end 
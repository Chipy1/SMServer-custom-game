dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

RebuildWatchtowerQuest = class()
RebuildWatchtowerQuest.isSaveObject = true

local Stages = {
    rebuild_lookout = 1,
    return_to_farmer = 2,
    listen_to_farmer = 3
}

function RebuildWatchtowerQuest.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.rebuild_lookout
    end
    self.sv.previousInteraction = nil

	QuestManager.Sv_SubscribeEvent( "event.quest_rebuild_watchtower.update", self.scriptableObject, "sv_e_onBuilderGuideUpdate" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.FarmerTalk, self.scriptableObject, "sv_e_onTalkToFarmer" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )





    -- ensure that hubert will move off the platform in his hideout track.
    QuestActorManager.Sv_NotifyActor( "Hubert", "notify.encounter_done" )
	QuestActorManager.Sv_NotifyActor( "Hubert", "notify.ruins_cleared" )

    self:sv_saveAndSync()
end

function RebuildWatchtowerQuest.sv_setNpcInteractionData( self )
    if self.sv.previousInteraction == self.sv.saved.stage then
        return
    end
    if self.sv.saved.stage == Stages.return_to_farmer then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = true } )
    else
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = false } )
    end
    self.sv.previousInteraction = self.sv.saved.stage
end















function RebuildWatchtowerQuest.sv_saveAndSync( self )
    self:sv_setNpcInteractionData()
    self.storage:save( self.sv.saved )
    self.network:setClientData( { stage = self.sv.saved.stage } )
end

function RebuildWatchtowerQuest.sv_e_onTalkToFarmer( self, data )
    if self.sv.saved.stage == Stages.return_to_farmer then
        DialogManager.Sv_PlayDialogBeat( "hubert_receive_reward", self.scriptableObject )
        self.sv.saved.stage = Stages.listen_to_farmer
    end
    self:sv_saveAndSync()
end

function RebuildWatchtowerQuest.sv_finishQuest( self )
    self:sv_setNpcInteractionData()
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )

    -- this completion is prerequisite for "quest_find_excavation" activation from trader. next quest may start from there.
    CompleteQuest( "quest_rebuild_watchtower" )
end

function RebuildWatchtowerQuest.sv_e_onDialogCompleted( self, data )
    if self.sv.saved.stage == Stages.listen_to_farmer and IsDialogBeat( data.params.uuid, data.params.entryName, "hubert_receive_reward" ) then
        self:sv_finishQuest()
    end
end

function RebuildWatchtowerQuest.sv_e_onBuilderGuideUpdate( self, data )
	if data.params.isComplete then
		QuestManager.Sv_SendEvent( "event.quest_build_watchtower.build_complete", data )
		self.sv.saved.stage = Stages.return_to_farmer
		self:sv_saveAndSync()
	end
end

-- Client

function RebuildWatchtowerQuest.client_onCreate( self )
    self.cl = {}
    self.cl.stage = Stages.listen_to_farmer
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.guideActive = true
    self.scriptableObject.clientPublicData.progressString = ""

    self:cl_updateMarkers()
    QuestManager.Cl_OnQuestCreated( "quest_rebuild_watchtower" )
    QuestManager.Cl_UpdateQuestTracker()
end

function RebuildWatchtowerQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function RebuildWatchtowerQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage
    self:cl_updateProgress( prevStage )
end

function RebuildWatchtowerQuest.cl_updateProgress( self, prevStage )
    local trackingData = self.data.trackingSteps
    trackingData.build.complete = self.cl.stage > Stages.rebuild_lookout
    trackingData.talk.complete = self.cl.stage > Stages.return_to_farmer

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )
    if self.cl.stage == Stages.rebuild_lookout then
        self.scriptableObject.clientPublicData.guideActive = true
        self.scriptableObject.clientPublicData.blueprintPath = "$SURVIVAL_DATA/BuilderGuides/bq_watchtower_02_guide.json"
    else
        self.scriptableObject.clientPublicData.blueprintPath = nil
        self.scriptableObject.clientPublicData.guideActive = false
    end
    self:cl_updateMarkers()
    QuestManager.Cl_UpdateQuestTracker()
end

function RebuildWatchtowerQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end

    self:cl_hideMarkers()

    if self.cl.stage == Stages.return_to_farmer then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", true )
    elseif self.cl.stage == Stages.rebuild_lookout then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_build_watchtower.marker", true )
    end
end

function RebuildWatchtowerQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_build_watchtower.marker", false )
end

function RebuildWatchtowerQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function RebuildWatchtowerQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end
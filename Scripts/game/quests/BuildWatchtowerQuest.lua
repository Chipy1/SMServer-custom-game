dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua"

BuildWatchtowerQuest = class()
BuildWatchtowerQuest.isSaveObject = true

local Stages = {
	talk_with_farmer = 1,
	listen_tower = 2,
	build_tower = 3,
	return_to_farmer = 4,
	listen_end = 5,
}

function BuildWatchtowerQuest.server_onCreate( self )

	QuestManager.Sv_SubscribeEvent( "event.quest_build_watchtower.update", self.scriptableObject, "sv_e_onBuilderGuideUpdate" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.FarmerTalk, self.scriptableObject, "sv_e_onTalkToFarmer" )
	QuestManager.Sv_SubscribeEvent( "infoPanel", self.scriptableObject, "sv_e_onInfoPanel" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )




	
	-- ensure that hubert will move off the platform in his hideout track.
	QuestActorManager.Sv_NotifyActor( "Hubert", "notify.encounter_done" )
	QuestActorManager.Sv_NotifyActor( "Hubert", "notify.ruins_cleared" )

	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.stage = Stages.talk_with_farmer
		self.sv.saved.pingPanel = true
	end
	self.sv.previousInteraction = nil
	self:sv_saveAndSync()
end

function BuildWatchtowerQuest.sv_setNpcInteractionData( self )
	if self.sv.previousInteraction == self.sv.saved.stage then
		return
	end
	if self.sv.saved.stage == Stages.talk_with_farmer or self.sv.saved.stage == Stages.return_to_farmer then
		QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = true } )
	else
		QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = false } )
	end
	self.sv.previousInteraction = self.sv.saved.stage
end















function BuildWatchtowerQuest.sv_saveAndSync( self )
	self:sv_setNpcInteractionData()
	self.storage:save( self.sv.saved )
	self.network:setClientData( { stage = self.sv.saved.stage, pingPanel = self.sv.saved.pingPanel } )
end

function BuildWatchtowerQuest.sv_e_onBuilderGuideUpdate( self, data )
	if data.params.isComplete then
		QuestManager.Sv_SendEvent( "event.quest_build_watchtower.build_complete", data )
		self.sv.saved.stage = Stages.return_to_farmer
		self:sv_saveAndSync()
	end
end

function BuildWatchtowerQuest.sv_e_onInfoPanel( self )
	self.sv.saved.pingPanel = false
	self:sv_saveAndSync()
end

function BuildWatchtowerQuest.sv_e_onTalkToFarmer( self, data )
	if self.sv.saved.stage == Stages.talk_with_farmer then
		self.sv.saved.stage = Stages.listen_tower
		DialogManager.Sv_PlayDialogBeat( "hubert_meet_at_watchtower", self.scriptableObject )
	elseif self.sv.saved.stage == Stages.return_to_farmer then
		self.sv.saved.stage = Stages.listen_end
		DialogManager.Sv_PlayDialogBeat( "hubert_watchtower_complete", self.scriptableObject )
	end
	self:sv_saveAndSync()
end

function BuildWatchtowerQuest.sv_finishQuest( self )
	QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
	CompleteQuest( "quest_build_watchtower" )
end

function BuildWatchtowerQuest.sv_e_onDialogCompleted( self, data )
	if data.params.uuid ~= dialog_build_watchtower_quest then
		return
	end
	if self.sv.saved.stage == Stages.listen_tower then
		self.sv.saved.stage = Stages.build_tower
	else
		if self.sv.saved.stage == Stages.listen_end then
			self:sv_finishQuest()
		end
	end
	self:sv_saveAndSync()
end

-- Client

function BuildWatchtowerQuest.client_onCreate( self )
	self.cl = {}
	self.cl.pingPanel = true
	self.cl.panelPinged = false
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.guideActive = false
	self.scriptableObject.clientPublicData.trackerData = {
		{
			name = "none", text = "no text"
		}
	}

	QuestManager.Cl_OnQuestCreated( "quest_build_watchtower" )
end

function BuildWatchtowerQuest.client_onDestroy( self )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_hubert_tower" )
    self:cl_e_onUntracked()
end

function BuildWatchtowerQuest.client_onClientDataUpdate( self, data )
	local prevStage = self.cl.stage
	self.cl.pingPanel = data.pingPanel
	self.cl.stage = data.stage
	self:cl_updateProgress( prevStage )
end

function BuildWatchtowerQuest.cl_updateProgress( self, prevStage )
	local trackingData = self.data.trackingSteps
    trackingData.talk1.complete = self.cl.stage > Stages.talk_with_farmer
	trackingData.build.complete = self.cl.stage > Stages.build_tower
	trackingData.talk2.complete = self.cl.stage > Stages.return_to_farmer
	
	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )
	if self.cl.stage == Stages.build_tower then
		self.scriptableObject.clientPublicData.guideActive = true
		self.scriptableObject.clientPublicData.blueprintPath = "$SURVIVAL_DATA/BuilderGuides/bq_watchtower_01_guide.json"
	else
		self.scriptableObject.clientPublicData.blueprintPath = nil
		self.scriptableObject.clientPublicData.guideActive = false
	end
	
	self:cl_updateMarkers()
	QuestManager.Cl_UpdateQuestTracker()
end

function BuildWatchtowerQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end
	self:cl_hideMarkers()
	if self.cl.stage == Stages.build_tower then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_build_watchtower.marker", true )
	elseif self.cl.stage == Stages.return_to_farmer or self.cl.stage == Stages.talk_with_farmer then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", true )
	end

	if self.cl.stage >= Stages.build_tower then
		if self.cl.pingPanel and not self.cl.panelPinged then
			self.cl.panelPinged = true
			QuestEntityManager.Cl_ActivateEventPing( "ping_hubert_tower" )
		elseif not self.cl.pingPanel then
			QuestEntityManager.Cl_DeactivateEventPing( "ping_hubert_tower" )
	
		end
	end
end

function BuildWatchtowerQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_build_watchtower.marker", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", false )
end

function BuildWatchtowerQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function BuildWatchtowerQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end
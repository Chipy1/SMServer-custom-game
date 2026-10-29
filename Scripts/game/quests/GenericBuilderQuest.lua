dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

GenericBuilderQuest = class()
GenericBuilderQuest.isSaveObject = true

GenericBuilderQuest.Stages = {
	build_thing = 1,
	talk_to_person = 2,
	wait_for_rewards = 3
}
local Stages = GenericBuilderQuest.Stages

GenericBuilderQuest.ScrapperQuestNames = {
	"quest_build_bigfan",
	"quest_build_carousel",
	"quest_build_catapult",
	"quest_build_musicbox",
	"quest_build_sawbladearm",
	"quest_build_steelbridge"
}

GenericBuilderQuest.ScrapperQuestRewards = {
	"465ef85e-47be-472e-aa72-25b4c870d305",
	"236aeca5-d247-45d0-9f52-8a8d68f80f4f",
	"5eb99d5e-eae5-43a9-aec2-443ed3609cc6",
	"61a50e7c-c454-4b0c-b32c-b322eb3f6ab1",
	"2a3fc190-3fff-4099-acd3-3db1d9d1e813",
	"5476b4ca-d9b4-4667-9113-f5892e552c16"
}

function GenericBuilderQuest.sv_getScrapperCompletion( self )
	local count = 0
	for _, scrapperQuestName in ipairs( GenericBuilderQuest.ScrapperQuestNames ) do
		if QuestManager.Sv_IsQuestComplete( scrapperQuestName ) then
			count = count + 1
		end
	end
	return count
end

function GenericBuilderQuest.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.stage = Stages.build_thing
		self.sv.saved.name = self.params.name
		self.sv.saved.blueprintPath = self.params.additionalParams.path

		self.network:setClientData( self.sv.saved.name, 2 )
		
		-- when quest starts disable waypoint effect
		local tsk = TileStorageManager.Sv_GetTileStorageKeyFromPosition( self.params.additionalParams.world, self.params.additionalParams.pos )
		SetTileStorageFlag( tsk, "quest.builderqueststart" )
		EffectManager.Sv_UpdateTagFilteredEffectsForTile( self.params.additionalParams.world, self.params.additionalParams.pos, { "quest.builderqueststart" }  )
	end
	QuestManager.Sv_SubscribeEvent( "event."..self.sv.saved.name..".update", self.scriptableObject, "sv_e_onBuilderGuideUpdate" )
	QuestManager.Sv_SubscribeEvent( "generic.builder.talk."..self.sv.saved.name, self.scriptableObject, "sv_e_onTalk" )
	QuestManager.Sv_SubscribeEvent( "generic.builder.finish."..self.sv.saved.name, self.scriptableObject, "sv_e_finishQuest" )

	Sv_SetPublicDataStage( self, self.sv.saved.stage )

	self:sv_saveAndSync()
	self.network:setClientData( self.sv.saved.blueprintPath, 3 )
end

function GenericBuilderQuest.sv_saveAndSync( self )
	self.storage:save( self.sv.saved )
	self.network:setClientData( { stage = self.sv.saved.stage } )
end

function GenericBuilderQuest.sv_e_onTalk( self, data )
	if self.sv.saved.stage == Stages.talk_to_person then
		self.sv.saved.stage = Stages.wait_for_rewards
		Sv_SetPublicDataStage( self, self.sv.saved.stage )
	end
	self:sv_saveAndSync()
end

function GenericBuilderQuest.sv_e_onBuilderGuideUpdate( self, data )
	if data.params.isComplete then
		self.sv.saved.stage = Stages.talk_to_person
		Sv_SetPublicDataStage( self, self.sv.saved.stage )
		self:sv_saveAndSync()
	end
end

function GenericBuilderQuest.sv_e_finishQuest( self, params )
	CompleteQuest( self.sv.saved.name )

	if SafeNestedAccess( params, "params", "isScrapper" ) then
		local completionCount = self:sv_getScrapperCompletion()
		sm.event.sendToGame( "sv_e_grantAdditionalRewards", { { type = "additionalReward", uuid = GenericBuilderQuest.ScrapperQuestRewards[completionCount] } } )
	end
end

function GenericBuilderQuest.client_onCreate( self )
	self.cl = {}
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.guideActive = false
end

function GenericBuilderQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function GenericBuilderQuest.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.stage = data.stage
		self.scriptableObject.clientPublicData.completedData = {}
		for i = 1, self.cl.stage - 1 do
			self.scriptableObject.clientPublicData.completedData[#self.scriptableObject.clientPublicData.completedData+1] = Cl_GetProgressText( i, self.data.progressSteps )
		end
		if self.cl.stage == Stages.build_thing then
			self.scriptableObject.clientPublicData.guideActive = true
		else
			self.scriptableObject.clientPublicData.guideActive = false
		end
	elseif channel == 2 then
		QuestManager.Cl_OnQuestCreated( data )
	elseif channel == 3 then
		self.cl.blueprintPath = data
		if self.cl.blueprintPath then
			self.scriptableObject.clientPublicData.blueprintPath = self.cl.blueprintPath
		end
	end
	self:cl_updateProgress()
end

function GenericBuilderQuest.cl_updateProgress( self )
	self.scriptableObject.clientPublicData.progressString = Cl_GetProgressText( self.cl.stage, self.data.progressSteps )
	QuestManager.Cl_UpdateQuestTracker()
end

function GenericBuilderQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( self.data.nodeName, true )
end

function GenericBuilderQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( self.data.nodeName, false )
end

function GenericBuilderQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function GenericBuilderQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end
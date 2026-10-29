dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

LiftPlatformBuilderQuest = class()
LiftPlatformBuilderQuest.isSaveObject = true

LiftPlatformBuilderQuest.Stages = {
	place_lift = 1,
	build_thing = 2
}
local Stages = LiftPlatformBuilderQuest.Stages

function LiftPlatformBuilderQuest.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.stage = Stages.place_lift
		self.sv.saved.stageData = {}
		self.sv.saved.name = self.params.name
		self.sv.saved.blueprintPath = self.params.additionalParams.path
	
		self.network:setClientData( self.sv.saved.name, 2 )

		-- when quest starts disable waypoint effect
		local tsk = TileStorageManager.Sv_GetTileStorageKeyFromPosition( self.params.additionalParams.world, self.params.additionalParams.pos )
		SetTileStorageFlag( tsk, "quest.builderqueststart" )
		EffectManager.Sv_UpdateTagFilteredEffectsForTile( self.params.additionalParams.world, self.params.additionalParams.pos, { "quest.builderqueststart" }  )
	end
	
	QuestManager.Sv_SubscribeEvent( "event."..self.sv.saved.name..".update", self.scriptableObject, "sv_e_onBuilderGuideUpdate" )
	
	QuestManager.Sv_SubscribeEvent( "event."..self.sv.saved.name..".place_lift", self.scriptableObject, "sv_e_onLiftPlaced" )

	self.sv.tutorial = false
	if self.sv.saved.name == "quest_build_first_car" then
		self.sv.tutorial = true
	end

	Sv_SetPublicDataStage( self, self.sv.saved.stage )

	self:sv_saveAndSync()
	self.network:setClientData( self.sv.saved.blueprintPath, 3 )
end

function LiftPlatformBuilderQuest.sv_e_onLiftPlaced( self )
	self.sv.saved.stage = Stages.build_thing
	Sv_SetPublicDataStage( self, self.sv.saved.stage )
	self:sv_saveAndSync()
end

function LiftPlatformBuilderQuest.sv_saveAndSync( self )
	self.storage:save( self.sv.saved )
	self.network:setClientData( { stage = self.sv.saved.stage, stageData = self.sv.saved.stageData, tutorial = self.sv.tutorial } )
end

function LiftPlatformBuilderQuest.sv_e_onBuilderGuideUpdate( self, data )
	if self.sv.tutorial and not data.params.isComplete then
		self.sv.saved.stageData = {
				stageIndex = data.params.currentStageIndex,
				stageInfo = data.params.stageInfo
			}
	elseif data.params.isComplete then
		local builderGuideShape = data.params.interactable.shape
		local body = builderGuideShape.body
		local localPos = builderGuideShape.localPosition
		local bb = builderGuideShape.localRotation * builderGuideShape:getBoundingBox() * 4
		local pos = localPos + sm.vec3.min( bb, sm.vec3.zero() )
		local size = bb:abs()



		builderGuideShape:destroyShape() -- Destroy builderguide part
		body:createBlock( ITEMS.blk_scrapwood, size, pos ) -- Replace with wood blocks
		QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
		CompleteQuest( self.sv.saved.name )
	end

	self:sv_saveAndSync()
	Sv_SetPublicDataStage( self, self.sv.saved.stage )

end

function LiftPlatformBuilderQuest.client_onCreate( self )
	self.cl = {}
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.guideActive = false
end

function LiftPlatformBuilderQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function LiftPlatformBuilderQuest.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.stage = data.stage
		self.cl.tutorial = data.tutorial
		if self.cl.stage == Stages.build_thing then
			self.scriptableObject.clientPublicData.guideActive = true
		else
			self.scriptableObject.clientPublicData.guideActive = false
		end
		self:cl_updateProgress( data.stage, data.stageData )
	elseif channel == 2 then
		QuestManager.Cl_OnQuestCreated( data )
	elseif channel == 3 then
		self.cl.blueprintPath = data
		if self.cl.blueprintPath then
			self.scriptableObject.clientPublicData.blueprintPath = self.cl.blueprintPath
		end
	end
end

function LiftPlatformBuilderQuest.cl_updateProgress( self, stage, stageData )
	local text = Cl_GetProgressText( self.cl.stage, self.data.progressSteps )

	if self.cl.tutorial then
		if stage == Stages.build_thing and stageData and stageData.stageIndex then
			local index = stageData.stageIndex

			if index == 0 then
				text = string.format( sm.gui.translateLocalizationTags( "#{QUEST_SCRAPCAR_BUILD_00}" ), sm.gui.getKeyBinding( "NextCreateRotation" ) )
			elseif index == 1 then
				text = "#{QUEST_SCRAPCAR_BUILD_01}"
			elseif index == 2 then
				text = string.format( sm.gui.translateLocalizationTags( "#{QUEST_SCRAPCAR_BUILD_02}" ), sm.gui.getKeyBinding( "LiftUp" ), sm.gui.getKeyBinding( "LiftDown" ) )
			elseif index == 3 then
				text = "#{QUEST_SCRAPCAR_BUILD_03}"
			elseif index == 4 then
				text = "#{QUEST_SCRAPCAR_BUILD_04}"
			elseif index == 5 then
				text = "#{QUEST_SCRAPCAR_BUILD_05}"
			elseif index == 6 then
				text = "#{QUEST_SCRAPCAR_BUILD_06}"
			elseif index == 7 then
				if stageData.stageInfo.partsLeft > 0 then
					text = string.format( sm.gui.translateLocalizationTags( "#{QUEST_SCRAPCAR_BUILD_07A}" ), sm.gui.getKeyBinding( "NextCreateRotation" ) )
				else
					text = "#{QUEST_SCRAPCAR_BUILD_07B}"
				end
			elseif index == 8 then
				text = "#{QUEST_SCRAPCAR_BUILD_08}"
			end
		end
	end

	self.scriptableObject.clientPublicData.progressString = text
	QuestManager.Cl_UpdateQuestTracker()
end

function LiftPlatformBuilderQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( self.data.nodeName, true )
end

function LiftPlatformBuilderQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( self.data.nodeName, false )
end

function LiftPlatformBuilderQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function LiftPlatformBuilderQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end
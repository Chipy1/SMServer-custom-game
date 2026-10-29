dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

BuilderGuideQuest = class()
BuilderGuideQuest.isSaveObject = true

local Stages = {
	place_on_lift = 1,
	complete_builder_guide = 2,
	add_fuel = 3,
}

function BuilderGuideQuest.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.stage = Stages.place_on_lift
	end

	QuestManager.Sv_SubscribeEvent( QuestEvent.InventoryChanges, self.scriptableObject, "sv_e_onInventoryChanges" )
	QuestManager.Sv_SubscribeEvent( "event.quest_builder_guide.update", self.scriptableObject, "sv_e_onBuilderGuideUpdate" )

	self:sv_saveAndSync()
end

function BuilderGuideQuest.sv_updateClientData( self )
end

function BuilderGuideQuest.sv_saveAndSync( self )
	self.storage:save( self.sv.saved )
	self.network:setClientData( { stage = self.sv.saved.stage, stageData = self.sv.saved.stageData } )
end

function BuilderGuideQuest.sv_e_onInventoryChanges( self, data )
	if FindInventoryChange( data.params.changes, obj_consumable_gas ) < 0 then
		self:sv_checkForFuel()
	end
end

function BuilderGuideQuest.sv_e_onBuilderGuideUpdate( self, data )
	--print( "BUILDER GUIDE UPDATE:", data.params )
	local builderguideInteractable = sm.exists( data.params.interactable ) and data.params.interactable or nil

	if self.sv.saved.stage == Stages.place_on_lift then
		if builderguideInteractable and builderguideInteractable.body:isOnLift() and not builderguideInteractable.body:isOnVirtualLift() then
			self.sv.saved.stage = Stages.complete_builder_guide
			self.sv.saved.stageData = { stageIndex = data.params.currentStageIndex }
		end
	end

	if self.sv.saved.stage == Stages.complete_builder_guide then
		if builderguideInteractable and builderguideInteractable.body:isOnLift() and not builderguideInteractable.body:isOnVirtualLift() then
			if not data.params.isComplete then
				self.sv.saved.stageData = {
					stageIndex = data.params.currentStageIndex,
					stageInfo = data.params.stageInfo
			 	}
			else
				self.sv.saved.stage = Stages.add_fuel
				self.sv.saved.stageData = {}
				local shapes = builderguideInteractable.body:getShapes()
				for _, shape in ipairs( shapes ) do
					if shape.uuid == obj_scrap_gasengine then
						self.sv.saved.stageData.engine = shape.interactable
					end
				end
				self:sv_checkForFuel()
			end
		else
			self.sv.saved.stage = Stages.place_on_lift
			self.sv.saved.stageData = nil
		end
	end

	--TODO: Check remove lift stage

	self:sv_saveAndSync()
end

function BuilderGuideQuest.sv_checkForFuel( self )
	if self.sv.saved.stage == Stages.add_fuel then
		local container = self.sv.saved.stageData.engine:getContainer()
		local quantity = sm.container.totalQuantity( container, obj_consumable_gas )
		if quantity > 0 then
			--TODO: Remove lift stage
			self.sv.saved.stage = nil
			self.sv.saved.stageData = nil
			QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
			QuestManager.Sv_CompleteQuest( "quest_builder_guide" )
		end
	end
end

--------------------------------------------------------------------------------

function BuilderGuideQuest.client_onCreate( self )
	QuestManager.Cl_OnQuestCreated( "quest_builder_guide" )
	self.cl = {}
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.progressString = ""
end

function BuilderGuideQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function BuilderGuideQuest.client_onClientDataUpdate( self, data )
	self.cl.data = data --TODO: For refresh, DELETE
	self:cl_updateProgress( data.stage, data.stageData )
end

function BuilderGuideQuest.client_onRefresh( self )
	if self.cl.data then
		self:cl_updateProgress( self.cl.data.stage, self.cl.data.stageData )
	end
end

function BuilderGuideQuest.cl_updateProgress( self, stage, stageData )
	local text = ""--"Builder Guide (optional)\n"

	if stage == Stages.place_on_lift then
		text = text.."#{QUEST_SCRAPCAR_PLACE_ON_LIFT}";

	elseif stage == Stages.complete_builder_guide and stageData and stageData.stageIndex then
		local index = stageData.stageIndex
		--text = text.."Stage "..index.."\n";

		if index == 0 then
			text = text..string.format( sm.gui.translateLocalizationTags( "#{QUEST_SCRAPCAR_BUILD_00}" ), sm.gui.getKeyBinding( "NextCreateRotation" ) )
		elseif index == 1 then
			text = text.."#{QUEST_SCRAPCAR_BUILD_01}"
		elseif index == 2 then
			text = text..string.format( sm.gui.translateLocalizationTags( "#{QUEST_SCRAPCAR_BUILD_02}" ), sm.gui.getKeyBinding( "LiftUp" ), sm.gui.getKeyBinding( "LiftDown" ) )
		elseif index == 3 then
			text = text.."#{QUEST_SCRAPCAR_BUILD_03}"
		elseif index == 4 then
			text = text.."#{QUEST_SCRAPCAR_BUILD_04}"
		elseif index == 5 then
			text = text.."#{QUEST_SCRAPCAR_BUILD_05}"
		elseif index == 6 then
			text = text.."#{QUEST_SCRAPCAR_BUILD_06}"
		elseif index == 7 then
			if stageData.stageInfo.partsLeft > 0 then
				text = text..string.format( sm.gui.translateLocalizationTags( "#{QUEST_SCRAPCAR_BUILD_07A}" ), sm.gui.getKeyBinding( "NextCreateRotation" ) )
			else
				text = "#{QUEST_SCRAPCAR_BUILD_07B}"
			end
		elseif index == 8 then
			text = text.."#{QUEST_SCRAPCAR_BUILD_08}"
		end
		
	elseif stage == Stages.add_fuel then
		text = text.."#{QUEST_SCRAPCAR_ADD_FUEL}"
	end

	self.scriptableObject.clientPublicData.progressString = text;
	QuestManager.Cl_UpdateQuestTracker()
end

function BuilderGuideQuest.cl_showMarkers( self )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_build_car.marker", true )
end

function BuilderGuideQuest.cl_hideMarkers( self )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_build_car.marker", false )
end

function BuilderGuideQuest.cl_e_onTracked( self )
	self:cl_showMarkers()
end

function BuilderGuideQuest.cl_e_onUntracked( self )
	self:cl_hideMarkers()
end 
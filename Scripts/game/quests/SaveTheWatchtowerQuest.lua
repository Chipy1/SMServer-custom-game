dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

SaveTheWatchtowerQuest = class()
SaveTheWatchtowerQuest.isSaveObject = true

local WaitTickTime = 40
local FinishEvent = "event.quest_save_watchtower.finish"
local Stages = {
    return_to_hideout = 1,
    grab_extinguisher = 2,
    put_out_fire = 3,
    wait_for_effect = 4
}

local FireNames = { "quest_save_lookout.fire01", "quest_save_lookout.fire02" }

local HideoutNearTrigger = "hideout_near_area.trigger"

local ReactivatePlatformMessage = { event = "NEXT", nextBuilderGuidePlatform = "$SURVIVAL_DATA/LocalBlueprints/BuilderQuest/BuilderQuest_Platform_Watchtower_02.blueprint" }
local FireCheckTickInterval = 20

function SaveTheWatchtowerQuest.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.return_to_hideout
        self.sv.saved.dousedFires = {}
        self.sv.saved.hasCalledDestroy = false
        self.sv.saved.hasDynamicFires = true

        local node = QuestEntityManager.Sv_GetNamedCellQuestNode( "watchtower_platform" )
        if node then
            local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( node.world, node.position )
            local value = TileStorageManager.Sv_GetValue( tileStorageKey, BUILDERGUIDE_PLATFORM_TABLE )
            if value and value.platform and sm.exists( value.platform ) then
                sm.event.sendToInteractable( value.platform, "sv_e_onQuestEvent", ReactivatePlatformMessage )
                self.sv.saved.hasCalledDestroy = true
            end
        end
    end
    self.sv.tickCounter = 0
    self.sv.done = false
    self.sv.previousInteraction = nil
    self.sv.overworld = WorldManager.Sv_GetWorld( "overworld" )
    self.sv.firePosition = QuestEntityManager.Sv_GetQuestMarkerPosition( "quest_shared_farmer.marker" )
    self.sv.tickCounter = 0
    if self.sv.saved.stage == Stages.return_to_hideout then
        sm.event.sendToWorld( self.sv.overworld, "sv_e_activateFires", FireNames )
        NodeSpawnManager.Sv_ActivateSpawnTrigger( "quest_save_watchtower_debris", self.sv.overworld )
    end

    if not self.sv.firePosition then
        sm.message.subscribe( MESSAGE_TYPES.QUEST.TerrainLoaded, "sv_m_questEntityTerrainLoaded" )
    end
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( HideoutNearTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.FireDoused, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.FarmerTalk, self.scriptableObject, "sv_e_onTalkToFarmer" )
    -- Delayed finish: fired by FinishQuestAfterDelay once the final checkmark has had time to show.
    QuestManager.Sv_SubscribeEvent( FinishEvent, self.scriptableObject, "sv_finishQuest" )




    self:sv_saveAndSync()
end

function SaveTheWatchtowerQuest.sv_m_questEntityTerrainLoaded( self, world )
    if world == WorldManager.Sv_GetWorld( "overworld" ) then
        self.sv.firePosition = QuestEntityManager.Sv_GetQuestMarkerPosition( "quest_shared_farmer.marker" )
    end
end

function SaveTheWatchtowerQuest.server_onFixedUpdate( self )
    local overworld = WorldManager.Sv_GetWorld( "overworld" )
    if not self.sv.saved.hasCalledDestroy and overworld then
        if overworld:isCellLoadedServer( -16, -16 ) then
            local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromCell( overworld, -16, -16 )
            local value = TileStorageManager.Sv_GetValue( tileKey, BUILDERGUIDE_PLATFORM_TABLE )
            if value and value.questName and value.questName == "quest_build_watchtower" then
                sm.event.sendToInteractable( value.platform, "sv_e_onQuestEvent", ReactivatePlatformMessage )
                self.sv.saved.hasCalledDestroy = true
                self:sv_saveAndSync()
            end
        end
    end

    if self.sv.saved.stage == Stages.put_out_fire and self.sv.saved.hasDynamicFires then
        self.sv.tickCounter = self.sv.tickCounter + 1
        if self.sv.tickCounter >= FireCheckTickInterval then
            self.sv.tickCounter = 0
            if self.sv.firePosition then
                local x = math.floor( self.sv.firePosition.x / 64 )
                local y = math.floor( self.sv.firePosition.y / 64 )
                if self.sv.overworld:isCellLoadedServer( x, y ) then
                    if not sm.fire.isAreaBurning( self.sv.firePosition, 50, self.sv.overworld ) then
                        self.sv.saved.dousedFires = self:sv_getDousedFires()
                        if #self.sv.saved.dousedFires == #FireNames then
                            self.sv.saved.hasDynamicFires = false
                            self.sv.saved.stage = Stages.wait_for_effect
                            FinishQuestAfterDelay( FinishEvent, WaitTickTime )
                        end
                        self:sv_saveAndSync()
                    end
                end
            end
        end
    end
end

function SaveTheWatchtowerQuest.sv_setNpcInteractionData( self )
    if self.sv.previousInteraction == self.sv.saved.stage then
        return
    end
    if self.sv.saved.stage == Stages.grab_extinguisher then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { animation = "emote_give_in", canInteract = true, item = obj_consumable_extinguisher } )
    elseif self.sv.saved.stage == Stages.put_out_fire then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { animation = "emote_give_out", canInteract = false } )
    else
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = false } )
    end
    self.sv.previousInteraction = self.sv.saved.stage
end















function SaveTheWatchtowerQuest.sv_saveAndSync( self )
    self:sv_setNpcInteractionData()
    self.storage:save( self.sv.saved )
    self.network:setClientData( { stage = self.sv.saved.stage } )
end

function SaveTheWatchtowerQuest.sv_getDousedFires( self )
	local dousedFires = {}
	for _, name in ipairs( FireNames ) do
		if g_dousedNamedFires[name] then
			dousedFires[#dousedFires + 1] = name
		end
	end
	return dousedFires
end

function SaveTheWatchtowerQuest.sv_e_onQuestEvent( self, data )
    if self.sv.saved.stage == Stages.return_to_hideout and data and data.event == HideoutNearTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
        self.sv.saved.stage = Stages.grab_extinguisher
        DialogManager.Sv_PlayDialogBeat( "hubert_help_fire", self.scriptableObject )
    elseif self.sv.saved.stage == Stages.put_out_fire then
        if data and data.event == QuestEvent.FireDoused then
            if not sm.fire.isAreaBurning( self.sv.firePosition, 50, self.sv.overworld ) then
                self.sv.saved.dousedFires = self:sv_getDousedFires()
                if #self.sv.saved.dousedFires == #FireNames and not self.sv.saved.hasDynamicFires then
                    self.sv.saved.stage = Stages.wait_for_effect
                end
            end
        end
    end
    self:sv_saveAndSync()
end

function SaveTheWatchtowerQuest.sv_e_onTalkToFarmer( self, data )
    if self.sv.saved.stage == Stages.grab_extinguisher then
        local player = SafeNestedAccess( data, "params", "player" )
        if not player then
            return
        end
        local inventory = player:getInventory()
        if not inventory then
            return
        end
        sm.container.beginTransaction()
        sm.container.collect( inventory, obj_consumable_extinguisher, 50, true )
        if sm.container.endTransaction() then
            self.sv.saved.stage = Stages.put_out_fire
        end
    end
    self:sv_saveAndSync()
end

function SaveTheWatchtowerQuest.sv_finishQuest( self )
    if not self.sv.done then
        self.sv.done = true
        QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
    
        CompleteAndActivateQuestThroughDialogBeat( "quest_save_watchtower", "quest_rebuild_watchtower", "hubert_rebuild_watchtower_start" )
    end
end

-- Client

function SaveTheWatchtowerQuest.client_onCreate( self )
    self.cl = {}
    self.cl.stage = Stages.return_to_hideout
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.progressString = ""

    self:cl_updateMarkers()
    QuestManager.Cl_OnQuestCreated( "quest_save_watchtower" )
    QuestManager.Cl_UpdateQuestTracker()
end

function SaveTheWatchtowerQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function SaveTheWatchtowerQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    if self.cl.stage ~= data.stage then
        self.cl.stage = data.stage
    end

    self:cl_updateProgress( prevStage )
end

function SaveTheWatchtowerQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end

    self:cl_hideMarkers()

    if self.cl.stage == Stages.return_to_hideout or self.cl.stage == Stages.put_out_fire then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", true )
    end
end

function SaveTheWatchtowerQuest.cl_updateProgress( self, prevStage )
    local trackingData = self.data.trackingSteps
    trackingData.return_to_hideout.complete = self.cl.stage > Stages.return_to_hideout
    trackingData.extinguish.complete = self.cl.stage > Stages.grab_extinguisher
    trackingData.fires.complete = self.cl.stage > Stages.put_out_fire

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

    self:cl_updateMarkers()
    QuestManager.Cl_UpdateQuestTracker()
end

function SaveTheWatchtowerQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_build_watchtower.marker", false )
end

function SaveTheWatchtowerQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function SaveTheWatchtowerQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end 
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua"

MysteriousCallerQuest = class()
MysteriousCallerQuest.isSaveObject = true

local Stages = {
	go_to_hideout = 1,
	save_farmer = 2,
    approach_the_farmer = 3,
    listen_to_conversation = 4,
    reach_ruins = 5,
    clear_out_enemies = 6,
    wait_for_effects = 7
}

local WaitTickTime = 40
local FinishEvent = "event.quest_mysterious_caller.finish"

local HideoutFarAreaTrigger = "hideout_far_area.trigger"
local HideoutNearAreaTrigger = "hideout_near_area.trigger"
local HideoutApproachFarmerTrigger = "hideout_approach_farmer.trigger"
local ClearRuinsTrigger = "quest_clear_ruins.trigger"

function MysteriousCallerQuest.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.stage = Stages.go_to_hideout
        self.sv.saved.defeatedEnemies = 0
        self.sv.saved.waveReacted = false
        self.sv.saved.firstDialogueDone = false
	end
	QuestManager.Sv_SubscribePlayerEnterAreaTrigger( HideoutFarAreaTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribePlayerEnterAreaTrigger( HideoutNearAreaTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribePlayerEnterAreaTrigger( HideoutApproachFarmerTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribePlayerEnterAreaTrigger( ClearRuinsTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )
    QuestManager.Sv_SubscribeEvent( FinishEvent, self.scriptableObject, "sv_e_onFinishQuest" )




    
    self:sv_saveAndSync()
end

function MysteriousCallerQuest.sv_startEncounter( self )
    NodeSpawnManager.Sv_ActivateSpawnTrigger( "spawnFarmer", WorldManager.Sv_GetWorld( "overworld" ) )
    QuestActorManager.Sv_BeginActorTrack( "hubert.actortrack", "Hubert" )
    local spawnNode = QuestEntityManager.Sv_GetEventNodes( "farmerRubble" )
    local combatParams = {
        name = "saveFarmerEncounter",
        position = spawnNode[1].position,
        world = WorldManager.Sv_GetWorld( "overworld" ),
        preset = "ce_savefarmer",
        subscriber = self.scriptableObject,
        finishFunction = "sv_e_encounterDone",
        newWaveFunction = "sv_e_encounterWave",
        enemyDefeatedFunction = "sv_e_enemyDefeated",
    }
    CombatEncounterManager.Sv_StartEncounter( combatParams )
    self.sv.saved.stage = Stages.save_farmer
    QuestEntityManager.Sv_BumpNamedAreaTrigger( HideoutNearAreaTrigger )
end






















function MysteriousCallerQuest.sv_saveAndSync( self )
	self.storage:save( self.sv.saved )
	self.network:setClientData( { stage = self.sv.saved.stage, defeatedEnemies = self.sv.saved.defeatedEnemies } )
end



function MysteriousCallerQuest.sv_e_onQuestEvent( self, data )
    if self.sv.saved.stage == Stages.go_to_hideout then
        if data.event == HideoutFarAreaTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self:sv_startEncounter()
        end
    elseif self.sv.saved.stage == Stages.save_farmer and not self.sv.saved.firstDialogueDone then
        if data.event == HideoutNearAreaTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.firstDialogueDone = true
            DialogManager.Sv_PlayDialogBeat( "mysterious_caller_first_encounter", self.scriptableObject )
        end
    elseif self.sv.saved.stage == Stages.approach_the_farmer then
        if data.event == HideoutApproachFarmerTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            QuestActorManager.Sv_NotifyActor( "Hubert", "notify.encounter_done" )
            DialogManager.Sv_PlayDialogBeat( "hubert_post_fight_introduction", self.scriptableObject )
            self.sv.saved.stage = Stages.listen_to_conversation
        end
    elseif self.sv.saved.stage == Stages.reach_ruins then
        if data.event == ClearRuinsTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.stage = Stages.clear_out_enemies
            if not self.sv.saved.encounterStarted then
                NodeSpawnManager.Sv_ActivateSpawnTrigger( "event.clearRuin", WorldManager.Sv_GetWorld( "overworld" ) )
                local node = QuestEntityManager.Sv_GetNamedAreaTrigger( ClearRuinsTrigger )
                if node then
                    local combatParams = {
                        name = "event.quest_clear_ruins.defeat_unit",
                        position = node.areaTrigger:getWorldPosition(),
                        world = WorldManager.Sv_GetWorld( "overworld" ),
                        subscriber = self.scriptableObject,
                        finishFunction = "sv_e_ruinsCleared",
                        targetCount = 1
                    }
                    CombatEncounterManager.Sv_StartNonSpawningEncounter( combatParams )
                    self.sv.saved.encounterStarted = true
                end
            end
        end
    end
    self:sv_saveAndSync()
end

function MysteriousCallerQuest.sv_e_ruinsCleared( self )
    QuestActorManager.Sv_NotifyActor( "Hubert", "notify.ruins_cleared" ) -- farmer should now teleport to his new position, now or next time he's seen.
    local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromCell( WorldManager.Sv_GetWorld( "overworld" ), -16, -16 )
    SetTileStorageFlag( tileKey, "quest.hideout.rubble" )

    -- if the tile is loaded, force reload to remove the rubble.
    sm.event.sendToGame( "sv_reloadTile", { pos = sm.vec3.new( -16, -16, 0 ) * 64, world = WorldManager.Sv_GetWorld( "overworld" ) } )
    EffectManager.Sv_UpdateTagFilteredEffectsForTile( WorldManager.Sv_GetWorld( "overworld" ), sm.vec3.new( -16, -16, 0 ) * 64, { "quest.hideout.rubble"} )

    self.sv.saved.stage = Stages.wait_for_effects
    FinishQuestAfterDelay( FinishEvent, WaitTickTime )
    self:sv_saveAndSync()
end

function MysteriousCallerQuest.sv_e_enemyDefeated( self )
    self.sv.saved.defeatedEnemies = self.sv.saved.defeatedEnemies + 1
    if self.sv.saved.defeatedEnemies == 1 then
        DialogManager.Sv_PlayDialogBeat( "mysterious_caller_combat_quip_1", self.scriptableObject )
    elseif self.sv.saved.defeatedEnemies == 2 then
        DialogManager.Sv_PlayDialogBeat( "mysterious_caller_combat_quip_2", self.scriptableObject )
    end
    self:sv_saveAndSync()
end

function MysteriousCallerQuest.sv_e_encounterDone( self )
    self.sv.saved.stage = Stages.approach_the_farmer
    if QuestEntityManager.Sv_NamedAreaTriggerContainsPlayer( HideoutApproachFarmerTrigger ) then
        QuestActorManager.Sv_NotifyActor( "Hubert", "notify.encounter_done" )
        DialogManager.Sv_PlayDialogBeat( "hubert_post_fight_introduction", self.scriptableObject )
        self.sv.saved.stage = Stages.listen_to_conversation
    end
    self:sv_saveAndSync()
end

function MysteriousCallerQuest.sv_e_encounterWave( self )
    if not self.sv.saved.waveReacted then
        self.sv.saved.waveReacted = true
        self:sv_saveAndSync()
    end
end

function MysteriousCallerQuest.sv_e_onFinishQuest( self )
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
    NodeSpawnManager.Sv_DeactivateSpawnTrigger( "spawnFarmer" )
    CompleteAndActivateQuestThroughDialogBeat( "quest_mystery_call", "quest_feed_the_farmers", "clear_ruins_complete_start_feed_farmers" )
end

function MysteriousCallerQuest.sv_e_onDialogCompleted( self, data )
    if self.sv.saved.stage == Stages.listen_to_conversation and IsDialogBeat( data.params.uuid, data.params.entryName, "hubert_post_fight_introduction" ) then
        self.sv.saved.stage = Stages.reach_ruins
        QuestEntityManager.Sv_BumpNamedAreaTrigger( ClearRuinsTrigger )
        self:sv_saveAndSync()
    end
end

function MysteriousCallerQuest.client_onCreate( self )
    self.cl = {}
    self.cl.stage = Stages.go_to_hideout
    self.cl.defeatedEnemies = 0

    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.progressString = ""
    self:cl_updateMarkers()
    QuestManager.Cl_OnQuestCreated( "quest_mystery_call" )
    QuestManager.Cl_UpdateQuestTracker()
end

function MysteriousCallerQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function MysteriousCallerQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end
    self:cl_hideMarkers()
    if self.cl.stage == Stages.go_to_hideout or self.cl.stage == Stages.save_farmer or self.cl.stage == Stages.approach_the_farmer then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_mystery_call.marker", true )
    elseif self.cl.stage == Stages.reach_ruins or self.cl.stage == Stages.clear_out_enemies then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_ruins.marker", true )
    end
end

function MysteriousCallerQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_mystery_call.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_ruins.marker", false )
end

function MysteriousCallerQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    if self.cl.stage ~= data.stage then
        self.cl.stage = data.stage
        self:cl_updateMarkers()
    end
    self.cl.defeatedEnemies = data.defeatedEnemies
    self:cl_updateProgress( prevStage )
end

function MysteriousCallerQuest.cl_updateProgress( self, prevStage )
    local trackingData = self.data.trackingSteps

    trackingData.find.complete = self.cl.stage > Stages.go_to_hideout
    trackingData.defend.complete = self.cl.stage > Stages.save_farmer
    trackingData.approach.complete = self.cl.stage > Stages.approach_the_farmer
    trackingData.ruins.complete = self.cl.stage > Stages.reach_ruins
    trackingData.destroy.complete = self.cl.stage > Stages.clear_out_enemies

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

    QuestManager.Cl_UpdateQuestTracker()
end

function MysteriousCallerQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function MysteriousCallerQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end 
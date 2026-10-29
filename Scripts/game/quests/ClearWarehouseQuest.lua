dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

ClearWarehouseQuest = class()
ClearWarehouseQuest.isSaveObject = true

local CameraShakeBurstInterval = 40 * 30 --30 seconds
local Stages = {
    talk_to_hubert = 1,
    listen_to_farmer = 2,
    take_key = 3,
    find_the_warehouse = 4,
    enter_the_warehouse = 5,
    investigate = 6,
    reach_the_roof = 7,
    defeat_the_trashbot = 8
}

local FindWarehouseTrigger = "quest_clear_warehouse.find_warehouse"
local InvestigateTrigger = "quest_clear_warehouse.investigate"
local ReachRoofTrigger = "quest_clear_warehouse.reach_roof"

local function TriggerRoofCinematic( self, players )
	sm.game.pauseSaving( "Trashbot Spawn Cinematic 1", 40 * 30 )
    EffectManager.Sv_PlayNamedCinematic( { name = "cinematic.trashbot01", callbackData = { world = WorldManager.Sv_GetWorld( "overworld" ), players = players }, interruptible = false } )
    local namedAreaTrigger = QuestEntityManager.Sv_GetNamedAreaTrigger( ReachRoofTrigger )
    if namedAreaTrigger then
        local world = WorldManager.Sv_GetWorld( "overworld" )
        local triggerAreaPosition = namedAreaTrigger.areaTrigger:getWorldPosition()
        local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, triggerAreaPosition )
        SetRailPower( true, "ts:rail:warehouse", tileKey )
        SetTileStorageFlagAtPosition( world, triggerAreaPosition, "bossfight" )
        sm.event.sendToGame( "sv_reloadTile", { pos = triggerAreaPosition, world = world } )
    end
    self.sv.cinematicTriggered = true
end

function ClearWarehouseQuest.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.talk_to_hubert
    end
    self.sv.cinematicTriggered = false
    self.sv.previousInteraction = nil
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( FindWarehouseTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( InvestigateTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( ReachRoofTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_clear_warehouse.enter", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_clear_warehouse.defeat_trashbot", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_clear_warehouse.spawn_trashbot", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.FarmerTalk, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "warehouse_level_4_ping", self.scriptableObject, "sv_e_toggleElevatorPing" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )
    QuestManager.Sv_SubscribeEvent( "event.quest_clear_warehouse.bossfight_music", self.scriptableObject, "sv_e_setBossFightMusicFlag" )






    self:sv_saveAndSync()
end



















































































function ClearWarehouseQuest.sv_setNpcInteractionData( self )
    if self.sv.previousInteraction == self.sv.saved.stage then
        return
    end
    if self.sv.saved.stage == Stages.talk_to_hubert then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = true } )
    elseif self.sv.saved.stage == Stages.take_key then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { animation = "emote_give_in", canInteract = true, log = ITEMS.obj_survivalobject_keycard } )
    elseif self.sv.saved.stage == Stages.find_the_warehouse then
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { animation = "emote_give_out", canInteract = false } )
    else
        QuestManager.Sv_SetNpcInteractionData( QuestUnits.Hubert, { canInteract = false } )
    end
    self.sv.previousInteraction = self.sv.saved.stage
end

function ClearWarehouseQuest.sv_saveAndSync( self )
    self:sv_setNpcInteractionData()
    self.storage:save( self.sv.saved )
    self.network:setClientData( { stage = self.sv.saved.stage, hidePing = self.sv.saved.hidePing } )
end

function ClearWarehouseQuest.sv_e_onQuestEvent( self, data )











    if self.sv.saved.stage == Stages.talk_to_hubert then
        if data.event == QuestEvent.FarmerTalk then
            self.sv.saved.stage = Stages.listen_to_farmer
            DialogManager.Sv_PlayDialogBeat( "hubert_gives_warehouse_key", self.scriptableObject )
        end
    elseif self.sv.saved.stage == Stages.take_key then
        if data.event == QuestEvent.FarmerTalk then
            self.sv.saved.stage = Stages.find_the_warehouse
            LogEntryManager.Sv_AddLog( LOGS.log_warehouse_key )
            if QuestEntityManager.Sv_NamedAreaTriggerContainsPlayer( FindWarehouseTrigger ) then
                self.sv.saved.stage = Stages.enter_the_warehouse
            end
        end
    elseif self.sv.saved.stage == Stages.find_the_warehouse then
        if data.event == FindWarehouseTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.stage = Stages.enter_the_warehouse
        end
    elseif self.sv.saved.stage == Stages.investigate then
        if data.event == InvestigateTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.stage = Stages.reach_the_roof
        end
    elseif self.sv.saved.stage == Stages.enter_the_warehouse then
        if data.event == "event.quest_clear_warehouse.enter" then
            LogEntryManager.Sv_RemoveLog( LOGS.log_warehouse_key )
            self.sv.saved.stage = Stages.investigate
        end
    elseif self.sv.saved.stage == Stages.reach_the_roof and self.sv.cinematicTriggered == false then
        if data.event == ReachRoofTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            TriggerRoofCinematic( self )
        end
    elseif self.sv.saved.stage == Stages.reach_the_roof and data.event == "event.quest_clear_warehouse.spawn_trashbot" then
        self.sv.saved.stage = Stages.defeat_the_trashbot
        self.scriptableObject:setPublicData( { bossfight = true } )
    elseif self.sv.saved.stage == Stages.defeat_the_trashbot then
        if data.event == "event.quest_clear_warehouse.defeat_trashbot" then
            self:sv_finishQuest()
        end
    end
    
    self:sv_saveAndSync()
end

function ClearWarehouseQuest.sv_e_toggleElevatorPing( self )
    self.sv.saved.hidePing = true
    self:sv_saveAndSync()
end

function ClearWarehouseQuest.sv_e_onDialogCompleted( self, data )
    if data.params.uuid ~= dialog_clear_warehouse then
        return
    end
    if self.sv.saved.stage == Stages.listen_to_farmer then
        self.sv.saved.stage = Stages.take_key
    end
    self:sv_saveAndSync()
end

function ClearWarehouseQuest.sv_finishQuest( self )
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
    QuestManager.Sv_CompleteQuest( "quest_clear_warehouse" )
    QuestManager.Sv_ActivateQuest( "quest_warehouse_destruction", nil, true )
end

function ClearWarehouseQuest.server_onFixedUpdate( self )
    -- recovery for saves stuck by not having the log
    if self.sv.saved.stage > Stages.take_key and self.sv.saved.stage < Stages.investigate and not LogEntryManager.Sv_HasLog( LOGS.log_warehouse_key ) then
        LogEntryManager.Sv_AddLog( LOGS.log_warehouse_key )
    end
end

function ClearWarehouseQuest.client_onCreate( self )
    QuestManager.Cl_OnQuestCreated( "quest_clear_warehouse" )
    self.cl = {}
    self.cl.shakeTickCounter = 0
    self.cl.stage = Stages.find_the_warehouse
    self.cl.localPlayerInFight = false
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.progressString = ""
    QuestManager.Cl_OnQuestCreated( "quest_clear_warehouse" )
end

function ClearWarehouseQuest.client_onFixedUpdate( self )
    if self.cl.stage == Stages.reach_the_roof then
        local insideWarehouse = false
        local myPlayer = sm.localPlayer.getPlayer()
        local myCharacter = myPlayer and myPlayer.character or nil
        if myCharacter then
            if myPlayer.character:getWorld().id ~= 1 then
                insideWarehouse = true
            end
        end
        if insideWarehouse then
            if self.cl.fallingDustEffectBurst == nil and sm.exists( myCharacter ) then
                self.cl.fallingDustEffectBurst = sm.effect.createEffect( "Warehouse - Fallingsmoke_burst", myCharacter )
                self.cl.fallingDustEffectBurst:setOffsetPosition( sm.vec3.new( 0, 15, 0 ) )
                self.cl.fallingDustEffectBurst:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
                self.cl.fallingDustEffectBurst:start()
            elseif self.cl.fallingDustEffectBurst and sm.exists( self.cl.fallingDustEffectBurst ) then
                if self.cl.shakeTickCounter % CameraShakeBurstInterval == 0 then
                    self.cl.fallingDustEffectBurst:start()
                end
            end
            self.cl.shakeTickCounter = self.cl.shakeTickCounter + 1
            if self.cl.fallingDustEffectBurst and not sm.exists( self.cl.fallingDustEffectBurst ) then
                self.cl.fallingDustEffectBurst = nil
            end
        else
            if sm.exists( self.cl.fallingDustEffectBurst ) then
                if self.cl.fallingDustEffect and self.cl.fallingDustEffectBurst:isPlaying() then
                    self.cl.fallingDustEffectBurst:stop()
                end
            end
        end
    else
        if self.cl.fallingDustEffect and sm.exists( self.cl.fallingDustEffectBurst ) then
            self.cl.fallingDustEffectBurst:destroy()
            self.cl.fallingDustEffectBurst = nil
		end
    end
    if self.cl.stage == Stages.defeat_the_trashbot and self.cl.tracked then
        local myPlayer = sm.localPlayer.getPlayer()
        local myCharacter = myPlayer and myPlayer.character or nil
        if myCharacter then
            local isInFight = false
            local world = myPlayer.character:getWorld()
            if world.id == 1 then
                local trashbotNode = QuestEntityManager.Cl_GetNamedQuestMarker( "quest_clear_warehouse.trashbot_position" )
                if trashbotNode and ( trashbotNode.position - myCharacter.worldPosition ):length() < 100 then
                    isInFight = true
                end
            end
            if isInFight ~= self.cl.localPlayerInFight then
                self.cl.localPlayerInFight = isInFight
                if isInFight then
                    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_warehouse.ladder", false )
                else
                    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_warehouse.ladder", true )
                end
            end
        end
    end
end

function ClearWarehouseQuest.client_onDestroy( self )
    QuestEntityManager.Cl_DeactivateEventPing( "quest_clear_warehouse_elevator" )
    self:cl_e_onUntracked()
end

function ClearWarehouseQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    if self.cl.stage ~= data.stage then
        self.cl.stage = data.stage
    end
    self.cl.hidePing = data.hidePing

    self:cl_updateProgress( prevStage )
end

function ClearWarehouseQuest.cl_updateProgress( self, prevStage )
    local trackingData = self.data.trackingSteps
    trackingData.talk.complete = self.cl.stage > Stages.talk_to_hubert
    trackingData.key.complete = self.cl.stage > Stages.take_key
    trackingData.find.complete = self.cl.stage > Stages.find_the_warehouse
    trackingData.enter.complete = self.cl.stage > Stages.enter_the_warehouse
    trackingData.investigate.complete = self.cl.stage > Stages.investigate
    trackingData.roof.complete = self.cl.stage > Stages.reach_the_roof
    trackingData.defeat.complete = self.cl.stage > Stages.defeat_the_trashbot

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

    self:cl_updateMarkers()
    QuestManager.Cl_UpdateQuestTracker()
end

function ClearWarehouseQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end
    if self.cl.stage == Stages.talk_to_hubert then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", true )
    elseif self.cl.stage == Stages.find_the_warehouse  or self.cl.stage == Stages.enter_the_warehouse then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_warehouse.key_reader", true )
    elseif self.cl.stage == Stages.reach_the_roof then
        if not self.cl.hidePing then
            QuestEntityManager.Cl_ActivateEventPing( "quest_clear_warehouse_elevator" )
        else
            QuestEntityManager.Cl_DeactivateEventPing( "quest_clear_warehouse_elevator" )
        end
        local myPlayer = sm.localPlayer.getPlayer()
        if myPlayer and myPlayer.character then
            if myPlayer.character:getWorld().id == 1 then
                QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_warehouse.key_reader", true )
            else
                QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_warehouse.key_reader", false )
            end
        else
            QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_warehouse.key_reader", false )
        end
    else
        QuestEntityManager.Cl_DeactivateEventPing( "quest_clear_warehouse_elevator" )
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", false )
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_warehouse.key_reader", false )
    end
end

function ClearWarehouseQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_warehouse.key_reader", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_clear_warehouse.ladder", false )
end

function ClearWarehouseQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function ClearWarehouseQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end

function ClearWarehouseQuest.client_onLocalPlayerChangedWorld( self, world )
    self:cl_updateMarkers()
end

function ClearWarehouseQuest.sv_e_setBossFightMusicFlag( self )
    -- Tell the trashbot to enable its boss music radius monitor.
    -- Fired by the spawn cinematic right after players are teleported into the arena.
    sm.message.send( MESSAGE_TYPES.GENERAL.SetTrashbotBossMusic )
end
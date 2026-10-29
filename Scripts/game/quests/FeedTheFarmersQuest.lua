dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua"

FeedTheFarmersQuest = class()
FeedTheFarmersQuest.isSaveObject = true

local WaitTickTime = 40
local FinishEvent = "event.quest_feed_the_farmers.finish"
local Stages = {
    find_packing_station = 1,
    deposit_tomatoes = 2,
    use_packingstation = 3,
    deliver_crate = 4,
    use_trader = 5,
    wait_for_effect = 6
}

local TomatoTargetAmount = 20

local PackingStationTrigger = "quest_deliver_vegetables.trigger"

function FeedTheFarmersQuest.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.find_packing_station
        self.sv.saved.dialogStarted = false
    end
    self.sv.tomatoCount = 0

    QuestManager.Sv_SubscribeEvent( QuestEvent.PackingStationCreateCrate, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.PackingStationDeposit, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( PackingStationTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DeliverTraderCrate, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.TraderProgressTrade, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )
    -- Delayed finish: fired by FinishQuestAfterDelay once the final checkmark has had time to show.
    QuestManager.Sv_SubscribeEvent( FinishEvent, self.scriptableObject, "sv_finishQuest" )





    if self.sv.saved.stage == Stages.deposit_tomatoes then
        self:sv_checkProgressSkip()
    end

    self:sv_saveAndSync()
end

function FeedTheFarmersQuest.sv_checkProgressSkip( self )
    local hasCreatedCrate = PackingStationManager.Sv_GetPacksCreated() > 0
    local currentFillAmount = PackingStationManager.Sv_GetHighestLoad( tostring( ITEMS.obj_plantables_tomato ) )
    local traderInfo = sm.storage.load( STORAGE_CHANNEL_TRADER_INFORMATION ) or {}
    local traderInventory = traderInfo.currentItems or {}
    local tomatoCount = traderInventory[tostring( ITEMS.obj_crates_tomato )] or 0
    if tomatoCount > 0 then
        self.sv.saved.stage = Stages.use_trader
    elseif hasCreatedCrate then
        self.sv.saved.stage = Stages.deliver_crate
    elseif currentFillAmount > 0 then
        self.sv.saved.stage = Stages.deposit_tomatoes
    elseif currentFillAmount >= TomatoTargetAmount then
        self.sv.saved.stage = Stages.use_packingstation
    end
    self.sv.tomatoCount = currentFillAmount
end






















function FeedTheFarmersQuest.sv_saveAndSync( self )
    self.storage:save( self.sv.saved )
    self.network:setClientData( { stage = self.sv.saved.stage, tomatoCount = self.sv.tomatoCount, found = self.sv.saved.dialogStarted } )
end

function FeedTheFarmersQuest.sv_e_onQuestEvent( self, data )
    if self.sv.saved.stage == Stages.deposit_tomatoes then
        if data.event == QuestEvent.PackingStationDeposit then
            self:sv_checkProgressSkip()
            if self.sv.tomatoCount >= TomatoTargetAmount then
                self.sv.saved.stage = Stages.use_packingstation
            end
        end
    end
    if self.sv.saved.stage == Stages.find_packing_station then
        if data.event == PackingStationTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix and not self.sv.saved.dialogStarted then
            LogEntryManager.Sv_AddLog( LOGS.log_packingstation_vegetable )
            DialogManager.Sv_PlayDialogBeat( "hubert_thats_a_packing_station", self.scriptableObject )
            self.sv.saved.dialogStarted = true
        end
    end
    if self.sv.saved.stage <= Stages.use_packingstation then
        if data.event == QuestEvent.PackingStationCreateCrate then
            if data.params.shapeUuid == ITEMS.obj_crates_tomato then
                self.sv.saved.stage = Stages.deliver_crate
            end
        end
    end
    if self.sv.saved.stage <= Stages.deliver_crate then
        if data.event == QuestEvent.DeliverTraderCrate then
            if data.params.shapeUuid == ITEMS.obj_crates_tomato then
                self.sv.saved.stage = Stages.use_trader
            end
        end
    end
    if self.sv.saved.stage == Stages.use_trader then
        if data.event == QuestEvent.TraderProgressTrade then
            self.sv.saved.stage = Stages.wait_for_effect



            FinishQuestAfterDelay( FinishEvent, WaitTickTime )
        end
    end

    self:sv_saveAndSync()
end

function FeedTheFarmersQuest.sv_finishQuest( self )
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )



    local prerequisiteQuestEvent = QuestEvent.TraderLeaveArea

    CompleteAndActivateQuestThroughDialogBeat( "quest_feed_the_farmers", "quest_clear_minidungeon", "tomato_delivered_start_growlab", nil, { prerequisiteQuestEvent = prerequisiteQuestEvent } )
end

function FeedTheFarmersQuest.sv_e_onDialogCompleted( self, data )
    if data.params.uuid ~= dialog_feed_farmers_quest then
        return
    end
    if self.sv.saved.stage == Stages.find_packing_station then
        self.sv.saved.stage = Stages.deposit_tomatoes
        if self.sv.tomatoCount >= TomatoTargetAmount then
            self.sv.saved.stage = Stages.use_packingstation
        end
        self:sv_checkProgressSkip()
        self:sv_saveAndSync()
    end
end

function FeedTheFarmersQuest.client_onCreate( self )
    self.cl = {}
    self.cl.stage = Stages.find_packing_station
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.progressString = ""

    QuestManager.Cl_OnQuestCreated( "quest_feed_the_farmers" )
end

function FeedTheFarmersQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function FeedTheFarmersQuest.cl_e_explanation( self )
    self.network:sendToServer( "sv_n_explanation" )
end

function FeedTheFarmersQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end
    self:cl_hideMarkers()
    if self.cl.stage == Stages.find_packing_station or self.cl.stage == Stages.deposit_tomatoes or self.cl.stage == Stages.use_packingstation then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_deliver_vegetables.find_station_marker", true )
    elseif self.cl.stage == Stages.deliver_crate then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_deliver_vegetables.dropoff_marker", true )
        QuestEntityManager.Cl_ActivateEventPing( "ping_deposit_button" )
    elseif self.cl.stage == Stages.use_trader then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_trader.trader_location", true )
        QuestEntityManager.Cl_DeactivateEventPing( "ping_deposit_button" )
    end
end

function FeedTheFarmersQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_DeactivateEventPing( "ping_deposit_button" )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_deliver_vegetables.station_marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_deliver_vegetables.find_station_marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_deliver_vegetables.dropoff_marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_trader.trader_location", false )
end

function FeedTheFarmersQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    if self.cl.stage ~= data.stage and data.stage == Stages.deposit_tomatoes then
        sm.item.addTrackedItem( ITEMS.obj_plantables_tomato, sm.item.trackingType.mainQuest )
    elseif self.cl.stage ~= data.stage and data.stage == Stages.use_trader then
        sm.item.removeTrackedItem( ITEMS.obj_plantables_tomato, sm.item.trackingType.mainQuest )
    end

    if self.cl.stage ~= data.stage then
        self.cl.stage = data.stage
        self:cl_updateMarkers()
    end
    self.cl.tomatoCount = data.tomatoCount
    self.cl.found = data.found
    self:cl_updateProgress( prevStage )
end

function FeedTheFarmersQuest.cl_updateProgress( self, prevStage )
    local trackingData = self.data.trackingSteps

    trackingData.find.complete = self.cl.found
    trackingData.tomatoes.count1 = self.cl.tomatoCount
    trackingData.tomatoes.count2 = TomatoTargetAmount
    trackingData.deliver.complete = self.cl.stage > Stages.deliver_crate
    trackingData.trader.complete = self.cl.stage > Stages.use_trader

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )
	self.scriptableObject.clientPublicData.traderUnlocked = self.cl.stage >= Stages.use_trader

    QuestManager.Cl_UpdateQuestTracker()
end

function FeedTheFarmersQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function FeedTheFarmersQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end
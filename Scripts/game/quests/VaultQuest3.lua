dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ProgressionManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_logs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

VaultQuest3 = class()
VaultQuest3.isSaveObject = true

local QUEST_NAME = "quest_vault_3"
local WaitTickTime = 40
local FinishEvent = "event.quest_vault_3.finish"

local NextQuestDelay = 0 -- seconds

local Stages = {
    track_quota = 1,
    listen_axobot = 2,  -- Quota done: listen to Axobot's completion call before fetching the card.
    get_card = 3,
    wait_for_effect = 4,  -- Dummy final stage: lets the get_card checkmark show before the quest untracks.
}

local AxobotQuotaCompleteBeat = "axobot_quota_final_complete"

-- Access card ("vault quota key") handed over by the trader (Wonky/Axobot) once the quota is met.
local AccessCardLog = LOGS.log_accesscard_04
-- Trader quest marker shown while the player needs to return for the access card.
local TraderMarker = "quest_activate_mininghub.axobot"

-- Phae hints about the second station once the quota is at least half done AND the player has spent
-- some time exploring a drill world (drill1 or drill2), away from the elevator.
local UndergroundHintFraction = 0.5
-- Floor indices in UNDERGROUND_ELEVATORS["MAIN"].floors: drill1 = 5 (depth 4), drill2 = 7 (depth 6).
local Drill1FloorIndex = 5
local Drill2FloorIndex = 7
local Station2HintMinTicksInDrill = 40 * 30 -- must explore a drill world for ~30s before the hint can play
local Station2HintMinElevatorDistance = 3 * 64 -- and be at least this many meters from the elevator
local HintCheckIntervalTicks = WaitTickTime -- throttle the position check to once per second

-- Server

function VaultQuest3.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {
            stage = Stages.track_quota,
            phaeStation2HintPlayed = false,
            -- Per drill world (keyed by floor index): the elevator the player arrived from and when.
            -- Tracked independently so multiplayer players can be in drill1 and drill2 at once.
            -- drillWorlds[floor] = { world = <world>, pos = <vec3>, arrivalTick = <tick> }
            drillWorlds = {},
        }
        self.storage:save( self.sv.saved )
    end

    QuestManager.Sv_SubscribeEvent( QuestEvent.VaultTotalUpdated, self.scriptableObject, "sv_e_onVaultTotalUpdated" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )
    -- Player must collect the access card from the trader (Wonky) to finish the quest.
    QuestManager.Sv_SubscribeEvent( "axobot_card_taken", self.scriptableObject, "sv_e_onCardTaken" )
    -- Delayed finish: fired by FinishQuestAfterDelay once the get_card checkmark has had time to show.
    QuestManager.Sv_SubscribeEvent( FinishEvent, self.scriptableObject, "sv_finishQuest" )
    if not self.sv.saved.phaeStation2HintPlayed then
        QuestManager.Sv_SubscribeEvent( "underground_elevator_used", self.scriptableObject, "sv_e_onElevatorUsed" )
    end




    self:sv_updateQuestProgress( ProgressionManager.Sv_GetVaultTotal() )
end

function VaultQuest3.sv_e_onVaultTotalUpdated( self, data )
    self:sv_updateQuestProgress( data.params.total )
end

function VaultQuest3.sv_e_onElevatorUsed( self, data )
    if self.sv.saved.phaeStation2HintPlayed then
        return
    end
    -- Track each drill world (drill1 / drill2) the player rides into; the station-2 hint plays once a
    -- player has explored one away from its elevator. Each floor is tracked independently for multiplayer.
    local floor = data.params.floor
    if floor == Drill1FloorIndex or floor == Drill2FloorIndex then
        self.sv.saved.drillWorlds[floor] = {
            world = data.params.world,
            pos = data.params.position,
            arrivalTick = sm.game.getCurrentTick(),
        }
        self.storage:save( self.sv.saved )
    end
end

function VaultQuest3.server_onFixedUpdate( self )
    if self.sv.saved.phaeStation2HintPlayed or not next( self.sv.saved.drillWorlds ) then
        return
    end
    self.sv.hintCheckTick = ( self.sv.hintCheckTick or 0 ) + 1
    if self.sv.hintCheckTick < HintCheckIntervalTicks then
        return
    end
    self.sv.hintCheckTick = 0

    -- Require the quota to be at least half done.
    local step = self.data.trackingSteps.quota
    if ProgressionManager.Sv_GetVaultTotal() < step.threshold * UndergroundHintFraction then
        return
    end
    -- Require a player who has spent enough time in a tracked drill world AND wandered away from its elevator.
    if self:sv_anyPlayerFarFromDrillElevator() then
        self.sv.saved.phaeStation2HintPlayed = true
        self.storage:save( self.sv.saved )
        DialogManager.Sv_PlayDialogBeat( "phae_underground_station2_hint", self.scriptableObject )
    end
end

function VaultQuest3.sv_anyPlayerFarFromDrillElevator( self )
    local now = sm.game.getCurrentTick()
    local thresholdSq = Station2HintMinElevatorDistance * Station2HintMinElevatorDistance
    for _, drillWorld in pairs( self.sv.saved.drillWorlds ) do
        if drillWorld.world and sm.exists( drillWorld.world ) and drillWorld.pos
            and ( now - drillWorld.arrivalTick ) >= Station2HintMinTicksInDrill then
            for _, player in ipairs( sm.player.getAllPlayers() ) do
                local character = player:getCharacter()
                if character and sm.exists( character ) and character:getWorld() == drillWorld.world then
                    if ( character:getWorldPosition() - drillWorld.pos ):length2() >= thresholdSq then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function VaultQuest3.sv_updateQuestProgress( self, vaultTotal )
    local step = self.data.trackingSteps.quota
    if vaultTotal >= step.threshold and self.sv.saved.stage == Stages.track_quota then
        self.sv.saved.stage = Stages.listen_axobot
        self.storage:save( self.sv.saved )
        DialogManager.Sv_PlayDialogBeat( AxobotQuotaCompleteBeat, self.scriptableObject )
        QuestManager.Sv_SendEvent( QuestEvent.VaultQuotaReached )
    end

    self:sv_sync( vaultTotal )
end

function VaultQuest3.sv_e_onDialogCompleted( self, data )
    if IsDialogBeat( data.params.uuid, data.params.entryName, AxobotQuotaCompleteBeat ) then
        -- Quota dialog finished: now send the player back to the trader to collect the access card.
        if self.sv.saved.stage == Stages.listen_axobot then
            self.sv.saved.stage = Stages.get_card
            self.storage:save( self.sv.saved )
            self:sv_sync()
        end
    end
end

-- Collected the access card: advance to wait_for_effect so the get_card checkmark flashes, then finish after a short delay.
function VaultQuest3.sv_e_onCardTaken( self )
    if self.sv.saved.stage == Stages.get_card then
        self.sv.saved.stage = Stages.wait_for_effect
        self.storage:save( self.sv.saved )
        self:sv_sync()
        FinishQuestAfterDelay( FinishEvent, WaitTickTime )
    end
end

function VaultQuest3.sv_sync( self, vaultTotal )
    vaultTotal = vaultTotal or ProgressionManager.Sv_GetVaultTotal()
    self.network:setClientData( { stage = self.sv.saved.stage, vaultTotal = vaultTotal } )
end

function VaultQuest3.sv_finishQuest( self )
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
    CompleteQuest( QUEST_NAME )

    -- Normally vault_3 finishes after the scrapyard quest and starts the second station quest. If the
    -- quota was met before scrapyard, don't start it here -- scrapyard completion handles the catch-up
    -- (see ScrapyardQuest.sv_finishQuest).
    if QuestManager.Sv_IsQuestComplete( "quest_scrapyard" ) then
        CompleteAndActivateQuestThroughDialogBeat( "quest_vault_3", "quest_station_2", "finish_quota_3_start_station_2", NextQuestDelay )
    end
end

-- Client

function VaultQuest3.client_onCreate( self )
    self.cl = {}
    self.scriptableObject.clientPublicData = {}

    QuestManager.Cl_OnQuestCreated( QUEST_NAME )
    QuestManager.Cl_UpdateQuestTracker()
end

function VaultQuest3.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function VaultQuest3.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage or Stages.track_quota
    self.cl.vaultTotal = data.vaultTotal
    self:cl_updateProgress( prevStage )
end

function VaultQuest3.cl_updateProgress( self, prevStage )
    local vaultTotal = self.cl.vaultTotal or 0
    local stage = self.cl.stage or Stages.track_quota
    local trackingData = self.data.trackingSteps

    trackingData.quota.count1 = vaultTotal
    trackingData.quota.count2 = trackingData.quota.threshold
    -- get_card completes at the wait_for_effect stage; its flash plays via ApplyTrackingProgress.
    trackingData.get_card.complete = stage > Stages.get_card

    ApplyTrackingProgress( self, trackingData, stage, prevStage )

    -- Tell the trader (Wonky) to hand over this quest's access card while we're in the get_card stage.
    self.scriptableObject.clientPublicData.traderResponse = ( stage == Stages.get_card ) and "give_access_card" or nil
    self.scriptableObject.clientPublicData.traderCardLog = ( stage == Stages.get_card ) and tostring( AccessCardLog ) or nil

    if self.cl.tracked then
        self:cl_updateMarkers()
    end
    QuestManager.Cl_UpdateQuestTracker()
end

function VaultQuest3.cl_updateMarkers( self )
    -- Point back to the trader while collecting the access card; kept through wait_for_effect so the checkmark settles.
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( TraderMarker, self.cl.stage == Stages.get_card or self.cl.stage == Stages.wait_for_effect )
end

function VaultQuest3.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( TraderMarker, false )
end

function VaultQuest3.client_onRefresh( self )
    self:cl_updateProgress()
end

function VaultQuest3.cl_e_onTracked( self )
    self.cl.tracked = true
    self:cl_updateMarkers()
end

function VaultQuest3.cl_e_onUntracked( self )
    self.cl.tracked = false
    self:cl_hideMarkers()
end

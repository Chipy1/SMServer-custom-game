-- MysteriousSignalQuest.lua
-- Quest: Mysterious Signal
-- Guides the player to station1 (depth 3) and culminates in meeting Phae in the control room.

dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestActorManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/NodeSpawnManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

MysteriousSignalQuest = class()
MysteriousSignalQuest.isSaveObject = true

local QUEST_NAME = "quest_mysterious_signal"
local WaitTickTime = 40

MysteriousSignalQuest.Stages = {
    go_to_station = 1,         -- Player needs to ride elevator to depth 3 (ElevatorMarker visible)
    investigate_area = 2,      -- Arrived at depth 3; "Investigate the area" active until station entered + Lorenzo done
    lorenzo_talking = 3,       -- Entered StationTrigger; Lorenzo's reveal call playing; still "Investigate the area"
    explore_station = 4,       -- Lorenzo finished; "Explore the Station" toward the signal source
    signal_close = 5,          -- SignalCloseTrigger; ControlRoomMarker reveals the signal source
    reached_control_room = 6,  -- ControlRoomTrigger; Phae walks and talks; "Reach the Control Room" checked
}
local Stages = MysteriousSignalQuest.Stages

-- Area trigger names (placed by level designer in station1 tiles)
local StationTrigger = "quest_mysterious_signal.station_area"
local SignalCloseTrigger = "quest_mysterious_signal.signal_close"
local ControlRoomTrigger = "quest_mysterious_signal.controlroom_area"

-- Quest markers (placed by level designer)
local ElevatorMarker = "quest_mysterious_signal.elevator"
local ControlRoomMarker = "quest_mysterious_signal.controlroom" -- signal source marker, revealed when close

-- Actor track / spawn constants (level designer places matching nodes)
local PhaeSpawnTrigger = "quest_mysterious_signal.spawnPhae"
local PhaeActorTrackName = "phae.controlroom"
local PhaeActorName = "Phe" -- Internal name is Phe, spelling was changed to Phae.
local PhaeNotifyEvent = "notify.phae_player_arrived"
local MechanicsActorNames = { "Phe", "mechanic_male_01", "mechanic_male_02", "mechanic_male_03", "mechanic_male_04" }

-- Dialog beat played when the player reaches the station; we also watch its completion to advance.
local LorenzoRevealBeat = "lorenzo_station_reveal"

-- Phae's control-room dialog beat; the quest finishes once she stops talking (this beat completes).
local PhaeTalkBeat = "meeting_phae_in_control_room"

local Station1FloorIndex = 4 -- UNDERGROUND_ELEVATORS["MAIN"].floors[4] = station1 (depth 3)

-- Server

function MysteriousSignalQuest.server_onCreate( self )
    self.sv = {}
    self.sv.dirty = false
    self.sv.saved = self.storage:load() or {}
    if not self.sv.saved.stage then
        self.sv.saved.stage = Stages.go_to_station
        self.sv.dirty = true
    end

    self.scriptableObject.publicData = { stage = self.sv.saved.stage }
    self.network:setClientData( { stage = self.sv.saved.stage } )

    QuestManager.Sv_SubscribeEvent( "underground_elevator_used", self.scriptableObject, "sv_e_onElevatorUsed" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( SignalCloseTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( StationTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( ControlRoomTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )



    self:sv_saveIfDirty()
end

function MysteriousSignalQuest.sv_saveIfDirty( self )
    if self.sv.dirty then
        self.sv.dirty = false
        self:sv_saveAndSync()
    end
end

function MysteriousSignalQuest.sv_saveAndSync( self )
    self.storage:save( self.sv.saved )
    self.scriptableObject.publicData = { stage = self.sv.saved.stage }
    self.network:setClientData( { stage = self.sv.saved.stage } )
end

function MysteriousSignalQuest.sv_e_onElevatorUsed( self, data )
    if self.sv.saved.stage ~= Stages.go_to_station then
        return
    end
    if data.params.elevatorName == "MAIN" and data.params.floor == Station1FloorIndex then
        self.sv.saved.stage = Stages.investigate_area
        self.sv.dirty = true
        self:sv_saveIfDirty()
    end
end

function MysteriousSignalQuest.sv_e_onQuestEvent( self, data )
    --print( "[MysteriousSignalQuest] sv_e_onQuestEvent", data.event, data.params and data.params.name )
    local stage = self.sv.saved.stage
    if stage < Stages.lorenzo_talking and data.event == StationTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
        local triggerData = QuestEntityManager.Sv_GetNamedAreaTrigger( StationTrigger )
        -- Player reached the station area — Lorenzo calls to investigate
        DialogManager.Sv_PlayDialogBeat( LorenzoRevealBeat, self.scriptableObject )
        -- Spawn Phae and begin her actor track (she will idle until notified)
        if triggerData then
            NodeSpawnManager.Sv_ActivateSpawnTrigger( PhaeSpawnTrigger, triggerData.areaTrigger.world )
        end
        QuestActorManager.Sv_BeginActorTrack( PhaeActorTrackName, PhaeActorName )
        self.sv.saved.stage = Stages.lorenzo_talking
        self.sv.dirty = true
    elseif stage < Stages.signal_close and data.event == SignalCloseTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
        -- Player got close to the signal source; reveal the control-room marker.
        self.sv.saved.stage = Stages.signal_close
        self.sv.dirty = true
    elseif stage < Stages.reached_control_room and data.event == ControlRoomTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
        -- Player reached the control room — notify Phae to start walking/talking
        --QuestActorManager.Sv_NotifyActor( PhaeActorName, PhaeNotifyEvent )
        for _, name in ipairs( MechanicsActorNames ) do
            QuestActorManager.Sv_NotifyActor( name, PhaeNotifyEvent )
        end
        -- Capture the control room actor units now so they can be cleaned up on completion
        self.sv.saved.controlRoomUnits = {}
        for _, name in ipairs( MechanicsActorNames ) do
            local unit = QuestActorManager.Sv_GetActorUnit( name )
            if unit then
                self.sv.saved.controlRoomUnits[name] = unit
            end
        end
        self.sv.saved.stage = Stages.reached_control_room
        self.sv.dirty = true
    end
    self:sv_saveIfDirty()
end

function MysteriousSignalQuest.sv_e_onDialogCompleted( self, data )
    if self.sv.saved.stage == Stages.lorenzo_talking then
        if IsDialogBeat( data.params.uuid, data.params.entryName, LorenzoRevealBeat ) then
            -- Lorenzo finished his reveal call; let the player explore toward the signal.
            self.sv.saved.stage = Stages.explore_station
            self:sv_saveAndSync()
        end
    elseif self.sv.saved.stage == Stages.reached_control_room then
        if IsDialogBeat( data.params.uuid, data.params.entryName, PhaeTalkBeat ) then
            -- Phae finished talking in the control room — complete the quest.
            self:sv_finishQuest()
        end
    end
end

function MysteriousSignalQuest.sv_finishQuest( self )
    self:sv_saveAndSync()
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )

    -- unregister all the control room actors and mark their units so they disappear on unload.
    for _, name in ipairs( MechanicsActorNames ) do
        local unit = self.sv.saved.controlRoomUnits and self.sv.saved.controlRoomUnits[name]
        if unit then
            if sm.exists( unit ) then
                sm.event.sendToUnit( unit, "sv_e_markForRemoval", nil, sm.event.types.instant )
            else
                sm.unit.forceDestroy( unit )
            end
        end
    end
    self.sv.saved.controlRoomUnits = nil

    CompleteAndActivateQuestThroughDialogBeat( QUEST_NAME, "quest_vault_2", "lorenzo_after_meeting_phae_start_vault2", 15 )
end

-- Client

function MysteriousSignalQuest.client_onCreate( self )
    self.cl = {}
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.stage = Stages.go_to_station

    QuestManager.Cl_OnQuestCreated( QUEST_NAME )
    QuestManager.Cl_UpdateQuestTracker()
end

function MysteriousSignalQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function MysteriousSignalQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage
    self:cl_updateProgress( prevStage )
end

function MysteriousSignalQuest.cl_updateProgress( self, prevStage )
    if not self.cl.stage then return end
    local trackingData = self.data.trackingSteps

    trackingData.go_to_station.complete = self.cl.stage > Stages.go_to_station
    trackingData.investigate_area.complete = self.cl.stage >= Stages.lorenzo_talking
    trackingData.explore_station.complete = self.cl.stage > Stages.explore_station
    trackingData.reach_control_room.complete = self.cl.stage >= Stages.reached_control_room

    ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

    if self.cl.tracked then
        self:cl_updateMarkers()
    end
    QuestManager.Cl_UpdateQuestTracker()
end

function MysteriousSignalQuest.client_onRefresh( self )
    self:cl_updateProgress()
end

function MysteriousSignalQuest.cl_updateMarkers( self )
    self:cl_hideMarkers()
    if self.cl.stage == Stages.go_to_station then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ElevatorMarker, true )
    elseif self.cl.stage == Stages.signal_close then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ControlRoomMarker, true )
    end
end

function MysteriousSignalQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ElevatorMarker, false )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ControlRoomMarker, false )
end

function MysteriousSignalQuest.cl_e_onTracked( self )
    self.cl.tracked = true
    self:cl_updateMarkers()
end

function MysteriousSignalQuest.cl_e_onUntracked( self )
    self.cl.tracked = false
    self:cl_hideMarkers()
end

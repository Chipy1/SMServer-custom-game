-- SecondStationQuest.lua
-- Quest: The Second Station
-- Guides the player to station2 (depth 7) and culminates in Phae's lore dump in the control room.
-- NOTE: Phae is NOT physically present in this quest. Every dialog here is a phone call (type "call").

dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

SecondStationQuest = class()
SecondStationQuest.isSaveObject = true

local QUEST_NAME = "quest_station_2"
local NextQuestDelay = 5 -- seconds

SecondStationQuest.Stages = {
    go_to_station = 1,         -- Ride the elevator down to station2 (no marker; player picks the floor)
    arrived_at_station = 2,    -- Arrived at depth 7; "go to the station" checked
    listening = 3,             -- (hidden) Entered StationTrigger; Phae's arrival call plays; "reach station" stays checked
    explore_station = 4,       -- Phae finished talking; head toward the control room
    reached_control_room = 5,  -- ControlRoomTrigger; Phae calls with the lore dump (waiting for it to finish)
}
local Stages = SecondStationQuest.Stages

-- station2 = UNDERGROUND_ELEVATORS["MAIN"].floors[8] (depth 7)
local Station2FloorIndex = 8

-- Area trigger names (placed by level designer in station2 tiles)
local StationTrigger = "quest_station_2.station_area"
local ControlRoomTrigger = "quest_station_2.controlroom_area"

-- Quest markers (placed by level designer)
local ControlRoomMarker = "quest_station_2.controlroom"

-- Phae's arrival call when the player first reaches the station; the player listens until it finishes.
local ArrivedBeat = "player_arrived_at_station2"

-- Phae's extensive lore dump in the control room. The quest finishes once this call completes.
local ControlRoomLoreBeat = "station2_control_room_lore_dump"

-- Server

function SecondStationQuest.server_onCreate( self )
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
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( StationTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( ControlRoomTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )




    self:sv_saveIfDirty()
end























function SecondStationQuest.sv_saveIfDirty( self )
    if self.sv.dirty then
        self.sv.dirty = false
        self:sv_saveAndSync()
    end
end

function SecondStationQuest.sv_saveAndSync( self )
    self.storage:save( self.sv.saved )
    self.scriptableObject.publicData = { stage = self.sv.saved.stage }
    self.network:setClientData( { stage = self.sv.saved.stage } )
end

function SecondStationQuest.sv_e_onElevatorUsed( self, data )
    if self.sv.saved.stage ~= Stages.go_to_station then
        return
    end
    if data.params.elevatorName == "MAIN" and data.params.floor == Station2FloorIndex then
        self.sv.saved.stage = Stages.arrived_at_station
        self.sv.dirty = true
        self:sv_saveIfDirty()
    end
end

function SecondStationQuest.sv_e_onQuestEvent( self, data )
    local stage = self.sv.saved.stage
    if stage < Stages.listening and data.event == StationTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
        DialogManager.Sv_PlayDialogBeat( ArrivedBeat, self.scriptableObject )
        self.sv.saved.stage = Stages.listening
        self.sv.dirty = true
    elseif stage < Stages.reached_control_room and data.event == ControlRoomTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
        DialogManager.Sv_PlayDialogBeat( ControlRoomLoreBeat, self.scriptableObject )
        self.sv.saved.stage = Stages.reached_control_room
        self.sv.dirty = true
    end
    self:sv_saveIfDirty()
end

function SecondStationQuest.sv_e_onDialogCompleted( self, data )
    if self.sv.saved.stage == Stages.listening then
        if IsDialogBeat( data.params.uuid, data.params.entryName, ArrivedBeat ) then
            self.sv.saved.stage = Stages.explore_station
            self:sv_saveAndSync()
        end
    elseif self.sv.saved.stage == Stages.reached_control_room then
        if IsDialogBeat( data.params.uuid, data.params.entryName, ControlRoomLoreBeat ) then
            self:sv_finishQuest()
        end
    end
end

function SecondStationQuest.sv_finishQuest( self )
    self:sv_saveAndSync()
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )

    -- Lorenzo calls to kick off the boss-train descent (BosstrainQuest part 1).
    CompleteAndActivateQuestThroughDialogBeat( QUEST_NAME, "quest_bosstrain", "lorenzo_after_station2_start_bosstrain", NextQuestDelay )
end

-- Client

function SecondStationQuest.client_onCreate( self )
    self.cl = {}
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.stage = Stages.go_to_station

    QuestManager.Cl_OnQuestCreated( QUEST_NAME )
    QuestManager.Cl_UpdateQuestTracker()
end

function SecondStationQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function SecondStationQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage
    self:cl_updateProgress( prevStage )
end

function SecondStationQuest.cl_updateProgress( self, prevStage )
    if not self.cl.stage then return end
    local trackingData = self.data.trackingSteps

    trackingData.go_to_station.complete = self.cl.stage > Stages.go_to_station
    trackingData.reach_station.complete = self.cl.stage > Stages.arrived_at_station
    trackingData.reach_control_room.complete = self.cl.stage > Stages.explore_station

    ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

    if self.cl.tracked then
        self:cl_updateMarkers()
    end
    QuestManager.Cl_UpdateQuestTracker()
end

function SecondStationQuest.client_onRefresh( self )
    self:cl_updateProgress()
end

function SecondStationQuest.cl_updateMarkers( self )
    self:cl_hideMarkers()
    if self.cl.stage == Stages.explore_station then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ControlRoomMarker, true )
    end
end

function SecondStationQuest.cl_hideMarkers( self )
    QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ControlRoomMarker, false )
end

function SecondStationQuest.cl_e_onTracked( self )
    self.cl.tracked = true
    self:cl_updateMarkers()
end

function SecondStationQuest.cl_e_onUntracked( self )
    self.cl.tracked = false
    self:cl_hideMarkers()
end

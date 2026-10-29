dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua"
dofile( "$SURVIVAL_DATA/Scripts/game/managers/NodeSpawnManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DrillbotManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_logs.lua" )

BosstrainQuest = class()
BosstrainQuest.isSaveObject = true

local TrainWaypointNameLorenzo = "quest_bosstrain.waypoint_lorenzo" -- waypoint on the train for lorenzo to go to
local TrainWaypointNameHubert = "quest_bosstrain.waypoint_hubert" -- waypoint on the train for hubert to go to

local SpawnTrainStationEvent = "event.quest_bosstrain.spawn_train_station" -- single node event: spawns Lorenzo and Hubert together at the boss-floor train
local OutsideSpawnEvent = "spawn.bosstrain.outside" -- shared node trigger: spawns the outside NPCs at the wreck after the boss is defeated

local QuestName = "quest_bosstrain"

local CinematicName = "cinematic.bosstrainstart"

local WAIT_FOR_EFFECT_TICKS = 40 -- 1 second delay so the insert_core checkmark plays before the quest completes
local FinishEvent = "event.quest_bosstrain.finish"

local GoFromMountain = "corePickup"
local GyroCoreUuid = sm.uuid.new( "5f5b2a0d-b629-4bea-93ca-e1f45ccac62b" )
local TrackStartConditionName = "quest_bosstrain.outside.start"

local DroppedCoreMarkerName = "quest_bosstrain.marker_dropped_core"

local CarryCoreTrigger = "CarryCoreTrigger"
local InspectWreckTrigger = "InspectWreckTrigger" -- area trigger at the wreck: entering it (reaching Hubert & Lorenzo) starts Lorenzo's "grab the core" dialog

-- Boss-floor wreck dialog beats (DrillbotOutsideCutsceneDialog "Get the Core").
local BackToShipBeat = "lorenzo_back_to_ship" -- Lorenzo's "back to the ship" call as the NPCs leave the mountain with the core

local BoardingTrigger = "BosstrainBoarding" -- area trigger on the train: a player entering it advances board -> activate
local TrainPortalNodeNameB = "bosstrain_quest.trail_portal_B" -- name of that VOLUME node (provides opening B pos/rot)

-- Hosted marker on Lorenzo, who stands on the boss-floor train (see people.json questMarkerName).
local LorenzoHostedMarkerName = "quest_hosted_lorenzo.marker"

local BosstrainQuestMarkers = {
    "quest_bosstrain.marker_elevator",
    "quest_bosstrain.marker_train",
    "quest_bosstrain.marker_gyrocore",
    "quest_bosstrain.marker_insert",
    LorenzoHostedMarkerName,
    DroppedCoreMarkerName
}

-- Part 1: descent to the boss floor (added before the original train sequence)
local ElevatorEntryTrigger = "quest_bosstrain.elevator_entry" -- area trigger: player steps into the boss elevator
local ElevatorMarkerName = "quest_bosstrain.marker_elevator"
local ElevatorUnlockFXEvent = "event.quest_bosstrain.unlock_elevator" -- event effect name: sparks + schematic-bot unlock effect
-- Boss floor = UNDERGROUND_ELEVATORS["MAIN"].floors[9] ("drillbot lobby", depth 8, displayDepth 7, requires the miner-boss key)
local BossFloorIndex = 9
local BossLevelDialogDelay1 = 30 * 40 -- ticks before Hubert's intro call after arrival
local BossLevelDialogDelay2 = 60 * 40 -- ticks before Lorenzo's intro call after arrival
local BossElevatorDescendingBeat = "elevator_descending_to_boss_floor" -- Hubert's mid-ride call during the boss descent
local BossElevatorRideDelay = 12 * 40 -- ticks after departure before Hubert's mid-ride call
local PlayerBoardsTrainBeat = "player_steps_onto_bosstrain" -- Lorenzo's call once the player steps onto the train

local QuestStartBeat = "after_bosstrain_quest_start" -- Hubert's call shortly after the quest first starts
local QuestStartBeatDelay = 10 * 40 -- ticks after the quest first starts before Hubert's intro call plays

local Stages = {
    -- Part 1: descent to the boss floor (prepended before the original train sequence)
    p1_enter_elevator = 1,  -- Lorenzo's opening call is done; NPCs removed; "enter the elevator"
    p1_unlock_elevator = 2, -- player entered the elevator; Phae calls; the elevator unlocks when she finishes
    p1_ride = 3,            -- elevator unlocked; "take the elevator down"; arrival spawns Lorenzo & Hubert
    p1_listen_arrival = 4, -- listen to arrival calls; "reach the train"
    -- Original train sequence
    board = 5, -- player heads to the train; reaching it checks "reach Lorenzo" and queues Lorenzo's intro
    listen_lorenzo = 6, -- listening to Lorenzo's train intro; "reach Lorenzo" stays checked until it finishes
    activate = 7, -- player talks to lorenzo on the train
	ride = 8, -- cinematic step
    boss = 9, -- boss fight
    inspect_wreck = 10, -- reach Hubert & Lorenzo at the wreck; entering the trigger completes the inspect step
    get_core = 11, -- get the core
    insert_core = 12, -- insert the core
    wait_for_effect = 13 -- brief delay after inserting the core so the checkmark effect plays before the quest completes
}
BosstrainQuest.Stages = Stages

-- NPCs that wait at the boss-floor train.
local TrainNpcs = {
    { actorName = "Lorenzo", questUnit = QuestUnits.Lorenzo, waypoint = TrainWaypointNameLorenzo },
    { actorName = "Hubert",  questUnit = QuestUnits.Hubert,  waypoint = TrainWaypointNameHubert },
}

-- Outside actors released after the boss fight. Each one's spawn.bosstrain.outside node sets
-- questActorParams.spawnTrack, so node-spawning begins their track; the quest only notifies them
-- (start_outside_waypoint_track) to release the track's opening wait at the right cinematic beat.
local OutsideNpcs = {
    { actorName = "Lorenzo" },
    { actorName = "Hubert" },
    { actorName = "Phe" },
}

function BosstrainQuest.sv_getTrainStationWorldFromActorTrack( self )
    local actorTrack = QuestEntityManager.Sv_GetNamedActorTrack( TrainWaypointNameLorenzo )
    if actorTrack then
        return actorTrack.world
    end
    return nil
end

function BosstrainQuest.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.stage = Stages.p1_enter_elevator
        --self.sv.saved.trainStationTrack = nil
        self.sv.saved.trainStationWorld = self:sv_getTrainStationWorldFromActorTrack()

        self:sv_removeStartingNpcs()
        NodeSpawnManager.Sv_ActivateSpawnTrigger( SpawnTrainStationEvent, self.sv.saved.trainStationWorld )

        -- Starting the gyrocore quest permanently ends all bond builder (flavor) dialogs.
        DialogManager.Sv_StopBondBuilders()

        -- Hubert's delayed intro call; tracked so it can be cancelled if the player reaches the elevator first.
        self.sv.saved.questStartActivator = PlayDialogBeatDelayed( QuestStartBeat, QuestStartBeatDelay )
    end

    QuestManager.Sv_SubscribeEvent( FinishEvent, self.scriptableObject, "sv_finishQuest" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.ActorTrackLoaded, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( QuestEvent.QuestUnitCreated, self.scriptableObject, "sv_e_onQuestEvent" )

    -- speak with lorenzo on the train
	QuestManager.Sv_SubscribeEvent( "event.bosstrain_depart", self.scriptableObject, "sv_e_onQuestEvent" )

    -- Boarding the train (entering this trigger) advances board -> activate.
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( BoardingTrigger, self.scriptableObject, "sv_e_onQuestEvent" )

    QuestManager.Sv_SubscribeEvent( "event.quest_bosstrain.enter_bossfight", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_bosstrain.world_ready", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_bosstrain.fail_bossfight", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_bosstrain.end_bossfight", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_bosstrain.finish_cinematic", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_bosstrain.tile_swap", self.scriptableObject, "sv_e_onQuestEvent" )

    QuestManager.Sv_SubscribeEvent( QuestEvent.InventoryChanges, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( CarryCoreTrigger .. QuestEvent.AreaTriggerPlayerExitSuffix, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( InspectWreckTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "event.quest_bosstrain.insert_core", self.scriptableObject, "sv_e_onQuestEvent" )

    QuestManager.Sv_SubscribeEvent( "event.quest_bosstrain.start_outside_waypoint_track", self.scriptableObject, "sv_e_onQuestEvent" )

    -- Part 1: elevator descent to the boss floor
    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )
    QuestManager.Sv_SubscribeEvent( "underground_elevator_departed", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribeEvent( "underground_elevator_used", self.scriptableObject, "sv_e_onQuestEvent" )
    QuestManager.Sv_SubscribePlayerEnterAreaTrigger( ElevatorEntryTrigger, self.scriptableObject, "sv_e_onQuestEvent" )




    self:sv_saveAndSync()
end

function BosstrainQuest.client_onRefresh( self )
    self:cl_updateProgress()
end

-- Cancel the delayed Hubert quest-start call if it hasn't fired yet.
function BosstrainQuest.sv_cancelQuestStartDialog( self )
    local activator = self.sv.saved.questStartActivator
    if activator and sm.exists( activator ) then
        activator:destroy()
    end
    self.sv.saved.questStartActivator = nil
end

-- Cancel pending boss-floor arrival calls (delayed Hubert/Lorenzo intros) if the player boards early.
function BosstrainQuest.sv_cancelTrainIntroDialogs( self )
    if self.sv.saved.trainIntroActivators then
        for _, activator in ipairs( self.sv.saved.trainIntroActivators ) do
            if activator and sm.exists( activator ) then
                activator:destroy()
            end
        end
        self.sv.saved.trainIntroActivators = nil
    end
end

function BosstrainQuest.sv_removeStartingNpcs( self )
    -- Unregister their actor tracks and destroy their units so they leave the world entirely.
    for _, actorName in ipairs( { "Hubert", "Lorenzo", "Phe" } ) do
        QuestActorManager.Sv_UnregisterActor( actorName )
    end
    for _, questUnitEnum in ipairs( { QuestUnits.Hubert, QuestUnits.Lorenzo, QuestUnits.Phe } ) do
        local unit = QuestManager.Sv_GetQuestUnit( questUnitEnum )
        if unit then
            sm.unit.forceDestroy( unit )
        end
    end
end

-- Find the tagged VOLUME node in the train tile that marks portal opening B.
function BosstrainQuest.sv_findTrainPortalBNode( self, nearPosition, world )
    local xMin, xMax, yMin, yMax = GetTileRanges( nearPosition, world.id )
    if not xMin then
        return nil
    end
    for x = xMin, xMax do
        for y = yMin, yMax do
            local nodes = sm.cell.getNodesByTag( x, y, "VOLUME", world )
            for _, node in ipairs( nodes ) do
                if node.params and node.params.name == TrainPortalNodeNameB then
                    return node
                end
            end
        end
    end
    return nil
end

-- Create the train portal as the player boards. Opening A = the boarding trigger volume (the train);
-- opening B = the tagged VOLUME node in the tile. Used at departure to carry train contents to B.
function BosstrainQuest.sv_createTrainPortal( self )
    if self.sv.saved.trainPortal and sm.exists( self.sv.saved.trainPortal ) then
        return
    end

    local triggerData = QuestEntityManager.Sv_GetNamedAreaTrigger( BoardingTrigger )
    if not ( triggerData and sm.exists( triggerData.areaTrigger ) ) then
        sm.log.warning( "BosstrainQuest: cannot create train portal, boarding trigger missing" )
        return
    end
    local trigger = triggerData.areaTrigger
    local world = trigger.world
    local openingAPos = trigger:getWorldPosition()
    local openingARot = trigger:getWorldRotation()
    local halfExtents = trigger:getSize()

    local nodeB = self:sv_findTrainPortalBNode( openingAPos, world )
    if not nodeB then
        sm.log.warning( "BosstrainQuest: cannot create train portal, '"..TrainPortalNodeNameB.."' node not found" )
        return
    end

    local portal = sm.portal.createPortal( halfExtents )
    portal:setOpeningA( openingAPos, openingARot, world )
    portal:setOpeningB( nodeB.position, nodeB.rotation, world )

    self.sv.saved.trainPortal = portal
    self:sv_saveAndSync()
end

-- Move loose creations from the train (opening A) to opening B at departure. Characters are filtered
-- out; players and NPCs are relocated to the boss-fight world separately.
function BosstrainQuest.sv_transferCreationsFromTrain( self )
    if self.sv.saved.trainPortal and sm.exists( self.sv.saved.trainPortal ) then
        self.sv.saved.trainPortal:transferAToB( sm.physics.filter.dynamicBody )
    end
end

function BosstrainQuest.sv_e_onDialogCompleted( self, data )
    if self.sv.saved.stage == Stages.p1_unlock_elevator then
        if IsDialogBeat( data.params.uuid, data.params.entryName, "enter_station2_elevator_after_station2_complete" ) then
            -- Phae finished her call: unlock the elevator down to the boss floor.
            -- Granting the (hidden) miner-boss key satisfies UNDERGROUND_ELEVATORS["MAIN"].floors[9].requiresKey.
            LogEntryManager.Sv_AddLog( LOGS.log_underground_minerboss_key, true )
            -- Sparks + schematic-bot unlock effect at the elevator.
            if self.sv.saved.elevatorWorld and self.sv.saved.elevatorPos then
                EffectManager.Sv_ActivateEventEffect( self.sv.saved.elevatorWorld, ElevatorUnlockFXEvent, self.sv.saved.elevatorPos )
            end
            self.sv.saved.stage = Stages.p1_ride
            self:sv_saveAndSync()
        end
    elseif self.sv.saved.stage == Stages.p1_listen_arrival then
        if IsDialogBeat( data.params.uuid, data.params.entryName, "player_reaches_boss_floor" ) then
            -- Final arrival call finished: the player can now board and speak with Lorenzo on the train.
            self.sv.saved.stage = Stages.board
            self:sv_saveAndSync()
        end
    elseif self.sv.saved.stage == Stages.listen_lorenzo then
        if IsDialogBeat( data.params.uuid, data.params.entryName, PlayerBoardsTrainBeat ) then
            -- Lorenzo finished his train intro: prompt the player to speak with him when ready.
            self.sv.saved.stage = Stages.activate
            self:sv_saveAndSync()
            -- If the player already interacted with Lorenzo before this point, honour it now.
            self:sv_processPendingDepart()
        end
    end
end

-- fallback replay a bosstrain_depart request that arrived before the activate stage.
function BosstrainQuest.sv_processPendingDepart( self )
    if self.sv.saved.stage == Stages.activate and self.sv.saved.departPending then
        local pending = self.sv.saved.departPending
        self.sv.saved.departPending = nil
        self:sv_saveAndSync()
        self:sv_e_onQuestEvent( { event = "event.bosstrain_depart", next = pending.next, params = { player = pending.player } } )
    end
end

function BosstrainQuest.sv_saveAndSync( self )
    if sm.exists( self.scriptableObject ) then
        self.storage:save( self.sv.saved )
        Sv_SetPublicDataStage( self, self.sv.saved.stage )
        self.network:setClientData( { stage = self.sv.saved.stage, coreTimerActive = self.sv.saved.corePickupTick ~= nil } )
    end
end

function BosstrainQuest.server_onFixedUpdate( self, dt )
    if ( self.sv.saved.stage == Stages.insert_core or self.sv.saved.stage == Stages.get_core ) and self.sv.saved.corePickupTick then
        local currentTick = sm.game.getCurrentTick()
        local elapsedTicks = currentTick - self.sv.saved.corePickupTick
        if elapsedTicks > GYRO_CORE_TIMEOUT_TICKS then
            -- Find and remove the core from the carrying player, even getting from inactive players
            for _, player in pairs( sm.player.getAllPlayers( true ) ) do
                local carryContainer = player:getCarry()
                if carryContainer and sm.container.totalQuantity( carryContainer, GyroCoreUuid ) > 0 then
                    sm.log.info( "BosstrainQuest: Gyro core timeout " .. elapsedTicks .. " > " .. GYRO_CORE_TIMEOUT_TICKS .. ", removing from " .. player:getName() )
                    if sm.container.beginTransaction() then
                        sm.container.spendFromSlot( carryContainer, 0, GyroCoreUuid, 1, true )
                        sm.container.endTransaction()
                    end
                    break
                end
            end
            -- now we should reset to stage get_core and respawn the core in the world for players to pick up again.
            self.sv.saved.stage = Stages.get_core
            self.sv.saved.corePickupTick = nil
          
            self.sv.saved.coreRemoveEffectPlayed = nil
            NodeSpawnManager.Sv_ActivateSpawnTrigger( "respawn.gyrocore", WorldManager.Sv_GetWorld( "overworld" ) )
            self:sv_saveAndSync()
        end
    end

    -- Recovery for saves stuck by old auto interaction complete bug.
    if self.sv.saved.stage == Stages.activate then
        local currentCommand = QuestActorManager.Sv_GetActorCurrentCommand( "Lorenzo" )
        if currentCommand and currentCommand.name == "wait" and currentCommand.notifyActorEvent == "endless" then
            sm.log.info( "BosstrainQuest: Lorenzo is not waiting for interaction, resetting actor track" )
            QuestActorManager.Sv_BeginActorTrack( TrainWaypointNameLorenzo, "Lorenzo", true )
        end
    end
end













































-- Gyro-core pickup: stamp the carrier's pickup tick and jump to insert_core. Shared by the
-- inspect/listen/get_core stages so grabbing the core early skips ahead.
function BosstrainQuest.sv_tryPickUpCore( self, data )
    if data.event == QuestEvent.InventoryChanges and FindInventoryChange( data.params.changes, GyroCoreUuid ) > 0 then
        -- Find the player whose carry container received the gyro core
        for _, player in pairs( sm.player.getAllPlayers() ) do
            local carryContainer = player:getCarry()
            if carryContainer == data.params.container then
                local pickupTick = sm.game.getCurrentTick()
                player:setCarryData( { pickupTick = pickupTick } )
                self.sv.saved.corePickupTick = pickupTick

                if not self.sv.saved.coreRemoveEffectPlayed then
                    self.sv.saved.coreRemoveEffectPlayed = true
                    local corePosition = QuestEntityManager.Sv_GetQuestMarkerPosition( "quest_bosstrain.marker_gyrocore" )
                    if corePosition then
                        sm.effect.playEffect( "audio:event:/char/npc/bots/enemies/drillbot/core_remove", corePosition, nil, nil, nil, nil, nil, player:getCharacter():getWorld() )
                    end
                end

                sm.log.info( "BosstrainQuest: Gyro core picked up by " .. player:getName() .. " at tick " .. pickupTick )
                break
            end
        end
        self.sv.saved.stage = Stages.insert_core
        return true
    end
    return false
end

function BosstrainQuest.sv_e_onQuestEvent( self, data )
    if self.sv.saved.stage <= Stages.activate and ( data.event == QuestEvent.QuestUnitCreated or data.event == QuestEvent.ActorTrackLoaded ) then
        for _, npc in ipairs( TrainNpcs ) do
            if data.event == QuestEvent.ActorTrackLoaded then
                if data.params.name == npc.waypoint then
                    QuestActorManager.Sv_BeginActorTrack( npc.waypoint, npc.actorName )
                    break
                end
            elseif data.event == QuestEvent.QuestUnitCreated then
                if data.params.questUnitEnum == npc.questUnit then
                    QuestActorManager.Sv_BeginActorTrack( npc.waypoint, npc.actorName )
                    break
                end
            end
        end
    end

    if data.event == CarryCoreTrigger .. QuestEvent.AreaTriggerPlayerExitSuffix then
        if data.params.results then
            for _,result in ipairs( data.params.results ) do
                if sm.exists( result ) then
                    local player = result:getPlayer()
                    if player then
                        local carryContainer = player:getCarry()
                        if carryContainer then
                            if sm.container.totalQuantity( carryContainer, GyroCoreUuid ) > 0 then
                                for _, value in ipairs( END_QUEST_ACTORS ) do
                                    QuestActorManager.Sv_NotifyActor( value, GoFromMountain )
                                end
                                -- Leaving the wreck with the core: Lorenzo's "back to the ship" call as the NPCs head off.
                                if not self.sv.saved.backToShipPlayed then
                                    self.sv.saved.backToShipPlayed = true
                                    self:sv_saveAndSync()
                                    DialogManager.Sv_PlayDialogBeat( BackToShipBeat, self.scriptableObject )
                                end
                            end
                        end
                        return true
                    end
                end
            end
        end
    end

    if data.event == "event.bosstrain_depart" and self.sv.saved.stage < Stages.activate then
        self.sv.saved.departPending = { next = data.next, player = data.params and data.params.player }
        self:sv_saveAndSync()
        return
    end

    if self.sv.saved.stage == Stages.p1_enter_elevator then
        if data.event == ElevatorEntryTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            -- Player stepped into the boss elevator: Phae calls.
            -- Cancel Hubert's pending intro call so it can't fire after Phae's elevator call.
            self:sv_cancelQuestStartDialog()
            local triggerData = QuestEntityManager.Sv_GetNamedAreaTrigger( ElevatorEntryTrigger )
            if triggerData and sm.exists( triggerData.areaTrigger ) then
                self.sv.saved.elevatorWorld = triggerData.areaTrigger.world
                self.sv.saved.elevatorPos = triggerData.areaTrigger:getWorldPosition()
            end
            DialogManager.Sv_PlayDialogBeat( "enter_station2_elevator_after_station2_complete", self.scriptableObject )
            self.sv.saved.stage = Stages.p1_unlock_elevator
        end
    elseif self.sv.saved.stage == Stages.p1_ride then
        if data.event == "underground_elevator_departed" and data.params.elevatorName == "MAIN" and data.params.destinationFloor == BossFloorIndex then
            -- Elevator just left for the boss floor: schedule Hubert's mid-ride call.
            PlayDialogBeatDelayed( BossElevatorDescendingBeat, BossElevatorRideDelay )
        elseif data.event == "underground_elevator_used" and data.params.floor == BossFloorIndex then
            -- Elevator arrived at the boss floor and the doors opened.
            self.sv.saved.trainStationWorld = self.sv.saved.trainStationWorld or self:sv_getTrainStationWorldFromActorTrack()
            DialogManager.Sv_PlayDialogBeat( "player_reaches_boss_floor", self.scriptableObject )

            -- Hubert speaks first, then Lorenzo, with a delay between the two calls. Track these delayed
            -- activators so they can be cancelled if the player boards and starts the ride before the
            -- intro calls have fired.

            -- used to be multiple.
            self.sv.saved.trainIntroActivators = {
                PlayDialogBeatDelayed( "delayed1_after_reaching_bossfloor", BossLevelDialogDelay1 )
            }

            self.sv.saved.stage = Stages.p1_listen_arrival
        end
    end

    if self.sv.saved.stage == Stages.board then
        if data.event == BoardingTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            -- A player reached the train: "reach Lorenzo" is checked. Cancel any still-pending approach
            -- calls so they don't fire after boarding, then play Lorenzo's dedicated boarding line
            -- directly through the manager. sv_e_onDialogCompleted advances to activate when it ends.
            self:sv_cancelTrainIntroDialogs()
            self:sv_createTrainPortal()
            DialogManager.Sv_PlayDialogBeat( PlayerBoardsTrainBeat, self.scriptableObject )
            self.sv.saved.stage = Stages.listen_lorenzo
        end
    elseif self.sv.saved.stage == Stages.activate then
        if data.event == "event.bosstrain_depart" then
            
            -- Check all non-host players present.  The dedicated server host is
            -- not a character in the world, so counting it made the train wait
            -- for a player who could never stand in the trigger.
            local present = false
            local hostPlayer = sm.player.getHostPlayer()
            local presentNonHost = 0
            local requiredNonHost = 0
            for _, player in ipairs( sm.player.getAllPlayers() ) do
                if player ~= hostPlayer then
                    requiredNonHost = requiredNonHost + 1
                end
            end

            local playersPresentArea = QuestEntityManager.Sv_GetNamedAreaTrigger( BoardingTrigger )
            local presentPlayers = {}
            if playersPresentArea and sm.exists( playersPresentArea.areaTrigger ) then

                local contents = playersPresentArea.areaTrigger:getContents()
                for _, content in ipairs( contents ) do
                    if type( content ) == "Character" then
                        if content:isPlayer() then
                            local player = content:getPlayer()
                            table.insert( presentPlayers, player )
                            if player ~= hostPlayer then
                                presentNonHost = presentNonHost + 1
                            end
                        end
                    end
                end
                if presentNonHost == requiredNonHost then
                    present = true
                end
            end

            if not present and not data.next and data.params.player then
                self.network:sendToClient( data.params.player, "cl_n_alertPlayersPresent" )
            elseif present or data.next then
                local unit = QuestManager.Sv_GetQuestUnit( QuestUnits.Lorenzo )
                local tsk
                if unit and unit.character then
                    tsk = TileStorageManager.Sv_GetTileStorageKeyFromObject( unit.character )
                end
                --train kinematic triggered by cinematic effect
                sm.game.pauseSaving( "DB Train", 40 * 60 * 2 );
                self.sv.saved.trainStationWorld = self.sv.saved.trainStationWorld or self:sv_getTrainStationWorldFromActorTrack()
                EffectManager.Sv_PlayNamedCinematic( { name = CinematicName, callbackData = { world = self.sv.saved.trainStationWorld, tileStorageKey = tsk, players = presentPlayers }, interruptible = false } )
                QuestActorManager.Sv_CompleteActorInteraction( "Lorenzo" )
                QuestActorManager.Sv_NotifyActor( "Hubert", "quest_bosstrain.introcinematic" )

                -- Train is departing: carry everything left on it across to the portal B drop-off.
                self:sv_transferCreationsFromTrain()

                if self.sv.saved.drillbotWorld then
                    -- if world exists from before, reset it. If it was unloaded, load it and then reset it.
                    if not sm.exists( self.sv.saved.drillbotWorld ) then
                        sm.world.loadWorld( self.sv.saved.drillbotWorld )
                        self.sv.resetWorldOnReady = true
                    else
                        sm.event.sendToWorld( self.sv.saved.drillbotWorld, "sv_e_resetWorld" )
                    end
                else
                    self.sv.saved.drillbotWorld = sm.world.createWorld( "$SURVIVAL_DATA/Scripts/game/worlds/DrillbotWorld.lua", "DrillbotWorld", {}, math.random( 1073741823 ) )
                end

                self.sv.saved.stage = Stages.ride
            end
        end
    elseif self.sv.saved.stage == Stages.ride then
        if data.event == "event.quest_bosstrain.world_ready" then
            if self.sv.resetWorldOnReady == true then
                sm.event.sendToWorld( self.sv.saved.drillbotWorld, "sv_e_resetWorld" )
                self.sv.resetWorldOnReady = false
            end
        end
        if data.event == "event.quest_bosstrain.enter_bossfight" then
            -- cinematic says it's time to enter the boss fight, tell mgr to spawn the carts, then move the players in.
            sm.game.resumeSaving( "DB Train" );
            -- The train NPCs rode the train in; remove them and stop the station spawn re-priming them
            -- (a failed fight re-primes it again from fail_bossfight).
            for _, npc in ipairs( TrainNpcs ) do
                local unit = QuestManager.Sv_GetQuestUnit( npc.questUnit )
                if unit and sm.exists( unit ) then
                    QuestActorManager.Sv_UnregisterActor( npc.actorName )
                    unit:destroy()
                end
            end

            if self.sv.saved.drillbotWorld then
                -- move all players who are present during the cinematic to the boss fight world, even if you log in during it.
                -- i.e. all players who are in self.sv.saved.trainStationWorld
                self.sv.saved.trainStationWorld = self.sv.saved.trainStationWorld or self:sv_getTrainStationWorldFromActorTrack()
                local bossfightPlayers = {}
                for _, player in pairs( sm.player.getAllPlayers() ) do
                    local character = player:getCharacter()
                    if character and sm.exists( character ) then
                        if character:getWorld() == self.sv.saved.trainStationWorld then
                            bossfightPlayers[#bossfightPlayers + 1] = player
                        end
                    end
                end
                DrillbotManager.Sv_StartFight( self.sv.saved.drillbotWorld, bossfightPlayers )
                self.sv.saved.stage = Stages.boss
            end
            -- NOTE: train kinematic should not be set to saved, should always appear at the station when reloading.
        end
    elseif self.sv.saved.stage == Stages.boss then
        if data.event == "event.quest_bosstrain.fail_bossfight" then
            -- boss fight failed, restart from the boarding stage
            self.sv.saved.stage = Stages.board
            self.sv.saved.departPending = nil
            -- ensure Lorenzo and Hubert are back at the station
            NodeSpawnManager.Sv_DeactivateSpawnTrigger( SpawnTrainStationEvent )
            NodeSpawnManager.Sv_ActivateSpawnTrigger( SpawnTrainStationEvent, self.sv.saved.trainStationWorld )
        end
        if data.event == "event.quest_bosstrain.end_bossfight" then
            -- boss fight complete, move all player back to overworld
            DrillbotManager.Sv_EndFight( self.sv.saved.drillbotWorld )
        end
        if data.event == "event.quest_bosstrain.tile_swap" then
            local locations = sm.storage.load( STORAGE_CHANNEL_LOCATIONS )
            if locations and locations["drillbotMountain"] then
                local location = locations["drillbotMountain"]
                SetTileStorageFlagAtPosition( location.world, location.pos, "drillbot_defeated" )
                sm.event.sendToGame( "sv_reloadTile", { pos = location.pos, world = location.world } )
                EffectManager.Sv_UpdateTagFilteredEffectsForTile( location.world, location.pos, { "drillbot_defeated" } )
                NodeSpawnManager.Sv_ActivateSpawnTrigger( OutsideSpawnEvent, location.world )
            else
                sm.log.error( "Error: No location 'drillbotMountain' found in location storage" )
            end
        end
        if data.event == "event.quest_bosstrain.start_outside_waypoint_track" then
            -- Release the outside actors at the right cinematic beat.
            for _, npc in ipairs( OutsideNpcs ) do
                QuestActorManager.Sv_NotifyActor( npc.actorName, TrackStartConditionName )
            end

            -- destroy all bots nearby the mountain.
            local locations = sm.storage.load( STORAGE_CHANNEL_LOCATIONS )
            if locations and locations["drillbotMountain"] then
                local location = locations["drillbotMountain"]
                local radius = 64 * 6
                local units = sm.unit.getAllUnits( location.world )
                for _, unit in pairs( units ) do
                    local character = sm.exists( unit ) and unit:getCharacter() or nil
                    if character and sm.exists( character ) and ( character:getWorldPosition() - location.pos ):length2() < radius * radius then
                        if isAnyOf( character:getCharacterType(), g_robots ) then
                            unit:destroy()
                            print( "Destroyed a robot at the mountain" )
                        end
                    end
                end
            else
                sm.log.error( "Error: No location 'drillbotMountain' found in location storage" )
            end

            -- notify all outdoor actors to continue on their tracks
            self.sv.saved.stage = Stages.inspect_wreck
        end
        if data.event == "event.quest_bosstrain.finish_cinematic" then --TODO rename this event, finish cinematic
            sm.game.resumeSaving( "DB Mountain" ) -- resumes here but starts in drillbot manager
        end
    elseif self.sv.saved.stage == Stages.inspect_wreck then
        if data.event == InspectWreckTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            -- Reaching the wreck completes the inspect step; go straight to grabbing the core.
            self.sv.saved.stage = Stages.get_core
        else
            -- The core is already grabbable during the inspect step; grabbing it skips ahead to insert_core.
            self:sv_tryPickUpCore( data )
        end
    elseif self.sv.saved.stage == Stages.get_core then
        self:sv_tryPickUpCore( data )
    elseif self.sv.saved.stage == Stages.insert_core then
        if data.event == "event.quest_bosstrain.insert_core" then
            -- Core inserted: hold on a short delay stage so the checkmark effect plays before completing.
            self.sv.saved.stage = Stages.wait_for_effect
            FinishQuestAfterDelay( FinishEvent, WAIT_FOR_EFFECT_TICKS )
        end
        if data.event == QuestEvent.InventoryChanges then
            if FindInventoryChange( data.params.changes, GyroCoreUuid ) < 0 then
                -- Core was dropped, go back to get_core but keep the timer running
                self.sv.saved.stage = Stages.get_core
            end
        end
    end
    self:sv_saveAndSync()
end

function BosstrainQuest.sv_finishQuest( self )
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )

    -- The train portal is only needed during the boarding/departure sequence; clean it up on completion.
    if self.sv.saved.trainPortal then
        if sm.exists( self.sv.saved.trainPortal ) then
            sm.portal.destroy( self.sv.saved.trainPortal )
        end
    end
    CompleteAndActivateQuestThroughDialogBeat( QuestName, "quest_endgame", "after_put_core_start_end_quest" )
end

function BosstrainQuest.cl_n_alertPlayersPresent( self )
   NotificationManager.Cl_AddGenericNotification( "#{REQUIRES_ALL_PLAYERS_PRESENT}", nil, true )
end

function BosstrainQuest.client_onCreate( self )
    self.cl = {}
    self.cl.stage = Stages.p1_enter_elevator
    self.scriptableObject.clientPublicData = {}
    self.scriptableObject.clientPublicData.stage = Stages.p1_enter_elevator
    QuestManager.Cl_OnQuestCreated( QuestName  )
    QuestManager.Cl_UpdateQuestTracker()
end

function BosstrainQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

function BosstrainQuest.cl_e_onFinishQuest( self ) -- complete from dialog callback
    self.network:sendToServer( "sv_n_finishQuest" )
end

function BosstrainQuest.client_onClientDataUpdate( self, data )
    local prevStage = self.cl.stage
    self.cl.stage = data.stage
    self.cl.coreTimerActive = data.coreTimerActive
    self:cl_updateProgress( prevStage )
end

function BosstrainQuest.cl_updateProgress( self, prevStage )
    if not self.cl.stage then return end
    local trackingData = self.data.trackingSteps

    -- Checkmarks fill while their line is still visible (multi-stage objectives).
    trackingData.enter_elevator.complete = self.cl.stage > Stages.p1_enter_elevator
    trackingData.take_elevator.complete = self.cl.stage > Stages.p1_ride

    trackingData.reach_train.complete = self.cl.stage > Stages.board
    trackingData.speak_lorenzo.complete = self.cl.stage > Stages.activate
    -- inspect_wreck checks as soon as the player enters the wreck trigger (advancing to get_core).
    trackingData.inspect_wreck.complete = self.cl.stage > Stages.inspect_wreck
    trackingData.get_core.complete = self.cl.stage > Stages.get_core
    trackingData.insert_core.complete = self.cl.stage > Stages.insert_core

    ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

    self:cl_updateMarkers()
    QuestManager.Cl_UpdateQuestTracker()
end
        
 

function BosstrainQuest.cl_updateMarkers( self )
    if not self.cl.tracked then
        return
    end
    self:cl_hideMarkers()
    if self.cl.stage == Stages.p1_enter_elevator or self.cl.stage == Stages.p1_unlock_elevator or self.cl.stage == Stages.p1_ride then
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( ElevatorMarkerName, true )
    elseif self.cl.stage == Stages.p1_listen_arrival or self.cl.stage == Stages.board or self.cl.stage == Stages.listen_lorenzo or self.cl.stage == Stages.activate then
        -- Point the player at Lorenzo himself, who is always standing on the boss-floor train during these stages.
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( LorenzoHostedMarkerName, true )
    elseif self.cl.stage == Stages.inspect_wreck or self.cl.stage == Stages.get_core then
        -- The gyro-core (and its marker) is reachable from the moment the player arrives at the wreck.
        if self.cl.coreTimerActive then
            QuestEntityManager.Cl_SetNamedQuestMarkerVisible( DroppedCoreMarkerName, true )
        else
            QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_bosstrain.marker_gyrocore", true )
        end
    elseif self.cl.stage == Stages.insert_core then
        local coreInCarry = false
        for _, player in pairs( sm.player.getAllPlayers() ) do
            local carryContainer = player:getCarry()
            if carryContainer and sm.exists( carryContainer ) then
                if sm.container.totalQuantity( carryContainer, GyroCoreUuid ) > 0 then
                    coreInCarry = true
                    break
                end
            end
        end
        if coreInCarry then
            QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_bosstrain.marker_insert", true )
        else
            QuestEntityManager.Cl_SetNamedQuestMarkerVisible( DroppedCoreMarkerName, true )
        end
    end

end

function BosstrainQuest.cl_hideMarkers( self )
    for _, markerName in ipairs( BosstrainQuestMarkers ) do
        QuestEntityManager.Cl_SetNamedQuestMarkerVisible( markerName, false )
    end
end

function BosstrainQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function BosstrainQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end
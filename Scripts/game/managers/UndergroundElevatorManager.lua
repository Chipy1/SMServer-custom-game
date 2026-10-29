dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ProgressionManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

local ScrapyardFloorIndex = 6
local ScrapyardQuestName = "quest_scrapyard"
local ScrapyardQuestDialogBeat = "elevator_stuck_at_scrapyard_start_quest"


UndergroundElevatorManager = class( nil )

local ELEVATOR_TRAVEL_TICKS = 1120
-- Departure-anchored offsets (ticks elapsed since departure). Computed per ride as
-- travelTicks - offset so the doors close and the walls/visuals start shortly after
-- departure even on long (boss-floor) rides.
local ELEVATOR_CLOSE_DOOR_OFFSET = 40
local ELEVATOR_MOVEWALLS_OFFSET = 300
-- Arrival-anchored checkpoints (ticks remaining until arrival). These stay a fixed time before arrival.
local ELEVATOR_LOAD_WORLDS_TICK = 760
local ELEVATOR_TRANSFER_TICK = 400
local ELEVATOR_START_FADE = ELEVATOR_TRANSFER_TICK + 50 -- Sometime before transfer
local ELEVATOR_AUDIO_STOPPING = ELEVATOR_START_FADE + 40
local ELEVATOR_END_FADE = 320 -- Before doors open
-- Quest/dialog triggers fire slightly after the end fade. Since ticksToDestination counts
-- down, a later moment is a smaller value, so the delay is subtracted from ELEVATOR_END_FADE.
local ELEVATOR_QUEST_TRIGGER_DELAY = 40 * 3
local ELEVATOR_QUEST_TRIGGER = ELEVATOR_END_FADE - ELEVATOR_QUEST_TRIGGER_DELAY
local ELEVATOR_OPEN_DOOR = 60

local ELEVATOR_FADE_TIMEOUT = ELEVATOR_START_FADE * ( 1.0 / 40.0 ) + 5.0
local ELEVATOR_FADE_DURATION = 0.75

-- Boss-floor descent ("drillbot lobby", UNDERGROUND_ELEVATORS["MAIN"].floors[9]) for the bosstrain quest.
local BossLobbyFloorIndex = 9
local BOSS_ELEVATOR_TRAVEL_TICKS_FIRST = ELEVATOR_TRAVEL_TICKS * 3          -- long, dramatic first descent
local BOSS_ELEVATOR_TRAVEL_TICKS_REPEAT = math.max( BOSS_ELEVATOR_TRAVEL_TICKS_FIRST / 2, ELEVATOR_TRAVEL_TICKS ) -- half as long on subsequent rides, but at least the normal ride length

function UndergroundElevatorManager.Sv_FindUndergroundConnectionTag( tags )
	local foundTags = intersection( tags, UNDERGROUND_CONNECTIONS )
	if #foundTags == 1 then
		return foundTags[1]
	elseif #foundTags == 0 then
		sm.log.error( "No elevator connection tags found in tag list:", tags )
	else
		sm.log.error( "Multiple elevator connection tags found in tag list:", tags )
	end
    return nil
end

function UndergroundElevatorManager.Sv_FindElevatorFloor( world, connectionTag )
	print( "Finding elevator floor for connection tag", connectionTag )
	local publicData = world.publicData
	if publicData.type == "Overworld" then
		local elevator = UNDERGROUND_ELEVATORS[CONNECTION_TO_ELEVATOR_NAME[connectionTag]]
		print( elevator.floors[1] )
		return 1, elevator.floors[1]
	else
		local elevator = UNDERGROUND_ELEVATORS[CONNECTION_TO_ELEVATOR_NAME[connectionTag]]
		for i, floor in ipairs( elevator.floors ) do
			if floor.depth == publicData.depth and floor.connectionTag == connectionTag then
				print( elevator.floors[i] )
				return i, elevator.floors[i]
			end
		end
	end
	return nil, nil
end

function UndergroundElevatorManager.server_onCreate( self )
	g_undergroundElevatorManager = self
    self.elevators = sm.storage.load( STORAGE_CHANNEL_UNDERGROUND_ELEVATORS )
    if self.elevators == nil then
        self.elevators = {}
		self:sv_saveElevators()
    end
	for _, elevator in pairs( self.elevators ) do
		if elevator.floors == nil then
			elevator.floors = {}
		end
		local currentFloor = elevator.ticksToDestination == -1 and elevator.currentFloor or nil
		elevator.doorStates = elevator.doorStates or {}
		elevator.pendingDoorStates = elevator.pendingDoorStates or {}
		for floorIndex, _ in pairs( elevator.floors ) do
			elevator.doorStates[floorIndex] = currentFloor == floorIndex
		end
	end
    self.activeElevators = {}
	self.loadedCells = {}
	self.loadCellHandles = {}

	for _, elevator in pairs( self.elevators ) do
		if elevator.ticksToDestination >= 0 and elevator.currentFloor > 0 then
			addToArrayIfNotExists( self.activeElevators, elevator )
		end
	end
	--g_questManager is not guaranteed initialized at this point so defer recory till one tick later
	sm.event.sendToScriptableObject( self.scriptableObject, "sv_tryRecoverScrapyardQuest" )
end

-- Legacy save recovery for the scrapyard quest if activation never occurred
function UndergroundElevatorManager.sv_tryRecoverScrapyardQuest( self )
	local mainElevator = self.elevators["MAIN"]
	local shouldRecoverScrapyardQuest = (mainElevator and mainElevator.scrapyardDialogStarted) and
										not QuestManager.Sv_HasQuestActivator( ScrapyardQuestName ) and
										not QuestManager.Sv_IsQuestComplete( ScrapyardQuestName ) and
										not QuestManager.Sv_IsQuestActive( ScrapyardQuestName )
	if shouldRecoverScrapyardQuest then
		QuestManager.Sv_TryActivateQuest( ScrapyardQuestName )
	end
end

function UndergroundElevatorManager.sv_saveElevators( self )
    sm.storage.save( STORAGE_CHANNEL_UNDERGROUND_ELEVATORS, self.elevators )
end

local function CellKey( world, x, y )
	return world.id..":("..x..","..y..")"
end

local function GetElevatorTravelDirection( elevator )
	if elevator.currentFloor > elevator.destinationFloor then
		return "up"
	end
	return "down"
end

local function IsElevatorMoving( elevatorFloor )
	if elevatorFloor == nil then
		return false
	end
	return KinematicManager.Sv_IsMoving( elevatorFloor.tileKey, "opengate01", { elevatorFloor.connectionTag } )
end

local function IsOpenEventRegistered( elevatorFloor )
	if elevatorFloor == nil then
		return false
	end
	local registered = KinematicManager.Sv_GetRegistered( elevatorFloor.tileKey, "opengate01", { elevatorFloor.connectionTag } )
	return registered ~= nil and #registered > 0
end

local function CanElevatorGo( elevator, targetFloor )
	if elevator.ticksToDestination ~= -1 then
		return false
	end
	assert( elevator.destinationFloor == elevator.currentFloor )
	local currentFloor = elevator.currentFloor ~= 0 and elevator.floors[elevator.currentFloor] or nil
	if IsElevatorMoving( currentFloor ) then
		return false
	end
	return elevator.currentFloor ~= targetFloor
end

local function InitializeEmptyDoorStates( elevator )
	elevator.doorStates = elevator.doorStates or {}
	elevator.pendingDoorStates = elevator.pendingDoorStates or {}
	for floorIndex, _ in pairs( elevator.floors ) do
		if elevator.doorStates[floorIndex] == nil then
			elevator.doorStates[floorIndex] = elevator.currentFloor == floorIndex and elevator.ticksToDestination == -1
		end
	end
end

local function IsElevatorDoorOpen( elevator, floorIndex )
	InitializeEmptyDoorStates( elevator )
	return elevator.doorStates[floorIndex] == true
end

local function SetElevatorDoorOpen( elevator, floorIndex, isOpen )
	InitializeEmptyDoorStates( elevator )
	elevator.doorStates[floorIndex] = isOpen == true
end

function UndergroundElevatorManager.sv_setElevatorDoorOpen( self, elevator, floorIndex, shouldBeOpen )
	local elevatorFloor = elevator and elevator.floors[floorIndex] or nil
	if elevatorFloor == nil then
		return false
	end
	InitializeEmptyDoorStates( elevator )

	if IsElevatorDoorOpen( elevator, floorIndex ) == shouldBeOpen and elevator.pendingDoorStates[floorIndex] == nil then
		return false
	end

	if not IsOpenEventRegistered( elevatorFloor ) then
		elevator.pendingDoorStates[floorIndex] = shouldBeOpen
		return false
	end

	KinematicManager.Sv_Activate( elevatorFloor.tileKey, "opengate01", { tags = { elevatorFloor.connectionTag } } )
	SetElevatorDoorOpen( elevator, floorIndex, shouldBeOpen )
	elevator.pendingDoorStates[floorIndex] = nil
	return true
end

function UndergroundElevatorManager.sv_flushPendingElevatorDoorState( self, elevator, floorIndex )
	local elevatorFloor = elevator and elevator.floors[floorIndex] or nil
	if elevatorFloor == nil then
		return false
	end
	InitializeEmptyDoorStates( elevator )

	local pendingState = elevator.pendingDoorStates[floorIndex]
	if pendingState == nil then
		return false
	end

	if IsElevatorDoorOpen( elevator, floorIndex ) == pendingState then
		elevator.pendingDoorStates[floorIndex] = nil
		return false
	end

	if not IsOpenEventRegistered( elevatorFloor ) then
		return false
	end

	KinematicManager.Sv_Activate( elevatorFloor.tileKey, "opengate01", { tags = { elevatorFloor.connectionTag } } )
	SetElevatorDoorOpen( elevator, floorIndex, pendingState )
	elevator.pendingDoorStates[floorIndex] = nil
	return true
end

local elevatorTagConfig = {
	UNDERGROUND_ELEVATOR_EXCAVATION = {
		prefix = "Excavationelevator - GearLoop",
		positionOffset = sm.vec3.new( 0, 0, 0 ),
		rotationOffset = sm.vec3.new( 0, 0, 0 ),
		lightsFlag = "elevators:elevator_first_lights.activated"
	},
	UNDERGROUND_ELEVATOR_MAIN = {
		prefix = "Excavationelevator - GearLoop",
		positionOffset = sm.vec3.new( 0, 0, 0 ),
		rotationOffset = sm.vec3.new( 180, 180, 0 ),
		lightsFlag = "elevators:elevator_main_lights.activated"
	},
	UNDERGROUND_ELEVATOR_MECHANICSTATION = {
		prefix = "Excavationelevator - ServiceElevatorWalls",
		positionOffset = sm.vec3.new( 0, 0, 0 ),
		rotationOffset = sm.vec3.new( 180, 180, 0 ),
		lightsFlag = "elevators:elevator_service_lights.activated"
	}
}

local function GetElevatorTagConfig( connectionTag )
	return elevatorTagConfig[connectionTag]
end

local function GetElevatorLightsFlag( connectionTag )
	local typeData = GetElevatorTagConfig( connectionTag )
	if typeData and typeData.lightsFlag then
		return typeData.lightsFlag
	end
	return "elevators:elevator_first_lights.activated"
end

function UndergroundElevatorManager.sv_onCellLoaded( self, world, x, y )
	self.loadedCells[CellKey( world, x, y )] = true
end

function UndergroundElevatorManager.sv_onCellUnloaded( self, world, x, y )
	self.loadedCells[CellKey( world, x, y )] = nil
end

function UndergroundElevatorManager.server_onFixedUpdate( self )
    local save = false
	for i = #self.activeElevators, 1, -1 do
		local elevator = self.activeElevators[i]
		local hubFloorIndex = elevator.hubFloor or 1
		local currentFloor = elevator.currentFloor ~= 0 and elevator.floors[elevator.currentFloor] or nil
		local destinationFloor = elevator.floors[elevator.destinationFloor]
		local travelTicks = elevator.travelTicks or ELEVATOR_TRAVEL_TICKS
		local closeDoorTick = travelTicks - ELEVATOR_CLOSE_DOOR_OFFSET
		local moveWallsTick = travelTicks - ELEVATOR_MOVEWALLS_OFFSET
		
		if currentFloor and self:sv_flushPendingElevatorDoorState( elevator, elevator.currentFloor ) then
			save = true
		end
		if destinationFloor and elevator.destinationFloor ~= elevator.currentFloor and self:sv_flushPendingElevatorDoorState( elevator, elevator.destinationFloor ) then
			save = true
		end
		
		local travelDirection = GetElevatorTravelDirection( elevator )
		if currentFloor then
			if elevator.ticksToDestination == closeDoorTick then
				if self:sv_setElevatorDoorOpen( elevator, elevator.currentFloor, false ) then
					save = true
				end
			end
			if elevator.ticksToDestination == moveWallsTick then
				self:sv_activateElevatorEffects( currentFloor.tileKey, currentFloor.world, currentFloor.connectionTag )
				self:sv_activateDepthbot( currentFloor.tileKey, elevator.name, elevator.currentFloor, elevator.destinationFloor )
				self.network:sendToClients( "cl_n_startTravelSound", { world = currentFloor.world, tileKey = currentFloor.tileKey, connection = currentFloor.connectionTag } )
				self.network:sendToClients( "cl_n_startMovingEffects", { world = currentFloor.world, tileKey = currentFloor.tileKey, connection = currentFloor.connectionTag, direction = travelDirection } )

				local departureFloor = elevator.floors[elevator.currentFloor]
				if departureFloor then
					local lightsFlag = GetElevatorLightsFlag( departureFloor.connectionTag )
					SetTileStorageFlag( departureFloor.tileKey, lightsFlag )
					EffectManager.Sv_UpdateTagFilteredEffectsForTile( departureFloor.world, departureFloor.position, { lightsFlag } )
				end
			end
			if elevator.ticksToDestination == ELEVATOR_AUDIO_STOPPING then
				self.network:sendToClients( "cl_n_stopTravelSound", { world = currentFloor.world, tileKey = currentFloor.tileKey, connection = currentFloor.connectionTag } )
			end
		end
		
		if destinationFloor then
			if elevator.ticksToDestination == moveWallsTick then
				self.network:sendToClients( "cl_n_startTravelSound", { world = destinationFloor.world, tileKey = destinationFloor.tileKey, connection = destinationFloor.connectionTag } )
			end
			if elevator.ticksToDestination == ELEVATOR_AUDIO_STOPPING then
				self.network:sendToClients( "cl_n_stopTravelSound", { world = destinationFloor.world, tileKey = destinationFloor.tileKey, connection = destinationFloor.connectionTag } )
			end
			if elevator.ticksToDestination == ELEVATOR_OPEN_DOOR then
				if self:sv_setElevatorDoorOpen( elevator, elevator.destinationFloor, true ) then
					save = true
				end
				
				local arrivedFloor = elevator.floors[elevator.destinationFloor]
				if arrivedFloor then
					local lightsFlag = GetElevatorLightsFlag( arrivedFloor.connectionTag )
					UnsetTileStorageFlag( arrivedFloor.tileKey, lightsFlag )
					EffectManager.Sv_UpdateTagFilteredEffectsForTile( arrivedFloor.world, arrivedFloor.position, { lightsFlag } )
				end
			end
		end
		
		-- Start Fade
		if elevator.ticksToDestination == ELEVATOR_START_FADE then
			if elevator.currentFloor == hubFloorIndex and destinationFloor then
				self:sv_sendFadeToBlackEvent( destinationFloor.portal:getContentsA(), true )
			elseif elevator.currentFloor ~= hubFloorIndex and currentFloor then
				self:sv_sendFadeToBlackEvent( currentFloor.portal:getContentsB(), true )
			end
		end

		if elevator.ticksToDestination == ELEVATOR_LOAD_WORLDS_TICK then
			self:sv_loadWorlds( elevator )
		end

		if elevator.ticksToDestination < ELEVATOR_LOAD_WORLDS_TICK and elevator.ticksToDestination > ELEVATOR_TRANSFER_TICK then
			self:sv_prepareCells( elevator )
		end

		-- Transfer
		if elevator.ticksToDestination == ELEVATOR_TRANSFER_TICK then
			local currentFloorDebug = UNDERGROUND_ELEVATORS[elevator.name].floors[elevator.currentFloor].debug
			local destinationFloorDebug = UNDERGROUND_ELEVATORS[elevator.name].floors[elevator.destinationFloor].debug
			if self:sv_tryTransfer( elevator, elevator.currentFloor, elevator.destinationFloor ) then
				sm.log.info( "Underground elevator '"..elevator.name.."' transferred from floor "..elevator.currentFloor.." ("..currentFloorDebug..") to floor "..elevator.destinationFloor.." ("..destinationFloorDebug..")" )
				for floorIndex, floor in pairs( elevator.floors ) do
					if floorIndex ~= elevator.currentFloor and floorIndex ~= elevator.destinationFloor then
						if self:sv_tryTransfer( elevator, floorIndex, elevator.destinationFloor ) then
							local floorDebug = UNDERGROUND_ELEVATORS[elevator.name].floors[floorIndex].debug
							sm.log.info( "Also transferred floor "..floorIndex.." ("..floorDebug..")" )
						end
					end
				end
				if destinationFloor then
					self:sv_lockDepthbotMarker( destinationFloor.tileKey, elevator.name, elevator.destinationFloor )
				end
			else
				sm.log.info( "Underground elevator '"..elevator.name.."' wants to transfer from floor "..elevator.currentFloor.." ("..currentFloorDebug..") to floor "..elevator.destinationFloor.." ("..destinationFloorDebug..") but destination is not ready, added 1 second" )
				elevator.ticksToDestination = elevator.ticksToDestination + 40
				self:sv_loadWorlds( elevator )
				self:sv_prepareCells( elevator )
			end
			save = true
		end

		-- End Fade
		if elevator.ticksToDestination == ELEVATOR_END_FADE then
			KinematicManager.Sv_ResetTrack( destinationFloor.tileKey, "opengate01", { toBack = false, tags = { destinationFloor.connectionTag } } )

			if elevator.destinationFloor == hubFloorIndex and currentFloor then
				self:sv_sendFadeToBlackEvent( currentFloor.portal:getContentsA(), false )
			elseif elevator.destinationFloor ~= hubFloorIndex and destinationFloor then
				local arrivedContents = destinationFloor.portal:getContentsB()
				self:sv_sendFadeToBlackEvent( arrivedContents, false )
				if TriggerContentsContainsAnyPlayer( arrivedContents ) then
					if elevator.name == "MAIN" and elevator.destinationFloor == ScrapyardFloorIndex then
						-- Arriving at the scrapyard permanently unlocks it for direct selection on every MAIN elevator panel.
						if not elevator.scrapyardUnlocked then
							elevator.scrapyardUnlocked = true
							save = true
						end

						-- special effect for arriving at the scrapyard floor while the scrapyard quest is not completed or active, to hint players that something is wrong with the elevator and to check the scrapyard floor for clues.
						if not QuestManager.Sv_IsQuestComplete( ScrapyardQuestName ) then
							EffectManager.Sv_ActivateEventEffect( destinationFloor.world, "scrapyard_elevator_blockage", destinationFloor.position )
						end
					end
				end
			end
			
			self.network:sendToClients( "cl_n_stopMovingEffects", { world = destinationFloor.world, tileKey = destinationFloor.tileKey, connection = destinationFloor.connectionTag, direction = travelDirection, destinationFloor = elevator.destinationFloor } )

			local arrivedFloor = elevator.floors[elevator.destinationFloor]
			if arrivedFloor then
				local firstLightsFlag = GetElevatorLightsFlag( arrivedFloor.connectionTag )
				SetTileStorageFlag( arrivedFloor.tileKey, firstLightsFlag )
				EffectManager.Sv_UpdateTagFilteredEffectsForTile( arrivedFloor.world, arrivedFloor.position, { firstLightsFlag } )
			end
		end

		-- Quest/dialog triggers (fired a fixed delay after the end fade)
		if elevator.ticksToDestination == ELEVATOR_QUEST_TRIGGER then
			local arrivedContents
			if elevator.destinationFloor == hubFloorIndex and currentFloor then
				arrivedContents = currentFloor.portal:getContentsA()
			elseif elevator.destinationFloor ~= hubFloorIndex and destinationFloor then
				arrivedContents = destinationFloor.portal:getContentsB()
			end
			if arrivedContents then
				if TriggerContentsContainsAnyPlayer( arrivedContents ) then
					QuestManager.Sv_SendEvent( "underground_elevator_used", { elevatorName = elevator.name, floor = elevator.destinationFloor, world = destinationFloor.world, position = destinationFloor.position } )
					if elevator.name == "MAIN" then
						-- Reaching a drill world records a progression milestone and queues its bond builder (flavor) dialog batch.
						local depth = UNDERGROUND_ELEVATORS["MAIN"].floors[elevator.destinationFloor].depth
						ProgressionManager.Sv_SetReachedUndergroundDepth( depth )
						if depth == 4 then
							DialogManager.Sv_QueueBondBuilderBatch( "drill1" )
						elseif depth == 6 then
							DialogManager.Sv_QueueBondBuilderBatch( "drill2" )
						end
					end
					if elevator.name == "MAIN" and elevator.destinationFloor == ScrapyardFloorIndex then
						if not QuestManager.Sv_IsQuestActive( ScrapyardQuestName ) and not QuestManager.Sv_IsQuestComplete( ScrapyardQuestName ) then
							if not elevator.scrapyardDialogStarted then
								QuestManager.Sv_TryAbandonQuest( "quest_vault_3" )
								elevator.scrapyardDialogStarted = true
								save = true
								ActivateQuestThroughDialogBeat( ScrapyardQuestName, ScrapyardQuestDialogBeat )
							end
						end
					end
				end
			end
		end

		-- Countdown
		elevator.ticksToDestination = elevator.ticksToDestination - 1
		if elevator.ticksToDestination < 0 then
			sm.log.info( "Underground elevator '"..elevator.name.."' arrived at floor "..elevator.destinationFloor )
			local arrivedTileKey = elevator.floors[elevator.destinationFloor] and elevator.floors[elevator.destinationFloor].tileKey or (currentFloor and currentFloor.tileKey)
			if arrivedTileKey then
				self:sv_depthbotArrive( arrivedTileKey, elevator.name, elevator.currentFloor, elevator.destinationFloor )
			end
			self:sv_releaseLoadCellHandles( elevator )
			elevator.currentFloor = elevator.destinationFloor
			elevator.ticksToDestination = -1
			table.remove( self.activeElevators, i )
			save = true
		end
	end
	if save then
		self:sv_saveElevators()
	end
end

function UndergroundElevatorManager.sv_loadWorlds( self, elevator )
	if elevator.currentFloor ~= 0 then
		local elevatorCurrentFloor = elevator.floors[elevator.currentFloor]
		if elevatorCurrentFloor and elevatorCurrentFloor.world and not sm.exists( elevatorCurrentFloor.world ) then
			sm.world.loadWorld( elevatorCurrentFloor.world )
		end
	end
	local elevatorDestinationFloor = elevator.floors[elevator.destinationFloor]
	if elevatorDestinationFloor and elevatorDestinationFloor.world and not sm.exists( elevatorDestinationFloor.world ) then
		sm.world.loadWorld( elevatorDestinationFloor.world )
	end
end

function UndergroundElevatorManager.sv_prepareCells( self, elevator )
    if elevator.currentFloor ~= 0 then
        if self.loadCellHandles[elevator.name..elevator.currentFloor] == nil then
			local elevatorCurrentFloor = elevator.floors[elevator.currentFloor]
            if elevatorCurrentFloor and sm.exists( elevatorCurrentFloor.world ) then
        		printf( "Loading current floor cell %s:(%s,%s)", elevatorCurrentFloor.world.id, elevatorCurrentFloor.x, elevatorCurrentFloor.y )
				local handle = elevatorCurrentFloor.world:loadCellWithHandle( elevatorCurrentFloor.x, elevatorCurrentFloor.y, "sv_prepareCellsDone" )
                self.loadCellHandles[elevator.name..elevator.currentFloor] = handle
            end
        end
    end
    if self.loadCellHandles[elevator.name..elevator.destinationFloor] == nil then
		local elevatorDestinationFloor = elevator.floors[elevator.destinationFloor]
        if elevatorDestinationFloor and sm.exists( elevatorDestinationFloor.world ) then
			printf( "Loading destination floor cell %s:(%s,%s)", elevatorDestinationFloor.world.id, elevatorDestinationFloor.x, elevatorDestinationFloor.y )
			local handle = elevatorDestinationFloor.world:loadCellWithHandle( elevatorDestinationFloor.x, elevatorDestinationFloor.y, "sv_prepareCellsDone" )
            self.loadCellHandles[elevator.name..elevator.destinationFloor] = handle
        end
    end
end


function UndergroundElevatorManager.sv_prepareCellsDone( self, world, x, y, params )
	print( "UndergroundElevatorManager.sv_prepareCells DONE!", world, x, y, params )
end

function UndergroundElevatorManager.sv_tryTransfer( self, elevator, fromFloorIndex, toFloorIndex )
	if elevator.currentFloor == 0 then -- First time call
		return true
	end
	local elevatorFromFloor = elevator.floors[fromFloorIndex]
	local elevatorToFloor = elevator.floors[toFloorIndex]
	if not elevatorFromFloor or not elevatorToFloor then
		return false
	end
	
	local cellKeyFrom = CellKey( elevatorFromFloor.world, elevatorFromFloor.x, elevatorFromFloor.y )
	local cellKeyTo = CellKey( elevatorToFloor.world, elevatorToFloor.x, elevatorToFloor.y )

	if sm.exists( elevatorToFloor.world ) and self.loadedCells[cellKeyTo] and sm.exists( elevatorFromFloor.world ) and self.loadedCells[cellKeyFrom] then
		local hubFloorIndex = elevator.hubFloor or 1
		if toFloorIndex == hubFloorIndex then
			elevatorFromFloor.portal:transferBToA()
		elseif fromFloorIndex == hubFloorIndex then
			elevatorToFloor.portal:transferAToB()
		else
			sm.portal.transferBToB( elevatorFromFloor.portal, elevatorToFloor.portal )
		end

		return true
	end
	return false
end

function UndergroundElevatorManager.sv_releaseLoadCellHandles( self, elevator )
    if elevator.currentFloor ~= 0 and self.loadCellHandles[elevator.name..elevator.currentFloor] then
        self.loadCellHandles[elevator.name..elevator.currentFloor]:release()
        self.loadCellHandles[elevator.name..elevator.currentFloor] = nil
    end
    if self.loadCellHandles[elevator.name..elevator.destinationFloor] then
        self.loadCellHandles[elevator.name..elevator.destinationFloor]:release()
        self.loadCellHandles[elevator.name..elevator.destinationFloor] = nil
    end
end

function UndergroundElevatorManager.sv_activateElevatorEffects( self, tileKey, world, connectionTag )
	local tileData = TileStorageManager.Sv_GetValueInSubTable( tileKey, UNDERGROUND_ELEVATOR_TABLE, connectionTag )
	if tileData.elevator and sm.exists( tileData.elevator ) then
		local elevatorPosition = tileData.elevator.shape.worldPosition
		EffectManager.Sv_ActivateEventEffect( world, "ElevatorInside_trigger", elevatorPosition )
	end
end

function UndergroundElevatorManager.sv_activateDepthbot( self, tileKey, elevatorName, currentFloor, destinationFloor )
	if g_tileStorageManager then
		local depthBotsGo = function( depthbots )
			if depthbots then
				for _,depthbot in ipairs( depthbots ) do
					if sm.exists( depthbot ) then
						if destinationFloor > currentFloor then
							sm.event.sendToInteractable( depthbot, "sv_e_goDown" )
						else
							sm.event.sendToInteractable( depthbot, "sv_e_goUp" )
						end
					end
				end
			end
		end
		if currentFloor ~= 0 then
			local elevatorFloor = UNDERGROUND_ELEVATORS[elevatorName].floors[currentFloor]
			local tileData = TileStorageManager.Sv_GetValueInSubTable( tileKey, UNDERGROUND_ELEVATOR_TABLE, elevatorFloor.connectionTag ) or {}
			depthBotsGo( tileData.depthbots )
		end
		local elevatorFloor = UNDERGROUND_ELEVATORS[elevatorName].floors[destinationFloor]
		local tileData = TileStorageManager.Sv_GetValueInSubTable( tileKey, UNDERGROUND_ELEVATOR_TABLE, elevatorFloor.connectionTag ) or {}
		depthBotsGo( tileData.depthbots )
	end
end

function UndergroundElevatorManager.sv_lockDepthbotMarker( self, tileKey, elevatorName, floor )
	if g_tileStorageManager then
		local elevatorFloor = UNDERGROUND_ELEVATORS[elevatorName].floors[floor]
		local tileData = TileStorageManager.Sv_GetValueInSubTable( tileKey, UNDERGROUND_ELEVATOR_TABLE, elevatorFloor.connectionTag ) or {}
		if tileData and tileData.depthbots then
			for _, depthbot in ipairs( tileData.depthbots  ) do
				if sm.exists( depthbot ) then
					sm.event.sendToInteractable( depthbot, "sv_e_setMarkerLocked", { markerLocked = true }, sm.event.types.instant )
				end
			end
		end
	end
end

function UndergroundElevatorManager.sv_depthbotArrive( self, tileKey, elevatorName, currentFloor, destinationFloor )
	if g_tileStorageManager then
		local depthBotsArrive = function( depthbots )
			if depthbots then
				for _, depthbot in ipairs( depthbots ) do
					if sm.exists( depthbot ) then
						sm.event.sendToInteractable( depthbot, "sv_e_arrived" )
					end
				end
			end
		end
		if currentFloor ~= 0 then
			local elevatorFloor = UNDERGROUND_ELEVATORS[elevatorName].floors[currentFloor]
			local tileData = TileStorageManager.Sv_GetValueInSubTable( tileKey, UNDERGROUND_ELEVATOR_TABLE, elevatorFloor.connectionTag ) or {}
			depthBotsArrive( tileData.depthbots )
		end
		local elevatorFloor = UNDERGROUND_ELEVATORS[elevatorName].floors[destinationFloor]
		local tileData = TileStorageManager.Sv_GetValueInSubTable( tileKey, UNDERGROUND_ELEVATOR_TABLE, elevatorFloor.connectionTag ) or {}
		depthBotsArrive( tileData.depthbots )
	end
end

function UndergroundElevatorManager.sv_sendFadeToBlackEvent( self, contents, start )
	if contents == nil then
		return
	end
	for _,object in ipairs( contents ) do
		if type( object ) == "Character" and sm.exists( object ) then
			local player = object:getPlayer()
			if player then
				if start then
					sm.event.sendToPlayer( player, "sv_startFadeToBlack", { duration = ELEVATOR_FADE_DURATION, timeout = ELEVATOR_FADE_TIMEOUT } )
				else
					sm.event.sendToPlayer( player, "sv_endFadeToBlack", { duration = ELEVATOR_FADE_DURATION } )
				end
			end
		end
	end
end

function UndergroundElevatorManager.sv_e_failsafeLoadCell( self, params )
	local elevator = self.elevators[params.elevatorName]
	assert( elevator )
	local elevatorTargetFloor = elevator.floors[params.targetFloor]
	sm.log.info( "Loading cell "..tostring(elevatorTargetFloor.x)..", "..tostring(elevatorTargetFloor.y).." for transfering to floor "..params.targetFloor )
	self.failsafeHandles = self.failsafeHandles or {}
	params.handleIndex = #self.failsafeHandles + 1
	if elevatorTargetFloor and elevatorTargetFloor.world and not sm.exists( elevatorTargetFloor.world ) then
		sm.world.loadWorld( elevatorTargetFloor.world )
	end
	local handle = elevatorTargetFloor.world:loadCellWithHandle( elevatorTargetFloor.x, elevatorTargetFloor.y, "sv_failsafeTransfer", params )
	self.failsafeHandles[params.handleIndex] = handle
end

function UndergroundElevatorManager.sv_failsafeTransfer( self, world, x, y, params )
	local elevator = self.elevators[params.elevatorName]
	assert( elevator )
	sm.log.info( "Cell "..x..", "..y.." loaded. Trying to transfer from  "..params.currentFloor.." to "..params.targetFloor )
	if self:sv_tryTransfer( elevator, params.currentFloor, params.targetFloor ) then
		sm.log.info( "Failsafe transfer successful!" )
	else
		sm.log.info( "Failsafe transfer failed..." )
	end
	self.failsafeHandles[params.handleIndex]:release()
	self.failsafeHandles[params.handleIndex] = nil
end

function UndergroundElevatorManager.Sv_TryFailSafeTransfer( elevatorName, fromFloor )
	if g_undergroundElevatorManager then
		local elevator = g_undergroundElevatorManager.elevators[elevatorName]
		if elevator and fromFloor and fromFloor ~= elevator.currentFloor then
			local moving = elevator.ticksToDestination ~= -1
			local alreadyArriving = moving and elevator.destinationFloor == fromFloor
			if not alreadyArriving then
				sm.log.info( "Underground elevator '"..elevatorName.."' used from floor "..fromFloor.." but is at floor "..elevator.currentFloor.."." )
				if elevator.currentFloor ~= 0 and elevator.floors[fromFloor] and elevator.floors[elevator.currentFloor] then
					sm.log.info( "Elevator '"..elevatorName.."' initiating failsafe transfer from floor "..fromFloor.." to floor "..elevator.currentFloor.."." )
					local params = { elevatorName = elevatorName, currentFloor = fromFloor, targetFloor = elevator.currentFloor }
					sm.event.sendToScriptableObject( g_undergroundElevatorManager.scriptableObject, "sv_e_failsafeLoadCell", params, sm.event.types.instant )
					return true
				end
			end
		end
	end
	return false
end

function UndergroundElevatorManager.sv_go( self, elevatorName, currentFloor, targetFloor )
	local elevator = self.elevators[elevatorName]
	assert( elevator )
	if currentFloor and currentFloor ~= elevator.currentFloor then
		UndergroundElevatorManager.Sv_TryFailSafeTransfer( elevatorName, currentFloor )
		return false
	end

	if elevator.ticksToDestination == -1 then -- Not on the move
		assert( elevator.destinationFloor == elevator.currentFloor )
		if CanElevatorGo( elevator, targetFloor ) then
			elevator.destinationFloor = targetFloor
			if elevator.currentFloor == 0 then
				elevator.ticksToDestination = ELEVATOR_OPEN_DOOR
			elseif elevatorName == "MAIN" and targetFloor == BossLobbyFloorIndex then
				-- First descent to the boss floor is a long, dramatic ride; every later ride takes half as long.
				if elevator.bossRideTaken then
					elevator.ticksToDestination = BOSS_ELEVATOR_TRAVEL_TICKS_REPEAT
				else
					elevator.ticksToDestination = BOSS_ELEVATOR_TRAVEL_TICKS_FIRST
					elevator.bossRideTaken = true
				end
			else
				elevator.ticksToDestination = ELEVATOR_TRAVEL_TICKS
			end
			-- Remember the full ride length so the departure-anchored events (door close, walls)
			-- can be timed relative to the start regardless of how long the ride is.
			elevator.travelTicks = elevator.ticksToDestination
			-- Notify quests that the elevator has departed, mirroring the arrival
			-- "underground_elevator_used" event so a quest can schedule mid-ride dialog.
			if elevator.currentFloor ~= 0 then
				local departureFloor = elevator.floors[elevator.currentFloor]
				-- Immediately lock the depthbot markers so pressing "go" gives instant feedback. The
				-- direction submesh swaps still happen later at moveWallsTick via sv_activateDepthbot.
				if departureFloor then
					self:sv_lockDepthbotMarker( departureFloor.tileKey, elevator.name, elevator.currentFloor )
				end
				QuestManager.Sv_SendEvent( "underground_elevator_departed", {
					elevatorName = elevator.name,
					currentFloor = elevator.currentFloor,
					destinationFloor = targetFloor,
					world = departureFloor and departureFloor.world or nil,
					position = departureFloor and departureFloor.position or nil
				} )
			end
			addToArrayIfNotExists( self.activeElevators, self.elevators[elevatorName] )
			return true
		else
			if elevator.currentFloor == targetFloor then
				sm.log.info( "Underground elevator already at floor "..targetFloor )
			else
				sm.log.info( "Waiting for kinematic animation" )
			end
		end
	else
		sm.log.info( "Underground elevator is already moving to floor "..elevator.destinationFloor )
	end
	return false
end

function UndergroundElevatorManager.sv_canGo( self, elevatorName, targetFloor )
	local elevator = self.elevators[elevatorName]
	if elevator == nil then
		return false
	end
	return CanElevatorGo( elevator, targetFloor )
end

function UndergroundElevatorManager.sv_isDoorOpen( self, elevatorName, floorIndex )
	local elevator = self.elevators[elevatorName]
	if elevator == nil then
		return false
	end
	return IsElevatorDoorOpen( elevator, floorIndex )
end

function UndergroundElevatorManager.sv_isScrapyardUnlocked( self, elevatorName )
	local elevator = self.elevators[elevatorName]
	return elevator ~= nil and elevator.scrapyardUnlocked == true
end

function UndergroundElevatorManager.sv_registerElevatorFloor( self, elevatorName, floor, world, worldPos, connectionTag, transferArea )
	local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, worldPos )
	if tileKey == nil then
		sm.log.error( "UndergroundElevatorManager.sv_registerElevatorFloor could not calculate tile storage key for position: " .. tostring( worldPos ) .. " in world: " .. tostring( world.id ) )
		return
	end
	sm.log.info( "Registering elevator: name", elevatorName, "floor", floor, "world", world, "worldPos", worldPos, "tileKey", tileKey, "connectionTag", connectionTag, "transferArea", transferArea )
	self.elevators[elevatorName] = self.elevators[elevatorName] or {
		name = elevatorName,
		floors = {},
		hubFloor = UNDERGROUND_ELEVATORS[elevatorName].hubFloor,
		currentFloor = 0,
		destinationFloor = 0,
		ticksToDestination = -1, -- At destination
		size = transferArea.scale / 2,
		loadDestinationQueue = {}
	}
	local elevator = self.elevators[elevatorName]
	local elevatorFloor = elevator.floors[floor]
	if elevatorFloor then
		sm.log.info( "Elevator floor already registered" )
	else
		local x = math.floor( worldPos.x / 64 )
		local y = math.floor( worldPos.y / 64 )
		elevatorFloor = { world = world, x = x, y = y, tileKey = tileKey, connectionTag = connectionTag, position = transferArea.position, rotation = transferArea.rotation }
		local hubFloorIndex = elevator.hubFloor or 1
		if floor ~= hubFloorIndex then
			elevatorFloor.portal = sm.portal.createPortal( elevator.size )
			elevatorFloor.portal:setOpeningB( transferArea.position, transferArea.rotation, world )
			local hubFloor = elevator.floors[hubFloorIndex]
			if hubFloor then
				elevatorFloor.portal:setOpeningA( hubFloor.position, hubFloor.rotation, hubFloor.world )
			end
		elseif floor == hubFloorIndex then
			for _,elevatorFloor in pairs( elevator.floors ) do
				if elevatorFloor.portal then
					elevatorFloor.portal:setOpeningA( transferArea.position, transferArea.rotation, world )
				end
			end
		end
		elevator.floors[floor] = elevatorFloor
	end

	InitializeEmptyDoorStates( elevator )
	self:sv_flushPendingElevatorDoorState( elevator, floor )
	if elevator.ticksToDestination == -1 then
		for floorIndex, _ in pairs( elevator.floors ) do
			SetElevatorDoorOpen( elevator, floorIndex, elevator.currentFloor == floorIndex )
			elevator.pendingDoorStates[floorIndex] = nil
		end
	end
	
	self:sv_saveElevators()
end

------------------------------ CLIENT ----------------------------------

function UndergroundElevatorManager.cl_getElevatorEffectData( self, areaNode )
	local defaultPrefix = "Excavationelevator"
	local defaultOffset = sm.vec3.new( 0, 0, 0 )
	local defaultRotationOffset = sm.vec3.new( 0, 0, 0 )
	for tag, data in pairs( elevatorTagConfig ) do
		if isAnyOf( tag, areaNode.tags ) then
			return data.prefix, data.positionOffset, data.rotationOffset
		end
	end
	return defaultPrefix, defaultOffset, defaultRotationOffset
end

function UndergroundElevatorManager.cl_onCellLoaded( self, world, x, y )
	local elevatorAreas = sm.cell.getNodesByTag( x, y, "UNDERGROUND_ELEVATOR_AREA", world )
	for _, areaNode in ipairs( elevatorAreas ) do
		local foundTags = intersection( areaNode.tags, UNDERGROUND_CONNECTIONS )
		if #foundTags == 1 then
			local tileKey = TileStorageManager.Cl_GetTileStorageKeyFromPosition( world, areaNode.position )
			if tileKey then
				self.cl.areas = self.cl.areas or {}
				self.cl.areas[world.id] = self.cl.areas[world.id] or {}
				self.cl.areas[world.id][tileKey] = self.cl.areas[world.id][tileKey] or {}
				if not self.cl.areas[world.id][tileKey][foundTags[1]] then
					local effectPrefix, positionOffset, rotationOffset = self:cl_getElevatorEffectData( areaNode )
					local effectPosition = areaNode.position + positionOffset
					local effectRotation = sm.quat.fromEuler( rotationOffset )
				
					local insideTrigger = sm.areaTrigger.createBox( areaNode.scale / 2, areaNode.position, areaNode.rotation, sm.areaTrigger.filter.character )
					insideTrigger:bindOnEnter( "cl_trigger_enterElevator", self )
					insideTrigger:bindOnExit( "cl_trigger_exitElevator", self )
					local elevator = {
						insideNode = areaNode,
						insideTrigger = insideTrigger,
						outsideSoundEffect = sm.effect.createEffect( "Excavationelevator - TravelOutside" ),
						staticEffect = sm.effect.createEffect( effectPrefix ),
						upStartEffect = sm.effect.createEffect( effectPrefix .. "_UpStart" ),
						upStopEffect = sm.effect.createEffect( effectPrefix .. "_UpStop" ),
						downStartEffect = sm.effect.createEffect( effectPrefix .. "_DownStart" ),
						downStopEffect = sm.effect.createEffect( effectPrefix .. "_DownStop" )
					}
					elevator.outsideSoundEffect:setPosition( areaNode.position )
					elevator.outsideSoundEffect:setWorld( areaNode.world )

					elevator.staticEffect:setRotation( effectRotation )
					elevator.staticEffect:setPosition( effectPosition )
					elevator.staticEffect:setWorld( areaNode.world )
					elevator.staticEffect:start()

					elevator.upStartEffect:setRotation( effectRotation )
					elevator.upStartEffect:setPosition( effectPosition )
					elevator.upStartEffect:setWorld( areaNode.world )
					elevator.upStopEffect:setRotation( effectRotation )
					elevator.upStopEffect:setPosition( effectPosition )
					elevator.upStopEffect:setWorld( areaNode.world )
					
					elevator.downStartEffect:setRotation( effectRotation )
					elevator.downStartEffect:setPosition( effectPosition )
					elevator.downStartEffect:setWorld( areaNode.world )
					elevator.downStopEffect:setRotation( effectRotation )
					elevator.downStopEffect:setPosition( effectPosition )
					elevator.downStopEffect:setWorld( areaNode.world )

					self.cl.areas[world.id][tileKey][foundTags[1]] = elevator
					self.cl.triggers[insideTrigger.id] = elevator
				end
			end
		elseif #foundTags == 0 then
			sm.log.error( "No elevator connection tags found on the UNDERGROUND_ELEVATOR_AREA node" )
			sm.log.error( "Node:", areaNode )
		else
			sm.log.error( "Multiple elevator connection tags found on the same UNDERGROUND_ELEVATOR_AREA node" )
			sm.log.error( "Node:", areaNode )
		end
	end
end

function UndergroundElevatorManager.client_onCreate( self )
	g_undergroundElevatorManagerClient = self
	self.cl = {}
	self.cl.triggers = {}
	self.cl.areas = {}

	self.cl.insideSoundEffect2D = sm.effect.createEffect2D( "Excavationelevator - TravelInside" )
	self.cl.ambienceSoundEffect2D = sm.effect.createEffect2D( "Excavationelevator - Ambiance" )
end

function UndergroundElevatorManager.client_onDestroy( self )
	self.cl.insideSoundEffect2D:destroy()
	self.cl.ambienceSoundEffect2D:destroy()
	for _, elevator in pairs( self.cl.triggers ) do
		elevator.outsideSoundEffect:destroy()
		elevator.staticEffect:destroy()
		elevator.upStartEffect:destroy()
		elevator.upStopEffect:destroy()
		elevator.downStartEffect:destroy()
		elevator.downStopEffect:destroy()	
	end
end

function UndergroundElevatorManager.cl_trigger_enterElevator( self, trigger, results )
    if TriggerResultContainsLocalPlayer( results ) then
		print( "Entered elevator trigger" )
		local elevator = self.cl.triggers[trigger.id]
		if elevator then
			self.cl.ambienceSoundEffect2D:start()

			if elevator.isMoving then
				if not self.cl.insideSoundEffect2D:isPlaying() then
					self.cl.insideSoundEffect2D:start()
				end
				if elevator.outsideSoundEffect:isPlaying() then
					elevator.outsideSoundEffect:stop()
				end
			end
		end
    end
end

function UndergroundElevatorManager.cl_trigger_exitElevator( self, trigger, results )
    if TriggerResultContainsLocalPlayer( results ) then
		print( "Exited elevator trigger" )
		local elevator = self.cl.triggers[trigger.id]
		if elevator then
			self.cl.ambienceSoundEffect2D:stopBreakSustain()

			if self.cl.insideSoundEffect2D:isPlaying() then
				self.cl.insideSoundEffect2D:stop()
			end
			if elevator.isMoving then
				elevator.outsideSoundEffect:start()
			end
		end
    end
end

function UndergroundElevatorManager.cl_n_startTravelSound( self, params )
	local elevator = nil
	if self.cl.areas[params.world.id] then
		if self.cl.areas[params.world.id][params.tileKey] then
			elevator = self.cl.areas[params.world.id][params.tileKey][params.connection]
			if elevator then
				elevator.isMoving = true
				local triggerContent = elevator.insideTrigger:getContents()
				if TriggerContentsContainsLocalPlayer( triggerContent ) then
					self.cl.insideSoundEffect2D:start()
				else
					elevator.outsideSoundEffect:start() --TODO FIX NOWORLD SCRIPT
				end
			end
		end
	end
end

function UndergroundElevatorManager.cl_n_stopTravelSound( self, params )
	local elevator = nil
	if self.cl.areas[params.world.id] then
		if self.cl.areas[params.world.id][params.tileKey] then
			elevator = self.cl.areas[params.world.id][params.tileKey][params.connection]
			if elevator then
				elevator.isMoving = false
				if self.cl.insideSoundEffect2D:isPlaying() then
					self.cl.insideSoundEffect2D:stopBreakSustain()
				end
				if elevator.outsideSoundEffect:isPlaying() then
					elevator.outsideSoundEffect:stopBreakSustain()
				end
			end
		end
	end
end

function UndergroundElevatorManager.cl_n_startMovingEffects( self, params )
	local elevator = nil
	if self.cl.areas[params.world.id] then
		if self.cl.areas[params.world.id][params.tileKey] then
			elevator = self.cl.areas[params.world.id][params.tileKey][params.connection]
			if elevator then
				elevator.staticEffect:stop()
				elevator.upStopEffect:stop()
				elevator.downStopEffect:stop()
				if params.direction == "up" then
					elevator.upStartEffect:start()
					elevator.downStartEffect:stop()
				elseif params.direction == "down" then
					elevator.downStartEffect:start()
					elevator.upStartEffect:stop()
				end
			end
		end
	end
end

function UndergroundElevatorManager.cl_n_stopMovingEffects( self, params )
	local elevator = nil
	if self.cl.areas[params.world.id] then
		if self.cl.areas[params.world.id][params.tileKey] then
			elevator = self.cl.areas[params.world.id][params.tileKey][params.connection]
			if elevator then
				elevator.staticEffect:stop()
				elevator.upStartEffect:stop()
				elevator.downStartEffect:stop()
				if params.direction == "up" then
					elevator.upStopEffect:start()
					elevator.downStopEffect:stop()
				elseif params.direction == "down" then
					elevator.downStopEffect:start()
					elevator.upStopEffect:stop()
					if params.destinationFloor == 2 and ( params.connection == "UNDERGROUND_ELEVATOR_MAIN" or params.connection == "UNDERGROUND_ELEVATOR_MECHANICSTATION" ) and TriggerContentsContainsLocalPlayer( elevator.insideTrigger:getContents() ) then
						local world = elevator.insideTrigger:getWorld()
						sm.effect.playEffect( "audio:event:/music/minehub", nil, nil, nil, nil, nil, nil, world )
					end
				end
			end
		end
	end
end

function UndergroundElevatorManager.sv_checkLoadDestinationQueue( self, world )
	local elevatorLocations = sm.storage.load( STORAGE_CHANNEL_ELEVATOR_LOCATIONS ) or {}
	if elevatorLocations[world.id] then
		for _,locationNode in ipairs( elevatorLocations[world.id] ) do
			local isDestinationNode = function( destination )
				return destination.world == world and isAnyOf( destination.connectionTag, locationNode.tags )
			end
			for _,elevator in pairs( self.elevators ) do
				local idx = indexOf( elevator.loadDestinationQueue, isDestinationNode )
				if idx then
					local x = math.floor( locationNode.pos.x / 64 )
					local y = math.floor( locationNode.pos.y / 64 )
					print( "Loading destination world cell from location node", locationNode )
					if self.loadCellHandles[elevator.name..elevator.destinationFloor] == nil then
						self.loadCellHandles[elevator.name..elevator.destinationFloor] = world:loadCellWithHandle( x, y, "sv_checkLoadDestinationQueueDone", nil, self )
						table.remove( elevator.loadDestinationQueue, idx )
					end
				end
			end
		end
	end
end

function UndergroundElevatorManager.sv_checkLoadDestinationQueueDone( self, world, x, y, params )
	print( "UndergroundElevatorManager.sv_checkLoadDestinationQueue DONE!", world, x, y, params )
end

function UndergroundElevatorManager.sv_loadDestinationWorldCell( self, world, elevatorName, connectionTag )
	local elevator = self.elevators[elevatorName]
	if elevator then
		elevator.loadDestinationQueue[#elevator.loadDestinationQueue + 1] = { world = world, connectionTag = connectionTag }
		self:sv_checkLoadDestinationQueue( world )
	end
end

function UndergroundElevatorManager.Sv_LoadDestinationWorldCell( world, elevatorName, connectionTag )
	if g_undergroundElevatorManager then
		g_undergroundElevatorManager:sv_loadDestinationWorldCell( world, elevatorName, connectionTag )
	end
end

function UndergroundElevatorManager.Sv_OnTerrainLoaded( world )
	if g_undergroundElevatorManager then
		g_undergroundElevatorManager:sv_checkLoadDestinationQueue( world )
	end
end

function UndergroundElevatorManager.Sv_OnCellLoaded( world, x, y )
	if g_undergroundElevatorManager then
		g_undergroundElevatorManager:sv_onCellLoaded( world, x, y )
	end
end

function UndergroundElevatorManager.Sv_OnCellUnloaded( world, x, y )
	if g_undergroundElevatorManager then
		g_undergroundElevatorManager:sv_onCellUnloaded( world, x, y )
	end
end

function UndergroundElevatorManager.Cl_OnCellLoaded( world, x, y )
	if g_undergroundElevatorManagerClient then
		g_undergroundElevatorManagerClient:cl_onCellLoaded( world, x, y )
	end
end

function UndergroundElevatorManager.Sv_Go( elevatorName, currentFloor, targetFloor )
	sm.log.info( "Underground elevator '"..elevatorName.."' go from floor "..currentFloor.." to floor "..targetFloor )
	if g_undergroundElevatorManager then
		return g_undergroundElevatorManager:sv_go( elevatorName, currentFloor, targetFloor )
	end
	return false
end

function UndergroundElevatorManager.Sv_CanGo( elevatorName, targetFloor )
	if g_undergroundElevatorManager then
		return g_undergroundElevatorManager:sv_canGo( elevatorName, targetFloor )
	end
	return false
end

function UndergroundElevatorManager.Sv_IsDoorOpen( elevatorName, floorIndex )
	if g_undergroundElevatorManager then
		return g_undergroundElevatorManager:sv_isDoorOpen( elevatorName, floorIndex )
	end
	return false
end

function UndergroundElevatorManager.Sv_IsScrapyardUnlocked( elevatorName )
	if g_undergroundElevatorManager then
		return g_undergroundElevatorManager:sv_isScrapyardUnlocked( elevatorName )
	end
	return false
end

function UndergroundElevatorManager.Sv_Call( elevatorName, floor )
	sm.log.info( "Underground elevator '"..elevatorName.."' called from floor "..floor )
	if g_undergroundElevatorManager then
		return g_undergroundElevatorManager:sv_go( elevatorName, nil, floor )
	end
	return false
end

function UndergroundElevatorManager.Sv_RegisterElevatorFloor( elevatorName, floor, world, worldPos, connectionTag, transferArea )
	if g_undergroundElevatorManager then
		g_undergroundElevatorManager:sv_registerElevatorFloor( elevatorName, floor, world, worldPos, connectionTag, transferArea )
	end
end

function UndergroundElevatorManager.Sv_GetFloorPosition( elevatorName, floor )
	if g_undergroundElevatorManager then
		local elevator = g_undergroundElevatorManager.elevators[elevatorName]
		if elevator and elevator.floors[floor] then
			return elevator.floors[floor].position
		end
	end
	return nil
end

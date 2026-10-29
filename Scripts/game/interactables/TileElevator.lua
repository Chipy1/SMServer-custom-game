dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

TileElevator = class()
TileElevator.maxParentCount = 255
TileElevator.maxChildCount = 255
TileElevator.connectionInput = sm.interactable.connectionType.logic
TileElevator.connectionOutput = sm.interactable.connectionType.logic + sm.interactable.connectionType.power

-- Timing constants (same as warehouse elevator)
local ELEVATOR_TRAVEL_TICKS = 680
local ELEVATOR_MOVEWALLS_TICK = ELEVATOR_TRAVEL_TICKS - 60
local ELEVATOR_TRANSFER_TICK = 120
local ELEVATOR_START_FADE = ELEVATOR_TRANSFER_TICK + 40 -- Sometime before transfer
local ELEVATOR_END_FADE = 40 -- Before doors open

local ELEVATOR_FADE_TIMEOUT = ELEVATOR_START_FADE * ( 1.0 / 40.0 ) + 5.0
local ELEVATOR_FADE_DURATION = 0.45

local PORTAL_SIZE = sm.vec3.new( 1.75, 1.75, 3.0 ) - sm.vec3.new( 0.05, 0.05, 0.05 )
local ELEVATOR_PORTAL_OFFSET = sm.vec3.new( 0, 1.875, 0 )

local TRASHBOT_CONNECTION = "TILE_ELEVATOR_TRASHBOT_CONNECTION"

local function floorToLetter( floorIndex )
	return floorIndex == 1 and "a" or "b"
end

function TileElevator.sv_saveSharedData( self, data )
	TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, TILE_ELEVATOR_TABLE, self.sv.connectionName, data )
	TileStorageManager.Sv_Save()
end

-- Server

function TileElevator.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()

	if not self.sv.saved then
		self.sv.saved = {}

		if self.params then
			-- Params set externally (e.g. by a cell-load hook)
			self.sv.saved.connectionName = self.params.connectionName
			self.sv.saved.floorIndex = self.params.floorIndex
		else
			-- Derive from instance tags: expects { "TILE_ELEVATOR", "<connectionName>", "FLOOR_1" or "FLOOR_2" }
			local connectionName = nil
			local floorIndex = nil
			local knownTags = { TILE_ELEVATOR = true, FLOOR_1 = true, FLOOR_2 = true, SCRAPYARD_PLAYERS_PRESENT = true }
			for _, tag in ipairs( self.tags ) do
				if tag == "FLOOR_1" then
					floorIndex = 1
				elseif tag == "FLOOR_2" then
					floorIndex = 2
				elseif not knownTags[tag] then
					assert( connectionName == nil, "TileElevator: multiple connection name tags found" )
					connectionName = tag
				end
                print( "TileElevator: tag " .. tag )
			end
			assert( connectionName, "TileElevator: missing connection name tag" )
			assert( floorIndex, "TileElevator: missing FLOOR_1 or FLOOR_2 tag" )
			self.sv.saved.connectionName = connectionName
			self.sv.saved.floorIndex = floorIndex
		end
		self.storage:save( self.sv.saved )
	end

	local world = sm.world.getCurrentWorld()
	local position = self.shape.worldPosition + self.shape.worldRotation * ELEVATOR_PORTAL_OFFSET

	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	self.sv.connectionName = self.sv.saved.connectionName
	self.sv.floorIndex = self.sv.saved.floorIndex

	-- Register in shared tileStorage
	local data = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, TILE_ELEVATOR_TABLE, self.sv.connectionName ) or {
		currentFloor = 1,
		destinationFloor = 0,
		ticksToDestination = -1,
		portal = nil
	}
	data.floors = data.floors or {}
	data.floors[self.sv.floorIndex] = {
		interactable = self.interactable,
		position = position,
		rotation = self.shape.worldRotation
	}

	-- Create portal when both floors are registered
	if data.floors[1] and data.floors[2] then
		if not data.portal then
			data.portal = sm.portal.createPortal( PORTAL_SIZE )
			print( "TileElevator: Created portal " .. data.portal.id .. " for " .. self.sv.connectionName )
            data.portal:setOpeningA( data.floors[1].position, data.floors[1].rotation, world )
            data.portal:setOpeningB( data.floors[2].position, data.floors[2].rotation, world )
		end
	end

	self:sv_saveSharedData( data )

	self.interactable:setPublicData( {
		portalHalfSize = PORTAL_SIZE,
		portalPosition = position,
		portalRotation = self.shape.worldRotation
	} )

	self.sv.elevatorPanelButton = nil
	self.sv.elevatorCallButton = nil
	for _, parent in ipairs( self.interactable:getParents() ) do
		local uid = parent.shape.shapeUuid
		if uid == obj_survivalobject_elevatorbutton then
			self.sv.elevatorPanelButton = parent
		elseif uid == obj_survivalobject_elevatorcallbutton then
			self.sv.elevatorCallButton = parent
		end
	end

	self.sv.lastActiveState = self.interactable:isActive()
	self.sv.prevPower = self.interactable.power
end

function TileElevator.server_onFixedUpdate( self )
	local data = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, TILE_ELEVATOR_TABLE, self.sv.connectionName )
	if not data or not data.portal then return end

	local elevatorPanelButton = self.sv.elevatorPanelButton
	local elevatorCallButton = self.sv.elevatorCallButton

	-- Handle button presses (either floor can initiate)
	if elevatorPanelButton and elevatorPanelButton:isActive() then
		if not data.disabled then
			self:sv_panelButtonPressed( data )
		end
		elevatorPanelButton:setActive( false )
	end

	if elevatorCallButton and elevatorCallButton:isActive() then
		if not data.disabled then
			self:sv_callButtonPressed( data )
		end
		elevatorCallButton:setActive( false )
	end

	-- Floor 1 drives the tick sequence and door state
	if self.sv.floorIndex == 1 then
		if data.ticksToDestination > 0 then
			self:sv_tickElevator( data )
		else
			self:sv_setIdleDoorState( data )
		end
	end

	-- Update call button display
	if elevatorCallButton then
		local callbuttonData = elevatorCallButton:getPublicData()
		if callbuttonData then
			if data.disabled then
				callbuttonData.destination = ""
				callbuttonData.ticksToDestination = 0
				callbuttonData.elevatorHome = nil
			elseif data.ticksToDestination > 0 then
				callbuttonData.destination = floorToLetter( data.destinationFloor )
				callbuttonData.ticksToDestination = data.ticksToDestination
			else
				callbuttonData.destination = floorToLetter( data.currentFloor )
				callbuttonData.ticksToDestination = 0
			end
			if not data.disabled then
				callbuttonData.elevatorHome = floorToLetter( data.currentFloor )
			end
		end
	end

	-- Both floors track their own state changes for client sound events
	self:sv_updateClientEvents()
end

function TileElevator.sv_panelButtonPressed( self, data )
	if data.ticksToDestination > 0 then return end

	local targetFloor = 3 - self.sv.floorIndex

	if data.currentFloor == self.sv.floorIndex then
		-- Normal: elevator is here, send to other floor
		data.destinationFloor = targetFloor
		data.ticksToDestination = ELEVATOR_TRAVEL_TICKS
		self:sv_saveSharedData( data )
	elseif data.currentFloor ~= 0 then
		-- Wrong location: elevator is at the other floor, short trip
		data.destinationFloor = targetFloor
		data.ticksToDestination = ELEVATOR_TRANSFER_TICK + 40
		local floor = data.floors[self.sv.floorIndex]
		if floor and floor.interactable and sm.exists( floor.interactable ) then
			floor.interactable:setPower( self.sv.floorIndex == 1 and 1 or -1 )
		end
		self:sv_saveSharedData( data )
		print( "TileElevator: Pressed at wrong location, going to floor " .. targetFloor )
	end
end

function TileElevator.sv_callButtonPressed( self, data )
	if data.ticksToDestination > 0 then return end
	if data.currentFloor == self.sv.floorIndex then return end

	data.destinationFloor = self.sv.floorIndex
	data.ticksToDestination = ELEVATOR_TRAVEL_TICKS
	self:sv_saveSharedData( data )
	print( "TileElevator: Called to floor " .. self.sv.floorIndex )
end

function TileElevator.sv_setIdleDoorState( self, data )
	for i = 1, 2 do
		local floor = data.floors[i]
		if floor and floor.interactable and sm.exists( floor.interactable ) then
			floor.interactable.active = data.currentFloor == i
			floor.interactable:setPower( 0 )
		end
	end
end

function TileElevator.sv_tickElevator( self, data )
	local save = false

	-- Move walls
	if data.ticksToDestination == ELEVATOR_MOVEWALLS_TICK then
		local floor1 = data.floors[1]
		if floor1 and floor1.interactable and sm.exists( floor1.interactable ) then
			floor1.interactable:setPower( data.destinationFloor == 1 and -1 or 1 )
		end
		local floor2 = data.floors[2]
		if floor2 and floor2.interactable and sm.exists( floor2.interactable ) then
			floor2.interactable:setPower( data.destinationFloor == 2 and 1 or -1 )
		end
	end

	-- Start Fade
	if data.ticksToDestination == ELEVATOR_START_FADE then
		if data.destinationFloor == 2 then
			TileElevator.sv_sendFadeToBlackEvent( data.portal:getContentsA(), true )
		elseif data.destinationFloor == 1 then
			TileElevator.sv_sendFadeToBlackEvent( data.portal:getContentsB(), true )
		end
	end

	-- Transfer
	if data.ticksToDestination == ELEVATOR_TRANSFER_TICK then
		print( "TileElevator: Transferring to floor " .. data.destinationFloor )
		if data.destinationFloor == 2 then
			data.portal:transferAToB()
		elseif data.destinationFloor == 1 then
			data.portal:transferBToA()
		end
		save = true
	end

	-- End Fade
	if data.ticksToDestination == ELEVATOR_END_FADE then
		if data.destinationFloor == 1 then
			TileElevator.sv_sendFadeToBlackEvent( data.portal:getContentsA(), false )
		elseif data.destinationFloor == 2 then
			TileElevator.sv_sendFadeToBlackEvent( data.portal:getContentsB(), false )
		end
	end

	-- Countdown
	data.ticksToDestination = data.ticksToDestination - 1
	if data.ticksToDestination <= 0 then
		print( "TileElevator: Arrived at floor " .. data.destinationFloor )
		data.currentFloor = data.destinationFloor
		data.ticksToDestination = -1
		self:sv_setIdleDoorState( data )
		save = true
	else
		-- Doors closed while moving
		for i = 1, 2 do
			local floor = data.floors[i]
			if floor and floor.interactable and sm.exists( floor.interactable ) then
				floor.interactable.active = false
			end
		end
	end

	if save then
		self:sv_saveSharedData( data )
	else
		TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, TILE_ELEVATOR_TABLE, self.sv.connectionName, data )
	end
end

function TileElevator.sv_sendFadeToBlackEvent( contents, start )
	if contents == nil then return end
	for _, object in ipairs( contents ) do
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

function TileElevator.sv_updateClientEvents( self )
	if not self.sv.lastActiveState and self.interactable:isActive() then
		self.network:sendToClients( "cl_n_doorOpen" )
	elseif self.sv.lastActiveState and not self.interactable:isActive() then
		self.network:sendToClients( "cl_n_doorClose" )
	end
	self.sv.lastActiveState = self.interactable:isActive()

	if self.sv.prevPower == 0 and self.interactable.power ~= 0 then
		self.network:sendToClients( "cl_n_startMovingSounds" )
	elseif self.sv.prevPower ~= 0 and self.interactable.power == 0 then
		self.network:sendToClients( "cl_n_stopMovingSounds" )
	end
	self.sv.prevPower = self.interactable.power
end

-- Client

function TileElevator.client_onCreate( self )
	self.cl = {}
	self.cl.moveEffect = sm.effect.createEffect( "ElevatorWall", self.interactable )
	self.cl.moveEffectOutside = sm.effect.createEffect( "Elevator - MoveOutside", self.interactable )
	self.cl.musicEffect = sm.effect.createEffect( "ElevatorMusic", self.interactable )
	self.cl.ambienceEffect = sm.effect.createEffect( "ElevatorAmbiance", self.interactable )

	if self.interactable:isActive() then
		self:startElevatorSounds()
	end

	local position = self.shape.worldPosition + self.shape.worldRotation * ELEVATOR_PORTAL_OFFSET
	local size = sm.vec3.new( 1.75, 1.75, 3.0 ) - sm.vec3.new( 0.05, 0.05, 0.05 )
	self.cl.insideArea = sm.areaTrigger.createBox( size, position, self.shape.worldRotation, sm.areaTrigger.filter.character )
	self.cl.insideArea:bindOnEnter( "cl_t_onEnter", self )
	self.cl.insideArea:bindOnExit( "cl_t_onExit", self )
end

function TileElevator.client_onDestroy( self )
	if self.cl.insideArea then
		sm.areaTrigger.destroy( self.cl.insideArea )
	end
end

function TileElevator.cl_t_onEnter( self, trigger, results )
	if not TriggerResultContainsLocalPlayer( results ) then
		return
	end
	self:startElevatorSounds()
	if self.interactable.power ~= 0 then
		if not self.cl.moveEffect:isPlaying() or self.cl.moveEffect:isBreakSustaining() then
			self.cl.moveEffect:start()
		end
		if self.cl.moveEffectOutside:isPlaying() or not self.cl.moveEffectOutside:isBreakSustaining() then
			self.cl.moveEffectOutside:stopImmediate()
		end
	end
end

function TileElevator.cl_t_onExit( self, trigger, results )
	if results == nil then return end
	local localCharacterId = sm.localPlayer.getPlayer().character.id
	for _, result in ipairs( results ) do
		if result.id == localCharacterId then
			AmbienceManager.Cl_SetPauseWorldAmbience( false )
			if not self.interactable:isActive() then
				self:stopElevatorSounds()
				if self.interactable.power ~= 0 then
					if not self.cl.moveEffectOutside:isPlaying() or self.cl.moveEffectOutside:isBreakSustaining() then
						self.cl.moveEffectOutside:start()
					end
					if self.cl.moveEffect:isPlaying() then
						self.cl.moveEffect:stopImmediate()
					end
				end
			end
		end
	end
end

function TileElevator.cl_n_doorOpen( self )
	self:stopMovingSounds()
	self:startElevatorSounds()
	sm.effect.playHostedEffect( "Elevator - Opendoor", self.interactable )
end

function TileElevator.cl_n_doorClose( self )
	sm.effect.playHostedEffect( "Elevator - Closedoor", self.interactable )
	local inside = self.cl.insideArea and TriggerContentsContainsLocalPlayer( self.cl.insideArea:getContents() )
	if inside then
		AmbienceManager.Cl_SetPauseWorldAmbience( true )
	else
		self:stopElevatorSounds()
	end
end

function TileElevator.cl_n_startMovingSounds( self )
	local inside = self.cl.insideArea and TriggerContentsContainsLocalPlayer( self.cl.insideArea:getContents() )
	if inside then
		if self.cl.moveEffect:isBreakSustaining() then
			self.cl.moveEffect:start()
		end
	else
		if self.cl.moveEffectOutside:isBreakSustaining() then
			self.cl.moveEffectOutside:start()
		end
	end
end

function TileElevator.cl_n_stopMovingSounds( self )
	local inside = self.cl.insideArea and TriggerContentsContainsLocalPlayer( self.cl.insideArea:getContents() )
	if not inside then
		AmbienceManager.Cl_SetPauseWorldAmbience( false )
	end
	self:stopMovingSounds()
end

function TileElevator.startElevatorSounds( self )
	if not self.cl.musicEffect:isPlaying() or self.cl.musicEffect:isBreakSustaining() then
		self.cl.musicEffect:start()
	end
	if not self.cl.ambienceEffect:isPlaying() or self.cl.ambienceEffect:isBreakSustaining() then
		self.cl.ambienceEffect:start()
	end
end

function TileElevator.stopElevatorSounds( self )
	if self.cl.musicEffect:isPlaying() or not self.cl.musicEffect:isBreakSustaining() then
		self.cl.musicEffect:stopImmediate()
	end
	if self.cl.ambienceEffect:isPlaying() then
		self.cl.ambienceEffect:stop()
	end
end

function TileElevator.stopMovingSounds( self )
	if not self.cl.moveEffect:isBreakSustaining() then
		self.cl.moveEffect:stopBreakSustain()
	end
	if not self.cl.moveEffectOutside:isBreakSustaining() then
		self.cl.moveEffectOutside:stopBreakSustain()
	end
end

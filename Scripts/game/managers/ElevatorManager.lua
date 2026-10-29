dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

ElevatorManager = class( nil )

local ELEVATOR_TRAVEL_TICKS = 680
local ELEVATOR_MOVEWALLS_TICK = ELEVATOR_TRAVEL_TICKS - 60
local ELEVATOR_LOAD_WORLDS_TICK = ELEVATOR_MOVEWALLS_TICK - 60
local ELEVATOR_TRANSFER_TICK = 120
local ELEVATOR_START_FADE = ELEVATOR_TRANSFER_TICK + 40 -- Sometime before transfer
local ELEVATOR_END_FADE = 40 -- Before doors open
 
local ELEVATOR_FADE_TIMEOUT = ELEVATOR_START_FADE * ( 1.0 / 40.0 ) + 5.0
local ELEVATOR_FADE_DURATION = 0.45

function ElevatorManager.server_onCreate( self )
	g_elevatorManager = self


	-- Game script managed global elevator table
	self.elevators = sm.storage.load( STORAGE_CHANNEL_ELEVATORS )
	if not self.elevators then
		self.elevators = {}
		self:sv_saveElevators()
	end

	self.activeElevators = {}
	self.objectToElevator = {}

	self.loadedCells = {}
	self.loadHandles = {}
end


function ElevatorManager.sv_loadElevatorsOnOverworldCell( self, x, y, cellTags )

	local exits = {}
	local nodes = sm.cell.getNodesByTag( x, y, "ELEVATOR_EXIT_HINT" )
	for i,n in ipairs( nodes ) do
		local vector = n.rotation * ( sm.vec3.new( 0, 1, 0 ) * n.scale )
		local x1, y1 = getCell( n.position.x + vector.x, n.position.y + vector.y )
		exits[i] = { x = x1, y = y1 }
	end

	local setParamsOnElevators = function( tags, exits )
		local elevators = sm.cell.getInteractablesByTags( x, y, tags )
		for _,e in ipairs( elevators ) do
			local maxLevels = 0
			local foundFloorTag = false
			local foundTestTag = false
			for _, tag in ipairs( cellTags ) do
				if CELL_TAG_TO_WAREHOUSE_FLOORS[tag] then
					maxLevels = CELL_TAG_TO_WAREHOUSE_FLOORS[tag]
					foundFloorTag = true
					foundTestTag = tag == "POI_TEST"
					break
				end
			end
			assert( tags[2] ~= "ENTRANCE" or #exits > 0, "Elevator on ("..x..", "..y..") does not have an exit hint" )
			--assert( tags[2] ~= "ENTRANCE" or maxLevels ~= 0, "Elevator is not placed on a warehouse tile" )
			if foundFloorTag == false then
				maxLevels = 4
			end

			local params = {
				name = tags[1].."_"..tags[2],
				x = x,
				y = y,
				exits = exits,
				maxLevels = maxLevels,
				test = foundTestTag,
				cellTags = cellTags
			}
			e:setParams( params )
		end
	end

	local setParamsOnButtons = function( tags, goingUp )
		local buttons = sm.cell.getInteractablesByTags( x, y, tags )
		for _,b in ipairs( buttons ) do
			local params = {
				goingUp = goingUp
			}
			b:setParams( params )
		end
	end

	setParamsOnElevators( { "ELEVATOR", "ENTRANCE" }, exits )
	setParamsOnElevators( { "ELEVATOR", "EXIT" } )
	setParamsOnButtons( { "ELEVATOR_BUTTON", "ENTRANCE" }, true )
	setParamsOnButtons( { "ELEVATOR_BUTTON", "EXIT" }, false )
end

function ElevatorManager.sv_loadElevatorsOnWarehouseCell( self, x, y, warehouseIndex, level )
	local setParamsOnElevators = function( tags )
		local elevators = sm.cell.getInteractablesByTags( x, y, tags )
		for _,e in ipairs( elevators ) do
			local params = {
				name = tags[1].."_"..tags[2],
				warehouseIndex = warehouseIndex,
				level = level
			}
			e:setParams( params )
		end
	end

	local setParamsOnButtons = function( tags, goingUp )
		local buttons = sm.cell.getInteractablesByTags( x, y, tags )
		for _,b in ipairs( buttons ) do
			local params = {
				goingUp = goingUp
			}
			b:setParams( params )
		end
	end

	setParamsOnElevators( { "ELEVATOR", "ENTRANCE" } )
	setParamsOnElevators( { "ELEVATOR", "UP" } )
	setParamsOnElevators( { "ELEVATOR", "DOWN" } )
	setParamsOnElevators( { "ELEVATOR", "EXIT" } )
	
	setParamsOnButtons( { "ELEVATOR_BUTTON", "ENTRANCE" }, false )
	setParamsOnButtons( { "ELEVATOR_BUTTON", "UP" }, true )
	setParamsOnButtons( { "ELEVATOR_BUTTON", "DOWN" }, false )
	setParamsOnButtons( { "ELEVATOR_BUTTON", "EXIT" }, true )
end

function ElevatorManager.sv_saveElevators( self )
	sm.storage.save( STORAGE_CHANNEL_ELEVATORS, self.elevators )

end

local function CellKey( world, x, y )
	return world.id..":("..x..","..y..")"
end

function ElevatorManager.sv_onCellLoaded( self, world, x, y )
	self.loadedCells[CellKey( world, x, y )] = true
end

function ElevatorManager.sv_onCellUnloaded( self, world, x, y )
	self.loadedCells[CellKey( world, x, y )] = nil
end

function ElevatorManager.server_onFixedUpdate( self )
	local save = false
	for _,elevator in pairs( self.activeElevators ) do
		-- Transfer
		if elevator.ticksToDestination == ELEVATOR_TRANSFER_TICK then
			print( "Transfering to", elevator.destination )

			if self:sv_isElevatorReadyForTransfer( elevator ) then
				if elevator.destination == "b" then
					elevator.portal:transferAToB()
				else--if elevator.destination == "a" then
					elevator.portal:transferBToA()
				end
			else
				sm.log.info( "An elevator wants to transfer to '"..elevator.destination.."' but destination is not ready, added 1 second" )
				elevator.ticksToDestination = elevator.ticksToDestination + 40

				if self:sv_needToLoadWorlds( elevator.portal ) then
					self:sv_loadPortalWorlds( elevator.portal )
				end

				self:sv_prepareCells( elevator.portal )
			end
			save = true
		end

		-- Open doors
		if elevator.ticksToDestination == 0 then
			if elevator.a and sm.exists( elevator.a ) then
				elevator.a.active = elevator.destination == "a"
				elevator.a:setPower( 0 )
			end
			if elevator.b and sm.exists( elevator.b ) then
				elevator.b.active = elevator.destination == "b"
				elevator.b:setPower( 0 )
			end
		elseif elevator.ticksToDestination > 0 then -- Elevator is moving

			-- Countdown
			elevator.ticksToDestination = elevator.ticksToDestination - 1
			if elevator.ticksToDestination == 0 then
				save = true
				self:sv_arrived( elevator )
			end

			-- Close doors
			if elevator.a and sm.exists( elevator.a ) then
				elevator.a.active = false
				if elevator.ticksToDestination == ELEVATOR_MOVEWALLS_TICK then
					elevator.a:setPower( elevator.destination == "a" and -1 or 1 )
				end
			end
			if elevator.b and sm.exists( elevator.b ) then
				elevator.b.active = false
				if elevator.ticksToDestination == ELEVATOR_MOVEWALLS_TICK then
					elevator.b:setPower( elevator.destination == "b" and 1 or -1 )
				end
			end

			-- Start Fade
			if elevator.ticksToDestination == ELEVATOR_START_FADE then
				if elevator.destination == "b" then
					if elevator.portal:getWorldB() then
						self:sv_sendFadeToBlackEvent( elevator.portal:getContentsA(), true )
					end
				end
				if elevator.destination == "a" then
					if elevator.portal:getWorldA() then
						self:sv_sendFadeToBlackEvent( elevator.portal:getContentsB(), true )
					end
				end
			end

			if elevator.ticksToDestination == ELEVATOR_LOAD_WORLDS_TICK then
				self:sv_loadPortalWorlds( elevator.portal )
			end

			-- Transfer
			if elevator.ticksToDestination < ELEVATOR_LOAD_WORLDS_TICK and
			   elevator.ticksToDestination > ELEVATOR_TRANSFER_TICK
			then
				-- Prepare for transfer
				self:sv_prepareCells( elevator.portal )
			end

			-- End Fade
			if elevator.ticksToDestination == ELEVATOR_END_FADE then
				if elevator.destination == "a" then
					if elevator.portal:getWorldB() then
						self:sv_sendFadeToBlackEvent( elevator.portal:getContentsA(), false )
					end
				end
				if elevator.destination == "b" then
					if elevator.portal:getWorldA() then
						self:sv_sendFadeToBlackEvent( elevator.portal:getContentsB(), false )
					end
				end
			end
		end
	end
	if save then
		self:sv_saveElevators()
	end
end

function ElevatorManager.sv_loadBForPlayersInElevator( self, portalId, world, x, y )
	if self.loadHandles[portalId] == nil then
		self.loadHandles[portalId] = {}
	end

	if self.loadHandles[portalId].b == nil then
		printf( "Loading cell %s:(%s,%s) (ElevatorManager.sv_loadBForPlayersInElevator)", world.id, x, y )

		self.loadHandles[portalId].b = {}
		for cellX = x - 1, x + 1, 1 do
			for cellY = y - 1, y + 1, 1 do
				if world:isCellInBounds( cellX, cellY ) then
					table.insert( self.loadHandles[portalId].b, world:loadCellWithHandle( cellX, cellY, nil ) )
				end
			end
		end
	end
end

function ElevatorManager.sv_sendFadeToBlackEvent( self, contents, start )
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

function ElevatorManager.sv_prepareCells( self, portal )
	if self.loadHandles[portal.id] == nil then
		self.loadHandles[portal.id] = {}
	end

	local function loadCells( world, position )
		local x = math.floor( position.x / 64 )
		local y = math.floor( position.y / 64 )
		printf( "Loading cell %s:(%s,%s) (ElevatorManager.sv_prepareCells)", world.id, x, y )

		local handles = {}
		for cellX = x-1, x+1, 1 do
			for cellY = y-1, y+1, 1 do
				if world:isCellInBounds( cellX, cellY ) then
					table.insert( handles, world:loadCellWithHandle( cellX, cellY, nil ) )
				end
			end
		end
		return handles
	end

	if self.loadHandles[portal.id].a == nil then
		if sm.exists( portal:getWorldA() ) then
			self.loadHandles[portal.id].a = loadCells( portal:getWorldA(), portal:getPositionA() )
		end
	end

	if self.loadHandles[portal.id].b == nil then
		if sm.exists( portal:getWorldB() ) then
			self.loadHandles[portal.id].b = loadCells( portal:getWorldB(), portal:getPositionB() )
		end
	end
end

-- Shape context

function ElevatorManager.sv_registerElevator( self, interactable, portal )
	local elevator = self.elevators[portal.id]
	if elevator then
		-- Exists, check if A (load) otherwise, set as B
		assert( elevator.a )
		if elevator.a ~= interactable then
			assert( elevator.b == nil or elevator.b == interactable )
			elevator.b = interactable
		end
	else
		-- Does not exist, create and set as A
		elevator = {}
		elevator.portal = portal
		elevator.destination = "b"
		elevator.ticksToDestination = 0 -- At destination
		elevator.a = interactable
		self.elevators[portal.id] = elevator
	end

	self:sv_saveElevators()
	addToArrayIfNotExists( self.activeElevators, elevator )
	self.objectToElevator[interactable.id] = elevator
end


function ElevatorManager.sv_removeElevator( self, interactable )
	local elevator = self.objectToElevator[interactable.id]
	if elevator == nil then
		return
	end

	self.objectToElevator[interactable.id] = nil
	local remove = true
	for _,e in pairs( self.objectToElevator ) do
		if e == elevator then
			remove = false
			break
		end
	end
	if remove then
		removeFromArray( self.activeElevators, function( value ) return value == elevator end )
	end
end

function ElevatorManager.sv_getElevatorDestination( self, interactable )
	local elevator = self.objectToElevator[interactable.id]
	assert( elevator, "Attempt to get an non existing elevator for interactable"..interactable.id )

	return elevator.destination, elevator.ticksToDestination
end

function ElevatorManager.sv_getElevatorHome( self, interactable )
	local elevator = self.objectToElevator[interactable.id]
	assert( elevator, "Attempt to get an non existing elevator for interactable"..interactable.id )

	if interactable == elevator.b then
		return "b"
	end
	return "a"
end

function ElevatorManager.sv_call( self, interactable )
	local elevator = self.objectToElevator[interactable.id]
	assert( elevator )

	if elevator.ticksToDestination == 0 then -- Not on the move
		print( "Elevator CALL!" )
		if elevator.destination == "b" and interactable == elevator.a then
			elevator.destination = "a"
			elevator.ticksToDestination = ELEVATOR_TRAVEL_TICKS
		elseif elevator.destination == "a" and interactable == elevator.b then
			elevator.destination = "b"
			elevator.ticksToDestination = ELEVATOR_TRAVEL_TICKS
		end
	end
end


function ElevatorManager.sv_go( self, interactable )
	print( "Elevator GO!" )
	local elevator = self.objectToElevator[interactable.id]
	assert( elevator )

	if elevator.ticksToDestination == 0 then -- Not on the move
		if elevator.destination == "a" and interactable == elevator.a then
			-- A to B
			elevator.destination = "b"
			elevator.ticksToDestination = ELEVATOR_TRAVEL_TICKS

		elseif elevator.destination == "b" and interactable == elevator.b then
			-- B to A
			elevator.destination = "a"
			elevator.ticksToDestination = ELEVATOR_TRAVEL_TICKS
		elseif interactable == elevator.a then
			elevator.destination = "b"
			elevator.ticksToDestination = ELEVATOR_TRANSFER_TICK + 40
			elevator.a:setPower( 1 )
			print("Elevator pressed at wrong location, AtoB")
		elseif interactable == elevator.b then
			elevator.destination = "a"
			elevator.ticksToDestination = ELEVATOR_TRANSFER_TICK + 40
			elevator.b:setPower( -1 )
			print("Elevator pressed at wrong location, BtoA")
		end
	end
end

function ElevatorManager.sv_arrived( self, elevator )
	print( "ElevatorManager.sv_arrived" )
	local handles = self.loadHandles[elevator.portal.id]
	if handles then
		if handles.a then
			for _, handle in ipairs(handles.a) do
				handle:release()
			end
			handles.a = nil
		end
		if handles.b then
			for _, handle in ipairs(handles.b) do
				handle:release()
			end
			handles.b = nil
		end
		self.loadHandles[elevator.portal.id] = nil
	end
end


function ElevatorManager.sv_isElevatorReadyForTransfer( self, elevator )
	local function worldReady ( world, position )
		local x = math.floor( position.x / 64 )
		local y = math.floor( position.y / 64 )
		if world then
			if sm.exists( world ) then
				if self.loadedCells[CellKey( world, x, y )] then
					return true
				end
			end
		end
		return false
	end
	local portal = elevator.portal
	local aReady = worldReady( portal:getWorldA(), portal:getPositionA() )
	local bReady = worldReady( portal:getWorldB(), portal:getPositionB() )
	
	if elevator.destination == "a" then
		return aReady
	else
		return bReady
	end
end

function ElevatorManager.sv_needToLoadWorlds( self, portal )
	local needA = portal:getWorldA() and not sm.exists( portal:getWorldA() )
	local needB = portal:getWorldB() and not sm.exists( portal:getWorldB() )

	return needA or needB
end

function ElevatorManager.sv_loadPortalWorlds( self, portal )
	if portal:getWorldA() and not sm.exists( portal:getWorldA() ) then
		sm.world.loadWorld( portal:getWorldA() )
	end

	if portal:getWorldB() and not sm.exists( portal:getWorldB() ) then
		sm.world.loadWorld( portal:getWorldB() )
	end
end

function ElevatorManager.Sv_CreateElevatorDestination( params )
	if g_elevatorManager then
		sm.event.sendToScriptableObject( g_elevatorManager.scriptableObject, "sv_e_createElevatorDestination", params, sm.event.types.instant )
	end
end

function ElevatorManager.sv_e_createElevatorDestination( self, params )
	-- Warehouse get or create
	local warehouse
	if params.warehouseIndex then
		warehouse = WarehouseManager.Sv_GetWarehouseFromIndex( params.warehouseIndex )
	else
		assert( params.name == "ELEVATOR_ENTRANCE" )
		warehouse = WarehouseManager.Sv_CreateWarehouse( {
			world = params.portal:getWorldA(),
			position = params.position,
			maxLevels = params.maxLevels,
			exits = params.exits,
			cellTags = params.cellTags,
			test = params.test,
		} )
	end

	-- Level up
	local level
	if params.level then
		if params.name == "ELEVATOR_UP" then
			level = params.level + 1
		elseif params.name == "ELEVATOR_DOWN" then
			level = params.level - 1
		elseif params.name == "ELEVATOR_EXIT" then
			if #warehouse.exits > 0 then
				for _,cell in ipairs( warehouse.exits ) do
					if not sm.exists( warehouse.world ) then
						sm.world.loadWorld( warehouse.world )
					end
					local name = params.name.." "..cell.x..","..cell.y
					sm.portal.addWorldPortalHook( warehouse.world, name, params.portal )
					ElevatorManager.Sv_LoadBForPlayersInElevator( params.portal.id, warehouse.world, cell.x, cell.y )
				end
			else
				sm.log.error( "No exit hint found, this elevator is going nowhere!" )
			end
			return
		else
			assert( false )
		end
	else
		if params.name == "ELEVATOR_EXIT" then
			level = warehouse.maxLevels
		elseif params.name == "ELEVATOR_ENTRANCE" then
			level = 1
		else
		end
	end

	-- Create warehouse world
	local worldData = {}
	worldData.level = level
	worldData.isQuestWarehouse = warehouse.isQuestWarehouse
	worldData.warehouseIndex = warehouse.index
	worldData.maxLevels = warehouse.maxLevels



	local world = sm.world.createWorld( "$SURVIVAL_DATA/Scripts/game/worlds/WarehouseWorld.lua", "WarehouseWorld", worldData, math.random( 1073741823 ) )
	warehouse.worlds[#warehouse.worlds+1] = world
	WarehouseManager.Sv_SaveAndSynch()

	-- Elevator portal hook
	local name
	if params.name == "ELEVATOR_UP" then
		name = "ELEVATOR_DOWN"
	elseif params.name == "ELEVATOR_DOWN" then
		name = "ELEVATOR_UP"
	else
		name = params.name
	end
	sm.portal.addWorldPortalHook( world, name, params.portal )
	ElevatorManager.Sv_LoadBForPlayersInElevator( params.portal.id, world, 0, 0 )
end

function ElevatorManager.Sv_OnCellLoaded( world, x, y )
	if g_elevatorManager then
		g_elevatorManager:sv_onCellLoaded( world, x, y )
	end
end

function ElevatorManager.Sv_OnCellUnloaded( world, x, y )
	if g_elevatorManager then
		g_elevatorManager:sv_onCellUnloaded( world, x, y )
	end
end

function ElevatorManager.Sv_Go( object )
	if g_elevatorManager then
		g_elevatorManager:sv_go( object )
	end
end

function ElevatorManager.Sv_Call( object )
	if g_elevatorManager then
		g_elevatorManager:sv_call( object )
	end
end

function ElevatorManager.Sv_RegisterElevator( object, portal )
	if g_elevatorManager then
		g_elevatorManager:sv_registerElevator( object, portal )
	end
end

function ElevatorManager.Sv_RemoveElevator( object )
	if g_elevatorManager then
		g_elevatorManager:sv_removeElevator( object )
	end
end

function ElevatorManager.Sv_GetElevatorHome( object )
	if g_elevatorManager then
		return g_elevatorManager:sv_getElevatorHome( object )
	end
end

function ElevatorManager.Sv_GetElevatorDestination( object )
	if g_elevatorManager then
		return g_elevatorManager:sv_getElevatorDestination( object )
	end
end

function ElevatorManager.Sv_LoadBForPlayersInElevator( portalId, world, x, y )
	if g_elevatorManager then
		g_elevatorManager:sv_loadBForPlayersInElevator( portalId, world, x, y )
	end
end

function ElevatorManager.Sv_LoadElevatorsOnOverworldCell( x, y, cellTags )
	if g_elevatorManager then
		g_elevatorManager:sv_loadElevatorsOnOverworldCell( x, y, cellTags )
	end
end

function ElevatorManager.Sv_LoadElevatorsOnWarehouseCell( x, y, warehouseIndex, level )
	if g_elevatorManager then
		g_elevatorManager:sv_loadElevatorsOnWarehouseCell( x, y, warehouseIndex, level )
	end
end

